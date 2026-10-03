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

Before applying branch governance, enable PR auto-merge and delete head branch on merge. These are repository settings, not ruleset rules, so `github-policy.sh` does not own them. Required for `start-dev` / `pr-dev` (`gh pr merge --auto --delete-branch`).

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

## Branch governance (polish phase 4)

After the CI workflow is on the default branch and merge settings are enabled, apply the
canonical policy. Governance is expressed as **branch rulesets**, never as classic
`branches/*/protection` — the classic endpoint returns 404 on a rulesets-governed repository,
so tooling that reads it reports a protected repo as unprotected.

```bash
PLUGIN_ROOT="$(cd "$CONTRACT_ROOT/../../.." && pwd)"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

bash "$PLUGIN_ROOT/scripts/github-policy.sh" plan  --repo "$REPO"   # diff, writes nothing
bash "$PLUGIN_ROOT/scripts/github-policy.sh" apply --repo "$REPO"   # confirms each change
```

Audit only (read-only; this is what `ensure-branch-protection.sh --verify-only` used to mean):

```bash
bash "$PLUGIN_ROOT/scripts/github-policy.sh" audit --repo "$REPO"
```

**There is no inline fallback, on purpose.** The previous version of this section carried a
hand-rolled `gh api ... PUT .../protection` with `strict=true`, one literal `CI` context and
`required_approving_review_count=1`. All three contradict the canonical policy, and a copy of
policy values in a template is exactly the drift the single policy document exists to remove.
Required contexts are per-repository — nine on `tamirs-superpowers`, out of fifteen CI jobs —
and must never be globalised. Everything that governs a branch lives in
[`config/github/repository-policy.json`](../../../../config/github/repository-policy.json);
read it, do not restate it.

`ensure-branch-protection.sh` still exists as a deprecating shim onto these verbs so older
callers keep working. Do not write new calls to it.

**When GitHub administration access is unavailable**, this step is skipped, not failed. The
scaffolded repository is complete and pushed; report that the policy was not applied, give the
`apply` command above, and move on.
