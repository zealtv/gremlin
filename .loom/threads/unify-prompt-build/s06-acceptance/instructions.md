# s06-acceptance

**Outcome.** End-to-end verification of the unified prompt-build model. The gate for tying the parent thread.

## Scope

Run the verification gate from the parent thread end-to-end:

**Fresh install.**

1. `install.sh` in a clean directory.
2. `ls .gremlin/context/system/` shows `skills.md`, `tools.md`, `memory.md`, `README.md`.
3. Each non-README entry resolves to its expected target.
4. Tend a trivial item; dump the assembled prompt and confirm a skills section, tools section, and (possibly empty) memory section all appear.

**Opt-out and restore.**

1. `rm .gremlin/context/system/memory.md`.
2. Tend a trivial item; assembled prompt no longer contains the memory catalog.
3. `gremlin doctor`. Next assembled prompt contains the memory catalog again.

**Migration.**

1. Start from a pre-thread `.gremlin/` (no `context/system/`).
2. Run `/update` against a canonical tarball built from this thread's HEAD.
3. `context/system/` is populated; skills and tools still reach the model unchanged.

**User content.**

1. Drop `.gremlin/context/marker.md` with a known phrase.
2. Tend; phrase appears in the prompt after the `system/` block, before the transcript.

**Glean catalog freshness.**

1. With the runner up, create a finding via `.glean/glean.sh`.
2. Without restarting the runner, the catalog should still update on the next runner cycle — verify the cadence matches what s03 implemented.

## Artifact

Write a short report in this stitch directory before tying it:

- which checks passed and which surfaced surprises;
- assembled-prompt diffs (before / after) for the trivial-item case;
- any follow-up stitches the gate suggests.

## Constraints

- This stitch verifies. It does not implement. If a check fails, the failing piece moves back into a child stitch of the relevant earlier stage rather than being patched inside acceptance.
- Use the live-verify path (push canonical → `/update` on the remote live gremlin) for at least the migration step, not just a local clean room.
