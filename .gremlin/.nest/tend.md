# tend

Each item in `in/` is a message for the gremlin to act on (from a bridge, or from a groundhog tick).

Build the prompt by concatenating, in order:

1. `../gremlin.md`
2. every file in `../context/` (sorted)
3. `../skills/INDEX.md`
4. `../tools/README.md`
5. `../transcript.md`
6. the item body

Pipe to `../bin/llm.sh`. Write the reply to `out/<ts>.md` via `.landing` rename. Append the assistant turn to `../transcript.md`.

This file is process, not identity. Identity lives in `../gremlin.md`.
