# verification

- `bash -n .gremlin/bridges/telegram/telegram.sh` passed after outbound cursor changes.
- A mock transcript was checked through `TELEGRAM_TRANSCRIPT=/private/tmp/telegram-transcript.md`.
- A mock send log was checked through `TELEGRAM_TEST_SEND_LOG=/private/tmp/telegram-send.log`.
- Missing `.cursor` initialized to the current transcript byte size and did not push old history.
- A new assistant turn after the cursor was pushed once to the mock send log.
- `.cursor` advanced from `88` to `177` after the successful push.
- A simulated send failure via `TELEGRAM_TEST_SEND_FAIL=1` returned non-zero and left `.cursor` unchanged at `177`.
- Temporary fake config, cursor, transcript, and send log were removed after the check.

No real Telegram token or chat id was used for this stitch.

## implementation note

The current cursor advancement is batch-based: all assistant turns in the unread chunk must send successfully before the cursor advances to the current transcript size. If a later send fails after an earlier send in the same batch succeeds, the earlier turn may be retried on the next pass. Real staged verification should watch for duplicates under network/API failures.
