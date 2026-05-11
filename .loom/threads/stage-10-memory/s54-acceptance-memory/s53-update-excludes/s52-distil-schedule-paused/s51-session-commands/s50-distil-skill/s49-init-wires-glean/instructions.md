# s49-init-wires-glean

**Outcome.** Installing or copying a fresh gremlin leaves `.gremlin/.glean/`
initialized and ready for memory review.

This stitch depends on Glean being vendored below it in the Loom chain. Only
tend it after `s48-vendor-glean` ties.

## Scope

- Update install/init flow so `.gremlin/.glean/glean.sh init` runs for new
  gremlins.
- Ensure required trays exist:
  - `.glean/in/`
  - `.glean/findings/`
  - `.glean/out/`
  - `.glean/dropped/`
- Ensure `findings/INDEX.md` exists after init.
- Ensure Gremlin's canonical `.glean/distil.md` is present in new installs.
- Do not overwrite an existing local `.glean/distil.md` during normal local
  initialization unless this is explicitly part of canonical install behavior.

## Constraints

- Keep Glean content-opaque to Gremlin's tender hot path.
- Do not require network access during init; vendored files should be enough.

## Verification

1. Run the install flow into a disposable host folder.
2. Confirm `.gremlin/.glean/` exists with the expected trays.
3. Run `./.gremlin/.glean/glean.sh status`.
4. Run `./.gremlin/.glean/glean.sh index` successfully.
5. Confirm `distil.md` is the Gremlin-tuned default.

## Notes

- Check both `install.sh` and any local copy/development instructions that need
  to mention Glean initialization.
