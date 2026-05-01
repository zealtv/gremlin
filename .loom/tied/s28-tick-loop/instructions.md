# s28-tick-loop

`bin/tick-loop.sh`:

1. Run `.groundhog/groundhog.sh tick`.
2. For each item directory in `.groundhog/out/`:
   - If it contains `message.md`: `mv` that file to `.nest/out/<ts>.md` (scheduled outbound — bypasses the tender entirely). Then `rm -rf` the now-empty source directory.
   - Otherwise: `mv` the item directory into `.nest/in/` (scheduled work for the tender).

**Verify:** Manually drop a `.groundhog/out/foo/message.md` and run `bin/tick-loop.sh` once — the message routes to `.nest/out/`.
