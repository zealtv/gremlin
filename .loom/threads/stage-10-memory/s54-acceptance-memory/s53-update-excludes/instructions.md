# s53-update-excludes

**Outcome.** `/update` preserves local Glean memory state while still overlaying
canonical Glean protocol files.

This stitch depends on the scheduled-review and command/skill integration below
it in the Loom chain. Only tend it after `s52-distil-schedule-paused` ties.

## Scope

Update `.gremlin/commands/update.sh` excludes so local Glean state survives:

- `.glean/in/`
- `.glean/findings/`
- `.glean/out/`
- `.glean/dropped/`
- `.glean/distil.md`

Do not exclude `.glean/` wholesale. Canonical files should update:

- `.glean/glean.sh`
- `.glean/README.md`

Update docs that describe `/update` preservation behavior if needed.

## Verification

1. In a disposable gremlin copy, create:
   - a finding under `.glean/findings/`;
   - an inbox item under `.glean/in/`;
   - an out item under `.glean/out/`;
   - a dropped finding plus reason under `.glean/dropped/`;
   - a local edit in `.glean/distil.md`.
2. Point `.upstream` at a local tarball from the canonical repo.
3. Run `./.gremlin/gremlin update --dry-run` and inspect that local Glean state
   is not overwritten.
4. Run `./.gremlin/gremlin update`.
5. Confirm local Glean state remains and canonical `.glean/glean.sh` /
   `.glean/README.md` are present.

## Notes

- Keep update behavior consistent with existing preservation of `context/`,
  transcripts, queues, schedules, `.model`, and `.paused`.
