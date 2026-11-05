# `labels-compliant` — the canonical set, already applied

**Represents:** a repository where `scripts/github-labels.sh apply` has already
run: every label in `config/github/labels.json` plus one `agent:<platform>` per
key of `core/capabilities/platforms.json`, with the canonical colours and
descriptions.

**Covers:**
- **Idempotence.** `audit` exits 0, `plan` reports nothing to do, and `apply`
  performs zero mutations — `gh_mutations` is `0`. A spurious write here is a
  behavioural bug.
- **Nothing extra.** No label outside the set, so `--prune` has nothing to
  delete and must send no `DELETE`.

**Contents:** `labels.json` (rendered from the canonical set — regenerate it
when `config/github/labels.json` or the registry's platform list changes),
`repo.json` (copied from `compliant`).
