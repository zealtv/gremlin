# s45a1-daemon-service-shape

Create the Telegram bridge script's local daemon/service shape without real Telegram API behavior yet.

## Outcome

`.gremlin/bridges/telegram/telegram.sh` exists, is executable, and supports `start`, `stop`, `status`, `restart`, `run`, and `help` in the same spirit as the `gremlin` wrapper. The script has stable paths for config, log, pid, cursor, and update offset, and fails clearly when config is missing.

## Scope

- Add `.gremlin/bridges/telegram/telegram.sh`.
- Establish bridge-local runtime files:
  - `telegram.log`
  - `telegram.pid`
  - `.cursor`
  - `.update-offset`
  - `config`
- `start` backgrounds `run`, writes logs, and avoids duplicate daemon starts.
- `stop` terminates the recorded process if present.
- `status` reports configured/unconfigured and running/stopped without printing secrets.
- `run` loads config and enters a placeholder loop or exits with a clear not-yet-implemented message until later children fill it in.
- Do not make network calls in this stitch.

## Verify

1. `bash -n .gremlin/bridges/telegram/telegram.sh` passes.
2. `./.gremlin/gremlin telegram help` works through wrapper dispatch.
3. `./.gremlin/gremlin telegram status` works without config and does not leak secrets.
4. Starting without config fails clearly and does not leave a stale pid.
