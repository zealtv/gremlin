# stage-2-tend-loop

**Outcome.** Drop a file into `.nest/in/` by hand, the tender processes it, a reply lands in `.nest/out/`, both turns appear in `transcript.md`.

Tie this stitch when every child is tied and a short note below records what was learned.

## Notes

- Transcript format (locked): `## <role> — <iso>` header, body lines, single blank line between turns. Writers (`tend-loop.sh`, `say`) must each use a single `>>` append per turn to avoid POSIX interleaving.
- s06: tend-loop is single-shot. Resolves paths via `BASH_SOURCE` so it works from any cwd. Items can be files or dirs (`message.md` for dirs).
- s08: stage-2 acceptance simulated `say`'s user-turn write by hand (append `## user` then ingest+tend). Real wiring lands in stage-3.
- Stage-2 outcome: tend-loop processes a hand-fed item end-to-end. Transcript ordering correct across multiple items.
