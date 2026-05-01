# s24-indexer

`bin/index-skills.sh`: walk `skills/*.md` (follow symlinks), parse YAML frontmatter, write `skills/INDEX.md`.

- Skills with `triggers: [always]` are inlined in full at the top of the index.
- Other skills get one line each: `- \`name\` — first trigger`.

The tender's prompt always includes `INDEX.md`. Individual skill files are read by the tender (plain `cat`) when a trigger matches.

**Verify:** Running the indexer produces a sensible `INDEX.md` listing both skills.
