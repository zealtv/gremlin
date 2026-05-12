# s01-doctor-and-seed

**Outcome.** A fresh gremlin install produces a populated `context/system/`, and `gremlin doctor` can restore it on demand.

## Scope

Add `bin/doctor.sh`:

- Defines an expected manifest as a small in-script constant:
  - `context/system/skills.md → ../../skills/INDEX.md`
  - `context/system/tools.md → ../../tools/README.md`
  - `context/system/memory.md → ../../.glean/findings/INDEX.md`
- Creates `context/system/` if missing.
- For each manifest entry: creates the symlink if missing; relinks it if the target is wrong; leaves it untouched if correct.
- Writes `context/system/README.md` if missing — a short paragraph explaining the directory is managed by `gremlin doctor`, that `rm` opts out of a broadcast, and `gremlin doctor` restores it.
- Reports each action on stdout (`created`, `relinked`, `ok`, `skipped (real file)`).
- Exits non-zero only on a filesystem error.

Wire the subcommand:

- `gremlin doctor` invokes `bin/doctor.sh`.
- `/help` lists it.

Wire install:

- `install.sh` calls `bin/doctor.sh` after the rest of `.gremlin/` is in place, so a fresh gremlin ships with `context/system/` populated.

## Constraints

- Doctor never deletes a non-symlink in `context/system/`. If the user has dropped a real `.md` there, doctor leaves it and reports `skipped (real file)`.
- Doctor never touches `context/*.md` at the top level.
- The expected manifest lives in the script, not in a separate file. Keep it small enough to read at a glance.
- No `--force` flag. Doctor only creates missing entries or relinks an existing symlink to the correct target.

## Verification

1. `rm -rf .gremlin/context/system/`. Run `gremlin doctor`. Directory and four entries are recreated.
2. Repoint `context/system/memory.md` to a wrong target. Run `gremlin doctor`. The symlink is relinked correctly.
3. Drop a real file `context/system/notes.md`. Run `gremlin doctor`. The file is left untouched and reported as `skipped (real file)`.
4. Fresh `install.sh` in an empty directory produces a populated `context/system/` without a separate doctor invocation.

## Notes

- README content can be terse — three or four sentences. It is the doc users hit when they `ls` the directory wondering what it is.
- This stitch does not change the tender. Until s04 lands, the symlinks exist but are not yet read into the prompt by the new path.
