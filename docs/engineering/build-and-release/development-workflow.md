# Development Workflow

## Setup

```bash
git clone https://github.com/Tamircohen28/tamirs-superpowers.git
cd tamirs-superpowers
brew install shellcheck jq gh   # if not already installed
make validate                   # confirm all checks pass
```

## Running checks

```bash
make validate   # shellcheck + JSON validation + SKILL.md frontmatter check
make lint       # shellcheck only
```

There is no build step — all content is Markdown, JSON, and Bash.

## Branching

- `main` is the default and stable branch
- Feature branches: `feat/<description>`
- Fix branches: `fix/<description>`
- All changes go through a PR

## Making a change

1. Create a branch: `git checkout -b feat/my-change`
2. Make changes
3. Run `make validate`
4. Update `CHANGELOG.md` under `[Unreleased]`
5. If you added/removed a skill, update `README.md`
6. Push and open a PR

## Releasing

Releases are created via the [Release workflow](.github/workflows/release.yml) — trigger it manually from the Actions tab with a semver version string. The workflow:

1. Bumps the version in `.claude-plugin/plugin.json`
2. Commits the bump
3. Creates `v<version>` and `tamirs-superpowers--v<version>` git tags
4. Creates a GitHub Release

The `tamirs-superpowers--v<version>` tag follows the Claude Code marketplace convention for version resolution — it allows users to pin dependencies to specific versions via `{ "name": "tamirs-superpowers", "version": "~0.6.0" }` in their own plugin.json.

## Testing a skill locally

Claude Code loads plugins from your configured install paths. To test a change:

1. Find your plugin install dir: `/plugin list` in Claude Code
2. Edit the skill file directly (or symlink your dev clone to the install path)
3. Run `/reload-plugins` in Claude Code
4. Test the skill

For hook changes, restart Claude Code entirely to pick up the new hook scripts.
