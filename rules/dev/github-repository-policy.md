---
alwaysApply: false
globs:
  - "config/github/**/*"
  - "core/schemas/repository-policy.json"
  - "scripts/github-policy.sh"
  - "scripts/lib/github-common.sh"
  - "scripts/check-github-policy.sh"
  - ".github/workflows/**/*"
  - "skills/repo/**/*"
---

# GitHub Repository Policy

How every repository this account owns is governed on GitHub: what protects the default branch, what gates a merge, and which workflows may have their runs cancelled.

The policy is **data, not prose**. It lives in [`config/github/repository-policy.json`](../../config/github/repository-policy.json), constrained by [`core/schemas/repository-policy.json`](../../core/schemas/repository-policy.json). This document explains the decisions; it never restates the values. If a rule, a status-check context, or a concurrency group appears in a SKILL.md, a script, or a doc, that copy is drift — delete it and read the JSON.

---

## 1. Rulesets, not classic branch protection

Governance is expressed as **repository rulesets** (`repos/{owner}/{repo}/rulesets`), not classic branch protection (`repos/{owner}/{repo}/branches/{branch}/protection`).

Classic protection is legacy here, and reading it is actively misleading: on a repository correctly governed by rulesets, `GET .../branches/{branch}/protection` returns **404**. Tooling that probes only the classic endpoint reports a protected repository as unprotected — that was a live defect in `ensure-branch-protection.sh` and `standards-inventory.sh` before this policy existed. Read rulesets first; treat classic protection as legacy state to migrate, never as the answer.

Two rulesets, in this order:

| Ruleset | What it does | Safe to apply when |
|---|---|---|
| **Default Branch - Safety** | No deletion, no force pushes | Day one. It depends on nothing. |
| **Default Branch - PR & CI** | Pull request required, linear history, CI contexts | Only after a CI workflow exists on the default branch |

Applying PR & CI to a repository with no matching CI jobs blocks every pull request in it forever. That ordering is the reason the policy ships two rulesets instead of one.

---

## 2. Never write a literal branch name

Every ruleset targets the default branch through GitHub's magic ref **`~DEFAULT_BRANCH`**, in `conditions.ref_name.include`.

This is not a stylistic preference. The governed fleet mixes both default-branch spellings — 15 repositories use one, 4 use the other — so any literal is silently wrong on one of those sets, and it stops matching entirely the moment a default branch is renamed. `scripts/check-github-policy.sh` scans every string value in the policy and fails on a literal branch name or a `refs/heads/` prefix.

The same applies in code: resolve a default branch with `git symbolic-ref --quiet --short refs/remotes/origin/HEAD`, or `github_default_branch` from the shared library. Never hardcode one, never guess.

---

## 3. "Require branches to be up to date" is OFF, on purpose

`strict_required_status_checks_policy` is **false**, and it must stay false.

This is the single most likely thing for a well-meaning contributor to "fix", so the reason is worth stating plainly.

Development here runs as **one objective → a task DAG → parallel workers → an integration branch → one pull request**. Several worker branches and their PRs are open at the same time by design. With strict checks on, every merge into the default branch invalidates the green status of every other open pull request, and each must rebuild before it can merge:

- N merges cost **O(N²)** CI runs instead of O(N).
- Workers serialize behind each other for no correctness gain.
- The integration PR can never stay green long enough to land, because a sibling merge un-greens it mid-flight.

What protects correctness instead:

- **`required_linear_history`** — no merge commit can quietly introduce a combination that was never tested as a unit.
- **A full CI run on the integration branch** before it merges. That is the point where the combined result is verified, and it is verified once rather than N times.
- **Required contexts** on the pull request itself, so nothing merges red.

The policy encodes the decision twice: the boolean, and a `strict_is_intentional` acknowledgement flag next to it. The schema pins both with `const`, so flipping the toggle requires editing the schema — which is exactly the amount of friction the decision deserves. If you believe strict checks are needed, change the development architecture first, then this.

---

## 4. Required status-check contexts are per repository, never global

A context is a **CI job name**. Job names differ from repository to repository, and a required context that no workflow produces is not a stricter gate — it is a pull request that can never merge.

So: the account-wide default context list is **empty**, and each repository opts its own contexts in under `repositories.<owner/repo>.required_checks.contexts`. Contexts are paired with the GitHub Actions app's `integration_id` when the payload is rendered; without it, any app that reports a matching check name can satisfy the requirement.

**Adding a CI job does not make it blocking.** The job's `name:` must also be added to that repository's context list and the policy re-applied. This repository requires 9 of its CI jobs; the rest run and report without gating.

---

## 5. Reviews: zero approvals, mandatory thread resolution

`required_approving_review_count` is **0**, and `required_review_thread_resolution` is **true**. These are one decision, not two.

This is a single-author account. A requirement for one approving review cannot be satisfied honestly — it can only be satisfied by merging with `--admin`, and a rule that is routinely bypassed is worse than no rule, because it makes the ruleset page lie. Setting the count to zero and requiring every review thread to be resolved keeps a real gate: an unresolved comment, from a human or from a review bot, blocks the merge.

For the same reason `require_code_owner_review`, `require_last_push_approval`, and `dismiss_stale_reviews_on_push` are all false. There is no second owner to review, no second author to approve the last push, and nothing to dismiss.

### Bypass actors

The canonical policy sets `bypass_actors: []`. An always-bypass for repository admins on a single-admin account means every rule above is advisory — and it is invisible in the summary view, which makes it the most dangerous kind of drift. The policy keeps the field explicit rather than omitting it, precisely so that an actor added on github.com shows up as a diff.

---

## 6. How this interacts with one-objective / one-PR

The two fit together deliberately:

- **One PR per objective** means the default branch sees few, large, already-integrated merges. That is what makes linear history readable and a revert a single commit.
- **Parallel workers** means many branches exist at once but only one becomes a pull request. Their correctness is established on the integration branch, not by each rebasing onto every sibling's merge.
- **Zero required approvals** keeps the solo author's merge path honest, so no step in the loop needs `--admin`.
- **Non-strict checks** is what lets the above run in parallel at all.

Remove any one of these and the others stop making sense. Treat them as a set.

---

## 7. Actions concurrency standard

Cancelling a superseded workflow run is free money on a test workflow and data loss on a deployment. The policy therefore classifies workflows as **data** — name patterns plus content signals a script can match — rather than leaving it to judgement.

**Cancellable** — pure, repeatable verification. A cancelled run leaves nothing behind, and the newer commit's run supersedes it anyway:

- tests, lint, typecheck, build
- repository/plugin validation
- read-only security and static analysis (CodeQL, secret scans)

These get the canonical concurrency block: grouped on the workflow plus the PR number (falling back to the ref), with `cancel-in-progress: true`.

**Never cancel** — anything that mutates state outside the repository. A cancelled run leaves that state half-written, and there is no "just re-run it":

- deployments and environment promotions
- releases, tags, and package publishing
- database migrations
- infrastructure provisioning (Terraform, cloud CLIs)
- anything requesting an OIDC token, declaring an `environment:`, or triggered by a release or tag push

If two of these must not overlap, use the **serializing** block instead — same group, `cancel-in-progress: false` — so the second run queues behind the first rather than killing it.

**Precedence: `never_cancel` wins.** A workflow matching signals in both classes is never cancelled. A test job wrongly serialized costs minutes; a deployment wrongly cancelled costs an inconsistent external system.

**Unclassified workflows are reported, not guessed at.** A workflow matching neither class is surfaced for a human decision and left untouched.

---

## 8. Transport and permissions

Per [`gh-cli-preference.md`](gh-cli-preference.md), all of this goes through the **`gh` CLI** — never GitHub MCP, never browser automation. Every read and write goes through the one abstraction in [`scripts/lib/github-common.sh`](../../scripts/lib/github-common.sh); do not add a fifth spelling of `gh api repos/...` to another script.

`gh` is normally an optional feature dependency. **Here it is not**: repository policy *is* a GitHub action, so a missing or unauthenticated `gh` is a hard, reportable failure with a named cause — never a silent skip and never a local substitute.

### Required permissions

| Operation | Needs |
|---|---|
| Read rulesets, repository metadata | `repo` scope; read access to the repository |
| Create / update / delete rulesets | `repo` scope **and repository admin** |
| Rulesets on an organization-owned repository | `admin:org` in addition, when the ruleset is org-level |
| Edit workflow files | `workflow` scope |

The library distinguishes and reports each failure mode separately — unauthenticated, insufficient scope, plain permission denial, organization or enterprise policy, rate limit (with the retry delay), unsupported plan or feature, and an unexpected response shape. None of them is ever swallowed, because "nothing happened" and "you are not allowed to see this" must never look the same to the caller.

---

## 9. Changing the policy

1. Edit `config/github/repository-policy.json`.
2. Bump its `version` — every content change, per the `_contract` canonical-config pattern.
3. Run `bash scripts/check-github-policy.sh` (offline; no network, no `gh`).
4. Run the policy entrypoint's `plan` verb to see live drift. `plan` never writes.
5. Apply only after confirming the diff. Applying mutates live branch governance and can lock the author out of their own default branch.
