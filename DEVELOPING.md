# developing gremlin

How to work on the gremlin repo while running a personal gremlin in parallel — without leaking personal data into the public repo.

> **Paths.** This guide uses two example paths:
> - `~/repos/gremlin` — the canonical repo (what you push)
> - `~/Desktop/mygremlin` — the host directory for your personal gremlin
>
> Substitute your own. The names don't matter; what matters is that the second lives **outside** the first.

## Setup (once)

```bash
cd ~/repos/gremlin
./init.sh ~/Desktop/mygremlin
```

Personalise the copy: edit `~/Desktop/mygremlin/.gremlin/gremlin.md`, drop facts into `context/*.md`. Never edit identity or context inside the repo.

`init.sh` writes `~/Desktop/mygremlin/.gremlin/.upstream` pointing at the public canonical tarball on GitHub. `/update` (a slash command) is the one and only way personal copies pull from canonical — for end users and for you. To iterate against your local clone instead of GitHub, point `.upstream` at a local tarball:

```bash
echo 'file:///tmp/gremlin.tar.gz' > ~/Desktop/mygremlin/.gremlin/.upstream
```

Then refresh that tarball whenever you want to test a canonical change:

```bash
( cd ~/repos && tar -czf /tmp/gremlin.tar.gz gremlin/.gremlin )
```

Code flows; runtime artefacts and your `context/` don't — `/update` excludes `transcript*`, the nest queues, groundhog runtime + schedule, `context/`, `gremlin.md`, and per-install state (`.upstream`, `.model`, `.paused`).

## Daily loop

1. Edit the canonical inside `~/repos/gremlin/.gremlin/`.
2. Re-tar: `( cd ~/repos && tar -czf /tmp/gremlin.tar.gz gremlin/.gremlin )`.
3. From `~/Desktop/mygremlin/`: `./.gremlin/bin/say "/update"` (or `/update --dry-run` to preview).
4. Run / test.
5. Iterate.
6. Commit the canonical changes.

Bigger work — features, extensions, refactors — drives through the loom.

## Working with the loom

`.loom/threads/` holds work that has shape. A feature with more than one step belongs in a thread. Small fixes don't.

The protocol is in `.loom/README.md`. Quick reminders:

- Draft a goal stitch under `.loom/threads/<thread>/instructions.md`.
- Decompose into child stitches as the work clarifies. Name them in the order you want them taken.
- `./.loom/loom.sh next` — the next loose end.
- `./.loom/loom.sh claim <stitch-id>` — race-free claim.
- `./.loom/loom.sh tie <stitch-id>` — done.
- `./.loom/loom.sh status` — overview.

Acceptance stitches at the end of a thread are the gates.

## Safety rules

- **Never run `say` against the repo's `.gremlin/`.** That's how `transcript.md`, nest queues, and `.groundhog/out/`/`fired/` accumulate personal data inside the repo.
- **Code flows one direction:** repo → personal copy. Never sync personal back.
- **`git status` is the canary.** From `~/repos/gremlin`, if anything under the personal-leakable paths changes, you ran something against the wrong copy. `git checkout -- <path>` to discard.
- **Personalisation lives only outside the repo.**

## Real sandboxing (optional)

The protocol does not enforce a sandbox; `bin/llm.sh` invokes claude with unrestricted bash. The convention is "host a gremlin in a directory where broad reach is acceptable" — fine for personal use, weak as security.

If you want actual isolation, wrap `bin/llm.sh` (or `run.sh`) with one of:

- **`sandbox-exec`** (macOS, built-in) — declarative profile language. Restrict file access to the host dir; deny everything else. Tightest fit, no install.
- **`bwrap`** (Linux, bubblewrap) — user-namespace isolation. Bind-mount only the host dir into the sandbox.
- **Container** (Docker / Podman) — heaviest but most portable. Bind-mount the host dir, run `run.sh` inside.
- **Dedicated UNIX user** — `useradd`, `chown` the host dir, run `run.sh` via `sudo -u`. Filesystem permissions do the work; no extra tooling.
- **`firejail`** (Linux) — profile-based, easier than bwrap.
- **`chroot`** — old-school; filesystem-only.

The seam is `bin/llm.sh`. Whichever you pick, the rest of the gremlin doesn't notice.

## Promoting personal-copy work to canonical

When something in your personal copy is worth shipping:

- **A new tool** — write a *generic* version directly into `.gremlin/tools/`. Don't `cp` your personal one back. Rewrite without your specifics.
- **A new skill** — same. Generic by hand.
- **A loop tweak** — edit the canonical script, then sync forward.

The asymmetry is deliberate: personal copy is presumed to carry context; the repo is presumed generic. Crossing that boundary is a deliberate hand-written act.

## Fresh transcript in your personal copy

```bash
cd ~/Desktop/mygremlin && ./.gremlin/bin/archive.sh
```

Pending groundhog items live in `.groundhog/` and are untouched.

## Picking up between sessions

From `~/repos/gremlin`:

- `./.loom/loom.sh status` — what's tied, loose, claimed
- `./.loom/loom.sh next` — next loose end
- `./.loom/loom.sh waiting` — anything blocked externally
- `./.loom/loom.sh loose-ends` — all of them, in order

## Next items

These extensions slot in cleanly without restructuring the foundation. Pick one, draft a thread under `.loom/threads/`, decompose.

- **Telegram (or any other) bridge** — long-running daemon that tails `transcript.md` for assistant turns and writes inbound to `.nest/in/`, with a `bridges/<name>/.cursor` for at-least-once replay.
- **Attachments** — items in `.nest/in/` and `.nest/out/` become directories. The protocol already accepts both.
- **Voice (whisper in, TTS out)** — a transcribe tool runs pre-tend; a TTS tool produces `voice.ogg` next to `message.md`.
- **A second gremlin in the same parent** — another host folder. Maybe a delegate skill.
- **Shared libraries across gremlins** — symlinks. No protocol change.

## Pre-push checklist

Before pushing, from `~/repos/gremlin`:

- [ ] `git status` is clean
- [ ] `cat .gremlin/transcript.md` is empty
- [ ] `.gremlin/.nest/in/`, `.groundhog/out/`, `.groundhog/fired/` contain only `.gitkeep`
- [ ] `.gremlin/.nest/out/` contains only `.gitkeep` *or* archive entries newer than the sweep window (default 14 days; cleared by `nestling sweep`)
- [ ] `cat .gremlin/gremlin.md` is generic — no real names, people, or projects
- [ ] `ls .gremlin/context/` contains only `.gitkeep` (or generic placeholders)
- [ ] No `.env`, no `meta.json`, no API keys anywhere

`.DS_Store` is `.gitignore`'d. Beyond that, the safety story is convention plus this checklist — no hooks, no scanners. The repo stays clean because nobody runs personal work against it.
