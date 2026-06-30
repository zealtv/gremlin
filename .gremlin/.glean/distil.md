# Distil

This is Gremlin's local brief for turning conversations and notes into durable
memory.

Glean is the memory workbench. A finding can be loaded into a prompt three ways,
and most findings only ever need the first two:

1. **Durable in Glean** — it lives in `findings/` and is searchable with
   `fetch`. Every finding starts here.
2. **Recallable by trigger** — it has `## Triggers`, so the host pipes each
   inbound message through `glean.sh recall` and loads matching bodies
   automatically (see `tend-loop.sh`). No promotion needed; the finding arrives
   exactly when its topic comes up.
3. **Always-loaded via `context/`** — symlinked into `context/`, so it rides in
   every prompt regardless of topic. Reserve this for the small set that must
   affect nearly every turn.

Good, precise triggers make most findings useful without ever touching
`context/`.
Promotion is only for findings that must be present even when nothing in the
message would recall them.

## Posture

Keep memory small, useful, transparent, and correctable.

- Prefer revising an existing finding over creating a near-duplicate.
- Do not remember temporary, sensitive, or incidental details.
- Do not infer a durable preference from a single ambiguous moment.
- Do not copy transcript chunks forward when a short finding would do.
- Record why the memory was earned so a future user can inspect it.
- It is valid to remember nothing.

Memory should improve future judgment. If it would only make the corpus larger,
leave it behind.

## Session Review

When reviewing an archived transcript, read for durable carry-forward value:

1. stable user preferences;
2. project facts likely to matter later;
3. recurring workflows, naming conventions, or local protocols;
4. decisions the user explicitly settled;
5. corrections to an existing finding.

Choose one of four outcomes:

1. **Revise** an existing finding in `findings/<id>.md`.
2. **Create** a new finding in `findings/<new-id>.md`.
3. **Drop** a stale finding with `glean.sh drop <id> "reason..."`.
4. **Remember nothing** when the session did not earn memory.

Run `glean.sh fetch` before creating a finding. Run `glean.sh index` after
writing, revising, or dropping findings.

## Inbox Distillation

When raw material arrives in `in/`, handle it with the same posture:

1. read the item;
2. search for related findings;
3. revise, create, drop, or do nothing;
4. close the inbox item with `glean.sh complete <in-id>`;
5. run `glean.sh index` after changing findings.

`out/` is audit residue for considered inbox items. It is swept on retention.
Transcript archives are not automatically copied into `in/`.

## Finding Shape

A finding is one markdown file at `findings/<id>.md`:

- first line: `# Title`;
- first non-empty line after the title: a one-sentence recall cue, written the
  way the finding would come up when an agent scans `INDEX.md`;
- optional sections:
  - `## Why` for source, motivation, or decision history;
  - `## Triggers` for a short list of literal names, identifiers, error strings,
    or user aliases the description would lose — not a keyword dump or a
    restatement of the title; `recall` matches these on whole words;
  - `## Associations` for wikilinks such as `- [[other-id]]`;
  - `## Context` for compact examples or references.

The description is the agentic retrieval cue; triggers are the deterministic
recall needles. Keep both precise.

## Promotion

Most findings should stay in Glean and surface by trigger. Before promoting, ask
**"are triggers sufficient?"** If a good set of `## Triggers` will bring the
finding to mind whenever it is relevant, leave it unpromoted — trigger recall
already covers the use case, and `context/` stays lean.

Promote only when the finding must affect prompts *even when nothing in the
message would recall it* — a global default like a location or unit system that
shapes answers silently. When a finding clears that bar, **perform the promotion
yourself** rather than asking the user to — the symlink lives in the host's
`context/`, not in Glean's protocol:

```sh
ln -s ../.glean/findings/<id>.md .gremlin/context/<id>.md
```

Demote by removing the symlink from `context/`; the finding remains in Glean.
Removing a stale always-loaded symlink whose use case is now covered by triggers
is good curation, not loss.
