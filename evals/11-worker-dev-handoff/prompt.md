---
name: worker-dev-handoff
description: >-
  A dispatched worker is given exactly one task of an objective and asked to work it and
  hand off. The plugin's worker-dev skill should implement inside scope, validate what it
  can, and end at a handoff file whose status is honest — never at a pull request.
expected_outcome: >-
  worker-dev fires; src/auth/rate_limit.py and/or tests/test_rate_limit.py are written and
  nothing outside scope; .dev-files/objectives/login-rate-limit/handoffs/task-001.json exists
  with status in completed|partial|failed|blocked, validation entries that only record
  commands actually run (or an honest non-completed status when none could be), and no PR.
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write]
tags: [fire, dev-workflow]
---

You're the implementer for task-001 of objective `login-rate-limit`. Work this task and hand off.

The orchestrator already wrote the task file at `.dev-files/objectives/login-rate-limit/tasks/task-001.json`; here is its content, since you're starting in a fresh checkout:

```json
{
  "schema_version": 1,
  "id": "task-001",
  "title": "Add a token-bucket limiter for POST /login (5 attempts per minute per client IP)",
  "role": "implementer",
  "scope": ["src/auth/rate_limit.py", "tests/test_rate_limit.py"],
  "depends_on": [],
  "validation_tier": "worker",
  "branch": "worker/login-rate-limit/001",
  "status": "ready"
}
```

The limiter is a small Python class: `RateLimiter(limit=5, window_seconds=60)` with `allow(client_ip) -> bool`, in-memory, no external dependencies. When you're done, write the handoff to `.dev-files/objectives/login-rate-limit/handoffs/task-001.json`.
