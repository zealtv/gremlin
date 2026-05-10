# groundhog-run-scripts

**Outcome.** A groundhog item containing an executable `run.sh` is executed as a script when it fires — no model call. Output is surfaced as a `## system — ⚙️ run:` transcript turn.

## Why

Some scheduled work is just "run this command" — a backup, a check, a refresh. Routing it through the model is wasteful and unreliable. Scripts that do want the model can call `bin/say` from inside `run.sh`.

## Mechanism (gremlin-side; groundhog stays opaque)

`bin/tick-loop.sh` is now a pure router (per tied stitch `tick-loop-pure-router`): it just moves materialised items into `.nest/in/`. All shape dispatch lives in `bin/tend-loop.sh`, which already branches on `message.md` → `## system — 💌 message:`. Add the `run.sh` branch as a sibling, *before* the message.md branch (more specific wins).

- If the claimed item is a directory containing an executable `run.sh`:
  - `cd` to the host folder (tend-loop already does this at top).
  - Execute `run.sh` (capture stdout, let stderr go to the runner log via `>&2`).
  - If exit zero and stdout non-empty: append `## system — <iso>\n⚙️ run: <stdout>\n\n` to `transcript.md`.
  - If exit zero and stdout empty: no transcript turn (quiet success).
  - If exit non-zero: append `## system — <iso>\n⚠️ error: run.sh exited <code>\n<stdout-tail>\n\n`.
  - Archive via `nestling complete` like the other branches.
- If the item has `run.sh` but it's not executable: log a warning to stderr and drop the item via `nestling drop` with a reason. Do not fall through to model-backed tend — an item that named itself a script and isn't executable is malformed, not a prompt.
- Order when both `run.sh` (executable) and `message.md` exist: `run.sh` wins.

## Touchpoints

- `bin/tend-loop.sh` — new branch (sibling of the message.md branch).
- `docs/protocol.md` — Data Flow + Loops + tend-loop dispatch list: add the `run.sh` route.
- **Do not edit `.groundhog/README.md`.** That file is the canonical upstream README from `~/repos/groundhog`, vendored verbatim. Groundhog is content-opaque by design — it must not learn about `run.sh`. Any documentation of the gremlin-side convention belongs in `docs/protocol.md`. The same rule applies to `.nest/README.md` and `.loom/README.md`: edits go upstream-first or to a sibling gremlin-side doc, never to the vendored copy.

## Verify

- Add a `once` item with `run.sh` that `echo "hello"`; tick; transcript has `⚙️ run: hello`; item gone from `.groundhog/out/`.
- `run.sh` that touches a host file (e.g. `touch ./scratch`) — file appears in host folder, confirming cwd.
- `run.sh` that exits 1 → `⚠️ error:` system turn with exit code; runner log has stderr.
- Item with both `message.md` and `run.sh` — decide order. Recommend: `run.sh` wins (more specific); document.
- Item with `run.sh` not executable — skip with a logged warning, do not treat as tend-target.

## Consistency / staleness

- `docs/protocol.md` Data Flow diagram and tend-loop dispatch list — add the `run.sh` path.
- `commands/new.sh` if it scaffolds groundhog items — could optionally offer a `run.sh` shape (defer if scope grows).
- Sweep for assumptions that "every materialised item without `message.md` is a tend-target." With `run.sh` added, the tender now has three shapes; only items that are neither `message.md`-only nor executable-`run.sh`-bearing fall through to model-backed tend.

## Unblocked

- `system-turn-type/format-and-docs` is tied — the `## system —` convention is documented in `docs/protocol.md`. No remaining wait.
