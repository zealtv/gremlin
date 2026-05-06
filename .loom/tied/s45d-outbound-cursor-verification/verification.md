# verification

## findings during cursor/restart testing

- Missing `.cursor` test exposed a startup issue: the bridge started with no cursor, then entered Telegram long-polling before running outbound cursor initialization. With a quiet bot, `.cursor` did not appear within 3 seconds.
- Canonical fix: `cmd_run` now calls `ensure_cursor` immediately after startup logging, before entering the poll/push loop.
- Retest after sync/fix:
  - user removed `.cursor`
  - `wc -c .gremlin/transcript.md` reported `2018`
  - bridge start created `.cursor` within 1 second
  - `.cursor` contained `2018`
  - log showed daemon startup only, with no old transcript push
- New outbound turn after startup succeeded:
  - user reported success for `s45d new outbound turn test`
  - Telegram received one assistant reply
  - bridge log shows outbound push through transcript byte `2163`
  - `.cursor` and `wc -c .gremlin/transcript.md` both read `2163`
- Telegram bridge restart did not duplicate the prior outbound turn:
  - `./.gremlin/gremlin telegram restart` stopped and restarted cleanly
  - `.cursor` remained `2163`
  - log showed daemon startup after restart with no new push line
- Runner restart while Telegram bridge stayed up succeeded:
  - user reported the restart test looked good
  - transcript contains `s45d runner restart test`
  - bridge log shows the inbound text was ingested with privacy-safe filename `20260506T053251Z-telegram-HHJoYx.md`
  - bridge log shows outbound push through transcript byte `2308`
  - `.cursor` and `wc -c .gremlin/transcript.md` both read `2308`
- Proactive reminder test exposed a scheduling path bug:
  - `remind-me.md` told the tender to write `.groundhog/...` from the host working directory
  - `tick-loop.sh` correctly reads `.gremlin/.groundhog`
  - reminders were created under host-root `.groundhog`, where the runner never ticks
  - canonical fix: `remind-me.md` now instructs use of `./.gremlin/tools/now.sh` and `.gremlin/.groundhog/schedule/...`
  - canonical docs fix: root README checklist now names `.gremlin/.groundhog/out` and `.gremlin/.groundhog/fired`
- Proactive reminder retest after sync/restart succeeded:
  - user requested a fresh reminder after syncing the fixed skill
  - reminder landed under `.gremlin/.groundhog`
  - fired marker appeared under `.gremlin/.groundhog/fired/2026-05-06/once/2026-05-06/15-41/confirm-telegram-proactive`
  - transcript contains assistant reminder turn at `2026-05-06T05:41:00Z`
  - user observed the reminder in TUI first, then shortly after in Telegram
  - bridge log shows outbound push through transcript byte `3043`
- Paused-runner behavior succeeded:
  - user created `.gremlin/.paused`
  - user sent `s45d paused runner test` from Telegram
  - no assistant reply was sent while paused
  - after removing `.gremlin/.paused`, the queued inbound message was tended
  - TUI/transcript showed the turn and assistant reply
  - Telegram received exactly one reply
- Telegram bridge stop exposed a timeout mismatch: `stop` waited 5 seconds, but `getUpdates` long-polls for up to 30 seconds. The command could report `sent stop signal...` even though status immediately afterward showed stopped.
- Canonical fix: `STOP_TIMEOUT` now defaults to 35 seconds and can be overridden with `TELEGRAM_STOP_TIMEOUT`.

## docs findings

- Bridge stop may take up to the long-poll timeout. Docs should describe this as normal, not as a hang.
- Reminder docs/tests should explicitly verify that scheduled reminders land under `.gremlin/.groundhog`, not host-root `.groundhog`.
