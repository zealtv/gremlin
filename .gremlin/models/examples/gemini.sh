#!/usr/bin/env bash
# gemini 2.5 flash

set -euo pipefail

if [ -d "${HOME:-}/.local/bin" ]; then
  PATH="$HOME/.local/bin:$PATH"
fi
export PATH

command -v gemini >/dev/null 2>&1 || { echo 'gemini not found — install with npm install -g @google/gemini-cli' >&2; exit 1; }

# Requires the gemini CLI (https://github.com/google-gemini/gemini-cli).
# `-p` takes the prompt as its argument, so slurp stdin first — piping
# stdin while passing a bare `-p` misparses the flags. Verify against
# your installed version. Gemini's trusted folders feature is optional
# and disabled by default; if you enable it, trust the gremlin host
# folder or its parent directory.
prompt="$(cat)"
exec gemini --model gemini-2.5-flash -p "$prompt"
