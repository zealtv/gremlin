# s13-runner

`.scribe/run.sh`:

- Background each loop (just `tend-loop.sh` for now; `tick-loop.sh` joins in stage 7).
- Each loop is `while sleep <cadence>; do bin/<loop>.sh; done`.
- `trap 'kill 0' INT TERM` so SIGINT brings every child down.
- `wait` at the end so the script blocks.

**Verify:** `./.scribe/run.sh` starts cleanly. Ctrl-C ends every child process — `pgrep -f tend-loop` returns nothing.
