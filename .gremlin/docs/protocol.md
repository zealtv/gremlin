# Protocol

This is the single-gremlin mechanics reference.

Gremlin contains several nested protocols worth reading directly:

- `.nest/README.md`: inbound item lifecycle, claims, completion, and sweep.
- `.groundhog/README.md`: schedules, ticks, fired items, and materialized work.
- `.glean/README.md`: memory workbench, finding contract, and distillation flow.
- `.lore/README.md`: durable, dated records kept whole — the retention sibling to Glean.

## Layout

```text
your-repo/
  AGENTS.md / CLAUDE.md   # the map: generated primitives block + preamble
  .nest/                  # inbound/completed item protocol
  .loom/                  # finite work: threads and stitches
  .lore/                  # durable, dated records: items, generated INDEX
  .glean/                 # memory workbench: inbox, findings, out, dropped
  .groundhog/             # scheduled work protocol
  .gremlin/               # the optional tender
    gremlin.md            # identity: personality, purpose, voice
    context/              # always-loaded broadcast surface
    gremlin               # user-facing wrapper
    transcript.md         # append-only conversation log — private
    transcript-archive/   # rotated transcripts
    bin/                  # runner scripts and one-shot bridge implementation
    bridges/              # long-running user/channel bridges
    commands/             # slash commands
    tools/                # bash tools the gremlin can call
    skills/               # markdown procedures
    models/               # model runner presets
    host/                 # what this gremlin contributes to the host's
                          #   primitives: its scheduled jobs, tend.md, distil.md
```

The host folder is the agent's outside identity and working directory. The
`.gremlin/` folder defines how that agent behaves, and `bin/run.sh` executes
the loops from the host folder rather than from inside `.gremlin/`.

The five primitives are **not** inside `.gremlin/`. They belong to the host
folder, and a human acts on exactly the same files the gremlin does.

## Installation and delivery

`install.sh` lays down `.gremlin/`, then — as a convenience, once — installs
any missing primitive by fetching its repo and running **its own**
`install.sh`, and copies `host/` into place. `GREMLIN_SKIP_PRIMITIVES=1`
installs the tender alone.

After that, gremlin never installs anything. `/update` overlays `.gremlin/`
only; it does not initialise, repair or reach for a primitive, and its exclude
list is down to identity files because there is nothing else of the user's
under the overlay target. A missing primitive is reported by `doctor`, loudly,
with that project's install command, and there is no fallback to a private
copy.

The gremlin's own scheduled work (`weekly reflect`, its dead-man's switch, a
paused weekly curate pass) lives on the **host's** `.groundhog/schedule/`, not
on a private one. Visibility is the point: a human can see the gremlin's
self-care and pause it by renaming the job, like any other. Two host-local
policy files do **not** travel that way, or at all — see "Facts and policy"
below. `bin/install-host-files.sh` installs the jobs, fills gaps and nothing
else.

## Placement

*A primitive installation is a self-named dotdir bundling its script and its
data, living at the root of the host directory whose work it records.*
**`.gremlin/` is one of them.**

A gremlin is the optional tender of a host directory. It sits beside `.nest/`,
`.loom/`, `.lore/`, `.glean/` and `.groundhog/` and acts on them. It does not
contain them, deliver them, or own their data — humans and other tools act on
exactly the same files.

A primitive dotdir found *inside* `.gremlin/` is **legacy placement**: the
shape gremlin shipped before the sibling inversion. `doctor` reports it; the
fix is to hoist it to the host root.

There are no tiers. The three-tier model this replaces said a thing was
canonical-delivered *iff* it lived inside `.gremlin/`, and called a sibling
primitive drift. Both statements are withdrawn:

- The old **Tier 1** (`.gremlin/` bundling the five primitives as a private
  working set) is exactly the legacy placement described above. Primitives are
  installed by their own `install.sh`, not delivered by gremlin, and `/update`
  never overlays them because they are no longer inside its target.
- The old **Tier 2** (`.dash/`, `library/` and similar gremlin-produced
  artifacts at the host root) is unchanged in behaviour and no longer a tier —
  those dirs were already host-root siblings and now simply sit among peers.
  `.dash` is still content rather than a primitive: it carries no script.
- The old **Tier 3** (the same primitive tools installed at a broader host)
  disappears, because there is no higher scope to distinguish. A gremlin whose
  host dir is a fleet root or a workspace repo is just a gremlin; its
  primitives are its host's primitives, like anyone else's.

A primitive is missing, not vendored: if a gremlin needs `.loom/` and the host
has none, `doctor` fails loudly with that primitive's own install command.
There is no fallback to a private copy.

## Verbs

```
wake     start the loops                    sleep    stop them
tend     work the nest once, now            status   awake or asleep?
prompt   submit one turn and wait for its response
```

Plus `restart`, `tui`, `help`, every `commands/<name>.sh` as `/name`, and every
bridge by its own name.

**`prompt` is the one-shot conversational verb.** It accepts either a question
or an instruction, writes one nest item, waits for the next assistant turn,
and prints its body. `prompt --read-only` adds a contract at the end of the
assembled model prompt for that turn: inspect and answer, but do not change
files or external state. This is prompt guidance, not an enforced sandbox;
the selected model harness still determines which tools are technically
available.

Slash commands are not prompts. Interactive bridges dispatch `/name`,
`/update`, and their peers through `bin/slash.sh`; shell callers use the direct
wrapper surface (`gremlin name`, `gremlin update`).

**`wake` is the daemon, not a task.** It backgrounds `bin/run.sh` exactly as
`start` did; `sleep` stops it. The per-task shape the brain dump gestured at —
wake, do the thing, sleep — is `tend`: one pass over `.nest/in/` right now, in
the foreground, whether or not the gremlin is awake. Making `tend` addressable
is the real gain here; it was internal (`bin/tend-loop.sh`) and unreachable
before.

**The old verbs are gone, not aliased.** `start`, `stop`, `say`, `ask`, and
`tell` fail with the new name and a non-zero exit. Deliberately loud rather than silently
forwarding, for one concrete reason: `commands/stop.sh` exists — `/stop` aborts
an in-flight model call — so a `stop` left to fall through to the command
dispatcher would quietly do something *different* from what muscle memory
expects. A verb that changed meaning is worse than a verb that is gone.

## Names

A gremlin has a name of its own, held in `.gremlin/name`:

```
name=snallygaster
source=generated        # or custom, once a human has named it
vocabulary=1            # which names/vN.txt it was drawn from
```

It is **rolled once, at first `doctor` run, and persisted** — never derived
from the host path. Deriving would rename a gremlin the moment it was moved,
and a gremlin is a folder you can `mv`. `/name <new name>` changes it and
records `source=custom`, so a later roll cannot quietly undo a human's choice.
`/update` excludes `/name` and `/identity.md`: an update must never rename
anyone.

The deliberate consequence of persisting rather than deriving: **`cp -r`
produces a twin with the same name.** The copy is the same gremlin until you
say otherwise — right when you meant to clone one, and fixed with
`/name --roll` when you meant to make a new one.

`doctor` generates `identity.md` from the name and broadcasts it through
`context/system/identity.md`, so the gremlin knows what it is called and can
sign with it. The web bridge's header is now the gremlin's name and the machine
it runs on; the repository it tends moved to the tooltip, because those are two
different things — before names, `name@host` was really `folder@machine`.

The vocabulary is `names/v1.txt`, a pinned local wordlist of single-word mythic
creatures, not a dependency: an external name package could rename an
installation when it updated. Add to it freely; never edit a line in place, and
start `v2.txt` when the character of the list changes. Because names are
persisted, growing the vocabulary can never rename an existing gremlin.

## Facts and policy

A gremlin may generate **facts** about its host. It does not author **policy**
for it.

- *Facts* are things true of the folder that can be read off disk: which
  primitives are installed, where to start reading. `AGENTS.md`'s generated
  block is facts, which is why gremlin maintains it and regenerates it on every
  `doctor` run.
- *Policy* is what this repository wants: how arrivals should be routed
  (`.nest/tend.md`), what is worth remembering (`.glean/distil.md`). Both files
  belong to whoever owns the repository. Each primitive ships its own neutral
  starting point; gremlin ships neither, overwrites neither, and reads both.

`doctor` reports when one of those files is still its primitive's untouched
starting point, and says what a gremlin would like to find there. That is the
whole of gremlin's involvement: noticing, not writing.

This is the placement law applied to file *contents* rather than file
locations, and it settles a question the vendored layout used to hide. When
`.nest/` lived inside `.gremlin/`, gremlin authoring `tend.md` was
unremarkable — it was writing in its own folder. At the host root it is writing
in someone else's. Two symptoms made the case: the shipped `tend.md` was a
prose description of `bin/tend-loop.sh`, kept in a second file that nothing
verified and that could only ever be redundant or wrong; and the shipped
`distil.md` was mostly generic glean mechanics, which belong in
`skills/distil.md` where the model already reads them.

## The map

`AGENTS.md` at the host root is how a cold agent — of any runtime, not just
this one — learns the shape of the repository. Its primitives section is
**derived, not hand-maintained**: `bin/index-primitives.sh` rewrites the block
between its markers from what is actually installed on disk, and `doctor` runs
it. Everything outside the markers is hand-written and never touched, so the
file is a generated index with a human preamble.

`CLAUDE.md` is a symlink to `AGENTS.md`, created only when nothing of that name
exists. `AGENTS.md` is the runtime-agnostic name and matches the family's
model-agnostic stance; a real hand-written `CLAUDE.md` is left alone and told
about, never clobbered. Two copies of a map drift; a symlink cannot.

The same list is written into `.gremlin/PRIMITIVES.md` and broadcast to the
gremlin through `context/system/primitives.md`, so the tender and the human
read the same map from the same source.

## Prompt Inputs

The tender builds each prompt from:

1. `gremlin.md`
2. sorted `context/system/*.md` symlinks
3. sorted top-level `context/*.md`
4. `transcript.md`
5. the current item body

`context/` is the always-loaded broadcast surface. `context/system/` is the
gremlin-managed part of that surface: entries are symlinks by convention, and
the tender reads only symlinked `.md` entries there, so real files such as
`context/system/README.md` are ignored. `gremlin doctor` creates or restores the
managed symlinks for skills, tools, memory, and turn-taking.

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

`gremlin prompt` is the one-shot and scripting surface. It writes one item,
waits for the next assistant turn, and prints it. It has no reply correlation
identifier: if concurrent work appends another assistant turn first, that turn
is what the waiting process sees.

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

`models/memory.sh` is the conventional alias for memory-review work. It ships as
a thin wrapper around `default.sh`; customize it only when memory review should
use a different model or harness from ordinary conversation.

### Per-item override

When the tender claims an item directory containing a `.model` file, it reads
the single-line alias and exports `GREMLIN_MODEL` for that tend. A scheduled
groundhog item can therefore pick its own preset — a cheap fast one for a daily
summary, a heavier one for a weekly review — without changing the gremlin-wide
`.model`. The convention is gremlin-side: groundhog stays content-opaque and
just delivers the directory; the `.model` file is just a file to it.

Memory review items use the same mechanism by writing `memory` into `.model`.

## Memory

`.glean/` is the host repository’s Glean workbench, which the gremlin reads and writes but does not own:

- `in/` receives deliberate raw packets for distillation.
- `findings/` holds flat markdown findings and generated `INDEX.md`.
- `out/` holds considered inbox items until swept.
- `dropped/` holds retired findings and reason files.
- `distil.md` is the host-local brief for deciding what deserves memory.

Glean's generated `findings/INDEX.md` is broadcast by default through
`context/system/memory.md`. Finding bodies stay in Glean and are fetched on
demand. Promote a full finding by symlinking it into top-level `context/`;
demote it by removing the symlink while leaving the finding in Glean.

## Loops

`gremlin wake` backgrounds `bin/run.sh`, which starts two loops:

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

Before each pass, Gremlin asks canonical Nestlings for claims older than its
stale threshold. This discovery is read-only. Gremlin resolves those claims
only when the pidfile does not identify a live tender process group; Nestlings
then retries explicitly marked directories within its attempt limit or drops
them fail-closed. Liveness and model-failure detection remain Gremlin policy,
while retry and drop transitions remain canonical Nestlings protocol.

### /stop

`/stop` is the user-visible abort: it reads `.tending.pid`, signals the pgid
(TERM, then KILL after a short grace), moves the active `.nest/in/*.tending`
claim into `.nest/dropped/<x>` with a reason file, appends a
`## system — ✋ item aborted` turn, and removes the pidfile. The tender's
abort branch then sees the missing claim and exits cleanly without a
phantom assistant turn. `/stop` is idempotent: a missing pidfile prints
"nothing to stop"; a stale pidfile is cleaned and any orphaned `.tending`
claim is dropped.

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

- `⚙️ run:` — a script ran (scheduled `run.sh` body).
- `⚠️ error:` — runtime failure worth surfacing. Known shapes: `run.sh exited
  <code>` (with optional tail of stdout), `empty model reply` (the preset
  exited 0 with no stdout — surfaced loudly so bridges have something to push
  instead of a silent empty `## assistant —`).
- `💌 message:` — scheduled `message.md` body emitted by the tender (any flavour: reminder, summary, status — the role is "voice from outside the conversation").
- `✋ item aborted` — `/stop` cancelled the in-flight model call. Terse fixed-form line; no message tail.

### Authorship

The tender writes the appropriate turn for the item it tended:
`## user —` plus `## assistant —` for model-backed tends, `## system —`
for non-model tends (scheduled `message.md`, `run.sh`).

A model-backed tend can decline to write a turn at all: a reply of exactly
`<silent>` is a **stated sentinel** meaning *the gremlin chose not to speak*.
The tender completes the item into `.nest/out/` but writes no `## assistant —`
turn. This is the deliberate opposite of the loud `⚠️ error: empty model reply`
above: silence is stated, an empty reply is an accident, and the two stay
distinct so empties still surface preset/auth failures. The gremlin learns the
sentinel from `context/system/turntaking.md`.

Outside-the-tender callers write `## system —` directly: slash commands
like `/stop` (`⚙️ run: item aborted`), future bridges with their own
status to surface.

The tick loop does **not** write transcript turns. It routes materialised
groundhog items into `.nest/in/`; the tender dispatches by shape.

### Bridges

Bridges may style `system` turns by emoji prefix (e.g. dimmed, framed,
icon-prefixed). They must not eat or rewrite the body — the emoji+label
is part of the message.

A turn body may also carry **media embeds** a media-capable bridge renders into
native attachments, stripping the markup from the surrounding text:

- `🖼️ [caption](path-or-url)` — an image, sent as a photo. (`![caption](path-or-url)`
  is accepted as a silent back-compat alias.)
- `📎 [caption](path-or-url)` — a file, sent as a native document.
- `🔊 [text-to-speak](tts:)` — speech, synthesized at send time and sent as a
  voice message. The transcript stays text: the `(tts:)` markup is the source of
  truth, audio is generated on the way out and not stored, so the one-writer and
  git-diffable transcript stay intact. A bridge that cannot render an embed
  leaves the markup as plain text.

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

## Work That Outlives A Turn

A single tend is short by design. Long or recurring work is expressed as *many*
short tends, not one long-running process — turns multiply, the turn does not
lengthen. There is one writer (the tender) and one inbound arrow
(`tend → .nest/in/`); progress is just the reply of each step — a real turn the
bridges already fan out, not a side-channel. Two rhythms:

**Immediate continuation.** A tend does one bounded step, replies with what it
did and what is next, then re-queues itself by writing a fresh item into its own
`.nest/in/` via `tools/continue.sh "<next step>"`. The next tend picks it up.
Stop by replying without re-queuing. This is self-delegation: the inbox arrow
from `docs/composition.md`, pointed at self. See `skills/long-task.md`.

**Clock-paced goals.** A goal that should wake on a schedule is a groundhog
`every/<N>m/<slug>/` item; each firing is one bounded tend.

*Quiet by default is the `run.sh` gate.* A model-backed (`instructions.md`) goal
emits a pushed `## assistant` turn on every firing — inherently chatty. To stay
quiet, use the executable-`run.sh` shape: the clock drives a cheap silent check
that prints nothing on a no-change tick (→ no turn, no push, no model cost), and
prints a line — or escalates to a model tend via `tools/continue.sh` — only on a
real milestone. Cadence is milestones, not the clock.

*Termination is the author's job.* There is no kernel guard against a runaway
chain or an undisarmed schedule — a guard would be a framework. A goal disarms
itself with `.groundhog/groundhog.sh drop <slug>` (or by renaming its schedule
path to `.paused`). Back every standing `every/<N>m/<goal>` with a
`once/<YYYY-MM-DD>/<goal>-expire/` one-shot whose `run.sh` drops the goal — a
dead-man's switch that fires even if the goal never reaches its own done
condition. `/stop` and `.paused` remain the human backstop.

*Path resolution in a scheduled `run.sh` must be depth-independent.* Groundhog
materialises every item to `.nest/in/<name>/` regardless of its schedule depth,
so a `run.sh` cannot count `../` segments to find `.gremlin`. Walk up to the
directory that contains `.nest`:

```sh
GREMLIN_DIR="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; \
  while [ "$d" != / ] && [ ! -d "$d/.nest" ]; do d="$(dirname "$d")"; done; \
  printf %s "$d")"
```

### The binding constraint

The in-flight model child must never append to `transcript.md`. The tender is
the sole transcript writer; a scheduled `run.sh` reports by writing to *stdout*,
which the tender turns into a `## system — ⚙️ run:` turn. This is why long work
speaks *between* tends, where the tender is already the only writer — never from
inside a running model call.
