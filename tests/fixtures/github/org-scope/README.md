# org-scope

`GET /orgs/{org}/rulesets` answers `403` with GitHub's missing-scope wording.
Distinct from `org-plan-free` in body only — both are 403 — because the remedy
is different: this one is fixed by `gh auth refresh -s admin:org`, the other
cannot be fixed by the user at all.
