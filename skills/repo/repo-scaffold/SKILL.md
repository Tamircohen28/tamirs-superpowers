---
name: repo-scaffold
description: 'Use when the user wants to create a new GitHub repository from scratch with production-ready infrastructure. Triggers: ''scaffold a repo'', ''create a new repo'', ''set up a new project'', ''new github repo'', ''bootstrap a project'', ''forge a repo'', ''/repo-scaffold'', ''start a new repo'', ''initialize a project'', ''make me a repo''. Does NOT trigger for repo-standards (existing repo polish) or when the user only wants docs.'
when_to_use: User wants to create a brand-new private GitHub repo from an idea or description — fully scaffolded with docs, CI, Claude Code tooling, and branch protection.
argument-hint: <repo-name> -- <description> [--src <github-url-or-local-path>] [--tech <stack>]
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- Bash
- Read
- Write
- Edit
- Glob
- Grep
- Agent
- Skill
- WebFetch
disallowed-tools: []
model: claude-sonnet-4-6
effort: high
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  capability: repo-scaffold
  provider: developer-workflow
  platforms:
  - claude
  tags:
  - github
  - scaffold
  - docs
  - ci-cd
  - claude-code
  - bootstrap
  updated-date: '2026-06-16'
---

# repo-scaffold

Create a production-ready private GitHub repo in one command. Outputs a fully scaffolded repo matching Tamir Cohen's style: badge-rich README, user + engineering docs, CLAUDE.md, .claude/ config with plugins, CI/CD, branch protection, and project-specific skills.

## Input Format

```
/repo-scaffold <repo-name> -- <description> [--src <url-or-path>] [--tech <stack>]
```

- `<repo-name>` — kebab-case name for the GitHub repo
- `<description>` — what the project does (sentence or two)
- `--src` (optional) — GitHub URL or local path of existing source to port
- `--tech` (optional) — force a tech stack: `node`, `nextjs`, `python`, `swift`, `generic`

If no `--tech` is given, auto-detect using the script at `$CLAUDE_SKILL_DIR/scripts/detect-stack.sh`:
```bash
bash "$CLAUDE_SKILL_DIR/scripts/detect-stack.sh" "<description>" [<src-local-path>]
```

## Tech Stack Detection Matrix

| Keywords in description / source files | Detected stack |
|---|---|
| next, nextjs, vercel, react + server | `nextjs` |
| react, vue, angular, vite, frontend | `node` |
| python, fastapi, flask, django, poetry | `python` |
| swift, macos, xcode, swiftui | `swift` |
| node, express, cli, npm, package.json | `node` |
| anything else | `generic` |

When `--src` is a GitHub URL, fetch the root file listing to check for `package.json`, `pyproject.toml`, `Package.swift`, etc.

## Baked-In Style Patterns

These patterns are distilled from TamirCohen28's repos. Apply them to every generated repo.

**README structure:** centered hero, badges (CI, MIT, Claude Code `D97757`), elevator pitch, features, **Prerequisites**, Quick Start, architecture, docs links.

**Docs tree** (canonical — see `skills/repo/_contract/standards-contract.json`):
```
docs/
  README.md
  CHANGELOG.md
  CONTRIBUTING.md
  user/
  engineering/
  agent-guidelines/
```

**Root file checklist:** `AGENTS.md`, `CLAUDE.md` (line 1: `@AGENTS.md`), `LICENSE`, `Makefile` (with `agent:check`), `.gitignore`, `CODEOWNERS`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `scripts/check-agent-drift.sh`, `.cursor/rules/000-project.mdc`, `.nvmrc` (node/nextjs only).

**Branch strategy:** `master` (default), `stable` (releases). Feature: `feat/`, fixes: `fix/`.

**Commit convention:**
```
<type>(<scope>): <description>

Co-Authored-By: Claude <noreply@anthropic.com>
```

**CLAUDE.md:** Line 1 `@AGENTS.md`; Claude-only addenda ~30 lines max. Full portable policy in `AGENTS.md` (100–200 lines).

**CI:** `ci.yml` with jobs named exactly `CI` and `secret-scan`; plus `claude.yml`, `release.yml`, `dependabot.yml`. All use `ubuntu-latest` except Swift (`macos-latest`).

**Branch protection on `master`:** require 1 PR review, require `CI` status check, no direct pushes.

**Contract:** `CONTRACT_ROOT="$(cd "$CLAUDE_SKILL_DIR/../_contract" && pwd)"`. Read `$CONTRACT_ROOT/templates/INDEX.md` and stack bodies in `legacy-scaffold-templates.md` — do not invent formats.

---

## Execution

### Stage 1: Parse & Plan

Extract from args:
- `REPO_NAME` — first token before `--`
- `DESCRIPTION` — text after `--` before any flags
- `SRC` — value of `--src` (optional)
- `TECH` — value of `--tech`; if absent, run detect-stack.sh

Print a one-line plan before proceeding:
```
Creating private repo TamirCohen28/<REPO_NAME> [<TECH> stack] — "<DESCRIPTION>". Scaffolding now...
```

If `--src` is a GitHub URL, run:
```bash
gh repo view <org>/<repo> --json defaultBranchRef,languages,description 2>/dev/null
```
to confirm access and refine tech stack detection.

### Stage 2: Create & Clone Repo

```bash
gh repo create TamirCohen28/$REPO_NAME \
  --private \
  --description "$DESCRIPTION" \
  --clone \
  --gitignore "" 2>&1
```

Set `REPO_ROOT=/tmp/$REPO_NAME`. All subsequent agents write files here.

Confirm clone succeeded:
```bash
ls "$REPO_ROOT"
```

### Stage 3: Parallel Content Generation

Fan out **5 agents** IN THE SAME TURN (one message with 5 Agent tool calls). Each agent writes its files directly to `REPO_ROOT`. They operate on non-overlapping directories.

Pass to every agent: `REPO_NAME`, `DESCRIPTION`, `TECH`, `REPO_ROOT`, `CONTRACT_ROOT="$(cd "$CLAUDE_SKILL_DIR/../_contract" && pwd)"`.

---

**Agent A — Documentation** (writes `docs/` and `README.md`)

```
You are writing documentation for a new GitHub repo.

Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Repo root: REPO_ROOT

Read templates from: CONTRACT_ROOT/templates/INDEX.md and legacy-scaffold-templates.md

Write these files (fully populated — no template placeholders left unfilled):

1. REPO_ROOT/README.md — hero README with Prerequisites + Quick Start (CI badge, MIT badge, Claude Code badge D97757)
2. REPO_ROOT/docs/README.md — canonical docs index
3. REPO_ROOT/docs/CHANGELOG.md — Unreleased + 0.1.0 stub
4. REPO_ROOT/docs/CONTRIBUTING.md — fork, branch naming, commit convention, PR process
5. REPO_ROOT/docs/user/quick-start.md — 10-15 step guide
6. REPO_ROOT/docs/user/usage.md — common workflows
7. REPO_ROOT/docs/user/troubleshooting.md — common issues + fixes
8. REPO_ROOT/docs/user/reference/commands.md — command reference table
9. REPO_ROOT/docs/engineering/architecture/overview.md — components, data flow, key decisions
10. REPO_ROOT/docs/engineering/decisions/ADR-001-initial-architecture.md — first ADR
11. REPO_ROOT/docs/engineering/guides/getting-started.md — developer onboarding
12. REPO_ROOT/docs/engineering/build-and-release/README.md — how to build, test, release
```

---

**Agent B — .claude/ Configuration** (writes `.claude/` only — `CLAUDE.md` is Agent E)

```
You are setting up the Claude Code workspace config for a new GitHub repo.

Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Repo root: REPO_ROOT

Read templates from: CONTRACT_ROOT/templates/legacy-scaffold-templates.md

Write these files:

1. REPO_ROOT/.claude/settings.json — per template, with TECH-appropriate permissions added to the allow list

2. REPO_ROOT/.claude/rules/constraints.md — project hard constraints (no secrets, no force-push to master, no .github/workflows/ edits without review, plus 3-5 TECH-appropriate constraints)

3. REPO_ROOT/.claude/skills/run-REPO_NAME/SKILL.md — utility skill to build and run the project locally (30-50 lines, correct commands for TECH)
```

---

**Agent C — CI/CD** (writes `.github/`)

```
You are setting up GitHub Actions CI/CD for a new repo.

Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Repo root: REPO_ROOT

Read CI templates from: CONTRACT_ROOT/templates/github/ci.yml.tmpl and legacy-scaffold-templates.md

Write these files:

1. REPO_ROOT/.github/workflows/ci.yml — jobs `CI` and `secret-scan`. TECH-appropriate setup in `CI`. ubuntu-latest except Swift uses macos-latest.

2. REPO_ROOT/.github/workflows/claude.yml — Claude Code automation per template

3. REPO_ROOT/.github/workflows/release.yml — per template

4. REPO_ROOT/.github/pull_request_template.md — Summary, Type of change (checkbox), Test plan, Notes

5. REPO_ROOT/.github/dependabot.yml — per CONTRACT_ROOT/templates/github/dependabot.yml.tmpl

6. REPO_ROOT/CODEOWNERS — "* @TamirCohen28"
```

---

**Agent D — Root Infrastructure** (writes root config files)

```
You are writing the root infrastructure files for a new GitHub repo.

Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Repo root: REPO_ROOT

Write these files:

1. REPO_ROOT/LICENSE — MIT license, copyright "2026 Tamir Cohen"
2. REPO_ROOT/CODE_OF_CONDUCT.md — Contributor Covenant 2.1 short form
3. REPO_ROOT/SECURITY.md — supported versions, report to tamircohen2468@gmail.com
4. REPO_ROOT/Makefile — per template for TECH (help default, install, build, test, lint, dev, clean, **agent:check** running scripts/check-agent-drift.sh)
5. REPO_ROOT/.gitignore — comprehensive for TECH per template
6. REPO_ROOT/.nvmrc — ONLY if TECH is node or nextjs; content: "22"
7. REPO_ROOT/scripts/check-agent-drift.sh — copy from CONTRACT_ROOT/templates/check-agent-drift.sh.tmpl (executable)
```

---

**Agent E — Multi-agent** (writes `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/`)

```
Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Repo root: REPO_ROOT

Follow multi-agent-repo references/platform-setup.md (phases 0–1):

1. REPO_ROOT/AGENTS.md — canonical portable rules (100–200 lines, exact make/npm commands)
2. REPO_ROOT/CLAUDE.md — line 1: @AGENTS.md; Claude-only addenda only
3. REPO_ROOT/.cursor/rules/000-project.mdc — alwaysApply: true, points to AGENTS.md
4. REPO_ROOT/docs/agent-guidelines/README.md — stub index linking to AGENTS.md
```

---

### Stage 4: Assemble, Contract Gate, Push, and Protect

After all 5 agents complete:

```bash
cd "$REPO_ROOT"
CONTRACT_ROOT="$(cd "$CLAUDE_SKILL_DIR/../_contract" && pwd)"
bash "$CONTRACT_ROOT/scripts/assert-contract.sh" "$REPO_ROOT" app-gold
```

If assert-contract fails, fix gaps and re-run **before** committing.

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore(scaffold): initial repo scaffold

Generated by repo-scaffold skill — passes app-gold contract profile.
Includes: README, docs, AGENTS.md, CLAUDE.md, .claude/, CI/CD, multi-agent adapters.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
git push origin master
```

Apply branch protection:

```bash
gh api repos/TamirCohen28/$REPO_NAME/branches/master/protection \
  --method PUT \
  --silent \
  -F 'required_status_checks[strict]=true' \
  -F 'required_status_checks[contexts][]=CI' \
  -F 'required_pull_request_reviews[required_approving_review_count]=1' \
  -F 'enforce_admins=false' \
  -F 'restrictions=null'
```

Confirm:
```bash
gh api repos/TamirCohen28/$REPO_NAME/branches/master/protection \
  --jq '.required_status_checks.contexts, .required_pull_request_reviews.required_approving_review_count'
```

### Stage 5: Run skill-creator

Invoke `tamirs-superpowers:skill-creator` to generate 2 project-specific skills:

```
Generate 2 project-specific skills for the repo at REPO_ROOT.
Project: REPO_NAME (DESCRIPTION, TECH stack).
Skills to generate:
1. A debug/log skill for common failure modes in this project type
2. A deploy/release skill that follows the release.yml workflow
Save them to REPO_ROOT/.claude/skills/ and push to origin master.
```

### Stage 6: Final Summary

Print:
```
✓ Repo created:       https://github.com/TamirCohen28/REPO_NAME
✓ Contract:          app-gold profile passed (assert-contract.sh)
✓ Files committed:    README, docs/, AGENTS.md, CLAUDE.md, .claude/, .github/, root infra
✓ Branch protection:  master — 1 required review + CI check
✓ skill-creator:      ran — check .claude/skills/ for generated skills

Next steps:
  gh repo clone TamirCohen28/REPO_NAME
  cd REPO_NAME && make install
  /plugin marketplace add Tamircohen28/plugins  (in Claude Code session)
  /plugin install tamirs-superpowers@tamirs-plugins
```
