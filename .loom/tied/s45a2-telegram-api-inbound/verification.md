# verification

- `bash -n .gremlin/bridges/telegram/telegram.sh` passed after inbound polling changes.
- Inbound uses `curl` for Telegram API requests and `jq` for JSON parsing.
- A mock `getUpdates` response was exercised with fake local config only:
  - configured chat text update was ingested through `.nest/nestling.sh ingest`
  - wrong-chat update was ignored
  - non-text configured-chat update was ignored
  - `.update-offset` advanced from no file to `103`
- Temporary fake config, mock response, update-offset, and generated `.nest/in/*telegram-*.md` item were removed after the check.

No real Telegram token or chat id was used for this stitch.

## docs findings

- The bridge has runtime dependencies on `curl` and `jq`.
- The real setup docs should mention that wrong `TELEGRAM_CHAT_ID` presents as ignored updates, not a bot-token failure.
