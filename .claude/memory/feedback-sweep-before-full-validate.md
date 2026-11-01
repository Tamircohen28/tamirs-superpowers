---
name: feedback-sweep-before-full-validate
description: "Before triggering an expensive full-suite gate to fix a reported issue, grep for every instance of the pattern first — fix once, validate once"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 2cf8ac00-e3a4-499b-bfcd-278317a64ff9
  modified: 2026-09-21T19:18:01.231Z
---

During the v3.9.0 release, doc contradictions in `docs/user/install/codex.md` were fixed one at
a time as a peer agent reported each one — three separate spots asserting the same false MCP
claim, discovered sequentially rather than swept in one pass. Each fix triggered (or landed
mid-flight during) a `make validate` run, producing 2–3 wasted multi-minute full-suite runs
before the final one that actually mattered.

**Why:** the cost of grepping the whole file/repo for every instance of a pattern is seconds.
The cost of a full-suite gate is minutes. Paying the expensive one N times because the cheap one
wasn't run first is backwards.

**How to apply:** when a report names one instance of a wrong claim/pattern, before fixing it —
`grep -rn` (or equivalent) for the pattern across the file or repo first, fix every instance
found, *then* trigger the expensive gate once. This is the same discipline as
[[feedback-background-task-exit-codes]] — background the gate, but also don't re-trigger it
reactively per-finding when one sweep-and-fix would do.

Related: [[feedback-verify-mechanism-claims]] (a hypothesis that explains all evidence is still
a hypothesis — the same logic applies to "I fixed the one instance I was told about").
