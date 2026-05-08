# stop-slash-command

**Outcome.** `/stop` aborts an in-flight model call: kills the process group, drops the active claim with a reason, and appends a `## system — ⚙️ run: item aborted` turn to transcript.

## Touchpoints

- `commands/stop.sh` (new).
- `commands/README.md` — list it.
- `commands/help.sh` — list it in help output.

## Procedure

1. If `.gremlin/.tending.pid` is missing → print "nothing to stop"; exit 0.
2. Read pgid. If the process is no longer alive → clean the pidfile, attempt the drop step anyway in case a stale claim exists, exit 0.
3. `kill -TERM -<pgid>`. Brief wait (e.g. 0.5s). If still alive, `kill -KILL -<pgid>`.
4. Find the active claim: any directory matching `.nest/in/*.tending` (single-tender invariant — expect one). Move it to `.nest/dropped/<x>` (without the suffix) and write `<x>.reason.md` with `stopped by user at <iso>`.
5. Append a `## system — <iso>\n⚙️ run: item aborted\n\n` block to `transcript.md`.
6. Remove the pidfile (in case the tender's trap didn't get there first).

## Idempotency

- Re-running `/stop` after a successful abort is a no-op with the "nothing to stop" message.
- Race with the tender's own trap is fine — both `rm -f` the pidfile.

## Verify

- Send a long prompt via TUI; before reply lands, type `/stop`. Process killed, item in `.nest/dropped/<x>` with reason, transcript shows user turn + system abort turn, no assistant turn.
- `/stop` with nothing in flight → friendly message, no errors.
- `/stop` after `/stop` → friendly message.
- Stale pidfile (manually written, no live PID) → cleaned, friendly message.

## Consistency / staleness

- `commands/README.md`, `commands/help.sh` — new command listed.
- `docs/protocol.md` — mention `/stop` in the Loops or a new Cancellation section; cross-reference `system-turn-type`.
- `bridges/tui/README.md` — note `/stop` as the emergency abort.

## Waits on

- `tender-pidfile` — sibling, must be in place first.
- `system-turn-type/format-and-docs` — convention for the abort turn.

Mark `.waiting` until both are tied.
