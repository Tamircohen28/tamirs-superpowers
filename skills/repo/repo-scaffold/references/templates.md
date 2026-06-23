# repo-scaffold Templates

Reference templates used by Agent A, B, C, D during scaffolding. All `{{PLACEHOLDER}}` values must be replaced with actual project data — never leave them unfilled.

---

## README Templates

### Hero Section (all stacks)

```markdown
<div align="center">

# {{REPO_NAME}}

<p>{{SHORT_DESCRIPTION}}</p>

[![CI](https://github.com/TamirCohen28/{{REPO_NAME}}/actions/workflows/ci.yml/badge.svg)](https://github.com/TamirCohen28/{{REPO_NAME}}/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-v0.1.0-D97757?logo=anthropic&logoColor=white)](https://claude.ai/code)

</div>

---

## What It Does

{{ONE_PARAGRAPH_DESCRIPTION}}

## Features

- {{FEATURE_1}}
- {{FEATURE_2}}
- {{FEATURE_3}}
- {{FEATURE_4}}

## Quick Start

```bash
git clone https://github.com/TamirCohen28/{{REPO_NAME}}.git
cd {{REPO_NAME}}
make install
make dev
```

See [docs/user/quick-start.md](docs/user/quick-start.md) for full setup.

## Architecture

{{ARCHITECTURE_SUMMARY_1_PARAGRAPH}}

See [docs/engineering/architecture/overview.md](docs/engineering/architecture/overview.md) for the full picture.

## Documentation

| Doc | Purpose |
|-----|---------|
| [Quick Start](docs/user/quick-start.md) | Get running in 5 minutes |
| [Usage Guide](docs/user/usage.md) | Common workflows |
| [Architecture](docs/engineering/architecture/overview.md) | System design |
| [CLAUDE.md](CLAUDE.md) | Developer guide for AI-assisted work |
| [Contributing](CONTRIBUTING.md) | How to contribute |

## License

MIT — see [LICENSE](LICENSE).
```

### By The Numbers Section (add when project has measurable stats)

```markdown
<div align="center">

![Skills](https://img.shields.io/badge/skills-{{N}}-blue?style=flat-square)
![Tests](https://img.shields.io/badge/tests-{{N}}-green?style=flat-square)
![CI checks](https://img.shields.io/badge/CI_checks-{{N}}-red?style=flat-square)

</div>
```

---

## CLAUDE.md Template

```markdown
# {{REPO_NAME}} — Developer Guide

> Required reading before making changes. Keep this file up to date.

## Overview

{{DESCRIPTION}}

**Primary language / stack:** {{TECH}}
**Repo:** https://github.com/TamirCohen28/{{REPO_NAME}}

## Architecture

{{COMPONENT_MAP}}

Key files:
- `{{KEY_FILE_1}}` — {{PURPOSE_1}}
- `{{KEY_FILE_2}}` — {{PURPOSE_2}}
- `{{KEY_FILE_3}}` — {{PURPOSE_3}}

## Quick Start

```bash
git clone https://github.com/TamirCohen28/{{REPO_NAME}}.git
cd {{REPO_NAME}}
make install   # install dependencies
make dev       # start development server / REPL
```

## Commands

| Command | Purpose |
|---------|---------|
| `make install` | Install all dependencies |
| `make build` | Build for production |
| `make test` | Run test suite |
| `make lint` | Run linter |
| `make dev` | Start dev server |
| `make clean` | Remove build artifacts |

## Coding Standards

- {{STANDARD_1}}
- {{STANDARD_2}}
- {{STANDARD_3}}
- File names: kebab-case for scripts, PascalCase for components/classes
- No commented-out code — delete dead code, use git history

## Commit Convention

```
<type>(<scope>): <description>

[optional body]

Co-Authored-By: Claude <noreply@anthropic.com>
```

Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`

## Constraints

- Never commit secrets, tokens, or `.env` files
- No direct pushes to `master` — always open a PR
- No `git push --force` to `master`
- Do not modify `.github/workflows/` without review
- {{PROJECT_SPECIFIC_CONSTRAINT}}

## Working With Claude Code

```bash
# Install tamirs-plugins marketplace
/plugin marketplace add Tamircohen28/plugins

# Install plugins
/plugin install tamirs-superpowers@tamirs-plugins
/plugin install headhunter@tamirs-plugins
/plugin install jose-claudinho@tamirs-plugins
```

Available skills after install: `/repo-scaffold`, `/repo-standards`, `/multi-agent-repo`, and more.
See [docs/engineering/guides/getting-started.md](docs/engineering/guides/getting-started.md) for full setup.
```

---

## .claude/settings.json Template

```json
{
  "extraKnownMarketplaces": [
    {
      "name": "tamirs-plugins",
      "sourceUrl": "https://github.com/Tamircohen28/plugins"
    }
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
```

**Stack-specific additions to `permissions.allow`:**

Node / Next.js:
```json
"Bash(npm *)", "Bash(npx *)", "Bash(node *)", "Bash(make *)"
```

Python:
```json
"Bash(python *)", "Bash(pip *)", "Bash(pytest *)", "Bash(make *)"
```

Swift / macOS:
```json
"Bash(swift *)", "Bash(xcodebuild *)", "Bash(make *)"
```

Generic:
```json
"Bash(make *)", "Bash(sh *)", "Bash(bash *)"
```

---

## GitHub Actions CI Templates

### Node / Next.js (`ci.yml`)

```yaml
name: CI

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

jobs:
  CI:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version-file: .nvmrc
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Lint
        run: npm run lint

      - name: Test
        run: npm test
```

### Python (`ci.yml`)

```yaml
name: CI

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

jobs:
  CI:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install dependencies
        run: pip install -e ".[dev]"

      - name: Lint
        run: ruff check .

      - name: Test
        run: pytest
```

### Swift (`ci.yml`)

```yaml
name: CI

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

jobs:
  CI:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: swift build

      - name: Test
        run: swift test
```

### Generic (`ci.yml`)

```yaml
name: CI

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

jobs:
  CI:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Lint shell scripts
        run: find . -name "*.sh" -exec shellcheck {} \;

      - name: Validate JSON
        run: find . -name "*.json" ! -path "*/node_modules/*" -exec python3 -m json.tool {} \; > /dev/null

      - name: Run tests
        run: make test
```

---

### claude.yml (all stacks)

```yaml
name: Claude Code

on:
  issue_comment:
    types: [created]
  pull_request:
    types: [labeled]

permissions:
  contents: write
  pull-requests: write
  issues: write

jobs:
  claude:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request' && contains(github.event.label.name, 'claude'))
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 1

      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          model: claude-opus-4-8
```

---

### release.yml (all stacks)

```yaml
name: Release

on:
  push:
    tags:
      - "v*.*.*"

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Create GitHub Release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release create ${{ github.ref_name }} \
            --title "${{ github.ref_name }}" \
            --generate-notes \
            --draft=false

      - name: Update stable branch
        run: |
          git push origin HEAD:stable --force-with-lease
```

---

## Makefile Templates

### Node / Next.js

```makefile
.DEFAULT_GOAL := help

.PHONY: help install build test lint dev clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Install dependencies
	npm ci

build: ## Build for production
	npm run build

test: ## Run tests
	npm test

lint: ## Run linter
	npm run lint

dev: ## Start development server
	npm run dev

clean: ## Remove build artifacts
	rm -rf .next dist node_modules/.cache
```

### Python

```makefile
.DEFAULT_GOAL := help

.PHONY: help install build test lint dev clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Install dependencies
	pip install -e ".[dev]"

build: ## Build package
	python -m build

test: ## Run tests
	pytest

lint: ## Run linter
	ruff check .

dev: ## Start dev mode
	python -m {{PACKAGE_NAME}}

clean: ## Remove build artifacts
	rm -rf dist/ __pycache__/ .pytest_cache/ *.egg-info/
```

### Generic

```makefile
.DEFAULT_GOAL := help

.PHONY: help install test lint clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Setup environment
	@echo "Add setup steps here"

test: ## Run tests
	@echo "Add test steps here"

lint: ## Lint shell scripts
	find . -name "*.sh" -exec shellcheck {} \;

clean: ## Clean artifacts
	@echo "Add clean steps here"
```

---

## .gitignore Templates

### Node / Next.js

```
# Dependencies
node_modules/
.pnp
.pnp.js

# Build
dist/
.next/
out/
build/

# Environment
.env
.env.local
.env.*.local

# Logs
*.log
npm-debug.log*

# Runtime
.DS_Store
*.tgz
coverage/
.nyc_output/

# Claude Code
.dev-files/
.claude/worktrees/
```

### Python

```
# Dependencies
__pycache__/
*.py[cod]
*.egg-info/
.eggs/
.venv/
venv/
env/

# Build
dist/
build/

# Environment
.env
.env.*

# Testing
.pytest_cache/
.coverage
htmlcov/

# Logs
*.log

# OS
.DS_Store

# Claude Code
.dev-files/
.claude/worktrees/
```

### Generic

```
# Environment
.env
.env.*

# Logs
*.log

# Build
dist/
build/
.build/

# OS
.DS_Store
Thumbs.db

# Claude Code
.dev-files/
.claude/worktrees/
```
