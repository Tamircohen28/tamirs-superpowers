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
6. If you changed **shipped plugin content** (`skills/`, `hooks/`, `agents/`, manifests, `scripts/`), bump all three `plugin.json` manifests and `README.md` badges in the release PR — see [`rules/dev/plugin-version-bump.md`](../../../rules/dev/plugin-version-bump.md)
7. Push and open a PR

## Releasing

Releases are created via the [Release workflow](.github/workflows/release.yml) — trigger it manually from the Actions tab with a semver version string. The workflow:

1. Bumps the version in every present `plugin.json` manifest (skip if the release PR already bumped them)
2. Commits the bump when needed
3. Creates a `v<version>` git tag (required — CI fails if manifest version has no matching tag)
4. Creates a GitHub Release

**Claude Code users** must refresh after a release:

```text
/plugin marketplace update tamirs-marketplace
/plugin update tamirs-superpowers@tamirs-marketplace
/reload-plugins
```

Without a version bump, `/plugin update` reports "already at the latest version" even when new commits exist on GitHub.

## Testing a skill locally

Claude Code loads plugins from your configured install paths. To test a change:

1. Find your plugin install dir: `/plugin list` in Claude Code
2. Edit the skill file directly (or symlink your dev clone to the install path)
3. Run `/reload-plugins` in Claude Code
4. Test the skill

For hook changes, restart Claude Code entirely to pick up the new hook scripts.
