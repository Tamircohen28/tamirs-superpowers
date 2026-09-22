---
type: regex
target: { source: file, path: "skills/onboard-service/SKILL.md" }
match: contains
flags: is
---
(?=.*dashboard)(?=.*SLO)(?=.*alert)(?=.*runbook)
