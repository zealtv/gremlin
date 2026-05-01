# s27-acceptance-6

Conversational test via `say`: "remind me to buy milk tomorrow at 9am". Verify:

- A file appears at `.groundhog/schedule/once/<tomorrow>/<slug>/message.md` with the reminder text.
- The reply confirms the reminder with the date.
- The reply style matches `reply-style.md` (short).
