#!/usr/bin/env bash
# claude sonnet 4.6

set -euo pipefail

if [ -d "${HOME:-}/.local/bin" ]; then
  PATH="$HOME/.local/bin:$PATH"
fi
export PATH

command -v claude >/dev/null 2>&1 || { echo 'claude not found — install the Claude Code CLI from https://docs.anthropic.com/en/docs/claude-code' >&2; exit 1; }

# Sonnet is the balanced default. `Read` is included so the gremlin can open
# files in its host folder — and so inbound photo turns (the `image` preset
# delegates here) can actually view the image referenced by path. Without
# `Read`, vision-capable models still cannot open a local file and the turn
# stalls.
exec claude -p --model claude-sonnet-4-6 --allowedTools "Bash Read"

# Variants:
# exec claude -p --model claude-haiku-4-5 --allowedTools "Bash Read"
# exec claude -p --model claude-opus-4-7  --allowedTools "Bash Read"
