# 👀 gremlin

A gremlin is a folder you can talk to.

Install one into the current directory:

```sh
curl -fsSL https://raw.githubusercontent.com/zealtv/gremlin/main/install.sh | bash -s
```

## Quick Start

Configure a model preset before starting. The default preset is
`.gremlin/models/default.sh`; edit it to match the model CLI you want to use, or
drop another executable preset into `.gremlin/models/` and select it from the
TUI with `/model <alias>`.

The gremlin's working directory is the parent folder that contains `.gremlin/`.
The runner `cd`s there before tending, so model CLIs and tools should treat
that host folder as the normal workspace scope.

Start the runner:

```sh
./.gremlin/gremlin start
```

Open the TUI:

```sh
./.gremlin/gremlin tui
```

Use the TUI for normal interactive work.

Then customize the installed gremlin:

- `.gremlin/gremlin.md`: identity, personality, purpose, voice.
- `.gremlin/context/`: facts loaded into every prompt.
- `.gremlin/skills/`: markdown procedures.
- `.gremlin/tools/`: bash tools.
- `.gremlin/models/`: model runner presets.

More user-facing docs live inside the installed gremlin:

- `.gremlin/README.md`
- `.gremlin/docs/protocol.md`
- `.gremlin/docs/composition.md`
- `.gremlin/.nest/README.md`
- `.gremlin/.groundhog/README.md`

## Principle

The folder is the agent.

- Inbound messages become files in `.gremlin/.nest/in/`.
- The tender reads identity, context, skills, tools, transcript, and the item.
- Replies append to `.gremlin/transcript.md`.
- Bridges write inbound items and tail transcript output.
- Groundhog provides scheduled messages and recurring tasks.
- Tools are bash scripts. Skills are markdown procedures.

No database, no queue, no daemon coordination. Files and atomic moves.

## Repository Shape

This repo dogfoods one canonical gremlin at `.gremlin/`. Do not run personal
work against that reference gremlin. Copy or install it into another host folder
first.

For local development copies:

```sh
mkdir -p ~/Desktop/mygremlin
cp -R .gremlin ~/Desktop/mygremlin/.gremlin
```

The installed `.gremlin/.upstream` points at the public canonical tarball.
`/update` overlays canonical files while preserving identity, context,
transcripts, queues, schedules, `.upstream`, `.model`, and `.paused`.

To test local canonical changes through `/update`, point a personal copy at a
local tarball:

```sh
echo 'file:///tmp/gremlin.tar.gz' > ~/Desktop/mygremlin/.gremlin/.upstream
( cd ~/repos && tar -czf /tmp/gremlin.tar.gz gremlin/.gremlin )
```

Then run `/update` from the TUI, or:

```sh
cd ~/Desktop/mygremlin
./.gremlin/gremlin update
```

## Developing

Keep personal state out of this repo.

- Develop canonical files under `~/repos/gremlin/.gremlin/`.
- Run and personalize a copy outside the repo.
- Never run `say` or the TUI against the repo's reference `.gremlin/`.
- Promote personal-copy ideas back by rewriting generic versions in canonical.
- Use `.gremlin/.nest/README.md`, `.gremlin/.groundhog/README.md`, and
  `.loom/README.md` to understand the nested protocols.
- Use `.loom/threads/` for planned work; current and future items belong there.

Before pushing:

- `git status` shows only intended changes.
- `.gremlin/transcript.md` is empty.
- `.gremlin/.nest/in/`, `.groundhog/out/`, and `.groundhog/fired/` contain only
  placeholder files.
- `.gremlin/context/` contains no personal facts.
- `.gremlin/gremlin.md` is generic.
- No `.env`, API keys, bridge configs, or personal metadata are tracked.

## Sandboxing

The protocol does not enforce a sandbox. Host a gremlin where broad shell and
file access is acceptable.

For real isolation, wrap `bin/llm.sh` or `bin/run.sh` with OS or harness controls:
a separate UNIX user, container, VM, `sandbox-exec`, `bwrap`, or equivalent.
