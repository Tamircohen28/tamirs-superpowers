---
name: research-skill-isolation
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write]
tags: [fire, create]
---

Make me a skill that digs through a codebase to find everywhere a given environment variable is read — including indirect access like a config object or a getenv wrapper — and reports what it found with file and line references.

It does a lot of searching, so it should do that digging off to the side without cluttering up my main conversation.

Put it in `skills/env-var-trace/`.
