# stage-10-memory

**Outcome.** A fresh gremlin ships with Glean vendored as its memory protocol.
Ended sessions can be reviewed automatically for durable memory, while temporary
sessions can be discarded from memory review. Findings are the workbench;
`context/` remains the always-loaded broadcast; promotion is explicit by
symlink.

**Glean ships at `github.com/zealtv/glean`.** Gremlin integration can proceed
from the concrete child stitches below. The design record lives in
`s47-find-flow/flow.md` once that stitch is tied.

## Strategy

**Two memory surfaces.**

- `.gremlin/.glean/findings/` is the workbench: distilled findings the agent
  can search and revise. It is not always loaded.
- `.gremlin/context/` is the broadcast: material loaded into every prompt.
- Promotion is explicit: symlink `context/<id>.md` to
  `../.glean/findings/<id>.md` when a finding has earned always-loading.

**Session close is the review point.**

- `/new` archives the current transcript, starts a fresh transcript,
  and queues a visible memory-review item for the archived session.
- `/discard` archives the current transcript and starts fresh without
  queueing memory review.
- `/new` and `/discard` are the canonical session commands.
- The review item is model-backed, carries `.model = memory`, and asks the
  agent to review the archive against `.glean/distil.md`.

**Automatic review, not automatic permanent memory.**

- `/new` does not copy whole transcripts into `.glean/in/`.
- Transcript archives remain the durable raw corpus.
- `.glean/in/` remains available for deliberate raw packets, not the automatic
  graveyard for every conversation.
- The review pass may create, revise, drop, or do nothing. It runs
  `glean.sh index` after changing findings and reports a brief visible outcome
  in the fresh transcript.

**Glean stays pure and vendored.**

- No new folders or ledger are added to Glean's protocol.
- A finding is one flat markdown file at `findings/<id>.md`.
- Parser contract: title (first `# ` line) plus description (first non-empty
  line before the next heading). Everything else is free prose.
- Suggested sections live in the host's `distil.md`: `## Why`, `## Triggers`,
  `## Associations`, `## Context`.
- Associations use wikilinks: `- [[other-id]]`.
- `index` always-loads via `findings/INDEX.md`; `fetch` is strict by default
  and can widen with `--all`.

**Memory integration is orthogonal to the tender hot path.** The integration
rides on `context/`, one triggered distil skill, vendored Glean, slash commands,
and the existing per-item `.model` hook. `tend-loop.sh` and `llm.sh` do not need
memory-specific changes.

## Child stitches

These are structured as a serial Loom chain so the next concrete loose end is
vendoring Glean, the acceptance gate only opens after every integration piece
has tied, and field assessment happens after the basic system works:

```text
s54-memory-field-use
└── s53-acceptance-memory
    └── s52-update-excludes
        └── s51-session-commands
            └── s50-distil-skill
                └── s49-init-wires-glean
                    └── s48-vendor-glean
```

- `s48-vendor-glean` — vendor `.gremlin/.glean/` with upstream `glean.sh` and
  `README.md`, seed trays, add gremlin-tuned `distil.md`, and ship
  `models/memory.sh` as a thin wrapper.
- `s49-init-wires-glean` — ensure install/init creates a usable `.glean/`.
- `s50-distil-skill` — add the triggered memory/distil skill used by manual
  asks and review items.
- `s51-session-commands` — add `/new` and `/discard`.
- `s52-update-excludes` — preserve local Glean state across `/update` while
  still overlaying canonical Glean files.
- `s53-acceptance-memory` — verify `/new`, `/discard`, the
  memory model preset, and cold-start recall through promoted findings.
- `s54-memory-field-use` — pressure test the system in ordinary day-to-day use,
  assess memory quality, and turn observed friction into follow-up stitches.

## Dependencies

- Glean rebuild is complete. Treat `github.com/zealtv/glean` as canonical.
- Groundhog paused-items support has landed, but periodic memory review is
  deferred. `/new` is the primary distillation trigger for this stage.

## Verification gate

Cold-start recall:

1. Fresh install produces an empty `.gremlin/.glean/findings/`.
2. User establishes a durable preference in conversation.
3. User runs `/new`.
4. A memory-review item is queued with `.model = memory` and tended.
5. The review creates or revises a finding and refreshes `findings/INDEX.md`.
6. Promote the finding by symlink into `.gremlin/context/`.
7. Start another fresh session.
8. Ask a question that depends on the preference. The answer should reflect the
   promoted finding because it is loaded through `context/`.

Discard path:

1. User establishes a temporary preference.
2. User runs `/discard`.
3. No memory-review item is queued.
4. No finding is created from that discarded session.

Update path:

1. Create local findings, inbox residue, dropped findings, and a customized
   `.glean/distil.md`.
2. Run `/update --dry-run`, then `/update` against a local canonical tarball.
3. Local Glean state remains; canonical `.glean/glean.sh` and `.glean/README.md`
   update.

If cold-start recall works, it is memory. If not, it is a filing cabinet.

## Notes

- `/new` is intentionally transparent rather than quiet: the fresh
  transcript receives a short memory-review outcome.
- `/discard` archives rather than deletes; its promise is no memory
  review, not no record.
- A future quiet review item shape can be considered after this visible path is
  proven.
- A paused Groundhog memory-review rhythm is deferred. `/new` is the
  primary distillation trigger; scheduled review can return later if real use
  shows a need for periodic corpus cleanup or `.glean/in/` draining.
