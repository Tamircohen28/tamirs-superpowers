# Contributor bootstrap and development workflow

**This is contributor setup, not user install.** If you only want to *use* the toolkit, stop
here and follow the [install guide for your platform](../../user/install/README.md).
`make install` does not install the plugin — it is now a thin shim over
`scripts/setup.sh apply --yes --targets claude`, which renders this repo's canonical config
onto *your machine*. Users who want that run [`make setup`](../../user/setup.md) knowingly;
it is never a step in getting the plugin.

---

## Bootstrap

```bash
git clone https://github.com/Tamircohen28/tamirs-superpowers.git
cd tamirs-superpowers
brew install shellcheck jq gh          # macOS; apt equivalents elsewhere
python3 -m pip install -r scripts/requirements-validate.txt   # pyyaml, for frontmatter checks
make validate                          # must pass with zero errors
```

There is no build step, no `package.json`, and no compiled output. Everything is Markdown,
JSON, and bash.

Confirm the environment before you debug anything else:

```bash
make doctor          # or: bash scripts/doctor.sh .
```

> `make bootstrap-dev` is declared in the Makefile's help and `.PHONY` list but has **no
> recipe** — `make -n bootstrap-dev` prints "Nothing to be done". Use the clone + `brew
> install` + `make validate` sequence above until it is implemented.

## Running checks

| Command | What it covers | Tier |
|---|---|:--:|
| `make validate` | the full local gate — CI parity for everything not needing a platform CLI | 2 |
| `make lint` | shellcheck only (`-S warning`) | 0 |
| `make test-hooks` | behavior tests in `tests/test-*.sh` | 1 |
| `make test-repo-contract` | scaffold contract fixtures | 1 |
| `bash scripts/check-version-truth.sh .` | version consumers agree with `plugin-version.json` | 0 |
| `bash scripts/check-doc-claims.sh .` | skill counts and target coverage match the tree | 0 |
| `bash scripts/check-capability-registry.sh .` | the capability registry satisfies its schema | 0 |
| `make check-gemini-adapter` · `make gemini-extension-check` | the generated `.gemini/` mirror is present and current | 0 |
| `make opencode-agents-check` | the generated `.opencode/agent/` mirror is current | 0 |
| `bash scripts/validate-roles.sh` | roles, agents, and workflow schemas agree | 0 |

Full picture: [testing matrix](testing-matrix.md).

## Working on the toolkit itself

Load your working copy directly instead of the installed plugin:

```bash
claude --plugin-dir "$PWD"            # Claude Code
gemini extensions link .              # Gemini CLI
```

For Cursor, import the repo as a team marketplace with Auto Refresh. For OpenCode, point
`opencode.json` `skills.paths` at your checkout.

## Branching

- `master` is the default and stable branch.
- Feature branches: `feat/<description>`; fixes: `fix/<description>`.
- Objective work follows the [branch model](../architecture/branch-worktree-model.md):
  `objective/<slug>` with `worker/<slug>/NNN` merging into it. Worker branches never merge
  into `master` directly.
- Everything goes through a PR.

## Making a change

1. Branch.
2. Make the change. Match the surrounding code's idiom; do not restate a canonical contract
   in a second place — reference it.
3. New shell scripts: `set -euo pipefail`, shellcheck-clean at `-S warning`, never block on
   stdin, and a **validation tier stated in the header comment**.
4. New JSON must parse with `jq empty`. New `SKILL.md` must pass
   `python3 scripts/validate-skill-frontmatter.py` — use `/skill-creator` rather than
   hand-writing frontmatter.
5. Run `make validate`.
6. Update `CHANGELOG.md` under `[Unreleased]`.
7. If you added or removed a skill, the count in the docs must move with it —
   `scripts/check-doc-claims.sh` will tell you exactly where.
8. If you changed shipped plugin content (`skills/`, `hooks/`, `agents/`, `scripts/`,
   manifests), bump the version **in `plugin-version.json`** and sync the consumers:

   ```bash
   bash scripts/check-version-truth.sh . --sync
   ```

   Never hand-edit a manifest version. See [versioning](versioning.md).
9. If you touched `agents/*.md` or `skills/**`, regenerate the platform mirrors —
   `make gemini-extension` and `make opencode-agents` — and never hand-edit `.gemini/` or
   `.opencode/agent/` directly. Their `*-check` counterparts fail CI on drift.
10. Open a PR.

## Commit convention

```text
<type>(<scope>): <description>
```

Types: `feat`, `fix`, `chore`, `docs`, `refactor`.
Scopes: `skills`, `hooks`, `marketplace`, `ci`, `docs`, `core`, `platforms`.

## Hard constraints

- Never `runs-on: [self-hosted]` in a workflow — always `ubuntu-latest`.
- Never commit a secret. Credentials are `${ENV_VAR}` placeholders only.
- Never add employer-internal references (domains, private orgs, internal tooling names).
- Never duplicate canonical content per platform. Generate it, with a drift check.
- Never move a manifest version backwards past a cut release.

## Releasing

See [versioning and release](versioning.md).
