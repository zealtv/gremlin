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
  gremlin               # user-facing wrapper
  transcript.md         # append-only conversation log
  transcript-archive/   # rotated transcripts
  bin/                  # runner scripts and one-shot bridge implementation
  bridges/              # long-running user/channel bridges
  commands/             # slash commands
  tools/                # bash tools the gremlin can call
  skills/               # markdown procedures
  models/               # model runner presets
  .nest/                # inbound/completed item protocol
  .groundhog/           # scheduled work protocol
```

The host folder is the agent's outside identity and working directory. The
`.gremlin/` folder defines how that agent behaves, and `bin/run.sh` executes
the loops from the host folder rather than from inside `.gremlin/`.

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
./.gremlin/gremlin tui
```

`gremlin say` is the one-shot and scripting surface. It writes one item, waits
for the next assistant turn, and prints it.

## Skills And Tools

A skill is a markdown procedure in `skills/`. Skills have YAML frontmatter with
triggers. `bin/index-skills.sh` builds `skills/INDEX.md`; the tender reads full
skill files only when a trigger matches.

A tool is a bash script in `tools/`. It takes args or stdin, writes stdout, and
uses stderr plus a non-zero exit for errors.

## Models

`bin/llm.sh` selects an alias and runs `models/<alias>.sh`. Alias precedence:

1. `$GREMLIN_MODEL` — per-call override.
2. `.gremlin/.model` — gremlin-wide default, set via `/model <alias>` from the TUI.
3. `default` — built-in fallback.

Each model preset receives the prompt on stdin and writes the reply to stdout.
That keeps the rest of the gremlin independent of the model harness. A preset
does not have to call a model at all; `models/echo.sh` ships as a script-only
example for routers, fixed-response bots, and local rule engines.

Presets run with the host folder as the current working directory. Do not
assume the gremlin is inside a git repository; the intended scope is usually
just the parent folder containing `.gremlin/`.

Configure `models/default.sh` before first use, or add another executable preset
and select it from the TUI with `/model <alias>`.

### Per-item override

When the tender claims an item directory containing a `.model` file, it reads
the single-line alias and exports `GREMLIN_MODEL` for that tend. A scheduled
groundhog item can therefore pick its own preset — a cheap fast one for a daily
summary, a heavier one for a weekly review — without changing the gremlin-wide
`.model`. The convention is gremlin-side: groundhog stays content-opaque and
just delivers the directory; the `.model` file is just a file to it.

## Loops

`gremlin start` backgrounds `bin/run.sh`, which starts two loops:

- `bin/tend-loop.sh`: claims items from `.nest/in/`, appends the user turn,
  calls the model, appends the assistant turn, and completes the item into
  `.nest/out/`.
- `bin/tick-loop.sh`: fires scheduled groundhog items. `message.md` becomes an
  assistant transcript turn; other items move into `.nest/in/` for tending.

Both loops honor `.paused`.

### Tender pidfile

While a model call is in flight, `bin/tend-loop.sh` writes the llm child's
process-group id to `.gremlin/.tending.pid` (atomic via `.tmp` rename) and
runs the preset in its own pgid so a single signal can reach the preset's
children too (curl, jq, model SDKs). The pidfile is removed when the call
returns — clean exit, error, or external kill — by an `EXIT` trap as the
safety net.

If the call exits non-zero **and** the claim has been moved out of
`.nest/in/<x>.tending` (i.e. an outside actor like `/stop` dropped it),
the tender treats this as a clean abort: it does not write an assistant
turn and does not complete the item into `.nest/out/`. The system turn
that announces the abort is the responsibility of whoever moved the
claim, not the tender.

A tender process killed with `SIGKILL` cannot run its trap; the pidfile
is then stale. Treat a pidfile whose pid is not alive as "nothing to
stop" and clean it on next inspection. The pidfile lives next to
`.paused` and follows the same idiom: a single root-level flag observed
by anyone who needs it.

## Transcript

`transcript.md` is append-only markdown. Three turn roles:

```markdown
## user — 2026-04-27T19:42:11Z
hello

## assistant — 2026-04-27T19:42:14Z
hi, what's up?

## system — 2026-04-27T19:43:02Z
⚙️ run: backup.sh ok
```

`user` and `assistant` are the conversational pair — real model exchanges.
`system` is everything else: aborts, scheduled output, errors, future
tool-use traces. The role grammar stays stable; sub-categorisation lives in
the body.

### Body convention

For `system` turns, the first line is `<emoji> <label>: <message>`;
remaining lines are free-form. Vocabulary grows by adding new emoji+label
pairs, never new role headers.

Initial sub-categories:

- `⚙️ run:` — a script ran (scheduled `run.sh` body), or an item was aborted.
- `⚠️ error:` — runtime failure worth surfacing (e.g. `run.sh` exited non-zero).
- `💌 message:` — scheduled `message.md` body emitted by the tender (any flavour: reminder, summary, status — the role is "voice from outside the conversation").

### Authorship

The tender writes the appropriate turn for the item it tended:
`## user —` plus `## assistant —` for model-backed tends, `## system —`
for non-model tends (scheduled `message.md`, `run.sh`).

Outside-the-tender callers write `## system —` directly: slash commands
like `/stop` (`⚙️ run: item aborted`), future bridges with their own
status to surface.

The tick loop does **not** write transcript turns. It routes materialised
groundhog items into `.nest/in/`; the tender dispatches by shape.

### Bridges

Bridges may style `system` turns by emoji prefix (e.g. dimmed, framed,
icon-prefixed). They must not eat or rewrite the body — the emoji+label
is part of the message.

## Data Flow

Every inbound item flows through `.nest/in/`; the tender is the only writer
of transcript turns for tended work, dispatching by item shape.

Interactive message:

```text
bridge -> .nest/in/<item>
       -> tend-loop -> transcript.md (## user — / ## assistant —)
                    -> .nest/out/<archive>
```

Scheduled item (any axis — `message.md`, `instructions.md`, `run.sh`):

```text
.groundhog/schedule/...
  -> .groundhog/out/...
  -> tick-loop -> .nest/in/...
  -> tend-loop -> transcript.md (turn role depends on shape)
              -> .nest/out/<archive>
```

Tend-loop dispatch by shape, checked in order (first match wins):

- Directory with executable `run.sh` → no model. Run the script with the host
  folder as cwd, capture stdout (stderr goes to the runner log). On exit 0
  with non-empty stdout: `## system — ⚙️ run: <stdout>`. On exit 0 with
  empty stdout: no transcript turn (quiet success). On non-zero exit:
  `## system — ⚠️ error: run.sh exited <code>` followed by the last lines of
  stdout. `run.sh` wins over `message.md` when both are present.
- Directory with `run.sh` that is not executable → drop with reason. The
  item named itself a script and is malformed; do not fall through to the
  model.
- Directory with `message.md` (and no `instructions.md`) → no model →
  `## system — 💌 message: <body>`.
- Directory with `instructions.md`, or a file item → model-backed tend →
  `## user —` plus `## assistant —`.
