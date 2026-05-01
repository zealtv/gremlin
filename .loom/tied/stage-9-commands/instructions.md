# stage-9-commands

**Outcome.** Slash-prefixed system commands at the bridge. `say "/foo bar"` runs `commands/foo.sh bar` and never reaches the LLM. Ships with `/new`, `/model`, `/help`. Adding a new command is a `cp` into `commands/`.

The seam is parallel to `tools/`:

| Surface | Audience | Discovered via | Privilege |
|---------|----------|----------------|-----------|
| `tools/<name>.sh` | the LLM | `tools/README.md` in prompt | claude `--allowedTools` |
| `commands/<name>.sh` | the user | `commands/help.sh` (slash help) | the user's shell |

Tie this stitch when every child is tied and a short note below records what was learned.

## Notes

- Slash dispatch lives in `say` directly, before the existing send-and-wait. Slash messages bypass the LLM entirely — no transcript turn, no nest item.
- Presets are env files at `.gremlin/models/<alias>.env`, sourced by `bin/llm.sh`. `.gremlin/.model` holds the active alias name. Missing alias → fall back to `default`, log to stderr.
- claude CLI in 4.x has `--model` but no `--thinking` flag in `-p` mode (as of 2026-05). Each preset's `EXTRA_FLAGS` is the seam for whatever the CLI grows.
- `/help` extracts each script's first `# <name> — <summary>` comment line; `<name> — ` prefix is stripped to avoid duplication in the menu.
- Stage-9 outcome: user-facing slash commands work, two surfaces visible (`tools/` for the LLM, `commands/` for you). Adding a new command is a `cp` into `commands/`.