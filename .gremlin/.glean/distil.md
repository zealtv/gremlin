# Distil

This is Gremlin's local brief for turning conversations and notes into durable
memory.

Glean is the memory workbench. `findings/` holds distilled, revisable memory;
`context/` is the always-loaded broadcast surface. A finding only enters
`context/` when a user or agent explicitly promotes it, usually by symlinking
`context/<id>.md` to `../.glean/findings/<id>.md`.

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
- first non-empty line after the title: one-sentence description;
- optional sections:
  - `## Why` for source, motivation, or decision history;
  - `## Triggers` for terms that should bring this finding to mind;
  - `## Associations` for wikilinks such as `- [[other-id]]`;
  - `## Context` for compact examples or references.

The description and triggers are retrieval surfaces. Keep them clear.

## Promotion

Most findings should stay in Glean and be fetched on demand. Promote only the
small set that should affect every prompt.

Promotion is host-owned:

```sh
ln -s ../.glean/findings/<id>.md .gremlin/context/<id>.md
```

Demote by removing the symlink from `context/`; the finding remains in Glean.
