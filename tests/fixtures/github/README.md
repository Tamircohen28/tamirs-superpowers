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
| [`no-permission`](no-permission/README.md) | 403 on rulesets | named degradation, run continues |
| [`rate-limited`](rate-limited/README.md) | 403 + `Retry-After` | throttle ≠ permission failure |
| [`auth-failed`](auth-failed/README.md) | 401 everywhere | hard stop before any repo is touched |
| [`conflict`](conflict/README.md) | 409 on `PUT` | write-side failure, isolate and continue |
| [`unprocessable`](unprocessable/README.md) | 422 on `POST` | structured `.errors`, not just `.message` |
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
`fake_gh_error` appends the same at runtime and is consulted first. Statuses:
`401`, `403`, `403-rate-limit`, `404`, `409`, `422`. Bodies use GitHub's real
envelope (`message` / `documentation_url` / `status`, plus `errors` for 422) and
can be overridden per scenario with `errors/<status>.json`.

## Fidelity

Ruleset payloads are transcribed from `session-files/ground-truth-rulesets.md`,
captured live on 2026-08-19, and keep the wire form — including `&` for the
`&` in `Default Branch - PR & CI`, which is how Go's `json.Marshal` (and
therefore `gh api`) emits it.
