---
name: new-skill-from-workflow
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write]
tags: [fire, create]
---

Before every release we go through the same checks by hand: run the test suite, confirm CHANGELOG.md has an entry for the new version, verify the version in package.json matches the git tag, and check that no new TODO comments slipped in.

I want this as a reusable skill I can trigger instead of re-reading my own notes every time. Set it up properly.

Put it in `skills/release-preflight/`.
