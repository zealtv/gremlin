# stage-4-runner

**Outcome.** `./.gremlin/run.sh` brings every loop up; SIGINT brings them down with no orphans. A `.paused` flag idles the loops without killing them.

Tie this stitch when every child is tied and a short note below records what was learned.

## Notes

- s13: PLAN suggested `trap 'kill 0' INT TERM` — segfaults bash 3.2 on macOS. Switched to explicit PID tracking + `kill "$pid"` from the trap, then `exit 0`. Dropped `set -e` on the supervisor (a child's non-zero shouldn't bail the whole runner).
- s14: `.paused` lives at `.gremlin/.paused` and is checked at the top of each loop script (not in `run.sh`) so direct `tend-loop.sh` invocations honour it too. Pending nest items pile up while paused; FIFO resumes on `rm`.
- Stage-4 outcome: a single command starts the gremlin; Ctrl-C ends it cleanly; `.paused` is the safe-quiesce signal for stage-8's archive.