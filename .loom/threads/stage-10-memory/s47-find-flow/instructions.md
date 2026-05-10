# s47 — find the flow

**Outcome.** A written flow that resolves the open design questions for memory, then rewrites the parent's child-stitch list (`s48`–`s53`) into concrete `instructions.md` files and refreshes the verification gate. No code lands from this stitch — it's a design stitch.

This stitch must tie before any `s48`+ child can be claimed: their instructions don't exist yet, and the answers below determine what they say.

## Questions to resolve

1. **What does "capture" mean gremlin-side?**
   - Working hypothesis: a gremlin verb that loads transcript material into `.glean/in/` via `glean.sh ingest`. Not a glean command.
   - Decide: is it a tool, a skill, a slash command, or just an inline shell call from another skill?

2. **Distillation triggers.**
   - Manual ("distil", "let's distil", "consolidate findings").
   - Scheduled: a paused groundhog item that fires nightly (or weekly) into `.nest/in/`.
   - Decide: ship both? Same skill body either way (one code path). What's the default schedule cadence and is it paused on install? (Memory says yes — paused, user opts in.)

3. **`/new` and the transcript graveyard.**
   - Today `/new` rotates `transcript.md` into `transcript-archive/` (human-readable record).
   - Decide: does `/new` *also* copy the just-rotated transcript into `.glean/in/` for later distillation?
     - Pro: nothing is forgotten; the inbox accumulates and a paused distil drains it on demand.
     - Con: the inbox grows unbounded between distillations; risk of burying signal in noise.
     - Alternative: capture is explicit — only an invoked verb pushes transcripts into `in/`.
   - This is the load-bearing decision. Pick one and live with the consequences.

4. **gremlin's own `distil.md`.**
   - Glean ships a default `distil.md` at `.glean/distil.md` (host-local, editable).
   - Gremlin should ship its own canonical `distil.md` that overrides glean's default at install time, mirroring how `.nest`, `.groundhog`, and `.loom` vendoring works.
   - Decide: where does gremlin's canonical `distil.md` live in the source tree, and does `init.sh` overwrite or only place-if-missing?

5. **Vendoring shape.**
   - Like loom / nest / groundhog: glean ships into `.gremlin/.glean/` carrying its own `README.md` (upstream-canonical, do not edit per project convention) plus `glean.sh`. Gremlin layers its own `distil.md` on top.
   - Glean has no `test.sh` — drop that reference from the parent's strategy section.

6. **`/update` and `.glean/` runtime.**
   - Findings, inbox, out, dropped, and the host-local `distil.md` are all local state. `/update` should preserve everything under `.glean/` except the upstream canonical files (`glean.sh`, `README.md`).
   - Decide: simplest excludes shape — preserve `.glean/` wholesale, then re-overlay the canonical files? Or enumerate the runtime trays?

7. **Verification gate.**
   - The current cold-start recall gate (parent's "Verification gate" section) was written before glean had real shape. Rewrite it once 1–6 are decided. Be explicit about which `glean.sh` commands the distil skill calls (`ingest`, `complete`, `index`, `drop` — there is no `capture`).

## Deliverables

When this stitch ties:

- A short flow doc inside this stitch directory (`flow.md` or similar) recording the chosen answers and the reasoning.
- The parent's `instructions.md` updated:
  - Strategy section reconciled with the chosen flow.
  - "Surgical changes" rewritten with concrete steps.
  - Verification gate rewritten.
  - Dead reference to glean's deleted loom (line ~62) stripped.
- Child stitches `s48-vendor-glean/`, `s49-init-wires-glean/`, `s50-distil-skill/`, `s51-distil-schedule-paused/`, `s52-update-excludes/`, `s53-acceptance-memory/` each get their own `instructions.md` written, structured so dependencies are honored:
  - `s48` is a precondition for `s49`/`s50`/`s51`/`s52` (vendoring must land before anything wires into it). Express by nesting those under `s48`, or rely on alphanumeric ordering of siblings — pick the cleaner shape based on actual dependency graph.
  - `s53` (acceptance) depends on everything else; nest the others under it, or run it last by name.

## Constraints

- Keep the flow as small as it can be while still being memory. If a question's answer is "do nothing," that's a valid answer.
- Distillation stays deliberate — no automatic flows that the user hasn't opted into.
- Glean stays content-opaque to gremlin's tender hot path; the integration rides on `context/` + one triggered skill + vendored glean.
