#!/usr/bin/env bash
# image — vision preset for inbound photos
#
# Understands images sent to the gremlin. Must be able to view an image file
# referenced by path in the prompt.
#
# Selected per item, not gremlin-wide: the Telegram bridge stamps an inbound
# photo item with `.model = image`, so the tender runs THIS preset for that
# turn instead of the default — the same mechanism memory.sh uses for
# memory-review items (see bin/tend-loop.sh per-item .model override).
#
# This preset MUST be able to view an image file referenced by path in the
# prompt. The item's instructions.md points at a scaled preview (and the
# full-resolution original); the tender appends their absolute paths under
# `## attachments`. Point this at a vision-capable invocation, for example:
#
#   # Claude — include Read so it can open the image file:
#   exec claude -p --model claude-sonnet-4-6 --allowedTools "Bash Read"
#
#   # Codex — gpt-5.x reads images referenced on disk natively:
#   exec codex --dangerously-bypass-approvals-and-sandbox exec \
#     --skip-git-repo-check --model gpt-5.5 -
#
# By default it delegates to the gremlin's default preset. Override on the host
# if the default is not vision-capable.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$script_dir/default.sh"
