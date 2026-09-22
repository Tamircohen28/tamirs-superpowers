---
type: regex
target: { source: file, path: ".claude/skills/db-migrate/SKILL.md" }
match: contains
flags: im
---
(?:^when_to_use:\s*\S|use when|triggers?:)
