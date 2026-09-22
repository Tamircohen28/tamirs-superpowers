---
type: regex
target: { source: file, path: "skills/release-preflight/SKILL.md" }
match: not_contains
flags: m
weight: 0.5
---
^(?:triggers|use_when|trigger[-_]phrases|auto_invoke|tools|category|author|version|examples):
