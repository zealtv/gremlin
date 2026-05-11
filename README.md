# 👀 gremlin

gremlin is an AI agent that lives in a folder.

You can connect it to Claude Code, OpenAI Codex, Open Code, Pi, or your local model.


## Quick Start

### Install gremlin into the current directory

```sh
curl -fsSL https://raw.githubusercontent.com/zealtv/gremlin/main/install.sh | bash -s
```

### Configure a model preset

Model presets are just executables that read a prompt on stdin and write a reply on stdout. The default preset is `.gremlin/models/default.sh` which looks like this (edit it to match the model CLI you want to use):

```sh
#!/usr/bin/env bash
# claude sonnet 4.6
set -euo pipefail
exec claude -p --model claude-sonnet-4-6 --allowedTools "Bash"
```

### Start the runner

```sh
.gremlin/gremlin start
```

### Run the TUI

```sh
.gremlin/gremlin tui
```

Run `/help` for to list commands.

### Customize the gremlin:

- `.gremlin/gremlin.md`: identity, personality, purpose, voice.
- `.gremlin/context/`: facts loaded into every prompt.
- `.gremlin/skills/`: markdown skills.
- `.gremlin/tools/`: bash tools.
- `.gremlin/models/`: model presets.


## Principles

gremlin uses a family of simple, file-based protocols for messaging, scheduling, and memory.

- 🪺 [nestlings](https://github.com/zealtv/nestlings): queing and actioning work
- 🦫 [groundhog](https://github.com/zealtv/groundhog): scheduling reocurring tasks
- 🔮 [glean](https://github.com/zealtv/glean): memory distillation and retrieval
- 🪡 [loom](https://github.com/zealtv/loom): planning structured work while developing gremlin

Everything is bash and markdown. Simplicity, clarity, and extensibility are the guiding principles.


## Sandboxing

The protocol does not enforce a sandbox. Host a gremlin where broad shell and
file access is acceptable.

For real isolation, wrap `bin/llm.sh` or `bin/run.sh` with OS or harness controls:
a separate UNIX user, container, VM, `sandbox-exec`, `bwrap`, or equivalent.


# More 

User-facing docs live inside the installed gremlin:

- `.gremlin/README.md`
- `.gremlin/docs/protocol.md`
- `.gremlin/docs/composition.md`