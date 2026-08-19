# `_defaults` — last-resort responses shared by every scenario

Consulted only after the active scenario directory (and its `by-repo/` overrides)
have been tried, so any scenario can override any of these by dropping a file of
the same name into its own directory.

| File | Serves | Why it is here and not per-scenario |
|------|--------|--------------------------------------|
| `POST.json` | any unmatched `POST` | Tests of write paths assert on **what was sent** (`gh_last_body`), not on what came back. Without a generic write response every scenario would need a near-identical echo fixture. |
| `PUT.json` | any unmatched `PUT` | Ruleset update, `PUT /repos/{o}/{r}/rulesets/{id}`. |
| `PATCH.json` | any unmatched `PATCH` | Repo settings, `PATCH /repos/{o}/{r}`. |
| `DELETE.json` | any unmatched `DELETE` | Real GitHub answers `204 No Content`; an empty file is not valid JSON and `make validate` runs `jq empty` over every `*.json`, so this is `{}`. |
| `auth-status.txt` | `gh auth status` | The scope list is copied from `session-files/ground-truth-rulesets.md`. |
| `user.json` | `gh api user` | |
| `rate-limit.json` | `gh api rate_limit` | A backoff path needs somewhere to read remaining quota. |
| `repo-view.json` | `gh repo view` | GraphQL field names (`nameWithOwner`, `defaultBranchRef`), which differ from the REST `repo.json`. |
| `repo-list.json` | `gh repo list` | The measured fleet: 19 repos, `main`×15 / `master`×4. |

**GET requests deliberately have no generic fallback.** An unmapped read fails
with exit 78 rather than returning `{}` — a mock that answers everything proves
nothing.
