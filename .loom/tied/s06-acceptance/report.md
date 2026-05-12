# s06 acceptance report

## Result

All clean-room acceptance checks passed.

## Fresh install

- Installed from `/private/tmp/gremlin-s06-current.tar.gz` into `/private/tmp/gremlin-s06-fresh`.
- `context/system/` contained `README.md`, `skills.md`, `tools.md`, and `memory.md`.
- Managed symlinks resolved to:
  - `skills.md -> ../../skills/INDEX.md`
  - `tools.md -> ../../tools/README.md`
  - `memory.md -> ../../.glean/findings/INDEX.md`
- A captured trivial tend prompt contained the memory catalog header, `# skills index`, and `# tools`.

Artifact: `prompt-fresh.md`.

## Opt-out and restore

- Removed `context/system/memory.md`.
- Captured prompt no longer contained the Glean catalog header.
- Ran `gremlin doctor`; it recreated `context/system/memory.md`.
- Captured prompt contained the Glean catalog again.

Artifacts: `prompt-no-memory.md`, `prompt-memory-restored.md`, `prompt-memory-diff.diff`.

## Migration

- Simulated an older gremlin by removing `context/system/` from a clean install.
- Pointed `.upstream` at the current canonical tarball and ran `/update`.
- `/update` ran doctor and recreated all managed `context/system/` entries.
- A captured tend after migration still contained `# skills index` and `# tools`.

## User context

- Added top-level `context/marker.md` containing `S06 user context marker phrase`.
- Captured prompt placed the marker after the system block (`# tools`) and before the first transcript turn.

Artifacts: `prompt-marker.md`, `prompt-marker-diff.diff`.

## Glean freshness

- Added a finding directly under `.glean/findings/`.
- Before runner startup, `findings/INDEX.md` did not contain the new entry.
- Started `bin/run.sh`; startup refreshed the Glean index.
- `findings/INDEX.md` then contained `[[s06-runner-freshness]]`.

Cadence note: s03 implemented Glean index refresh at runner startup, alongside skills indexing. It does not refresh continuously on each 5-second tend-loop cycle while an already-running runner stays up.

## Follow-ups

No follow-up stitches from this gate. The only surprise was the wording in the original acceptance note saying "with the runner up"; actual implemented cadence is startup refresh, and the observed behavior matches s03.
