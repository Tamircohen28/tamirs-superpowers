# `insufficient-scope` — authenticated, but the token lacks `administration`

**Represents:** a valid token with the wrong scopes. `gh auth status` succeeds,
repo metadata reads, and only the rulesets endpoint 403s — with a body naming
the missing scope and an `x-oauth-scopes` header that does not contain it.

**Covers:** the `insufficient_scope` class, which `scripts/lib/github-common.sh`
separates from plain `forbidden` by matching `scope` / `oauth` /
`not accessible by` / `fine-grained` in `.message`. The distinction matters to
the operator: a scope failure is fixed by re-authorizing the token, a
`forbidden` by getting admin on the repo. Telling someone to re-auth when they
simply lack admin wastes their afternoon.

**Why `scopes.txt`:** it sets `x-oauth-scopes: gist, read:user`, so the header
disagrees with what the operation needs. The shim's default scope list is the
measured token from `ground-truth-rulesets.md` (`admin:org`, `repo`, …), which
would make this scenario indistinguishable from `no-permission`.

**Contrast with:** [`no-permission`](../no-permission/README.md) (same 403 status,
message says "Resource not accessible by personal access token") and
[`rate-limited`](../rate-limited/README.md) (same status, throttle).
Three fixtures, one status code, three correct responses.

**Contents:** `errors.txt`, `scopes.txt`, `repo.json`, `repo-view.json`,
`workflows.json`.
