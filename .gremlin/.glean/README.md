# 🔮 glean

A tiny, file-based protocol for memory and distillation.

You glean a finding from larger work. A finding is one small unit of current
guidance — what's worth carrying forward.


```
.glean/
  glean.sh
  in/                            ← raw inbox; anything goes
  findings/
    INDEX.md                     ← generated; always-loaded surface
    example-finding-001.md       ← one flat file per finding
    example-finding-002.md
  out/                           ← inbox items after distillation; swept on retention
    foo.md
  dropped/                       ← retired findings; durable reflection drawer
    bar.md
    bar.reason.md                ← why the finding was retired
  distil.md                      ← host-local distillation instructions, editable
```

The file system is the protocol.

## The finding contract

A finding is one markdown file at `findings/<id>.md`, it only needs two things:

- **Title** — first `# ` line. 
- **Description** — first non-empty line *between* the title and the next
  heading. One sentence. 

Everything else is free prose. Findings can link to other resources. The supplied `distil.md` *suggests* common sections:

- **Triggers** — phrases under `## Triggers` (one per bullet, or comma separated) that should bring this finding to mind. They are searched by `fetch` and are the needles `recall` matches against an incoming text. Triggers are optional, but they are what makes a finding *recallable* automatically — a finding with none still surfaces through `INDEX.md`, but nothing will pull its body in by topic.
- **Associations** — wikilinks `[[id]]` under `##Associations` that resolve to `findings/<id>.md`. Associations are just bullet links - nothing parses them, but they read well and an agent can grep for backlinks trivially.
- **Context** — examples, references, and longer notes can live under `## Context`, and can be loaded on demand for leaner systems.
- **Why** - reasoning or historical context.


## Disclosure layers

Three tiers of cost, by design:

| Tier | What | When |
|---|---|---|
| **Always loaded** | `findings/INDEX.md` | A host symlinks this into its always-loaded context surface. The agent sees one bullet per finding (id + title + description). |
| **Fetched on demand** | `findings/<id>.md` body | Agent runs `fetch` to get matching paths, then reads the bodies. |
| **Recalled by trigger** | `findings/<id>.md` body | A host pipes an inbound text through `recall` and loads the matched bodies automatically, without the agent choosing to search. |
| **Read by hand** | Anything else | Long examples, references — surface a finding as a starting point and follow links. |

Promotion to always-loaded is the host's call (e.g. by symlinking a specific
finding into the host's always-context surface). Glean stays unaware of how
its output is consumed.


## Procedure

The default flow is: **ingest** raw material, **distil** it into findings, **fetch** findings on demand. Periodically, **curate** the corpus.

### Ingest

**Ingest** raw material into `in/`.
  ```sh
  ./glean.sh ingest some/note.md          # file or directory
  echo "rough thought" | ./glean.sh ingest - rough
   ```


### Distil

**Distil** is the act of turning raw material in `in/` into findings.

Read each item in `in/` and choose one of three outcomes:

- **revise** an existing finding — edit `findings/<id>.md` in place;
- **create** a new finding — write `findings/<new-id>.md` directly (a finding is just a file);
- **nothing earned** — the material doesn't merit carry-forward.

In all three cases, close the inbox item:

```sh
./glean.sh complete <in-id>     # in/<id> → out/<id>
```

`out/` is the audit residue — every inbox item that was considered passes
through it, regardless of whether a finding was produced. It's swept on
retention. Items remaining in `in/` are still awaiting distillation.

Run `./glean.sh index` after writing or revising findings to refresh `INDEX.md`.

The `distil.md` brief seeded by `init` is host-local: edit it freely to
shape distillation for *this* glean system. The protocol doesn't care what
the brief says — it only cares about the finding contract.


### Fetch

Return findings matching the query.  

Fetch has two modes. 
  - **strict** (default): matches against id, title, description, and contents of `## Triggers`. 
  - *all* (`--all`or `-a`): grep the whole file. 

Strict by default keeps the agent's context lean and rewards writers who curate their
Triggers section.

### Recall

`recall` is the inverse of `fetch`. Where `fetch` takes a query and asks *"which
findings mention these terms?"*, `recall` takes a block of text — typically an
inbound message — and asks *"which findings' triggers fire on this text?"*

```sh
./glean.sh recall "logged a protein bread and a roo burger"   # text as args
echo "$inbound_message" | ./glean.sh recall                   # or on stdin
```

It prints the path of every finding with at least one `## Triggers` phrase
occurring (case-insensitively) in the text. Findings without triggers never
match. This is the primitive a host wires into reply-time recall: pipe each
incoming message through `recall` and load the matched bodies into context, so
findings are used deterministically instead of relying on the agent to search.


### Curate

Separately from inbox work, periodically sit with `findings/` as a whole:
merge findings that overlap, split findings that have grown to cover two
ideas, add wikilinks under `## Associations`, and retire findings that no
longer earn their place.

```sh
./glean.sh drop <finding-id> "reason..."   # findings/<id>.md → dropped/
```

`dropped/` is the reflection drawer for retired ideas. It's durable — not
swept — so old reasoning remains available to read later.


## Vendoring

To add glean to another project, copy `glean.sh` and `README.md` into the
project's `.glean/` directory, then run `./.glean/glean.sh init` to seed
the trays:

```sh
mkdir -p <project>/.glean
cp glean.sh README.md <project>/.glean/
<project>/.glean/glean.sh init
```

`init` creates `in/`, `findings/`, `out/`, and `dropped/` next to itself,
and seeds `distil.md` if one is not already present. `glean.sh` operates
on the `.glean/` directory it lives in, so each vendored copy is
self-contained.

## Commands

```
./glean.sh init
./glean.sh ingest <src> [name]      # land raw material in in/ (use - for stdin)
./glean.sh complete <id>            # in/<id> → out/<id>; closes a distillation
./glean.sh drop <id> [reason...]    # findings/<id>.md → dropped/, with reason
./glean.sh index                    # regenerate findings/INDEX.md
./glean.sh fetch [--all] <q...>     # paths of findings matching query
./glean.sh recall [text...]         # paths of findings whose triggers fire on text (stdin if no args)
./glean.sh status                   # list trays
./glean.sh sweep [days]             # remove out/ entries older than N days (default 14)
```
