# stop-command

**Outcome.** `/stop` cancels the in-flight model call (emergency abort — e.g. the user just realised they asked the gremlin to delete something).

## Mechanism

- Tender writes `.gremlin/.tending.pid` (process group id) before `exec`-ing `bin/llm.sh`. Exit-trap removes it on success, failure, or signal.
- `/stop` reads the pidfile, kills the process group (so the model preset's child curl/etc. dies too), moves the active claim from `.nest/in/<x>.tending` to `.nest/dropped/<x>` with `<x>.reason.md`, and appends a `## system —` turn (`⚙️ run: item aborted`) to transcript.
- Tender, on llm.sh non-zero exit, checks whether its claim has moved away. If yes, it exits silently — no assistant turn written.

## Why pidfile, not no-file

We want a *real* cancel — kill the model subprocess, stop the tokens. Process-tree discovery is fragile across model presets. Single tender → single pidfile is enough; lives at gremlin root next to `.paused`, deleted at end of every tend.

## Children

- `tender-pidfile` — pidfile plumbing in the tender. Independent.
- `stop-slash-command` — the `/stop` command itself. Depends on `tender-pidfile` and on `system-turn-type/format-and-docs` (for the abort turn).

## Verify (parent-level)

- Send a long-running prompt; before reply lands, run `/stop`. Process tree dies, pidfile cleaned, item in `.nest/dropped/`, transcript has user turn + `## system — ⚙️ run: item aborted` + no assistant turn.
- `/stop` with nothing in flight is a no-op with a friendly message.
- Tender that completes normally also cleans the pidfile.
