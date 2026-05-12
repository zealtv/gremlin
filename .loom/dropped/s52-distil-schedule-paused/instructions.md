# s52-distil-schedule-paused

**Outcome.** A fresh gremlin ships with an opt-in paused schedule item for
periodic memory review.

This stitch depends on the session commands and distil skill below it in the
Loom chain. Only tend it after `s51-session-commands` ties.

## Scope

- Add a paused groundhog item under `.gremlin/.groundhog/schedule/`.
- The item should be paused by default using the `.paused` suffix.
- Prefer a weekly cadence over nightly; weekly communicates review rather than
  constant accumulation.
- The item should create normal model-backed work in `.nest/in/` via
  `instructions.md`, not a shell script.
- Include `.model` with `memory` if the item shape supports copying that file
  through groundhog and tick routing.
- The instructions should ask the agent to review recent unreviewed transcript
  archives and/or pending `.glean/in/` items using the distil skill and
  `.glean/distil.md`.

## Constraints

- Do not add state to Glean for source tracking.
- Do not auto-enable scheduled review for fresh installs.
- Keep the scheduled path secondary to `/new`; it is an opt-in rhythm,
  not the primary memory mechanism.

## Verification

1. `groundhog.sh list` shows the scheduled item as paused.
2. `groundhog.sh due` does not include it while paused.
3. Renaming to unpause allows it to fire at the chosen cadence.
4. A fired copy routes into `.nest/in/` and is tended as model-backed work.
5. The item uses the memory model when `.model` is present.

## Notes

- If the current tick loop strips or ignores `.model` for groundhog material,
  record that and keep the model override to `/new` only for now.
