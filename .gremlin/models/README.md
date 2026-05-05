# models

A model preset is an executable script. The active alias is read from
`.gremlin/.model` (or `default` if absent), and the gremlin runs
`models/<alias>.sh` for every reply.

## Contract

A preset:

- reads the assembled prompt on **stdin**
- writes the reply on **stdout**
- exits **non-zero** on failure

That is the whole interface. Anything that fits — claude, gemini,
codex, pi, opencode, nanocoder, ollama, a Python script wrapping an
HTTP API — is a valid preset. Different harnesses take different
flags; that's exactly why the invocation lives per-preset.

## File name = alias

`models/fast.sh` -> alias `fast`. Switch at runtime with
`/model fast` in the TUI, or `bin/say /model fast` from a script.
`/model` lists every `*.sh` in this directory,
marking the active one with `*`.

## Label

The first `# …` comment line after the shebang is the human-readable
label `/model` shows next to the alias. Keep it short.

```bash
#!/usr/bin/env bash
# fast — claude haiku
exec claude -p --model claude-haiku-4-5 --allowedTools "Bash"
```

If a preset has no label line, `/model` shows just the filename.

## Adding a preset

Drop a new file in this directory, make it executable, give it a
label. `default.sh` ships as the canonical example and contains
commented starter invocations for several agent CLIs — copy from
there, or write your own.

```sh
cp models/default.sh models/local.sh
chmod +x models/local.sh
$EDITOR models/local.sh   # uncomment one block, drop the rest
./.gremlin/bin/say /model local
```

## Permissions

There is no enforced sandbox at the gremlin layer. Each harness has
its own permissions model — claude has `--allowedTools`, others have
their equivalents — and the appropriate flag goes inside the preset.
The convention is to host a gremlin in a directory where broad
filesystem reach is acceptable. See `docs/composition.md` for notes on
OS-level isolation.
