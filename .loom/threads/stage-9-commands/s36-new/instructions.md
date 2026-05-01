# s36-new

`commands/new.sh`: invoke `bin/archive.sh`. Print a short confirmation. First line is the comment summary picked up by `/help`.

```bash
#!/usr/bin/env bash
# new — start a fresh transcript (rotates current into transcript-archive/)
set -euo pipefail
GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$GREMLIN_DIR/bin/archive.sh"
echo "fresh transcript"
```

**Verify:** with `run.sh` running, `./.gremlin/say "/new"` prints "fresh transcript", `wc -l .gremlin/transcript.md` is 0, today's archive file exists.
