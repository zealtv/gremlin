# stage-8-archive

**Outcome.** A clean way to start a fresh session without losing history or breaking in-flight loops.

Tie this stitch when every child is tied and a short note below records what was learned.

## Notes

- archive.sh uses `.paused` + a 6s quiesce sleep (longer than tend's 5s cadence) so any in-flight tend pass finishes its `>>` before the rotation. Skipping the sleep would risk an assistant turn being orphaned into the new empty transcript.
- Same-day re-archive: suffixes `-2`, `-3`, etc. so multiple archives in one day don't collide.
- Pending groundhog items live in `.groundhog/` and are entirely untouched by archive — survives across sessions cleanly.
- Stage-8 outcome: full MVP. The gremlin holds a conversation, processes scheduled work, fires reminders, archives cleanly. Nothing left in the threads/.