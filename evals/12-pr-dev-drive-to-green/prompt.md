---
name: pr-dev-drive-to-green
description: >-
  A user asks to drive a pull request with red checks to merge. The plugin's pr-dev skill
  should read the PR's checks through the bundled github server, identify the failing
  required check, and refuse to merge while it is red. The suite's mocks answer with a PR
  whose required check `test (ubuntu-latest)` is failing on the current head.
expected_outcome: >-
  pr-dev fires; pull_request_read is called; the response names `test (ubuntu-latest)`
  (or the failing test it runs) as what is blocking, and merge_pull_request is never called.
  Without GitHub access, the honest answer — "I can't read the checks from here; here is
  what I would read" — passes the behaviour grader too; the indicators show which path ran.
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write]
tags: [fire, dev-workflow, github]
---

PR #87 in acme/webapp has red checks. Get it green and merged.
