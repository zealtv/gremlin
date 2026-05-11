# s52-update-excludes verification

- Updated `/update` to preserve local Glean state:
  - `.glean/in/`
  - `.glean/findings/`
  - `.glean/out/`
  - `.glean/dropped/`
  - `.glean/distil.md`
- Did not exclude `.glean/` wholesale, so canonical `.glean/glean.sh` and
  `.glean/README.md` still update.
- Fixed the update cleanup trap so `--dry-run` exits 0 when no pause file was
  created by this invocation.
- Updated docs describing `/update` preservation behavior.

Checks run:

```sh
bash -n .gremlin/commands/update.sh
cp -R .gremlin /private/tmp/gremlin-s52-host/.gremlin
cp -R .gremlin /private/tmp/gremlin-s52-canon/gremlin/.gremlin
# create local in/findings/out/dropped/distil state in host copy
# modify canonical .glean/README.md and .glean/glean.sh in tarball copy
tar -czf /private/tmp/gremlin-s52-canon.tar.gz -C /private/tmp/gremlin-s52-canon gremlin
/private/tmp/gremlin-s52-host/.gremlin/gremlin update --dry-run
/private/tmp/gremlin-s52-host/.gremlin/gremlin update
```

Dry-run exited 0 and itemized only `.glean/README.md` and `.glean/glean.sh`
under `.glean/`.

After the real update, local `in/`, `findings/`, `out/`, `dropped/`, and
`distil.md` were preserved, while canonical marker changes in `.glean/README.md`
and `.glean/glean.sh` appeared in the host copy.
