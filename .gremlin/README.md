# gremlin

A gremlin is a folder you can talk to. This `.gremlin/` directory turns its parent folder into an agent.

The folder that holds `.gremlin/` is the gremlin's workspace — it reads, writes, and runs things there.

## Run

Point the gremlin at a model first. The default preset is `models/default.sh` — edit it for the model CLI you want, or drop in another executable `models/<alias>.sh` and pick it from the TUI with `/model <alias>`.

A preset is just an executable that reads the prompt on stdin and writes a reply on stdout, so it doesn't even have to call an LLM — `models/echo.sh` ships as a script-only example.

Start the gremlin runner from the host folder:

```sh
./.gremlin/gremlin wake
```

The runner backgrounds the tend and schedule loops. Leave it running while you interact with the gremlin.

## Talk

Use the TUI for normal interactive work:

```sh
./.gremlin/gremlin tui
```

The TUI shows transcript history, sends submitted messages into `.nest/in/`, and renders assistant turns as they land in `transcript.md`.

Use `gremlin prompt` for one-shot conversational turns from a shell. Add
`--read-only` when the current turn must inspect and answer without changing
files or external state:

```sh
./.gremlin/gremlin prompt "summarize this folder"
./.gremlin/gremlin prompt --read-only "review this implementation"
./.gremlin/gremlin help
```

Use `/new` at a real session boundary: it starts a clean conversation, files the old one away, and reviews it for anything worth remembering. Use `/discard` for throwaway sessions that should be archived but not reviewed for memory.

## Telegram

The Telegram bridge lets a single Telegram chat talk to the gremlin.

1. In Telegram, create a bot with BotFather and copy the bot token.
2. Get your numeric chat id. One simple option is to message `@myidbot`.
3. From the host folder, create the local config:

```sh
cp ./.gremlin/bridges/telegram/config.example ./.gremlin/bridges/telegram/config
chmod 600 ./.gremlin/bridges/telegram/config
```

4. Edit `config` and set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`.
5. Start the runner and bridge:

```sh
./.gremlin/gremlin wake
./.gremlin/gremlin telegram start
./.gremlin/gremlin telegram status
```

Telegram's `/start` message is passed through as normal text; the gremlin may reply that it does not recognize it. Send a regular message after setup.

More detail: `bridges/telegram/README.md`.

## Verbs

```sh
./.gremlin/gremlin wake      # start the loops
./.gremlin/gremlin sleep     # stop them
./.gremlin/gremlin tend      # work the nest once, now
./.gremlin/gremlin prompt "…" # submit one turn and wait for its response
./.gremlin/gremlin prompt --read-only "…"
./.gremlin/gremlin status    # awake or asleep?
```

`start`, `stop`, `say`, `ask`, and `tell` were replaced by `wake`, `sleep`,
and `prompt`. The old words are gone rather than aliased, and say so when you
use them. Shell commands use the direct surface (`gremlin model fast`,
`gremlin update`); slash syntax belongs to interactive bridges.

## Customize

- `gremlin.md`: identity, personality, purpose, voice.
- `/name`: what this gremlin is called — its own name, not its folder's. Rolled
  from `names/v1.txt` at first start and kept; `/name <new name>` renames it,
  `/name --roll` rolls another. An update never changes it.
- `context/`: the always-loaded broadcast surface; `context/system/` is gremlin-managed.
- `.glean/`: memory workbench for distilled findings; see `.glean/README.md`.
  This and the four primitives below it live at the host root, beside `.gremlin/`
  rather than inside it — they are the repository's, and the gremlin acts on them.
- `.lore/`: durable, dated records kept whole — the library beside Glean's memory; see `.lore/README.md`.
- `.loom/`: durable goals that outlive a turn and human-gated self-edit proposals; see `.loom/README.md`.
- `skills/*.md`: procedures the gremlin can follow.
- `tools/*.sh`: bash tools the gremlin can run.
- `models/*.sh`: model runner presets.
- `commands/*.sh`: slash commands for bridges and scripts.

Run `./.gremlin/gremlin restart` after editing skills so `skills/INDEX.md` is rebuilt. You can also run `.gremlin/bin/index-skills.sh` directly.

## Memory

`.glean/` is the host repository's memory workbench, a sibling of `.gremlin/`: it keeps distilled findings as flat markdown. See `.glean/README.md` for the full layout.

The generated finding catalog is broadcast by default through `context/system/memory.md`. Search or fetch finding bodies when they are relevant, then promote only the small set that should always be fully broadcast by symlinking them into `.gremlin/context/`:

```sh
ln -s ../../.glean/findings/<id>.md ./.gremlin/context/<id>.md
```

`models/memory.sh` is the default review model alias for memory-review work. It is intentionally a thin wrapper around `models/default.sh`, so a fresh gremlin inherits the configured default model unless you choose to specialize memory review later.

## Update

`.gremlin/.upstream` stores the tarball URL used by `/update`.

`/update` overlays `.gremlin/` and nothing else. The primitives at the host
root are outside its target entirely, so an update cannot touch your nest,
loom, lore, glean or groundhog — that is a property of where they live, not of
an exclude list. It does not install or repair a primitive either; `doctor`
reports a missing one with that project's install command, and
`bin/install-primitives.sh` is there if you want it done for you.

From the TUI, run:

```text
/update
```

From a script or shell:

```sh
./.gremlin/gremlin update
```

`/update` refreshes the shared machinery and leaves everything that's *yours* untouched — your identity, context, transcripts, queues, schedules, memory, and settings (`.upstream`, `.model`, `.paused`). Afterwards it runs `gremlin doctor` to restore any managed `context/system/` links.


## Developing

Keep personal state out of this repo.

- Run and personalize a copy outside the repo.
- Never run `prompt` or the TUI against the repo's reference `.gremlin/`.
- Promote personal-copy ideas back by rewriting generic versions in canonical.
- Use `.nest/README.md` and `.groundhog/README.md` to
  understand the nested protocols.

Before pushing:

- `git status` shows only intended changes.
- `.gremlin/transcript.md` is empty.
- `.nest/in/`, `.groundhog/out/`, and `.groundhog/fired/` contain only
  placeholder files.
- `.loom/threads/`, `.loom/tied/`, and `.loom/dropped/` contain
  only placeholder files.
- `.gremlin/context/` contains no personal facts.
- `.gremlin/gremlin.md` is generic.
- No `.env`, API keys, bridge configs, or personal metadata are tracked.



## More

- `docs/protocol.md`: layout, loops, transcript, skills, tools, models, and data
  flow.
- `docs/composition.md`: multiple gremlins, delegation, shared context,
  sandboxing, and extensions.
- `.nest/README.md`: the nestling inbox/claim/complete protocol.
- `.groundhog/README.md`: the schedule/tick protocol.
- `.glean/README.md`: the glean memory protocol.
- `.lore/README.md`: the lore protocol for durable, dated records.
- `.loom/README.md`: the loom protocol for goals that outlive a turn.
