# `no-rulesets` — an ungoverned repository

**Represents:** a repo with no rulesets and no classic branch protection — the
state of a freshly created repo, and therefore the state `repo-scaffold` hands
to the policy step.

**Covers:** the greenfield `apply` path. `plan` must report both rulesets as
*create*, and `apply` must issue exactly two `POST /repos/{o}/{r}/rulesets` calls
with bodies matching the canonical policy — assert with `gh_mutations` = 2 and
`gh_last_body`.

**Also covers the empty-vs-absent distinction:** `rulesets.json` is `[]`, not a
404. Code that treats "no rulesets" as an error rather than as a state to
reconcile fails here.

**Contents:** `repo.json`, `repo-view.json`, `rulesets.json` (`[]`),
`workflows.json`, `errors.txt` (classic protection 404).
