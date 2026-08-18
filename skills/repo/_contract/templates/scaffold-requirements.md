# Scaffold Templates — repo-standards polish mode

Load when executing polish mode phases 1–4. Defines README, docs, GitHub, and branch governance artifacts.

---

## README.md structure

Required sections in order:

1. Centered hero image or badge placeholder
2. Project name as `# Title`
3. **Badge row 1:** author (GitHub profile link), CI status, license, version
4. **Badge row 2 (optional):** npm/PyPI, live site, framework versions — omit row if N/A
5. **Badge row 3 (when ≥2 AI targets):** one version badge per supported target —
   Claude Code / Cursor / Codex / Gemini CLI / OpenCode. The badge value must equal
   `validated_against` in `platform-targets.json`; a target still carrying
   `"validated_against": "unknown"` is declared but unvalidated and needs no badge yet.
6. One-paragraph hook
7. Feature highlights (4–6 bullets)
8. Prerequisites
9. Quick Start — **one-liner `make install` first**; per-target subsections when multi-platform
10. Documentation link to `docs/`
11. Contributing link to `docs/CONTRIBUTING.md`
12. License line

See [`references/readme-badges.md`](../references/readme-badges.md) for badge markdown examples.

Never use placeholder text. Derive content from the actual codebase.

---

## docs/ tree

```
docs/
  README.md
  CHANGELOG.md
  CONTRIBUTING.md
  user/
    README.md
    concepts.md
    quick-start.md
    troubleshooting.md
  engineering/
    README.md
    architecture/overview.md
    build-and-release/development-workflow.md
    build-and-release/ci-workflow.md
    decisions/README.md
```

---

## .github/ infrastructure

### CI (`.github/workflows/ci.yml`)

- Triggers: `pull_request`, `push` to default branch, `workflow_dispatch`
- Jobs: lint, test, secret-scan
- **Always** `runs-on: ubuntu-latest` — never `self-hosted`

### Release, Dependabot, PR template, issue templates

See scaffold-templates section 5c below for full YAML shapes.

---

## Root files

- `LICENSE` — MIT, current year
- `CODEOWNERS` — `* @TamirCohen28` (or project owner)
- `AGENTS.md` — canonical agent policy (required)
- `CHANGELOG.md` — root mirror; keep in sync with `docs/CHANGELOG.md`
- `CLAUDE.md` — `@AGENTS.md` import + Claude-only addenda
- `Makefile` — **required targets:** `install`, `update`, `uninstall`, plus `test`/`lint` when applicable
- `scripts/` — user-facing shell scripts only (`install.sh`, `update.sh`, `uninstall.sh`, helpers); **no** `.sh` at repo root
- `docs/engineering/build-and-release/versioning.md` — semver + tagging policy (see `references/versioning-policy.md`)

---

## Repository merge settings (polish phase 4)

Before branch protection, enable PR auto-merge and delete head branch on merge. Required for `start-dev` / `pr-dev` (`gh pr merge --auto --delete-branch`).

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

gh api -X PATCH "repos/$REPO" \
  -f allow_auto_merge=true \
  -f delete_branch_on_merge=true
```

When scaffolding from `tamirs-superpowers`, prefer the contract helper:

```bash
bash "$CONTRACT_ROOT/scripts/enable-repo-merge-settings.sh" "$REPO"
```

Confirm:

```bash
gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
  --jq '{allow_auto_merge, delete_branch_on_merge}'
```

---

## Branch protection (polish phase 4)

After CI workflow exists with a job named `CI` and merge settings are enabled:

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo master)

# Apply if missing, then verify (1 review + CI check)
bash "$CONTRACT_ROOT/scripts/ensure-branch-protection.sh" "$REPO" "$DEFAULT_BRANCH"
```

Or inline (when `CONTRACT_ROOT` is unavailable):

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo master)

gh api "repos/$REPO/branches/$DEFAULT_BRANCH/protection" \
  --method PUT \
  --silent \
  -F 'required_status_checks[strict]=true' \
  -F 'required_status_checks[contexts][]=CI' \
  -F 'required_pull_request_reviews[required_approving_review_count]=1' \
  -F 'enforce_admins=false' \
  -F 'restrictions=null'

gh api "repos/$REPO/branches/$DEFAULT_BRANCH/protection" \
  --jq '{reviews: .required_pull_request_reviews.required_approving_review_count, checks: .required_status_checks.contexts}'
```

Verify only (audit / after manual edits):

```bash
bash "$CONTRACT_ROOT/scripts/ensure-branch-protection.sh" --verify-only
```

Adjust `REQUIRED_CHECK` if your CI job is not named `CI` (must match `ci.yml`).
