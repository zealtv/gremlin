# telegram-render

**Outcome.** The Telegram bridge handles `## system —` transcript turns without crashing, eating, or misattributing them.

## Decision needed

Should Telegram **send** system turns to the user, or filter them out?

- **Send** (recommended): user gets `⚙️ run: item aborted` confirmation when they `/stop`, and sees scheduled-script output. Costs them a notification; gains them visibility.
- **Filter**: keep Telegram conversation-only. User has no idea their `/stop` actually fired.

Default to send. Note any strong reason to filter in this stitch's notes before tying.

## Touchpoints

- `bridges/telegram/telegram.sh` — outbound transcript watcher.
  - `extract_assistant_turns` (around line 173) currently emits only `assistant`. Generalise: emit `assistant` *and* `system`, still skip `user`.
  - `push_transcript_once` (around line 199) consumes that stream — no shape change needed if we keep the emit format.

## Steps

1. Rename / generalise `extract_assistant_turns` to extract both `assistant` and `system` turns. Awk role regex needs `^## (assistant|system)[[:space:]]`.
2. Send each extracted turn body via `sendMessage` as today. The emoji+label in the body is the visual cue; no extra formatting required.
3. Confirm Telegram doesn't barf on a leading emoji (it doesn't — UTF-8 in `text` is fine, including 4-byte glyphs like 💌).

## Sub-categories that will arrive

Per `docs/protocol.md`, every `## system —` body starts with an emoji+label:

- `⚙️ run:` — script ran / item aborted (lands when `/stop` exists, and from `groundhog-run-scripts`).
- `⚠️ error:` — runtime failure surfaced.
- `💌 message:` — scheduled `message.md` body emitted by the tender. **Currently the only system sub-type emitted in the wild** (by `bin/tick-loop.sh`), so it's the live verification case.

The bridge does not interpret sub-types. Body goes through verbatim.

## Verify

- Append a `## system — <iso>\n⚙️ run: hello\n\n` block to transcript while the bridge is running; chat receives `⚙️ run: hello` verbatim.
- Schedule a `once/<near-date>/<HH-MM>/<slug>/message.md` groundhog item; let it fire; chat receives `💌 message: <body>` verbatim. (The live case.)
- `## user —` turns are still skipped (don't echo the user's own message back at them).
- Restart the bridge after firing — `.cursor` past the system turn means it's not re-sent.
- Old transcripts (no system turns) replay unchanged.

## Consistency / staleness

- `bridges/telegram/README.md` if it documents which turn types get forwarded.
- Sibling: `tui-render` decision should match in spirit (both surface system turns).

Waits on `format-and-docs` only nominally.
