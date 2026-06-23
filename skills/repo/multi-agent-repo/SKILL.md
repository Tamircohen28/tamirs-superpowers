---
name: multi-agent-repo
description: 'Use when auditing or setting up a repository for multi-agent development across Claude Code, Cursor, and Codex — or making a repo compatible with those assistants. Triggers: multi-agent repo, audit agent setup, AGENTS.md gaps, make compatible with Claude and Cursor, add Codex support, add cursor rules, generate AGENTS.md, agent drift, canonical AGENTS.md, multi-agent-repo review/plan/dev, multi-platform AI support.'
when_to_use: 'User wants to review, plan, or implement multi-agent repo infrastructure — audit gaps for Claude Code + Cursor + Codex, produce a remediation plan, generate platform config files, or implement AGENTS.md + thin adapters + drift checks on a PR branch. Phrases: audit this repo for multi-agent, make this compatible with Claude and Cursor, set up AGENTS.md canonical layout, fix agent drift, multi-agent plan, multi-agent dev.'
argument-hint: '[review|plan|dev] [repo path, review/plan doc path, or free-text constraints — default: review + cwd]'
arguments:
- mode
- target
disable-model-invocation: true
user-invocable: true
allowed-tools:
- Bash
- Read
- Write
- Edit
- Glob
- Grep
- WebFetch
- Agent
disallowed-tools: []
model: claude-sonnet-4-6
effort: high
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  capability: repo
  tags:
  - multi-agent
  - agents-md
  - cursor
  - codex
  - claude-code
  - audit
  - compatibility
  - plugin
  updated-date: '2026-06-23'
---

## Live context
!`git rev-parse --show-toplevel 2>/dev/null && echo "cwd repo: $(basename "$(git rev-parse --show-toplevel)")" || echo "not a git repo"`
!`gh auth status 2>&1 | head -1 || echo "gh: not available"`

# multi-agent-repo

Audit, plan, and implement canonical multi-agent repository setup: **one `AGENTS.md` source of truth**, thin adapters per tool, portable skills, and CI-enforced validation.

## Why this skill exists

Teams running Claude Code, Cursor, and Codex in parallel often maintain three diverging instruction files. Policies drift, context bloats past Codex's 32 KiB limit, and agents ignore duplicated rules. This skill runs **review → plan → dev** so you know what's missing, what order to fix it, and can land the full setup via PR. For quick file generation without a prior audit, use **dev** mode directly.

## Supporting files

| Path | When to read |
|------|----------------|
| `references/mode-contracts.md` | Parse arguments; know stop conditions per mode |
| `references/target-layouts.md` | Classify app vs claude-plugin vs hybrid |
| `references/audit-rubric.md` | Full checklist for review mode |
| `references/gap-scoring.md` | Auto vs manual rubric mapping |
| `references/platform-setup.md` | Fetch docs + generate AGENTS.md and thin adapters (phases 0–1) |
| `references/platform-specs.md` | Schema fallback when live doc fetch fails |
| `scripts/parse-mode-args.sh` | Deterministic mode/target parsing |
| `scripts/inventory-agent-setup.sh` | Deterministic JSON snapshot |
| `scripts/score-inventory-gaps.sh` | Auto-score P1/P2/P3 from inventory |
| `scripts/check-agent-drift.sh` | Verify wrappers reference AGENTS.md |
| `templates/*.md.tmpl` | Report, plan, and PR body shapes |

## Required execution flow

1. Parse args with `parse-mode-args.sh` — do not guess mode from free text alone.
2. Run inventory + gap scoring before any rubric walk (review) or plan grouping.
3. Route to exactly one mode section; plan/dev may chain prior modes in the same turn.
4. Write outputs only to paths in `references/mode-contracts.md`.

## Parse input

```bash
SKILL_DIR="$CLAUDE_SKILL_DIR"
PARSED="$(bash "$SKILL_DIR/scripts/parse-mode-args.sh" $ARGUMENTS)"
MODE="$(echo "$PARSED" | jq -r '.mode')"
TARGET_ROOT="$(echo "$PARSED" | jq -r '.target')"
CONSTRAINTS="$(echo "$PARSED" | jq -r '.constraints')"
DATE="$(date +%Y-%m-%d)"
INVENTORY="$(bash "$SKILL_DIR/scripts/inventory-agent-setup.sh" "$TARGET_ROOT")"
GAPS="$(echo "$INVENTORY" | bash "$SKILL_DIR/scripts/score-inventory-gaps.sh")"
REPO_TYPE="$(echo "$INVENTORY" | jq -r '.repo_type')"
REVIEW_PATH="$TARGET_ROOT/docs/agent-guidelines/multi-agent-review-$DATE.md"
PLAN_PATH="$TARGET_ROOT/docs/agent-guidelines/multi-agent-plan-$DATE.md"
```

Route to the matching section below. **Do not skip review data in plan/dev** when no prior doc path is given.

---

## Mode: review (read-only)

**Goal:** Gap report vs canonical multi-agent layout. **No repo edits** except `docs/agent-guidelines/` + report file.

### Steps

1. Read `references/target-layouts.md` — note expected layout for `$REPO_TYPE`.
2. Run inventory and `score-inventory-gaps.sh` (already captured above). Read `references/gap-scoring.md` for auto vs manual split.
3. Start the report gap table from **auto-scored** `$GAPS` JSON.
4. Walk **manual sections** in `references/audit-rubric.md` (content quality, duplication, command accuracy). Merge new findings; dedupe by rubric ID.
5. `mkdir -p "$TARGET_ROOT/docs/agent-guidelines"`
6. Write `$REVIEW_PATH` using `templates/review-report.md.tmpl`.

### Report structure

ALWAYS include these sections in order:

```markdown
# Multi-agent review — [repo name]
## Executive summary
## Repo classification
## Gap summary (P1 / P2 / P3 counts)
## Findings table
| ID | Severity | Evidence | Remediation | Phase |
## Recommended next step
## Inventory appendix (JSON)
```

7. Print executive summary: repo type, P1/P2/P3 counts, path to report.

**Stop.** Do not edit AGENTS.md, CLAUDE.md, or rules in review mode.

---

## Mode: plan

**Goal:** Phased remediation plan from review findings.

### Steps

1. If user did not pass a review doc path, run **review mode** first in the same turn.
2. Read the review report (user path or latest `multi-agent-review-*.md` under `docs/agent-guidelines/`).
3. Group P1/P2 gaps into phases:

| Phase | Focus |
|-------|-------|
| 0 | Canonical `AGENTS.md` |
| 1 | Thin adapters: `CLAUDE.md` (`@AGENTS.md`), `.cursor/rules/000-project.mdc` |
| 2 | Scoped `.mdc` rules + `docs/agent-guidelines/{testing,security,style}.md` |
| 3 | Portable skills (`.agents/skills/` or plugin `skills/` per repo type) |
| 4 | `scripts/check-agent-drift.sh` + `agent:check` in Makefile/package.json + CI |
| 5 | Run validation; re-inventory; P1 must be 0 |

4. For each phase list: actions, files, implementation notes (`references/platform-setup.md` for phases 0–1), validation command, risk.
5. Write `$PLAN_PATH` from `templates/remediation-plan.md.tmpl`.
6. Present plan summary to user.

**Stop** unless mode is `dev`.

---

## Mode: dev

**Goal:** Implement plan on feature branch; open PR. **Never merge.**

### Preconditions

- Git repo at `$TARGET_ROOT`
- `gh` authenticated (`gh auth status`)
- Warn if working tree dirty; do not discard user changes

### Steps

1. If no plan doc in arguments, run **plan mode** first.
2. Read plan doc (user path or `$PLAN_PATH`).
3. Create branch:

```bash
cd "$TARGET_ROOT"
BRANCH="feat/multi-agent-setup"
git checkout -b "$BRANCH" 2>/dev/null || git checkout -b "feat/multi-agent-setup-$(date +%s)"
```

4. Implement phases in order:

**Phase 0–1 — platform files**

Follow `references/platform-setup.md` for live doc fetch, AGENTS.md, CLAUDE.md (`@AGENTS.md`), and `000-project.mdc`. Respect `$CONSTRAINTS`.

**Phase 2–3 — local**

- Add scoped `.mdc` rules (globs for src/tests/db per stack)
- Create `docs/agent-guidelines/` stubs linked from AGENTS.md
- For **app** repos: ensure `.agents/skills/` or document bridge
- For **claude-plugin** repos: keep `skills/` per `plugin.json` — do not force `.agents/skills/`

**Phase 4 — enforcement**

- Copy or adapt `scripts/check-agent-drift.sh` from this skill into target `scripts/`
- For Node repos: copy `templates/check-no-agent-drift.mjs.tmpl` → `scripts/check-no-agent-drift.mjs`
- Wire `agent:rules` or extend `validate` in Makefile / `package.json` scripts
- Add CI step if `.github/workflows/` exists (mirror AGENTS.md validation command)

**Phase 5 — validate**

```bash
bash scripts/check-agent-drift.sh
# plus stack-specific command from AGENTS.md
bash "$SKILL_DIR/scripts/inventory-agent-setup.sh" "$TARGET_ROOT"
```

5. Commit in logical chunks (`feat(agents): …`, `chore(ci): …`).
6. Push and open PR:

```bash
git push -u origin HEAD
gh pr create --title "feat(agents): multi-agent repo setup" --body "$(cat <<'EOF'
<fill from templates/pr-body.md.tmpl>
EOF
)"
```

7. Print PR URL and re-inventory summary.

**Stop at PR.** User or `pr-dev` merges after approval.

---

## Anti-patterns (do not do these)

| Anti-pattern | Why it fails |
|--------------|--------------|
| Editing AGENTS.md in review mode | Review is read-only except the report path |
| Skipping review before dev on unfamiliar repos | Misses P1 gaps; run review or plan first unless user explicitly wants quick dev |
| Duplicating AGENTS.md into CLAUDE.md or `.mdc` | Drift on next policy change; violates thin-adapter model |
| More than 2 `alwaysApply: true` Cursor rules | Context bloat; Codex/Cursor ignore overflow |
| Skipping `score-inventory-gaps.sh` | Manual rubric walk alone misses deterministic P1s inconsistently |
| Merging the PR from this skill | User or `pr-dev` owns merge after review |

---

## Hard rules

- **AGENTS.md is canonical** — CLAUDE.md and `.mdc` files point to it; never duplicate full policy text.
- **≤ 2** Cursor rules with `alwaysApply: true`.
- **AGENTS.md ≤ 32 KiB** — no Claude-only syntax in AGENTS.md.
- **Plugin repos** — respect existing `skills/` layout; do not migrate to `.agents/skills/` without explicit user request.
- **Windows** — prefer `@AGENTS.md` in CLAUDE.md over symlinks.
- **Never force-push** or push to branches other than the feature branch.
- **Never merge** the PR from this skill.

## Relationship to other skills

| Skill | When to use instead |
|-------|---------------------|
| `repo-review` | General repo hygiene (misplaced files, stale refs) — not multi-agent layout |
| `plan-dev` | Break arbitrary features into GitHub issues |
| `start-dev` | Implement a feature issue, not agent infrastructure |
| `pr-dev` | Drive the PR to merge after dev mode opens it |

## Error handling

| Situation | Action |
|-----------|--------|
| Target not a directory | Ask for valid path; stop |
| Not a git repo in dev mode | Stop; suggest review/plan only |
| `gh` not authenticated | Stop; print `gh auth login` instructions |
| Platform doc fetch partial failure | Log platform; use `references/platform-specs.md` fallback; continue |
| Inventory shows P1 after dev | List remaining gaps; do not claim complete |

## Example invocations

```text
/multi-agent-repo
/multi-agent-repo review ../other-repo
/multi-agent-repo plan
/multi-agent-repo plan docs/agent-guidelines/multi-agent-review-2026-06-23.md
/multi-agent-repo dev
/multi-agent-repo dev . -- prioritize CI and drift checker only
```
