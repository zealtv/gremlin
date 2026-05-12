# s04-tender-context-only

**Outcome.** `bin/tend-loop.sh` builds the model prompt from `gremlin.md` + `context/system/*.md` + `context/*.md` (top-level) + transcript + item. The hardcoded `skills/INDEX.md` and `tools/README.md` inlines are removed.

## Scope

Modify `bin/tend-loop.sh`'s prompt-build block to read, in order:

1. `gremlin.md`
2. `context/system/*.md` sorted, **excluding** `README.md`. Recommended rule: include only entries that are symlinks. That makes the exclusion mechanical, makes the `README.md` exclusion trivial, and signals that `system/` is for symlinks.
3. `context/*.md` at the top level, sorted, **excluding** the `system/` directory itself.
4. Transcript.
5. Current item body.

Step 2 may be empty (a gremlin with no system symlinks). Step 3 may be empty (no user-authored broadcast). Both are fine.

## Constraints

- Symlinks must be followed when read. `cat` does this by default — confirm and proceed.
- A missing `context/` directory is tolerated as "no broadcast" — do not error.
- Do not land before s01–s03. Until install seeds `context/system/` and the runner refreshes the glean index, this change would regress new and existing gremlins.
- Skills and tools must continue to reach the model in the assembled prompt with no functional change beyond ordering within the new structure.

## Verification

1. Dump the assembled prompt for one trivial tend before and after the change. The skills index and tools index appear in both; their content matches.
2. `rm context/system/skills.md`. Next assembled prompt has no skills section. `gremlin doctor` restores it; next prompt contains it again.
3. Add `context/marker.md` containing a known phrase. Next assembled prompt contains the phrase, positioned after the `system/` block and before the transcript.
4. A `context/system/README.md` file is present but does **not** appear in the assembled prompt.

## Notes

- The "only symlinks in `system/`" rule is also documentation: a future reader scanning the code sees that `system/` is structurally different from the top-level `context/`. The README file is the only real file in there, and it is filtered out by the symlink check.
- This is the load-bearing change for the thread. Verification artifacts (assembled-prompt dumps for before/after) should live in this stitch directory.
