# 👀 gremlin

A gremlin is a folder you can talk to.

Drop a dot folder into any working directory and that directory now has an agent in it. Drop another dot folder next to the first and you have two agents. There is no supervisor, no canopy, no registry — composition is adjacency.

Built on `nestlings`, `groundhog`, and `loom`. LLM-agnostic by construction: nothing in the layout depends on which model runs the tender.

## Principle

The folder *is* the agent.

- An incoming message becomes a file in `.<name>/.nest/in/`.
- The tender reads `tend.md` and `transcript.md`, replies into `.nest/out/`.
- A bridge ships items between the outside world and the nest.
- A groundhog provides scheduled messages and recurring tasks.
- Tools are bash scripts. Skills are markdown procedures.

No database, no queue, no MCP, no daemon coordination. Files and atomic moves.

## A gremlin is a dot folder

Each gremlin is a single self-contained directory whose name starts with `.`. The dot is the convention: it marks the folder as a system folder, the way `.git/` and `.nest/` do. The folder name *is* the gremlin's name.

```
some-working-directory/
  ...your real files...
  .scribe/              # one gremlin
  .scout/               # another gremlin, same parent
```

Each gremlin runs its own loops. Each has its own bot, its own nest, its own groundhog, its own transcript, its own tools and skills. Two gremlins in the same parent see each other through the file system — delegation is `mv item ../.scout/.nest/in/`.

There is no enforced "shared/" folder. If two gremlins want to share a tool, symlink it. If you want a global library, keep it in `~/.config/gremlin/` and symlink from there. The protocol is silent on where shared things live.

## Single gremlin layout (canonical)

```
.scribe/
  run.sh                # backgrounds the loops; traps SIGINT
  say                   # local CLI bridge: write a message, get a reply
  tend.md               # identity, scope, voice
  transcript.md         # append-only conversation log
  transcript-archive/   # rotated transcripts
  bin/
    tend-loop.sh        # the agent loop
    tick-loop.sh        # groundhog tick → route items
    llm.sh              # the only LLM-specific code
    archive.sh          # rotate transcript safely
    index-skills.sh     # build skills/INDEX.md from frontmatter
  tools/
    README.md           # the tool menu
    <tool>.sh           # owned tools
  skills/
    INDEX.md            # generated index of triggers
    <skill>.md          # one procedure per file
  .nest/
    nestling.sh
    in/ out/ dropped/
  .groundhog/
    groundhog.sh
    schedule/ out/ fired/
```

The top of `.scribe/` holds only what isn't owned by a nested protocol: the runner, the bridges, conversation state, and the libraries.

## The seams

A gremlin has four small surfaces. Everything else is internals.

### Bridges (how the world reaches the gremlin)

A bridge moves bytes between the outside world and `.nest/`. Inbound bridges write into `.nest/in/`; outbound bridges read from `.nest/out/`. Bridges know nothing about the LLM, prompts, or skills.

The MVP ships one bridge: a local CLI named `say`. It writes your message into `.nest/in/`, then waits for a reply to appear in `.nest/out/` and prints it. Synchronous from your side, async from the gremlin's.

Telegram, Discord, email, web — all later additions, each just another script that talks to the same two folders. Swap the bridge, the gremlin doesn't notice.

### Tools (`tools/<name>.sh`)

A tool is a bash script that takes args (or stdin) and writes text to stdout. Errors go to stderr with a non-zero exit. That's the whole interface. Pure functions of args → stdout; state lives in nests and transcripts.

`tools/README.md` is the menu the tender reads. The runner invokes the tender with `--allowedTools "Bash(./tools/*)"` (or the LLM equivalent) so the agent never gets unrestricted shell.

### Skills (`skills/<name>.md`)

A skill is a plain markdown file describing a procedure. Skills are LLM-agnostic — any model that reads markdown can use them. They are loaded into the prompt, not into a harness.

Each skill has YAML frontmatter declaring when it applies:

```markdown
---
name: remind-me
triggers:
  - user asks to be reminded of something at a future time
---

# remind-me

When the user asks to be reminded, write a file at:
.groundhog/schedule/once/<YYYY-MM-DD>/<slug>/message.md
...
```

`bin/index-skills.sh` walks `skills/*.md` and builds `skills/INDEX.md` — a list of triggers plus inlined `triggers: [always]` skills (identity, reply style, refusal policy). The tender's prompt always includes `INDEX.md` and reads individual skill files when a trigger matches.

Tool vs skill: **tool = script you run, skill = procedure you follow.**

### The LLM seam (`bin/llm.sh`)

One file hides everything LLM-specific. `llm.sh "<prompt>"` reads stdin or args, calls whichever model CLI is wired up, prints the reply on stdout. Swap models by editing this one file. Everything else — bridges, nests, skills, tools, transcript — stays the same.

## The loops

Each loop is a single shell script. They never call each other; they share the file system.

### `bin/tend-loop.sh` (~5s cadence)

1. List ready items via `.nest/nestling.sh list`; bail if empty.
2. Claim the oldest item.
3. Build the prompt: `tend.md` + `skills/INDEX.md` + `tools/README.md` + `transcript.md` + the item.
4. Pipe to `bin/llm.sh`; capture reply.
5. Write reply to `.nest/out/<timestamp>.md` via `.landing` rename.
6. Append `## assistant — <iso8601>\n<reply>\n\n` to `transcript.md`.
7. Complete the claimed item.

### `bin/tick-loop.sh` (~60s cadence)

1. `.groundhog/groundhog.sh tick`.
2. For each item in `.groundhog/out/`:
   - If it contains `message.md`: `mv` that into `.nest/out/<timestamp>.md` (scheduled outbound — no agent invocation).
   - Otherwise: `mv` the item directory into `.nest/in/` (scheduled work for the tender).

### `run.sh`

Backgrounds each loop, `trap 'kill 0' INT TERM`, `wait`. Runs the indexer at startup. Honours a `.paused` flag — loops idle when present so you can archive cleanly.

## Files

### `tend.md`

One paragraph telling the tender how to act in this nest. Read on every tend pass.

```markdown
You are the scribe. You take notes for the user and recall them on demand.

Read skills/INDEX.md for the procedures available to you.
Read tools/README.md for the scripts you can run.
Reply briefly.
```

### `transcript.md`

Plain markdown, append-only. Two writers: the inbound bridge (user turns) and `tend-loop.sh` (assistant turns). Each writer does one `>>` append per message; concurrent small appends do not interleave on POSIX.

```markdown
## user — 2026-04-27T19:42:11Z
hello

## assistant — 2026-04-27T19:42:14Z
hi, what's up?
```

### Archive

There is no automatic rotation. To start a fresh session: `bin/archive.sh` touches `.paused`, moves `transcript.md` into `transcript-archive/<date>.md`, drops a fresh empty `transcript.md`, and removes `.paused`. Pending groundhog items survive — they live in `.groundhog/`, untouched.

## Data flow

**You send a message.**
`say` → `.nest/in/` + `transcript.md` → `tend-loop.sh` reads transcript, skills, tools, replies → `.nest/out/` + `transcript.md` → `say` prints the reply.

**Scheduled outbound ("morning ping at 8am").**
`.groundhog/schedule/daily/08/morning/message.md` → `tick-loop.sh` → `.nest/out/` → bridge. No agent invocation.

**Scheduled tending ("brief me at 9am").**
`.groundhog/schedule/daily/09/briefing/instructions.md` → `tick-loop.sh` → `.nest/in/` → `tend-loop.sh` reads instructions, runs tools, replies.

**Self-pacing follow-up.**
Tender, mid-conversation, follows `skills/remind-me.md` and writes `.groundhog/schedule/once/2026-04-28/follow-up/instructions.md`. Surfaces tomorrow as scheduled tending.

## Composition

A second gremlin is `mkdir .scout/`, copy the same skeleton, edit `tend.md`. Start its `run.sh`. Two folders, two loops, one parent directory.

Inter-gremlin delegation is one `mv`: `mv request.md ../.scout/.nest/in/`. The receiver picks it up next tend pass. Replies go to the requester's `in/`, never to one's own `out/` (that's the nestling protocol).

There is no shared state, no shared process, no shared anything. Two gremlins in the same parent are independent agents that happen to share a file system.

## What's foundational, what's an extension

The MVP gives you: a runnable gremlin that converses via local CLI, calls tools, follows skills, fires scheduled work via groundhog, and archives transcripts cleanly.

Extensions slot in without restructuring:

- **Telegram (or any other) bridge** — replace `say` with `bin/bridge-in.sh` + `bin/bridge-out.sh` reading `meta.json`.
- **Attachments** — items in `.nest/in/` and `.nest/out/` become directories. The protocol already accepts both.
- **Voice (whisper in, TTS out)** — a transcribe tool runs pre-tend; a TTS tool produces `voice.ogg` next to `message.md`.
- **A second gremlin** — `mkdir`. Maybe a delegate skill.
- **Shared libraries** — symlinks. No protocol change.

## Why this composes

- **Bridges are dumb.** They translate bytes between a platform and the file system. They know nothing about the LLM, prompts, or context.
- **The tender is platform-agnostic.** Swap the bridge to change platform; nests, groundhogs, transcripts, tools, and skills are unchanged.
- **The tender is LLM-agnostic.** Skills are markdown, tools are bash, the prompt is a concatenation of files. Swap `llm.sh` to change models.
- **Gremlins are siblings.** Each is a complete unit. Adding one is `mkdir`. Removing one is `rm -rf`. Cross-gremlin work is `mv`.
- **Debugging is `ls` and `cat`.** Every piece of state — pending work, schedule, tools, skills, conversation — is a visible file.
