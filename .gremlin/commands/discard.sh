#!/usr/bin/env bash
# discard — start fresh without memory review
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$GREMLIN_DIR/bin/archive.sh"
echo "fresh transcript"
echo "memory review skipped"
