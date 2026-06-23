---
name: repo-scaffold
description: 'Use when the user wants to create a new GitHub repository from scratch with production-ready infrastructure. Triggers: ''scaffold a repo'', ''create a new repo'', ''set up a new project'', ''new github repo'', ''bootstrap a project'', ''forge a repo'', ''/repo-scaffold'', ''start a new repo'', ''initialize a project'', ''make me a repo''. Does NOT trigger for repo-polish (existing repo) or when the user only wants docs.'
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

**README structure:** centered hero section, badges row (CI, MIT, Claude Code `D97757`), elevator pitch, features list, quick-start, architecture overview, links to docs.

**Docs tree:**
```
docs/
  README.md            ← canonical index
  user/
    quick-start.md
    usage.md
    troubleshooting.md
    reference/commands.md
  engineering/
    architecture/overview.md
    decisions/ADR-001-initial-architecture.md
    guides/getting-started.md
    build-and-release/README.md
```

**Root file checklist:** `CLAUDE.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `LICENSE` (MIT), `Makefile`, `.gitignore`, `CODEOWNERS`, `.nvmrc` (node/nextjs only).

**Branch strategy:** `master` (default), `stable` (releases). Feature: `feat/`, fixes: `fix/`.

**Commit convention:**
```
<type>(<scope>): <description>

Co-Authored-By: Claude <noreply@anthropic.com>
```

**CLAUDE.md:** 200-350 lines. Sections: Overview, Architecture, Quick Start, Commands, Coding Standards, Commit Convention, Constraints, Working With Claude Code.

**CI:** Three workflows: `ci.yml` (job MUST be named exactly `CI`), `claude.yml`, `release.yml`. All use `ubuntu-latest` except Swift which uses `macos-latest`.

**Branch protection on `master`:** require 1 PR review, require `CI` status check, no direct pushes.

Read `$CLAUDE_SKILL_DIR/references/templates.md` for exact template content for README, CLAUDE.md, .claude/settings.json, CI workflows, Makefile, and .gitignore — use those templates, do not invent formats.

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

Fan out 4 agents IN THE SAME TURN (one message with 4 Agent tool calls). Each agent writes its files directly to `REPO_ROOT`. They operate on non-overlapping directories.

Pass to every agent: `REPO_NAME`, `DESCRIPTION`, `TECH`, `REPO_ROOT`, `SKILL_DIR=$CLAUDE_SKILL_DIR`.

---

**Agent A — Documentation** (writes `docs/` and `README.md`)

```
You are writing documentation for a new GitHub repo.

Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Repo root: REPO_ROOT

Read templates from: SKILL_DIR/references/templates.md

Write these files (fully populated — no template placeholders left unfilled):

1. REPO_ROOT/README.md — hero README per template (CI badge, MIT badge, Claude Code badge D97757)
2. REPO_ROOT/docs/README.md — canonical docs index
3. REPO_ROOT/docs/user/quick-start.md — 10-15 step guide
4. REPO_ROOT/docs/user/usage.md — common workflows
5. REPO_ROOT/docs/user/troubleshooting.md — common issues + fixes
6. REPO_ROOT/docs/user/reference/commands.md — command reference table
7. REPO_ROOT/docs/engineering/architecture/overview.md — components, data flow, key decisions
8. REPO_ROOT/docs/engineering/decisions/ADR-001-initial-architecture.md — first ADR
9. REPO_ROOT/docs/engineering/guides/getting-started.md — developer onboarding
10. REPO_ROOT/docs/engineering/build-and-release/README.md — how to build, test, release
```

---

**Agent B — .claude/ Configuration** (writes `.claude/` and `CLAUDE.md`)

```
You are setting up the Claude Code workspace config for a new GitHub repo.

Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Repo root: REPO_ROOT

Read templates from: SKILL_DIR/references/templates.md

Write these files:

1. REPO_ROOT/CLAUDE.md — 200-350 lines per template (Overview, Architecture, Quick Start, Commands, Coding Standards, Commit Convention, Constraints, Working With Claude Code)

2. REPO_ROOT/.claude/settings.json — per template, with TECH-appropriate permissions added to the allow list

3. REPO_ROOT/.claude/rules/constraints.md — project hard constraints (no secrets, no force-push to master, no .github/workflows/ edits without review, plus 3-5 TECH-appropriate constraints)

4. REPO_ROOT/.claude/skills/run-REPO_NAME/SKILL.md — utility skill to build and run the project locally (30-50 lines, correct commands for TECH)
```

---

**Agent C — CI/CD** (writes `.github/`)

```
You are setting up GitHub Actions CI/CD for a new repo.

Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Repo root: REPO_ROOT

Read CI templates from: SKILL_DIR/references/templates.md

Write these files:

1. REPO_ROOT/.github/workflows/ci.yml — job MUST be named exactly "CI". Use TECH-appropriate setup action. ubuntu-latest except Swift uses macos-latest.

2. REPO_ROOT/.github/workflows/claude.yml — Claude Code automation per template

3. REPO_ROOT/.github/workflows/release.yml — per template

4. REPO_ROOT/.github/pull_request_template.md — Summary, Type of change (checkbox), Test plan, Notes, "Generated with Claude Code" footer

5. REPO_ROOT/CODEOWNERS — "* @TamirCohen28"
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
2. REPO_ROOT/CONTRIBUTING.md — fork, branch naming, commit convention, PR process
3. REPO_ROOT/CODE_OF_CONDUCT.md — Contributor Covenant 2.1 short form
4. REPO_ROOT/SECURITY.md — supported versions, report to tamircohen2468@gmail.com
5. REPO_ROOT/Makefile — per template for TECH (help default, install, build, test, lint, dev, clean)
6. REPO_ROOT/.gitignore — comprehensive for TECH per template
7. REPO_ROOT/.nvmrc — ONLY if TECH is node or nextjs; content: "22"
8. REPO_ROOT/CHANGELOG.md — stub with ## [Unreleased] and ## [0.1.0] sections
```

---

### Stage 4: Assemble, Push, and Protect

After all 4 agents complete:

```bash
cd "$REPO_ROOT"
git add -A
git commit -m "$(cat <<'EOF'
chore(scaffold): initial repo scaffold

Generated by repo-scaffold skill with production-master style patterns.
Includes: README, docs, CLAUDE.md, .claude/ config, CI/CD workflows,
branch protection setup, and project-specific skill.

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
✓ Files committed:    README, docs/, CLAUDE.md, .claude/, .github/workflows/, root infra
✓ Branch protection:  master — 1 required review + CI check
✓ skill-creator:      ran — check .claude/skills/ for generated skills

Next steps:
  gh repo clone TamirCohen28/REPO_NAME
  cd REPO_NAME && make install
  /plugin marketplace add Tamircohen28/plugins  (in Claude Code session)
  /plugin install tamirs-superpowers@tamirs-plugins
```
