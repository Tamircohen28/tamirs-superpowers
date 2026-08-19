# `classic-overlap` — BOTH mechanisms in force on the same branch

**Represents:** the state GitHub's "Convert to ruleset" button leaves behind.
`GET .../rulesets` returns the two canonical rulesets AND
`GET .../branches/main/protection` returns a classic payload. Both apply at
once and GitHub takes the stricter of the two.

**Why it is separate from `classic-protection`:** that fixture is a repository
governed by classic protection *only* (`rulesets` is `[]`) — the migration-from-
nothing case. This one is the more dangerous case, because the rulesets look
right. An audit that reads only the rulesets reports COMPLIANT while the branch
is actually gated by a classic rule nobody has opened in a year.

**The finding this fixture exists for:** `protection.json` carries
`required_status_checks.strict: true`. The canonical policy sets
`strict_required_status_checks_policy: false` deliberately and at length
(`config/github/repository-policy.json`, `required_checks._comment`). Because
GitHub aggregates the two mechanisms, the leftover classic rule silently
reinstates "branch must be up to date" — and it does so invisibly, since the
ruleset everybody reads still says `false`.

**Contents:** `rulesets.json` + `ruleset-21049068.json` + `ruleset-21049069.json`
(from `compliant`), `protection.json` (from `classic-protection`), `repo.json`,
`repo-view.json`, `workflows.json`. No `errors.txt`: here the protection
endpoint answers 200.
