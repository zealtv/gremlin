# s02-installed-gremlin-docs

Move user-facing gremlin docs inside `.gremlin/`.

Acceptance:

- `.gremlin/README.md` explains run, TUI-first interaction, `say` for one-shot
  scripting, customization, and update.
- `.gremlin/docs/protocol.md` contains the deeper single-gremlin protocol
  reference.
- `.gremlin/docs/composition.md` contains multi-gremlin composition guidance.
- `.gremlin/gremlin.md` tells the agent to read these docs on demand when
  asked about its own protocol.
