---
name: project-admin-merge-personal-repo
description: tamirs-superpowers no longer needs --admin to merge — branch protection was fixed on 2026-08-02; plain auto-merge works
metadata:
  type: project
---

**As of 2026-08-02, `--admin` is no longer required to merge PRs in tamirs-superpowers.** Plain `gh pr merge "$PR" --auto --squash --delete-branch` reaches `mergeStateStatus: CLEAN` and merges on its own.

**What was wrong:** branch protection on `master` required a status context literally named `CI`, which no job ever reported — the commit status API returned `{"contexts": [], "state": "pending"}` permanently. Combined with `required_approving_review_count: 1` on a repo where Tamir is the sole contributor (GitHub forbids self-approval), **every** PR sat at `BLOCKED` / `REVIEW_REQUIRED` and auto-merge could never fire. PRs #66–#72 all merged via `--admin` with zero reviews.

**What changed:**

| Setting | Before | After |
|---|---|---|
| `required_status_checks.contexts` | `["CI"]` (phantom) | the 9 real job names |
| `required_approving_review_count` | `1` (unsatisfiable) | `0` |

Requiring the real job names matters — emptying the list would have left *no* CI gate at all. `required_pull_request_reviews` is still present with count `0`, so a PR is still required and direct pushes to master remain blocked; only the impossible approval requirement is gone. `enforce_admins` stays `false`.

**How to apply:** merge normally — `gh pr merge "$PR" --auto --squash --delete-branch`. Reserve `--admin` for a genuine emergency, not as the default path. If a PR sits at `BLOCKED` again, check `gh api repos/Tamircohen28/tamirs-superpowers/branches/master/protection` before assuming a reviewer is coming; a required context that no job reports looks identical to "CI still queued" but never resolves.

Renaming or removing a CI job now blocks merges until the required-contexts list is updated to match. See [[reference-release-tag-alignment]] and [[feedback-ci-yml-guard-hook]].
