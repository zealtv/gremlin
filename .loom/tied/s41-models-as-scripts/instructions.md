# s41-models-as-scripts

Make model presets fully model- and harness-agnostic. Each preset becomes a small executable bash script that consumes the prompt on stdin and writes the reply to stdout. `llm.sh` collapses to a thin dispatcher. `EXTRA_FLAGS`/`MODEL` go away — the preset *is* the invocation.

Standalone stitch. Independent of stage-11.

## Why

Today (`bin/llm.sh:46-64`):

- `llm.sh` hardcodes `claude -p --allowedTools "Bash"` as the only invocation shape.
- Presets (`models/*.env`) define `MODEL=` and `EXTRA_FLAGS=` — fields that only make sense for claude.
- The header at `llm.sh:1-13` claims you can swap CLIs by editing the bottom of the file, but doing so also requires rewriting the preset format. The seam is in the wrong place.

A gremlin should be able to mix claude, gemini, codex, pi, opencode, nanocoder, ollama, anything — even within one models directory — without touching `llm.sh`.

## Shape

### Preset = executable script

`models/<alias>.sh` is an executable that:
- Reads the assembled prompt on stdin.
- Writes the reply on stdout.
- Exits non-zero on failure.

That's the whole contract. Anything that fits — claude, gemini, ollama, a custom Python wrapper around an HTTP API — is a valid preset.

### Label convention

First commented line after the shebang is the human-readable label, surfaced by `/model`:

```bash
#!/usr/bin/env bash
# balanced — claude sonnet 4.6
exec claude -p --model claude-sonnet-4-6 --allowedTools "Bash"
```

`commands/model.sh` greps the first `^# ` line after the shebang for the label. If absent, just print the filename.

### `llm.sh`

Collapses to:

```bash
#!/usr/bin/env bash
set -euo pipefail
GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

alias_name="$(tr -d '[:space:]' < "$GREMLIN_DIR/.model" 2>/dev/null || true)"
[ -n "$alias_name" ] || alias_name="default"

preset="$GREMLIN_DIR/models/$alias_name.sh"
if [ ! -x "$preset" ]; then
  echo "llm.sh: preset '$alias_name' not found, falling back to default" >&2
  preset="$GREMLIN_DIR/models/default.sh"
fi

prompt="${*:-$(cat)}"
printf '%s' "$prompt" | "$preset"
```

No more `MODEL`, `EXTRA_FLAGS`, sourcing, or hardcoded CLI name. The header comment block in llm.sh shrinks to a one-paragraph note: "active preset is `models/<alias>.sh`; `.model` selects the alias; default is `default`."

### `commands/model.sh`

- Glob `models/*.sh` instead of `models/*.env`.
- For each preset, extract the label from the first `# ` line after the shebang. If none, show filename only.
- Same active-marker (`*`) and selection logic.

### Canonical ships only `default.sh`

Today canonical ships `default.env`, `fast.env`, `deep.env`. After this stitch, canonical ships **only `default.sh`**. The names `fast` and `deep` are reserved for the user — they often want those names for their own preferences, and `/update` (s42) preserves user-created files but overwrites canonical ones.

`default.sh` is the only preset shipped *and* the documentation surface — its commented examples show the user how to add their own.

## `default.sh` content

This file is load-bearing — it's the user's introduction to the preset model and the menu of available harnesses. Treat it as documentation that happens to be runnable.

```bash
#!/usr/bin/env bash
# default — claude sonnet 4.6
#
# A model preset is an executable script that:
#   - reads the prompt on stdin
#   - writes the reply on stdout
#   - exits non-zero on failure
#
# That's the whole contract. The active preset is selected by the
# alias name in `.gremlin/.model` (or "default" if absent). Switch
# at runtime with `say "/model <alias>"`.
#
# Add presets by dropping `models/<alias>.sh` files. Each preset is
# its own invocation — different harnesses take different flags, and
# this is where those differences live. Below are starter examples
# for several agent harnesses; uncomment and adapt one, or write
# your own.
#
# Permissions / sandboxing: each harness has its own model. Claude's
# `--allowedTools "Bash"` is the equivalent of "no real sandbox,"
# matching the gremlin's host-directory convention. Other harnesses'
# equivalents go here too.

set -euo pipefail

# --- claude (anthropic) -------------------------------------------------
# Currently active. Sonnet is the balanced default.
exec claude -p --model claude-sonnet-4-6 --allowedTools "Bash"

# --- claude variants ----------------------------------------------------
# exec claude -p --model claude-haiku-4-5 --allowedTools "Bash"
# exec claude -p --model claude-opus-4-7  --allowedTools "Bash"

# --- gemini (google) ----------------------------------------------------
# Requires the gemini CLI (https://github.com/google-gemini/gemini-cli).
# exec gemini -p --model gemini-2.5-flash

# --- codex (openai) -----------------------------------------------------
# Requires the openai codex CLI. Verify exact flags against your
# installed version.
# exec codex --model gpt-5 -

# --- pi (https://pi.dev) ------------------------------------------------
# Multi-provider agent. Stdin is merged into the print-mode prompt.
# exec pi -p --provider anthropic --model claude-sonnet-4-6
# exec pi -p --provider openai    --model gpt-4o
# exec pi -p --provider google    --model gemini-2.5-flash --thinking medium

# --- opencode (https://opencode.ai) -------------------------------------
# Open-source coding agent harness.
# exec opencode run --model anthropic/claude-sonnet-4-6

# --- nanocoder (https://github.com/Nano-Collective/nanocoder) -----------
# Open-source local-first coding agent. Verify stdin support against
# your installed version; if it doesn't accept stdin, wrap with a
# small shim that reads stdin and passes via `run "<text>"`.
# exec nanocoder --provider openrouter --model google/gemini-2.5-flash run

# --- ollama (local) -----------------------------------------------------
# No API key needed; runs against a local ollama server.
# exec ollama run llama3.2

# --- custom http wrapper ------------------------------------------------
# If your harness has no CLI, write a small wrapper. Example using curl:
#   prompt="$(cat)"
#   curl -sS https://api.example.com/v1/chat \
#     -H "Authorization: Bearer $API_KEY" \
#     -d "$(jq -Rsn --arg p "$prompt" '{prompt: $p}')" \
#   | jq -r '.reply'
```

The above is the spec for what ships. Verify each commented example against current CLIs at build time — flags drift. Where uncertain, leave a `# verify against your installed version` note rather than ship a wrong invocation.

## Migration notes

- Existing personal copies have `default.env`, `fast.env`, `deep.env` and a `.model` pointing at one of them. After update, `default.sh` is the new canonical preset.
- The user (sole personal-copy owner currently) will tidy `*.env` files manually. No migration helper needed.
- `.model` value still resolves correctly: `default` → `default.sh` if user follows through; otherwise llm.sh logs the fallback.

## Verify

1. After the stitch, `models/` contains only `default.sh` in canonical.
2. `bin/llm.sh "say hi"` produces a reply via `default.sh`.
3. Create `models/fast.sh` with a haiku invocation. `say "/model fast"`. Next reply uses haiku.
4. `/model` lists `default` and `fast`, with the active one marked, each shown with its label from the first `# ` line.
5. Create `models/local.sh` invoking `ollama run llama3.2` (assuming ollama is installed). Switch to it. Reply comes from the local model.
6. Switch back to a non-existent preset (`say "/model bogus"`). `model.sh` rejects it with a list of available presets. `.model` is unchanged.
7. `bin/llm.sh` contains no reference to `claude`, `MODEL`, or `EXTRA_FLAGS`.

## README updates

- README.md section on `bin/llm.sh` (around `:124`): reframe. "One file routes prompts to the active preset. Each preset is a small script that takes the prompt on stdin and emits a reply." Drop the "edit llm.sh to swap CLIs" framing — that's now per-preset.
- Add a short `models/README.md` that documents the contract (stdin → stdout, label convention, file name = alias) and points to `default.sh` for examples.

## Out of scope

- Streaming output. Presets that stream just stream; the gremlin currently consumes the whole reply at once and that doesn't change.
- Per-preset environment files (e.g. API keys per provider). Keep secrets in the user's shell environment or a sourced file the preset itself reads. Don't add a parallel config layer.
- A `/model add` helper. Editing `models/<name>.sh` directly is the path; commands shouldn't generate code.
