# s45a2-telegram-api-inbound

Implement Telegram polling and inbound message ingestion.

## Outcome

The bridge can long-poll Telegram `getUpdates`, filter to the configured chat, write text messages into `.nest/in/` via the nestling protocol, and persist `.update-offset`.

## Scope

- Read `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` from bridge `config`.
- Use `curl` for Telegram API calls.
- Parse JSON with a dependable local tool if available; otherwise keep parsing narrowly scoped and documented.
- Poll `getUpdates` with `offset=<next>` and `timeout=30`.
- Accept text messages only.
- Ignore other chats and non-text messages without crashing.
- Ingest accepted text through `.gremlin/.nest/nestling.sh ingest`.
- Persist `update_id + 1` only after the accepted/ignored update has been handled.

## Verify

1. `bash -n` passes.
2. Missing `curl` or malformed config fails clearly.
3. Polling loop can be dry-run or unit-checked without real secrets where practical.
4. Real-bot behavior is left for `s45c-inbound-smoke-test`.
