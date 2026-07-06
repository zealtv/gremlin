#!/usr/bin/env bash
# ollama llama3.2

set -euo pipefail

if [ -d "${HOME:-}/.local/bin" ]; then
  PATH="$HOME/.local/bin:$PATH"
fi
export PATH

command -v ollama >/dev/null 2>&1 || { echo 'ollama not found — install it from https://ollama.com/download' >&2; exit 1; }

# No API key needed; runs against a local ollama server.
exec ollama run llama3.2
