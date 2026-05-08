#!/usr/bin/env bash
# echo — script-as-model demo (no LLM)
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

# bin/tend-loop.sh assembles the prompt by concatenating gremlin.md,
# context/*.md, skills/INDEX.md, tools/README.md, the full transcript,
# and the current item body. The body therefore appears twice near
# the end of the prompt:
#
#   ## <role> — <iso>
#   <body>          ← last transcript turn
#                   ← blank line (transcript's per-turn '\n\n')
#                   ← blank line (extra '\n' from tend-loop's `echo`)
#   <body>          ← body re-emitted at end of prompt
#
# Two consecutive blank lines reliably mark that boundary regardless
# of which roles appear in the transcript, so we drop everything up to
# and including them and keep the trailing body.
body="$(awk '
  $0 == "" && prev == "" { buf = ""; prev = $0; next }
  { buf = buf $0 ORS; prev = $0 }
  END { sub(/\n+$/, "", buf); print buf }
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
