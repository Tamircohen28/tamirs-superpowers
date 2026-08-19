# `compliant` — the ground truth, already in the desired state

**Represents:** `Tamircohen28/tamirs-superpowers` as captured on 2026-08-19. The
two rulesets are transcribed from `session-files/ground-truth-rulesets.md`; the
surrounding API metadata (`id`, `node_id`, `_links`, timestamps) is what the REST
API wraps them in.

**Covers:**
- **Idempotence.** `plan` against this scenario must report zero changes and
  `apply` must perform zero mutations — `gh_mutations` is `0`. This is the one
  fixture where a spurious write is a *behavioural* bug rather than a diff.
- **Normalized comparison.** The live JSON carries fields the canonical policy
  does not (`id`, `node_id`, `source`, `_links`, `created_at`, `updated_at`,
  `current_user_can_bypass`). Comparison must normalize them away and still find
  the two sides equal.
- **`strict_required_status_checks_policy: false`** — the correct value, so a
  detector that always reports drift fails here.
- **A repository-admin bypass actor** (`RepositoryRole 5`, `always`) on the
  PR & CI ruleset. It is on the real repository, so it is here. Canonical says
  `bypass_actors: []` and it stays that way: bypass actors are **preserved,
  never asserted**, because on a single-admin account that actor is the merge
  path, and "tightening" it to the canonical empty list would revoke the
  author's ability to merge into their own default branch.
- **`required_approving_review_count: 1`**, not the account default of `0`.
  Read together with the bypass actor: collaborators need a review, the owner
  merges through the bypass. It reaches this fixture from
  `repositories["Tamircohen28/tamirs-superpowers"].rules.parameters` in the
  canonical policy, and `tests/test-github-policy.sh` asserts that the two agree
  — if you change one, that assertion tells you to change the other.
- **`~DEFAULT_BRANCH`** on a repo whose default branch is `master`.

**Note on `\u0026`:** the PR & CI ruleset's name is stored as `\u0026`, which is how
`gh api` (Go's `json.Marshal`) emits it. Fixtures reproduce the wire bytes, not
the prettified form.

**Contents:** `rulesets.json` (two summaries), `ruleset-21049068.json` (Safety),
`ruleset-21049069.json` (PR & CI), `repo.json`, `repo-view.json`,
`workflows.json`, `errors.txt` (classic protection 404 — verbatim ground truth).
