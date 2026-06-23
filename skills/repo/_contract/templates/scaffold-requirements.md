# Scaffold Templates — repo-standards polish mode

Load when executing polish mode phases 1–4. Defines README, docs, GitHub, and branch governance artifacts.

---

## README.md structure

Required sections in order:

1. Centered hero image or badge placeholder
2. Project name as `# Title`
3. Badges row: CI status, license
4. One-paragraph hook
5. Feature highlights (4–6 bullets)
6. Prerequisites
7. Quick Start (3–5 steps)
8. Documentation link to `docs/`
9. Contributing link to `docs/CONTRIBUTING.md`
10. License line

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
- `CLAUDE.md` — overview, key files, commands, constraints
- `Makefile` — install, test, lint when applicable

---

## Branch protection (polish phase 4)

After CI workflow exists with a job named `CI`:

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
```

Adjust `contexts[]` to match actual required check names from `ci.yml`.
