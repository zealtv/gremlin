# s04 verification

## Prompt dumps

- `prompt-before.md` captures the pre-change prompt assembly for `S04 prompt assembly probe`.
- `prompt-after.md` captures the post-change prompt assembly for the same body using a capture model in a temporary gremlin.

Both dumps contain the skills index and tools menu:

- skills marker: `Reply briefly in the style of an actual gremlin`
- tools marker: `` `now.sh` ``

The post-change dump reaches those sections through `context/system/skills.md` and `context/system/tools.md`.

## Checks

- Removed `context/system/skills.md`; the next captured prompt did not contain `# skills index`.
- Ran `gremlin doctor`; it recreated `context/system/skills.md`, and the next captured prompt contained `# skills index` again.
- Added top-level `context/marker.md`; the next captured prompt placed `S04 top-level marker phrase` after the system block and before the transcript.
- Confirmed real `context/system/README.md` did not appear in the assembled prompt.
- Moved `context/` aside in the temporary gremlin; `tend-loop.sh` completed without error and produced a prompt without skills/tools/context sections.
