# gremlin

A gremlin is a folder you can talk to. This `.gremlin/` directory turns its parent folder into an agent.

The folder that holds `.gremlin/` is the gremlin's workspace — it reads, writes, and runs things there.

## Run

Point the gremlin at a model first. The default preset is `models/default.sh` — edit it for the model CLI you want, or drop in another executable `models/<alias>.sh` and pick it from the TUI with `/model <alias>`.

A preset is just an executable that reads the prompt on stdin and writes a reply on stdout, so it doesn't even have to call an LLM — `models/echo.sh` ships as a script-only example.

Start the gremlin runner from the host folder:

```sh
./.gremlin/gremlin start
```

The runner backgrounds the tend and schedule loops. Leave it running while you interact with the gremlin.

## Talk

Use the TUI for normal interactive work:

```sh
./.gremlin/gremlin tui
```

The TUI shows transcript history, sends submitted messages into `.nest/in/`, and renders assistant turns as they land in `transcript.md`.

Use `gremlin say` for one-shot prompts, shell scripts, and direct slash commands:

```sh
./.gremlin/gremlin say "summarize this folder"
./.gremlin/gremlin say /help
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
./.gremlin/gremlin start
./.gremlin/gremlin telegram start
./.gremlin/gremlin telegram status
```

Telegram's `/start` message is passed through as normal text; the gremlin may reply that it does not recognize it. Send a regular message after setup.

More detail: `bridges/telegram/README.md`.

## Customize

- `gremlin.md`: identity, personality, purpose, voice.
- `context/`: the always-loaded broadcast surface; `context/system/` is gremlin-managed.
- `.glean/`: memory workbench for distilled findings; see `.glean/README.md`.
- `.lore/`: durable, dated records kept whole — the library beside Glean's memory; see `.lore/README.md`.
- `.loom/`: durable goals that outlive a turn and human-gated self-edit proposals; see `.loom/README.md`.
- `skills/*.md`: procedures the gremlin can follow.
- `tools/*.sh`: bash tools the gremlin can run.
- `models/*.sh`: model runner presets.
- `commands/*.sh`: slash commands for bridges and scripts.

Run `./.gremlin/gremlin restart` after editing skills so `skills/INDEX.md` is rebuilt. You can also run `.gremlin/bin/index-skills.sh` directly.

## Memory

`.gremlin/.glean/` is the local memory workbench: it keeps distilled findings as flat markdown. See `.glean/README.md` for the full layout.

The generated finding catalog is broadcast by default through `context/system/memory.md`. Search or fetch finding bodies when they are relevant, then promote only the small set that should always be fully broadcast by symlinking them into `.gremlin/context/`:

```sh
ln -s ../.glean/findings/<id>.md ./.gremlin/context/<id>.md
```

`models/memory.sh` is the default review model alias for memory-review work. It is intentionally a thin wrapper around `models/default.sh`, so a fresh gremlin inherits the configured default model unless you choose to specialize memory review later.

## Update

`.gremlin/.upstream` stores the tarball URL used by `/update`.

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
- Never run `say` or the TUI against the repo's reference `.gremlin/`.
- Promote personal-copy ideas back by rewriting generic versions in canonical.
- Use `.gremlin/.nest/README.md` and `.gremlin/.groundhog/README.md` to
  understand the nested protocols.

Before pushing:

- `git status` shows only intended changes.
- `.gremlin/transcript.md` is empty.
- `.gremlin/.nest/in/`, `.gremlin/.groundhog/out/`, and `.gremlin/.groundhog/fired/` contain only
  placeholder files.
- `.gremlin/.loom/threads/`, `.gremlin/.loom/tied/`, and `.gremlin/.loom/dropped/` contain
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
