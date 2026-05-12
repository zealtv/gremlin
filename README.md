# 👀 gremlin

**A gremlin is a folder you can talk to.** Drop `.gremlin/` into any directory and that directory becomes an agent — persistent, scheduleable, and addressable from the TUI, Telegram, or a shell pipe.

No daemon. No database. No framework. No language runtime. Just bash, markdown, and the filesystem. Where OpenClaw and Hermes need Node and bring their own home directory, config DSL, and update story (OpenClaw's update path is famously fiddly), a gremlin is a folder you can `cp -r`, `git diff`, and `mv`.

<!-- TODO: drop a short looping GIF of the TUI here — user message in, assistant reply landing in transcript -->

## Quick start

Install into the current directory:

```sh
curl -fsSL https://raw.githubusercontent.com/zealtv/gremlin/main/install.sh | bash -s
```

Point it at a model. `.gremlin/models/default.sh` is just an executable that reads a prompt on stdin and writes a reply on stdout — edit it for whichever CLI you use (Claude Code, Codex, Open Code, a local model, anything):

```sh
#!/usr/bin/env bash
exec claude -p --model claude-sonnet-4-6 --allowedTools "Bash"
```

Start the runner and open the TUI:

```sh
.gremlin/gremlin start
.gremlin/gremlin tui
```

Run `/help` for commands.

### Talk to it from Telegram

1. Create a bot with `@BotFather` and copy the token.
2. Get your numeric chat id from `@myidbot`.
3. Copy `.gremlin/bridges/telegram/config.example` to `config`, fill in `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`, then `.gremlin/gremlin telegram start`.

## Features

- **The agent is a folder.** Copy it, fork it, version it, delete it. There is no hidden state.
- **Almost no dependencies.** Bash, coreutils, and whatever CLI talks to your model. Updating is `/update` — an overlay that preserves your identity, transcripts, memory, and queues.
- **Bring your own model.** A model preset is just `stdin → stdout`. Swap models with `/model <alias>`. Non-LLM scripts work too.
- **One inbox, many sources.** TUI, Telegram, scheduled ticks, peer gremlins, and `gremlin say` all funnel through `.nest/in/`. One tender loop, one dispatch rule.
- **Composition is adjacency.** Multiple gremlins = multiple folders. Delegation is `mv item ../other/.gremlin/.nest/in/`.
- **Scheduled and persistent.** Background tend + tick loops give you reminders, nightly summaries, and self-initiated work without a separate scheduler.
- **Append-only transcript.** `transcript.md` is the source of truth. Bridges tail it. Debugging is `cat`.
- **Memory you control.** Glean stores findings as flat markdown; the catalog is broadcast by default, bodies are fetched on demand, and selected findings can be promoted into full context with a symlink.
- **Everything is a file.** Skills, tools, commands, model presets, bridges — every extension point is a directory of small scripts or markdown.

## Layout

```
your-folder/
└── .gremlin/
    ├── gremlin.md           identity, personality, voice
    ├── context/             always-loaded context, including managed system/ links
    ├── skills/              markdown procedures with triggers
    ├── tools/               bash tools the gremlin can run
    ├── models/              stdin → stdout model presets
    ├── commands/            slash commands
    ├── bridges/             TUI, Telegram, …
    ├── .nest/               inbox / claimed / completed items
    ├── .groundhog/          scheduled work
    ├── .glean/              memory workbench
    ├── transcript.md        append-only conversation log
    └── gremlin              the executable
```

## More

User-facing docs live inside the installed gremlin:

- `.gremlin/README.md` — full usage guide
- `.gremlin/docs/protocol.md` — loops, transcript, dispatch, models
- `.gremlin/docs/composition.md` — multiple gremlins, delegation, sandboxing

The underlying file-based protocols are vendored and documented on their own:

- 🪺 [nestlings](https://github.com/zealtv/nestlings) — queueing and actioning work
- 🦫 [groundhog](https://github.com/zealtv/groundhog) — scheduling recurring tasks
- 🔮 [glean](https://github.com/zealtv/glean) — memory distillation and retrieval
- 🪡 [loom](https://github.com/zealtv/loom) — planning structured work

## Sandboxing

The protocol does not enforce a sandbox. Host a gremlin where broad shell and file access is acceptable. For real isolation, wrap `.gremlin/bin/llm.sh` with a separate UNIX user, container, VM, `sandbox-exec`, `bwrap`, or equivalent.
