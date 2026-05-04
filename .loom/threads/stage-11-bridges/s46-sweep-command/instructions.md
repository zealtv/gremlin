# s46-sweep-command

Add a `/sweep` slash command that fans out across the embedded protocols' own sweep functions. Tidies the per-item archives that accumulate in nestling and groundhog out-trays.

## Why

Both protocols ship a `sweep [days]` subcommand:

- `nestling.sh sweep [days]` reaps `.nest/out/` and `.nest/dropped/` older than N days (default 14).
- `groundhog.sh sweep [days]` reaps `.groundhog/out/` and `.groundhog/fired/` older than N days (default 14).

Today neither runs automatically. After s43, `.nest/out/` legitimately accumulates archive entries; `.groundhog/fired/` already does. A user-invoked sweep keeps things tidy without a daemon to remember.

## Shape

New file: `.gremlin/commands/sweep.sh`. Same convention as the other commands (`commands/help.sh`, `commands/now.sh`, etc.). Invoked as `/sweep` from any bridge.

```bash
#!/usr/bin/env bash
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
days="${1:-14}"

echo "sweeping nestling (>${days}d)..."
"$GREMLIN_DIR/.nest/nestling.sh" sweep "$days"

echo "sweeping groundhog (>${days}d)..."
"$GREMLIN_DIR/.groundhog/groundhog.sh" sweep "$days"

echo "done."
```

Exact wording / output formatting is decided at build; the spec is "fan out to both protocols, surface their stdout, propagate any non-zero exit."

## Behaviour

- `/sweep` with no args: 14 days (each protocol's own default).
- `/sweep 7`: pass 7 to both. Both protocols accept the same argument shape.
- `/sweep 0`: each protocol treats 0 as "everything older than now," i.e. wipe both archive surfaces. Useful but destructive — fine to expose, both protocols already permit it.

Output: each protocol's own `swept ...` lines pass through. The command does not summarise.

## Out of scope

- Scheduled / automated sweeps. If wanted later, this is one line in `.groundhog/schedule/recurring/` invoking the command. Don't pre-build.
- Sweep policies per surface (e.g. nest/out at 30 days, groundhog/fired at 7). The protocols' shared default is fine; revisit when a real reason emerges.
- A `/sweep --dry-run`. Both protocols would need it first; not their job today.

## Verify

1. Generate archive entries: have a few normal exchanges via the TUI (each one fills `.nest/out/`). Schedule and fire at least one groundhog reminder.
2. `find .nest/out .nest/dropped .groundhog/out .groundhog/fired -mtime +0` — files exist.
3. Run `/sweep 0` from the TUI.
4. The four directories above contain only `.gitkeep` (or are empty save protocol bookkeeping).
5. Run `/sweep` again with no args — exits cleanly, no errors, no further changes.
6. `transcript.md` is unaffected by the sweep. Sweep only touches per-item archives.

## Dependencies

- **Strictly after s43.** Pre-s43, `.nest/out/` is the bridge delivery queue; `nestling sweep` would destroy undelivered scheduled outbound. Only safe to ship once `.nest/out/` is the protocol-aligned archive that s43 reframes it as.
