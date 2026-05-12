# unify-prompt-build

**Outcome.** `context/` is the only always-loaded surface. The tender's prompt build collapses to `gremlin.md` + `context/` + transcript + item. Skills, tools, and memory expose themselves to every prompt by being symlinked into `context/system/`, not by being special-cased in the tender.

**Why.** Today the tender hardcodes four sources into the prompt (`gremlin.md`, `context/*.md`, `skills/INDEX.md`, `tools/README.md`). Memory has no path into the prompt at all unless a finding is symlinked into `context/` by hand. The hardcoding made the tender carry the "what is always loaded" decision; the missing memory path made Glean effectively invisible. One uniform mechanism — symlinks in `context/system/` — fixes both. It also generalises the stage-10-memory strategy note: the tender stops knowing about *any* specific child protocol, which is a stronger version of "memory stays orthogonal to the tender."

## Strategy

**Two tiers inside `context/`.**

- `context/system/` holds protocol-managed symlinks (skills, tools, memory; later, optionally, peers). `gremlin doctor` owns this directory.
- `context/*.md` at the top level is the user's own always-loaded material.
- The tender concatenates `context/system/*.md` (sorted) then top-level `context/*.md` (sorted, excluding the `system/` directory).

**Eager seeding at install.**

- A fresh gremlin's `context/system/` already contains `skills.md`, `tools.md`, `memory.md` symlinks plus a real `README.md` that explains the directory.
- `/update` invokes `gremlin doctor` so existing gremlins migrate transparently.

**`gremlin doctor` is the repair tool, not the setup tool.** Install seeds; doctor restores. Doctor walks a small expected manifest and (re)creates missing symlinks. It never deletes or overwrites user content.

**Tender stops naming child protocols.** `bin/tend-loop.sh` reads `gremlin.md` and `context/` and that is all. Adding a new always-loaded surface later is a symlink, not a code change.

**Peer directory is described, not implemented.** This thread documents how a peer-gremlin directory could plug into `context/system/peers.md` in the future, but does not build it.

## Child stitches

Serial chain — leaf is the next loose end:

```text
s06-acceptance
└── s05-docs
    └── s04-tender-context-only
        └── s03-runner-indexes-glean
            └── s02-update-migration
                └── s01-doctor-and-seed
```

- **s01-doctor-and-seed** — `bin/doctor.sh` + `gremlin doctor` subcommand; install seeds `context/system/` with the three expected symlinks and a README.
- **s02-update-migration** — `/update` invokes `gremlin doctor` after overlay so existing gremlins gain `context/system/` transparently.
- **s03-runner-indexes-glean** — `bin/run.sh` calls `.glean/glean.sh index` alongside `bin/index-skills.sh` so the memory catalog stays current.
- **s04-tender-context-only** — collapse the tender's prompt build to `gremlin.md` + `context/system/*.md` + `context/*.md` + transcript + item. Drop the hardcoded skills/tools inlines.
- **s05-docs** — rewrite `docs/protocol.md`'s "Prompt Inputs" section; note the peer directory in `docs/composition.md` as a future shape; write `context/system/README.md`; refresh root README and `.gremlin/README.md`.
- **s06-acceptance** — end-to-end verification gate.

## Verification gate

**Fresh install.**

1. `install.sh` runs in a clean directory.
2. `ls .gremlin/context/system/` shows `skills.md`, `tools.md`, `memory.md`, `README.md`.
3. Each non-README entry is a symlink to the expected target.
4. The assembled prompt for a trivial item contains the skills index, tools index, and the (possibly empty) memory index.

**Opt-out.**

1. `rm .gremlin/context/system/memory.md`.
2. Next prompt no longer contains the memory catalog.
3. `gremlin doctor` restores it. Next prompt contains it again.

**Migration.**

1. Older gremlin (no `context/system/`) runs `/update`.
2. After update, `context/system/` exists and is populated.
3. No functional regression — skills and tools still reach the model.

**User content.**

1. User writes `.gremlin/context/my-prefs.md` with a known phrase.
2. That phrase appears in the prompt *after* the `system/` block, before the transcript.

## Constraints

- The expected manifest of system symlinks is a small constant in `bin/doctor.sh`. Do not invent a manifest file.
- `context/system/README.md` is a real file and is **not** loaded into the prompt — the tender's `system/` glob reads only `.md` files that are symlinks, or excludes `README.md` by name. Pick one rule and document it in s04.
- Do not modify Glean's protocol. The catalog being broadcast is host policy, not a Glean change.
- Peer-gremlin directory is **not** implemented here. `docs/composition.md` describes the shape only.

## Notes

- This thread revises the stage-10-memory strategy note that said "memory integration is orthogonal to the tender hot path." The replacement principle is stronger: the tender is orthogonal to *every* child protocol.
- Ordering within each tier is alphabetical. If finer ordering becomes necessary, numeric prefixes inside `system/` are the cheapest extension and need no code change.
- A durable opt-out mechanism (preventing doctor from restoring a deleted system symlink across `/update`) is **deferred**. Stage 10's stance applies: raise a follow-up stitch only if real use shows friction.
