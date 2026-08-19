# The GitHub API surface behind this skill

Read this when a run fails, degrades, or reports something you cannot explain
from the human report alone. Nothing here is a rule you may restate elsewhere —
the policy itself lives in `config/github/repository-policy.json` and only
there.

Every call below is issued by `scripts/lib/github-common.sh` (repository level)
or `scripts/lib/github-org.sh` (organization level) through one `gh api`
primitive. Never call these endpoints yourself to "check something quickly": the
primitive is what classifies the failure, and a bare `gh api` gives you a body
without the classification, which is how a rate limit gets reported as a
permissions problem.

---

## Repository level

| Call | Endpoint | Used for |
|---|---|---|
| list rulesets | `GET /repos/{owner}/{repo}/rulesets?includes_parents=false` | what this repo defines itself |
| list with parents | `GET /repos/{owner}/{repo}/rulesets?includes_parents=true` | what it *inherits* from its org |
| read one | `GET /repos/{owner}/{repo}/rulesets/{id}` | rules, conditions, bypass actors |
| create | `POST /repos/{owner}/{repo}/rulesets` | `apply`, after a confirmation |
| update | `PUT /repos/{owner}/{repo}/rulesets/{id}` | `apply`, after a confirmation |
| classic protection | `GET /repos/{owner}/{repo}/branches/{branch}/protection` | legacy — read, never written |
| workflows | `GET /repos/{owner}/{repo}/contents/.github/workflows` | Actions concurrency audit |
| repository | `GET /repos/{owner}/{repo}` | default branch, fork, archived, visibility |
| collaborators | `GET /repos/{owner}/{repo}/collaborators` | one input to the derived approval count; issued **only** when a bypass actor is present |

A `404` on the classic-protection endpoint is the healthy, common answer on a
rulesets-governed repository. It is not an error and is never reported as one.

## Organization level

| Call | Endpoint | Used for |
|---|---|---|
| list | `GET /orgs/{org}/rulesets` | the availability probe **and** the listing — there is no cheaper question |
| read one | `GET /orgs/{org}/rulesets/{id}` | rules and targeting |
| create | `POST /orgs/{org}/rulesets` | `apply --org X --org-level` only |
| update | `PUT /orgs/{org}/rulesets/{id}` | `apply --org X --org-level` only |
| repositories | `GET /orgs/{org}/repos?type=all` | the sweep list |

### Targeting — the only thing an org ruleset has that a repo ruleset does not

```json
"conditions": {
  "ref_name":        { "include": ["~DEFAULT_BRANCH"], "exclude": [] },
  "repository_name": { "include": ["~ALL"], "exclude": [], "protected": false }
}
```

`repository_name` may instead be `repository_id` (a fixed list of ids, which
does not cover future repositories and is therefore never rendered here) or
`repository_property` (custom-property matching, which needs properties defined
on the org — neither `ProductionMasterAI` nor `SentinelAIOrg` has any as of
2026-08-19, so `repository_name` is what the renderer emits).

`~ALL` is what makes the org ruleset worth having: it covers repositories that
do not exist yet.

---

## What each failure means, and what the tool does with it

The probe classifies by **message wording first, status code second** — because
GitHub returns 403 for at least four unrelated situations and only `.message`
tells them apart.

| Observed | Class | Behaviour |
|---|---|---|
| `200` + JSON array | `ok` | org-level available |
| `403` "Upgrade to GitHub Team to enable this feature." | `plan` | **degrade**: report that org ruleset management is unavailable on this organization's plan, fall back to per-repository |
| `403` "Token does not have the required scope: administration" / OAuth wording | `scope` | degrade; remedy is `gh auth refresh -h github.com -s admin:org` |
| `403` "…organization has enabled OAuth App access restrictions" / SAML / IP allow list | `org_policy` | degrade; needs an org admin, not a scope |
| `403` other | `permission` | degrade; this token is not an organization owner |
| `404` | `not_found` | degrade; the org does not exist or is invisible to this token |
| `422` "…not available…" / "…plan…" | `plan` | degrade, as above |
| `429` / `403` with `x-ratelimit-remaining: 0` | `rate_limited` | transient; retry after `Retry-After` |
| `409` on a write | `conflict` | the ruleset changed since it was read — **re-plan and re-diff, never retry the same payload** |
| `5xx` or no response | `network` | a real failure. Nothing may be concluded about the plan or the permissions |

**Only the last row is a failure.** Everything above it is a degrade: the tool
continues with per-repository policy and states the reason. Report the reason
the tool printed rather than a paraphrase — "your plan does not support this"
and "you are missing a scope" send the user to completely different places.

---

## Two shapes that surprise people

**Classic protection and rulesets both apply.** They are not alternatives.
GitHub evaluates every rule targeting the branch and the strictest requirement
wins. `GET .../rulesets` returning the right thing therefore does not mean the
branch is governed the way the ruleset says.

**`includes_parents=true` is how inheritance becomes visible.** With
`includes_parents=false` an organization ruleset that governs the repository is
simply not in the listing, so a repository can look ungoverned while an org rule
blocks every merge. Entries whose `source_type` is not `Repository` are
inherited and are never edited from the repository side.
