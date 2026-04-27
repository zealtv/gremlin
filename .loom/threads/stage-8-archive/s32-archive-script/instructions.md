# s32-archive-script

`bin/archive.sh`:

1. `touch .paused` and pause briefly so any in-flight loop iteration finishes.
2. `mv transcript.md transcript-archive/$(date +%Y-%m-%d).md` (handle the case where today's archive already exists — append a counter suffix or the time).
3. `touch transcript.md`.
4. `rm .paused`.

Pending groundhog items live in `.groundhog/` and are untouched.

**Verify:** Mid-session archive transitions to a fresh transcript with no message lost or duplicated.
