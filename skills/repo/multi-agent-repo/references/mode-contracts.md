# Mode contracts — review / plan / dev

## Argument parsing

Parse `$ARGUMENTS` (or `$0` / `$1` when using named `arguments` frontmatter):

| Position | Name | Default | Values |
|----------|------|---------|--------|
| 1 | `mode` | `review` | `review`, `plan`, `dev` |
| 2+ | `target` | cwd git root | repo path, review/plan doc path, or free-text constraints |

```bash
TARGET_ROOT="${2:-$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null || pwd)}"
TARGET_ROOT="$(cd "$TARGET_ROOT" 2>/dev/null && pwd || echo "$TARGET_ROOT")"
DATE="$(date +%Y-%m-%d)"
```

If first token is not a known mode, treat entire `$ARGUMENTS` as free-text constraints and mode = `review`.

## Environment variables (set at mode start)

| Variable | Purpose |
|----------|---------|
| `TARGET_ROOT` | Absolute path to repo under audit |
| `REPO_TYPE` | `app`, `claude-plugin`, or `hybrid` |
| `INVENTORY_JSON` | Output of `inventory-agent-setup.sh` |
| `REVIEW_PATH` | `docs/agent-guidelines/multi-agent-review-<date>.md` |
| `PLAN_PATH` | `docs/agent-guidelines/multi-agent-plan-<date>.md` |

## Review mode

**Purpose:** Read-only gap analysis.

**Inputs:** `TARGET_ROOT`, optional constraint text from user.

**Steps:**
1. Detect `REPO_TYPE` (see `target-layouts.md`).
2. Run `bash "$CLAUDE_SKILL_DIR/scripts/inventory-agent-setup.sh" "$TARGET_ROOT"`.
3. Walk `audit-rubric.md`; classify each gap P1/P2/P3.
4. Write `$TARGET_ROOT/docs/agent-guidelines/multi-agent-review-$DATE.md` from `templates/review-report.md.tmpl`.
5. Print executive summary: repo type, P1/P2/P3 counts, report path.

**Stop condition:** No edits except creating `docs/agent-guidelines/` and the report file.

**Allowed tools:** Bash, Read, Write (report only), Glob, Grep, WebFetch.

## Plan mode

**Purpose:** Phased remediation plan from review findings.

**Inputs:** `TARGET_ROOT`, optional path to existing review doc.

**Steps:**
1. If no review doc in arguments → run review mode inline first.
2. Read review report (latest in `docs/agent-guidelines/multi-agent-review-*.md` if not specified).
3. Group P1/P2 into phases 0–5 (see SKILL.md).
4. Write `$TARGET_ROOT/docs/agent-guidelines/multi-agent-plan-$DATE.md` from `templates/remediation-plan.md.tmpl`.
5. Present plan summary to user.

**Stop condition:** No implementation edits. Plan doc only.

## Dev mode

**Purpose:** Implement multi-agent setup on a feature branch and open a PR.

**Inputs:** `TARGET_ROOT`, optional plan doc path or constraint text.

**Steps:**
1. If no plan doc → run plan mode inline first.
2. Verify git repo + `gh` auth; warn if working tree dirty.
3. Create branch `feat/multi-agent-setup` (append slug if branch exists).
4. Implement phases 0–5 per plan (`references/platform-setup.md` for phases 0–1).
5. Commit in logical chunks; run validation commands from plan.
6. Push + `gh pr create` using `templates/pr-body.md.tmpl`.
7. Re-run inventory; confirm P1 gaps closed.

**Stop condition:** PR URL printed. **Never merge.**

**Hard stops (blocked state):**
- Not a git repository
- `gh` not authenticated
- User forbids writes
- Target is not user's repo and no write access

## Phase order (plan + dev)

| Phase | Focus | Implementation |
|-------|-------|----------------|
| 0 | Canonical `AGENTS.md` | `references/platform-setup.md` |
| 1 | Thin adapters (`CLAUDE.md`, `000-project.mdc`) | `references/platform-setup.md` |
| 2 | Scoped `.mdc` rules + `docs/agent-guidelines/` | local |
| 3 | Portable skills + symlinks | local |
| 4 | Drift checker + `agent:check` + CI | local scripts |
| 5 | Validate | `make validate` / `pnpm agent:check` / inventory script |

## Output paths (always under target repo)

```
docs/agent-guidelines/multi-agent-review-<YYYY-MM-DD>.md
docs/agent-guidelines/multi-agent-plan-<YYYY-MM-DD>.md
```

Do not write session artifacts to tamirs-superpowers `.dev-files/` when auditing an external repo.
