# s49-init-wires-glean verification

- Updated `install.sh` to run `.glean/glean.sh init` after copying a fresh
  `.gremlin/`.
- Updated `install.sh` to refresh `.glean/findings/INDEX.md` during install.
- Added `GREMLIN_INSTALL_URL` so install-flow tests can use a local tarball
  without network access.
- Updated local development copy docs to run Glean init and index.

Checks run:

```sh
bash -n install.sh .gremlin/.glean/glean.sh
tar -czf /private/tmp/gremlin-install-test.tar.gz gremlin/.gremlin
GREMLIN_INSTALL_URL=file:///private/tmp/gremlin-install-test.tar.gz ./install.sh /private/tmp/gremlin-install-host
/private/tmp/gremlin-install-host/.gremlin/.glean/glean.sh status
/private/tmp/gremlin-install-host/.gremlin/.glean/glean.sh index
diff -q .gremlin/.glean/distil.md /private/tmp/gremlin-install-host/.gremlin/.glean/distil.md
```

The installed gremlin had `.glean/in/`, `findings/`, `out/`, and `dropped/`;
`findings/INDEX.md` existed; `status` and `index` succeeded; and `distil.md`
matched Gremlin's tuned default.

Also verified that running `glean.sh init` against an existing `.glean/distil.md`
does not overwrite local edits.
