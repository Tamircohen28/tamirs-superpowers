# `no-actions` — a repository with no workflows

**Represents:** a repo where `GET /repos/{o}/{r}/actions/workflows` returns
`total_count: 0` — a docs repo, a fresh scaffold before CI lands, or a project
that never adopted Actions.

**Covers: required status checks cannot be required when nothing can report
them.** `ground-truth-rulesets.md`: "Required checks are repo-specific: 9
contexts here, out of 16 CI jobs. **Do not globalise them.**" Applying the nine
canonical contexts here would create a ruleset no PR can ever satisfy — every
merge blocked forever on checks that will never run. This is the lockout failure
mode in its purest form.

**Expected:** the Safety ruleset applies unchanged; the PR & CI ruleset either
omits `required_status_checks` or the run stops and says why. Whichever the
architecture chooses, this fixture is where that choice is pinned.

**Secondary coverage:** `repo-scaffold` runs the policy step right after the
first push, which is exactly this state.

**Contents:** `workflows.json` (empty), `rulesets.json` (`[]`), `repo.json`,
`repo-view.json`, `errors.txt`.
