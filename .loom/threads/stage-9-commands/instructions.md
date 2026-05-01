# stage-9-commands

**Outcome.** Slash-prefixed system commands at the bridge. `say "/foo bar"` runs `commands/foo.sh bar` and never reaches the LLM. Ships with `/new`, `/model`, `/help`. Adding a new command is a `cp` into `commands/`.

The seam is parallel to `tools/`:

| Surface | Audience | Discovered via | Privilege |
|---------|----------|----------------|-----------|
| `tools/<name>.sh` | the LLM | `tools/README.md` in prompt | claude `--allowedTools` |
| `commands/<name>.sh` | the user | `commands/help.sh` (slash help) | the user's shell |

Tie this stitch when every child is tied and a short note below records what was learned.

## Notes
