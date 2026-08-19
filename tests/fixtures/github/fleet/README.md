# `fleet` — three repos in three different states, from one scenario

**Represents:** a bulk run. `gh repo list` returns the measured fleet (19 repos,
`main`×15 / `master`×4, served from `_defaults/repo-list.json`), and three of
them answer differently:

| Repo | Default branch | State |
|------|----------------|-------|
| `Tamircohen28/tamirs-superpowers` | `master` | compliant |
| `Tamircohen28/job-tracker-web` | `main` | no rulesets |
| `Tamircohen28/whoRuz` | `main` | drifted (`strict…: true`) |

**How:** `by-repo/<owner>__<repo>/` overrides win over the scenario root, so one
directory serves per-repo state without 19 scenario directories. Any repo not
listed under `by-repo/` has no `rulesets.json` anywhere and the mock exits 78 —
which is the desired behaviour: a fleet test must enumerate the repos it means to
touch rather than sweeping whatever `repo list` returned.

**Covers:**
- **Per-repo failure isolation and a summary.** `recon-github-policy.md` §5.4:
  there is no multi-repo iteration pattern anywhere in the repo today.
- **Mixed outcomes in one run** — up-to-date, create, update — which is what the
  `--json` `summary` block (`changes` / `up_to_date` / `skipped`) has to count.
- **Both default-branch spellings in a single run.**

**Contents:** `by-repo/` with three repos, `repo-view.json`, `errors.txt`.
Combine with `fake_gh_error` at runtime to make one repo of the three fail
without disturbing the other two.
