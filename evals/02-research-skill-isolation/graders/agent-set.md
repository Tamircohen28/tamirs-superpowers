---
type: regex
target: { source: file, path: "skills/env-var-trace/SKILL.md" }
match: contains
flags: m
---
^agent:\s*['"]?[A-Za-z0-9][A-Za-z0-9_:./-]*['"]?\s*$
