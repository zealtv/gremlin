# s29-tick-in-runner

Wire `tick-loop.sh` into `run.sh` at ~60s cadence. Honour `.paused` like the other loops.

**Verify:** With `run.sh` running, drop `schedule/once/<today>/<minute>/test/message.md`, wait one minute, see it routed.
