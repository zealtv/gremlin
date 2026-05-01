# s38-model

`commands/model.sh`:

- **No args:** list all `models/*.env` aliases (basenames, sorted), one per line. Mark the active alias (the one in `.gremlin/.model`, defaulting to `default`) with a leading `*`. Show the resolved `MODEL=` value next to each for quick reference.
- **One arg (`<alias>`):** if `models/<alias>.env` exists, write the alias to `.gremlin/.model` and print `model: <alias>`. If it doesn't exist, list available aliases on stderr and exit non-zero.

First comment line of the script is its `/help` summary.

**Verify:** `./.gremlin/say "/model"` lists presets with the active one starred. `./.gremlin/say "/model fast"` switches; the next `say "..."` runs through the fast model. `./.gremlin/say "/model nonsense"` fails informatively.
