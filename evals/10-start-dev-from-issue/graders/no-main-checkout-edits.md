---
type: regex
target: files
match: not_contains
flags: m
---
^(?!\.dev-files/|\.agent-worktrees/).+$
