# s05-docs

**Outcome.** Documentation reflects the new prompt-build model. A reader anywhere in the docs arrives at the same one-line rule: `context/` is the always-loaded surface; `context/system/` is gremlin-managed.

## Scope

`.gremlin/docs/protocol.md`:

- Rewrite the "Prompt Inputs" section to list:
  1. `gremlin.md`
  2. sorted `context/system/*.md` (symlink-only by convention)
  3. sorted top-level `context/*.md`
  4. `transcript.md`
  5. the current item body
- Add a short paragraph on the `system/` convention and `gremlin doctor`.
- Remove the lines that named `skills/INDEX.md` and `tools/README.md` as direct prompt inputs.

`.gremlin/docs/composition.md`:

- Add a "Surfaces" subsection: a peer-gremlin directory can be exposed to every prompt by generating `peers/INDEX.md` and symlinking it into `context/system/peers.md`. State plainly that this shape is described but **not implemented** in this stage. Existing `peers/<name> → ../../other/.gremlin/.nest/in/` symlinks remain the delegation mechanism.

`.gremlin/README.md`:

- Update the "Customize" list so `context/` is described as "the always-loaded broadcast surface; `context/system/` is gremlin-managed."

Root `README.md`:

- Soften the "Memory you control" bullet. Current text claims findings are not auto-injected; replace with: catalog is broadcast by default, finding bodies are fetched on demand, individual findings can be promoted to full broadcast by symlinking into `context/`.
- Update the directory tree to show `context/system/`.

`context/system/README.md`:

- Created by doctor in s01 with placeholder content. Author the canonical text in this stitch. Cover:
  - The directory is managed by `gremlin doctor`.
  - `rm` of a specific entry opts out of that broadcast.
  - `gremlin doctor` restores missing entries.
  - **Entries are symlinks by convention.** The tender reads only symlinks from `context/system/`, which is why this `README.md` (a real file) is not loaded into the prompt. Real `.md` files dropped here are ignored by the tender and skipped by doctor.
  - `/update` currently re-restores deleted entries (no durable opt-out in this stage).

## Constraints

- Do not document the peer directory as a current feature. It is a future shape.
- Root README stays tight. Detail belongs in `.gremlin/`.
- Do not duplicate Glean's own README content — link to it from `.gremlin/README.md` instead.

## Verification

1. A reader of `docs/protocol.md` can answer "what does the model see every turn?" from a single paragraph.
2. `composition.md`'s peer-directory note links to no nonexistent script and is clearly framed as a shape, not a feature.
3. `context/system/README.md` is readable in-place and matches doctor's actual behaviour from s01 + s02.
4. Root README still passes the "tight and impactful" bar — no new bullet creep.
