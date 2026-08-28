# tend

Each item in `in/` is a message for the gremlin to act on (from a bridge, or from a groundhog tick).

Build the prompt by concatenating, in order:

1. `../.gremlin/gremlin.md`
2. every file in `../.gremlin/context/` (sorted)
3. `../.gremlin/skills/INDEX.md`
4. `../.gremlin/tools/README.md`
5. `../.gremlin/transcript.md`
6. the item body

Pipe to `../.gremlin/bin/llm.sh`. Write the reply to `out/<ts>.md` via `.landing` rename. Append the assistant turn to `../.gremlin/transcript.md`.

When a trigger listed in `skills/INDEX.md` matches the user's request, the tender should `cat ../.gremlin/skills/<name>.md` to read the full skill body before replying.

This file is process, not identity. Identity lives in `../.gremlin/gremlin.md`.
