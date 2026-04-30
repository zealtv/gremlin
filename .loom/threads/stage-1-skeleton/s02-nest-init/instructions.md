# s02-nest-init

1. Copy `nestling.sh` from the family's `nestlings/.nest/nestling.sh` into `.gremlin/.nest/`.
2. Run `./.gremlin/.nest/nestling.sh ensure` to lay down `in/ out/ dropped/`.
3. Write `.gremlin/.nest/tend.md` describing the *tending process* for a gremlin's nest. Generic, protocol-level. Identity does **not** belong here.

`tend.md` body, roughly:

```markdown
# tend

Each item in `in/` is a message for the gremlin to act on (from a bridge, or
from groundhog tick).

Build the prompt by concatenating, in order:

1. `../gremlin.md`
2. every file in `../context/` (sorted)
3. `../skills/INDEX.md`
4. `../tools/README.md`
5. `../transcript.md`
6. the item body

Pipe to `../bin/llm.sh`. Write the reply to `out/<ts>.md` via `.landing` rename.
Append the assistant turn to `../transcript.md`.
```

**Verify:** `ls .gremlin/.nest/` shows `in/ out/ dropped/ nestling.sh tend.md`. `cat .gremlin/.nest/tend.md` describes process, not identity.
