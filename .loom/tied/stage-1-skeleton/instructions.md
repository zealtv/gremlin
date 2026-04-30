# stage-1-skeleton

**Outcome.** `.gremlin/` exists with the canonical layout. Nothing runs yet. A `bash -n` clean across the stubs.

Tie this stitch when every child is tied and a short note below records what was learned.

## Notes

- s01: empty dirs need `.gitkeep` so the canonical structure survives commit. Also: `.loom/tied/` and `.loom/dropped/` weren't created until first use — `mkdir -p` them as needed.
- s02/s03: same `.gitkeep` treatment for nest's `in/ out/ dropped/` and groundhog's `schedule/ out/ fired/`.
- s04: `claude -p` is the default LLM. The seam is `bin/llm.sh`; reads stdin or args.
- Stage-1 outcome: skeleton stands. Nothing runs yet, all scripts `bash -n` clean, `llm.sh` returns replies.
