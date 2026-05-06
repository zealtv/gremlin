# s03-telegram-shortcircuit

Make `/`-prefixed Telegram messages run through `bin/slash.sh` instead of
landing in `.nest/in/`.

## Files

- `.gremlin/bridges/telegram/telegram.sh` — in `handle_update` (line 246),
  after the chat_id and non-empty-text guards, add a branch:

  ```
  if [ "${text#/}" != "$text" ]; then
    output="$("$GREMLIN_DIR/bin/slash.sh" "$text" 2>&1)" || true
    [ -n "$output" ] || output="(no output)"
    send_message "$output" || echo "telegram: failed to send slash reply" >&2
    write_update_offset "$next_offset"
    return 0
  fi
  ```

  Then fall through to `ingest_text` as today.

## Notes

- Slash output bypasses the transcript entirely — Telegram is the only
  bridge that sees it. That matches TUI ephemerality.
- Telegram caps message text at 4096 chars. `/help` is well under. Defer a
  truncation guard until something actually overflows.
- README updates can wait until the whole thread ties off.

## Done when

- Bridge running. From the configured chat:
  - `/help` → help text arrives as a Telegram message; nothing appended to
    `transcript.md`; nothing in `.nest/in/` or `.nest/out/`.
  - `/nope` → `unknown command: /nope\ntry /help`.
  - `hello` → still ingested, model replies, reply pushes back.
- Messages from any other chat still ignored (chat_id guard runs first).
