---
name: start-dev-from-issue
description: >-
  A user asks to implement a GitHub issue. The plugin's start-dev skill should take it,
  read the issue through the bundled github server, and set the work up where this
  workflow keeps it — an objective/worktree under .dev-files/ or a worktree branch —
  never by editing the main checkout directly.
expected_outcome: >-
  start-dev fires; the issue is read; the response proposes or creates objective/worktree
  state under .dev-files/ (or names the worktree/branch it would create); no source file
  is written outside that state; no pull request is opened.
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write]
tags: [fire, dev-workflow, github]
---

Implement issue #42 from acme/webapp. Set it up the way you'd normally start a task — I don't want anything landing in the main checkout until it's been through the proper flow.
