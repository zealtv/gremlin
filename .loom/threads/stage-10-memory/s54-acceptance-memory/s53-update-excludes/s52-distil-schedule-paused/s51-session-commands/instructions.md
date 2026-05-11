# s51-session-commands

**Outcome.** Gremlin exposes explicit session-boundary commands for memory and
temporary sessions.

This stitch depends on the distil skill below it in the Loom chain. Only tend it
after `s50-distil-skill` ties.

## Scope

Add canonical long-form commands:

- `/new-session` — archive the current transcript, start fresh, and queue a
  visible memory-review item for the archived session.
- `/discard-session` — archive the current transcript and start fresh without
  queueing memory review.

Keep short aliases:

- `/new` delegates to `/new-session`.
- `/discard` delegates to `/discard-session`.

The memory-review item should be a directory in `.gremlin/.nest/in/`:

```text
memory-review-<archive-id>/
  instructions.md
  .model
```

`.model` should contain:

```text
memory
```

`instructions.md` should point at the archived transcript and tell the agent to
use the distil skill and `.gremlin/.glean/distil.md`. It should be explicit that
the agent may do nothing when no durable memory is earned.

## Constraints

- Reuse `bin/archive.sh` for transcript rotation.
- Do not copy whole transcripts into `.glean/in/`.
- Do not modify Glean's protocol.
- `/discard-session` archives rather than deletes; its guarantee is no memory
  review.
- Avoid duplicate review item creation for the archive just produced.

## Verification

1. Run `/new-session` in a disposable gremlin.
2. Confirm the transcript is archived and a fresh transcript exists.
3. Confirm `.nest/in/` receives a `memory-review-*` directory with
   `instructions.md` and `.model`.
4. Confirm `.model` contains `memory`.
5. Run `/discard-session` and confirm no memory-review item is created.
6. Confirm `/new` and `/discard` delegate to the long forms.
7. Confirm `/help` documents the long forms clearly.

## Notes

- The long names should be canonical in docs because they explain the behavior.
- The short aliases are compatibility and convenience.
