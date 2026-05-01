# commands

System commands for the user — invoked via the bridge with a leading `/`. `say "/foo bar"` runs `commands/foo.sh bar` and never reaches the LLM.

Parallel to `tools/`, but for a different audience: tools are for the gremlin, commands are for you. Commands run with your shell privileges; they're not allowlist-constrained.

## Contract

Each command is a bash script directly under `commands/`.

- The first comment line is a one-line summary used by `/help`. Format: `# <name> — <summary>`.
- Args → stdout; errors → stderr with a non-zero exit.
- No-args invocation should be informative when the command takes a setting (list options, print current state).

## Built-in commands

| Command | Purpose |
|---------|---------|
| `/new` | start a fresh transcript (rotates current into `transcript-archive/`) |
| `/model` | list or set the active model preset |
| `/help` | show available commands |

Add a command by dropping a script into this folder.
