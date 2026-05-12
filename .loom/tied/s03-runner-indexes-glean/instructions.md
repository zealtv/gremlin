# s03-runner-indexes-glean

**Outcome.** The runner refreshes the Glean catalog at the same point it refreshes the skills index, so the broadcast `context/system/memory.md` always reflects current findings.

## Scope

Modify `bin/run.sh`:

- After the existing `bin/index-skills.sh` invocation, call `.glean/glean.sh index` when `.glean/` exists.
- Both calls are best-effort: log a warning on failure, do not abort the runner.

## Constraints

- Do not call `glean.sh index` from the tender per-turn. The runner is the right cadence — same as skills.
- Do not move responsibility for index freshness into doctor. Doctor wires symlinks; the runner refreshes generated indexes. Keeping those concerns separate keeps both small.
- A gremlin with no `.glean/` directory (older layout) must still start cleanly. The presence check is on the directory, not on the script.

## Verification

1. Start a gremlin with no findings. `.glean/findings/INDEX.md` exists (empty-state form glean writes).
2. Create a finding manually with `.glean/glean.sh`. Restart the runner. `INDEX.md` updates without a manual `glean.sh index`.
3. With the s04 tender change in place, the next prompt contains the updated catalog entry.

## Notes

- This stitch is small but ordered before s04 deliberately: by the time the tender starts reading `context/system/memory.md` for every prompt, the catalog it points at is already refreshed on runner start.
