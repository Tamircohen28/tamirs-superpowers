# Contributing to tamirs-superpowers

Thanks for your interest. This is a personal plugin, but PRs for bug fixes and general-purpose skill improvements are welcome.

## What belongs here

- Bug fixes in hooks or skills
- New skills that work on **any** repo (no internal tooling, no company-specific APIs)
- MCP server stubs for publicly available npm packages
- Documentation improvements

**Not accepted:** Wix-internal references, company-specific scripts, skills that only work with private tools.

## Development setup

```bash
git clone https://github.com/TamirCohen28/tamirs-superpowers.git
cd tamirs-superpowers
brew install shellcheck jq  # if not already installed
make validate               # should pass with zero errors
```

## Making a change

1. Fork the repo and create a feature branch: `feat/<short-description>`
2. Make your change
3. Run `make validate` — fix any shellcheck warnings or JSON errors
4. Update `CHANGELOG.md` under `[Unreleased]`
5. Update `README.md` if you added or removed a skill
6. Open a PR using the PR template

## Commit message convention

```
<type>(<scope>): <description>
```

Types: `feat`, `fix`, `chore`, `docs`, `refactor`
Scopes: `skills`, `hooks`, `marketplace`, `ci`, `docs`

Examples:
```
feat(skills): add generic code-review skill
fix(hooks): handle missing cwd in capture-task-slug
docs: update quick-start with correct marketplace URL
```

## Adding a skill

1. Create `skills/<topic>/<skill-name>/SKILL.md`
2. Frontmatter must include `name:`, `description:`, and `allowed-tools:`
3. Add the skill to `README.md`'s skill table and update the count
4. Run `make validate`

Topic conventions:
- `dev-workflow` — git, PR, review, planning, debugging workflows
- `integrations` — external tool integrations (Slack, proto, etc.)
- `meta` — Claude Code itself, skill authoring, MCP
- `content` — creative or content-generation skills

## Code review

All PRs are reviewed by @TamirCohen28. Response time is best-effort — this is a personal project.
