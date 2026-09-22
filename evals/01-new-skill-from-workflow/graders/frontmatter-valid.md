---
type: regex
target: { source: file, path: "skills/release-preflight/SKILL.md" }
match: contains
---
^---\r?\n(?:[^\n]*\r?\n)*?name:[ \t]*[a-z0-9]+(?:-[a-z0-9]+)*[ \t]*\r?\n(?:[^\n]*\r?\n)*?---\r?\n
