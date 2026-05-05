# s42-update-command

Add a `/update` slash command that pulls gremlin core from GitHub and lays it over the personal copy, leaving personal data and user additions in place. Replaces the hand-rolled `sync.sh` pattern documented in `DEVELOPING.md` with an in-gremlin command.

Standalone stitch. Independent of stage-11.

## Why

Today personalisation requires the user to keep `~/repos/gremlin` cloned next to their personal copy and to write their own `sync.sh`. That works for one person but doesn't generalise — anyone running a gremlin on a server, in a container, or just without a sibling clone has no path to update.

`/update` makes the personal copy a first-class deployment of gremlin core. The canonical lives on GitHub; the personal copy pulls.

## Shape

New file: `.gremlin/commands/update.sh`. Same convention as other commands.

Behaviour:

1. Read upstream URL from `.gremlin/.upstream` (written by `init.sh`).
2. Touch `.gremlin/.paused` so `tend-loop` and `tick-loop` no-op during the swap (both already gate on this flag).
3. Download the canonical via `curl`:
   ```bash
   curl -fsSL "$URL" -o "$tmp/gremlin.tar.gz"
   tar -xzf "$tmp/gremlin.tar.gz" -C "$tmp"
   ```
   `$URL` is `https://github.com/<owner>/<repo>/archive/refs/heads/main.tar.gz` by default. The tarball extracts to a known directory (`<repo>-main/`).
4. Rsync `<extracted>/.gremlin/` into the live `.gremlin/`, with the exclude list below. **No `--delete`** — local-only files (custom skills, tools, commands, models) survive.
5. Remove `.paused`.
6. Print a one-line summary.

A `--dry-run` flag passes `--dry-run` to rsync and prints what would change without touching anything.

## Exclude list

```
transcript*
.nest/in/      .nest/out/      .nest/dropped/
.groundhog/out/  .groundhog/fired/  .groundhog/schedule/
context/
gremlin.md
.upstream
.model
.paused
```

Rationale per surface:

- `transcript*` — conversation log, personal.
- `.nest/{in,out,dropped}/` — runtime queue artefacts and per-item archive.
- `.groundhog/{out,fired,schedule}/` — runtime + the user's personal schedules.
- `context/` — personalisation, per existing convention.
- `gremlin.md` — identity. The intent is "edit this one file to spin up a gremlin quickly," so it must remain personal-edit territory after init.
- `.upstream`, `.model`, `.paused` — per-install or transient state.

## Behaviour for local edits

Falls out of `rsync -a` without `--delete`:

| Local file state | Update behaviour |
|---|---|
| User-created file (new skill / tool / command / model preset) | Untouched. Survives. |
| User-modified canonical file | Overwritten. Code flows one way (per the **Safety rules** section in `DEVELOPING.md`). |
| Canonical file removed upstream | Stays as local cruft. Not destructive. |

Document in the command's output / a short `commands/README.md` note: *name your custom additions distinctly from canonical names.* If the user creates `skills/help.md` and canonical also ships `skills/help.md`, theirs gets overwritten.

## init.sh changes

`init.sh` writes `.gremlin/.upstream` with the canonical URL on first init. A reasonable default:

```bash
echo "https://github.com/<owner>/gremlin/archive/refs/heads/main.tar.gz" \
  > "$DEST/.gremlin/.upstream"
```

The exact owner / repo is whatever this repo lives at when published. Fork users can edit `.upstream` to point at their fork.

## Atomicity

Rsync writes file-by-file. A `Ctrl-C` mid-update leaves a partial state. Acceptable for v1 (rsync is fast, the surface is small). If it becomes a problem, switch to staged-then-swapped: rsync into `.gremlin.new/`, then `mv .gremlin/<runtime-state> .gremlin.new/<runtime-state>; mv .gremlin .gremlin.old; mv .gremlin.new .gremlin`. Don't pre-build.

## Coupling with s41

s41 changes `models/` from `.env` files to `.sh` scripts and ships **only `default.sh`** in canonical. After s41, the model presets a user creates (`fast.sh`, `deep.sh`, anything) survive `/update` automatically by the rsync-no-delete rule. No special handling needed in this stitch.

If s41 lands first, that's the world this stitch ships into. If this lands first, the world is one with `default.env`/`fast.env`/`deep.env` — `/update` overwrites all three, which loses any user tweaks. Order: s41 first, ideally.

## Verify

1. From a fresh personal copy, `cat .gremlin/.upstream` shows the canonical URL.
2. Run `/update --dry-run`. Lists the files that would change. Touches nothing.
3. Make a deliberate local change to canonical: edit `.gremlin/skills/reply-style.md`. Add a custom skill: `.gremlin/skills/my-skill.md`.
4. Run `/update`. Output shows roughly N files updated.
5. `skills/reply-style.md` reverts to canonical content (overwrite).
6. `skills/my-skill.md` is still there (preserved).
7. `transcript.md` unchanged. `.nest/out/` archive entries unchanged. `.groundhog/schedule/` user entries unchanged. `gremlin.md` personalisations unchanged. `context/` unchanged.
8. `.paused` is gone after the command finishes.
9. `run.sh` (if running) resumes ticking normally.

## DEVELOPING.md

After `/update` exists, `sync.sh` becomes redundant for end-users. Keep the section but reframe: `sync.sh` is a *development convenience* for working on canonical (when you have a clone next to a personal copy), while `/update` is the *user-facing* update path. Or remove `sync.sh` entirely and tell developers to run `/update` against a `.upstream` pointing at `file://~/repos/gremlin/...` — `curl` accepts `file://` URLs. Decide during build.

## Out of scope

- Pinned versions / releases. Always HEAD of main for now.
- Authentication for private repos. Public GitHub only.
- Rollback. If `/update` breaks something, the user reverts manually or re-clones.
- Auto-update on a schedule. `/sweep`-style on-demand only.
