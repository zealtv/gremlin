# s48-vendor-glean

**Outcome.** Gremlin vendors Glean under `.gremlin/.glean/` and ships the memory
model preset needed by `/new` review items.

This is the first implementation loose end after `s47-find-flow` ties.

## Scope

- Copy canonical Glean files from `github.com/zealtv/glean` into
  `.gremlin/.glean/`:
  - `glean.sh`
  - `README.md`
- Seed protocol trays with placeholders as needed:
  - `in/`
  - `findings/`
  - `out/`
  - `dropped/`
- Add Gremlin's tuned `.gremlin/.glean/distil.md`.
- Add `.gremlin/models/memory.sh` as a thin wrapper around `default.sh`.
- Ensure `memory.sh` is executable.
- Update relevant docs to mention:
  - `.gremlin/.glean/` as the memory workbench;
  - `.gremlin/models/memory.sh` as the default review model alias;
  - promotion by symlink into `context/`.

## Constraints

- Treat `glean.sh` and `README.md` as upstream-canonical vendored files.
- Do not edit Glean's protocol shape.
- Do not add a `.glean/sources/` ledger.
- Do not wire `/new` yet; that belongs to later stitches.

## Verification

1. `./.gremlin/.glean/glean.sh status` runs.
2. `./.gremlin/.glean/glean.sh index` creates or refreshes
   `.glean/findings/INDEX.md`.
3. `.gremlin/models/memory.sh` can be executed and delegates to `default.sh`.
4. `git status` shows only intended vendored files, placeholders, model preset,
   and docs.

## Notes

- Glean's public repo currently stores canonical files under its own `.glean/`
  folder. Copy only the protocol files intended to ship inside Gremlin.
