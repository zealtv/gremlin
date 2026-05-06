# verification

- Added a Telegram quickstart to `.gremlin/README.md`.
- Expanded `.gremlin/bridges/telegram/README.md` with setup, requirements, verification, behavior, and troubleshooting.
- Included findings from local staged verification:
  - `/start` is normal text
  - Telegram delivery can lag TUI by several seconds
  - bridge stop can take up to the long-poll timeout
  - `.cursor` prevents first-start history replay
  - paused runner queues inbound work until unpaused
  - reminders must land under `.gremlin/.groundhog`
- Docs do not include real token, chat id, or Telegram update ids.
