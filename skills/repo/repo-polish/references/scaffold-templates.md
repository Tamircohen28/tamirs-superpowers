# Scaffold Templates — repo-polish

This file defines the exact structure and content requirements for each file created in Step 5.
Load it when executing Step 5 so you have the full spec in context.

---

## 5a. README.md structure

Required sections in order:

1. `<p align="center">` hero image placeholder (shields.io badge as stand-in if no banner image exists)
2. Project name as `# Title`
3. Badges row: CI status, license
4. One-paragraph hook: what this is and who it's for (use real project content)
5. **Feature highlights** — 4–6 bullets with bolded lead words
6. **Prerequisites** — runtime, tools, accounts required
7. **Quick Start** — 3–5 steps, zero to running
8. **Documentation** → link to `docs/`
9. **Contributing** → link to `docs/CONTRIBUTING.md`
10. **License** line

Never write placeholder text ("Your description here", "TODO: add content"). Every section must contain content derived from reading the actual code.

---

## 5b. docs/ tree

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

---

## 5c. .github/ infrastructure

### CI workflow (`.github/workflows/ci.yml`)

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

NEVER use `runs-on: [self-hosted]` — always `ubuntu-latest`.

### Release workflow (`.github/workflows/release.yml`)

Manual `workflow_dispatch` with `version` input. Steps: validate version format → create git tag → create GitHub Release with generated notes.

### Dependabot (`.github/dependabot.yml`)

Enable for detected ecosystem: `npm`, `pip`, or `github-actions`.

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

### PR template (`.github/pull_request_template.md`)

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

### Issue templates (`.github/ISSUE_TEMPLATE/`)

Create `bug_report.yml` and `feature_request.yml` with standard fields.

---

## 5d. CLAUDE.md

Generate at repo root with:
- Project overview (1 paragraph)
- Key file locations table
- Build command
- Test command
- Commit message convention
- Hard constraints (things Claude must never change)

---

## 5e. Makefile

If absent, create with targets: `install`, `test`, `lint`, `build` (if applicable), `clean`.

---

## 5f. LICENSE

If absent, create MIT license with current year and the project owner's name.

---

## 5g. .gitignore

If absent or sparse, generate a comprehensive one for the detected stack. Common entries:
- Node: `node_modules/`, `dist/`, `.env`, `*.log`
- Python: `__pycache__/`, `*.pyc`, `.venv/`, `dist/`, `*.egg-info`
- Go: `/vendor/`, `*.test`
- macOS: `.DS_Store`, `.AppleDouble`

---

## 5h. CODEOWNERS

```
* @<your-github-username>
```

Replace `<your-github-username>` with the actual GitHub username (default: `TamirCohen28`).
