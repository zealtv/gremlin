# tender-pidfile

**Outcome.** Whenever a model call is in flight, `.gremlin/.tending.pid` exists with the process group id of the `llm.sh` child. When the call ends (any reason), the pidfile is gone.

## Touchpoints

- `bin/tend-loop.sh` — wrap the `llm.sh` invocation.

## Mechanism

1. Before invoking `llm.sh`, start a new process group so a single signal can reach the preset's children (curl, jq, model SDKs). Either run `llm.sh` via `setsid` or `set -m` + background, capture the pgid.
2. Write the pgid to `.gremlin/.tending.pid` (atomic: write to `.tending.pid.tmp`, rename).
3. Set a trap (`EXIT`, `INT`, `TERM`) to `rm -f` the pidfile.
4. After `llm.sh` returns: if exit was non-zero **and** the claimed item has moved out of `.nest/in/<x>.tending` (i.e. `/stop` dropped it), skip the assistant transcript write and exit cleanly.
5. Otherwise, proceed as today (write assistant turn, complete the item).

## Verify

- Long-prompt run: `.gremlin/.tending.pid` appears for the duration; vanishes after.
- Kill the pgid externally (`kill -TERM -<pgid>`) mid-flight; tender exits, pidfile cleaned, no assistant turn written if claim is gone.
- Two consecutive normal tends — pidfile cleanly created and removed each time, no leftover.
- Tender crash (simulate with `kill -KILL` of the tender itself) leaves a stale pidfile — document this as the only known failure mode; `/stop` should treat a stale pidfile (PID not alive) as "nothing to stop" and clean it.

## Consistency / staleness

- `docs/protocol.md` Loops section — note pidfile lifecycle.
- Sweep tend-loop for any assumption that "tender always writes assistant turn"; the abort-skip is a new branch.
- `commands/sweep.sh` and any cleanup tooling — confirm they don't touch `.tending.pid`.
- Existing `.paused` flag at gremlin root — pidfile sits next to it; same idiom.
