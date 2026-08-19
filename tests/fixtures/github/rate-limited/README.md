# `rate-limited` — 403 with `Retry-After`

**Represents:** secondary rate limiting hit partway through a fleet run. The
status is 403, not 429 — GitHub's abuse/secondary limits answer 403 with a
rate-limit `message`, which is why "403 means permission" is the wrong reflex.

**Covers:**
- **Telling the two 403s apart.** The envelope here says
  `API rate limit exceeded for user ID 12345.`; `no-permission` says
  `Resource not accessible by personal access token`. Code that branches on
  status alone treats a transient throttle as a permanent permission failure.
- **`Retry-After` is available.** The shim emits `retry-after: 60` and
  `x-ratelimit-remaining: 0` on stderr, and in the header block when `-i` is
  passed, so a backoff path has something real to read.
- **`rate_limit` is queryable.** `rate-limit.json` reports `remaining: 0`, which
  is the pre-flight check a bulk run should make.

**Contents:** `errors.txt` (rate-limit token on both rulesets paths),
`rate-limit.json` (exhausted quota), `repo.json`, `repo-view.json`.
