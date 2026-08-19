# `classic-protection` — legacy branch protection, no rulesets

**Represents:** a repo governed the old way: `GET .../branches/main/protection`
returns a payload, `GET .../rulesets` returns `[]`.

**Why a fixture is the only way:** `ground-truth-rulesets.md` line 13 records
that this repo has **no** classic protection — `GET .../branches/master/protection`
is a 404 — so "the migration path (classic → rulesets) must be tested against a
repo that has classic rules", and no such repo is reachable from this test suite.
Without this directory the migration path is untested code.

**Covers:**
- **Reading the right endpoint first.** The recon records a live defect: today
  `ensure-branch-protection.sh` and `standards-inventory.sh` consult only classic
  protection, so S4-02/03/06 score as gaps on a repo that rulesets protect
  correctly. The new abstraction must read `rulesets` first and treat classic as
  legacy — this fixture is the mirror image that keeps the fix honest in the
  other direction.
- **Migration reporting.** `plan` must say the repo is governed by classic
  protection and name what changes, rather than reporting "unprotected".
- **The settings actually conflict.** `strict: true` (forbidden),
  `required_approving_review_count: 1` (the live policy uses 0 with
  `required_review_thread_resolution: true`), and `required_linear_history`
  disabled. A migration that silently carries these across is wrong.

**Contents:** `protection.json` (classic payload), `rulesets.json` (`[]`),
`repo.json`, `repo-view.json`, `workflows.json`. Note the absence of an
`errors.txt`: here the protection endpoint answers 200.
