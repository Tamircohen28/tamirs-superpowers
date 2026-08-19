# `forbidden` — a 403 that is none of the other 403s

**Represents:** a correctly scoped, correctly authenticated token on a repo the
user does not administer. GitHub says `Must have admin rights to Repository.`

**Covers: the residual `forbidden` class.** `github_api` reaches it only after
rate-limit wording, a zeroed quota, org-policy wording and scope wording have
all failed to match — so it is the class no other fixture can produce. Every
other 403 fixture here matches one of those earlier branches:

| Fixture | Message contains | Class |
|---------|------------------|-------|
| `rate-limited` | `rate limit exceeded` | `rate_limited` |
| `org-policy` | `organization has enabled` | `org_policy` |
| `insufficient-scope` | `scope` | `insufficient_scope` |
| `no-permission` | `not accessible by` | `insufficient_scope` |
| **`forbidden`** | none of the above | **`forbidden`** |

**Why it needed its own fixture:** the shim's default 403 body is
`Resource not accessible by personal access token`, which matches
`*"not accessible by"*` and classifies as `insufficient_scope`. Asserting
`forbidden` against the default body would have passed for the wrong reason and
left the residual branch untested. The override lives in `errors/403.json` —
the per-scenario body hook.

**Operator consequence:** `insufficient_scope` says "re-authorize your token",
`forbidden` says "you are not an admin of this repo". Wrong class, wasted
afternoon.

**Contents:** `errors.txt`, `errors/403.json` (the body override), `repo.json`,
`repo-view.json`.
