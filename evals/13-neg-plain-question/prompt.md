---
name: neg-plain-question
description: >-
  A plain git question with no task behind it. None of the dev-workflow skills (start-dev,
  worker-dev, pr-dev, orchestrate-dev, deliver-dev, switch-dev, plan-dev) may fire, and
  nothing may be written.
expected_outcome: >-
  A clear explanation of merge vs rebase and when to use each; no Skill invocation of a
  dev-workflow skill in either arm; no files created.
runs: 3
max_turns: 10
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
tags: [negative, dev-workflow]
---

What's the actual difference between `git merge` and `git rebase`, and when would you pick one over the other? Just explain it — I'm not changing anything right now.
