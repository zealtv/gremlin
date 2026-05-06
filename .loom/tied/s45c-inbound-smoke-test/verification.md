# verification

- Test message sent from Telegram mobile: `s45c inbound smoke test`.
- User observed inbound message appear in the TUI/transcript.
- User observed one assistant reply in the TUI after roughly 3-5 seconds.
- User observed one assistant reply in Telegram roughly 10 seconds after the TUI reply.
- Transcript contains matching turns:
  - `## user - 2026-05-06T04:30:18Z`
  - `## assistant - 2026-05-06T04:30:25Z`
- The bridge log recorded ingestion and outbound push, but did not write user turns directly; transcript turns appeared after the queued item was tended.
- Bridge log shows the smoke-test Telegram update was ingested.
- Bridge log shows outbound push through transcript byte `1862`.
- Telegram inbox was empty after tending.
- User sent a GIF and a voice message. Neither arrived in `.nest/in/`.
- Bridge log shows the GIF and voice updates were ignored as non-text messages.
- User then sent a follow-up text message. Bridge log shows that update was ingested and outbound push advanced.
- Inbound and outbound were still alive after the non-text updates.
- Wrong-chat behavior was checked with a mock `getUpdates` response because the user did not have a second Telegram account/chat available.
- The mock update used a deliberately non-matching `chat.id` and text `wrong chat smoke test`.
- The bridge reported that the mock update was ignored because the chat was not configured.
- No `.nest/in/` item was created for the mock update.
- The local `.update-offset` was restored to the prior real value after the mock check.

## findings for later docs

- In local testing, the TUI can show the assistant reply several seconds before Telegram receives the outbound push. For this run: TUI reply took about 3-5 seconds; Telegram delivery followed about 10 seconds later.
- The reply appeared once in Telegram for the normal text message.
- GIF and voice messages are ignored as non-text updates. The daemon continues polling afterward.
- Wrong-chat behavior can be verified without a second account by using the bridge's `TELEGRAM_TEST_UPDATES_FILE` hook, but docs should make clear this is a test hook and should not be part of normal setup.
