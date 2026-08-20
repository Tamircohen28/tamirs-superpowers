# tamirs-superpowers — agent entrypoint

A multi-platform agent plugin: bundled skills, specialist agents, worktree hooks, and MCP server stubs, shipped to five platforms and, underneath them, six supported runtime **surfaces**: **Claude** (**Claude Code**, **Claude Desktop**), **Codex** (**Codex CLI**), **Cursor** (**Cursor IDE**), **Gemini** (**Gemini CLI**, `gemini-extension.json`), and **OpenCode** (**OpenCode CLI**). The four non-Claude platforms each have a further surface — the Codex IDE extension, the Cursor CLI, Gemini Code Assist, the OpenCode desktop app — that has never been measured here; claim nothing about them in either direction. It is **not** a Node/Python/Go app — no build step, no `package.json`, no compiled output. All content is Markdown, JSON, and Bash.

**This file is a thin entrypoint, not the policy.** Canonical policy lives in [`core/`](core/) and [`rules/`](rules/README.md); this page tells you which of those to read and gives you the commands. When this file and a canonical rule disagree, the canonical rule wins — say so rather than following the stale copy.

---

## Read this first

| You are about to… | Read |
|-------------------|------|
| Do anything at all | [`core/policies/safety.md`](core/policies/safety.md) — the hard invariants |
| Branch, commit, or push | [`core/policies/git.md`](core/policies/git.md) + [`rules/dev/git-worktree-agent-workflow.md`](rules/dev/git-worktree-agent-workflow.md) |
| Run tests or checks | [`core/policies/validation.md`](core/policies/validation.md) — which tier applies where |
| Open a PR / ship | [`core/policies/delivery.md`](core/policies/delivery.md) — one objective, one PR |
| Take on a role (implementer, reviewer, …) | [`core/roles/README.md`](core/roles/README.md) — role is not provider |
| Pick which provider runs a task | [`core/providers/selection.md`](core/providers/selection.md) |
| Hand work to another provider | [`rules/dev/cross-platform-handoff.md`](rules/dev/cross-platform-handoff.md) |
| Write a plan, review, or scratch file | [`rules/dev/dev-files-workspace.md`](rules/dev/dev-files-workspace.md) — it goes in `.dev-files/` |
| Author or edit a `SKILL.md` | [`rules/dev/skill-quality-standards.md`](rules/dev/skill-quality-standards.md) + [`core/schemas/skill-frontmatter.json`](core/schemas/skill-frontmatter.json) |
| Write a script or a hook | [`rules/dev/user-facing-script-standards.md`](rules/dev/user-facing-script-standards.md) |
| Touch GitHub | [`rules/dev/gh-cli-preference.md`](rules/dev/gh-cli-preference.md) — `gh` is optional; degrade explicitly |
| Change shipped content | [`rules/dev/plugin-version-bump.md`](rules/dev/plugin-version-bump.md) — bump `plugin-version.json`, then `--sync` |

The full index, including the hard-invariant vs configurable-policy split and the adapter map, is [`rules/README.md`](rules/README.md).

---

## Work model in one paragraph

A user **objective** decomposes into worker **tasks** (a DAG). Each task runs in its own worktree on `worker/<slug>/NNN`, ends at **commit + handoff**, and never opens a PR. Workers compose into one **integration** worktree on `objective/<slug>`, which is where cross-worker review and full validation happen, and where the single PR is opened. Which provider ran a task is metadata recorded in `.dev-files/objectives/<id>/`, never encoded in a path or a branch name. Worker validation is targeted (Tier 1); full validation runs once at integration (Tier 2); CI is the final authority (Tier 3).

---

## Commands

```bash
make validate           # shellcheck + JSON + skill frontmatter + repo contract + doc claims
make lint               # shellcheck only
make test               # same as validate
make test-repo-contract # scaffold-gold (app-gold) + scaffold-plugin-gold (plugin-gold)
bash scripts/doctor.sh  # detected platform, version, dependencies, available capabilities
make install            # bootstrap Claude machine settings + agents (from a clone)
make update
make uninstall
```

Claude Code marketplace install:

```text
/plugin marketplace add Tamircohen28/tamirs-marketplace
/plugin install tamirs-superpowers@tamirs-marketplace
```

Per-surface install guides: [`docs/user/install/`](docs/user/install/) — one per supported surface, none for an unverified one. The machine-readable target list is [`platform-targets.json`](docs/engineering/build-and-release/platform-targets.json); the machine-readable capability list is [`core/capabilities/platforms.json`](core/capabilities/platforms.json).

---

## Repo-specific expectations

These are true of *this* repository and are not in `core/`:

- All JSON must parse (`jq empty`) — checked by `make validate`.
- All `.sh` must pass `shellcheck` at `-S warning` — `make lint`.
- Every `SKILL.md` must validate against the **portable** schema, [`core/schemas/skill-frontmatter.json`](core/schemas/skill-frontmatter.json), enforced by `scripts/validate-skill-frontmatter.py`. Claude-specific fields are a documented *extension* of that schema, not a universal requirement — see [`rules/dev/skill-quality-standards.md`](rules/dev/skill-quality-standards.md).
- The version lives in **one** file, `plugin-version.json`. Never hand-edit a manifest, badge, or `platform-targets.json` version — run `bash scripts/check-version-truth.sh --sync`.
- Commit format `<type>(<scope>): <description>` — types `feat`, `fix`, `chore`, `docs`, `refactor`; scopes `skills`, `hooks`, `core`, `rules`, `marketplace`, `ci`, `docs`.
- Never add `runs-on: [self-hosted]` to a workflow — use `ubuntu-latest`.
- Never commit secrets — `.mcp.json` uses `${ENV_VAR}` placeholders only.
- Never add employer-internal references (internal domains, private orgs, internal tooling names).
- Never add a `marketplace.json` here — publication goes through the separate `Tamircohen28/tamirs-marketplace` catalog.
- Never modify `hooks/lib/worktree-common.sh` without running shellcheck and testing both `capture-task-slug.sh` and `worktree-create.sh`.
- Never hand-write a `SKILL.md` — use the `skill-creator` skill.
- No install step for plugin **content**; `make install` only bootstraps machine settings and agents.

## Surface skills at the moment they apply

When a situation arises that a bundled skill covers, **either invoke the skill or tell the
user in one line that it exists** — do not silently hand-roll the work. One suggestion per
situation per session; never repeat a declined suggestion.

| Situation | Skill |
|---|---|
| The user asks what something cost, how many tokens it used, or why a session got expensive | `session-report` |
| A stack trace, traceback, panic or crash log is pasted, or a `file:line` is named | `targeted-debug` |
| "am I up to date", "what new features am I missing", "latest docs" — or a `*-plugin/plugin.json` or `CHANGELOG.md` is being bumped | `platform-sync` |
| A rate limit is hit, or an objective is still open and the session is ending | `switch-dev` |
| You are about to hand-write a capability a public skill or plugin plausibly already provides | `find-skill` |
| The session had repeated failures on the same thing, or the user corrected you several times | `retro` |

**Why the rule and not just good trigger descriptions:** `skill_auto_invocation` in
[`core/capabilities/platforms.json`](core/capabilities/platforms.json) is `partial` on Cursor
and `unknown` on Codex, Gemini CLI and OpenCode. Description-based auto-triggering only fires
reliably on Claude Code and Claude Desktop, and the `UserPromptSubmit` hook that reinforces it
(`hooks/skill-suggest.sh`) is unsupported on OpenCode. This rule is the only surfacing
mechanism that works on every supported surface, which is why it is written down rather than
left to the matcher.

## Key paths

| Path | Purpose |
|------|---------|
| `core/` | Portable framework — policies, roles, workflow schemas, capabilities |
| `platforms/<id>/adapter.yaml` | Per-target adapter metadata; authoritative capabilities stay in `core/capabilities/platforms.json` |
| `rules/` | Canonical contributor rules (all providers) — see `rules/README.md` |
| `plugin-version.json` | Single source of truth for the version; every consumer listed inside |
| `.claude-plugin/plugin.json` | Claude Code / Claude Desktop manifest |
| `.cursor-plugin/plugin.json` | Cursor manifest — shared by the Cursor IDE and the Cursor CLI (skills + MCP; no hooks) |
| `.codex-plugin/plugin.json` | Codex manifest (skills + hooks + MCP) |
| `gemini-extension.json` | Gemini CLI extension manifest (`platform-targets.json` key: `gemini_cli`) |
| `opencode.json` | OpenCode config (no version field — installs by path) |
| `hooks/hooks.json` | Hook event wiring (Claude Code + Codex) |
| `skills/<domain>/<name>/SKILL.md` | Bundled skills, grouped by domain |
| `agents/*.md` | Specialist agent definitions; each declares a `role:` from `core/roles/` |
| `skills/repo/_contract/` | Shared repo scaffold/standards contract — templates, scoring, gold fixtures (not a skill) |
| `scripts/` | User-facing scripts + validators |

---

## Cloud and headless runbook

Applies to Cursor Cloud, Codex sandboxes, Claude Code remote sessions, Gemini CLI, and CI — any non-interactive shell.

There is no app server or build output. "Running" this repo means exercising the validation harness:

| Check | Command |
|-------|---------|
| Full validation | `make validate` |
| Repo-standards gate | `make repo-standards-gate` |
| Plugin health | `bash .claude/skills/run-tamirs-superpowers/smoke.sh </dev/null` |
| Statusline render (Claude Code) | `echo '<session-json>' \| bash scripts/statusline.sh` |
| Environment / dependencies | `bash scripts/doctor.sh` |

**Gotchas:**

- `scripts/statusline.sh` reads JSON from **stdin**. With no piped input it blocks in non-interactive shells — always pipe or redirect (`</dev/null`). `smoke.sh` inherits stdin, so run it as `smoke.sh </dev/null`. The non-blocking requirement for new scripts is in [`user-facing-script-standards.md`](rules/dev/user-facing-script-standards.md) §4.
- `shellcheck` is required for shell coverage in `make lint`/`make validate`; if absent those targets **skip** shellcheck rather than failing. Install it via your system package manager.
- `make check-manifest-versions` needs network to compare against the latest release tag; it works offline against the current checkout.
- Cursor Cloud agents boot a fresh Linux VM — install `shellcheck` and `pip install -r scripts/requirements-validate.txt` first.

Platform-specific addenda: [`CLAUDE.md`](CLAUDE.md) (Claude Code / Desktop), `.cursor/rules/*.mdc` (Cursor IDE), `.codex/config.toml` (Codex), `docs/user/install/gemini.md` (Gemini CLI), `docs/user/install/opencode.md` (OpenCode — note what does not port).
