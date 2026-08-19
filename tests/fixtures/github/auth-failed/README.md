# `auth-failed` — 401 Bad credentials on everything

**Represents:** an expired, revoked or absent token. `gh auth status` fails and
so does every API call, including the innocuous ones.

**Covers:** the hard-stop path. `rules/dev/gh-cli-preference.md:25-45` allows
`gh` degradation in general, but records the exception that applies here: when
the GitHub action *is* the request, a missing or unusable `gh` is a hard
reportable failure, not a skip. So a 401 must abort with a named cause and a
non-zero exit — never "0 repos processed, all good".

**Note:** the glob is `*`, so `gh auth status` (logged under the pseudo-path
`gh:auth/status`) fails too. That is the point: the pre-flight check must be the
thing that catches this, before any repo is touched.

**Contents:** `errors.txt` only. Deliberately no response fixtures — nothing in
this scenario should ever get far enough to need one, and if something does, the
mock's exit 78 says so loudly.
