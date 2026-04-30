#!/usr/bin/env bash
# llm.sh — the single LLM seam.
#
# To swap models, change the command at the bottom of this file.
# Examples:
#   claude -p           # Anthropic Claude CLI (default)
#   gemini -p           # Google Gemini CLI
#   llm                 # simonw's llm CLI
#   ollama run <model>  # local model via ollama
#
# Contract: read prompt from args (joined) or stdin; print reply to stdout.
# Everything else in the gremlin is LLM-agnostic — model-specific concerns
# (flags, system prompts, allowed tools) live here and only here.

set -euo pipefail

if [ "$#" -gt 0 ]; then
  prompt="$*"
else
  prompt="$(cat)"
fi

printf '%s' "$prompt" | claude -p
