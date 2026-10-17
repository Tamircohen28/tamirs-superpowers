---
type: regex
target: { source: file, path: ".dev-files/objectives/login-rate-limit/handoffs/task-001.json" }
match: contains
---
"status"\s*:\s*"(?:completed|partial|failed|blocked)"
