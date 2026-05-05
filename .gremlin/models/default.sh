#!/usr/bin/env bash
# claude sonnet 4.6
#
# This is the default model preset. A model preset is an executable
# script that:
#   - reads the prompt on stdin
#   - writes the reply on stdout
#   - exits non-zero on failure
#
# That's the whole contract. The active preset is selected by the
# alias name in `.gremlin/.model` (or "default" if absent). Switch
# at runtime with `/model <alias>` in the TUI, or
# `bin/say /model <alias>` from a script.
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
# Verify stdin support against your installed version.
# exec gemini -p --model gemini-2.5-flash

# --- codex (openai) -----------------------------------------------------
# Requires the openai codex CLI. The `exec` subcommand is the
# non-interactive entry point; `-` makes it read the prompt from stdin.
# exec codex exec --model gpt-5.5 -
# exec codex exec --model gpt-5.4 -
# exec codex exec --model gpt-5.4-mini -
# exec codex exec --model gpt-5.3-codex -
# exec codex exec --model gpt-5.3-codex-spark -
# exec codex exec --model gpt-5.2 -



# --- pi (https://pi.dev) ------------------------------------------------
# Multi-provider agent. pi takes the prompt as a positional arg, so
# slurp stdin first.
# prompt="$(cat)"
# exec pi -p --provider anthropic --model claude-sonnet-4-6 "$prompt"
# exec pi -p --provider openai    --model gpt-4o            "$prompt"
# exec pi -p --provider google    --model gemini-2.5-flash --thinking medium "$prompt"

# --- opencode (https://opencode.ai) -------------------------------------
# Open-source coding agent harness.
# Verify against your installed version.
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
