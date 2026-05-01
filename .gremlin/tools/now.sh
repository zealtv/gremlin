#!/usr/bin/env bash
# now.sh — prints the current LOCAL time in ISO-8601 (with offset).
# Groundhog reads local time; the gremlin's user thinks in local time;
# so the canonical "now" is local. Internal scripts use UTC directly via
# `date -u`; this tool is the LLM's view of the clock.
set -euo pipefail
date +%Y-%m-%dT%H:%M:%S%z
