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
# Tool permissions: a gremlin's sandbox is its host directory — the folder
# that contains `.gremlin/`. Within that, broad bash is acceptable: the
# tender needs to read skills on demand (`cat skills/<name>.md`), write
# scheduled work to `.groundhog/`, and invoke `./tools/*`. Granting
# unrestricted Bash is fine because the caller's cwd is the gremlin root
# and the user is expected to host gremlins in sensible directories.
# Equivalent flags for other CLIs go in the swap-in command above.

set -euo pipefail

if [ "$#" -gt 0 ]; then
  prompt="$*"
else
  prompt="$(cat)"
fi

printf '%s' "$prompt" | claude -p --allowedTools "Bash"
