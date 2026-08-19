# `tests/fixtures/github` — canned GitHub API responses

Served by [`tests/lib/fake-gh.sh`](../../lib/fake-gh.sh). Every response the
GitHub-policy tests see comes from this tree; nothing reaches the network.

Point the shim at one directory at a time:

```bash
fake_gh_install "$TMP/bin" "$TMP/gh.log" "$REPO_ROOT/tests/fixtures/github/drifted"
PATH="$TMP/bin:$PATH"
# ... or, mid-test:
fake_gh_use_fixtures "$REPO_ROOT/tests/fixtures/github/compliant"
```

## Scenarios

| Directory | Represents | Primary requirement it covers |
|-----------|-----------|-------------------------------|
| [`compliant`](compliant/README.md) | the ground-truth repo, already correct | idempotence — zero mutations |
| [`no-rulesets`](no-rulesets/README.md) | ungoverned repo | greenfield create, `[]` is a state not an error |
| [`partial`](partial/README.md) | Safety only | per-ruleset reconciliation, resumability |
| [`drifted`](drifted/README.md) | `strict_required_status_checks_policy: true` | the forbidden setting, nested one field deep |
| [`classic-protection`](classic-protection/README.md) | legacy branch protection | the migration path, untestable live |
| [`custom-ruleset`](custom-ruleset/README.md) | canonical two + a user ruleset | never delete what the policy does not own |
| [`org-conflict`](org-conflict/README.md) | stricter org-level ruleset | org rulesets are read-only here and compose |
| [`different-checks`](different-checks/README.md) | foreign required contexts | contexts are per-repo, never globalised |
| [`no-actions`](no-actions/README.md) | no workflows | do not require checks nothing can report |
| [`default-main`](default-main/README.md) | `default_branch: main` (15/19) | `~DEFAULT_BRANCH`, not a literal |
| [`default-master`](default-master/README.md) | `default_branch: master` (4/19) | the same, from the other side |
| [`default-trunk`](default-trunk/README.md) | `default_branch: trunk` | catches `main`-or-`master` special-casing |
| [`no-permission`](no-permission/README.md) | 403, "not accessible by" | named degradation, run continues |
| [`insufficient-scope`](insufficient-scope/README.md) | 403, token lacks `administration` | re-authorize, not "get admin" |
| [`org-policy`](org-policy/README.md) | 403, org restriction | the 403 the operator cannot fix alone |
| [`forbidden`](forbidden/README.md) | 403, none of the above | the residual class |
| [`server-error`](server-error/README.md) | 502 | transient; retry, do not report as a finding |
| [`rate-limited`](rate-limited/README.md) | 403 + `Retry-After` | throttle ≠ permission failure |
| [`auth-failed`](auth-failed/README.md) | 401 everywhere | hard stop before any repo is touched |
| [`conflict`](conflict/README.md) | 409 on `PUT` | write-side failure, isolate and continue |
| [`unprocessable`](unprocessable/README.md) | 422 on `POST` | structured `.errors`, not just `.message` |
| [`classic-overlap`](classic-overlap/README.md) | rulesets AND classic protection on one branch | GitHub aggregates both; the stricter wins, so compliant rulesets are not the whole story |
| [`org-available`](org-available/README.md) | `orgs/{org}/rulesets` → `200 []` (measured: plan `team`) | org-level targeting is available and preferred |
| [`org-plan-free`](org-plan-free/README.md) | `403` "Upgrade to GitHub Team" (measured: plan `free`) | a plan wall is a degrade with an honest reason, never a permissions error |
| [`org-scope`](org-scope/README.md) | `403`, token lacks `admin:org` | same status code as the plan wall, different remedy |
| [`org-notfound`](org-notfound/README.md) | `404` on the org | invisible org degrades, does not fail |
| [`org-unreachable`](org-unreachable/README.md) | `500` on the org | the one org-probe outcome that IS a failure |
| [`org-stricter`](org-stricter/README.md) | an org ruleset stricter than canonical | CONFLICT and leave alone — no flag overrides it |
| [`org-drift`](org-drift/README.md) | canonical rulesets live at org level, one drifted | org-level idempotence, plus coverage narrowing |
| [`fleet`](fleet/README.md) | three repos, three states | bulk iteration, per-repo isolation |
| [`_defaults`](_defaults/README.md) | shared fallbacks | write responses, auth, repo list |

## File naming

The shim maps an API path to a fixture basename:

| Path | Fixture |
|------|---------|
| `repos/{o}/{r}` | `repo.json` |
| `repos/{o}/{r}/rulesets` | `rulesets.json` |
| `repos/{o}/{r}/rulesets/{id}` | `ruleset-{id}.json` |
| `repos/{o}/{r}/branches/{b}/protection` | `protection.json` |
| `repos/{o}/{r}/actions/workflows` | `workflows.json` |
| `orgs/{org}/rulesets` | `org-rulesets.json` |
| `orgs/{org}/rulesets/{id}` | `org-ruleset-{id}.json` |
| `user/repos`, `users/{u}/repos`, `orgs/{o}/repos` | `repo-list.json` |
| `rate_limit` | `rate-limit.json` |
| `user` | `user.json` |
| `gh repo view` / `gh repo list` | `repo-view.json` / `repo-list.json` |

Lookup order: `by-repo/{owner}__{repo}/{METHOD}-{name}.json` →
`by-repo/{owner}__{repo}/{name}.json` → `{METHOD}-{name}.json` →
`{name}.seq/{n}.json` → `{name}.json` → `_defaults/{METHOD}-{name}.json` →
`_defaults/{name}.json` → `_defaults/{METHOD}.json` (writes only).

`{name}.seq/1.json`, `2.json`, … serve one response per call and then repeat the
last — that is how "apply, then read back and see the new state" is expressed.

## Error injection

A scenario's `errors.txt` holds `<METHOD|ANY> <path-glob> <status>` lines;
`fake_gh_error` appends the same at runtime and is consulted first. Bodies use
GitHub's real envelope (`message` / `documentation_url` / `status`, plus `errors`
for 422) and can be overridden per scenario with `errors/<status>.json`.

| Token | HTTP | Classifies as | Distinguished by |
|-------|------|---------------|------------------|
| `401` | 401 | `unauthenticated` | status |
| `403` | 403 | `insufficient_scope` | body: "not accessible by" |
| `403-scope` | 403 | `insufficient_scope` | body: "scope" |
| `403-org-policy` | 403 | `org_policy` | body: "organization has enabled" |
| `403-saml` | 403 | `org_policy` | body: "SAML enforcement" |
| `403-rate-limit` | 403 | `rate_limited` | body: "rate limit" + `x-ratelimit-remaining: 0` |
| `404` | 404 | `not_found` | status |
| `404-unsupported` | 404 | `unsupported` | body: "upgrade" |
| `409` | 409 | `conflict` | status |
| `422` | 422 | `invalid_request` | status, plus `.errors[]` detail |
| `429` | 429 | `rate_limited` | status + `retry-after` |
| `451` | 451 | `org_policy` | status |
| `500` `502` `503` | 5xx | `network` | status |
| `no-response` | *none* | `network` | no status line at all |

**Five of these are HTTP 403 and differ only in `.message`.** That is how GitHub
actually reports them, and the class decides what the operator does next:
re-authorize a token, ask an org admin, wait out a throttle, or get admin on the
repo. A fixture whose body matched an earlier branch would pass for the wrong
reason, which is why `forbidden` needs its own body override.

**Order matters within 403.** Both of GitHub's real org-restriction messages
mention OAuth, so `github_api` tests org-policy wording *before* scope wording;
reversed, both would report as a missing scope and send the operator to
`gh auth refresh`, which cannot fix an org restriction. `403-org-policy` and
`403-saml` are the regression guard for that ordering, and the suite also asserts
that those bodies genuinely contain "OAuth" — otherwise the guard would pass
while testing nothing.

## The `--include` header contract

`scripts/lib/github-common.sh` runs every call as
`gh api --include --method <M> <path>` and classifies from the status line **plus
the `retry-after`, `x-oauth-scopes` and `x-ratelimit-remaining` headers**. The
shim therefore emits a complete header block, a blank line, then the body —
never a bare body. A plain 403 deliberately carries a *healthy*
`x-ratelimit-remaining`, so that "403 with remaining: 0 is a throttle" is a
discrimination the tests exercise rather than one that falls out of an absent
header.

`scopes.txt` in a scenario sets `x-oauth-scopes` (default: the measured token
from `ground-truth-rulesets.md`). `tests/test-fake-gh.sh` verifies all of this by
driving the real `github-common.sh` classifier — asserting the shim's header
format against the shim's own expectations would prove only self-consistency.

## Fidelity

Ruleset payloads are transcribed from `session-files/ground-truth-rulesets.md`,
captured live on 2026-08-19, and keep the wire form — including `&` for the
`&` in `Default Branch - PR & CI`, which is how Go's `json.Marshal` (and
therefore `gh api`) emits it.
