---
name: external-distribution
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write]
tags: [fire, create, constraint]
---

Build me a skill that drafts release notes from a list of merged pull requests — grouped by type, with breaking changes called out first.

I want to upload this one to claude.ai later so my team can use it there, so make sure it won't break when I do.

Put it in `.claude/skills/release-notes/`.
