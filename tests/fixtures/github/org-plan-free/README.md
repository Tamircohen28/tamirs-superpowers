# org-plan-free

`GET /orgs/{org}/rulesets` answers `403` with the body GitHub actually returns
for an organization on the Free plan:

    Upgrade to GitHub Team to enable this feature.

Measured against the real `SentinelAIOrg` (plan `free`, 12 repositories) on
2026-08-19.

The body is what makes this scenario, not the status code. `github-common.sh`
classifies this 403 as `forbidden`, whose explanation sends the reader to fix
repository admin permissions they already have — for a wall that is billing.
`github_org_probe` reads the wording first and degrades to per-repository
policy with the honest reason. The fixture exists so that stays true.
