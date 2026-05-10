# stage-10-memory

**Outcome.** A fresh gremlin ships with glean vendored as its memory protocol. Distillation is a deliberate act, not an automatic flow. Findings are the workbench; `context/` remains the broadcast; promotion is by symlink.

**Glean ships at `github.com/zealtv/glean`.** Gremlin integration can begin. The first child `s47-find-flow` is a design stitch that resolves the open flow questions and rewrites the remaining children into concrete `instructions.md` files; until it ties, the `s48`+ entries below are suggestions, not stitches.

**Open flow questions live in `s47-find-flow/instructions.md`** — read that before editing this file.

## Strategy

**Two surfaces.**

- `.gremlin/.glean/findings/` is the workbench — what the agent has distilled. Not always loaded.
- `.gremlin/context/` is the broadcast — what the agent always carries.
- Promotion is explicit: symlink `context/<id>.md → ../.glean/findings/<id>.md`. The agent decides when a finding has earned always-loading.

**Distillation is deliberate.**

- `/new` does **not** auto-pipe transcripts into `.glean/in/`. The transcript graveyard is `transcript-archive/`, which is human-readable and already exists.
- A `distil` skill, triggered explicitly ("distil", "let's distil", "consolidate findings"), reads `transcript.md` (or a named archive) and decides what to land — either as raw material via `glean.sh ingest` or, if already polished, directly via `glean.sh capture`.
- The agent participates in distillation rather than the system shovelling raw ore.
- Distillation may also be invoked by a scheduled groundhog item that lands in `.nest/in/` and is tended via the same `distil` skill (no second code path). The distil item ships paused, so a fresh gremlin only distils when the user opts in.

**Glean stays pure markdown.**

- No YAML, no frontmatter. A finding is one flat markdown file at `findings/<id>.md`.
- Parser contract: title (first `# ` line) + single-line description (first non-empty line between title and next heading). Everything else is free prose.
- `## Why`, `## Triggers`, `## Associations`, `## Context` are *suggested* sections in the host's `distil.md` brief — none enforced by the parser.
- Associations use wikilinks: `- [[other-id]]`.
- `index` always-loads via `findings/INDEX.md`; `fetch` does the prefetch (strict by default — id + title + description + Triggers — with `--all` to widen to whole-file grep).
- `ingest` uses the family-wide `.landing` write-protection suffix during the move, so an interrupted ingest leaves only `.landing` residue (ignored by other commands).

**Memory integration is orthogonal to the tender hot path.** The integration rides on the existing always-loaded `context/` slot plus one new triggered skill plus the vendored glean. `tend-loop.sh`, `llm.sh`, `tick-loop.sh`, and `archive.sh` need no memory-specific changes — those scripts remain content-opaque to memory.

## Surgical changes

### gremlin

> Concrete steps land here once `s47-find-flow` ties. The bullets below are pre-design suggestions and will be rewritten.

1. Vendor `.gremlin/.glean/` with glean's upstream-canonical `glean.sh` and `README.md` (do not edit — same convention as `.nest`, `.loom`, `.groundhog`), plus gremlin's own `distil.md` overlaid on top of glean's default. No `test.sh` exists upstream.
2. `init.sh`: one line to run `glean.sh init` against the new copy after `cp -r`.
3. `skills/distil.md`: triggered skill. Tight triggers. Body: read raw from `.glean/in/`, read existing findings via `index`/`fetch`, prefer associate→revise→create→drop, write distilled notes directly to `findings/<id>.md`, then `glean.sh complete <in-id>` and `glean.sh index`. Document promotion-via-symlink. (No `capture` command exists; capture is a gremlin-side verb to be defined in `s47-find-flow`.)
4. `/new` and groundhog-fired distillation behaviour — pending `s47-find-flow`.

### glean

Glean ships at `github.com/zealtv/glean`. Its rebuild loom has been emptied and deleted; treat the public repo as canonical.

## Verification gate

Cold-start recall:

1. Fresh init produces an empty glean.
2. Establish a durable preference in conversation.
3. Trigger distillation → finding lands at `.glean/findings/<id>.md`.
4. Promote via symlink into `context/`.
5. `/new` rotates the transcript.
6. Ask the same question cold (no transcript context). Answer should still be correct *because* the symlinked finding is in the loaded context. **Load-bearing test.**
7. Drop test: trigger removal. Finding moves to `.glean/dropped/`. Dangling symlink is acceptable; cleanup is a hygiene step the skill should mention.

If step 6 works, it's memory. If not, it's a filing cabinet.

## Child stitches

Glean-side work is shipped at `github.com/zealtv/glean` (rebuild loom emptied and deleted).

Gremlin-side:

- **`s47-find-flow`** *(real loose end — design stitch; see `s47-find-flow/instructions.md`)*. Resolves capture semantics, distillation triggers, `/new` behaviour, gremlin's own `distil.md`, vendoring shape, and `/update` excludes. Output is concrete `instructions.md` files for the children below.

The following are suggestions — not stitches yet. `s47-find-flow` writes their `instructions.md` files and structures dependencies (likely by nesting `s49`–`s52` under `s48`, and running `s53` last):

- `s48-vendor-glean` — vendor `glean.sh` + upstream `README.md` into `.gremlin/.glean/`, layer gremlin's canonical `distil.md` on top.
- `s49-init-wires-glean` — `init.sh` runs glean's init for new gremlins.
- `s50-distil-skill` — `skills/distil.md` with tight triggers + the procedure; consumes `index` / `fetch` / `ingest` / `complete` / `drop`.
- `s51-distil-schedule-paused` — ship a paused groundhog item that fires a distil instruction into `.nest/in/`. The groundhog "paused item" feature has landed (see Dependencies).
- `s52-update-excludes` — extend `commands/update.sh` `excludes=(...)` so `/update` preserves `.glean/` runtime state (exact list pending `s47-find-flow`).
- `s53-acceptance-memory` — the cold-start recall gate (rewritten by `s47-find-flow`).

## Dependencies

- ~~**Glean rebuild** *(glean repo)*. Goal stitch at `~/repos/glean/.loom/threads/glean-rebuild/`. Children `s47a`–`s47j` cover the rename, finding contract, all eight commands, tests, README, and this thread's update. `s48`–`s50` here wait on it.~~ ✅ Tied 2026-05-10. Glean ships at `github.com/zealtv/glean` (renamed from `zealtv/scribble`).
- ~~**Groundhog paused-items feature** *(groundhog repo)*. Stitch at `~/repos/groundhog/.loom/threads/paused-items/`. The distil item must ship paused so a fresh install does not auto-distil. `s51-distil-schedule-paused` waits on it.~~ ✅ Landed 2026-05-09 — `.paused` suffix on any path component takes that subtree off-schedule (cascades). Vendored into `.gremlin/.groundhog/`. `s51-distil-schedule-paused` is unblocked from the groundhog side.

## Decisions deferred to those child stitches

- Exact `distil.md` skill body (procedure, error cases, promotion guidance).
- Default `distil.md` shipped inside `.gremlin/.glean/` — glean's default vs gremlin-tuned.
- Trigger phrasing — start tight, loosen if needed.
- Whether `commands/new.sh` actually gets the nudge.
- `.gitkeep` strategy for `.glean/in/`, `findings/`, `dropped/` in the canonical.
- `commands/update.sh` excludes additions (probably mirror `context/` — `.glean/in/`, `.glean/findings/`, `.glean/dropped/`, and `distil.md` if it's user-tunable).

## Notes

(filled in as child stitches tie off; record what was learned)
