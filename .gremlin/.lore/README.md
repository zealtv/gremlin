# 🐉 lore

A tiny, file-based protocol for durable reference and record.

Lore keeps complete artifacts, dates them, and lets you find them again. A
**lore item** is one captured artifact: a small catalog card beside opaque,
unchanged content.

```text
.lore/
  lore.sh
  INDEX.md                         # generated catalog; read deliberately
  items/
    2026-06-27-interaction-model/
      item.md                      # title, description, optional provenance
      content/                     # the complete captured artifact
```

The file system is the protocol.

## What lore is for

Some artifacts should remain whole: prior art, specifications, design records,
decision history, completed transcripts, source documents, and session outputs.
They are useful because they can be consulted later in their original context.

The other filesystem protocols in this family move or transform state:
[nestlings](https://github.com/zealtv/nestlings) tends an inbox,
[groundhog](https://github.com/zealtv/groundhog) materializes recurring items,
[loom](https://github.com/zealtv/loom) resolves intentions, and
[glean](https://github.com/zealtv/glean) distils current guidance. Lore is the
retention primitive.

- **Glean is memory:** small, current, revisable, and intentionally lossy.
- **Lore is the library:** complete, dated, durable, and append-and-keep.

Glean may carry forward a conclusion from lore. Lore keeps the source that lets
someone inspect how that conclusion was reached.

## The item contract

An item is a directory at `items/<YYYY-MM-DD>-<slug>/` containing exactly two
required parts:

- `item.md` — the catalog card;
- `content/` — the complete payload, whose contents lore does not interpret.

`item.md` needs only:

- **Title** — the first `# ` line.
- **Description** — the first non-empty line after the title and before the next
  heading. Keep it to one sentence; it appears in `INDEX.md`.

Everything else is free Markdown. `## Source` and `## Tags` are useful optional
conventions:

```markdown
# Interaction model specification

The accepted interaction rules and examples for the service.

## Source

`service/docs/interaction-model.md` at commit `abc123`.

## Tags

- interaction
- specification
```

The directory id records the local capture date, not necessarily the source's
creation date. A changed source is a new capture with a new id; old editions stay
where they are. Append-only is a convention, not filesystem permission theater.

## One store

Reference and historical record use the same store. The distinction describes
why someone reads an artifact, not how it must be retained. A decision record can
also be prior art, and a specification eventually becomes history.

Items are flat and date-prefixed. Lore has no type trays, collections, or user
shelves. A flat path keeps ids exact, links simple, and `ls` meaningful. If real
scale later demands partitioning, the year can be derived mechanically from every
id.

## Disclosure

Lore is dark by default.

`INDEX.md` is a generated catalog with one line per item. A human or agent reads
it when researching; it is not automatically loaded into every prompt. Item
bodies are read only after the catalog or `fetch` identifies a relevant item.

A host may deliberately symlink the index or one item into its own context
surface. That is host composition, not lore state. Lore has no automatic recall
or promotion command: an old complete artifact should not enter context merely
because an inbound message happens to contain a matching phrase.

## Procedure

### Prepare

Prepare a directory before keeping it:

```text
/tmp/interaction-model/
  item.md
  content/
    specification.md
    examples.md
```

The prepared directory must already satisfy the item contract. Lore does not land
raw bytes with placeholder metadata, because that would make an item durable
before it is findable.

### Keep

```sh
./.lore/lore.sh keep /tmp/interaction-model interaction-model
```

`keep` validates the card and payload, prefixes the slug with today's local date,
copies through `<id>.landing`, and atomically renames the complete item into place.
It never overwrites or silently numbers a collision.

The content is opaque. It may contain Markdown, source trees, images, binary
files, or a mixture. “Complete” is the keeper's judgment; lore only verifies that
the `content/` directory exists. Prepared items containing symbolic links are
rejected because a link can depend on bytes outside the retained capture.

### Index and fetch

Regenerate the catalog after keeping or directly editing an item:

```sh
./.lore/lore.sh index
```

Search ids and all catalog-card prose with strict fetch:

```sh
./.lore/lore.sh fetch "interaction model"
```

Include textual payload content when needed:

```sh
./.lore/lore.sh fetch --all "speaker identity"
```

Queries are case-insensitive fixed strings. Multiple terms are alternatives;
matching any term returns the item directory. `fetch` prints paths and leaves the
decision to read their contents to the caller. It warns when `INDEX.md` is missing
or stale.

### Inspect

```sh
./.lore/lore.sh status
```

`status` reports valid, invalid, and partial items. It refreshes the catalog when
all landed items are valid and returns a failure status when invalid items or
`.landing` remnants need attention.

## Transcripts

Lore can be the durable home for completed transcript history, but it is not a
transcript writer or rotator. A live conversation system still owns coordination
with its writer. After that system closes a transcript safely, it may prepare and
keep the transcript as an ordinary lore item.

An existing `transcript-archive/` can remain a producer or spool while that
handoff is integrated. Lore should only replace its permanent-retention role once
every memory-review and archive path has been updated.

## Permanence and backup

Lore has no `drop`, `retire`, `expire`, or `sweep` command. Manual filesystem
deletion remains possible and visible, but it is not normalized as protocol
workflow. Lore also does not enforce immutability, deduplicate content, encrypt
secrets, synchronize replicas, or implement legal holds.

Git policy belongs to the host. A project may track safe lore; a deployment may
ignore instance-local items. **Ignored is not backed up.** Any deployment claiming
durable lore must copy the complete `items/` tree to another failure domain—such
as a private remote, filesystem snapshots, or replicated storage—and test that it
can restore it. `INDEX.md` is disposable; `items/` is the asset.

## Vendoring

Copy the script and README into a project's `.lore/` directory, then initialize
the store:

```sh
mkdir -p <project>/.lore
cp .lore/lore.sh README.md <project>/.lore/
<project>/.lore/lore.sh init
```

`lore.sh` resolves all state relative to the `.lore/` directory it lives in, so
each vendored copy is self-contained. Its small title/description extraction,
fixed-string search, and atomic-index mechanics intentionally resemble glean but
are copied locally: neither protocol depends on a shared runtime component.

## Commands

```text
./lore.sh init
./lore.sh keep <prepared-item-dir> <slug>
./lore.sh index
./lore.sh fetch [--all] <query...>
./lore.sh status
```
