---
type: regex
target: { source: file, path: ".claude/skills/release-preflight/SKILL.md" }
match: contains
flags: m
---
^name:\s*[a-z0-9]+(?:-[a-z0-9]+)*\s*$
