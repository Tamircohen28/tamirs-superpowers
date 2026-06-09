---
name: repo-polish
description: "Take a personal project directory, scan for employer IP, clean it up, and scaffold world-class repo infrastructure (README, user docs, engineering docs, CI/CD, PR templates, CLAUDE.md, CHANGELOG, CONTRIBUTING, LICENSE), then upload to GitHub account TamirCohen28 after approval. Trigger on: 'polish this repo', 'prepare project for GitHub', 'make it public-ready', 'clean up and publish', 'world-class repo', 'repo-polish', or any request to prepare a project for open-source / personal GitHub release."
user-invocable: true
when_to_use: "User wants to prepare a personal project for GitHub publication — scan for employer IP, add docs, set up CI/CD, upload to TamirCohen28."
argument-hint: "<path-to-project-directory>"
model: claude-sonnet-4-6
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
metadata:
  capability: repo-polish
  provider: developer-workflow
  platforms:
    - claude
  tags:
    - open-source
    - github
    - docs
    - ci-cd
    - ip-scan
    - cleanup
  updated-date: "2026-06-09"
---

# repo-polish

Prepare a personal project for world-class open-source publication on GitHub under **TamirCohen28**.

## Reference standard

Model every decision on `/Users/tamircohen/Projects/production-master`, which has:
- Hero `README.md` with badges, feature highlights, prerequisites, quick start
- `docs/user/` — concepts, quick-start, troubleshooting, guides, reference
- `docs/engineering/` — architecture, build-and-release, decisions (ADRs), guides, reference
- `docs/CHANGELOG.md`, `docs/CONTRIBUTING.md`
- `.github/` — `ci.yml`, `release.yml`, `dependabot.yml`, PR template, issue templates
- `CLAUDE.md` — Claude Code guidance
- `.claude/rules/` — governance rules
- `assets/` — banner and visual assets
- `CODEOWNERS`, `Makefile`, `LICENSE`

## Required execution flow

### Step 0 — Resolve project directory

Parse `$ARGUMENTS`. If it's a valid directory path, use it. If empty or not a directory:
```
Ask: "Which project directory should I polish? (provide absolute path)"
```
Stop until you have a real directory.

Set `PROJECT_DIR` to the absolute canonical path:
```bash
PROJECT_DIR="$(cd "$ARGUMENTS" && pwd)"
```

### Step 1 — Survey the project

Read enough to understand what was built:
```bash
# Structure overview
find "$PROJECT_DIR" -maxdepth 3 -not -path '*/node_modules/*' -not -path '*/.git/*' \
  -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/__pycache__/*' | sort

# Key files
for f in README.md package.json pyproject.toml go.mod Cargo.toml; do
  [[ -f "$PROJECT_DIR/$f" ]] && echo "=== $f ===" && head -40 "$PROJECT_DIR/$f"
done
```

Note: project name, language/stack, primary purpose, existing docs, existing CI.

### Step 2 — Employer IP scan

Run the scanner. This is MANDATORY before any other action.

```bash
# Locate the scanner in plugin cache or local skills
SCANNER=$(find ~/.claude/plugins/cache/tamirs-superpowers -name "ip-scan.sh" 2>/dev/null | sort -V | tail -1)
SCANNER="${SCANNER:-$HOME/.claude/skills/repo-polish/ip-scan.sh}"
bash "$SCANNER" "$PROJECT_DIR"
```

**Report to the user immediately:**
- Paste the full scanner output
- For each finding: the file path (relative to project), the matching line, and what category of employer IP it is
- Summarize: "Found X employer IP hits in Y files. Here's what needs to change:"

**Do NOT proceed to Step 3 until the user has acknowledged the employer IP findings.**

### Step 3 — Plan the polish

Produce a concise plan. Show the user:

1. **Employer IP remediation** — the exact changes (find/replace, line deletions) needed to remove each finding
2. **File cleanup** — files that should be removed (build artifacts, `.DS_Store`, temp files, editor cruft, internal config references)
3. **Docs to create** — which README/docs/CI files are missing vs already present
4. **GitHub repo settings** — name, description, visibility (default: public), topics

Example plan output format:
```
## Employer IP to remove
- README.md:8 — replace internal badge URL with public equivalent
- .github/workflows/ci.yml:15 — remove `runs-on: [self-hosted]`, use `ubuntu-latest`
- (etc.)

## Files to delete
- .falconrc.json (internal CI config — not needed publicly)
- .mcp.json (internal MCP config)
- (etc.)

## Docs to create / update
- README.md — rewrite hero section, remove internal badges
- docs/user/README.md — new
- (etc.)

## GitHub repo
- Repo name: <derived from project>
- Description: <one-liner>
- Visibility: public
```

**PAUSE and ask the user:**
> "Does this plan look right? Should I adjust anything before I start?"

Wait for explicit approval ("yes", "go ahead", "looks good", etc.) before Step 4.

### Step 4 — Apply employer IP fixes

For each employer IP finding from Step 2:
- Use `Edit` to make the precise change (never rewrite whole files for a small fix)
- Remove files that are purely internal config (internal CI configs, internal MCP configs, employer-specific scripts)
- Replace internal CI runner `runs-on: [self-hosted]` with `runs-on: ubuntu-latest` in any existing workflows
- Replace all `github.com/<employer-org>/<name>` with `github.com/TamirCohen28/<name>`
- Remove internal badge URLs (internal Slack badges, internal issue tracker badges)

After completing all fixes, re-run the scanner to confirm clean:
```bash
SCANNER=$(find ~/.claude/plugins/cache/tamirs-superpowers -name "ip-scan.sh" 2>/dev/null | sort -V | tail -1)
SCANNER="${SCANNER:-$HOME/.claude/skills/repo-polish/ip-scan.sh}"
bash "$SCANNER" "$PROJECT_DIR"
```

If any employer IP remains, fix it before continuing.

### Step 5 — Scaffold world-class repo infrastructure

Analyze what already exists and only create what's missing. Never overwrite a good existing file — augment or regenerate only if poor quality.

#### 5a. README.md

Generate a README.md modeled on production-master's structure:
- `<p align="center">` hero image placeholder (use a shields.io badge as stand-in if no banner asset)
- Project name as `# Title`
- Badges row: CI status badge (pointing to new GitHub Actions), GitHub license badge
- One-paragraph hook: what this is and who it's for
- **Feature highlights** — 4-6 bullets with bolded lead words
- **Prerequisites** — runtime, tools, accounts required
- **Quick Start** — 3-5 steps to go from zero to running
- **Documentation** → link to `docs/`
- **Contributing** → link to `docs/CONTRIBUTING.md`
- **License** line

Use real project content — never write placeholder text like "Your project description here."

#### 5b. docs/ tree

Create the following structure, writing each file with real content derived from the project:

```
docs/
  README.md           — doc map (index of all docs, audience guide)
  CHANGELOG.md        — ## [Unreleased] header + standard Keep a Changelog format
  CONTRIBUTING.md     — how to contribute, PR workflow, code style

  user/
    README.md         — user doc index
    concepts.md       — what the project does, key concepts
    quick-start.md    — first-run walkthrough (5 minutes or less)
    troubleshooting.md — common failures + fixes

  engineering/
    README.md         — engineering doc index (fast-lane table)
    architecture/
      overview.md     — what the system is, main components, data flow
    build-and-release/
      development-workflow.md  — how to contribute code
      ci-workflow.md  — what CI checks
    decisions/
      README.md       — ADR index and format
      001-<first-key-decision>.md — first ADR
```

Write every file with project-specific content. The architecture overview must explain the actual code. The ADR must document a real design decision visible in the code.

#### 5c. .github/ infrastructure

**CI workflow** (`.github/workflows/ci.yml`):
- Trigger: pull_request, push to main, workflow_dispatch
- Jobs: `lint`, `test`, `validate`
- Use `ubuntu-latest` (not self-hosted)
- Include secret scan job (grep for high-signal patterns)
- Detect project type and add the right test command:
  - Node.js: `npm test` or `yarn test`
  - Python: `pytest` or `python -m unittest`
  - Go: `go test ./...`
  - Shell: `shellcheck`
  - Generic: `make test` if Makefile exists

**Release workflow** (`.github/workflows/release.yml`):
- Manual trigger (`workflow_dispatch`) with `version` input
- Validates, creates git tag, creates GitHub Release

**Dependabot** (`.github/dependabot.yml`):
- Enable for the right ecosystem (npm, pip, github-actions, etc.)

**PR template** (`.github/pull_request_template.md`):
```markdown
## Summary
<!-- What does this PR do? 1-3 bullets. -->
-

## Test plan
- [ ] Tests pass locally
- [ ] Tested manually

## Documentation
- [ ] CHANGELOG.md updated under [Unreleased]

Closes #
```

**Issue templates** (`.github/ISSUE_TEMPLATE/`):
- `bug_report.yml` — structured bug report
- `feature_request.yml` — feature request form

#### 5d. CLAUDE.md

Generate a `CLAUDE.md` at the repo root that gives future Claude Code sessions:
- Project overview (1 paragraph)
- Key file locations (table: path → purpose)
- Build command
- Test command
- Commit message convention
- Hard constraints (things Claude should never change)

#### 5e. Makefile

If no Makefile exists, create a minimal one with targets:
- `install` — install dependencies
- `test` — run tests
- `lint` — run linter
- `build` — build/compile (if applicable)
- `clean` — remove build artifacts

#### 5f. LICENSE

If no LICENSE file exists, create MIT license with current year and "Tamir Cohen" as author.

#### 5g. .gitignore

If no `.gitignore` exists or it's sparse, generate a comprehensive one for the detected stack(s).

#### 5h. CODEOWNERS

Create `.github/CODEOWNERS`:
```
* @TamirCohen28
```

### Step 6 — Report what was done

Produce a summary table:
```
| File | Action |
|------|--------|
| README.md | Rewrote hero section, removed internal badges |
| docs/user/README.md | Created |
| .github/workflows/ci.yml | Created |
| internal-config.json | Deleted (internal CI config) |
| ... | ... |
```

Then ask:
> "Everything looks good. Ready to create the GitHub repo under **TamirCohen28** and push?
> Repo name: `<name>`, Visibility: public.
> Type 'yes' to proceed or tell me what to adjust."

**Do NOT push to GitHub until the user types explicit approval.**

### Step 7 — GitHub upload

Only execute after explicit user approval.

```bash
cd "$PROJECT_DIR"

# Ensure git repo exists
if [[ ! -d .git ]]; then
  git init
  git add -A
  git commit -m "Initial commit"
fi

# Create GitHub repo under TamirCohen28
REPO_NAME="$(basename "$PROJECT_DIR" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
DESCRIPTION="<one-liner from README>"

gh repo create "TamirCohen28/$REPO_NAME" \
  --public \
  --description "$DESCRIPTION" \
  --source . \
  --remote origin \
  --push

echo "Pushed to: https://github.com/TamirCohen28/$REPO_NAME"
```

If the user wants private:
```bash
gh repo create "TamirCohen28/$REPO_NAME" --private ...
```

After pushing, add GitHub Topics that match the project:
```bash
gh api repos/TamirCohen28/$REPO_NAME/topics \
  --method PUT \
  --field names[]="<tag1>" \
  --field names[]="<tag2>"
```

Print the final repo URL and a brief checklist of what to do next (add a banner image, set up branch protection, etc.).

## Quality standards

- Every doc file must contain real content derived from the project — no placeholder text
- README must have at least one working command in Quick Start
- CI must run the project's actual test command (don't invent a test command that doesn't work)
- Employer IP scan must come back clean before Step 7
- Never expose internal credentials, keys, or access tokens

## What NOT to do

- Do not rewrite files that are already high quality — enhance or leave them
- Do not use `runs-on: [self-hosted]` in any CI workflow
- Do not add employer-specific badges, internal Slack links, internal issue tracker links, or internal service URLs
- Do not push to GitHub without explicit user approval
- Do not use template placeholder text in any generated file
