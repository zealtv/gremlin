# s45b-local-copy-bot-setup

Prepare `~/Desktop/mygremlin` for real Telegram bridge verification using the current canonical work.

## Outcome

A local gremlin copy at `~/Desktop/mygremlin` is running the current Telegram bridge code with a real bot token and single test chat id stored only in that copy's ignored config file.

## Scope

- Sync or install the current canonical `.gremlin/` into `~/Desktop/mygremlin` using the repo's documented local-copy workflow.
- Preserve any personal/local state in `~/Desktop/mygremlin` unless the user explicitly approves replacing it.
- Create `~/Desktop/mygremlin/.gremlin/bridges/telegram/config` from `config.example` with the user's real bot token and chat id. Do not write credentials into this repo.
- Start or restart the local gremlin runner only for the local copy.
- Start the Telegram bridge against the local copy.

## Verification Notes

Create a short `verification.md` inside this stitch with:

- exact sync/install command used
- exact non-secret start/status commands used
- bridge status result
- any setup friction or missing docs discovered

## Verify

1. `~/Desktop/mygremlin/.gremlin/bridges/telegram/config` exists and is not in this repo.
2. The local gremlin runner reports running.
3. The local Telegram bridge reports running.
4. No secret values appear in this stitch's notes, transcript, shell output copied into docs, or repo files.

This stitch is setup only. Do not count the bridge done until the inbound and outbound child stitches pass.
