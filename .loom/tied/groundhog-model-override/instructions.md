# groundhog-model-override

**Outcome.** A groundhog item with a `.model` file inside it is tended using that model preset, regardless of the gremlin-wide `.model` setting.

## Why

Different scheduled work wants different models — the daily summariser might want a cheap fast preset, the weekly architectural review might want the heavy one. Letting items name their preset keeps the choice next to the work.

## Mechanism (gremlin-side; groundhog stays opaque)

- `bin/tend-loop.sh` — when claiming an item, if the item directory contains a `.model` file, read its contents (single-line alias) and export `GREMLIN_MODEL=<alias>` for the `bin/llm.sh` invocation.
- `bin/llm.sh` — honour `GREMLIN_MODEL` env above the gremlin-root `.model` file. Order: env → root `.model` → `default`.

## Touchpoints

- `bin/tend-loop.sh` — read item `.model`, export env.
- `bin/llm.sh` — env beats file.
- `docs/protocol.md` Models section — document the precedence (env → file → default) and the per-item convention.
- `.groundhog/README.md` (vendored) — note item-level `.model` convention as a gremlin-side recognition; groundhog itself remains opaque.

## Verify

- Item with `.model` containing alternate alias → that preset runs (confirm via a preset that prints a marker).
- Item without `.model` → gremlin-root `.model` (or default) used.
- `/model <alias>` from TUI sets root `.model`; per-item override still wins for items that have one.
- `bin/say` (one-shot) is unaffected.

## Consistency / staleness

- `docs/protocol.md` Models section — full precedence chain.
- README Quick Start mentions `models/default.sh`; sweep for any claim that `.model` is gremlin-wide only.
- Existing context doc references in `.gremlin/context/` (none currently) — no impact.

## No upstream work needed

Groundhog doesn't interpret item contents; the `.model` file is just a file. This is purely a gremlin-side recognition. No `.waiting` suffix.
