# s01-extract-slash-helper

Add `.gremlin/bin/slash.sh`. Pure dispatcher; no bridge logic.

## Contract

- Invocation: `bin/slash.sh "/cmd args..."` or `bin/slash.sh "cmd args..."`
  (leading `/` optional).
- Resolves `commands/<cmd>.sh`, runs it from `$GREMLIN_DIR` with stdin
  closed, args space-split (matching the existing convention in
  `tui.sh:run_slash` and `say.sh`).
- Stdout/stderr from the command pass through. Exit code is the command's.
- Empty cmd → exit 2, usage on stderr.
- Unknown cmd → exit 127, `unknown command: /<cmd>\ntry /help` on stderr.
- Does NOT handle `exit`/`quit` — those are bridge-process concerns.
- Does NOT touch transcript or `.nest/`.

## Files

- New: `.gremlin/bin/slash.sh` (chmod +x).

## Done when

- `./.gremlin/bin/slash.sh /help` prints help text.
- `./.gremlin/bin/slash.sh /nope` prints unknown-command on stderr, exits 127.
- `./.gremlin/bin/slash.sh ""` prints usage on stderr, exits 2.
- No other files changed yet.
