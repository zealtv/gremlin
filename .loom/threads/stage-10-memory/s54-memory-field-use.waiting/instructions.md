# s54-memory-field-use

**Outcome.** Exercise the memory system in real use after the formal acceptance
gate passes. Produce an assessment of whether the system is helpful,
transparent, and appropriately conservative, plus concrete follow-up stitches
for the next memory improvements.

This stitch depends on `s53-acceptance-memory`. Only tend it after the basic
memory path works end to end.

## Scope

- Use Gremlin normally for several real sessions, not just synthetic tests.
- Try `/new` at natural session boundaries and inspect what the review
  chose to remember, revise, or ignore.
- Try `/discard` for temporary or sensitive work and verify the promise
  remains understandable in practice: archived, but not reviewed for memory.
- Promote a small number of findings into `context/` only when they clearly
  improve future sessions.
- Record false positives, false negatives, stale findings, awkward prompts,
  surprising transparency gaps, and any friction around finding promotion.
- Convert important observations into follow-up Loom stitches instead of
  expanding this stitch into implementation work.

## Field Exercises

Run a small matrix of ordinary usage patterns:

1. Durable preference: state a preference that should help future work, then
   close with `/new`. Later, ask for work where the preference should
   matter.
2. Project fact: establish a fact about this repo or a nearby project, then
   test whether the resulting finding is discoverable without being promoted.
3. Working style: let a session reveal process preferences indirectly. Check
   whether the review is cautious about inferring them.
4. Temporary session: do exploratory or throwaway work, close with
   `/discard`, and verify no memory-review item is queued.
5. Correction: contradict or refine an existing remembered point and check
   whether the review revises rather than duplicating.
6. Silence: end a session with nothing durable in it and confirm that the review
   can choose to remember nothing.

## Assessment Framework

Score each exercised session qualitatively:

- **Salience:** Did the review remember things that would actually help later?
- **Restraint:** Did it avoid remembering incidental, temporary, or sensitive
  details?
- **Traceability:** Can the user understand why a finding exists and where it
  came from?
- **Distillation:** Is the finding shorter and more useful than the raw
  transcript?
- **Retrieval:** Can the agent find the memory when relevant without loading
  everything all the time?
- **Promotion:** Is it obvious which findings deserve `context/` and which
  should stay in Glean?
- **Correction:** Are updates and contradictions handled by revision rather
  than duplicate accumulation?
- **User experience:** Do `/new`, `/discard`, and the visible
  review outcome feel clear enough to use daily?

## Artifact

Before tying this stitch, write a short field report in this directory:

- what sessions were tried;
- what findings were created, revised, dropped, or promoted;
- examples of helpful recall;
- examples of over-remembering or missed salience;
- recommended changes, each linked to a new or existing Loom stitch.

## Notes

- Treat this as product discovery for the memory loop. Do not silently patch the
  implementation while assessing it.
- Prefer a few realistic sessions over many contrived prompts.
- The most important question is whether memory changes the next session in a
  way the user can see, trust, and correct.
