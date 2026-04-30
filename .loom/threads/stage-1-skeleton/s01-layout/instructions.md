# s01-layout

Create `.gremlin/` at the repo root with the canonical top-level entries:

- `gremlin.md` — a generic placeholder identity ("you are a gremlin: a small folder-based agent. you read your context and skills before replying. you reply briefly.").
- `context/` — empty folder. (Optional in real use; ships empty in the dogfood instance so the structure is visible.)
- `bin/` — empty for now; populated by later stitches.
- `tools/` — empty for now.
- `skills/` — empty for now.
- `transcript-archive/` — empty.
- `transcript.md` — empty file.

Do **not** create a top-level `tend.md` here. The nest's `tend.md` (process instructions) is seeded by `s02-nest-init`. Identity lives in `gremlin.md`.

**Verify:** `ls .gremlin/` shows the entries above. `cat .gremlin/gremlin.md` is non-empty and generic.
