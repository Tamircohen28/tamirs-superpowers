---
type: regex
target: files
match: not_contains
flags: m
---
^(?!src/auth/rate_limit\.py$|tests/test_rate_limit\.py$|\.dev-files/).+$
