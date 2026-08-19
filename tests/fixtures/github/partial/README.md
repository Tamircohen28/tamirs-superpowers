# `partial` — Safety present, PR & CI missing

**Represents:** a repo that got half the policy — plausibly one protected by hand
against force-push and deletion but never wired to required checks, or one where
an earlier `apply` failed between the two writes.

**Covers:**
- **Per-ruleset reconciliation.** The result must be one *create* (PR & CI) and
  one *up to date* (Safety) — not "create both" and not "everything is fine".
  Exactly one mutation: `gh_mutations` = 1.
- **Partial-failure resumability.** Re-running after an interrupted apply must
  converge rather than duplicate.

**Contents:** `rulesets.json` (one summary), `ruleset-21049068.json`, `repo.json`,
`repo-view.json`, `workflows.json`, `errors.txt`.
