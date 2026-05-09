# tui-header

**Outcome.** TUI header reads `-={ gremlin TUI (<host-abs-path>) }=-` so the user can see at a glance which host folder the TUI is attached to.

## Touchpoints

- `bridges/tui/tui.sh:596` — currently `title="    -------- gremlin tui -------- "`.

## Steps

1. Compute host absolute path. The TUI is launched from the host folder; `pwd` at startup or `cd "$GREMLIN_DIR/.." && pwd` both work.
2. Build the title: `-={ gremlin TUI ($host) }=-`.
3. Account for narrow terminals — long paths may overflow. Acceptable to truncate with `…` from the left if the path is wider than the chrome.

## Verify

- Run the TUI in a personal copy (`~/Desktop/mygremlin`); header shows the host path, not just "gremlin tui".
- Resize the terminal narrow; header still renders without breaking the box.

## Consistency / staleness

- Search `bridges/tui/tui.sh` for any other place that prints the gremlin name in chrome (footer, prompt label) — keep them coherent.
- `README.md` and `.gremlin/README.md` Quick Start show TUI invocation but not the header — no change expected; sweep to confirm.
