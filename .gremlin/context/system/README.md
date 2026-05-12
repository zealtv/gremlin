# context/system

This directory is managed by `gremlin doctor`.
It holds symlinks for gremlin-managed material that should be broadcast through `context/`.
Remove a specific entry to opt out of that broadcast; running `gremlin doctor` restores missing managed entries.
The `/update` command runs `gremlin doctor`, so updates also restore missing managed entries.
Real files placed here are left alone.
