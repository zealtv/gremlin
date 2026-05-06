# s45a4-integration-doc-scaffold

Finish canonical integration and static documentation scaffold for the Telegram bridge.

## Outcome

The implementation is discoverable from `./.gremlin/gremlin help`, secrets/runtime files are ignored, and `bridges/telegram/README.md` plus `config.example` exist as safe scaffolding for later verification-driven docs.

## Scope

- Add `.gremlin/bridges/telegram/config.example`.
- Add `.gremlin/bridges/telegram/README.md` with non-secret basic setup placeholders and clear note that `s45e` will fill in verified instructions.
- Update `.gitignore` for:
  - `.gremlin/bridges/*/config`
  - `.gremlin/bridges/*/*.pid`
  - `.gremlin/bridges/*/*.log`
  - `.gremlin/bridges/*/.cursor`
  - `.gremlin/bridges/*/.update-offset`
- Ensure executable bits are set where needed.
- Run static verification for all touched scripts.

## Verify

1. `./.gremlin/gremlin help` lists `telegram`.
2. `git status --short` shows no runtime files or secrets.
3. `bash -n` passes for changed shell scripts.
4. `s45a-telegram-bridge-implementation` acceptance criteria are satisfied before tying parent.
