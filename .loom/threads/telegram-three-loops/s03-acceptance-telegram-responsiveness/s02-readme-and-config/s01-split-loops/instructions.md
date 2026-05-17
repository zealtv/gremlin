# s01-split-loops

Refactor `bridges/telegram/telegram.sh` so `cmd_run` becomes a supervisor of
three independent background loops.

## What to build

Three loop functions, each a `while :; do … done` body:

- `inbound_loop` — calls `poll_once`; on failure, log and `sleep POLL_SLEEP`
  before retrying. No extra sleep on success: `getUpdates` already long-polls
  for up to `POLL_TIMEOUT`.
- `outbound_loop` — calls `push_transcript_once`; on failure, log and
  `sleep OUTBOUND_BACKOFF`. On success, `sleep TELEGRAM_PUSH_INTERVAL`
  (default `1`).
- `pulser_loop` — every `TELEGRAM_PULSE_INTERVAL` seconds (default `4`):
  if `compgen -G "$GREMLIN_DIR/.nest/in/*-telegram-*.md*" >/dev/null`,
  POST `sendChatAction` with `action=typing` and `chat_id=$TELEGRAM_CHAT_ID`.
  Glob covers both pending (`*.md`) and claimed (`*.md.tending`).

`cmd_run`:

- Keep the existing config/runtime/cursor setup and the startup log lines.
- Add `TELEGRAM_PUSH_INTERVAL` and `TELEGRAM_PULSE_INTERVAL` to the env-var
  defaults block at the top of the file.
- Fork all three loops in the background, capture their PIDs.
- `trap 'kill <pids> 2>/dev/null; wait; exit 0' INT TERM` so children die with
  the supervisor.
- `wait` on the children. If any exits non-zero unexpectedly, log and exit so
  the parent's PID file matches reality.

## Helper

Add a small `send_chat_action()` next to `send_message()` — same shape, just
`sendChatAction` and an `action` form field. Honour `TELEGRAM_TEST_SEND_FAIL`
and `TELEGRAM_TEST_SEND_LOG` for parity with `send_message`.

## Don't

- Don't add any new state files. The pulser reads the nest glob each tick;
  that's the whole signal.
- Don't change `POLL_TIMEOUT` defaults. Long-poll stays.
- Don't introduce `fswatch`/`inotifywait`. Plain `sleep` is the contract.
- Don't try to cancel the inbound long-poll on shutdown — `kill` plus the
  trap is enough; the `curl` will die with its process.

## Done when

- `telegram start` produces three background loops under one supervisor.
- `telegram stop` leaves no orphan processes (`pgrep -f telegram.sh` empty).
- `poll_once`, `push_transcript_once`, and the helpers still work standalone
  via `telegram poll-once` / `telegram push-once`.
