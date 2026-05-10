# groundhog-run-scripts

**Outcome.** A groundhog item containing an executable `run.sh` is executed as a script when it fires — no model call. Output is surfaced as a `## system — ⚙️ run:` transcript turn.

## Why

Some scheduled work is just "run this command" — a backup, a check, a refresh. Routing it through the model is wasteful and unreliable. Scripts that do want the model can call `bin/say` from inside `run.sh`.

## Mechanism (gremlin-side; groundhog stays opaque)

`bin/tick-loop.sh` already routes materialised items: `message.md` → outbound transcript, otherwise → `.nest/in/`. Add a third branch *before* the existing default:

- If the item directory contains an executable `run.sh`:
  - `cd` to the host folder.
  - Execute `run.sh` (capture stdout, let stderr go to the runner log).
  - If stdout is non-empty: append `## system — <iso>\n⚙️ run: <stdout>\n\n` to `transcript.md`.
  - If exit non-zero: append `## system — <iso>\n⚠️ error: run.sh exited <code>\n<stdout-tail>\n\n`.
  - `rm -rf` the materialised item.

## Touchpoints

- `bin/tick-loop.sh` — new branch.
- `docs/protocol.md` — Data Flow scheduled section: add the script route.
- **Do not edit `.groundhog/README.md`.** That file is the canonical upstream README from `~/repos/groundhog`, vendored verbatim. Groundhog is content-opaque by design — it must not learn about `run.sh`. Any documentation of the gremlin-side convention belongs in `docs/protocol.md`. The same rule applies to `.nest/README.md` and `.loom/README.md`: edits go upstream-first or to a sibling gremlin-side doc, never to the vendored copy.

## Verify

- Add a `once` item with `run.sh` that `echo "hello"`; tick; transcript has `⚙️ run: hello`; item gone from `.groundhog/out/`.
- `run.sh` that touches a host file (e.g. `touch ./scratch`) — file appears in host folder, confirming cwd.
- `run.sh` that exits 1 → `⚠️ error:` system turn with exit code; runner log has stderr.
- Item with both `message.md` and `run.sh` — decide order. Recommend: `run.sh` wins (more specific); document.
- Item with `run.sh` not executable — skip with a logged warning, do not treat as tend-target.

## Consistency / staleness

- `docs/protocol.md` Data Flow diagram — add the `run.sh` path.
- `commands/new.sh` if it scaffolds groundhog items — could optionally offer a `run.sh` shape (defer if scope grows).
- Sweep for assumptions that "every materialised item without `message.md` is a tend-target."

## Waits on

- `system-turn-type/format-and-docs` — for the `## system —` turn convention. Mark `.waiting` until tied.
