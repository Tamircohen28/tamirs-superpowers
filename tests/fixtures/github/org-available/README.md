# org-available

`GET /orgs/{org}/rulesets` answers `200 []`. Measured against the real
`ProductionMasterAI` (plan `team`) on 2026-08-19 — that organization genuinely
has zero organization rulesets today, which is why the canonical pair is
`absent` at org level and the plan is two creates.

This is the scenario where org-level targeting is available and preferred: one
ruleset with `repository_name: ~ALL` instead of one copy per repository.
