# org-notfound

`GET /orgs/{org}/rulesets` answers `404`: the organization does not exist, or
this token cannot see it. A degrade to per-repository policy, not a failure.
