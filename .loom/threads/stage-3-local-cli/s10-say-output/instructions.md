# s10-say-output

After writing input, `say` watches `.nest/out/` for new files (skip `.landing`). When one appears:

1. Print its contents to stdout.
2. `mv` it to `.nest/out/sent/` so the same reply isn't reprinted by a later invocation.

Cap the wait with a sensible timeout (say 60s) and exit non-zero if no reply arrives.

**Verify:** Drop a file in `.nest/out/` by hand; an already-running `say` reads it once, prints it, moves it to `sent/`.
