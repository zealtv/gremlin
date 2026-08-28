# 👀 gremlin

**A gremlin is a folder you can talk to.** Drop `.gremlin/` into any directory and that directory becomes an agent — persistent, scheduleable, and addressable from the TUI, Telegram, or a shell pipe.

No daemon. No database. No framework. No language runtime. Just bash, markdown, and the filesystem. A gremlin is a folder you can `cp -r`, `git diff`, and `mv`.

<!-- TODO: drop a short looping GIF of the TUI here — user message in, assistant reply landing in transcript -->

## Quick start

Install into the current directory:

```sh
curl -fsSL https://raw.githubusercontent.com/zealtv/gremlin/main/install.sh | bash -s
```

That lays down `.gremlin/` and, because a gremlin with no nest cannot be
tended, installs any of the five primitives you are missing by running each
project's own installer — once, at install time. After that gremlin never
touches them: `/update` overlays `.gremlin/` alone, and `doctor` reports a
missing primitive rather than reaching for a private copy. Add
`GREMLIN_SKIP_PRIMITIVES=1` to install the tender by itself.

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
- **Almost no dependencies.** Bash, coreutils, and whatever CLI talks to your model. Updating is `/update` — an overlay that preserves your identity, model presets, transcripts, memory, and queues.
- **Bring your own model.** A model preset is just `stdin → stdout`. Swap models with `/model <alias>`. Non-LLM scripts work too.
- **One inbox, many sources.** TUI, Telegram, scheduled ticks, peer gremlins, and `gremlin say` all funnel through `.nest/in/`. One tender loop, one dispatch rule.
- **Composition is adjacency.** Multiple gremlins = multiple folders. Delegation is `mv item ../other/.nest/in/`.
- **Scheduled and persistent.** Background tend + tick loops give you reminders, nightly summaries, and self-initiated work without a separate scheduler.
- **Append-only transcript.** `transcript.md` is the source of truth. Bridges tail it. Debugging is `cat`.
- **Memory you control.** Glean stores findings as flat markdown; the catalog is broadcast by default, bodies are fetched on demand, and selected findings can be promoted into full context with a symlink.
- **A library, not just memory.** Lore keeps complete, dated records — specs, decisions, transcripts — whole and findable, durable and dark by default: the append-and-keep sibling to Glean's revisable memory.
- **Everything is a file.** Skills, tools, commands, model presets, bridges — every extension point is a directory of small scripts or markdown.

## Layout

```
your-repo/
├── AGENTS.md               the map: generated primitives block + your preamble
├── CLAUDE.md               symlink to AGENTS.md, for runtimes that look for it
├── .nest/                  inbox / claimed / completed items
├── .loom/                  finite work: threads and stitches
├── .lore/                  durable, dated records
├── .glean/                 memory workbench
├── .groundhog/             scheduled work
└── .gremlin/               the optional tender
    ├── gremlin.md          identity, personality, voice
    ├── context/            always-loaded context, including managed system/ links
    ├── skills/             markdown procedures with triggers
    ├── tools/              bash tools the gremlin can run
    ├── models/             stdin → stdout model presets
    ├── commands/           slash commands
    ├── bridges/            TUI, Telegram, web
    ├── transcript.md       append-only conversation log — private
    └── gremlin             the executable
```

The five primitives live at the host root, not inside `.gremlin/`. A gremlin
is the optional tender of a folder: it sits beside them and acts on them, the
same files a human acts on. A primitive dotdir still inside `.gremlin/` is
legacy placement — `gremlin doctor` says so.

### The map is generated

`.gremlin/bin/index-primitives.sh` writes the primitives section of the host's
`AGENTS.md` between markers, from what is installed on disk — a reading order,
what each dotdir owns, and one line per primitive taken from its own README.
Prose outside the markers is yours and is never touched. `gremlin doctor` runs
the generator, so the map cannot rot; it also works on a repository with no
gremlin at all:

```sh
.gremlin/bin/index-primitives.sh [host-dir]
```

### Migrating an existing gremlin

A gremlin installed before the primitives moved out carries them inside
`.gremlin/`. `hoist-primitives.sh` moves them to the host root, data intact,
and leaves a relative symlink behind so nothing breaks mid-migration:

```sh
./hoist-primitives.sh --dry-run <host-dir>   # print exactly what would move
./hoist-primitives.sh          <host-dir>    # move it
./hoist-primitives.sh --revert <host-dir>    # put it all back
```

It merges rather than clobbers when the host root already has a primitive of
its own, and refuses the whole run — moving nothing — if the two sides hold
different files at the same path. Where the host is a git repository it moves
with `git mv`, so history follows.

The script is a one-time migration, so it ships beside `install.sh` rather
than inside the delivered bundle: it never rides `/update`. Run `/update` on
the host **first** — a gremlin whose `update.sh` predates the wholesale
primitive excludes would be silently un-migrated by its next update, and the
script refuses to touch one.

## More

User-facing docs live inside the installed gremlin:

- `.gremlin/README.md` — full usage guide
- `.gremlin/docs/protocol.md` — loops, transcript, dispatch, models
- `.gremlin/docs/composition.md` — multiple gremlins, delegation, sandboxing

The underlying file-based protocols are separate installs, siblings of
`.gremlin/` rather than parts of it, and documented on their own:

- 🪺 [nestlings](https://github.com/zealtv/nestlings) — queueing and actioning work
- 🦫 [groundhog](https://github.com/zealtv/groundhog) — scheduling recurring tasks
- 🔮 [glean](https://github.com/zealtv/glean) — memory distillation and retrieval
- 🐉 [lore](https://github.com/zealtv/lore) — durable, dated reference and record
- 🪡 [loom](https://github.com/zealtv/loom) — planning structured work

## Sandboxing

The protocol does not enforce a sandbox. Host a gremlin where broad shell and file access is acceptable. For real isolation, wrap `.gremlin/bin/llm.sh` with a separate UNIX user, container, VM, `sandbox-exec`, `bwrap`, or equivalent.
