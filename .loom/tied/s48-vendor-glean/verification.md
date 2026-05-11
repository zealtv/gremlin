# s48-vendor-glean verification

- Vendored canonical Glean script from `/Users/bob/repos/glean/.glean/glean.sh`.
- Vendored canonical Glean README from `/Users/bob/repos/glean/README.md`.
- Seeded `.gremlin/.glean/in/`, `findings/`, `out/`, and `dropped/`.
- Added Gremlin-local `.gremlin/.glean/distil.md`.
- Added executable `.gremlin/models/memory.sh` as a thin wrapper around
  `default.sh`.
- Documented `.glean/` as the memory workbench, `memory.sh` as the review
  alias, and promotion by symlink into `context/`.

Checks run:

```sh
.gremlin/.glean/glean.sh status
.gremlin/.glean/glean.sh index
bash -n .gremlin/models/memory.sh .gremlin/.glean/glean.sh
diff -q /Users/bob/repos/glean/.glean/glean.sh .gremlin/.glean/glean.sh
diff -q /Users/bob/repos/glean/README.md .gremlin/.glean/README.md
PATH=/usr/bin:/bin .gremlin/models/memory.sh </dev/null
```

The restricted `PATH` wrapper check reached `models/default.sh` and failed at
the configured `claude` executable, confirming that `memory.sh` delegates rather
than carrying its own model invocation.
