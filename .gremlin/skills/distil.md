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

### Light curation in passing

Your fetch already loaded the neighbourhood — use it. While you have those
findings in hand:

- if two fetched findings substantially overlap with each other or with what
  you're about to write, **merge** rather than create a third — pick the best
  home and revise it, then `drop` the redundant one with a reason;
- if a fetched finding is **contradicted** by the new material, drop the old
  one with a reason rather than letting both coexist;
- if a fetched finding has clearly grown to cover two distinct ideas, **note
  it in your reply for the next curate pass** but do not split it here —
  splits are riskier than merges and belong in the `curate` skill's
  deliberate, corpus-wide pass.

Keep curation scoped to findings the fetch actually returned. Do not go
rummaging through the corpus.

## Act

Every finding must include a non-empty `## Triggers` section. If you cannot
list at least one trigger term, the material is not yet ready to be a
finding — leave it for a later pass or record it under a clearer angle.

Findings are flat markdown files under `.gremlin/.glean/findings/`:

```markdown
# Title

One-sentence description.

## Why

Why this memory was earned.

## Triggers

- terms that should bring it to mind (required — strict `fetch` searches this
  section, so a finding without triggers is effectively only findable by id,
  title, or description)

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

A finding reaches a prompt three ways: durable in Glean (searchable), recallable
by trigger (auto-loaded when its `## Triggers` fire on the message), or
always-loaded via `context/`. Trigger recall covers most needs, so **do not
routinely suggest promotion.** A finding with good triggers is already there
when it matters.

First gate: **are triggers sufficient?** If well-chosen triggers will recall the
finding whenever it is relevant, stop — do nothing about promotion. Strengthen
the triggers instead if they look weak.

Promote only when *all* of these hold AND you can state why triggers are not
enough:

- describes the **user** or the **project** itself, not your tools or skills;
- it must shape answers **even when nothing in the message would recall it** —
  a silent global default such as location or unit system, not a topic the user
  will mention when it is relevant;
- it is durable — not tied to a single task or week.

When the gate is met, **do the promotion yourself** — create the symlink, then
refresh the index:

```sh
ln -s ../.glean/findings/<id>.md .gremlin/context/<id>.md
.gremlin/.glean/glean.sh index
```

Report in your reply what you promoted and the reason triggers fell short; do
not hand the user a command to paste. Promotion is rare by design, so when a
finding clears this gate, act on it. Likewise, remove a stale always-loaded
symlink yourself when trigger recall now covers its use case — that is good
curation, not loss.

## Reply

Summarize the result briefly:

- created, revised, dropped, completed, or nothing earned;
- finding ids affected;
- whether `index` was refreshed;
- any merges or drops done in passing, with reasons;
- any findings that look like they have grown to cover two ideas — flagged
  for the next `curate` pass, not split here;
- any promotion you performed (see Promotion) — the finding id and why triggers
  were insufficient. Promote yourself rather than handing over a command, and
  only when the gate is met; otherwise say nothing about promotion.
