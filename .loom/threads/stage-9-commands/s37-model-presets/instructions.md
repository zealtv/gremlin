# s37-model-presets

Define the preset format and wire `bin/llm.sh` to use it.

**Format.** Each preset is an env-style file at `.gremlin/models/<alias>.env`:

```bash
# default.env
MODEL=claude-sonnet-4-6
EXTRA_FLAGS=""
```

```bash
# fast.env
MODEL=claude-haiku-4-5
EXTRA_FLAGS=""
```

```bash
# deep.env
MODEL=claude-opus-4-7
EXTRA_FLAGS="--thinking high"   # placeholder; real flag depends on the CLI
```

Ship `default.env`, `fast.env`, `deep.env` in the canonical. Users add more by dropping files.

**Active selection.** `.gremlin/.model` contains the alias name (just `fast`, no path, no extension). If the file is missing, `default` is assumed.

**llm.sh wiring.** Read `.model`, source `models/<alias>.env`, pass `--model "$MODEL"` and any `$EXTRA_FLAGS` to the claude CLI. Keep all CLI-specific concerns inside llm.sh; the rest of the gremlin only knows about aliases.

If a preset doesn't exist, fall back to `default` and log a one-liner to stderr.

**Verify:** with `.gremlin/.model` containing `fast`, calling `bin/llm.sh "say hi"` runs against the fast model. Switching `.model` to `deep` switches the model on the next invocation. Removing `.model` falls back to `default`.
