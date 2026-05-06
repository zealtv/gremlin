# s02-rewire-tui-and-say

Replace inline slash dispatch in TUI and `say.sh` with calls to
`bin/slash.sh`. Behavior must be identical to before.

## Files

- `.gremlin/bin/say.sh` — collapse the slash stanza (lines 28–51) to:
  detect leading `/`, then `exec "$GREMLIN_DIR/bin/slash.sh" "$@"`.
- `.gremlin/bridges/tui/tui.sh` — inside `run_slash` (line 363), keep the
  `exit`/`quit` short-circuit, but replace the parsing + execution block
  (lines ~366–402) with a single call to `bin/slash.sh` capturing
  stdout+stderr into `output_file`. Keep the existing append-to-buffer
  rendering and `refresh_model` at the end.

## Done when

- `./.gremlin/bin/say.sh /help` output unchanged.
- TUI `/help`, `/model`, `/model <alias>`, `/nope`, `/` (empty) all behave
  as they did before — same buffer rendering, same exit code handling, same
  ephemeral display.
- `exit`/`quit` in TUI still terminates the TUI.
- No transcript or `.nest/` writes from any of the above.
