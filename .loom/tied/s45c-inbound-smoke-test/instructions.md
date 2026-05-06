# s45c-inbound-smoke-test

Verify the real Telegram inbound path on `~/Desktop/mygremlin`.

## Outcome

Sending a text message to the configured Telegram bot writes an inbound item, the tender appends the user turn to `transcript.md`, and the assistant reply reaches both transcript and Telegram.

## Scope

- Use the real bot configured in `s45b-local-copy-bot-setup`.
- Send a simple text message from Telegram.
- Observe the local copy's `.nest/in/`, `.nest/out/`, `transcript.md`, and bridge logs as needed.
- Keep testing notes free of bot token and chat id.

## Verification Notes

Create or append `verification.md` inside this stitch with:

- timestamp of test
- Telegram message text used, if nonsensitive
- whether `.nest/in/` received the item
- whether `transcript.md` received the matching `## user` and `## assistant` turns
- whether Telegram received the assistant reply
- any latency, formatting, or error behavior worth documenting

## Verify

1. Telegram text from the configured chat is accepted.
2. Text from any other chat is ignored or dropped according to the bridge design.
3. Non-text input does not crash the bridge.
4. The tender, not the bridge, owns transcript writes.
5. Telegram receives the assistant reply once.

If this exposes implementation defects, fix them in the implementation files before tying this stitch.
