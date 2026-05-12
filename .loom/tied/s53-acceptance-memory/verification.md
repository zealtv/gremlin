# s53-acceptance-memory verification

Acceptance was run in a disposable install at
`/private/tmp/gremlin-s53-host`, created from the current canonical `.gremlin`
via `install.sh` and a local tarball.

The disposable gremlin used a deterministic `models/default.sh` test preset:

- when run through a memory-review item, it created
  `.gremlin/.glean/findings/durable-preference.md` and ran
  `.gremlin/.glean/glean.sh index`;
- it logged the active model alias to `.gremlin/.acceptance-model-log`;
- on the recall prompt, it answered only if the promoted finding text appeared
  in the assembled prompt through `context/`.

Checks run:

```sh
GREMLIN_INSTALL_URL=file:///private/tmp/gremlin-s53.tar.gz ./install.sh /private/tmp/gremlin-s53-host

# Durable session:
printf '## user -- acceptance\nPlease remember this durable preference: I prefer concise acceptance answers.\n' > .gremlin/transcript.md
./.gremlin/commands/new.sh
find .gremlin/.nest/in -maxdepth 2 -type f -print
cat .gremlin/.nest/in/memory-review-2026-05-11/.model
./.gremlin/bin/tend-loop.sh
cat .gremlin/.acceptance-model-log
find .gremlin/.nest/out -maxdepth 2 -type f -print
sed -n '1,120p' .gremlin/.glean/findings/durable-preference.md
cat .gremlin/.glean/findings/INDEX.md

# Promotion and recall:
ln -sf ../.glean/findings/durable-preference.md .gremlin/context/durable-preference.md
./.gremlin/commands/discard.sh
./.gremlin/.nest/nestling.sh ingest /tmp/gremlin-s53-recall.md recall.md
./.gremlin/bin/tend-loop.sh
tail -n 12 .gremlin/transcript.md

# Discard:
./.gremlin/commands/discard.sh
./.gremlin/commands/new.sh
./.gremlin/commands/discard.sh
```

Results:

- `/new` rotated `transcript.md` into `transcript-archive/` and queued
  `.nest/in/memory-review-2026-05-11/`.
- The review item contained `instructions.md` and `.model`.
- `.model` contained `memory`.
- `tend-loop.sh` processed the review item and moved it into `.nest/out/`.
- `.acceptance-model-log` showed `memory` for the review, confirming the
  per-item alias and `models/memory.sh` delegation path.
- The review created `findings/durable-preference.md`.
- `findings/INDEX.md` was refreshed with `durable-preference`.
- Promoting the finding by symlink into `context/` made the recall prompt answer:
  `Your durable preference is concise acceptance answers.`
- `/discard` archived temporary sessions without increasing the
  memory-review item count or finding count.
- `/new` queued a memory-review item.
- `/discard` did not increase the memory-review item count.

This proves the memory loop at the protocol level. It does not evaluate the
quality of a real model's distillation judgment; that is the purpose of the
field-use stitch.
