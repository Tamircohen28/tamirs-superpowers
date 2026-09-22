---
type: regex
target: { source: file, path: ".claude/skills/onboard-service/SKILL.md" }
match: contains
flags: is
---
(?=.*dashboard)(?=.*SLO)(?=.*alert)(?=.*runbook)
