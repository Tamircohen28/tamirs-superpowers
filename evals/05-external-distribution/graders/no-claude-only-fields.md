---
type: regex
target: { source: file, path: ".claude/skills/release-notes/SKILL.md" }
match: not_contains
flags: m
---
^(?:context|agent|background|disable-model-invocation|user-invocable|effort|model|argument-hint|arguments|paths|shell|hooks|when_to_use|disallowed-tools):
