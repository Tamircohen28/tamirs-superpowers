# `no-permission` — 403 on the rulesets endpoint

**Represents:** a token that can read the repository but not its rulesets — a
fine-grained PAT without `administration: read`, or a repo the user does not
admin. `GET /repos/{o}/{r}` still succeeds, which is what makes this failure
mode confusing in the wild: the tool looks connected right up to the point it
matters.

**Covers:**
- **Named, non-fatal degradation.** `recon-github-policy.md` §5.5 records that
  nothing in the repo handles GitHub 403/429 today. Under bulk operation across
  19 repos, one 403 must mark that repo `blocked` with a reason and let the run
  continue — the `blocked` field convention borrowed from `capture-config.sh`.
- **The error body is the message.** GitHub's envelope carries `message` and
  `documentation_url`; the tool should surface them rather than printing an exit
  code.
- **`plan` must not claim compliance it could not verify.** A 403 read is not
  "no rulesets found".

**Contents:** `errors.txt` mapping both rulesets paths to 403, plus `repo.json`,
`repo-view.json` and `workflows.json` so the surrounding reads still succeed and
the 403 is isolated to the endpoint under test.
