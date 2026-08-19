# CLAUDE.md — tamirs-superpowers

Claude Code and Claude Desktop specifics for contributors. **Everything that is not Claude-specific lives elsewhere — start with [`AGENTS.md`](AGENTS.md)**, which is the shared entrypoint into [`core/`](core/) and [`rules/`](rules/README.md). This file adds only what is true of the Claude surface.

When this file and a canonical rule disagree, the canonical rule wins.

## What this repo is

A multi-platform agent plugin (skills, agents, hooks, MCP stubs) shipped to Claude Code, Claude Desktop, Cursor, Codex, Gemini CLI, and OpenCode. No build step, no `package.json`, no compiled output — Markdown, JSON, and Bash.

Claude Code and Claude Desktop are **one distribution**, not two formats: the same `.claude-plugin/plugin.json`, the same `skills/`, the same `agents/`. Desktop differences are surface-level (installation path, no CLI flags) and documented in [`docs/user/install/claude-code.md`](docs/user/install/claude-code.md).

## Commands

See [`AGENTS.md`](AGENTS.md#commands) for the full list. `make validate` before every push.

## Claude-only capabilities

Do not assume these exist on other providers — check [`core/capabilities/platforms.json`](core/capabilities/platforms.json) before relying on any of them, and degrade explicitly per [`core/policies/safety.md`](core/policies/safety.md).

- **Subagents** (`Agent` tool) — parallel worker execution. Other providers run tasks sequentially or through their own mechanism.
- **Hooks** — `hooks/hooks.json` is loaded by Claude Code and Codex only. Cursor does not wire it; Gemini CLI and OpenCode have their own or none.
- **Statusline** — wired via `.claude-plugin/plugin.json` `settings.statusLine` → `scripts/statusline.sh`. Claude-only. Test with piped JSON: `echo '<session-json>' | bash scripts/statusline.sh` — it blocks forever on unpiped stdin.
- **`EnterWorktree`** — automates worktree creation under `.claude/.worktrees/<name>`. That is the *legacy* layout; it stays supported and is never orphaned, but new objectives use `.agent-worktrees/<objective>/` per [`rules/dev/git-worktree-agent-workflow.md`](rules/dev/git-worktree-agent-workflow.md). `resolve-worktree.sh` understands both.
- **Project memory** — `.claude/memory/` (versioned backup, reviewable in PRs) mirrored into `~/.claude/projects/-Users-<you>-Projects-tamirs-superpowers/memory/` (auto-loaded each session). Keep them in sync; commit new memory files to `.claude/memory/`.

  ```bash
  MEMORY_DIR=~/.claude/projects/-Users-$(whoami)-Projects-tamirs-superpowers/memory
  mkdir -p "$MEMORY_DIR" && cp .claude/memory/* "$MEMORY_DIR/"
  ```

## Marketplace cache

The installed copy lives under `~/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/<version>/`. Claude uses the manifest `version` as the update cache key — pushing commits without a bump does not reach installed users. After a release:

```text
/plugin marketplace update tamirs-marketplace
/plugin update tamirs-superpowers@tamirs-marketplace
```

`/reload-plugins` reloads the **local cache** only; it never fetches from GitHub. For local development, symlink the cache directory at your clone or run with `--plugin-dir` — never hand-edit files under the cache. Full mechanics, including the version-glob failure mode: [`rules/dev/plugin-version-bump.md`](rules/dev/plugin-version-bump.md).

The version itself is edited in **one** place, `plugin-version.json`, then propagated with `bash scripts/check-version-truth.sh --sync`. Never hand-edit `.claude-plugin/plugin.json`'s version.

## Skill frontmatter on Claude

Every `SKILL.md` validates against the **portable** schema, [`core/schemas/skill-frontmatter.json`](core/schemas/skill-frontmatter.json). Claude Code's own frontmatter fields are a documented **extension** of that schema — they add Claude behavior (invocation gating, tool allowlists, model hints) and are validated when present. They are not a universal requirement, and a skill is not invalid for omitting a field no other provider understands. Authoring rules: [`rules/dev/skill-quality-standards.md`](rules/dev/skill-quality-standards.md). Never hand-write a `SKILL.md` — use `skill-creator`.

### Invocation tiers (Claude-specific)

- `user-invocable: false` — blocks the user typing `/skill-name`; other skills can still call it via the `Skill` tool.
- `disable-model-invocation: true` — prevents context-based auto-triggering.

| Tier | `user-invocable` | `disable-model-invocation` | Examples |
|------|:---:|:---:|----------|
| User + auto-trigger (default) | `true` | `false` | plan-dev, start-dev, pr-dev, repo-standards, cleanup, retro |
| Explicit-only (slash, no auto) | `true` | `true` | switch-dev |
| Internal companion | `false` | `true` | docs-review, mcp-pagination, changelog-review |

**Gating warning:** `disable-model-invocation: true` also blocks **subagent and workflow orchestration** — a subagent invoking a skill *is* model invocation, so a gated skill cannot be fanned out across subagents. Gate only a skill that must *never* run autonomously. Prefer putting safety **inside** the skill: `cleanup` stays model-invocable with confirmation gates, a dry-run, and a script that only touches provably-safe targets; `retro` stays model-invocable because it only *proposes* changes and never writes without approval.

Internal-only skills today: `changelog-review`, `docs-review`, `mcp-pagination`.

## Commit trailer

Claude sessions append:

```text
Co-Authored-By: Claude <noreply@anthropic.com>
```

Format and scopes are in [`AGENTS.md`](AGENTS.md#repo-specific-expectations).

## Remote and headless Claude sessions

Same validation commands as the [cloud runbook in `AGENTS.md`](AGENTS.md#cloud-and-headless-runbook). Hooks in `hooks/hooks.json` apply in Claude Code sessions only; a remote session without hook support must not assume worktree hooks ran.
