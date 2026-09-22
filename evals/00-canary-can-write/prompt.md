---
name: canary-can-write
description: >-
  Cheapest possible check that the plugin does not prevent Claude from writing a
  file. Added after the first pilot, where every authoring case scored 0 because
  the plugin's PreToolUse worktree hook denied all writes in the eval sandbox.
expected_outcome: >-
  hello.txt is created containing "ready", in BOTH arms. A negative delta here
  means the plugin is blocking writes and every authoring case below is
  measuring nothing.
runs: 3
max_turns: 4
timeout_seconds: 90
allowed_tools: [Write]
tags: [canary]
---

Create a file called hello.txt in the current directory containing exactly the word: ready
