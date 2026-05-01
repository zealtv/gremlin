#!/usr/bin/env bash
# new — start a fresh transcript (rotates current into transcript-archive/)
set -euo pipefail
GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$GREMLIN_DIR/bin/archive.sh"
echo "fresh transcript"
