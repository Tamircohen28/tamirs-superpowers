---
name: feedback-skill-creator-required
description: Always use /skill-creator (never hand-write SKILL.md) when creating or editing any skill in tamirs-superpowers
metadata:
  type: feedback
---

Never hand-craft a SKILL.md file directly using Write or Edit tools. Always invoke the `/skill-creator` skill first.

**Why:** Hand-written skills are "poor" — they miss evals, reference docs, helper scripts, and the quality bar that skill-creator enforces. User explicitly corrected this when I wrote `pr-dev/SKILL.md` by hand instead of using `/skill-creator`.

**How to apply:** Any time a new skill needs to be created or an existing skill updated, invoke `Skill({skill: "tamirs-superpowers:skill-creator"})` with the skill requirements. Never reach for Write/Edit on a SKILL.md path as a first move.
