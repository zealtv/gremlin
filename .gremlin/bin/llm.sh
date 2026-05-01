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
#
# Tool permissions: `--allowedTools "Bash(./tools/*)"` lets the model invoke
# scripts under ./tools/ without an interactive prompt. The caller must cd
# to the gremlin root first so `./tools/` resolves correctly.
# Equivalent flags for other CLIs go in the swap-in command above.

set -euo pipefail

if [ "$#" -gt 0 ]; then
  prompt="$*"
else
  prompt="$(cat)"
fi

printf '%s' "$prompt" | claude -p --allowedTools "Bash(./tools/*)"
