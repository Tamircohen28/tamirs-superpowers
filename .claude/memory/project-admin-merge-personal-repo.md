---
name: project-admin-merge-personal-repo
description: tamirs-superpowers requires --admin for all PR merges (solo repo, branch protection on)
metadata:
  type: project
---

tamirs-superpowers has branch protection requiring 1 approving review, but Tamir is the sole contributor — self-review is not possible on GitHub.

**Why:** Every PR merge in this repo hits `mergeStateStatus: BLOCKED` / `reviewDecision: REVIEW_REQUIRED`. Standard `gh pr merge --squash` fails. `--admin` is the correct and expected merge path.

**How to apply:** Always use `gh pr merge "$PR" --squash --delete-branch --admin` for this repo. No need to surface this as a blocker or ask — it's the established workflow. (See [[feedback-ci-yml-guard-hook]] for the parallel pattern with workflow files.)
