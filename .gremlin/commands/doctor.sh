#!/usr/bin/env bash
# doctor — repair gremlin-managed files
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$GREMLIN_DIR/bin/doctor.sh" "$@"
