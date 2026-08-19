# `drifted` — both rulesets present, `strict_required_status_checks_policy: true`

**Represents:** the single most important non-compliance to detect. Everything
else in both rulesets matches `compliant` byte for byte; one boolean is flipped.

**Kept in lockstep with `compliant`.** This fixture is defined as `compliant`
plus one flipped boolean, and `tests/test-fake-gh.sh` asserts exactly that. Any
edit to `compliant/ruleset-21049069.json` — the bypass actor and
`required_approving_review_count: 1` arrived that way — must be mirrored here.

**Covers:** the architectural constraint. `strict_required_status_checks_policy`
is GitHub's "require branches to be up to date before merging" toggle. With it
on, every merge invalidates every other open PR's checks — which is exactly what
the one-objective/one-PR architecture forbids, and why the live ruleset has it
**off** (`ground-truth-rulesets.md`, key findings).

**Why this fixture is load-bearing:** it is a one-field diff nested three levels
deep (`rules[] → parameters → strict_required_status_checks_policy`). A detector
that compares only ruleset *names*, only rule *types*, or only the top level
reports this repo as compliant. This session has already been bitten three times
by checks that silently passed — a `jq //` swallowing `false`, a `$(case …)`
capturing shell source, a detector matching the wrong quoting. Note that the
value here is a JSON `false` in `compliant` and `true` here: `jq '.x // "d"'`
returns `"d"` for both `false` and absent, so any comparison written that way
passes both fixtures and is wrong.

**Expected:** one *update* (PR & CI), one *up to date* (Safety); exactly one
mutation, a `PUT /repos/{o}/{r}/rulesets/21049069`.

**Contents:** as `compliant`, with `ruleset-21049069.json` differing in that one
boolean.
