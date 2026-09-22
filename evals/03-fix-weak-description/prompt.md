---
name: fix-weak-description
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write]
tags: [fire, repair]
---

This skill never fires on its own. I always have to type the slash command myself, even when I'm obviously doing the thing it's for. Figure out why, and give me the fixed version.

```markdown
---
name: db-migrate
description: A utility for database stuff.
---

# DB Migrate

Steps:
1. Check for pending migrations in `db/migrate/`.
2. Run them against the local database.
3. Regenerate `schema.rb`.
4. Confirm the schema version advanced.
```

Write the corrected file to `skills/db-migrate/SKILL.md`.
