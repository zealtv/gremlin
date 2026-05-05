# s44b-model-output-noise

`/model` output is intermittently contaminated by unrelated tokens (observed: `sync.sh`) when invoked from the TUI bridge.

Example observed output:

```
/model command output
default — claude sonnet 4.6
sync.sh fast — claude-haiku-4-5

/model command output
model: default

/model command output
sync.sh default — claude sonnet 4.6
fast — claude-haiku-4-5
```

## Goal

`/model` output in the TUI should be exactly the stdout/stderr produced by `commands/model.sh` and nothing else.

## Suspects

- The TUI bridge is capturing output that isn't from `commands/model.sh` (e.g. shell init noise, subshell cwd noise, inherited env warnings).
- The command is being run from an unexpected working directory (or with unexpected env) that triggers extra output.
- There is a `models/sync.sh` preset (or other `*.sh`) in the install and `/model` is correctly listing it, but the output formatting makes it look like injection.

## Investigation

1. Reproduce in a personal install where the bug occurs (e.g. `~/Desktop/mygremlin`):
   - Run `./.gremlin/commands/model.sh` directly and compare its raw output to what the TUI shows.
   - Run `./.gremlin/bin/say /model` and compare.
2. Check for a real file causing the token:
   - `ls -la .gremlin/models` for `sync.sh` (or similarly named presets).
3. If it is injection:
   - Ensure TUI slash dispatch runs with:
     - `cwd` pinned to `.gremlin/`
     - stdin detached (`</dev/null`)
     - clean locale/env (avoid `LC_ALL=C.UTF-8` warnings on macOS)
4. If it is a real preset:
   - Decide whether `/model` should hide non-preset scripts (policy), or whether the fix is naming guidance and/or a filter rule (e.g. only list `models/*.sh` that contain a label comment).

## Acceptance

- Repeated `/model` in the TUI never shows `sync.sh` unless a real `models/sync.sh` exists and is intentionally listed.
- Output in TUI matches `./.gremlin/commands/model.sh` (byte-for-byte) for the same install.

