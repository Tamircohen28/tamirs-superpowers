---
name: feedback-stacked-prs-fast-forward
description: "Several PRs that touch the same file region (CHANGELOG Unreleased) — stack them, run one CI round, and land the stack with a fast-forward push; a squash merge of the base re-conflicts every PR above it"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 24913b40-9931-473f-97b4-0cc26fdc1a9e
  modified: 2026-11-04T20:48:36.313Z
---

On 2026-11-04 five PRs (#356–#360) each added a bullet under `## [Unreleased]`. Squash-merging the first one
made the next three `CONFLICTING` on GitHub even though their content was a superset: the squash commit and the
branch both touch the same hunk, so the three-way merge sees overlapping edits, not identical ones. Rebasing after
each merge would have cost a ~30-minute `make validate` CI round per PR.

**Why:** the default-branch ruleset here requires linear history, so merge commits are out, and GitHub's rebase
merge rewrites SHAs, which recreates the same conflict for the next PR. Only a fast-forward keeps the stacked
commits' SHAs in master so the next PR's merge-base moves forward.

**How to apply:** rebase the PRs into one stack on `origin/master` (resolve the changelog by keeping both sides and
merging duplicate `### ` headings), push each branch, and let one CI round run on all of them in parallel. The
normal delivery path stays the PR merge (`gh pr merge --squash --admin`, each call approved by the user). Landing
the stack with `git push origin <head-sha>:refs/heads/master` is an **exception that needs the user's explicit
authorization for that push**, never a default: `core/policies/safety.md` invariant 5 forbids a direct push to the
protected default branch unless the repository allows it *and* the user asked. The admin role being able to bypass the ruleset is capability, not
authorization. On 2026-11-04 the user had said "merge all the green PRs" and confirmed the stack plan before the
push. When authorized: push the last green head in the stack; GitHub marks every PR whose head is now reachable as
merged, auto-deletes the branches, and closes `Closes #N` issues. If a PR in the middle turns red (or Codex finds
a real bypass), re-stack the ones above it directly onto master and move it to the end of the queue; each head
is a prefix of the next, so a partial fast-forward is always possible. A watcher on `statusCheckRollup` must treat
an empty rollup or an empty `conclusion` string as still pending — `//` in jq does not, and both fooled a first
version. Related: [[feedback-orchestration-speed]], [[feedback-wait-for-codex-before-merge]].
