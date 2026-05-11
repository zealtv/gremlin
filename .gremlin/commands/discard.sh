#!/usr/bin/env bash
# discard — alias for /discard-session
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$GREMLIN_DIR/commands/discard-session.sh" "$@"
