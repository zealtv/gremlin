#!/usr/bin/env bash
# codex gpt-5.5

set -euo pipefail

if [ -d "${HOME:-}/.local/bin" ]; then
  PATH="$HOME/.local/bin:$PATH"
fi
export PATH

command -v codex >/dev/null 2>&1 || { echo 'codex not found — install with npm install -g @openai/codex' >&2; exit 1; }

# Requires the openai codex CLI. The `exec` subcommand is the
# non-interactive entry point; `-` makes it read the prompt from stdin.
# Gremlin usually runs from a normal host folder rather than a git repo,
# so Codex presets should skip the repo trust check.
exec codex --ask-for-approval on-request exec --skip-git-repo-check --model gpt-5.5 -s workspace-write -
# exec codex --ask-for-approval on-request exec --skip-git-repo-check --model gpt-5.2 -s workspace-write -
# exec codex --ask-for-approval never exec --skip-git-repo-check --model gpt-5.5 -s danger-full-access -
# exec codex --ask-for-approval on-request exec --skip-git-repo-check --model gpt-5.4 -s workspace-write -
# exec codex --ask-for-approval on-request exec --skip-git-repo-check --model gpt-5.4-mini -s workspace-write -
# exec codex --ask-for-approval on-request exec --skip-git-repo-check --model gpt-5.3-codex -s workspace-write -
# exec codex --ask-for-approval on-request exec --skip-git-repo-check --model gpt-5.3-codex-spark -s workspace-write -
# exec codex --ask-for-approval on-request exec --skip-git-repo-check --model gpt-5.2 -s workspace-write -
