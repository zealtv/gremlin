# Composition

Composition is adjacency: multiple gremlins are multiple host folders, each with
its own `.gremlin/`.

```text
~/Desktop/gremlin-house/research/.gremlin/
~/Desktop/gremlin-house/admin/.gremlin/
```

They have no shared process and no shared state. They are independent agents
that happen to share a filesystem.

## Delegation

Delegation is a file move into another gremlin's inbox:

```sh
mv request.md ../admin/.gremlin/.nest/in/
```

The receiver picks it up on its next tend pass.

For repeated delegation, make the reach visible with a symlink:

```text
research/.gremlin/peers/admin -> ../../admin/.gremlin/.nest/in/
```

A skill can write an item into `peers/admin/`, and the sibling gremlin will tend
it.

## Shared Context

There is no enforced shared folder. If gremlins should share context, tools, or
skills, symlink them.

A useful convention for personal shared context is:

```text
~/.gremlin/context/
```

Each gremlin can symlink selected files from its own `context/` directory.

## Surfaces

`context/` is the always-loaded surface for a gremlin. The managed
`context/system/` subdirectory can expose generated indexes by symlink, such as
the skills, tools, and memory catalogs.

A future peer-gremlin directory could follow the same shape: generate a
`peers/INDEX.md` summary and symlink it into `context/system/peers.md` so it is
broadcast every turn. That is only a described shape in this stage, not an
implemented feature. Delegation today is still the inbox symlink described
above, such as `peers/<name> -> ../../other/.gremlin/.nest/in/`.

## Sandboxing

Sandboxing is convention, not enforcement. Host a gremlin where broad file and
shell access is acceptable.

For real isolation, run the gremlin under a separate OS user, container, VM, or
harness-specific sandbox. The main seam is `bin/llm.sh`; the rest of the gremlin
does not need to know how the model process is isolated.

## Extensions

Extensions fit the same file protocol:

- Push bridges tail `transcript.md` and write inbound items to `.nest/in/`.
- Attachments can be represented as item directories with `message.md` or
  `instructions.md` plus files.
- Voice can be added with transcribe/TTS tools around the same message files.
- Coordinators are gremlins with symlinks to child gremlin inboxes.
