# Example model presets

Runnable reference presets showing how to wire a model harness into a
gremlin. They are delivered and **refreshed by `/update`** — never edit
them in place; local edits will be overwritten. Live presets one level
up (`models/*.sh`) are host-owned and never touched by `/update`.

Adopt one under a host-owned alias (paths relative to `.gremlin/`):

```sh
cp models/examples/codex.sh models/local.sh
chmod +x models/local.sh
./gremlin model local        # or `/model local` in the TUI
```

Contract (same as any preset): read the prompt on stdin, write the
reply on stdout, exit non-zero on failure. Each example checks its CLI
exists and fails loud with an install hint if not.
