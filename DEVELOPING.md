# developing gremlin

How to work on the gremlin repo while running a personal gremlin in parallel — without leaking personal data into the public repo.

> **Paths used in this guide.** This guide uses two example paths:
> - `~/repos/gremlin` — the canonical repo (what you push)
> - `~/Desktop/mygremlin` — the host directory for your personal gremlin (your real instance)
>
> Substitute your own paths anywhere they appear. The directory names don't matter; what matters is that the second one lives **outside** the first.

## Setup (once)

- `cd ~/repos/gremlin`
- Pick a host directory for your personal gremlin somewhere **outside** the repo: `mkdir -p ~/Desktop/mygremlin`
- Once `s05a-init-script` is tied, run: `./init.sh ~/Desktop/mygremlin` → produces `~/Desktop/mygremlin/.gremlin/`
- Until `init.sh` exists: `cp -r .gremlin ~/Desktop/mygremlin/.gremlin`
- Personalise *your* copy only: edit `~/Desktop/mygremlin/.gremlin/gremlin.md`, drop facts into `context/*.md`. Never edit identity/context inside the repo.

## Daily dev loop (per stitch)

- `cd ~/repos/gremlin`
- `./.loom/loom.sh next` → tells you the next stitch (e.g. `stage-1-skeleton/s01-layout`)
- `./.loom/loom.sh claim <stitch-id>` → marks it `.stitching/`, race-free
- Read `cat .loom/threads/<thread>/<stitch-id>/instructions.md`
- **Edit the canonical** — `.gremlin/...` *inside the repo*. Scripts go in `.gremlin/bin/`, generic skills in `.gremlin/skills/`, etc.
- **Sync into your personal copy** to test:

  ```bash
  rsync -a \
    --exclude='transcript*' \
    --exclude='.nest/in/' --exclude='.nest/out/' --exclude='.nest/dropped/' \
    --exclude='.groundhog/out/' --exclude='.groundhog/fired/' \
    --exclude='context/' \
    ~/repos/gremlin/.gremlin/ ~/Desktop/mygremlin/.gremlin/
  ```

  The exclusions preserve your personal runtime state and your real `context/`. Code (bin, scripts, skills, gremlin.md) flows; runtime artefacts don't.
- **Run from the personal copy:** `cd ~/Desktop/mygremlin && ./.gremlin/run.sh` (or invoke the specific script the stitch is testing).
- Test the stitch's *Verify* clause against the personal copy. Iterate: edit in repo → rsync → re-test.
- When green: `cd ~/repos/gremlin && ./.loom/loom.sh tie <stitch-id>`
- Add a one-line note in the stage's goal stitch (`<thread>/instructions.md` under `## Notes`) if anything surprising came up.
- Commit the canonical changes.

## Safety rules

- **Never run `say` against the repo's `.gremlin/`.** That's the only way `transcript.md`, `.nest/in/`, `.nest/out/`, `.groundhog/out/`, `.groundhog/fired/` accumulate personal data inside the repo.
- **Code flows one direction:** repo → personal copy. Never sync personal back into the repo.
- **`git status` is the canary.** From `~/repos/gremlin`, if anything under the paths above changes, you ran something against the wrong copy. `git checkout -- <path>` to discard.
- **Personalisation lives only outside the repo.** Your real `gremlin.md`, your real `context/user.md`, your real schedule items, your real transcripts — all in `~/Desktop/mygremlin/.gremlin/`, never the repo.

## Promoting personal-copy work to the canonical

When you build something in your personal copy that's worth shipping:

- **A new tool** — write a *generic* version directly into the repo's `.gremlin/tools/`. Don't `cp` your personal one back. Rewrite without your specifics (no real account IDs, paths, names).
- **A new skill** — same. Generic by hand.
- **A loop tweak** — edit the canonical script in the repo, then rsync forward into your personal copy.

The asymmetry is deliberate: anything in your personal copy is presumed to carry context. Anything in the repo is presumed generic. Crossing that boundary is always a deliberate, hand-written act.

## Picking up between sessions

From `~/repos/gremlin`:

- `./.loom/loom.sh status` — what's tied, loose, claimed
- `./.loom/loom.sh next` — next loose end
- `./.loom/loom.sh waiting` — anything blocked on something external
- `./.loom/loom.sh loose-ends` — all of them, in order

## Fresh transcript in your personal copy

Once `stage-8-archive` is tied:

```bash
cd ~/Desktop/mygremlin && ./.gremlin/bin/archive.sh
```

Until then, by hand:

```bash
cd ~/Desktop/mygremlin/.gremlin
touch .paused
mv transcript.md transcript-archive/$(date +%Y-%m-%d).md
touch transcript.md
rm .paused
```

Pending groundhog items live in `.groundhog/` and are untouched.

## Pre-push checklist

Before pushing the repo public, from `~/repos/gremlin`:

- [ ] `git status` is clean
- [ ] `grep -ri "scribe" .` returns nothing
- [ ] `cat .gremlin/transcript.md` is empty
- [ ] `.gremlin/.nest/in/`, `.nest/out/`, `.groundhog/out/`, `.groundhog/fired/` are empty
- [ ] `cat .gremlin/gremlin.md` is generic — no real names, people, or projects
- [ ] `ls .gremlin/context/` is empty (or contains only generic placeholder content)
- [ ] No `.env`, no `meta.json`, no API keys anywhere

This is the entire safety story: convention plus a checklist. No `.gitignore`, no hooks, no scanners. The repo stays clean because nobody runs personal work against it.
