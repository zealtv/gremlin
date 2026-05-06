# s45a-telegram-bridge-implementation

Build the Telegram bridge feature in canonical `.gremlin/` without using real credentials.

## Outcome

Canonical gremlin has a `bridges/telegram/` bridge that can be started through the existing `gremlin <bridge> <verb>` dispatch shape, reads config from an ignored local env file, polls Telegram inbound messages, and pushes assistant transcript turns outbound using a persisted byte-offset cursor.

## Scope

- Add `.gremlin/bridges/telegram/telegram.sh`.
- Add `.gremlin/bridges/telegram/config.example`.
- Add `.gremlin/bridges/telegram/README.md` as a starter doc scaffold only; final setup and troubleshooting details belong to `s45e-docs-from-verification`.
- Add the needed `.gitignore` rules for bridge secrets and runtime cursor/update-offset files.
- Wire `./.gremlin/gremlin telegram start|stop|status|restart` if the wrapper needs bridge dispatch support beyond what s44c already provides.
- Keep secrets out of the repo. Do not create or commit a real `config`.

## Notes

- Plain text only. Ignore non-text Telegram updates with a concise log line.
- Single chat only. Drop updates from other chats.
- Missing `.cursor` on first launch should initialize to the current end of `transcript.md`, not replay history.
- Network/API behavior can be manually exercised later in `~/Desktop/mygremlin`; this stitch should cover static checks and any local no-secret checks that are possible.

## Verify

1. `git status --short` shows only intended canonical and loom files.
2. `./.gremlin/gremlin telegram status` exits cleanly and reports an unconfigured or stopped state without leaking secrets.
3. `./.gremlin/bridges/telegram/telegram.sh --help` or equivalent usage output is available.
4. Shell syntax checks pass for new/changed shell scripts.
5. No real token, chat id, cursor, or update offset file is tracked.

Record implementation notes or caveats in this stitch before tying it.
