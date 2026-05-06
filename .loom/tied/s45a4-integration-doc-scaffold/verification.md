# verification

- `bash -n .gremlin/bridges/telegram/telegram.sh` passed.
- `./.gremlin/gremlin help` lists `telegram` under bridges.
- `./.gremlin/gremlin telegram status` reports `telegram bridge stopped (unconfigured)` without printing secrets.
- `.gremlin/bridges/telegram/` contains only canonical files:
  - `telegram.sh`
  - `config.example`
  - `README.md`
- `.gitignore` now excludes bridge `config`, pid, log, cursor, and update-offset runtime files.

No real Telegram token or chat id was used for this stitch.
