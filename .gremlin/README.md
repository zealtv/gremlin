# gremlin

A gremlin is a folder you can talk to. This `.gremlin/` directory turns its
parent folder into an agent.

The parent folder that contains `.gremlin/` is also the gremlin's working
directory. `run.sh` changes into that host folder before invoking the loops and
model preset, so tools and model CLIs should treat it as the normal workspace
scope.

## Run

Configure a model preset first. The default preset is `models/default.sh`; edit
it for the model CLI you want to use, or add another executable
`models/<alias>.sh` and select it from the TUI with `/model <alias>`.

Start the gremlin runner from the host folder:

```sh
./.gremlin/run.sh
```

The runner backgrounds the tend and schedule loops. Leave it running while you
interact with the gremlin.

## Talk

Use the TUI for normal interactive work:

```sh
./.gremlin/bridges/tui/tui.sh
```

Run it in a second terminal beside `run.sh`. The TUI shows transcript history,
sends submitted messages into `.nest/in/`, and renders assistant turns as they
land in `transcript.md`.

Use `bin/say` for one-shot prompts, shell scripts, and direct slash commands:

```sh
./.gremlin/bin/say "summarize this folder"
./.gremlin/bin/say /help
```

## Customize

- `gremlin.md`: identity, personality, purpose, voice.
- `context/*.md`: facts loaded into every prompt.
- `skills/*.md`: procedures the gremlin can follow.
- `tools/*.sh`: bash tools the gremlin can run.
- `models/*.sh`: model runner presets.
- `commands/*.sh`: slash commands for bridges and scripts.

Run `./.gremlin/run.sh` again after editing skills so `skills/INDEX.md` is
rebuilt. You can also run `.gremlin/bin/index-skills.sh` directly.

## Update

`.gremlin/.upstream` stores the tarball URL used by `/update`.

From the TUI, run:

```text
/update
```

From a script or shell:

```sh
./.gremlin/bin/say /update
```

`/update` overlays canonical files while preserving identity, context,
transcripts, queues, schedules, `.upstream`, `.model`, and `.paused`.

## More

- `docs/protocol.md`: layout, loops, transcript, skills, tools, models, and data
  flow.
- `docs/composition.md`: multiple gremlins, delegation, shared context,
  sandboxing, and extensions.
- `.nest/README.md`: the nestling inbox/claim/complete protocol.
- `.groundhog/README.md`: the schedule/tick protocol.
