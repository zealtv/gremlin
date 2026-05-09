# tick-loop-pure-router

**Outcome.** `bin/tick-loop.sh` is a pure router: it ticks groundhog and moves every materialised item into `.nest/in/`. It writes no transcript turns. The tend-loop becomes the only place that recognises item shapes (`message.md`, `instructions.md`, future `run.sh`) and produces transcript turns.

## Why

Today tick-loop short-circuits `message.md` items — appends `## assistant —` directly and `rm -rf`'s them. That:

- skips the nest entirely (no archive, no audit trail),
- makes `.nest/out/` an inconsistent surface (some fired items leave a footprint, some vanish),
- forces every new "no-model" axis (e.g. `run.sh` from `groundhog-run-scripts`) to either inherit the same hole or duplicate the routing pattern,
- mislabels the turn — a scheduled message isn't a model output, but it's tagged as one.

Routing every fired item through the nest gives one audit surface, lets the tender be the single dispatcher, and makes per-item conventions (e.g. the `.model` file from `groundhog-model-override`) work uniformly across axes.

## Touchpoints

- `bin/tick-loop.sh` — strip the `message.md` branch and the direct transcript write. Keep only: `groundhog.sh tick`, then for each `out/*` move (or `nestling ingest`) into `.nest/in/`. No `cd`, no transcript handle.
- `bin/tend-loop.sh` — teach a `message.md` branch: if the claimed item is a directory containing `message.md` (and no `instructions.md`), append the body as the appropriate transcript turn (see "Open question" below) and complete the item; do **not** call the model.
- `docs/protocol.md` Loops + Data Flow sections — update so scheduled messages flow `groundhog → tick-loop → .nest/in/ → tend-loop → transcript.md + .nest/out/`. The current diagram has tick-loop writing transcript directly; that arrow goes away.
- `bin/tend-loop.sh` body-extraction order — currently checks `instructions.md` then `message.md` then file. The new dispatcher needs to *act differently* on which one it found, not just extract a body. Refactor the read into "classify shape, then handle."

## Role for scheduled `message.md`

Resolved: scheduled messages emit `## system — 📅 reminder:`, not `## assistant —`. Decided alongside `format-and-docs`: keeps the protocol uniform — every transcript turn is either a real model exchange (`user`/`assistant`) or some flavour of `system`, no carve-outs.

`📅 reminder:` is the initial label for scheduled-message output. Vocabulary is extensible per the system-turn convention, so alternative flavours (`📊 summary:`, etc.) can grow as needed without changing the role header.

User-visible knock-on: bridges that filter system turns would stop forwarding scheduled messages. That's why `telegram-render` and `tui-render` default to "send/style" rather than "filter" — scheduled reminders are the load-bearing example.

## Mechanism (sketch)

`bin/tick-loop.sh`:

```sh
"$GH/groundhog.sh" tick

for item in "$GH/out"/*; do
  [ -e "$item" ] || continue
  base="$(basename "$item")"
  [ "$base" = ".gitkeep" ] && continue
  [ -d "$item" ] || continue

  target="$NEST_IN/$base"
  n=2
  while [ -e "$target" ]; do
    target="$NEST_IN/$base-$n"
    n=$((n+1))
  done
  mv "$item" "$target"
done
```

`bin/tend-loop.sh` — after claim, before the model branch, dispatch:

```sh
if [ -d "$claimed_path" ] && [ -f "$claimed_path/message.md" ] && [ ! -f "$claimed_path/instructions.md" ]; then
  iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  body="$(cat "$claimed_path/message.md")"
  printf '## system — %s\n📅 reminder: %s\n\n' "$iso" "$body" >> "$TRANSCRIPT"
  "$NESTLING" complete "$name" "$claimed_path" >/dev/null
  exit 0
fi
# ...existing model-backed path follows...
```

(Exact form depends on whether `nest-out-archives-input` has landed first — see Sequencing.)

## Verify

- Schedule a `once/<date>/<HH-MM>/<slug>/message.md` item; tick fires it. Result: transcript shows the message body as `## system — 📅 reminder: <body>` (changed from today's `## assistant —`); `.nest/out/<slug>` contains the archived directory with `message.md` inside; `.groundhog/out/` is empty.
- Schedule a tend-target item (e.g. `instructions.md`); tick fires it. Result: full model-backed flow as today, just routed through tick → nest → tend rather than direct.
- Two scheduled `message.md` items materialised in the same tick: both move into `.nest/in/`, both get tended in subsequent passes (one per pass, per the single-shot tender contract). No collisions in `.nest/in/` or `.nest/out/`.
- An item with neither `message.md` nor `instructions.md` (e.g. an empty dir) — current behaviour was "tend as default"; new behaviour preserves that (the tender's existing fallback applies). Nothing should newly break.
- A `message.md` containing markdown that includes `^## ` lines — the body is treated as opaque text, not re-parsed. Bridges that read transcript turn-by-turn already handle this.

## Consistency / staleness

- `docs/protocol.md` Data Flow — both "Scheduled message" and "Scheduled tending" diagrams collapse into one shape: `groundhog → tick-loop → .nest/in/ → tend-loop → transcript.md`. The script axis (added by `groundhog-run-scripts`) becomes a third dispatcher branch with the same shape.
- `bin/tick-loop.sh` header comment — currently describes the `message.md` short-circuit; rewrite as "moves materialised groundhog items into the nest; tend-loop owns dispatch."
- `bin/tend-loop.sh` header comment — note the `message.md` branch.
- `commands/sweep.sh` — confirm it's untouched (sweeps nest + groundhog independently; no shared assumption).
- `bin/say.sh:66` — watches for `^## assistant — ` to know when the reply landed. Unchanged: scheduled messages don't typically arrive mid-`say`-cycle, and even if one did, `say.sh` would treat it as the boundary, which is reasonable.

## Sequencing

- **Lands before `groundhog-run-scripts`.** The script axis becomes a tend-loop dispatcher branch, not a tick-loop short-circuit. Filing it here means `groundhog-run-scripts` shrinks to "add a third case to the dispatcher."
- **Composes with `nest-out-archives-input`.** Either order works. If `nest-out-archives-input` lands first, the archive call here is `nestling complete <name> <claimed_path>` and the verify story is symmetric across all axes from day one. If this lands first, the `message.md` branch can use the current "complete with reply" call (degenerate — the message body *is* the result content) and get retrofitted by `nest-out-archives-input`. Either is fine; recommend `nest-out-archives-input` first to avoid back-and-forth on the complete-call shape.
- **Depends on `system-turn-type/format-and-docs` for the role definition.** This stitch emits `## system — 📅 reminder:`, which `format-and-docs` is establishing as the convention. Land `format-and-docs` first so the role is documented when this stitch's behaviour ships.
- **`groundhog-model-override`** automatically benefits — the tender already reads a per-item `.model` from the claimed path; tick-loop becoming a router means even `message.md`-style items could carry one (mostly moot since they don't call the model, but the principle holds).

## Notes

- This is the structural fix that makes the nest the single audit surface. It's a small refactor (tick-loop shrinks more than tend-loop grows) but it pays off every time a new axis is added.
