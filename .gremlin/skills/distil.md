---
name: distil
triggers:
  - user asks to distil, distill, remember, review, or consolidate material for memory
  - user says "distil this", "distill this", "remember this", "review this for memory", or "consolidate findings"
---

# distil

Use this skill for explicit memory work: reviewing a transcript archive,
distilling a raw packet in `.gremlin/.glean/in/`, revising findings, or handling
a direct user ask to remember or consolidate something.

Do not treat reviewed material as permanent memory by default. Distillation is a
judgment pass. Prefer "nothing earned" over weak findings.

## Load The Brief

1. Read `.gremlin/.glean/distil.md`.
2. Inspect `.gremlin/.glean/findings/INDEX.md` if it exists.
3. If the task points at an archived transcript, read that archive. Do not copy
   the whole transcript into `.glean/in/`.
4. If the task points at an item in `.gremlin/.glean/in/`, read that item and
   plan to close it with `complete` after considering it.

## Decide

Look for durable carry-forward value:

- stable user preferences;
- settled project facts or decisions;
- recurring workflows, local protocols, or naming conventions;
- corrections to existing findings;
- associations that make existing findings easier to retrieve.

Before creating a new finding, search for related findings:

```sh
.gremlin/.glean/glean.sh fetch <terms...>
.gremlin/.glean/glean.sh fetch --all <terms...>
```

Prefer revising an existing finding when it already covers the ground. Create a
new finding only when the material has a distinct, durable use.

## Act

Findings are flat markdown files under `.gremlin/.glean/findings/`:

```markdown
# Title

One-sentence description.

## Why

Why this memory was earned.

## Triggers

- terms that should bring it to mind

## Associations

- [[related-finding]]

## Context

Compact examples or references.
```

When an existing finding is stale or wrong, retire it with a reason:

```sh
.gremlin/.glean/glean.sh drop <id> "reason"
```

When you handled a deliberate raw packet from `.gremlin/.glean/in/`, close it:

```sh
.gremlin/.glean/glean.sh complete <in-id>
```

After creating, revising, or dropping findings, refresh the index:

```sh
.gremlin/.glean/glean.sh index
```

## Promotion

Most findings should stay in Glean and be fetched on demand. If a finding should
affect every future prompt, mention explicit promotion by symlink:

```sh
ln -s ../.glean/findings/<id>.md .gremlin/context/<id>.md
```

Do not promote automatically unless the user asked for always-loaded memory or
the review item explicitly requires it.

## Reply

Summarize the result briefly:

- created, revised, dropped, completed, or nothing earned;
- finding ids affected;
- whether `index` was refreshed;
- any suggested promotion into `context/`.
