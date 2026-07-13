#!/usr/bin/env bash
# script-as-model demo (no LLM)
#
# A model preset is just an executable that reads the prompt on stdin
# and writes a reply on stdout. Nothing requires it to call an LLM.
# This preset echoes the incoming item body back, prefixed with
# "echo:". Use it as a starting point for script-powered gremlins —
# routers, fixed-response bots, lookup tables, local rule engines, or
# anything else that needs a deterministic reply without a model.
#
# Switch to it with `/model echo` in the TUI, or
# `gremlin say /model echo` from a script.

set -euo pipefail

# bin/tend-loop.sh assembles the prompt as identity + context + the full
# transcript; the active message to answer is the LAST turn of that
# transcript, appended just before the model runs. Turns are headed with
# the stable `## <role> — <iso>` convention, so the incoming body is simply
# everything after the final turn header:
#
#   ## user — <iso>   ← the active turn's header (last in the prompt)
#   <body>            ← what we want
#
# Track that documented header contract rather than prompt whitespace:
# reset at every turn header, keep what follows the last one, then trim
# trailing blank lines. Layout-independent — unaffected by how many context
# sections or transcript turns precede it, and by blank lines in the body.
body="$(awk '
  /^## (user|assistant|system) — / { body = ""; capturing = 1; next }
  capturing { body = body $0 ORS }
  END { sub(/\n+$/, "", body); printf "%s", body }
')"

printf 'echo: %s\n' "$body"

# --- How to extend this script ----------------------------------------
#
# The variable $body now holds the incoming item body. Swap the
# `printf` above for whatever logic you want. A few sketches:
#
# 1. Keyword router — match on the first word and dispatch:
#
#      case "$body" in
#        weather*)  curl -s "https://wttr.in/?format=3" ;;
#        joke*)     shuf -n1 "$HOME/.jokes" ;;
#        *)         echo "I only know: weather, joke" ;;
#      esac
#
# 2. Static FAQ — a here-doc lookup, no network:
#
#      case "$body" in
#        *hours*)   echo "Open 9–5 weekdays." ;;
#        *address*) echo "123 Example St." ;;
#        *)         echo "Ask about hours or address." ;;
#      esac
#
# 3. Local model — pipe the body to a non-cloud runner:
#
#      printf '%s\n' "$body" | ollama run llama3.2
#
# 4. HTTP wrapper — call your own endpoint:
#
#      curl -sS https://api.example.com/reply \
#        --data-urlencode "q=$body"
#
# 5. Full prompt — if you want everything (identity, context,
#    transcript, body), drop the awk and just `cat` stdin into your
#    handler. The body extraction above is only useful when you want
#    just the incoming item.
#
# Anything that exits 0 with a reply on stdout works. Exit non-zero to
# signal failure; tend-loop will surface it.
