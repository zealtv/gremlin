# 👀 gremlin

A gremlin is a folder you can talk to.

Drop a `.gremlin/` into any directory and that directory now hosts an agent. Two host directories, side by side, each with their own `.gremlin/`, give you two agents. There is no supervisor, no canopy, no registry — composition is adjacency.

Built on `nestlings`, `groundhog`, and `loom`. LLM-agnostic by construction: nothing in the layout depends on which model runs the tender.

## Principle

The folder *is* the agent.

- An incoming message becomes a file in `.gremlin/.nest/in/`.
- The tender reads the gremlin's identity, context, skills, tools, and transcript, replies into `.nest/out/`.
- A bridge ships items between the outside world and the nest.
- A groundhog provides scheduled messages and recurring tasks.
- Tools are bash scripts. Skills are markdown procedures.

No database, no queue, no MCP, no daemon coordination. Files and atomic moves.

## A gremlin lives in `.gremlin/`

`.gremlin/` is the protocol marker — same role as `.nest/`, `.loom/`, and `.groundhog/`. Any folder hosting a gremlin contains a `.gremlin/`. The **host folder's name** is the gremlin's identity from the outside; what's *inside* `.gremlin/` defines the agent.

```
~/Desktop/research/           # the host folder — gremlin's identity from outside
  ...your real files...
  .gremlin/                   # the agent itself
  .loom/                      # (unrelated) you might also use loom for your own work here
```

To have two gremlins, use two host folders, each with its own `.gremlin/`. They see each other through the file system: delegation is `mv item ../other-host/.gremlin/.nest/in/`. There is no shared state, no shared process — two gremlins in the same parent directory are independent agents that happen to share a filesystem.

There is no enforced "shared/" folder for cross-gremlin tools or skills. If two gremlins want to share something, symlink it. The suggested convention for shared *context* (facts about you, your stakeholders, your environment) is `~/.gremlin/context/`, with each gremlin's `context/<file>.md` symlinking out to it. The protocol does not enforce this — it's a pointer, easy to ignore.

## Single gremlin layout (canonical)

```
.gremlin/
  gremlin.md            # identity: personality, purpose, voice
  context/              # optional: facts. user, stakeholders, environment, glossary
  run.sh                # backgrounds the loops; traps SIGINT
  say                   # local CLI bridge: write a message, get a reply
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
    tend.md             # how to tend this nest (protocol-level, not identity)
    in/ out/ dropped/
  .groundhog/
    groundhog.sh
    schedule/ out/ fired/
```

The top of `.gremlin/` holds only what isn't owned by a nested protocol: the identity, the context, the runner, the bridges, conversation state, and the libraries.

## Four kinds of writing, no overlap

A gremlin is configured through four distinct files/folders. Knowing which goes where keeps each one short and stable.

- **`gremlin.md`** — *who this gremlin is.* Personality, purpose, voice. Varies per gremlin. Always loaded.
- **`context/*.md`** — *what this gremlin knows.* Facts: user profile, stakeholders, environment, glossary. Varies per gremlin (or shared via symlink). Always loaded. No frontmatter, no triggers, no index — every file in `context/` is concatenated into every prompt.
- **`skills/<name>.md`** — *what this gremlin can do.* Procedures, with YAML triggers. Loaded selectively via `INDEX.md`.
- **`.nest/tend.md`** — *how a gremlin's nest is tended.* The prompt-assembly recipe. Protocol-level, mostly stable across gremlins.

Skill = procedure (when, how). Context = facts (always-on). Identity = self (always-on, framing). Tend = process (how to handle this kind of nest).

## The seams

A gremlin has four small surfaces. Everything else is internals.

### Bridges (how the world reaches the gremlin)

A bridge moves bytes between the outside world and `.nest/`. Inbound bridges write into `.nest/in/`; outbound bridges read from `.nest/out/`. Bridges know nothing about the LLM, prompts, or skills.

The MVP ships one bridge: a local CLI named `say`. `say "..."` writes your message into `.nest/in/`, waits for a reply in `.nest/out/`, prints it. `say --listen` blocks and prints whatever lands in `.nest/out/` — for scheduled outbound and as a side channel. Synchronous from your side, async from the gremlin's.

Telegram, Discord, email, web — all later additions, each just another script that talks to the same two folders. Swap the bridge, the gremlin doesn't notice.

### Tools (`tools/<name>.sh`)

A tool is a bash script that takes args (or stdin) and writes text to stdout. Errors go to stderr with a non-zero exit. That's the whole interface. Pure functions of args → stdout; state lives in nests and transcripts.

`tools/README.md` is the menu the tender reads. `bin/llm.sh` invokes the tender with `--allowedTools "Bash"` (unrestricted) so it can read skills on demand, run tools, and write scheduled work. There is **no enforced sandbox** — gremlins are gremlins. The convention is that you host one in a directory where broad bash is fine. Real isolation belongs outside the protocol (see "Sandboxing & sharing" and DEVELOPING.md). Tools are the *named* surface; the rest of the host directory is the *implicit* one.

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

`bin/index-skills.sh` walks `skills/*.md` and builds `skills/INDEX.md` — a list of triggers plus inlined `triggers: [always]` skills (reply style, refusal policy). The tender's prompt always includes `INDEX.md` and reads individual skill files when a trigger matches.

Tool vs skill: **tool = script you run, skill = procedure you follow.**

### The LLM seam (`bin/llm.sh`)

One file hides everything LLM-specific. `llm.sh "<prompt>"` reads stdin or args, calls whichever model CLI is wired up, prints the reply on stdout. Swap models by editing this one file. Everything else — bridges, nests, skills, tools, transcript — stays the same.

## The loops

Each loop is a single shell script. They never call each other; they share the file system.

### `bin/tend-loop.sh` (~5s cadence)

1. List ready items via `.nest/nestling.sh list`; bail if empty.
2. Claim the oldest item.
3. Build the prompt: `gremlin.md` + `context/*.md` (sorted) + `skills/INDEX.md` + `tools/README.md` + `transcript.md` + the item.
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

Backgrounds each loop, traps SIGINT/SIGTERM, kills the children explicitly, `wait`s. Runs the indexer at startup. Honours a `.paused` flag — loops idle when present so you can archive cleanly.

## Transcript

`transcript.md` is plain markdown, append-only. Two writers: the inbound bridge (user turns) and `tend-loop.sh` (assistant turns). One `>>` per turn — concurrent small appends do not interleave on POSIX.

```markdown
## user — 2026-04-27T19:42:11Z
hello

## assistant — 2026-04-27T19:42:14Z
hi, what's up?
```

`bin/archive.sh` rotates `transcript.md` into `transcript-archive/<date>.md` when you want a fresh session. It pauses the loops via `.paused` so an in-flight tend pass isn't orphaned. Pending groundhog items survive — they live in `.groundhog/`, untouched.

## Data flow

Four flows compose the runtime. They share no state besides the file system; both loops honour `.paused`.

**(1) `say` round-trip — you talk, the gremlin replies.**

```
  say "..."   ──►  transcript.md  (## user)
              ──►  .nest/in/<ts>.md
                                  ──(tend-loop)──►  .nest/out/<ts>.md
                                                ──►  transcript.md  (## assistant)
  say polls .nest/out/, prints the new file, moves it to out/sent/.
```

**(2) Scheduled outbound — a future message, no agent invocation.**

```
  .groundhog/schedule/once/<date>/foo/message.md
       ──(groundhog tick)──►  .groundhog/out/foo-<date>/message.md
       ──(tick-loop)──────►  .nest/out/<ts>.md
       ──(say --listen / bridge)──►  delivered
```

**(3) Scheduled tending — a future request the gremlin acts on.**

```
  .groundhog/schedule/daily/09/briefing/instructions.md
       ──(groundhog tick)──►  .groundhog/out/briefing-<date>/instructions.md
       ──(tick-loop)──────►  .nest/in/briefing-<date>/
       ──(tend-loop)──────►  .nest/out/<ts>.md   (assistant reply)
```

**(4) Self-pacing follow-up — the gremlin schedules its own future work.**

```
  say "remind me to ..."  ──(flow 1)──►  tend-loop runs `remind-me` skill,
                                          writes .groundhog/schedule/once/<date>/<slug>/message.md
  Tomorrow:  that file fires through flow (2) — user sees the reminder.
```

## Use a gremlin yourself

This repo dogfoods one gremlin at `.gremlin/` — the canonical reference. To run a gremlin of your own, copy that folder into any host directory:

```
./init.sh ~/Desktop/research
# or, equivalently:
cp -r .gremlin ~/Desktop/research/.gremlin
```

Then edit your `gremlin.md`, drop facts into `context/`, and start it:

```
cd ~/Desktop/research
./.gremlin/run.sh
./.gremlin/say "hello"
```

**Don't run `say` against this repo's reference `.gremlin/`.** Its purpose is to be a clean, generic example you copy from. If you do run `say` against it, you'll see `transcript.md` change in `git status` — that's the visible signal to copy the gremlin out and run it there instead.

This is the entire dev/use safety story: convention, not tooling. There is no `.gitignore`, no pre-commit hook, no sanitising script. The repo stays clean because nobody runs personal work against it.

## Composition

A second gremlin is a second host folder containing its own `.gremlin/`. Two parallel hosts; two `run.sh`s; one filesystem.

Inter-gremlin delegation is one `mv`: `mv request.md ../other-host/.gremlin/.nest/in/`. The receiver picks it up next tend pass. Replies go to the requester's `.nest/in/`, never to one's own `out/` (that's the nestling protocol).

There is no shared state, no shared process, no shared anything. Composition is adjacency.

### Sandboxing & sharing

Sandboxing is convention, not enforcement. `bin/llm.sh` runs the model with unrestricted bash; the rule is "host a gremlin somewhere broad reach is acceptable." Anything stricter belongs outside the protocol — see DEVELOPING.md for OS-level options.

When two gremlins should talk, or a gremlin should reach a shared resource, make the reach **visible** with a symlink. The link is the capability; removing it is revocation; `ls` is the audit trail.

Sibling delegation:

```
~/Desktop/house/gremlin1/.gremlin/peers/gremlin2
    →  ../../../gremlin2/.gremlin/.nest/in/
```

A skill in `gremlin1` writes to `peers/gremlin2/<item>` and the sibling picks it up next tend pass. Same shape with `children/` from a coordinator (a `house/` gremlin orchestrating its two children).

Shared context follows the same pattern: `~/.gremlin/context/` is a personal library; each gremlin's `context/<file>.md` symlinks out to it.

Prefer a coordinator over loose sibling-to-sibling links when coordination is non-trivial — the coordinator's transcript and skills become the place coordination logic lives, instead of being implicit in the filesystem reach.

## What's foundational, what's an extension

The MVP gives you: a runnable gremlin that converses via local CLI, calls tools, follows skills, fires scheduled work via groundhog, and archives transcripts cleanly.

Extensions slot in without restructuring:

- **Telegram (or any other) bridge** — replace `say` with `bin/bridge-in.sh` + `bin/bridge-out.sh` reading `meta.json`.
- **Attachments** — items in `.nest/in/` and `.nest/out/` become directories. The protocol already accepts both.
- **Voice (whisper in, TTS out)** — a transcribe tool runs pre-tend; a TTS tool produces `voice.ogg` next to `message.md`.
- **A second gremlin** — another host folder. Maybe a delegate skill.
- **Shared libraries** — symlinks. No protocol change.

## Why this composes

- **Bridges are dumb.** They translate bytes between a platform and the file system. They know nothing about the LLM, prompts, or context.
- **The tender is platform-agnostic.** Swap the bridge to change platform; nests, groundhogs, transcripts, tools, skills, identity, and context are unchanged.
- **The tender is LLM-agnostic.** Skills are markdown, tools are bash, the prompt is a concatenation of files. Swap `llm.sh` to change models.
- **Gremlins are folders.** Each is a complete unit. Adding one is `cp -r`. Removing one is `rm -rf`. Cross-gremlin work is `mv`.
- **Debugging is `ls` and `cat`.** Every piece of state — pending work, schedule, tools, skills, identity, context, conversation — is a visible file.
