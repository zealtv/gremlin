# s34-commands-folder

Create `.gremlin/commands/` with a `README.md` describing the contract. Commands are bash scripts at the top of `commands/`. The convention:

- First comment line of each script is its one-line summary (used by `/help`).
- Args → stdout; errors → stderr with non-zero exit.
- No-args invocation should be informative (list options, print current state) when the command takes a setting.

No commands ship in this stitch. Empty folder + README, same shape as `tools/`.

**Verify:** `cat .gremlin/commands/README.md` describes the contract; folder exists.
