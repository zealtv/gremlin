# s45e-docs-from-verification

Turn the staged Telegram verification findings into user-facing setup and operations docs.

## Outcome

The Telegram bridge docs explain how to create/configure a bot, start/stop/status/restart the bridge, verify it locally, understand cursor behavior, and troubleshoot common setup failures. The docs reflect what actually worked during `s45b`, `s45c`, and `s45d`.

## Inputs

- `s45b-local-copy-bot-setup/verification.md`
- `s45c-inbound-smoke-test/verification.md`
- `s45d-outbound-cursor-verification/verification.md`
- Parent `s45-telegram-bridge/instructions.md`

## Scope

- Update `.gremlin/bridges/telegram/README.md`.
- Update `.gremlin/bridges/telegram/config.example` comments if verification shows clearer wording is needed.
- Add a brief pointer from `.gremlin/README.md` or bridge docs index only if the existing docs need a discoverability hook.
- Mention token safety and rotation via BotFather if a token leaks.
- Document that `config`, `.cursor`, and `.update-offset` are local runtime files and should not be committed.

## Required Sections

- Setup: BotFather, token, finding the chat id, creating `config`.
- Running: `./.gremlin/gremlin telegram start|stop|status|restart`.
- Verification: simple inbound message, proactive reminder, restart/no-duplicate check.
- Behavior: single configured chat, text only, every assistant turn pushes, no history replay on first launch.
- Troubleshooting: bad token, wrong chat id, runner paused/stopped, no model configured, network/API failures, duplicate or missing messages.

## Verify

1. Docs do not include real token, chat id, local personal paths beyond the intentional `~/Desktop/mygremlin` verification example.
2. A reader can follow the docs from a fresh local copy without needing hidden context from the loom.
3. The docs include findings from all staged verification notes.
4. The parent `s45` acceptance list passes or any known limitation is explicitly recorded before tying.
