---
name: feedback-wait-for-codex-before-merge
description: The Codex PR reviewer posts 5-10 min after CI is green; a 👀 reaction means it is still reviewing — wait for it before merging or accept a follow-up PR
metadata:
  node_type: memory
  type: feedback
  originSessionId: 03613cd1-02ee-4604-ab0f-03bd4306a67a
  modified: 2026-10-06T16:00:50.869Z
---

This repo has the `chatgpt-codex-connector` reviewer. It adds a 👀 reaction to the PR while
reviewing, then posts a review (often with inline threads) — typically 5-10 minutes after the checks
go green. A 👍 reaction with no review means it found nothing.

**Why:** it caught real bugs on three of the last four PRs (2026-10-04/06): #262 a removed step that
was `plan-dev`'s only default-branch resolution; #263 a `gh api user` check that breaks GitHub
Enterprise and a guard regex missing whitespace variants; #267 a contradicted field-support matrix.
#267 was merged while the reaction was still 👀, so its finding needed follow-up PR #268.

**How to apply:** at the readiness gate, if the Codex reaction on the PR is 👀, wait (bounded, ~10 min)
for the review, then re-read unresolved threads before merging. Check reactions with
`gh api repos/<repo>/issues/<n>/reactions`. If you merge anyway (user approved), say the review is
still pending. Related: [[project-admin-merge-personal-repo]].
