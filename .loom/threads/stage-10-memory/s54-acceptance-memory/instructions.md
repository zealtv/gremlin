# s54-acceptance-memory

**Outcome.** Prove the memory integration works end to end: `/new-session`
reviews a completed session, `/discard-session` does not, the memory model
preset is used for review items, and promoted findings survive a fresh
transcript through `context/`.

This stitch depends on all implementation work below it in the Loom chain.
Only tend it after `s53-update-excludes` has tied.

## Scope

- Test a fresh gremlin copy outside this reference repo.
- Verify `/new-session` archives the transcript and queues a memory-review item.
- Verify the review item includes `.model` set to `memory`.
- Verify the memory preset delegates successfully to the configured default.
- Verify a durable preference can become a `.glean/findings/<id>.md` finding.
- Promote that finding into `context/` by symlink.
- Start another fresh session and verify cold-start recall.
- Verify `/discard-session` archives without queueing memory review.
- Verify `/new` and `/discard` aliases behave like the long commands.

## Verification

1. Create or use a disposable host folder with a copied/installed gremlin.
2. Configure the model preset enough to run a real review.
3. In a session, state a durable preference.
4. Run `/new-session`.
5. Confirm:
   - transcript rotated into `transcript-archive/`;
   - fresh `transcript.md` exists;
   - `.nest/in/` receives a `memory-review-*` item, or `.nest/out/` receives it
     if the runner already tended it;
   - the review item has `.model` containing `memory`.
6. Let the runner tend the review. Confirm the fresh transcript records a brief
   memory-review outcome.
7. Confirm a finding was created or revised in `.glean/findings/`, and
   `findings/INDEX.md` was refreshed.
8. Symlink the finding into `context/`.
9. Run `/new-session` or `/discard-session` to clear the active transcript.
10. Ask a question that depends on the preference. The answer should use the
    promoted context finding.
11. Repeat with a temporary preference and `/discard-session`; confirm no
    memory-review item or finding is produced from that session.

## Notes

- Keep personal state out of this repository.
- Record any friction in this stitch before tying it off.
