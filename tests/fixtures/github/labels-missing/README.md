# `labels-missing` — a repository that still has only what GitHub gave it

**Represents:** a repository created on github.com and never touched by
`scripts/github-labels.sh`: GitHub's nine default labels, the `agent:any` label
that `switch-dev` created by hand with an older description, and one label a
person made (`stale-experiment`) that the canonical set does not name.

**Covers:**
- **Create.** Every canonical label that is not a GitHub default is absent, and
  so is every `agent:<platform>` label — `plan` lists each one as a create, and
  `apply` sends one `POST repos/{o}/{r}/labels` per label with the rendered
  `name`, `color` and `description`.
- **Update.** `agent:any` exists with a drifted description; `apply` sends one
  `PATCH repos/{o}/{r}/labels/agent%3Aany` with the canonical values and no
  `new_name`, because the name already matches.
- **Case-insensitive colour.** `invalid` is stored as `E4E669`; the set says
  `e4e669`. That is NOT drift.
- **Extras are reported, never deleted** unless `--prune` is typed — the one
  `DELETE` the suite ever expects is `stale-experiment` under `--prune`.
- **Platform labels come from the registry.** The expected `agent:<platform>`
  creates are derived in the test from `core/capabilities/platforms.json`, not
  from a list in the test.

**Contents:** `labels.json` (eleven labels as `GET repos/{o}/{r}/labels` returns
them), `repo.json` (copied from `compliant`).
