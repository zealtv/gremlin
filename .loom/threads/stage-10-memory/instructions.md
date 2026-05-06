# stage-10-memory

**Outcome.** A fresh gremlin ships with scribble vendored as its memory protocol. Distillation is a deliberate act, not an automatic flow. Findings are the workbench; `context/` remains the broadcast; promotion is by symlink.

**Scribble-side children are fleshed out (`s47a`–`s47e`).** They must ship before gremlin integration begins. Gremlin-side children remain suggestions — each needs its own `instructions.md` written and committed before being claimed.

## Strategy

**Two surfaces.**

- `.gremlin/.scribble/findings/` is the workbench — what the agent has distilled. Not always loaded.
- `.gremlin/context/` is the broadcast — what the agent always carries.
- Promotion is explicit: symlink `context/<id>.md → ../.scribble/findings/<id>/finding.md`. The agent decides when a finding has earned always-loading.

**Distillation is deliberate.**

- `/new` does **not** auto-pipe transcripts into `.scribble/in/`. The transcript graveyard is `transcript-archive/`, which is human-readable and already exists.
- A `dream` skill, triggered explicitly ("dream", "let's dream", "consolidate findings"), reads `transcript.md` (or a named archive) and decides what to ingest as small distilled notes.
- The agent participates in distillation rather than the system shovelling raw ore.
- Dreaming may also be invoked by a scheduled groundhog item that lands in `.nest/in/` and is tended via the same `dream` skill (no second code path). The dream item ships paused, so a fresh gremlin only dreams when the user opts in.

**Scribble stays pure markdown.**

- No YAML, no frontmatter. `finding.md` is plain markdown with a fixed set of optional H2 sections (`Claim`, `Why`, `Scope`, `Triggers`, `Associations`).
- `index` and `fetch` parse those sections directly. The contract is the heading shape.

**Tend-loop, archive.sh, llm.sh, tick-loop.sh — all untouched.** The integration rides on the existing always-loaded `context/` slot plus one new triggered skill plus the vendored scribble.

## Surgical changes

### gremlin

1. Vendor `.gremlin/.scribble/` with `scribble.sh`, `README.md`, default `dream.md`. Match the nestlings/groundhog vendoring pattern.
2. `init.sh`: one line to run `scribble.sh init` against the new copy after `cp -r`.
3. `skills/dream.md`: triggered skill. Tight triggers. Body: read raw, read findings, prefer associate→revise→create→drop, ingest *small distilled notes*, document promotion-via-symlink.
4. (Optional) one-line nudge in `commands/new.sh`. Defer until acceptance.

### scribble

5. `finding.md` template grows a `## Triggers` section. README documents the section-based contract that `index` and `fetch` rely on.
6. `scribble.sh index` regenerates `findings/INDEX.md` — one bullet per finding (id, title, Claim line). Mirrors `bin/index-skills.sh`.
7. `scribble.sh fetch <query...>` returns paths of findings whose id, title, Claim, Scope, or Triggers match. The prefetch seam.
8. `scribble.sh capture <id>` reads stdin and lands ready in one shot. Replaces the previously-suggested `ingest <id> -` form.
9. README documents disclosure layers (INDEX always, finding.md on lookup, context.md deep dive) and the dream-as-item composition recipe (groundhog → nest → dream skill).

## Verification gate

Cold-start recall:

1. Fresh init produces an empty scribble.
2. Establish a durable preference in conversation.
3. Trigger dreaming → finding lands in `.scribble/findings/<id>/finding.md`.
4. Promote via symlink into `context/`.
5. `/new` rotates the transcript.
6. Ask the same question cold (no transcript context). Answer should still be correct *because* the symlinked finding is in the loaded context. **Load-bearing test.**
7. Drop test: trigger removal. Finding moves to `.scribble/dropped/`. Dangling symlink is acceptable; cleanup is a hygiene step the skill should mention.

If step 6 works, it's memory. If not, it's a filing cabinet.

## Child stitches

Scribble-side (fleshed out, ready to claim — must ship before any gremlin-side work):

- `s47a-finding-shape` *(scribble repo)* — plain-markdown finding contract; add `## Triggers` to template; document parse rules.
- `s47b-index` *(scribble repo)* — `scribble.sh index` writes `findings/INDEX.md`.
- `s47c-fetch` *(scribble repo)* — `scribble.sh fetch <query...>` returns matching finding paths.
- `s47d-capture` *(scribble repo)* — `scribble.sh capture <id>` reads stdin and lands ready.
- `s47e-readme` *(scribble repo)* — README documents disclosure layers and the dream-as-item recipe.

Gremlin-side (suggestions — need their own `instructions.md` before being claimed):

- `s48-vendor-scribble` — copy scribble.sh + README into `.gremlin/.scribble/`, ship a default `dream.md`.
- `s49-init-wires-scribble` — `init.sh` runs scribble's init for new gremlins.
- `s50-dream-skill` — `skills/dream.md` with tight triggers + the procedure; consumes `INDEX`/`fetch`/`capture`.
- `s51-dream-schedule-paused` — ship a paused groundhog item that fires a dream instruction into `.nest/in/`. Depends on the groundhog "paused item" feature (see Dependencies).
- `s52-sync-excludes` — update DEVELOPING.md sync helper template to exclude scribble runtime state.
- `s53-acceptance-memory` — the cold-start recall gate.

## Dependencies

- **Groundhog "paused item" feature** *(groundhog repo, separate change)*. The dream item must ship paused so a fresh install does not auto-dream. Groundhog today has a runner-wide `.paused`; per-item pause is a new feature. Tracked in the groundhog repo, not here. `s51-dream-schedule-paused` waits on it.

## Decisions deferred to those child stitches

- Exact `dream.md` skill body (procedure, error cases, promotion guidance).
- Default `dream.md` shipped inside `.gremlin/.scribble/` — scribble's default vs gremlin-tuned.
- Trigger phrasing — start tight, loosen if needed.
- Whether `commands/new.sh` actually gets the nudge.
- `.gitkeep` strategy for `.scribble/in/`, `findings/`, `dropped/` in the canonical.
- Sync helper exclusions (probably mirror `context/` — `.scribble/in/`, `findings/`, `dropped/`, `dream.md`).

## Notes

(filled in as child stitches tie off; record what was learned)
