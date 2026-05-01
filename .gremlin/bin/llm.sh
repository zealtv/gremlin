#!/usr/bin/env bash
# llm.sh — the single LLM seam.
#
# To swap CLIs, edit the invocation at the bottom of this file.
# Examples:
#   claude -p           # Anthropic Claude CLI (default)
#   gemini -p           # Google Gemini CLI
#   llm                 # simonw's llm CLI
#   ollama run <model>  # local model via ollama
#
# Contract: read prompt from args (joined) or stdin; print reply to stdout.
# Everything else in the gremlin is LLM-agnostic — model-specific concerns
# (flags, system prompts, allowed tools) live here and only here.
#
# Tool permissions: there is no enforced sandbox — the convention is that a
# gremlin lives in a directory where unrestricted bash is acceptable. The
# tender needs broad bash to read skills on demand, write to `.groundhog/`,
# and invoke tools. See README "Sandboxing & sharing" + DEVELOPING.md for
# OS-level isolation options. Equivalent allow-flags for other CLIs go in
# the swap-in command below.
#
# Model presets: the active alias is read from `.gremlin/.model` (or
# `default` if absent). Each preset is `.gremlin/models/<alias>.env` and
# defines at minimum `MODEL` and `EXTRA_FLAGS`. Edit the files to add
# presets; users select between them with `say "/model <alias>"`.

set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS_DIR="$GREMLIN_DIR/models"
ACTIVE_FILE="$GREMLIN_DIR/.model"

alias_name="default"
if [ -f "$ACTIVE_FILE" ]; then
  alias_name="$(tr -d '[:space:]' < "$ACTIVE_FILE")"
  [ -n "$alias_name" ] || alias_name="default"
fi

preset="$MODELS_DIR/$alias_name.env"
if [ ! -f "$preset" ]; then
  echo "llm.sh: preset '$alias_name' not found, falling back to default" >&2
  alias_name="default"
  preset="$MODELS_DIR/$alias_name.env"
fi

MODEL=""
EXTRA_FLAGS=""
if [ -f "$preset" ]; then
  # shellcheck disable=SC1090
  source "$preset"
fi

if [ "$#" -gt 0 ]; then
  prompt="$*"
else
  prompt="$(cat)"
fi

# shellcheck disable=SC2086
if [ -n "$MODEL" ]; then
  printf '%s' "$prompt" | claude -p --model "$MODEL" --allowedTools "Bash" $EXTRA_FLAGS
else
  printf '%s' "$prompt" | claude -p --allowedTools "Bash" $EXTRA_FLAGS
fi
