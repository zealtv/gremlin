# Protocol

This is the single-gremlin mechanics reference.

Gremlin contains two nested protocols worth reading directly:

- `.nest/README.md`: inbound item lifecycle, claims, completion, and sweep.
- `.groundhog/README.md`: schedules, ticks, fired items, and materialized work.

## Layout

```text
.gremlin/
  gremlin.md            # identity: personality, purpose, voice
  context/              # facts loaded into every prompt
  run.sh                # backgrounds the loops
  transcript.md         # append-only conversation log
  transcript-archive/   # rotated transcripts
  bin/                  # runner scripts and one-shot bridge
  bridges/              # long-running user/channel bridges
  commands/             # slash commands
  tools/                # bash tools the gremlin can call
  skills/               # markdown procedures
  models/               # model runner presets
  .nest/                # inbound/completed item protocol
  .groundhog/           # scheduled work protocol
```

The host folder is the agent's outside identity and working directory. The
`.gremlin/` folder defines how that agent behaves, and `run.sh` executes the
loops from the host folder rather than from inside `.gremlin/`.

## Prompt Inputs

The tender builds each prompt from:

1. `gremlin.md`
2. sorted `context/*.md`
3. `skills/INDEX.md`
4. `tools/README.md`
5. `transcript.md`
6. the current item body

Docs are not loaded automatically. Read this file, `README.md`, or
`docs/composition.md` only when the task calls for protocol detail.

## Bridges

Bridges are how the outside world reaches the gremlin.

- Inbound: write items to `.nest/in/`.
- Outbound: tail `transcript.md` for assistant turns.
- Bridges do not call the model or write assistant turns.

The TUI bridge is the normal interactive surface:

```sh
./.gremlin/bridges/tui/tui.sh
```

`bin/say` is the one-shot and scripting surface. It writes one item, waits for
the next assistant turn, and prints it.

## Skills And Tools

A skill is a markdown procedure in `skills/`. Skills have YAML frontmatter with
triggers. `bin/index-skills.sh` builds `skills/INDEX.md`; the tender reads full
skill files only when a trigger matches.

A tool is a bash script in `tools/`. It takes args or stdin, writes stdout, and
uses stderr plus a non-zero exit for errors.

## Models

`bin/llm.sh` reads `.model` or defaults to `default`, then runs
`models/<alias>.sh`.

Each model preset receives the prompt on stdin and writes the reply to stdout.
That keeps the rest of the gremlin independent of the model harness.

Presets run with the host folder as the current working directory. Do not
assume the gremlin is inside a git repository; the intended scope is usually
just the parent folder containing `.gremlin/`.

Configure `models/default.sh` before first use, or add another executable preset
and select it from the TUI with `/model <alias>`.

## Loops

`run.sh` starts two loops:

- `bin/tend-loop.sh`: claims items from `.nest/in/`, appends the user turn,
  calls the model, appends the assistant turn, and completes the item into
  `.nest/out/`.
- `bin/tick-loop.sh`: fires scheduled groundhog items. `message.md` becomes an
  assistant transcript turn; other items move into `.nest/in/` for tending.

Both loops honor `.paused`.

## Transcript

`transcript.md` is append-only markdown:

```markdown
## user — 2026-04-27T19:42:11Z
hello

## assistant — 2026-04-27T19:42:14Z
hi, what's up?
```

The tender owns transcript writes for model-backed turns. Scheduled outbound
messages are appended by `tick-loop.sh`.

## Data Flow

Interactive message:

```text
bridge -> .nest/in/<item>
       -> tend-loop -> transcript.md
                    -> .nest/out/<archive>
```

Scheduled message:

```text
.groundhog/schedule/.../message.md
  -> .groundhog/out/...
  -> tick-loop -> transcript.md
```

Scheduled tending:

```text
.groundhog/schedule/.../instructions.md
  -> .groundhog/out/...
  -> tick-loop -> .nest/in/...
  -> tend-loop -> transcript.md
```
