# s05a-init-script

Write `gremlin/init.sh` (at the repo root, alongside README.md and PLAN.md):

```bash
#!/usr/bin/env bash
# usage: ./init.sh <host-dir>
# Places a fresh .gremlin/ inside the given host directory.
set -euo pipefail
[[ -n "${1:-}" ]] || { echo "usage: $0 <host-dir>" >&2; exit 2; }
target="$1/.gremlin"
[[ ! -e "$target" ]] || { echo "refusing: $target already exists" >&2; exit 1; }
cp -r "$(dirname "$0")/.gremlin" "$target"
echo "initialised gremlin at $target"
```

Make executable: `chmod +x init.sh`.

This is the user-facing way to spin up a personal gremlin. It is also the cue that **the repo's reference `.gremlin/` is not for running** — you copy it out first.

**Verify:**
- `./init.sh /tmp/test-host` produces `/tmp/test-host/.gremlin/` mirroring the reference.
- A second `./init.sh /tmp/test-host` refuses with a clear error.
- `./init.sh` (no args) prints usage and exits non-zero.
