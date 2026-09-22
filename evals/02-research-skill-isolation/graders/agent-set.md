---
type: regex
target: { source: file, path: "skills/env-var-trace/SKILL.md" }
match: contains
flags: m
---
^agent:\s*['"]?(?:Explore|general-purpose|Plan)['"]?\s*$
