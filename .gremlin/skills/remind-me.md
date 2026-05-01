---
name: remind-me
triggers:
  - user asks to be reminded of something at a future time
  - user says "remind me", "follow up", "ping me later"
---

# remind-me

When the user asks to be reminded, schedule it by creating a file under `.groundhog/`. Do not confirm in prose only — actually create the file, and never guess the current time.

Groundhog reads **local time**, and the user thinks in local time. Use local dates and times throughout: in the path, in the body, and in your confirmation reply.

## Steps

1. **Run `./tools/now.sh` first.** Always. It returns the current local time with offset (e.g. `2026-05-01T21:15:00+1000`). The LLM does not know the current time; skipping this and inferring "tomorrow" from training data will give the user a wrong date.

2. Resolve the reminder's fire date in local time, using the timestamp from step 1 as the anchor. "Tomorrow" = day after that timestamp's date; "in three days" = +3 days; "next Monday" = next occurrence of Monday; etc. If the user gives an absolute date, use it as stated.

3. Pick a kebab-case slug summarising the reminder (e.g. `buy-milk`, `call-jess`, `submit-invoice`).

4. Compose the reminder body — the message to deliver when the reminder fires. Write it in the user's voice (e.g. "buy milk at 9am"). If the user gave a time of day, include it here — groundhog's `once/` axis is per-day.

5. Create the file with bash:

   ```bash
   mkdir -p .groundhog/schedule/once/<YYYY-MM-DD>/<slug>
   cat > .groundhog/schedule/once/<YYYY-MM-DD>/<slug>/message.md <<'EOF'
   <reminder body>
   EOF
   ```

6. Confirm to the user, **stating the resolved local date and the time-of-day text** verbatim from the body, so the user can spot a wrong resolution immediately.
