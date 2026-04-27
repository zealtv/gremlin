# s09-say-input

`say` script (lives at `.scribe/say`, executable):

1. Take a message (positional arg, or stdin if no arg).
2. Append a `## user` turn to `transcript.md` (same format as the tend loop uses).
3. Write the message to `.nest/in/<ts>.md` via `.landing` rename.

**Verify:** `./.scribe/say "hi"` produces a file in `.nest/in/` and a `## user` entry in `transcript.md`.
