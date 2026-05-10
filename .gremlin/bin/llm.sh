#!/usr/bin/env bash
# llm.sh — the single LLM seam.
#
# The active preset is `models/<alias>.sh`. Alias precedence:
#   1. $GREMLIN_MODEL  — per-call override (e.g. tend-loop sets this when
#                        the claimed item directory contains a .model file)
#   2. .gremlin/.model — gremlin-wide default (set via /model <alias>)
#   3. "default"       — built-in fallback
#
# A preset is an executable script that reads the prompt on stdin and
# writes the reply on stdout. Edit `models/default.sh` (or drop new
# `models/<alias>.sh` files) to swap CLIs or add presets.

set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS_DIR="$GREMLIN_DIR/models"
ACTIVE_FILE="$GREMLIN_DIR/.model"

alias_name="default"
if [ -f "$ACTIVE_FILE" ]; then
  candidate="$(tr -d '[:space:]' < "$ACTIVE_FILE")"
  [ -n "$candidate" ] && alias_name="$candidate"
fi
if [ -n "${GREMLIN_MODEL:-}" ]; then
  candidate="$(printf '%s' "$GREMLIN_MODEL" | tr -d '[:space:]')"
  [ -n "$candidate" ] && alias_name="$candidate"
fi

preset="$MODELS_DIR/$alias_name.sh"
if [ ! -x "$preset" ]; then
  echo "llm.sh: preset '$alias_name' not found, falling back to default" >&2
  preset="$MODELS_DIR/default.sh"
fi

if [ "$#" -gt 0 ]; then
  prompt="$*"
else
  prompt="$(cat)"
fi

printf '%s' "$prompt" | "$preset"
