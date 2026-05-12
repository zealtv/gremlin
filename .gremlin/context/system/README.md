# context/system

This directory is managed by `gremlin doctor`.
It holds symlinks for gremlin-managed material that should be broadcast through `context/`.

Remove a specific entry to opt out of that broadcast. Running `gremlin doctor` restores missing managed entries. The `/update` command also runs `gremlin doctor`, so updates currently restore deleted managed entries too; there is no durable opt-out in this stage.

Entries are symlinks by convention. The tender reads only symlinked `.md` files from this directory, which is why this `README.md` is not loaded into the prompt. Real `.md` files dropped here are ignored by the tender, left alone by doctor, and reported as `skipped (real file)`.
