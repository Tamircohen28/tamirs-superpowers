---
name: repo-scaffold
description: 'Use when the user wants to create a new GitHub repository from scratch with production-ready infrastructure. Triggers: ''scaffold a repo'', ''create a new repo'', ''set up a new project'', ''new github repo'', ''bootstrap a project'', ''forge a repo'', ''/repo-scaffold'', ''start a new repo'', ''initialize a project'', ''make me a repo'', ''agent-kit'', ''plugin marketplace''. Use --type plugin for agent-kit distribution repos. Does NOT trigger for repo-standards (existing repo polish) or when the user only wants docs.'
when_to_use: User wants to create a brand-new private GitHub repo from an idea or description — fully scaffolded with docs, CI, Claude Code tooling, and branch protection. Use --type plugin for agent-kit / multi-platform plugin distribution repos.
argument-hint: <repo-name> -- <description> [--type app|plugin] [--src <github-url-or-local-path>] [--tech <stack>]
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
  updated-date: '2026-06-23'
---

# repo-scaffold

Create a production-ready private GitHub repo in one command. Outputs a fully scaffolded repo matching Tamir Cohen's style: badge-rich README, user + engineering docs, CLAUDE.md, .claude/ config with plugins, CI/CD, branch protection, and project-specific skills.

**User guide (agent-kit / `--type plugin`):** [docs/user/agent-kit.md](../../../docs/user/agent-kit.md)

## Input Format

```
/repo-scaffold <repo-name> -- <description> [--type app|plugin] [--src <url-or-path>] [--tech <stack>]
```

- `<repo-name>` — kebab-case name for the GitHub repo
- `<description>` — what the project does (sentence or two)
- `--type` (optional) — `app` (default) or `plugin` (agent-kit distribution repo)
- `--src` (optional) — GitHub URL or local path of existing source to port
- `--tech` (optional) — force a tech stack: `node`, `nextjs`, `python`, `swift`, `generic`. **Plugin type forces `node`** unless overridden.

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
| plugin, agent-kit, marketplace, claude code plugin, skills distribution | suggest `--type plugin` |
| anything else | `generic` |

When `--type plugin`, read `$CONTRACT_ROOT/templates/scaffold-requirements-plugin.md` and render bodies from `$CONTRACT_ROOT/templates/plugin/`.

When `--src` is a GitHub URL, fetch the root file listing to check for `package.json`, `pyproject.toml`, `Package.swift`, etc.

## Baked-In Style Patterns

These patterns are distilled from TamirCohen28's repos. Apply them to every generated repo.

**README structure:** centered hero banner (`<p align="center"><img src="assets/banner.svg" alt="REPO_NAME" width="600" /></p>`), badges (CI, MIT, Claude Code `D97757`), elevator pitch, features, **Prerequisites**, Quick Start, architecture, docs links.

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

**Root file checklist:** `AGENTS.md`, `CLAUDE.md` (line 1: `@AGENTS.md`), `LICENSE`, `Makefile` (with `agent:check`), `.gitignore`, `CODEOWNERS`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `scripts/check-agent-drift.sh`, `.cursor/rules/000-project.mdc`, `.nvmrc` (node/nextjs only), `assets/banner.svg`.

**Branch strategy:** `master` (default), `stable` (releases). Feature: `feat/`, fixes: `fix/`.

**Commit convention:**
```
<type>(<scope>): <description>

Co-Authored-By: Claude <noreply@anthropic.com>
```

**CLAUDE.md:** Line 1 `@AGENTS.md`; Claude-only addenda ~30 lines max. Full portable policy in `AGENTS.md` (100–200 lines).

**CI:** `ci.yml` with jobs named exactly `CI` and `secret-scan`; plus `claude.yml`, `release.yml`, `dependabot.yml`. All use `ubuntu-latest` except Swift (`macos-latest`).

**Branch protection on `master`:** require 1 PR review, require `CI` status check, no direct pushes.

**Contract:** `CONTRACT_ROOT="$(cd "$CLAUDE_SKILL_DIR/../_contract" && pwd)"`. Read `$CONTRACT_ROOT/templates/INDEX.md` and stack bodies in `legacy-scaffold-templates.md` — do not invent formats. Exit gate: `app-gold` for `--type app`, `plugin-gold` for `--type plugin`.

---

## Execution

### Stage 1: Parse & Plan

Extract from args:
- `REPO_NAME` — first token before `--`
- `DESCRIPTION` — text after `--` before any flags
- `SCAFFOLD_TYPE` — value of `--type`; default `app`
- `SRC` — value of `--src` (optional)
- `TECH` — value of `--tech`; if absent, run detect-stack.sh
- If `SCAFFOLD_TYPE=plugin`, set `TECH=node` unless `--tech` explicitly set
- `CONTRACT_PROFILE=app-gold`; if `SCAFFOLD_TYPE=plugin`, set `CONTRACT_PROFILE=plugin-gold`

Print a one-line plan before proceeding:
```
Creating private repo TamirCohen28/<REPO_NAME> [<SCAFFOLD_TYPE> / <TECH>] — "<DESCRIPTION>". Scaffolding now...
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

Fan out agents IN THE SAME TURN (one message with multiple Agent tool calls). Each agent writes its files directly to `REPO_ROOT`. They operate on non-overlapping directories.

- **`--type app`:** 5 agents (A–E)
- **`--type plugin`:** 6 agents (A–F)

Pass to every agent: `REPO_NAME`, `DESCRIPTION`, `TECH`, `SCAFFOLD_TYPE`, `REPO_ROOT`, `CONTRACT_ROOT="$(cd "$CLAUDE_SKILL_DIR/../_contract" && pwd)"`.

---

**Agent A — Documentation** (writes `docs/` and `README.md`)

```
You are writing documentation for a new GitHub repo.

Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Scaffold type: SCAFFOLD_TYPE
Repo root: REPO_ROOT

Read templates from: CONTRACT_ROOT/templates/INDEX.md and legacy-scaffold-templates.md
If SCAFFOLD_TYPE=plugin, also read scaffold-requirements-plugin.md and plugin/docs/engineering/agent-kit-architecture.md.tmpl

Write these files (fully populated — no template placeholders left unfilled):

1. REPO_ROOT/README.md — hero README with Prerequisites + Quick Start (CI badge, MIT badge, Claude Code badge D97757).
   Open with: <p align="center"><img src="assets/banner.svg" alt="REPO_NAME" width="600" /></p>
   If plugin: add Install as Claude Code plugin, Build adapters (npm run build), Security model sections
1a. REPO_ROOT/assets/banner.svg — SVG hero banner (600×200). Center the repo name in Space Grotesk bold on a
    dark background (#0F1117), subtitle line in gray (#8B949E), subtle accent stripe in the project's primary
    color. Keep it minimal — name + one-line description, no clip-art. The SVG must be self-contained (no
    external font references — embed a web-safe fallback stack).
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
13. If plugin: REPO_ROOT/docs/engineering/agent-kit-architecture.md — canonical → adapters model
```

---

**Agent B — .claude/ Configuration** (writes `.claude/` and plugin manifests when `--type plugin`)

```
You are setting up the Claude Code workspace config for a new GitHub repo.

Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Scaffold type: SCAFFOLD_TYPE
Repo root: REPO_ROOT

Read templates from: CONTRACT_ROOT/templates/legacy-scaffold-templates.md
If SCAFFOLD_TYPE=plugin, also read CONTRACT_ROOT/templates/plugin/marketplace.json.tmpl and plugins/plugin/.claude-plugin/plugin.json.tmpl

Write these files:

1. REPO_ROOT/.claude/settings.json — per template, with TECH-appropriate permissions added to the allow list

2. REPO_ROOT/.claude/rules/constraints.md — project hard constraints (no secrets, no force-push to master, no .github/workflows/ edits without review, plus 3-5 TECH-appropriate constraints)

3. If SCAFFOLD_TYPE=app: REPO_ROOT/.claude/skills/run-REPO_NAME/SKILL.md — utility skill (30-50 lines)

4. If SCAFFOLD_TYPE=plugin:
   - REPO_ROOT/.claude-plugin/marketplace.json — catalog listing plugins/REPO_NAME
   - REPO_ROOT/plugins/REPO_NAME/.claude-plugin/plugin.json — skills/commands/agents/hooks paths
   - REPO_ROOT/plugins/REPO_NAME/hooks/hooks.json — empty hooks stub {}
   - REPO_ROOT/plugins/REPO_NAME/commands/.gitkeep, agents/.gitkeep (empty dirs)
```

---

**Agent C — CI/CD** (writes `.github/`)

```
You are setting up GitHub Actions CI/CD for a new repo.

Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Scaffold type: SCAFFOLD_TYPE
Repo root: REPO_ROOT

Read CI templates from: CONTRACT_ROOT/templates/github/ci.yml.tmpl and legacy-scaffold-templates.md
If SCAFFOLD_TYPE=plugin, use CONTRACT_ROOT/templates/plugin/ci-plugin.yml.tmpl (jobs CI, validate, secret-scan)

Write these files:

1. REPO_ROOT/.github/workflows/ci.yml — jobs `CI`, `secret-scan`; if plugin add `validate` job (npm run build && npm run validate)

2. REPO_ROOT/.github/workflows/claude.yml — Claude Code automation per template

3. REPO_ROOT/.github/workflows/release.yml — per template

4. REPO_ROOT/.github/pull_request_template.md — Summary, Type of change (checkbox), Test plan, Notes

5. REPO_ROOT/.github/dependabot.yml — per CONTRACT_ROOT/templates/github/dependabot.yml.tmpl

6. REPO_ROOT/CODEOWNERS — "* @TamirCohen28"; if plugin add canonical/, plugins/, scripts/, hooks/ lines
```

---

**Agent D — Root Infrastructure** (writes root config files)

```
You are writing the root infrastructure files for a new GitHub repo.

Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Scaffold type: SCAFFOLD_TYPE
Repo root: REPO_ROOT

Write these files:

1. REPO_ROOT/LICENSE — MIT license, copyright "2026 Tamir Cohen"
2. REPO_ROOT/CODE_OF_CONDUCT.md — Contributor Covenant 2.1 short form
3. REPO_ROOT/SECURITY.md — supported versions, report to tamircohen2468@gmail.com
4. REPO_ROOT/Makefile — per template for TECH (help default, install, build, test, lint, dev, clean, **agent:check**)
5. REPO_ROOT/.gitignore — comprehensive for TECH per template
6. REPO_ROOT/.nvmrc — if TECH is node, nextjs, or SCAFFOLD_TYPE=plugin; content: "22"
7. REPO_ROOT/scripts/check-agent-drift.sh — copy from CONTRACT_ROOT/templates/check-agent-drift.sh.tmpl (executable)
8. If SCAFFOLD_TYPE=plugin: REPO_ROOT/package.json from CONTRACT_ROOT/templates/plugin/package.json.tmpl (build, validate, agent:check scripts) and REPO_ROOT/package-lock.json from package-lock.json.tmpl (enables npm ci in CI)
```

---

**Agent E — Multi-agent** (writes `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/`)

```
Project: REPO_NAME
Description: DESCRIPTION
Tech stack: TECH
Scaffold type: SCAFFOLD_TYPE
Repo root: REPO_ROOT

Follow multi-agent-repo references/platform-setup.md (phases 0–1):

1. REPO_ROOT/AGENTS.md — if app: canonical portable rules (100–200 lines). If plugin: **contributor workflow** for this agent-kit repo (edit canonical/, npm run build, never edit dist/)
2. REPO_ROOT/CLAUDE.md — line 1: @AGENTS.md; Claude-only addenda only
3. REPO_ROOT/.cursor/rules/000-project.mdc — alwaysApply: true, points to AGENTS.md
4. REPO_ROOT/docs/agent-guidelines/README.md — stub index linking to AGENTS.md
```

---

**Agent F — Agent-kit core** (writes `canonical/`, build scripts, `dist/` — **only when `--type plugin`**)

```
Project: REPO_NAME
Description: DESCRIPTION
Repo root: REPO_ROOT

Read templates from: CONTRACT_ROOT/templates/plugin/

Write these files (substitute REPO_NAME, DESCRIPTION, today's date):

1. REPO_ROOT/agent-kit.config.json — from agent-kit.config.json.tmpl
2. REPO_ROOT/canonical/rules/{core,testing,security,frontend,backend}.md — from templates
3. REPO_ROOT/canonical/skills/example-skill/SKILL.md — from template
4. REPO_ROOT/canonical/templates/*.hbs.tmpl — copy Handlebars stubs for future build pipeline
5. REPO_ROOT/scripts/build.mjs — from scripts/build.mjs.tmpl (executable logic via node)
6. REPO_ROOT/scripts/validate.mjs — from scripts/validate.mjs.tmpl

Then run:
  cd REPO_ROOT && npm run build

This generates dist/codex/AGENTS.md, dist/cursor/.cursor/rules/000-core.mdc, and plugins/REPO_NAME/skills/
```

---

### Stage 4: Assemble, Contract Gate, Push, and Protect

After all agents complete (5 for app, 6 for plugin):

```bash
cd "$REPO_ROOT"
CONTRACT_ROOT="$(cd "$CLAUDE_SKILL_DIR/../_contract" && pwd)"
bash "$CONTRACT_ROOT/scripts/assert-contract.sh" "$REPO_ROOT" "$CONTRACT_PROFILE"
```

If assert-contract fails, fix gaps and re-run **before** committing. For plugin repos, ensure `npm run build` ran so dist/ exists.

```bash
git add -A
git commit -m "$(cat <<EOF
chore(scaffold): initial repo scaffold

Generated by repo-scaffold skill — passes ${CONTRACT_PROFILE} contract profile.
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

Invoke `tamirs-superpowers:skill-creator`:

**If `--type app`** — generate 2 project-specific skills:

```
Generate 2 project-specific skills for the repo at REPO_ROOT.
Save them to REPO_ROOT/.claude/skills/ and push to origin master.
```

**If `--type plugin`** — generate 1 skill into canonical source:

```
Generate 1 project-specific skill for the agent-kit at REPO_ROOT.
Save to REPO_ROOT/canonical/skills/<skill-name>/SKILL.md (portable format).
Run npm run build to sync into plugins/REPO_NAME/skills/. Push to origin master.
```

### Stage 6: Final Summary

Print:
```
✓ Repo created:       https://github.com/TamirCohen28/REPO_NAME
✓ Contract:          CONTRACT_PROFILE passed (assert-contract.sh)
✓ Scaffold type:     SCAFFOLD_TYPE
✓ Branch protection:  master — 1 required review + CI check
✓ skill-creator:      ran

Next steps (app):
  gh repo clone TamirCohen28/REPO_NAME && cd REPO_NAME && make install

Next steps (plugin):
  gh repo clone TamirCohen28/REPO_NAME && cd REPO_NAME && npm ci && npm run build
  /plugin marketplace add TamirCohen28/REPO_NAME
  /plugin install REPO_NAME@<marketplace-name-from-marketplace.json>
```
