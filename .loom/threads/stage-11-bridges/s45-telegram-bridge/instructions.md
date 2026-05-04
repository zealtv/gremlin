# s45-telegram-bridge

Second bridge. Slots into the `bridges/<name>/` convention established by s44. A Telegram bot becomes a remote channel: messages sent to the bot land in `.nest/in/`; assistant turns from `transcript.md` get pushed back to the chat.

## Layout

```
bridges/
  telegram/
    telegram.sh       # entry point; long-running daemon
    .cursor           # last pushed transcript turn
    .update-offset    # last seen telegram update_id (inbound polling)
    config            # bot token, chat id (gitignored; .example committed)
    config.example
    README.md
```

## Configuration

- `bridges/telegram/config` is a small env-file:

  ```bash
  TELEGRAM_BOT_TOKEN="..."
  TELEGRAM_CHAT_ID="..."     # the single chat this bridge talks to
  ```

- `config.example` ships in the canonical with placeholders. `config` is `.gitignore`d.
- Single-chat for this stitch. Multi-chat is out of scope; revisit if it becomes a real need.

## Inbound (Telegram → gremlin)

- Long-poll the Telegram Bot API: `GET https://api.telegram.org/bot<token>/getUpdates?offset=<next>&timeout=30`.
- For each update from the configured chat:
  - Extract message text.
  - Write to `.nest/in/<iso>.md` (same path the TUI and `say` use).
  - **Do not** append to `transcript.md` — the tender owns transcript writes (per stage-11 goal). The user's own message is already visible in their Telegram chat, so no per-bridge processing affordance is needed; the next assistant turn the bridge pushes is the visible reply.
  - Persist the update's `update_id + 1` to `.update-offset` so we don't reprocess.
- Ignore non-text updates (photos, stickers) for this stitch. Log a one-liner, don't crash.

Polling is simpler than webhooks (no public URL needed). Keep it.

## Outbound (transcript → Telegram)

- Tail `transcript.md`. For each new `## assistant — <iso>` turn past the cursor:
  - `POST https://api.telegram.org/bot<token>/sendMessage` with `chat_id` and `text` (turn body).
  - On success, advance `.cursor` to that turn's iso.
  - On failure (network, rate limit), retry with backoff; do not advance the cursor until success.
- Cursor format: iso timestamp (matches s44).

## Cursor / restart semantics

- Same convention as s44: `bridges/telegram/.cursor` records the last successfully pushed turn.
- On startup: read cursor, push everything after it, advance as we go. A restart mid-conversation does not duplicate.
- Missing cursor on first launch: do **not** push the entire transcript history to Telegram. Initialise the cursor to "now" and only push turns from this point forward. (Different default than the TUI, because pushing 500 historical turns to a chat is noisy and possibly rate-limited.)

## Filtering

- Push only `## assistant —` turns. Skip `## user —` (the user already sent it from somewhere).
- No per-message routing. Every assistant turn pushes. Per the goal stitch: "all bridges always fire."

## Out of scope

- Multi-chat / multi-user support.
- Inline keyboards, commands, formatting beyond plain text.
- Webhook mode.
- Media (images, voice notes). Defer to a later stitch — the gremlin's nest already supports attachment directories, but wiring Telegram media into that is its own piece of work.
- Authentication beyond "this single chat id is allowed." Anything else from another chat is dropped silently.

## Dependencies

- **s43** must land first. Without transcript-as-single-surface, the bridge contract doesn't hold.
- **s44** establishes the `bridges/<name>/` folder convention and cursor file pattern. s45 follows that pattern; if s45 lands first it has to invent it instead, so prefer s44 first.

## Verify

1. `run.sh` running. TUI bridge running. Telegram bridge running with valid config pointing at a test chat.
2. Send "hi" from Telegram. Within seconds, both the TUI and the Telegram chat show the assistant's reply. `transcript.md` has the `## user` and `## assistant` turns.
3. Type "remind me in one minute to test" in the TUI. The reminder fires. Both the TUI **and** the Telegram chat receive the proactive message.
4. Restart the Telegram bridge. Nothing re-pushes; cursor honoured.
5. Restart the runner with the bridge still up. Bridge survives, picks up cleanly when transcript resumes appending.
6. Send "hi" from Telegram while the runner is paused (`.paused` flag). Message lands in `.nest/in/`. When unpaused, it processes; reply pushes to Telegram.

## Notes

The bot token is sensitive. The stitch must:
- Add `bridges/*/config` to the **canonical** `.gitignore` (the personal copy isn't a tracked repo, but contributors working on canonical must not accidentally commit a config).
- Document in the bridge's README that `config` should never be committed.
- Mention rotation: if the token leaks, regenerate via @BotFather and replace.
