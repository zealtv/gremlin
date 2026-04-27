# s14-pause-flag

Each loop checks for a `.paused` file at the top of each iteration and skips work while it exists. The check belongs in the loop scripts themselves (so it works under `run.sh` *or* a direct invocation).

**Verify:** With `run.sh` running, `touch .scribe/.paused`; the loops idle (no new work tended). `rm .scribe/.paused`; pending work resumes.
