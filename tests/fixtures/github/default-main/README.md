# `default-main` — repository whose default branch is `main`

**Represents:** the majority case in the measured fleet — 15 of 19 repos
(`ground-truth-rulesets.md`, "Repos and their default branches").

**Covers:** that the policy targets the default branch **dynamically**. Nothing
in a request body may contain the literal string `main`; the canonical rulesets
express the target as `~DEFAULT_BRANCH` in `conditions.ref_name.include`, which
is precisely what lets one policy serve a fleet with two spellings.

**Contents:** `repo.json` (`default_branch: main`), `repo-view.json`, empty
`rulesets.json`, `workflows.json`, and an `errors.txt` making classic
`branches/*/protection` return 404 — the real behaviour on a rulesets-only repo.

**Pair with:** [`default-master`](../default-master/README.md),
[`default-trunk`](../default-trunk/README.md).
