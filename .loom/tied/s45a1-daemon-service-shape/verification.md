# verification

- `bash -n .gremlin/bridges/telegram/telegram.sh` passed.
- `./.gremlin/gremlin telegram help` dispatches through the wrapper and prints bridge usage.
- `./.gremlin/gremlin telegram status` works without config and reports `telegram bridge stopped (unconfigured)`.
- `./.gremlin/gremlin telegram start` without config fails clearly with the missing config path.
- Missing-config start leaves no `telegram.pid` behind.

No real Telegram token or chat id was used for this stitch.
