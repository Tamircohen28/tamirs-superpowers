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

## Running locally

```bash
make validate   # all four checks
make lint       # shellcheck only
```

## Release workflow

Releases are created manually via `.github/workflows/release.yml` — see [development-workflow.md](development-workflow.md) for the full release process.
