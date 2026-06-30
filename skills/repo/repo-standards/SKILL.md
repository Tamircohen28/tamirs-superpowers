---
name: repo-standards
description: 'Use when auditing or polishing a repository to Tamir Cohen standards — README badges (author, version, AI targets), Makefile install/update/uninstall, docs tree, CI/CD, changelog + versioning policy, branch protection, employer IP scan, repo hygiene, and multi-agent setup. Triggers: repo standards, polish this repo, prepare for GitHub, world-class repo, publish-ready, scan employer IP, fix repo hygiene, repo-standards review/plan/polish, standards audit.'
when_to_use: 'User wants to review, plan, or implement full repo standards — README and docs layout, GitHub CI/CD, branch rules, IP-clean publish prep, and multi-agent support via multi-agent-repo. Phrases: polish this repo, repo standards review, make publish-ready, audit repo hygiene, standards plan, standards polish.'
argument-hint: '[review|plan|polish] [repo path, review/plan doc path, or free-text constraints — default: review + cwd]'
arguments:
- mode
- target
disable-model-invocation: false
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
- Skill
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
  - repo-standards
  - polish
  - github
  - docs
  - ci-cd
  - ip-scan
  - multi-agent
  updated-date: '2026-06-23'
---

## Live context
!`git rev-parse --show-toplevel 2>/dev/null && echo "cwd repo: $(basename "$(git rev-parse --show-toplevel)")" || echo "not a git repo"`
!`gh auth status 2>&1 | head -1 || echo "gh: not available"`

# repo-standards

Audit, plan, and implement **Tamir Cohen repo standards**: README + docs tree, GitHub CI/CD, branch governance, employer-IP clean, repo hygiene, and **multi-agent** support (via `multi-agent-repo`). Auto-detects `app-gold` vs `plugin-gold` (agent-kit repos).

**User guide (agent-kit):** [docs/user/agent-kit.md](../../../docs/user/agent-kit.md)

## Why this skill exists

Publishing or maintaining a repo without a unified checklist leaks employer IP, ships thin READMEs, and leaves agents without `AGENTS.md`. This skill runs **review → plan → polish** so gaps are visible, phased, and land on a PR branch — without auto-creating remotes or merging.

## Supporting files

| Path | When to read |
|------|----------------|
| `../_contract/README.md` | Contract change workflow; canonical paths |
| `../_contract/standards-contract.json` | Machine contract (`app-gold` profile) |
| `../_contract/templates/INDEX.md` | Polish phase 1–4 templates |
| `references/mode-contracts.md` | Parse args; stop conditions |
| `references/standards-rubric.md` | Pointer → `_contract/standards-rubric.md` |
| `references/polish-phases.md` | Polish implementation order |
| `references/delegation.md` | Skill() prompts for child skills |
| `references/plugin-review.md` | Agent-kit / plugin-gold manual review axes |
| `../_contract/references/readme-badges.md` | Badge rows, Makefile lifecycle, multi-target README |
| `../_contract/references/versioning-policy.md` | Semver, tagging, changelog enforcement |
| `scripts/parse-mode-args.sh` | Mode/target/doc_path parsing |
| `scripts/standards-inventory.sh` | Re-export → `_contract/scripts/` |
| `scripts/score-contract-gaps.sh` | Merged standards + multi-agent gaps |
| `scripts/assert-contract.sh` | Polish exit gate (app-gold P1/P2/P3 = 0) |
| `scripts/ip-scan.sh` | Employer IP scan |
| `templates/*.md.tmpl` | Report, plan, PR body |

## Required execution flow

1. Parse with `parse-mode-args.sh`.
2. Run inventory + gap scoring before rubric walk (review) or plan grouping.
3. Route to one mode; plan/polish may chain review in the same turn.
4. Write reports only to paths in `mode-contracts.md`.

## Parse input

```bash
SKILL_DIR="$CLAUDE_SKILL_DIR"
CONTRACT_ROOT="$(cd "$SKILL_DIR/../_contract" && pwd)"
PARSED="$(bash "$SKILL_DIR/scripts/parse-mode-args.sh" $ARGUMENTS)"
MODE="$(echo "$PARSED" | jq -r '.mode')"
TARGET_ROOT="$(echo "$PARSED" | jq -r '.target')"
DOC_PATH="$(echo "$PARSED" | jq -r '.doc_path // empty')"
CONSTRAINTS="$(echo "$PARSED" | jq -r '.constraints')"
DATE="$(date +%Y-%m-%d)"
CONTRACT_PROFILE="$(bash "$CONTRACT_ROOT/scripts/detect-contract-profile.sh" "$TARGET_ROOT")"
INVENTORY="$(bash "$SKILL_DIR/scripts/standards-inventory.sh" "$TARGET_ROOT")"
GAPS="$(bash "$SKILL_DIR/scripts/score-contract-gaps.sh" "$TARGET_ROOT" "$CONTRACT_PROFILE")"
IP_SCAN="$(bash "$SKILL_DIR/scripts/ip-scan.sh" "$TARGET_ROOT" 2>&1 || true)"
REVIEW_PATH="$TARGET_ROOT/docs/engineering/repo-standards-review-$DATE.md"
PLAN_PATH="$TARGET_ROOT/docs/engineering/repo-standards-plan-$DATE.md"
```

---

## Mode: review (read-only)

**Goal:** Unified gap report (standards S1–S7 + multi-agent S8). **No repo edits** except the report file.

### Steps

1. Read `references/standards-rubric.md`. If `$CONTRACT_PROFILE` is `plugin-gold`, also read `references/plugin-review.md`.
2. Start findings from `$GAPS` JSON (profile: `$CONTRACT_PROFILE`); walk rubric for qualitative gaps (README prose, doc content).
3. Include `$IP_SCAN` summary; flag S7-01 P1 if not CLEAN.
4. `cd "$TARGET_ROOT"` then `Skill("multi-agent-repo")` using `references/delegation.md` review prompt. Append child summary to report — do not duplicate full child report.
5. Read-only docs pass: summarize README + `docs/**` issues without calling `Skill("docs-review")` (it mutates files).
6. `mkdir -p "$TARGET_ROOT/docs/engineering"`
7. Write `$REVIEW_PATH` from `templates/review-report.md.tmpl`.

### Report structure

```markdown
# Repo standards review — [repo name]
## Executive summary
## Severity summary
## Standards gaps (S1–S7 + PK* if plugin-gold)
## Plugin / agent-kit appendix (if plugin-gold)
## Employer IP scan
## Multi-agent appendix
## Docs read-only notes
## Inventory appendix (JSON)
## Next steps
```

**Stop.** No implementation edits in review mode.

---

## Mode: plan

**Goal:** Phased remediation from review findings.

### Steps

1. If no review doc, run **review mode** first.
2. Read review (`$DOC_PATH`, user path, or latest `repo-standards-review-*.md`).
3. Group P1/P2 into phases 0–7 per `references/polish-phases.md`.
4. Note `Skill("multi-agent-repo")` for phase 5 (add `--constraints plugin` when `$CONTRACT_PROFILE=plugin-gold`) and `docs-review` / `changelog-review` for phase 6.
5. Write `$PLAN_PATH` from `templates/remediation-plan.md.tmpl`.
6. Present plan summary.

**Stop** unless mode is `polish`.

---

## Mode: polish

**Goal:** Implement plan on `feat/repo-standards-setup`; open PR. **Never merge. Never `gh repo create`.**

### Preconditions

- Git repo at `$TARGET_ROOT`
- `gh` authenticated
- Warn if dirty working tree

### Steps

1. If no plan doc, run **plan mode** first.
2. Read plan (`$DOC_PATH`, user path, or `$PLAN_PATH`).
3. **Phase 0:** Run `ip-scan.sh`; fix hits; re-scan until CLEAN. User must acknowledge findings before large edits if first polish run.
4. Create branch:

```bash
cd "$TARGET_ROOT"
git checkout -b feat/repo-standards-setup 2>/dev/null || git checkout -b "feat/repo-standards-setup-$(date +%s)"
```

5. **Phases 1–4:** Implement per plan using `$CONTRACT_ROOT/templates/` (see `INDEX.md`).
   **Banner (phase 1):** If S1-05 is a gap, generate `assets/banner.svg` — a 600×200 SVG with the repo name centered in bold on a dark background (#0F1117), subtitle in gray (#8B949E), and a subtle accent stripe. Use web-safe font stack (no external references). Add `<p align="center"><img src="assets/banner.svg" alt="REPO_NAME" width="600" /></p>` as the first line of README.md.
6. **Phase 5:** `Skill("multi-agent-repo")` per `references/delegation.md` on the same branch.
7. **Phase 6:** `Skill("docs-review")`; if plugin or agent-kit repo, `Skill("changelog-review")`. Fix all P1 findings.
8. **Phase 7:** `bash "$SKILL_DIR/scripts/assert-contract.sh" "$TARGET_ROOT" "$CONTRACT_PROFILE"` — P1/P2/P3 must be 0.
9. Commit in logical chunks; push; `gh pr create` with `templates/pr-body.md.tmpl`.
10. Print PR URL.

**Stop at PR.**

---

## Hard rules

- **Never `runs-on: [self-hosted]`** in generated CI.
- **Never push to GitHub new repo** from this skill — PR on existing remote only.
- **Never merge** the PR from this skill.
- **IP scan clean** before final PR.
- **Apply all P1** standards + multi-agent gaps before PR.
- **AGENTS.md canonical** — delegate multi-agent file generation to `multi-agent-repo`.

## Relationship to other skills

| Skill | When to use instead |
|-------|---------------------|
| `repo-scaffold` | Brand-new repo from scratch |
| `multi-agent-repo` | Multi-agent setup only, no full standards pass |
| `pr-dev` | Drive the standards PR to merge after polish |

## Example invocations

```text
/repo-standards
/repo-standards review ../my-app
/repo-standards plan
/repo-standards polish
/repo-standards polish . -- skip branch protection for now
```
