# stage-3-local-cli

**Outcome.** `./.gremlin/say "hello"` writes a message into `.nest/in/`, blocks until a reply lands in `.nest/out/`, prints the reply. End-to-end conversation without launching a daemon.

Tie this stitch when every child is tied and a short note below records what was learned.

## Notes

- `say` lives at `.gremlin/say` (top-level, user-facing) — not under `bin/`.
- s10: snapshot `out/` filenames *before* ingest so prior replies are ignored. 60s timeout, 0.5s polling. Found replies move to `out/sent/`.
- Transcript-as-context wires up automatically: tend-loop concats `transcript.md` into the prompt, so multi-turn coherence works without any extra plumbing (verified on the s12 acceptance "and times three?" → "12").
- Stage-3 outcome: full local round-trip via `say`. No daemon yet; tend-loop is run by hand or in a `while true` shell loop until stage-4's `run.sh` arrives.