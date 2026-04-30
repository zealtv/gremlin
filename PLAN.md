# gremlin implementation plan

A staged path from an empty directory to a runnable gremlin: it converses, calls tools, follows skills, fires scheduled work via groundhog, and archives transcripts cleanly. That is the foundation. Everything else (Telegram bridges, attachments, voice, multi-gremlin delegation) is built on top without restructuring.

The repo dogfoods one gremlin at `.gremlin/` — the canonical reference. To run a gremlin of your own, you copy that folder into a host directory (`./init.sh ~/somewhere` or `cp -r`) and edit it there. **Don't run `say` against the repo's reference `.gremlin/`** — its purpose is to stay generic. See the README for the full convention.

LLM-agnosticism is preserved by keeping every LLM-specific concern behind one helper (`bin/llm.sh`) and keeping skills as plain markdown.

## Stage map

| Stage | Outcome                                                                         |
|-------|---------------------------------------------------------------------------------|
| 1     | Skeleton: `.gremlin/` laid down, nest and groundhog initialized, llm.sh stubbed. |
| 2     | Tend loop: claim items, build prompt, reply to `.nest/out/`, append transcript. |
| 3     | Local CLI bridge (`say`): end-to-end conversation through the file system.      |
| 4     | Runner: `run.sh` backgrounds loops; `.paused` flag for clean shutdown.          |
| 5     | Tools: `tools/` folder, first tool, prompt includes the menu, allowedTools seam.|
| 6     | Skills: indexer builds `INDEX.md`; always-on + triggered skills wired in.       |
| 7     | Groundhog: `tick-loop.sh` routes due items into `.nest/in/` or `.nest/out/`.    |
| 8     | Archive: `bin/archive.sh` rotates `transcript.md` without losing in-flight work.|

Each stage gets a thread in the loom. Stitches are prefixed `sNN-` so loose ends sort globally. Acceptance stitches at the end of each stage are gates.

---

## Stage 1 — skeleton

**Outcome.** `.gremlin/` exists with the canonical layout. Nothing runs yet. A `bash -n` clean across the stubs.

**Stitches.**

- `s01-layout` — Create `.gremlin/` at the repo root with: a generic `gremlin.md` (placeholder identity), an empty `context/` folder, `bin/`, `tools/`, `skills/`, `transcript-archive/`, and an empty `transcript.md`.
  - *Verify:* `ls .gremlin/` shows the canonical top-level entries.
- `s02-nest-init` — Copy `nestling.sh` into `.gremlin/.nest/`. Run its `ensure`. Write `.gremlin/.nest/tend.md` describing the *tending process* for a gremlin's nest — generic, protocol-level, points at `../gremlin.md`, `../context/`, `../skills/INDEX.md`, `../tools/README.md`, `../transcript.md`. **Identity does not belong in `tend.md`.**
  - *Verify:* `ls .gremlin/.nest/` shows `in/ out/ dropped/ nestling.sh tend.md`.
- `s03-groundhog-init` — Copy `groundhog.sh` into `.gremlin/.groundhog/`. Run its `init`.
  - *Verify:* `ls .gremlin/.groundhog/` shows `schedule/ out/ fired/ groundhog.sh`.
- `s04-llm-helper` — `bin/llm.sh "<prompt>"`: read stdin or args, call the configured LLM CLI (default `claude -p`), print reply on stdout. Single seam.
  - *Verify:* `echo "say hi" | bin/llm.sh` returns a non-empty reply.
- `s05-acceptance-1` — Walk the layout: every protocol's invariants hold; every script is `bash -n` clean.
- `s05a-init-script` — Write `init.sh` at the repo root: a one-liner that places `.gremlin/` inside a target host directory (`cp -r "$(dirname "$0")/.gremlin" "$1/.gremlin"`). Document in the README that real use means running outside the repo, never against the reference instance.
  - *Verify:* `./init.sh /tmp/test-host` produces `/tmp/test-host/.gremlin/`.

---

## Stage 2 — tend loop

**Outcome.** Drop a file into `.nest/in/` by hand, the tender processes it, a reply lands in `.nest/out/`, both turns appear in `transcript.md`.

**Stitches.**

- `s06-tend-loop` — `bin/tend-loop.sh`: list ready items, claim oldest, build prompt (`gremlin.md` + every `context/*.md` (sorted) + `transcript.md` + the item body — skills/tools join in later stages), call `bin/llm.sh`, write reply to `.nest/out/<ts>.md` via `.landing` rename, append assistant turn to transcript, complete the item. If `context/` is empty or absent, the concatenation is a no-op.
  - *Verify:* Manual end-to-end with one item.
- `s07-transcript-format` — Settle the on-disk transcript format (`## user — <iso>`, `## assistant — <iso>`, blank line between). Single `>>` per turn so concurrent appends don't interleave.
  - *Verify:* Two consecutive items processed; transcript reads in order.
- `s08-acceptance-2` — Three hand-fed items in a row. Verify transcript integrity (no interleaving, all turns present, in order).

---

## Stage 3 — local CLI bridge

**Outcome.** `./.gremlin/say "hello"` writes a message into `.nest/in/`, blocks until a reply lands in `.nest/out/`, prints the reply. End-to-end conversation without launching anything.

**Stitches.**

- `s09-say-input` — `say` script: take a message (arg or stdin), append a `## user` turn to `transcript.md`, write the message to `.nest/in/<ts>.md` via `.landing` rename.
  - *Verify:* `./.gremlin/say "hi"` produces a file in `in/` and a transcript entry.
- `s10-say-output` — Watch `.nest/out/` for new files (skip `.landing`). When one appears: print it, then `mv` it to `.nest/out/sent/` (so the same reply isn't reprinted).
  - *Verify:* Drop a file in `.nest/out/` by hand; `say` reads it once, prints it, moves it to `sent/`.
- `s11-end-to-end` — Run `tend-loop.sh` in one terminal; `say "hi"` in another. Reply appears.
  - *Verify:* A two-turn conversation completes.
- `s12-acceptance-3` — Three-turn conversation through `say`. Transcript shows all six turns in order.

---

## Stage 4 — runner

**Outcome.** `./.gremlin/run.sh` brings every loop up; SIGINT brings them down with no orphans. A `.paused` flag idles the loops without killing them.

**Stitches.**

- `s13-runner` — `run.sh`: background each loop, `trap 'kill 0' INT TERM`, `wait`. Cadence per spec.
  - *Verify:* `./run.sh` starts cleanly; Ctrl-C ends all child processes.
- `s14-pause-flag` — Each loop checks `.paused` at the top of each iteration and idles while present.
  - *Verify:* `touch .paused`; loops idle. `rm .paused`; work resumes.
- `s15-acceptance-4` — Full conversation under `run.sh`. Pause mid-session, resume, finish.

---

## Stage 5 — tools

**Outcome.** The tender can call any script in `tools/`. State stays in nests and transcripts; tools are pure functions of args → stdout.

**Stitches.**

- `s16-tools-folder` — Create `tools/` with a `README.md` index. No tools yet.
- `s17-first-tool` — `tools/now.sh`: prints the current time. Tiny, deterministic, easy to spot in a transcript.
  - *Verify:* `./tools/now.sh` returns text, exits 0.
- `s18-tool-permissions` — `tend-loop.sh` invokes the tender with `--allowedTools "Bash(./tools/*)"` (or the LLM-equivalent). Document the seam in `bin/llm.sh`.
  - *Verify:* The tender can run a tool without an interactive prompt.
- `s19-tools-in-prompt` — `tend-loop.sh` includes `tools/README.md` in the prompt assembly.
  - *Verify:* Inspect a captured prompt; the tools list is present.
- `s20-acceptance-5` — Ask the gremlin "what time is it?". The reply uses `now.sh` and the transcript shows the tool call.

---

## Stage 6 — skills

**Outcome.** Plain markdown procedures with YAML frontmatter; `INDEX.md` is generated; the tender consults the index and reads individual skills on demand. LLM-agnostic.

**Stitches.**

- `s21-skills-folder` — Create `skills/`.
- `s22-always-skill` — Write `skills/reply-style.md` with `triggers: [always]` and a paragraph on tone, length, formatting.
- `s23-triggered-skill` — Write `skills/remind-me.md` with one or two natural-language triggers and a body explaining the groundhog file path to write.
- `s24-indexer` — `bin/index-skills.sh`: walk `skills/*.md` (follow symlinks), parse frontmatter, write `skills/INDEX.md`. Inline `always` skill bodies; list triggers for the rest.
  - *Verify:* Running the indexer produces a sensible `INDEX.md`.
- `s25-indexer-in-runner` — `run.sh` calls the indexer at startup.
- `s26-skills-in-prompt` — `tend-loop.sh` reads `skills/INDEX.md` into the prompt; document that the tender should `cat skills/<name>.md` when a trigger matches.
- `s27-acceptance-6` — Conversational test: "remind me to buy milk tomorrow at 9am". Verify `.groundhog/schedule/once/<tomorrow>/...` appears with the correct body. Reply confirms the reminder.

---

## Stage 7 — groundhog

**Outcome.** Scheduled outbound messages and scheduled work both flow through the gremlin without any agent invocation needed for outbound.

**Stitches.**

- `s28-tick-loop` — `bin/tick-loop.sh`: run `groundhog tick`, then route each `.groundhog/out/<item>/`: if it contains `message.md`, move it to `.nest/out/<ts>.md` (scheduled outbound); otherwise `mv` the item directory into `.nest/in/` (scheduled tending).
  - *Verify:* Manually drop a `.groundhog/out/` item with `message.md` and run `bin/tick-loop.sh` once — the message routes to `.nest/out/`.
- `s29-tick-in-runner` — Wire `tick-loop.sh` into `run.sh` at ~60s cadence.
  - *Verify:* Drop a `schedule/once/<today>/<minute>/test/message.md`, wait one minute, see it routed.
- `s30-acceptance-7-outbound` — Add a `schedule/once/<today>/<minute>/hello/message.md`. Verify it lands in `.nest/out/` on the next tick and `say` prints it.
- `s31-acceptance-7-tending` — Add `schedule/once/<today>/<minute>/task/instructions.md` saying "say good morning". Verify the tender processes it.

---

## Stage 8 — archive

**Outcome.** A clean way to start a fresh session without losing history or breaking in-flight loops.

**Stitches.**

- `s32-archive-script` — `bin/archive.sh`: `touch .paused`, `mv transcript.md transcript-archive/$(date +%Y-%m-%d).md`, `touch transcript.md`, `rm .paused`.
  - *Verify:* Mid-session archive transitions to a fresh transcript with no message lost or duplicated.
- `s33-acceptance-8` — Mid-conversation archive: the next reply uses only the new transcript and does not "remember" archived turns. Pending groundhog items survive.

---

## Notes on ordering and parallelism

Within a stage, most stitches are sequential because each builds on the previous file. The numeric prefixes (`sNN-`) make `loom next` walk them in order. Acceptance stitches at the end of each stage are gates: do not start the next stage until acceptance ties off.

## Definition of done (per stage)

A stage is done when:

1. Every stitch in its thread is tied (no children left in `threads/`).
2. The acceptance stitch ran end-to-end in the actual environment.
3. A short note in the goal stitch (added during tying) records what was learned.

## Out of scope (foundation)

These are explicitly *not* in the foundation. Each is a clean addition once the foundation stands.

- **Telegram (or any other) bridge.** Replace `say` with `bin/bridge-in.sh` + `bin/bridge-out.sh` reading `meta.json`.
- **Attachments.** Items in `.nest/in/` and `.nest/out/` become directories. The nest protocol already accepts both.
- **Voice in/out.** A trangremlin tool runs pre-tend; a TTS tool produces `voice.ogg` next to `message.md`.
- **A second gremlin in the same parent.** `mkdir`, copy skeleton, edit `tend.md`. Maybe a delegate skill.
- **Shared libraries across gremlins.** Symlinks. No protocol change.
