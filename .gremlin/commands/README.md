# commands

System commands for the user — invoked via a bridge with a leading `/`.
`/foo bar` in the TUI, or `bin/say /foo bar` from a script, runs
`commands/foo.sh bar` and never reaches the LLM.

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
| `/update` | pull canonical gremlin from `.upstream` and lay it over this copy |
| `/help` | show available commands |

Add a command by dropping a script into this folder. **Name custom additions distinctly from canonical names** — `/update` overwrites canonical files by name, so a personal `commands/help.sh` would be replaced. New names (e.g. `commands/standup.sh`) survive untouched.

`/update` reads the canonical tarball URL from `.gremlin/.upstream`. Edit that
file to track a fork or a local tarball (`file:///path/to/gremlin.tar.gz`).
