#!/usr/bin/env bash
# now.sh — prints the current UTC time in ISO-8601.
set -euo pipefail
date -u +%Y-%m-%dT%H:%M:%SZ
