# tools

Bash scripts the tender can invoke. Each tool is a pure function of args → stdout; errors go to stderr with a non-zero exit. State lives in nests and transcripts, not in tools.

To use a tool, run it from the gremlin's root, e.g. `./tools/<name>.sh [args...]`.

## Menu

| Tool | Args | Returns |
|------|------|---------|
| `now.sh` | — | current local time, ISO-8601 with offset (e.g. `2026-05-01T21:15:00+1000`) |
