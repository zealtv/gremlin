# stage-6-skills

**Outcome.** Plain markdown procedures with YAML frontmatter; `INDEX.md` is generated; the tender consults the index and reads individual skills on demand. LLM-agnostic.

Tie this stitch when every child is tied and a short note below records what was learned.

## Notes

- Sandbox is the host directory: `--allowedTools "Bash"` (unrestricted) lives in `bin/llm.sh`. Tool wrappers under `tools/` remain the *named* surface but aren't the only one.
- s24 indexer parses two trigger forms: inline `triggers: [always]` and multi-line `triggers:\n  - foo`. Always-bodies inlined; others get `- \`name\` — first trigger`.
- s27 first attempt: model confirmed the reminder in prose without actually creating the file. Fix took two prompts: gremlin.md now lays out the read-and-execute pattern explicitly ("don't claim you've done something you haven't"), and remind-me.md gives a concrete bash recipe instead of prose.
- Groundhog's `once/<YYYY-MM-DD>/<item>/` is date-resolution only; hour buckets exist for daily/weekly/monthly/yearly but not once. The skill puts time-of-day in the message body.
- Stage-6 outcome: skills work end-to-end. Always-skills shape voice; triggered skills run a procedure with real side effects.