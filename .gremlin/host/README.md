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

## Defaults

The timings and the expiry here are defaults. The host moves or pauses them like
any other job:

- **Sunday 22:00 reflect.** Move the job directory to another slot under
  `.groundhog/schedule/` (for instance into a new `weekly/sat/09-00/`), or
  rename it to `reflect.paused` to stop it. The job finds its own directory by name, so a
  moved job keeps its place in the reflection cursor.
- **Six-month expiry.** `reflect-expire` is a dead-man's switch that drops the
  weekly reflect job so it cannot run forever unattended. It ships here as
  `once/+26w/`, which no host ever sees: `bin/install-host-files.sh` turns
  `+<N>w` (or `+<N>d`) in a `once/` path into the date N weeks (days) after the
  install, so a gremlin installed on any day gets an expiry six months out and
  no file in this repository names a date. Re-date it by renaming its
  `once/<date>/` folder. To keep reflecting after it fires, run the installer
  again.
- **Weekly curate pass.** Ships paused (`curate-findings.paused`) on the
  `memory` model preset. Rename it to turn it on.

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

A job you paused or edited stays that way — the installer only ever fills a
gap (a job you deleted comes back if you run it again), and `/update` never
touches the host root at all.
