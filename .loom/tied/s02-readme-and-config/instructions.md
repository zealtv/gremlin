# s02-readme-and-config

Update `.gremlin/bridges/telegram/README.md` to reflect the three-loop model
landed in s01.

## Content to add

- **Loop model.** A short section explaining that the bridge supervisor forks
  three independent loops: inbound poll (long-polls `getUpdates`), outbound
  push (tails `transcript.md` and sends new assistant turns), typing pulse
  (sends `sendChatAction typing` while a telegram-origin nest item is
  outstanding).
- **In-flight inference.** One paragraph: the pulser doesn't track state. It
  globs `.nest/in/*-telegram-*.md*` each tick. Pending and `.tending` both
  match. When the runner moves the item to `.nest/out/`, the pulser goes
  quiet.
- **Env vars.** Document `TELEGRAM_PUSH_INTERVAL` (default 1) and
  `TELEGRAM_PULSE_INTERVAL` (default 4) alongside the existing
  `TELEGRAM_POLL_TIMEOUT`, `TELEGRAM_POLL_SLEEP`, etc.

## Don't

- Don't restate the entire bridge README — only patch what's now wrong or
  newly relevant.
- Don't add architecture diagrams; prose is fine.

## Done when

- README accurately describes the three loops and how to tune them.
- No stale references to the old "single loop that polls then pushes" shape.
