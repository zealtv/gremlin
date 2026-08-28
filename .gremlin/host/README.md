# host

What this gremlin contributes to its host repository's primitives: **its own
scheduled work**, and nothing else.

The layout mirrors the host root, so
`host/.groundhog/schedule/weekly/sun/22-00/reflect/` lands at
`<host>/.groundhog/schedule/weekly/sun/22-00/reflect/`.
`bin/install-host-files.sh` copies anything missing, at install time only.

The jobs live on the repository's shared schedule rather than a private one
because visibility is the point of the placement law: a human reading
`.groundhog/schedule/` sees that this repository reflects on Sunday nights, and
can pause it by renaming the directory the way they would pause any other job.

## What is deliberately not here

`.nest/tend.md` and `.glean/distil.md` used to ship from here too. They no
longer do.

**A gremlin may generate facts about its host. It does not author policy for
it.** `AGENTS.md` is facts — which primitives exist, in what order to read them
— regenerated from disk, so gremlin maintains it. `tend.md` (how items should
be routed here) and `distil.md` (what this repository considers worth
remembering) are policy, and policy belongs to whoever owns the repository.
Both primitives ship their own neutral starting point; `doctor` notices when
one is still untouched and says what a gremlin would like to see there.

The version gremlin used to ship was also a symptom: its `tend.md` was a prose
description of `bin/tend-loop.sh` kept in a second file that nothing verified,
and its `distil.md` was mostly generic glean mechanics that belong in
`skills/distil.md`, where the model already reads them.

A job you paused, edited or deleted stays that way — the installer only ever
fills a gap, and `/update` never touches the host root at all.
