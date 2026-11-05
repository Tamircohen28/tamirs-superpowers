# `inventory-drift` — compliant rulesets, drifted labels, for the inventory

**Represents:** `Tamircohen28/tamirs-superpowers` — the slug the `compliant`
rulesets were transcribed from, so against the canonical policy's per-repository
override they read as already compliant — with the two rulesets (copied from
`compliant`), GitHub's nine default labels plus a
drifted `agent:any` and one hand-made extra (copied from `labels-missing`),
and check-run/status fixtures so the policy audit's required-checks block can
read. The Actions-concurrency finding is NOT in this directory: the test that
uses this scenario plants a cancellable workflow with no concurrency block in
its hermetic checkout, which `github-policy.sh` reads as "this checkout".

**Covers:** `tests/test-standards-inventory-online.sh` — `standards-inventory.sh`
must consume `github-policy.sh audit --json` and `github-labels.sh audit --json`
when they exit **3** (drift is a successful read and IS the finding), score
S4-14 and S3-05 from them, and stay unchecked on any other exit code or on a
`failed` bucket.

**Contents:** `repo.json` / `repo-view.json` (from `compliant`), `rulesets.json`,
`ruleset-21049068.json`, `ruleset-21049069.json`, `workflows.json`,
`check-runs.json`, `commit-status.json`, `errors.txt` (classic protection
404), `labels.json`, `POST-labels.json`.
