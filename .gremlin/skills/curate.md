---
name: curate
triggers:
  - user asks to curate, tidy, prune, consolidate, or sweep findings or memory
  - user says "curate findings", "review the corpus", "merge findings", "tidy memory", "prune findings"
---

# curate

Use this skill for **deliberate, corpus-wide** review of Glean findings —
sitting with `findings/` as a whole and making it tidier. This is distinct
from the `distil` skill, which reacts to incoming material and only touches
the neighbourhood it fetched.

Curate is for the kind of work that does not happen on its own:

- merging findings that have grown to overlap;
- splitting findings that have grown to cover two distinct ideas;
- adding `## Associations` wikilinks that make related findings easier to
  reach;
- retiring findings that no longer earn their place;
- tightening or filling in `## Triggers` so strict `fetch` keeps working.

Curation is a judgment pass. Prefer doing less, well, over doing a lot
shallowly.

## Load The Corpus

1. Read `.gremlin/.glean/distil.md` for the local distillation brief — the
   same brief shapes what counts as a good finding.
2. Read `.gremlin/.glean/findings/INDEX.md` end to end. This is the whole
   corpus in one glance.
3. If the user gave a scope ("curate the testing findings", "look at
   everything about the loom"), narrow to that. If they did not, pick a
   cluster yourself — do not try to curate the whole corpus in one pass.

## Survey

Before changing anything, write down (to yourself, not to disk) what you see:

- **Clusters** — sets of findings that sit near each other in subject.
- **Overlaps** — pairs or triples that cover substantially the same ground.
- **Overgrown findings** — single files that have come to cover two distinct
  ideas. Look for findings whose `## Triggers` pull in two unrelated query
  shapes, or whose body has a second `# `-level concept buried in it.
- **Thin findings** — short, vague, or missing `## Triggers`. Strict fetch
  cannot reach a finding without triggers, so a thin finding is effectively
  invisible.
- **Stale findings** — contradicted by newer findings, by `context/`, or by
  the current state of the project.
- **Missing associations** — pairs where one finding obviously implies or
  depends on another but neither lists the other under `## Associations`.

Use fetch to confirm overlaps before merging:

```sh
.gremlin/.glean/glean.sh fetch <terms...>
.gremlin/.glean/glean.sh fetch --all <terms...>
```

## Act, sparingly

Pick a small, coherent set of changes for this pass. Three or four moves
that improve the corpus is a better outcome than fifteen that churn it.

**Merge** when two findings cover the same ground:

- pick the better home (clearer title, better triggers, more accurate body);
- revise it to absorb anything the other one had that was worth keeping;
- drop the redundant one with a reason naming the merge target.

```sh
.gremlin/.glean/glean.sh drop <id> "merged into <other-id>"
```

**Split** when a finding clearly covers two distinct ideas:

- write the two new findings as separate flat files under `findings/`;
- drop the original with a reason naming the two successors;
- splits are riskier than merges — if you are not sure, leave a note in your
  reply and let the user decide.

```sh
.gremlin/.glean/glean.sh drop <id> "split into <a-id> and <b-id>"
```

**Retire** a stale finding:

```sh
.gremlin/.glean/glean.sh drop <id> "<why it no longer earns a place>"
```

A drop reason is not optional. The `dropped/` tray is a durable reflection
drawer; future-you will want to know what was retired and why.

**Tighten** a finding in place by revising its file directly:

- add or fill in `## Triggers` — strict fetch reads only this section, the
  id, the title, and the description, so missing triggers means the finding
  is unreachable;
- add `## Associations` wikilinks where they help retrieval;
- shorten bloated bodies; the catalog bullet is the load-bearing surface,
  not the body.

After any create, revise, or drop, refresh the index:

```sh
.gremlin/.glean/glean.sh index
```

## Promotion review

Curation is the right moment to reconsider what lives in `.gremlin/context/`
(always-loaded) versus what stays in `findings/` (fetched on demand).

For each finding currently symlinked into `context/`, ask:

- does it still describe the user or the project itself?
- would a session that never fetched it still need it?
- is it durable, not tied to a specific past task?

If a `context/` symlink no longer earns its always-loaded slot, **suggest
demotion** in your reply with a ready-to-paste command. Do not remove it
yourself.

```sh
rm .gremlin/context/<id>.md
```

For findings not currently in `context/`, apply the same criteria from the
`distil` skill — describes user or project, durable, agent should act on it
without reminding — and **suggest promotion** with a ready-to-paste command:

```sh
ln -s ../.glean/findings/<id>.md .gremlin/context/<id>.md
```

Never promote or demote autonomously unless the user explicitly asked.
Promotion is cheap to do and expensive to undo — keep it a human gesture.

## Constraints

- Bound the pass. Pick a cluster or a scope and stay in it. Do not rummage.
- Prefer merge over split. Splits introduce two new findings; merges remove
  one and tighten the survivor.
- Never drop without a reason.
- Never silently rewrite a finding's intent. If the body needs to change
  meaningfully, the right move is usually a drop plus a fresh finding, not
  an in-place rewrite — drops leave a reflection trail; in-place rewrites
  do not.
- Leave thin or unclear findings alone if you cannot improve them — better
  to flag them in your reply than to half-fix them.

## Reply

Summarise the pass briefly:

- the scope you took (cluster, theme, or "user-requested");
- merges done, with source ids and merge target;
- drops done, with reasons;
- splits done or noted-but-not-done, with proposed successor ids;
- tightening: triggers added, associations added, bodies shortened;
- promotion or demotion suggestions, each with a ready-to-paste command;
- anything you noticed but deliberately did not touch (so the next pass
  has a starting point).
