# `org-policy` — blocked by an organization restriction, not by the token

**Represents:** an org with OAuth App access restrictions (or SAML/SSO, or an IP
allow list) refusing the request. The token is valid and correctly scoped; the
organization is the thing saying no.

**Covers:** the `org_policy` class, matched on `saml` / `sso` /
`organization has enabled` / `enterprise` / `ip allow` / `policy` in `.message`.
It is the one 403 the operator cannot fix alone — it needs an org admin — so
reporting it as `forbidden` or `insufficient_scope` sends them down a road that
dead-ends.

**Ordering matters:** `github_api` checks rate-limit wording first, then
`org_policy`, then scope wording. This fixture's message contains
`organization has enabled` and no rate-limit words, so it must land on
`org_policy`. A classifier that tested scope wording first would misfile it,
since the message also contains "authorization credentials".

**Contents:** `errors.txt`, `repo.json`, `repo-view.json`.
