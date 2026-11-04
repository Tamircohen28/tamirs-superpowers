---
name: feedback-status-cadence
description: When the user asks for status updates every N minutes during a long run, post them unprompted on that cadence — never wait to be asked
metadata:
  type: feedback
---

In the 2026-11-03/04 permission-levels run the user said "keep me updated every 10 min on the status" and then had to type "status?" about ten times over the following hours, each time more frustrated ("this is taking way to long").

**Why:** I only reported when a background task finished or the user asked, so long CI/validate waits looked like silence. The ask was explicit and I treated it as a one-off.

**How to apply:** when an update cadence is requested, keep it: on every wake-up (task notification, check-in) that lands past the interval, open with one or two lines — what is running, what finished, the next step and its ETA. If nothing will wake me before the next update is due, schedule one rather than going quiet. Short beats complete. Related: [[feedback-orchestration-speed]].
