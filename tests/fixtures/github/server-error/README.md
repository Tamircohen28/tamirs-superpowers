# `server-error` — GitHub itself is broken (502)

**Represents:** a transient upstream failure. Nothing about the request, the
token or the repo is wrong.

**Covers:** the `network` class, which `github_api` reaches two different ways —
a `5*` status, and *no status line at all*. Both are transient and both should
be retried rather than reported as a policy finding; neither should abort a
19-repo run.

**Testing the second path:** there is no fixture for "no HTTP response", because
the absence of a response is not something a response file can express. Use the
runtime injection instead:

```bash
fake_gh_error ANY 'repos/*/*/rulesets' no-response
```

The shim then prints nothing on stdout and fails, so `GITHUB_LAST_HTTP` comes up
empty and the caller classifies it as `network` — the shape of a DNS failure or
a dropped connection. A shim that always emits a status line cannot produce that
state, which is why it is a token rather than a fixture.

**Contents:** `errors.txt` (502 on the rulesets read), `repo.json`,
`repo-view.json`.
