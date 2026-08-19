# `org-conflict` — an organization ruleset imposing something stricter

**Represents:** a repo in `ProductionMasterAI` where the org has published
`Org baseline - reviews` (`source_type: Organization`, `repository_name: ~ALL`).
The repo's own two rulesets are canonical and compliant.

**Covers:**
- **Org rulesets appear in the repository listing.** `GET /repos/{o}/{r}/rulesets`
  returns org-sourced entries alongside repo-sourced ones, distinguished only by
  `source_type`. Code that assumes every listed ruleset is repo-owned will try to
  `PUT` an org ruleset it cannot write and get a 403 in production.
- **Rules compose; the strictest wins.** The org requires 2 approving reviews,
  code-owner review, squash-only merges, and
  `strict_required_status_checks_policy: true` — which contradicts the canonical
  policy's 0 approvals and non-strict checks. The repo policy cannot loosen this,
  so `plan` must report the effective state honestly (a conflict/note) rather
  than reporting compliance or attempting a write that will fail.
- **The lockout risk.** `recon-github-policy.md` §6: a policy tool must not
  reintroduce a required-approval count that blocks the solo-contributor flow.
  Here the block comes from above and must be *reported*, not fought.

**Contents:** `rulesets.json` (two repo + one org summary), the two canonical
details, `ruleset-30000001.json` (as served from the repo path),
`org-ruleset-30000001.json` and `org-rulesets.json` (as served from
`GET /orgs/{org}/rulesets`), `repo.json`, `repo-view.json`, `workflows.json`,
`errors.txt`.
