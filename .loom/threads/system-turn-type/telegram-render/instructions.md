# telegram-render

**Outcome.** The Telegram bridge handles `## system —` transcript turns without crashing, eating, or misattributing them.

## Decision needed

Should Telegram **send** system turns to the user, or filter them out?

- **Send** (recommended): user gets `⚙️ run: item aborted` confirmation when they `/stop`, and sees scheduled-script output. Costs them a notification; gains them visibility.
- **Filter**: keep Telegram conversation-only. User has no idea their `/stop` actually fired.

Default to send. Note any strong reason to filter in this stitch's notes before tying.

## Touchpoints

- `bridges/telegram/` — outbound transcript watcher / role handling.

## Steps

1. Match `^## system —` alongside the existing assistant match.
2. Send the body as a plain message. The emoji+label in the body is the visual cue; no extra formatting required.
3. Confirm Telegram doesn't barf on emoji at start of message.

## Verify

- Append a system turn to transcript while a Telegram bridge is running; user receives the body verbatim.
- `/stop` from TUI fires; Telegram receives the abort notice.
- Old transcripts (no system turns) replay unchanged.

## Consistency / staleness

- `bridges/telegram/README.md` if it documents which turn types get forwarded.
- Sibling: `tui-render` decision should match in spirit (both surface system turns).

Waits on `format-and-docs` only nominally.
