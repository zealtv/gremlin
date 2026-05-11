#!/usr/bin/env bash
# memory - delegates to default
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$script_dir/default.sh"
