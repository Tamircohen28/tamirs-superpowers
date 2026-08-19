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
- **`~DEFAULT_BRANCH`** on a repo whose default branch is `master`.

**Note on `\u0026`:** the PR & CI ruleset's name is stored as `\u0026`, which is how
`gh api` (Go's `json.Marshal`) emits it. Fixtures reproduce the wire bytes, not
the prettified form.

**Contents:** `rulesets.json` (two summaries), `ruleset-21049068.json` (Safety),
`ruleset-21049069.json` (PR & CI), `repo.json`, `repo-view.json`,
`workflows.json`, `errors.txt` (classic protection 404 — verbatim ground truth).
