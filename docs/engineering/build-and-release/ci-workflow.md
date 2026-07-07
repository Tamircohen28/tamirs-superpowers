# CI Workflow

CI runs on every pull request and push to `master` via `.github/workflows/ci.yml`.

## Jobs

### `shellcheck`

Runs [shellcheck](https://www.shellcheck.net/) on every `.sh` file under `hooks/` at warning severity, excluding SC2034 (unused variables — a common false positive in sourced shell libraries).

```bash
find hooks -name '*.sh' | xargs shellcheck -S warning --exclude SC2034
```

**Fails on:** any shellcheck warning at warning level or above.

### `Validate JSON`

Validates every `.json` file in the repo with `jq empty`.

```bash
find . -name '*.json' -not -path '*/.git/*' | while read f; do
  jq empty "$f" || exit 1
done
```

**Fails on:** malformed JSON (missing comma, trailing comma, unquoted key, etc.).

### `Validate SKILL.md frontmatter`

Checks that every `SKILL.md` has both a `name:` and `description:` field in its YAML frontmatter. These are required by Claude Code for skill discovery.

```bash
find skills -name 'SKILL.md' | while read f; do
  grep -q '^name:' "$f" || exit 1
  grep -q '^description:' "$f" || exit 1
done
```

**Fails on:** any skill missing `name:` or `description:`.

### `Secret scan`

Greps for high-signal secret patterns across all source files:

| Pattern | What it catches |
|---------|----------------|
| `AKIA[0-9A-Z]{16}` | AWS access key ID |
| `ghp_[A-Za-z0-9]{36}` | GitHub personal access token |
| `xoxb-[0-9]+-` | Slack bot token |
| `-----BEGIN (RSA\|EC\|OPENSSH) PRIVATE KEY` | Private key material |

**Fails on:** any match in `.sh`, `.json`, `.md`, or `.yml` files.

### `claude plugin validate`

Runs `claude plugin validate .` (Claude Code CLI) to confirm the plugin manifest and bundled skills load cleanly.

**Fails on:** any manifest or skill validation error reported by the CLI.

### `Repo contract (scaffold-gold)`

Runs `make test-repo-contract` to assert the `app-gold` and `plugin-gold` gold fixtures still match the shared contract in `skills/repo/_contract/`.

**Fails on:** any drift between the contract scripts/templates and the gold fixtures.

### `Manifest/tag version alignment`

Runs `skills/repo/_contract/scripts/check-manifest-version-alignment.sh` to confirm `.claude-plugin/plugin.json` is in sync with the Codex/Cursor manifests and the latest release tag.

On **pull requests**, the job passes `--manifests-only` so release PRs can bump manifests before the `vX.Y.Z` tag exists (full tag check still runs on push to `master`).

**Fails on:** a version mismatch across the three plugin manifests, or (on `master` pushes) manifest version with no matching git tag.

### `HOL Plugin Scanner`

Runs `plugin-scanner lint` (and a non-blocking publish-readiness `verify`) to check plugin structure. The `verify` step is `continue-on-error` because MCP stdio execution is intentionally skipped by the scanner in CI for safety.

**Fails on:** a `lint` structural violation. The `verify` step warns but does not fail the job.

## Required status checks

Branch protection on `master` requires these six contexts to pass before a PR can merge:

| Context | Job |
|---------|-----|
| `shellcheck` | `lint` |
| `Validate JSON` | `validate-json` |
| `Validate SKILL.md frontmatter` | `validate-skills` |
| `Secret scan` | `secret-scan` |
| `claude plugin validate` | `plugin-validate` |
| `Manifest/tag version alignment` | `manifest-version-alignment` |

`Repo contract (scaffold-gold)` and `HOL Plugin Scanner` run on every PR but are advisory (not required to merge). Branch protection is applied via `skills/repo/_contract/scripts/ensure-branch-protection.sh`.

## Running locally

```bash
make validate   # shellcheck + JSON + frontmatter + contract test
make lint       # shellcheck only
```

## Release workflow

Releases are created manually via `.github/workflows/release.yml` — see [development-workflow.md](development-workflow.md) for the full release process.
