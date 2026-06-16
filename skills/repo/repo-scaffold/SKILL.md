---
name: repo-scaffold
description: "Use when the user wants to create a new GitHub repository from scratch with production-ready infrastructure. Scaffolds a fully structured private repo with README (badge style from production-master), user + engineering docs, architecture, CLAUDE.md, .claude/ config with tamirs-plugins marketplace and all plugins, CI/CD workflows, branch protection rules, and project-specific skills — then runs skill-creator. Triggers: 'create a new repo', 'scaffold a repo', 'set up a new project', 'new github repo', 'bootstrap a project', 'forge a repo', 'repo-scaffold', '/repo-scaffold', 'start a new repo', 'initialize a project'."
user-invocable: true
when_to_use: "User wants to create a new private GitHub repo from an idea, description, or existing source code — fully scaffolded with docs, CI, Claude Code tooling, and branch protection."
argument-hint: "<repo-name> -- <description> [--src <github-url-or-local-path>] [--tech <stack>]"
model: claude-sonnet-4-6
effort: high
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
  updated-date: "2026-06-16"
---

# repo-scaffold

Create a production-ready private GitHub repo in one command. Outputs a fully scaffolded repo matching Tamir Cohen's style: badge-rich README, user + engineering docs, CLAUDE.md, full .claude/ config with plugins, CI/CD, branch protection, and project-specific skills.

## Input Format

```
/repo-scaffold <repo-name> -- <description> [--src <url-or-path>] [--tech <stack>]
```

- `<repo-name>` — kebab-case name for the GitHub repo
- `<description>` — what the project does (sentence or two)
- `--src` (optional) — GitHub URL or local path of existing source to port
- `--tech` (optional) — force a tech stack: `node`, `nextjs`, `python`, `swift`, `generic`

If no `--tech` is given, detect it from the description keywords or `--src` files.

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

These patterns are distilled from TamirCohen28's repos (production-master, headhunter, world-cup-party, job-tracker-web, tamirs-superpowers). Apply them to every generated repo — do not deviate without a clear reason.

**README structure:** centered hero section, badges row, short elevator pitch, features list, quick-start, architecture overview, links to docs.

**Badge style:** shields.io badges — CI (GitHub Actions), License (MIT blue), Claude Code (`D97757` color, Anthropic logo). Flat-square stat badges for "by the numbers" if the project has measurable things.

**Docs tree:**
```
docs/
  README.md            ← canonical index (list every doc with one-line purpose)
  user/
    quick-start.md
    usage.md
    troubleshooting.md
    reference/
  engineering/
    architecture/
      overview.md
    decisions/          ← ADRs
    guides/
    build-and-release/
```

**Root file checklist:** `CLAUDE.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `LICENSE` (MIT), `Makefile`, `.gitignore`, `CODEOWNERS`, `.nvmrc` (node projects).

**Branch strategy:** `master` (default), `stable` (releases). Feature branches use `feat/` prefix, fixes use `fix/`.

**Commit convention:**
```
<type>(<scope>): <description>

Co-Authored-By: Claude <noreply@anthropic.com>
```

**CLAUDE.md:** Must cover overview, architecture, commands (build/test/lint), coding standards, commit conventions, constraints. Mirrors global `~/.claude/CLAUDE.md` structure but scoped to this project.

**CI:** GitHub-hosted `ubuntu-latest` runners. Three workflows: `ci.yml` (lint + test, required check named `CI`), `claude.yml` (Claude Code PR automation), `release.yml` (tags stable, creates GitHub release).

**Branch protection on `master`:** require 1 PR review, require `CI` status check, no direct pushes, no force-push.

---

## Execution

### Stage 1: Parse & Plan

Extract from args:
- `REPO_NAME` — first token before `--`
- `DESCRIPTION` — text after `--` before any flags
- `SRC` — value of `--src` (optional)
- `TECH` — value of `--tech` or auto-detect from description/src

Print a one-line plan to the user before proceeding:
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
# Create private repo
gh repo create TamirCohen28/REPO_NAME \
  --private \
  --description "DESCRIPTION" \
  --clone \
  --gitignore "" 2>&1

# If clone didn't happen automatically:
cd /tmp && git clone git@github.com:TamirCohen28/REPO_NAME.git REPO_NAME
```

Set `REPO_ROOT=/tmp/REPO_NAME`. All subsequent agents write files here.

Confirm clone succeeded:
```bash
ls REPO_ROOT
```

### Stage 3: Parallel Content Generation

Fan out 4 agents IN THE SAME TURN (one message with 4 Agent tool calls). Each agent writes its files directly to `REPO_ROOT`. They operate on non-overlapping directories so no conflicts occur.

Pass these variables to every agent prompt: `REPO_NAME`, `DESCRIPTION`, `TECH`, `REPO_ROOT`.

---

**Agent A — Documentation** (writes `docs/` and `README.md`)

Prompt:
```
You are writing documentation for a new GitHub repo.

Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Repo root: REPO_ROOT

Read the templates from:
  ~/.claude/plugins/cache/tamirs-superpowers/*/skills/repo/repo-scaffold/references/templates.md

Then write these files, fully populated (no placeholders):

1. REPO_ROOT/README.md — hero README with CI badge, MIT badge, Claude Code badge (color D97757), elevator pitch, features list (bullet points derived from description), quick-start section, architecture section, and links to docs/. Base the badge URLs on https://github.com/TamirCohen28/REPO_NAME.

2. REPO_ROOT/docs/README.md — canonical docs index listing every doc file with one-line purpose.

3. REPO_ROOT/docs/user/quick-start.md — 10-15 step quick-start guide derived from the project description and tech stack.

4. REPO_ROOT/docs/user/usage.md — usage guide with common workflows.

5. REPO_ROOT/docs/user/troubleshooting.md — common issues and fixes (infer from tech stack and project type).

6. REPO_ROOT/docs/user/reference/commands.md — command reference table.

7. REPO_ROOT/docs/engineering/architecture/overview.md — architecture overview: components, data flow, key decisions. Derive from description.

8. REPO_ROOT/docs/engineering/decisions/ADR-001-initial-architecture.md — first ADR documenting the initial architectural choices.

9. REPO_ROOT/docs/engineering/guides/getting-started.md — developer onboarding guide.

10. REPO_ROOT/docs/engineering/build-and-release/README.md — how to build, test, and release.

Write each file using the Write tool. Make content specific to this project — never leave template placeholders unfilled.
```

---

**Agent B — .claude/ Configuration** (writes `.claude/` and `CLAUDE.md`)

Prompt:
```
You are setting up the Claude Code workspace config for a new GitHub repo.

Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Repo root: REPO_ROOT

Read the templates from:
  ~/.claude/plugins/cache/tamirs-superpowers/*/skills/repo/repo-scaffold/references/templates.md

Write these files:

1. REPO_ROOT/CLAUDE.md — developer guide (200-350 lines). Sections:
   - Overview (what the project does, why it exists)
   - Architecture (component map, key files)
   - Quick Start (clone, install, run)
   - Commands (build, test, lint, deploy — specific to TECH stack)
   - Coding Standards (naming, file structure, patterns)
   - Commit Convention (feat/fix/chore/docs, Co-Authored-By line)
   - Constraints (what NOT to do — e.g., no force-push to master, no secrets in code)
   - Working With Claude Code (how to use skills, what agents are available)

2. REPO_ROOT/.claude/settings.json — project-level Claude Code config:
   {
     "extraKnownMarketplaces": [
       { "name": "tamirs-plugins", "sourceUrl": "https://github.com/Tamircohen28/plugins" }
     ],
     "enabledPlugins": {
       "tamirs-superpowers@tamirs-plugins": true,
       "headhunter@tamirs-plugins": true,
       "jose-claudinho@tamirs-plugins": true
     },
     "permissions": {
       "allow": [
         "Bash(git *)",
         "Bash(gh *)",
         <add TECH-appropriate commands: e.g. "Bash(npm *)" for node, "Bash(python *)" for python>,
         "Read(*)",
         "Edit(*)",
         "Write(*)",
         "Glob(*)",
         "Grep(*)"
       ]
     },
     "attribution": {
       "commit": "Co-Authored-By: Claude <noreply@anthropic.com>"
     }
   }

3. REPO_ROOT/.claude/rules/constraints.md — project hard constraints:
   - No secrets or tokens committed
   - No force-push to master
   - No modifying .github/workflows/ without team review
   - <add 3-5 TECH-appropriate constraints>

4. REPO_ROOT/.claude/skills/run-REPO_NAME/SKILL.md — a quick project utility skill:
   A skill named "run-REPO_NAME" that builds and runs the project locally. Short (30-50 lines), with correct commands for TECH stack.

Write each file using Write tool. Make CLAUDE.md detailed and project-specific.
```

---

**Agent C — CI/CD** (writes `.github/`)

Prompt:
```
You are setting up GitHub Actions CI/CD for a new repo.

Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Repo root: REPO_ROOT

Read the CI templates from:
  ~/.claude/plugins/cache/tamirs-superpowers/*/skills/repo/repo-scaffold/references/templates.md

Write these files:

1. REPO_ROOT/.github/workflows/ci.yml
   - name: CI
   - triggers: push to master, pull_request to master
   - runs-on: ubuntu-latest
   - job name must be exactly "CI" (required for branch protection)
   - Steps: checkout, setup TECH toolchain, install deps, lint, test
   - Use correct tool for TECH: actions/setup-node@v4 + node-version-file: .nvmrc (node/nextjs), actions/setup-python@v5 (python), swift toolchain (swift), basic shellcheck (generic)

2. REPO_ROOT/.github/workflows/claude.yml
   - Claude Code PR automation workflow
   - Triggers: issue_comment with "@claude", pull_request labeled "claude"
   - Uses: anthropics/claude-code-action@v1 with claude-opus-4-8 model
   - Requires: ANTHROPIC_API_KEY secret

3. REPO_ROOT/.github/workflows/release.yml
   - Triggers: push of tags matching v*.*.*
   - Runs on: ubuntu-latest
   - Steps: checkout, build (TECH-appropriate), create GitHub release with gh CLI
   - Tags the stable branch

4. REPO_ROOT/.github/pull_request_template.md
   - Sections: Summary (bullets), Type of change (checkbox), Test plan (checklist), Notes
   - Footer: "Generated with Claude Code"

5. REPO_ROOT/CODEOWNERS
   - * @TamirCohen28

Write all files using Write tool. Make sure the job in ci.yml is named exactly "CI" — this is the required status check name for branch protection.
```

---

**Agent D — Root Infrastructure** (writes root config files)

Prompt:
```
You are writing the root infrastructure files for a new GitHub repo.

Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Repo root: REPO_ROOT

Write these files:

1. REPO_ROOT/LICENSE — MIT license, copyright "2026 Tamir Cohen"

2. REPO_ROOT/CONTRIBUTING.md — how to contribute: fork, branch naming (feat/, fix/), commit convention, PR process, code review expectations

3. REPO_ROOT/CODE_OF_CONDUCT.md — standard Contributor Covenant 2.1 short form

4. REPO_ROOT/SECURITY.md — security policy: supported versions table, how to report vulnerabilities (email tamircohen2468@gmail.com, do not open public issues)

5. REPO_ROOT/Makefile — useful targets for TECH stack:
   - help (default): print all targets with descriptions
   - install / setup: install dependencies
   - build: build the project
   - test: run tests
   - lint: run linter
   - clean: remove build artifacts
   - dev: start dev server (if applicable)
   Use correct commands for TECH (npm ci / pip install / swift build / etc.)

6. REPO_ROOT/.gitignore — comprehensive gitignore for TECH stack. Include: .env*, node_modules/, dist/, .build/, __pycache__/, .DS_Store, .dev-files/, *.log, coverage/

7. REPO_ROOT/.nvmrc — only if TECH is node or nextjs. Content: "22"

8. REPO_ROOT/CHANGELOG.md — changelog stub with ## [Unreleased] and ## [0.1.0] sections

Write all files using Write tool.
```

---

### Stage 4: Assemble, Push, and Protect

After all 4 agents complete, run:

```bash
cd REPO_ROOT

# Stage everything
git add -A

# Commit
git commit -m "$(cat <<'EOF'
chore(scaffold): initial repo scaffold

Generated by repo-scaffold skill with production-master style patterns.
Includes: README, docs, CLAUDE.md, .claude/ config, CI/CD workflows,
branch protection setup, and project-specific skill.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

# Push
git push origin master
```

Then apply branch protection:

```bash
gh api repos/TamirCohen28/REPO_NAME/branches/master/protection \
  --method PUT \
  --silent \
  -F 'required_status_checks[strict]=true' \
  -F 'required_status_checks[contexts][]=CI' \
  -F 'required_pull_request_reviews[required_approving_review_count]=1' \
  -F 'enforce_admins=false' \
  -F 'restrictions=null'
```

Confirm protection is set:
```bash
gh api repos/TamirCohen28/REPO_NAME/branches/master/protection \
  --jq '.required_status_checks.contexts, .required_pull_request_reviews.required_approving_review_count'
```

### Stage 5: Run skill-creator

Invoke the skill-creator to generate additional project-specific skills:

```
Use the Skill tool to invoke: tamirs-superpowers:skill-creator

Pass this context as the argument:
"Generate 2 project-specific skills for the repo at REPO_ROOT.
Project: REPO_NAME (DESCRIPTION, TECH stack).
Skills to generate:
1. A debug/log skill for common failure modes in this project type
2. A deploy/release skill that follows the release.yml workflow
Save them to REPO_ROOT/.claude/skills/ and push to origin master."
```

### Stage 6: Final Summary

Print:
```
✓ Repo created:    https://github.com/TamirCohen28/REPO_NAME
✓ Files committed: README, docs/, CLAUDE.md, .claude/, .github/workflows/, root infra
✓ Branch protection: master — 1 required review + CI check
✓ skill-creator: ran — check .claude/skills/ for generated skills

Next steps:
  gh repo clone TamirCohen28/REPO_NAME
  cd REPO_NAME && make install
  /plugin marketplace add Tamircohen28/plugins  (in Claude Code session)
  /plugin install tamirs-superpowers@tamirs-plugins
```
