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
  updated-date: '2026-08-03'
  tamirs:
    visibility: public
    category: repo
    capabilities:
      required: [shell, git]
      optional: [github_cli]
    role: reviewer
    updated-date: "2026-08-19"
    validation-tier: 2

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
| `../../../config/github/repository-policy.json` | Canonical GitHub repository policy — rulesets, required contexts, Actions concurrency. **Never restate its content**; read it. |
| `../../../scripts/github-policy.sh` | `audit` / `plan` / `apply` / `verify` for branch governance (S4-02…S4-14) |
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
PLUGIN_ROOT="$(cd "$CONTRACT_ROOT/../../.." && pwd)"
POLICY_CLI="$PLUGIN_ROOT/scripts/github-policy.sh"
REPO_SLUG="$(git -C "$TARGET_ROOT" remote get-url origin 2>/dev/null | sed -E 's#^.*github\.com[:/]##; s#\.git$##' || true)"
REVIEW_PATH="$TARGET_ROOT/docs/engineering/repo-standards-review-$DATE.md"
PLAN_PATH="$TARGET_ROOT/docs/engineering/repo-standards-plan-$DATE.md"
```

---

## Mode: review (read-only)

**Goal:** Unified gap report (standards S1–S7 + multi-agent S8 + E/V feature equivalence). **No repo edits** except the report file.

### Steps

1. Read `references/standards-rubric.md`. If `$CONTRACT_PROFILE` is `plugin-gold`, also read `references/plugin-review.md`.
2. Start findings from `$GAPS` JSON (profile: `$CONTRACT_PROFILE`); walk rubric for qualitative gaps (README prose, doc content).
3. Include `$IP_SCAN` summary; flag S7-01 P1 if not CLEAN.
4. `cd "$TARGET_ROOT"` then `Skill("multi-agent-repo")` using `references/delegation.md` review prompt. Append child summary to report — do not duplicate full child report.
5. Read-only docs pass: summarize README + `docs/**` issues without calling `Skill("docs-review")` (it mutates files).
6. When multi-platform, walk **Per-target parity (V-layer)** for every declared target and record V-01…V-05 gaps as P1.
7. `mkdir -p "$TARGET_ROOT/docs/engineering"`
8. Write `$REVIEW_PATH` from `templates/review-report.md.tmpl`.

### Report structure

```markdown
# Repo standards review — [repo name]
## Executive summary
## Severity summary
## Standards gaps (S1–S7 + PK* if plugin-gold)
## Plugin / agent-kit appendix (if plugin-gold)
## Employer IP scan
## GitHub repository policy
## Multi-agent appendix
## Feature equivalence appendix (E-layer)
## Platform targets appendix (V-layer)
## Docs read-only notes
## Inventory appendix (JSON)
## Next steps
```

`## GitHub repository policy` is populated from `$INVENTORY`'s `branch_governance` block and, when `$REPO_SLUG` is non-empty and `gh` is authenticated, `bash "$POLICY_CLI" audit --repo "$REPO_SLUG"`. Record, in this order:

1. Which mechanism governs the default branch — rulesets, classic protection, or nothing (`branch_governance.source`).
2. Per-ruleset compliance as the audit reports it, plus any CONFLICT the audit refuses to resolve.
3. `strict_required_status_checks_policy` — its literal value, because S4-09 is the one setting that must never silently flip.
4. Legacy classic protection as a **migration item**. Absent is the healthy state on a rulesets-governed repo and is never a finding.
5. Actions concurrency findings in both directions: a cancellable PR-validation workflow missing the block, and a stateful workflow that wrongly has cancellation on.

When governance could not be read (`branch_governance.readable` is `false` — no `gh`, no auth, or no permission), say so plainly and score **no** S4 gaps. An unread control is unknown, not broken. Never copy rule values, ruleset names, or required-context lists out of `config/github/repository-policy.json` into the report — cite the file.

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
   **Phase 4 (branch governance)** — after the CI workflow is on the default branch:
   ```bash
   bash "$CONTRACT_ROOT/scripts/enable-repo-merge-settings.sh"
   bash "$POLICY_CLI" plan  --repo "$REPO_SLUG"   # diff only, writes nothing
   bash "$POLICY_CLI" apply --repo "$REPO_SLUG"   # confirms each change at the TTY
   ```
   `github-policy.sh` replaced `ensure-branch-protection.sh`, which read and wrote **classic** `branches/*/protection` — an endpoint that 404s on a repository correctly governed by rulesets, so it reported protected repos as unprotected. The old script survives only as a deprecating shim onto these verbs.

   Rulesets are authoritative; classic protection is a **legacy migration item**, reported and never written, and its absence is not a gap. Every rule, required context, and enforcement value comes from `config/github/repository-policy.json` — do not restate any of it here or in the report.

   - `plan` when the user asked to audit only, or asked to skip applying rules (this is what `--verify-only` used to mean). `audit` for the read-only compliance answer with no remediation diff.
   - `apply` never writes without a confirmation, refuses any change that would make the repo **less** protected than it is today, and prints the plan instead of writing when there is no TTY.
   - **`strict_required_status_checks_policy` must stay `false`** (S4-09, P1). With it on, every merge marks every other open branch out of date and the one-objective/one-PR flow stalls behind a serial rebase queue.
   **Banner (phase 1):** If S1-05 is a gap, generate `assets/banner.svg` — a 600×200 SVG with the repo name centered in bold on a dark background (#0F1117), subtitle in gray (#8B949E), and a subtle accent stripe. Use web-safe font stack (no external references). Add `<p align="center"><img src="assets/banner.svg" alt="REPO_NAME" width="600" /></p>` as the first line of README.md.
6. **Phase 5:** `Skill("multi-agent-repo")` per `references/delegation.md` on the same branch (include feature equivalence + platform targets).
7. **Phase 6:** `Skill("docs-review")`; if plugin or agent-kit repo, `Skill("changelog-review")`. Fix all P1 findings.
8. **Phase 6b (agents only):** When multi-platform, run `make platform-targets-sync`, update `platform-targets.json` + README Row 3 + `platform-targets.md`, then `make platform-targets-assert`. Close every V-01…V-05 gap from the review in this phase — a declared target with a missing artifact must either be completed or dropped from `supported_targets`, never left half-supported.
9. **Phase 7:** Run `make repo-standards-gate` when multi-platform (or `make agent-polish-gate` + `assert-contract --manifests-only` on release PRs before the tag exists). P1/P2/P3 must be 0.
10. `$REVIEW_PATH` and `$PLAN_PATH` are session scratch notes, not deliverables — remove them from the branch before the final commit so they never ship in the PR: `git rm --ignore-unmatch "$REVIEW_PATH" "$PLAN_PATH"` (or plain `rm` if untracked).
11. Commit in logical chunks; push; `gh pr create` with `templates/pr-body.md.tmpl`.
12. Print PR URL.

**Stop at PR.**

---

## Per-target parity (V-layer)

A repo that declares support for a target owes that target a full set of artifacts. Partial support is worse than no support: the target appears in the README, users install against it, and the gaps surface as "the plugin is broken" rather than "this target was never finished".

For **every** key in `platform-targets.json` → `supported_targets`, confirm all five exist. Report a missing one as **P1**:

| # | Artifact | Failure mode when missing |
|---|----------|---------------------------|
| V-01 | Manifest or config for the target | Target cannot load the content at all |
| V-02 | `docs/user/install/<target>.md`, linked from the install README | Users have no documented path in |
| V-03 | `targets.<key>` entry with `validated_against`, `verified_on`, `verification_method`, `install_doc` | Version support is a guess; nothing can assert staleness |
| V-04 | A per-target sub-skill under the platform-sync umbrella | `/platform-sync` skips the target **silently** and reports success — reads as "no improvements found" |
| V-05 | The target named in README.md, AGENTS.md and CLAUDE.md | Invisible to users and to other agents |
| V-06 | A `core/capabilities/platforms.json` entry with an explicit status for every capability key | Skills assume capabilities the target lacks instead of degrading; gaps are re-litigated every audit |

A target whose `validated_against` is `"unknown"` is **declared but not yet validated**. V-02, V-04 and V-05 degrade to warnings for it, and it carries no README badge — that is the honest state, not a defect. It becomes a hard failure the moment a real version is recorded, so a declared target cannot sit unvalidated behind a green build once someone claims to have run it.

Two failure modes to check for specifically, because both fail quietly:

- **Marketplace declaration shape.** Claude Code's `extraKnownMarketplaces` is a **record keyed by marketplace name**, never an array. An array is dropped with no error and no warning, and a valid global `~/.claude/settings.json` can mask the broken project-level file for months. Nested form is `source: {source, repo}` (GitHub) or `source: {source, url}` (git); there is no `sourceUrl` field. Verify with `claude doctor`. Since Claude Code 2.1.232, `additionalMarketplaces` is accepted as a friendlier alias (and `allowedMarketplaces` for `strictKnownMarketplaces`) — same record shape, same silent-drop trap for arrays; keep `extraKnownMarketplaces` in files that must load on older versions.
- **Capability assumptions across targets.** Do not recommend a fix that assumes a capability the target lacks. Look the answer up in `core/capabilities/platforms.json` — the capability registry is the only source for this, and it records a status for all 19 capability keys on every target. Read the status out of the registry at audit time — do not carry one in your head or quote one from this file. Statuses move as targets are re-measured: OpenCode's `hooks` and Gemini's `skills` and `subagents` have each changed value during a single release cycle, and any prose that had pinned them was wrong within the day. Record a newly discovered gap **in the registry**, then run `bash scripts/check-platform-targets.sh . --sync-capabilities` to refresh the derived `capabilities`/`capability_gaps` mirror in `platform-targets.json`. Never hand-edit that mirror and never restate a status in prose: `make check-feature-equivalence` fails the build when two views of the platform set disagree.

`make check-doc-claims` enforces V-02, V-03, and V-05 — and computes the skill count and the supported-target count from the filesystem, so a stale "27 skills" or "four supported targets" in any Markdown or manifest fails CI rather than aging quietly. `make check-platform-targets` enforces V-04 and the derived capability mirror; `make check-feature-equivalence` enforces V-06 and registry agreement; `make check-marketplace-schema` enforces the record shape. All run inside `make validate`. Use `bash scripts/check-doc-claims.sh --expected` to print the numbers the docs must state.

## Agent execution rule

Agents run `make repo-standards-gate` during repo-standards polish **and** via `start-dev` / `pr-dev` (`run-pre-pr-gates.sh`) before every push/PR — **never** instruct the user to run `bash scripts/check-*.sh` directly.

## Hard rules

- **Never `runs-on: [self-hosted]`** in generated CI.
- **Never push to GitHub new repo** from this skill — PR on existing remote only.
- **Never merge** the PR from this skill.
- **IP scan clean** before final PR.
- **Apply all P1** standards + multi-agent gaps before PR.
- **No half-supported targets** — every key in `supported_targets` carries all five V-layer artifacts, or it comes out of the list.
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
