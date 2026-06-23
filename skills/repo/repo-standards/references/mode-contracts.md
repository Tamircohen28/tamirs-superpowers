# Mode contracts — review / plan / polish

## Argument parsing

| Position | Name | Default | Values |
|----------|------|---------|--------|
| 1 | `mode` | `review` | `review`, `plan`, `polish` |
| 2+ | `target` | cwd git root | repo path, review/plan doc path, or constraints |

Output from `parse-mode-args.sh`: `{ mode, target, doc_path, constraints }`.

## Output paths (under target repo)

```
docs/engineering/repo-standards-review-<YYYY-MM-DD>.md
docs/engineering/repo-standards-plan-<YYYY-MM-DD>.md
```

## review mode

**Purpose:** Read-only unified standards + multi-agent gap report.

**Stop:** Only creates `docs/engineering/repo-standards-review-*.md`.

## plan mode

**Purpose:** Phased remediation from review findings.

**Stop:** Only creates `docs/engineering/repo-standards-plan-*.md` unless mode is `polish`.

## polish mode

**Purpose:** Implement plan on `feat/repo-standards-setup`, open PR.

**Stop:** PR URL printed. Never merge. Never `gh repo create`.

**Hard stops:** Not a git repo; `gh` not authenticated; user forbids writes.

## Phase order (plan + polish)

| Phase | Focus |
|-------|-------|
| 0 | Employer IP remediation |
| 1 | README + LICENSE + root files |
| 2 | docs/ tree |
| 3 | .github/ CI + templates |
| 4 | Branch protection + CODEOWNERS |
| 5 | Multi-agent (`Skill("multi-agent-repo")`) |
| 6 | `docs-review` + `changelog-review` (plugin) |
| 7 | Re-run review; P1 = 0 |
