# s01-install-simplification

Make `.gremlin/` self-contained for install/update.

Acceptance:

- `.gremlin/.upstream` is committed with the canonical tarball URL.
- `install.sh` no longer writes `.upstream`; it copies the file from the
  downloaded `.gremlin/`.
- `init.sh` is removed.
- Local install docs use direct `cp -R .gremlin <host>/.gremlin`.
