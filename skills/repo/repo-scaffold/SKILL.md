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
  updated-date: '2026-08-19'
  tamirs:
    visibility: public
    category: repo
    capabilities:
      required: [shell, git]
      optional: [github_cli]
    role: implementer
    updated-date: "2026-08-19"
    validation-tier: 3

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

**README structure:** centered hero banner (`<p align="center"><img src="assets/banner.png" alt="REPO_NAME" width="600" /></p>` — `.png`, `.jpg`, `.webp` or `.svg`), badge rows, elevator pitch, features, **Prerequisites**, Quick Start, architecture, docs links, one-line text footer.

**Three README rules that are checked, not suggested** (`_contract/scripts/check-readme-branding.sh`, gaps S1-11..S1-14 — full statement in `_contract/references/readme-badges.md` and `readme-banner.md`):

1. **Every badge anchor on ONE line:** `<a href="..."><img ... /></a>`. Breaking the anchor across lines puts whitespace *inside* it, which GitHub renders as underlined link text between badges. Never reformat a badge row "for readability".
2. **No emoji above the first `## ` heading** — not in the H1, the tagline, the badges, or the banner. Body prose below it is free.
3. **AI-target badge versions are derived, never typed:** read `targets.<key>.validated_against` from `docs/engineering/build-and-release/platform-targets.json`. Copying a version out of a doc or another repo is the defect this check exists for.

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

**Root file checklist:** `AGENTS.md`, `CLAUDE.md` (line 1: `@AGENTS.md`), `LICENSE`, `Makefile` (with `agent:check`), `.gitignore`, `CODEOWNERS`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `scripts/check-agent-drift.sh`, `.cursor/rules/000-project.mdc`, `core/capabilities/{schema,platforms}.json`, `.nvmrc` (node/nextjs only), `assets/banner.{png|jpg|webp|svg}`.

**Branch strategy:** whatever `gh repo create` made the default (do not assume — resolve it once with `DEFAULT_BRANCH="$(bash "$CONTRACT_ROOT/../../dev-workflow/_shared/scripts/default-branch.sh")"` after the first fetch, and use `$DEFAULT_BRANCH` everywhere below), plus `stable` (releases). Feature: `feat/`, fixes: `fix/`. Generated workflows carry **no** `on.*.branches` filter, so they cannot be desynced from the name.

**Commit convention:**
```
<type>(<scope>): <description>

Co-Authored-By: Claude <noreply@anthropic.com>
```

**CLAUDE.md:** Line 1 `@AGENTS.md`; Claude-only addenda ~30 lines max. Full portable policy in `AGENTS.md` (100–200 lines).

**CI:** `ci.yml` with jobs named exactly `CI` and `secret-scan`; plus `claude.yml`, `release.yml`, `dependabot.yml`. All use `ubuntu-latest` except Swift (`macos-latest`).

**Default-branch governance:** applied from `config/github/repository-policy.json` by `scripts/github-policy.sh`, as **branch rulesets** — not classic branch protection, which 404s on a rulesets-governed repo. The policy targets the default branch through GitHub's `~DEFAULT_BRANCH` magic ref, so no branch name is ever hardcoded. Read the rules, the required status-check contexts, the enforcement values and the approving-review count out of that file — never restate or hardcode any of them here. Two things are worth knowing before you read it, because both are counter-intuitive and both are deliberate: the approving-review requirement is set for a **solo contributor** and is paired with review-thread resolution rather than an approval count (an approval requirement deadlocks a one-person repo), and `strict_required_status_checks_policy` is **false** and must stay false — it is not a tunable. With it on, every merge marks every other open branch out of date and the one-objective/one-PR flow stalls behind a serial rebase queue.

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
   Put every badge anchor on ONE line — <a href="..."><img ... /></a>. A newline inside the anchor is link
   text and GitHub underlines it between the badges. No emoji anywhere above the first "## " heading.
   Close with a one-line text footer after a --- rule: MIT © [Tamir Cohen](https://github.com/Tamircohen28)
   If plugin: add Install as Claude Code plugin, Build adapters (npm run build), Security model sections
1a. REPO_ROOT/assets/banner.svg — hero banner. READ CONTRACT_ROOT/references/readme-banner.md FIRST and
    follow it; it is the art direction and the pass/fail bar, and this line is only the summary.

    Design a GRAPHIC, not a wordmark. Pick one visual motif that says what the project does (a pipeline,
    a hub fanning out to targets, layered gates, an instrument) and build the picture around it:
    wordmark left, motif right; three depth planes (ground, motif, accent) using overlap, slight
    rotation, opacity falloff and one soft radial glow; a gradient on the hero object; a faint grid or
    circuit substrate at ~6% contrast; near-black ground (#0B0E14–#111726), near-white type, two brand
    hues. 1200x400 viewBox. Self-contained — no external font or image reference.

    It must PASS, and check-readme-branding.sh decides: >= 16 non-text shapes, <= 3 <text> elements,
    >= 5 shapes per text element, at least one gradient/filter/mask/opacity, a <title> and a <desc>
    whose sentence names the motif and its relation to the project, and ZERO emoji codepoints (emoji
    clip-art renders as tofu). Worked examples to copy the structure of:
    CONTRACT_ROOT/fixtures/scaffold-gold/assets/banner.svg and .../scaffold-plugin-gold/assets/banner.svg.

    A raster is equally acceptable and often better: 1280x640 png/jpg at assets/banner.png, >= 20 KB,
    >= 800px wide. Use one when you can actually render an image; otherwise author the SVG.

    Verify before finishing: bash CONTRACT_ROOT/scripts/check-readme-branding.sh REPO_ROOT
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

2. REPO_ROOT/.claude/rules/constraints.md — project hard constraints (no secrets, no force-push to the default branch, no .github/workflows/ edits without review, plus 3-5 TECH-appropriate constraints)

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

5. REPO_ROOT/.github/dependabot.yml — generate with only the ecosystems present in this repo.
   Always include a `github-actions` block (monthly schedule, grouped, limit 2, label: chore).
   Add an `npm` block when TECH is `node` or `nextjs`. Add a `pip` block when TECH is `python`.
   Conservative settings for all npm/pip blocks: weekly schedule (monday 09:00), group all minor+patch
   into one PR per ecosystem, ignore automatic major-version PRs, `open-pull-requests-limit: 3`, label: chore.
   Never use daily schedules. Never open one PR per dependency. Reference CONTRACT_ROOT/templates/github/dependabot.yml.tmpl for exact field names.

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
8. If TECH is node or nextjs: REPO_ROOT/vitest.config.ts — minimal config with `passWithNoTests: true` so CI never fails when no test files exist yet:
   ```typescript
   import { defineConfig } from 'vitest/config';
   export default defineConfig({
     test: { environment: 'node', passWithNoTests: true },
   });
   ```
9. If SCAFFOLD_TYPE=plugin: REPO_ROOT/package.json from CONTRACT_ROOT/templates/plugin/package.json.tmpl (build, validate, agent:check scripts) and REPO_ROOT/package-lock.json from package-lock.json.tmpl (enables npm ci in CI)
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

1. REPO_ROOT/AGENTS.md — if app: canonical portable rules (100–200 lines). If plugin: **contributor workflow** for this agent-kit repo (edit canonical/, npm run build, never edit dist/).
   AGENTS.md must include a "## Dependency management" section with these rules:
   - Configure dependabot.yml with only the ecosystems present in this repo.
   - Weekly cadence for npm/pip, monthly for GitHub Actions. Never daily.
   - Group minor and patch updates into one PR per ecosystem (groups).
   - Block automatic major-version PRs (ignore: version-update:semver-major).
   - Set open-pull-requests-limit: 3 or lower. Never one PR per dependency.
   - Do not blindly merge Dependabot PRs — require CI to pass first.
2. REPO_ROOT/CLAUDE.md — line 1: @AGENTS.md; Claude-only addenda only
3. REPO_ROOT/.cursor/rules/000-project.mdc — alwaysApply: true, points to AGENTS.md
4. REPO_ROOT/docs/agent-guidelines/README.md — stub index linking to AGENTS.md
5. REPO_ROOT/core/capabilities/schema.json and REPO_ROOT/core/capabilities/platforms.json —
   from CONTRACT_ROOT/templates/core/capabilities/*.tmpl, substituting GITHUB_OWNER and
   REPO_NAME. This is the capability registry: the ONE place the repo states which
   harnesses it targets and what each can do. Do not restate a platform's support in
   AGENTS.md, README, or a second JSON file — everything else derives from this file.
   Targets: claude_code, claude_desktop (runtime surface of claude_code — no separate
   manifest), codex, cursor, gemini_cli, opencode.
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

This generates one thin adapter per target, all from canonical/:
  - plugins/REPO_NAME/skills/               → Claude Code + Claude Desktop
  - dist/codex/AGENTS.md, dist/codex/.codex/config.toml → Codex CLI
  - dist/cursor/.cursor/rules/000-core.mdc  → Cursor
  - dist/gemini/gemini-extension.json, dist/gemini/GEMINI.md → Gemini CLI
  - dist/opencode/opencode.json             → OpenCode

Never hand-edit an adapter and never duplicate a rule per platform. npm run validate
proves the tree matches what build would produce.
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
# Push the branch the local repo is actually on. Hardcoding a name here pushed
# to a branch `gh repo create` never made, leaving CI that never fired.
git push -u origin HEAD
```

Enable PR auto-merge (required for `start-dev` / `pr-dev`):

```bash
bash "$CONTRACT_ROOT/scripts/enable-repo-merge-settings.sh" "TamirCohen28/$REPO_NAME"
```

Apply the canonical repository policy (branch rulesets on the default branch):

```bash
PLUGIN_ROOT="$(cd "$CONTRACT_ROOT/../../.." && pwd)"
bash "$PLUGIN_ROOT/scripts/github-policy.sh" apply --repo "TamirCohen28/$REPO_NAME"
```

This replaced `ensure-branch-protection.sh`, which wrote classic `branches/*/protection` with one literal `CI` context and a hardcoded default-branch name. The old script remains only as a deprecating shim onto this command.

**If it cannot run, the scaffold still succeeded.** Repository creation must never fail because branch governance could not be applied — the local tree, the docs, the CI and the contract gate are all real work that is already done and pushed. `github-policy.sh apply` exits non-zero when `gh` is missing, unauthenticated, or lacks repository-administration permission, and when there is no TTY to confirm at it prints the plan and writes nothing. Treat every one of those as a **degraded success**: continue to Stage 5, and report verbatim in the Stage 6 summary —

> Local repository configured. GitHub repository policy was not applied because GitHub administration access is unavailable.

— followed by the exact command the user can run themselves once access exists:

```bash
bash scripts/github-policy.sh apply --repo TamirCohen28/$REPO_NAME
```

Do not retry, do not fall back to classic branch protection, and do not silently mark the repo as protected.

### Stage 5: Run skill-creator

Invoke `tamirs-superpowers:skill-creator`:

**If `--type app`** — generate 2 project-specific skills:

```
Generate 2 project-specific skills for the repo at REPO_ROOT.
Save them to REPO_ROOT/.claude/skills/ and push the current branch (`git push -u origin HEAD`).
```

**If `--type plugin`** — generate 1 skill into canonical source:

```
Generate 1 project-specific skill for the agent-kit at REPO_ROOT.
Save to REPO_ROOT/canonical/skills/<skill-name>/SKILL.md (portable format).
Run npm run build to sync into plugins/REPO_NAME/skills/. Push the current branch (`git push -u origin HEAD`).
```

### Stage 6: Final Summary

Print:
```
✓ Repo created:       https://github.com/TamirCohen28/REPO_NAME
✓ Contract:          CONTRACT_PROFILE passed (assert-contract.sh)
✓ Scaffold type:     SCAFFOLD_TYPE
✓ Repository policy:  applied from config/github/repository-policy.json (or: NOT APPLIED — see above)
✓ skill-creator:      ran

Next steps (app):
  gh repo clone TamirCohen28/REPO_NAME && cd REPO_NAME && make install

Next steps (plugin):
  gh repo clone TamirCohen28/REPO_NAME && cd REPO_NAME && npm ci && npm run build
  /plugin marketplace add TamirCohen28/REPO_NAME
  /plugin install REPO_NAME@<marketplace-name-from-marketplace.json>
```
