# s47 flow: session memory

## Chosen shape

Gremlin should automatically review ended sessions for memory, but should not
automatically turn every transcript into permanent memory.

The session boundary is the user-facing hook:

- `/new` archives the current transcript, starts a fresh transcript,
  and queues a visible memory-review item for the archived session.
- `/discard` archives the current transcript and starts fresh without
  queueing memory review.

The terse names are canonical in docs and help because these commands are used
at session boundaries.

## Flow

```text
conversation
  -> /new
  -> transcript-archive/<archive>.md
  -> .nest/in/memory-review-<archive-id>/
       instructions.md
       .model = memory
  -> tender handles the review as normal model-backed work
  -> agent reads the archive and .glean/distil.md
  -> agent creates, revises, drops, or does nothing in .glean/findings/
  -> agent runs .glean/glean.sh index if findings changed
  -> fresh transcript gets a brief visible outcome
```

`/discard` shares the archive rotation but stops there:

```text
conversation
  -> /discard
  -> transcript-archive/<archive>.md
  -> fresh transcript
```

## Capture verb

Do not add a new gremlin-side "capture" command in this stage. The automatic
session review is the capture surface: it points the agent at a durable archive
and asks it to decide what, if anything, should become memory.

Manual memory work stays conversational: "distil this", "remember this", or
"review the last session for memory" should trigger the distil skill. A future
explicit command can still be added if real use shows the need.

## Glean boundary

Do not change Glean's protocol.

Gremlin does not add a `sources/` ledger to `.glean/`, and `/new` does
not copy full transcript archives into `.glean/in/` by default. Transcript
archives are already the durable raw corpus. `.glean/in/` remains available for
deliberate raw packets, not as the automatic graveyard for every conversation.

The memory-review item operates Glean directly:

- read `.gremlin/.glean/distil.md`;
- inspect `.gremlin/.glean/findings/` via `glean.sh index` / `fetch` as useful;
- revise or create flat finding files when earned;
- use `glean.sh drop` when retiring a finding;
- run `glean.sh index` after changes.

## Duplicate handling

The duplicate problem is avoided by not copying archives into `.glean/in/`.
Each `/new` queues review only for the archive it just created. Archive
names are unique because `archive.sh` already suffixes same-day archives.

If `/new` needs to be idempotent around review creation, it can check
for the review item name in `.nest/in/`, `.nest/out/`, and `.nest/dropped/`
before writing. This is local to the command and does not become Glean state.
If `.nest/out/` is swept later, no duplicate arises from old archives because
the command only handles the archive created in the current invocation.

## Transparency

Memory review is visible, not silent. The review item is model-backed, so the
fresh transcript will contain a short assistant outcome:

- no durable memory earned;
- revised finding `<id>`;
- created finding `<id>`;
- retired finding `<id>`;
- promoted finding `<id>` only if the user asked for always-loaded memory.

This is intentionally a little noisy. It makes proactive memory inspectable.
If the noise proves wrong in practice, a later stitch can add a quieter system
item shape without changing this memory model.

## Model choice

Use the existing per-item `.model` hook. The memory-review item contains:

```text
.model
memory
```

Ship `.gremlin/models/memory.sh` as a thin wrapper around `default.sh`. Users
can later replace it with a cheaper, slower, or more specialized model preset
without changing `/new` or the tender.

## Update behavior

`/update` should preserve host memory state:

- `.glean/in/`
- `.glean/findings/`
- `.glean/out/`
- `.glean/dropped/`
- `.glean/distil.md`

Canonical protocol files should still be overlaid:

- `.glean/glean.sh`
- `.glean/README.md`

The simplest rsync shape is to enumerate the runtime/local paths as excludes,
not exclude `.glean/` wholesale.

## Verification frame

The load-bearing test is cold-start recall after a reviewed session:

1. Fresh gremlin has empty `.glean/findings/`.
2. User states a durable preference in a session.
3. User runs `/new`.
4. Memory review creates or revises a finding and refreshes `INDEX.md`.
5. Promote the finding by symlink into `.gremlin/context/`.
6. Start another fresh session.
7. Ask a question that depends on the preference.
8. The answer reflects the finding because it is loaded through `context/`.

`/discard` gets the negative test: the same preference in a discarded
session should not produce a memory-review item or finding.
