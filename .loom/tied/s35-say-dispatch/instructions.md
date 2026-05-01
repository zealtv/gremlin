# s35-say-dispatch

In `.gremlin/say`, intercept messages whose first character is `/` *before* the existing send-and-wait flow. Behaviour:

1. Strip the leading `/`, split on first whitespace into `<cmd>` + remaining args.
2. If `commands/<cmd>.sh` exists and is executable: run it with the remaining args, pipe its stdout to the user's terminal, exit with the script's exit code.
3. Otherwise: error to stderr (`unknown command: /<cmd>`), exit 1.

Slash-prefixed messages do **not** append to `transcript.md` and do **not** ingest into `.nest/in/` — they bypass the LLM entirely.

Empty body (`say "/"` with nothing after) → print short help and exit non-zero.

**Verify:** with `commands/foo.sh` printing "ok", `./.gremlin/say "/foo"` prints "ok" and the transcript is unchanged. `./.gremlin/say "/notathing"` errors and exits non-zero.
