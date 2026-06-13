---
name: repo-polish
description: "Use when preparing a personal project for public GitHub — scan employer IP, scaffold docs/CI, publish. Triggers: 'polish this repo', 'prepare for GitHub', 'make public-ready', 'repo-polish', 'open-source this', 'scan for employer IP'."
disable-model-invocation: true
user-invocable: true
when_to_use: "User wants to prepare a personal project for GitHub publication — scan for employer IP, add docs, set up CI/CD, upload to GitHub."
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
  - Skill
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
  updated-date: "2026-06-13"
---

# repo-polish

Prepare a personal project for world-class open-source publication on GitHub.

## Why this skill exists

Publishing a project directly from a work environment almost always leaks employer IP: internal CI runners (`runs-on: [self-hosted]`), internal service URLs, hardcoded tokens, or references to private GitHub orgs. Beyond that, most personal projects lack the infrastructure (README, docs tree, CI, PR templates, CLAUDE.md) that signals a maintained, trustworthy project to contributors and future employers. This skill automates both the forensic cleanup and the scaffolding in a gated, user-approved flow — so nothing lands on GitHub without review.

## Internal skills

Quality audits are delegated to companion skills — invoke them with the **Skill tool**, not by reimplementing their checklists inline:

| Skill | Role | When repo-polish invokes it |
|-------|------|----------------------------|
| `repo-review` | Repo health audit (read-only report) | After scaffolding (Step 6a); optional early pass after Step 1 if repo is already large |
| `docs-review` | Doc sweep — fixes README + `docs/**` in place | After docs exist (Step 6b); re-run if Step 6a fixes touched docs |
| `changelog-review` | Claude Code plugin pattern audit | Step 6c — only if project has `.claude/` or is a Claude Code plugin |

All three are internal-only (`user-invocable: false`). Users run `repo-polish`; these skills run automatically during Step 6.

**Before every internal skill invocation:**

```bash
cd "$PROJECT_DIR"
```

Pass `$PROJECT_DIR` as context so the child skill audits the target project, not the plugin cache.

**Mandatory Step 6 order:** `repo-review` → apply P1 repo fixes → `docs-review` → apply doc fixes → `changelog-review` (if plugin) → apply P1 plugin-doc fixes. Do not skip to Step 7 until all invoked audits pass or remaining findings are explicitly P2/P3 deferred.

---

### Step 0 — Resolve project directory

Parse `$ARGUMENTS`. If it is a valid directory path, use it. If empty or invalid:

```
Ask: "Which project directory should I polish? (provide absolute path)"
```

Stop until you have a real directory, then canonicalize:

```bash
PROJECT_DIR="$(cd "$ARGUMENTS" && pwd)"
```

### Step 1 — Survey the project

```bash
# Structure overview (skip generated dirs)
find "$PROJECT_DIR" -maxdepth 3 \
  -not -path '*/node_modules/*' -not -path '*/.git/*' \
  -not -path '*/dist/*' -not -path '*/build/*' \
  -not -path '*/__pycache__/*' | sort

# Key manifest files
for f in README.md package.json pyproject.toml go.mod Cargo.toml; do
  [[ -f "$PROJECT_DIR/$f" ]] && printf '=== %s ===\n' "$f" && head -40 "$PROJECT_DIR/$f"
done
```

Note: project name, language/stack, primary purpose, existing docs, existing CI.

### Step 2 — Employer IP scan (MANDATORY before anything else)

Locate `ip-scan.sh` relative to the skill directory, then run it:

```bash
# ip-scan.sh lives in the same directory as this SKILL.md
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$SKILL_DIR/ip-scan.sh"

# Fallback: search plugin cache if skill dir resolution fails
if [[ ! -x "$SCANNER" ]]; then
  SCANNER=$(find "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins}" -name "ip-scan.sh" 2>/dev/null | sort -V | tail -1)
fi

bash "$SCANNER" "$PROJECT_DIR"
```

**Report to the user immediately:**
- Full scanner output
- For each finding: relative file path, matching line, and category of employer IP
- Summary: "Found X employer IP hits in Y files. Here's what needs to change:"

**Do NOT proceed to Step 3 until the user has acknowledged the employer IP findings.**

### Step 3 — Plan the polish

Show the user a concise plan covering:

1. **Employer IP remediation** — exact changes (find/replace, line deletions) for each finding
2. **File cleanup** — build artifacts, `.DS_Store`, temp files, editor cruft, internal configs
3. **Docs to create** — which README/docs/CI files are missing vs already present
4. **GitHub repo settings** — name, description, visibility (default: public), topics

Example plan format:
```
## Employer IP to remove
- README.md:8 — replace internal badge URL with public equivalent
- .github/workflows/ci.yml:15 — remove `runs-on: [self-hosted]`, use `ubuntu-latest`

## Files to delete
- .falconrc.json (internal CI config)

## Docs to create / update
- README.md — rewrite hero section
- docs/user/README.md — new

## GitHub repo
- Repo name: <derived>
- Description: <one-liner>
- Visibility: public
```

**PAUSE — ask the user:** "Does this plan look right? Should I adjust anything before I start?"

Wait for explicit approval before Step 4.

### Step 4 — Apply employer IP fixes

For each finding from Step 2:
- Use `Edit` for precise changes — never rewrite whole files for a small fix
- Delete files that are purely internal config (internal CI configs, employer-specific scripts)
- Replace `runs-on: [self-hosted]` with `runs-on: ubuntu-latest` in all workflows
- Replace `github.com/<employer-org>/` with `github.com/<your-github-username>/`
- Remove internal badge URLs (internal Slack badges, internal issue tracker links)

Re-run the scanner to confirm clean before continuing:

```bash
bash "$SCANNER" "$PROJECT_DIR"
```

If any employer IP remains, fix it before Step 5.

### Step 4b — Delete stale remote branches

After IP fixes are clean, prune merged and closed-PR branches from the remote.

```bash
cd "$PROJECT_DIR"

REMOTE=$(git remote | head -1)
DEFAULT_BRANCH=$(git remote show "$REMOTE" 2>/dev/null | grep 'HEAD branch' | cut -d: -f2 | tr -d ' ')
echo "Default branch: $DEFAULT_BRANCH  Remote: $REMOTE"

# Branches fully merged into the default branch
MERGED=$(git branch -r --merged "origin/$DEFAULT_BRANCH" \
  | grep -v "origin/HEAD\|origin/$DEFAULT_BRANCH" \
  | sed 's|origin/||' | tr -d ' ')

# Branches whose PRs are already merged or closed (requires gh)
PR_CLOSED=()
if command -v gh &>/dev/null; then
  while IFS= read -r branch; do
    git ls-remote --exit-code origin "$branch" &>/dev/null && PR_CLOSED+=("$branch")
  done < <(gh pr list --state closed --base "$DEFAULT_BRANCH" --json headRefName \
    --jq '.[].headRefName' 2>/dev/null || true)
fi

TO_DELETE=()
for b in $MERGED "${PR_CLOSED[@]:-}"; do
  [[ -z "$b" ]] && continue
  # Never delete the default branch or common protected names
  [[ "$b" == "$DEFAULT_BRANCH" || "$b" == "main" || "$b" == "master" || "$b" == "dev" ]] && continue
  TO_DELETE+=("$b")
done

# Deduplicate
mapfile -t TO_DELETE < <(printf '%s\n' "${TO_DELETE[@]:-}" | sort -u)

if [[ ${#TO_DELETE[@]} -eq 0 ]]; then
  echo "No stale remote branches found."
else
  echo "Stale branches to delete from remote:"
  printf '  - %s\n' "${TO_DELETE[@]}"
  for branch in "${TO_DELETE[@]}"; do
    git push "$REMOTE" --delete "$branch" && echo "  Deleted: $branch" || echo "  Failed to delete: $branch"
  done
fi
```

Report what was deleted (or "none") to the user before continuing.

### Step 5 — Scaffold world-class repo infrastructure

Analyze what already exists. Only create what is missing. Never overwrite a high-quality existing file — augment or regenerate only if poor quality.

#### 5a. README.md

Structure:
- `<p align="center">` hero image placeholder (shields.io badge as stand-in if no banner)
- Project name as `# Title`
- Badges row: CI status, license
- One-paragraph hook: what this is and who it is for
- **Feature highlights** — 4–6 bullets with bolded lead words
- **Prerequisites** — runtime, tools, accounts required
- **Quick Start** — 3–5 steps, zero to running
- **Documentation** → link to `docs/`
- **Contributing** → link to `docs/CONTRIBUTING.md`
- **License** line

Use real project content. Never write placeholder text.

#### 5b. docs/ tree

```
docs/
  README.md                          doc map — index of all docs
  CHANGELOG.md                       ## [Unreleased] header, Keep a Changelog format
  CONTRIBUTING.md                    PR workflow, code style, how to contribute

  user/
    README.md                        user doc index
    concepts.md                      key concepts
    quick-start.md                   first-run walkthrough (≤5 min)
    troubleshooting.md               common failures + fixes

  engineering/
    README.md                        engineering doc index
    architecture/
      overview.md                    system components, data flow
    build-and-release/
      development-workflow.md        how to contribute code
      ci-workflow.md                 what CI checks
    decisions/
      README.md                      ADR index and format
      001-<first-key-decision>.md    first ADR based on actual design choice
```

Every file must contain project-specific content derived from reading the actual code.

#### 5c. .github/ infrastructure

**CI workflow** (`.github/workflows/ci.yml`):
```yaml
on:
  pull_request:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # detect project type and add appropriate linter
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # Node.js: npm test | Python: pytest | Go: go test ./... | Shell: shellcheck
  secret-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Scan for secrets
        run: |
          grep -rn \
            -E "['\"]?[A-Za-z_]*(SECRET|TOKEN|PASSWORD|API_KEY)['\"]?\s*[:=]\s*['\"][^'\"]{8,}" \
            --include="*.yml" --include="*.json" --include="*.env*" \
            --exclude-dir=.git . && echo "SECRETS FOUND — fix before merge" && exit 1 || exit 0
```

**Release workflow** (`.github/workflows/release.yml`): manual `workflow_dispatch` with `version` input, validates, creates git tag, creates GitHub Release.

**Dependabot** (`.github/dependabot.yml`): enable for detected ecosystem (npm, pip, github-actions).

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

**Issue templates** (`.github/ISSUE_TEMPLATE/`): `bug_report.yml` and `feature_request.yml`.

#### 5d. CLAUDE.md

Generate at repo root with: project overview (1 paragraph), key file locations table, build command, test command, commit message convention, and hard constraints (things Claude must never change).

#### 5e. Makefile

If absent, create with targets: `install`, `test`, `lint`, `build` (if applicable), `clean`.

#### 5f. LICENSE

If absent, create MIT license with current year and the project owner's name.

#### 5g. .gitignore

If absent or sparse, generate a comprehensive one for the detected stack.

#### 5h. CODEOWNERS

```
* @<your-github-username>
```

### Step 6 — Quality audits (mandatory)

Run specialist audit skills against `$PROJECT_DIR`. Address **all P1 findings** before Step 7. P2/P3 may be noted in the summary as deferred.

```bash
cd "$PROJECT_DIR"
```

#### 6a. Repository health (repo-review)

Invoke first — surfaces structural issues before doc polish:

```
Skill("repo-review")
```

Context to pass: `$PROJECT_DIR` is the repo root. The skill writes a read-only report to `docs/repo-review-<date>.md`.

After the report returns:
1. Read every **P1** finding (empty dirs, CI-breaking layout, misplaced governance files).
2. Apply fixes in `$PROJECT_DIR` using `Edit` — repo-review does not edit files itself.
3. If P1 fixes changed structure or deleted stale files, note them for 6b.

#### 6b. Documentation quality (docs-review)

Invoke after Step 5 scaffolding (and after 6a P1 fixes) so README + `docs/**` exist:

```
Skill("docs-review")
```

Context to pass: audit `$PROJECT_DIR/README.md` and `$PROJECT_DIR/docs/**`. Optional argument: `docs/**` if the tree is large.

`docs-review` fixes docs in place. After it returns:
1. Review its summary for remaining broken links or stale counts.
2. Fix any P1 items it flagged but did not auto-fix.
3. If you applied manual doc fixes, re-run `Skill("docs-review")` once to confirm clean.

#### 6c. Claude Code pattern audit (changelog-review)

**Only** if the project is a Claude Code plugin or has a `.claude/` directory:

```
Skill("changelog-review")
```

Pass as review input: `.claude/`, `plugin.json` or `.claude-plugin/plugin.json`, `SKILL.md` files, `hooks/hooks.json`, and any `.mcp.json`.

Apply P1 findings (invalid frontmatter, stale hook wiring, broken skill paths) before continuing.

#### 6d. Audit gate

Before Step 7, confirm:

- [ ] `repo-review` invoked — all P1 repo findings fixed or explicitly deferred with reason
- [ ] `docs-review` invoked — README + docs link-clean; no stray plan files tracked
- [ ] `changelog-review` invoked if plugin — or N/A noted in summary

If any P1 item remains open, do not ask the user to push to GitHub.

### Step 7 — Report and confirm

Produce a summary table:

| File | Action |
|------|--------|
| README.md | Rewrote hero section, removed internal badges |
| docs/user/README.md | Created |
| .github/workflows/ci.yml | Created |
| internal-config.json | Deleted (internal CI config) |

Then ask:
> "Everything looks good. Ready to create the GitHub repo and push?
> Repo name: `<name>`, Visibility: public.
> Type 'yes' to proceed or tell me what to adjust."

**Do NOT push to GitHub until the user types explicit approval.**

### Step 8 — GitHub upload (after explicit approval only)

```bash
cd "$PROJECT_DIR"

# Initialize git if needed
if [[ ! -d .git ]]; then
  git init
  git add .
  git commit -m "Initial commit"
fi

# Derive repo name
REPO_NAME="$(basename "$PROJECT_DIR" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
DESCRIPTION="$(grep -m1 '.' README.md | sed 's/^#* *//')"

# Create and push
gh repo create "<your-github-username>/$REPO_NAME" \
  --public \
  --description "$DESCRIPTION" \
  --source . \
  --remote origin \
  --push

echo "Pushed to: https://github.com/<your-github-username>/$REPO_NAME"

# Add topics
gh api "repos/<your-github-username>/$REPO_NAME/topics" \
  --method PUT \
  --field names[]="<tag1>" \
  --field names[]="<tag2>"
```

For a private repo, replace `--public` with `--private`.

Print the final repo URL and a brief next-steps checklist (add a banner image, enable branch protection, set up Dependabot alerts).

## Hard rules

- **Always invoke `repo-review` and `docs-review` in Step 6** — do not skip audits or substitute a manual skim
- **Apply all P1 audit findings** before Step 7; defer P2/P3 only with explicit user-visible note
- **Never push to GitHub without explicit user approval** — "yes", "go ahead", or equivalent
- **Employer IP scan must be clean** before writing the final report or pushing
- **Never use `runs-on: [self-hosted]`** in any generated CI workflow — always `ubuntu-latest`
- **Never write placeholder text** in any generated file ("Your description here", "TODO: add content")
- **Never overwrite a high-quality existing file** — augment if needed, regenerate only if the existing content is poor
- **Never expose internal credentials, keys, or access tokens** — `.mcp.json` and `.env` files must be deleted or added to `.gitignore`
- **Always use `Edit` for targeted fixes** — do not rewrite whole files to fix a single line

## What NOT to do

- Do not skip the IP scan or proceed past Step 2 without user acknowledgment of findings
- Do not add employer-specific badges, internal Slack links, internal issue tracker links, or private service URLs
- Do not invent a test command that does not actually run — detect the project's real test runner
- Do not add `runs-on: [self-hosted]` to CI even if it was present before (remove it)
- Do not commit large binary files or build artifacts (`dist/`, `build/`, `__pycache__/`)

## Quick-reference checklist

```
[ ] Step 0  Project directory resolved and canonicalized
[ ] Step 1  Project surveyed (language, stack, purpose)
[ ] Step 2  IP scan run — user has acknowledged findings
[ ] Step 3  Polish plan shown — user has approved
[ ] Step 4  Employer IP removed — scan re-run and clean
[ ] Step 4b Stale remote branches deleted
[ ] Step 5  Repo infrastructure scaffolded
[ ] Step 6  Quality audits: repo-review (P1 fixed) → docs-review (clean) → changelog-review if plugin
[ ] Step 6d Audit gate passed — no open P1 findings
[ ] Step 7  Summary table shown — user has approved GitHub push
[ ] Step 8  GitHub repo created and pushed
```
