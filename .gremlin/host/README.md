# host

What this gremlin contributes to its host repository's primitives — its own
scheduled work, and the host-local policy files each primitive leaves for
whoever tends the folder.

The layout mirrors the host root: `host/.groundhog/schedule/weekly/sun/22-00/reflect/`
lands at `<host>/.groundhog/schedule/weekly/sun/22-00/reflect/`, and
`host/.nest/tend.md` lands at `<host>/.nest/tend.md`.

`bin/install-host-files.sh` copies anything that is missing. It is install-time
convenience, never delivery: the files belong to the host once they land, and
nothing here is a second copy of a primitive.

They live on the shared schedule rather than a private one because visibility
is the point of the placement law: a human reading `.groundhog/schedule/` sees
that this repository reflects on Sunday nights, and can pause it by renaming
the directory the way they would pause any other job.

Installation never overwrites. A job you paused, edited or deleted stays that
way, and an edited `tend.md` or `distil.md` is yours — the installer only ever
fills a gap, and `/update` never touches the host root at all.
