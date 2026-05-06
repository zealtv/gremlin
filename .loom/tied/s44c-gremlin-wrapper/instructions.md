# s44c-gremlin-wrapper

Introduce `./.gremlin/gremlin` as the single user-facing entry point. The 90% UX surface for interacting with a gremlin from its host folder.

## Why

Today every interaction has a different relative path: `./.gremlin/run.sh` to start the runner, `./.gremlin/bin/say` to message, `./.gremlin/bridges/tui/tui.sh` for the TUI, `./.gremlin/commands/<cmd>.sh` for everything else. Stage-11 is about to add a Telegram daemon, which compounds the surface unless we consolidate first. A wrapper lets the user say `./.gremlin/gremlin start`, `./.gremlin/gremlin tui`, `./.gremlin/gremlin say "hi"`, `./.gremlin/gremlin model`, and (in s45) `./.gremlin/gremlin telegram start` — one verb space, one entry point.

The wrapper rides on top of the existing scripts; it does not replace them. Direct invocation still works for scripting and debugging. This is a UX consolidation, not an architecture change.

## Layout

```
.gremlin/
  gremlin              # NEW. user-facing wrapper, no extension.
  run.log              # NEW. append-only runner stdout/stderr (gitignored).
  bin/
    run.sh             # MOVED from .gremlin/run.sh
    say.sh             # RENAMED from .gremlin/bin/say
    archive.sh
    index-skills.sh
    llm.sh
    tend-loop.sh
    tick-loop.sh
```

`bin/` becomes uniformly `*.sh` implementation. The unextensioned name is reserved for the user-facing wrapper at the gremlin root.

## Verbs

**Built-in (runner lifecycle).**

- `start` — background `bin/run.sh` via `nohup ... & disown`, redirect stdout/stderr (append) to `.gremlin/run.log`. Refuse with a clear message if already running.
- `stop` — SIGTERM the matched runner. `bin/run.sh`'s existing `trap shutdown INT TERM` handles cleanup.
- `status` — report PID(s) or "not running."
- `restart` — `stop`, wait for exit, `start`.
- `say <msg...>` / `say /command [args...]` — proxy to `bin/say.sh`. Pass argv through verbatim (including stdin pipe behaviour).
- `tui` — `exec bridges/tui/tui.sh`.
- `help` — print built-in verbs **and** auto-discovered commands (see below).

**Auto-discovered.** Any `commands/<name>.sh` is dispatched as `gremlin <name>`. Today: `new`, `update`, `model`, `help`. After s46: `sweep`. Built-in verbs take precedence on collision.

**Bridge subcommands (convention only — implemented by s45).** `gremlin <bridge> <verb>` will route to `bridges/<bridge>/<bridge>.sh <verb>`. The wrapper should *not* hardcode `telegram`; it should detect any executable `bridges/<name>/<name>.sh` and treat the next arg as a verb passed through. The bridge script owns its own `start/stop/status/restart` semantics. This stitch only needs to plumb the dispatch — s45 ships the first daemon that uses it. The TUI is the exception: it's a foreground bridge, exposed as `gremlin tui` (single verb) rather than `gremlin tui start`.

## Process tracking

No PID file. `pgrep -f "$GREMLIN_DIR/bin/run.sh"` is the source of truth — each gremlin's absolute path is unique, so two gremlins on one host don't collide.

- `start` runs pgrep first; if any match, refuse and print existing PID(s).
- `stop` SIGTERMs all matches; polls until pgrep returns empty or a short timeout (≈5s) before warning.
- `status` is just pgrep + a one-liner.

Same pattern is intended for bridge daemons (s45): `pgrep -f "$GREMLIN_DIR/bridges/<name>/<name>.sh"`.

## Log

`.gremlin/run.log` at the gremlin root. Append-only. No rotation in this stitch. Lives alongside `transcript.md` as runtime state, keeping `bin/` purely executable. Add `run.log` to canonical `.gitignore` so it never lands in the tracked repo.

## Surgical changes

- **Move** `.gremlin/run.sh` → `.gremlin/bin/run.sh`. The script's `GREMLIN_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` becomes `... && pwd)/..` (or equivalent `cd .. && pwd`). Verify `HOST_DIR` still resolves correctly.
- **Rename** `.gremlin/bin/say` → `.gremlin/bin/say.sh`. Update every reference — at minimum: any `commands/*.sh` that calls it, the canonical README's "test through `/update`" example (`./.gremlin/bin/say /update`), and the wrapper itself.
- **Create** `.gremlin/gremlin` (executable, `chmod +x`). Single bash file. Start with a usage block; a top-level `case "$1" in` over built-in verbs; fall through to commands/ auto-discovery; final fallthrough to bridges/ dispatch; otherwise unknown-verb error pointing at `gremlin help`.
- **Update** canonical `README.md`: quick-start uses `./.gremlin/gremlin start` and `./.gremlin/gremlin tui`. The local-canonical-tarball test-update example uses `./.gremlin/gremlin say /update` (or just `./.gremlin/gremlin update`).
- **Update** `install.sh` if it prints a "now run …" hint pointing at `run.sh`.
- **Update** `.gremlin/README.md` and any `docs/*` that reference `run.sh` or `bin/say`.
- **Update** `.gremlin/bridges/tui/tui.sh` startup hint (and `bridges/tui/README.md` if present) for any references to renamed/moved paths.
- **Update** `commands/help.sh` — leave it as-is (it's the slash-command surface used by the TUI's `/help`). The wrapper's `gremlin help` prints its own built-in verb list, then invokes `commands/help.sh` for the rest. Two surfaces, one source of truth for custom commands.
- **Update** canonical `.gitignore` to include `.gremlin/run.log`.
- **Update** parent `.loom/threads/stage-11-bridges/instructions.md`: add `s44c-gremlin-wrapper` to the "Child stitches (in order)" list, between s44b and s45, and note the dependency that s45 should plumb its daemon through the wrapper.

## Out of scope

- PATH installation / shim. `gremlin` stays at `.gremlin/gremlin`; users invoke as `./.gremlin/gremlin`. A future stitch can add an opt-in PATH symlink if there's demand.
- Removing direct invocation. `bin/run.sh`, `bin/say.sh`, `bridges/tui/tui.sh`, `commands/*.sh` remain runnable directly. The wrapper is promoted, not exclusive.
- Log rotation. One unbounded `run.log` is fine until it isn't.
- `gremlin telegram start` itself — that lands with s45. This stitch only proves out the dispatch convention.
- Any reshape of the slash-command surface (`/help`, `/model`, etc.). Slash commands keep dispatching through `commands/`; `gremlin <verb>` simply runs the same scripts non-interactively.

## Verify

1. Fresh personal copy at `~/Desktop/mygremlin` (Bob runs this himself per the personal-copy convention):
   - `./.gremlin/gremlin start` → returns immediately. `./.gremlin/gremlin status` shows a PID. `.gremlin/run.log` accumulates output.
   - `./.gremlin/gremlin say "hello"` returns a reply.
   - `./.gremlin/gremlin tui` opens the TUI; quit with Ctrl-D.
   - `./.gremlin/gremlin help` lists built-in verbs **and** auto-discovered `commands/*.sh`.
   - `./.gremlin/gremlin model`, `gremlin new`, `gremlin update` dispatch correctly.
   - `./.gremlin/gremlin restart` stops and restarts; PID changes.
   - `./.gremlin/gremlin stop` → `status` reports not running.
2. Two gremlins running concurrently on one host: each `gremlin status` reports only its own runner; `gremlin stop` in one leaves the other alive.
3. Direct invocation still works: `./.gremlin/bin/run.sh` foregrounded, `./.gremlin/bin/say.sh "hi"` one-shot, `./.gremlin/bridges/tui/tui.sh` opens directly.
4. Canonical repo: `git status` shows only intended changes; no `run.log` or PID files tracked; `bin/` contains only `*.sh` executables.

## Dependencies

- **s44** must be tied (provides `bridges/tui/tui.sh` for `gremlin tui`). ✓
- **s43** must be tied (transcript-as-single-surface; `say` already retargeted). ✓
- **Lands before s45** so the Telegram daemon is shaped as `gremlin telegram start/stop/status/restart` from day one rather than retrofitted.
- Independent of **s44a**, **s44b**, **s46**.
