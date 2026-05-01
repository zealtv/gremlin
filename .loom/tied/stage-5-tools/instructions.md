# stage-5-tools

**Outcome.** The tender can call any script in `tools/`. State stays in nests and transcripts; tools are pure functions of args → stdout.

Tie this stitch when every child is tied and a short note below records what was learned.

## Notes

- Tool permission flag for claude CLI: `--allowedTools "Bash(./tools/*)"`. Lives in `bin/llm.sh`. Equivalent flags for swap-in models go there too.
- Contract: `tend-loop.sh` cd's to `$GREMLIN_DIR` before invoking llm.sh, so the relative `./tools/*` glob resolves correctly regardless of where `run.sh` was launched from.
- Prompt assembly order: gremlin.md → context/*.md → (skills INDEX, stage-6) → tools/README.md → transcript.md → item.
- Stage-5 outcome: the gremlin can use bash tools without interactive prompts; `now.sh` end-to-end via `say` works.