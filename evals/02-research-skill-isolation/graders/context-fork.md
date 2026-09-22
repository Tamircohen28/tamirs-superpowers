---
type: regex
target: { source: file, path: ".claude/skills/env-var-trace/SKILL.md" }
match: contains
flags: m
---
^context:\s*['"]?fork['"]?\s*$
