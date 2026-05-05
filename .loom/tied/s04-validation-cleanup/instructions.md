# s04-validation-cleanup

Validate the docs/install cleanup.

Acceptance:

- Shell scripts touched by the install/update path pass syntax checks.
- Temp install proves `.gremlin/.upstream` is present.
- Stale references to `init.sh`, `DEVELOPING.md`, and `say` as primary UI are
  removed or intentionally kept only as historical loom records.
- The parent stitch can be tied.
