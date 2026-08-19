# `custom-ruleset` — the canonical two plus a user's own ruleset

**Represents:** a compliant repo that also carries `Protect release tags`
(id `40000001`, `target: tag`) — something the user created and the policy knows
nothing about.

**Covers: the policy must never delete what it does not own.** Reconciliation of
a *set* invites "delete everything not in the desired state", which here would
silently destroy the user's tag protection. The policy owns two rulesets by name
and must leave every other ruleset untouched.

**Expected:** zero changes and `gh_mutations` = 0. In particular assert
`gh_calls 'DELETE'` is `0` and that no request path mentions `40000001` beyond
the read.

**Secondary coverage:** the extra ruleset has `target: tag`, so code that matches
on target rather than on name has to get this right too.

**Contents:** `rulesets.json` (three summaries), the two canonical details,
`ruleset-40000001.json`, `repo.json`, `repo-view.json`, `workflows.json`,
`errors.txt`.
