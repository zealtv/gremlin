# s03-acceptance-telegram-responsiveness

Verify the three-loop bridge on the live host (`fanta:~/gizmo`) via the user's
ssh tmux pane. `/update` to push canonical first.

## Checks

1. **Typing on inbound.** Send a normal message from Telegram. Indicator
   appears within ~4s and persists continuously until the assistant turn
   lands.
2. **Outbound is prompt.** The reply arrives within ~1s of the assistant turn
   being appended to `transcript.md` (no longer gated by the inbound
   long-poll).
3. **Pulser is binary, not per-message.** Send a second message while the
   first is still in flight. The indicator keeps running, not flicker; goes
   quiet only when *all* telegram nest items are done.
4. **Idle silence.** With nothing in `.nest/in/`, no typing action is sent.
   Confirm by tailing `telegram.log` for a minute of inactivity.
5. **Clean stop.** `gremlin telegram stop` returns promptly. `pgrep -f
   telegram.sh` returns nothing — no orphaned loops.
6. **Restart works.** `gremlin telegram restart` recovers to a normal state;
   next message round-trips fine.

## Done when

All six checks pass on fanta. Tie off and consider whether daily use surfaces
anything worth a follow-up stitch (e.g., tuning intervals, indicator behaviour
during very long calls).
