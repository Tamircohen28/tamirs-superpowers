# CLAUDE.md — tamirs-superpowers

Claude Code and Claude Desktop specifics for contributors. **Everything that is not Claude-specific lives elsewhere — start with [`AGENTS.md`](AGENTS.md)**, which is the shared entrypoint into [`core/`](core/) and [`rules/`](rules/README.md). This file adds only what is true of the Claude platform's two surfaces, and only what is true *now*; the per-release history lives in [`docs/engineering/host-notes/claude-code.md`](docs/engineering/host-notes/claude-code.md).

When this file and a canonical rule disagree, the canonical rule wins.

## What this repo is

A multi-platform agent plugin (skills, agents, hooks, MCP stubs) shipped to six supported surfaces across five platforms: Claude (Claude Code, Claude Desktop), Codex (Codex CLI), Cursor (Cursor IDE), Gemini (Gemini CLI), and OpenCode (OpenCode CLI). No build step, no `package.json`, no compiled output — Markdown, JSON, and Bash.

Claude Code and Claude Desktop are **one distribution**, not two formats — the same manifest, `skills/` and `agents/` — and two **surfaces** of one platform: what differs is the runtime (installation path, no CLI flags, and the capability rows Desktop has never had measured), documented in [`docs/user/install/claude-desktop.md`](docs/user/install/claude-desktop.md).

## Commands

See [`AGENTS.md`](AGENTS.md#commands) for the full list. `make validate` before every push.

## Claude-only capabilities

Do not assume these exist on other providers — check [`core/capabilities/platforms.json`](core/capabilities/platforms.json) first, and degrade explicitly per [`core/policies/safety.md`](core/policies/safety.md).

Per-release host notes, 2.1.234 through 2.1.312, with what was adopted and what was reviewed and declined: [`docs/engineering/host-notes/claude-code.md`](docs/engineering/host-notes/claude-code.md).

- **Subagents** (`Agent` tool) — parallel worker execution, measured on Claude Code; not exercised on Desktop. Every `agents/*.md` pins its model alias in `model:`. A worker that stops on its own `maxTurns` comes back marked `partial`, which the handoff vocabulary in [`worker-dev`](skills/dev-workflow/worker-dev/SKILL.md) already treats as "decide, never quietly integrate around it."
- **Project instructions** — Claude Code loads a project's `CLAUDE.md` (falling back to `AGENTS.md`); Desktop, Cursor, Codex and OpenCode read `AGENTS.md`. This repo ships both. A `CLAUDE.md` at a *plugin* root is never loaded as plugin context, which is why this file is a contributor page, not an instruction file.
- **Hooks** — `hooks/hooks.json` is loaded by Claude Code and the Codex CLI; Cursor loads the separate bundle `platforms/cursor/hooks.json` (see [`docs/user/install/cursor.md`](docs/user/install/cursor.md)). The four core-safety guards — `protect-other-branches.sh`, `enforce-worktree-edits.sh`, `guard-sensitive-files.sh` (both wirings) and `docker-guard.py` — carry `onFailure: "block"` (Claude Code 2.1.295+): a guard that cannot start, times out or exits oddly blocks the action; advisory hooks stay fail-open, and `tests/test-manifest-invariants.sh` holds both sides. `StopFailure` with `"matcher": "rate_limit"` runs `hooks/rate-limit-handoff.sh`, which emits `systemMessage` because the turn has already failed and the user must read it — the moment you need `switch-dev` is the moment you cannot ask for it. Per-platform classification: [`hooks-classification.md`](docs/engineering/architecture/hooks-classification.md).
- **Mods** (Claude Code **2.1.287+**) — `mod/register.tsx` is a module of *function* hooks the engine runs in-process, named by the `modules` key of `hooks/hooks.json`, with its `$.state` contract at `mod/types/index.d.ts`. It is **additive**: every bash hook stays canonical, because a mod runs on Claude Code and the Desktop Code tab only. It draws live orchestration state (`/objective`, an objective pane, worker count on the spinner), shows a handoff-reminder band at `rate_limit_warn_percent`, draws the statusline figures on Desktop, adds a DoD line under answers that wrote files, folds a working-state snapshot into compaction, and enforces this file's commit trailer; its four gating-site hooks carry a pass-through `.catch`. Validated by `claude plugin validate .claude-plugin/plugin.json` (the `.` form never reads the mod) and `claude plugin test .` (`make test-mods`, 37 tests, both in CI). Design and validator rules: [`mods.md`](docs/engineering/architecture/mods.md).
- **MCP** — `.mcp.json` declares one stdio server (`github`, via `scripts/github-mcp.sh`), which takes its token through `${user_config.github_token}` and reads nothing off the machine.
- **Output styles** — `output-styles/evidence.md` ships `Evidence` (`keep-coding-instructions: true`, no `force-for-plugin`). Opt in with `/output-style Evidence`. Claude Code only.
- **Statusline** — `settings.statusLine` → `scripts/statusline.sh`. Claude Code only. Test with piped JSON: `echo '<session-json>' | bash scripts/statusline.sh` — it blocks forever on unpiped stdin. Schema and colours: [`statusline.md`](docs/engineering/statusline.md).
- **`Monitor`** — wraps a long-running Bash watch loop; every watch carries a deadline of at most 30 minutes. The one call here is [`pr-dev`'s CI-rollup wrapper](skills/dev-workflow/pr-dev/references/ci-monitor-loop.md).
- **`EnterWorktree`** — creates worktrees under `.claude/.worktrees/<name>`, the *legacy* layout; it stays supported, but new objectives use `.agent-worktrees/<objective>/` per [`git-worktree-agent-workflow.md`](rules/dev/git-worktree-agent-workflow.md). `resolve-worktree.sh` understands both.
- **Plugin state** — `${CLAUDE_PLUGIN_DATA}` is a per-plugin directory exported to hook and MCP/LSP processes that survives plugin updates. `hooks/lib/plugin-state.sh` resolves it with a mandatory fallback, because the Codex CLI loads the same `hooks.json` and exports no such variable.
- **Project memory** — `.claude/memory/` (versioned backup, reviewable in PRs) mirrored into a per-project transcript directory (auto-loaded each session). Keep them in sync; commit new memory files to `.claude/memory/`. The transcript directory name is *derived* from the clone's absolute path and shifts per machine; `CLAUDE_CODE_PROJECT_DIR_NAME` overrides it — pin it in your shell rc:

  ```bash
  export CLAUDE_CODE_PROJECT_DIR_NAME=tamirs-superpowers
  ```

  Restoring memory on a new machine prefers the pin; the fallback assumes a `~/Projects/tamirs-superpowers` clone:

  ```bash
  MEMORY_DIR=~/.claude/projects/${CLAUDE_CODE_PROJECT_DIR_NAME:--Users-$(whoami)-Projects-tamirs-superpowers}/memory
  mkdir -p "$MEMORY_DIR" && cp .claude/memory/* "$MEMORY_DIR/"
  ```

## Claude Code CLI baseline

Root [`.claude-code-version`](.claude-code-version) pins the Claude Code **host CLI** version the docs are written against — not `plugin-version.json`, this **plugin's own** release. The evidence-backed record is [`platform-targets.json`](docs/engineering/build-and-release/platform-targets.json) (`targets.claude_code`: `validated_against` = last live run; `reviewed_through`/`latest_known` = changelog read); `scripts/check-platform-version-pins.sh` (in `make validate`) holds the three root pins to it. Update the JSON first, then the pin.

## Anthropic's plugin directory

The directory tracks the tag `claude`, not `master`: `release.yml` builds the Claude-only subset of this tree (`scripts/build-claude-dist.sh`) from each release tag and moves `claude` onto it. Nobody develops on that tree. `make check-claude-dist` (in `make validate` and CI) holds the built tree to the directory's rules: credentials only as sensitive `userConfig` options, no bare `Bash`/`Skill` in `allowed-tools`, a mod that runs no process, and no `CHANGELOG.md` or `docs/engineering/` because the scanner reads prose about what the plugin *used* to do as what it does. Rules, rollback and resubmission: [`directory-distribution.md`](docs/engineering/build-and-release/directory-distribution.md).

## Marketplace cache

The installed copy lives under `~/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/<version>/`. Claude uses the manifest `version` as the update cache key — pushing commits without a bump does not reach installed users. After a release:

```text
/plugin marketplace update tamirs-marketplace
/plugin update tamirs-superpowers@tamirs-marketplace
```

`/reload-plugins` reloads the **local cache** only; it never fetches from GitHub. For local development, symlink the cache directory at your clone or run with `--plugin-dir` — never hand-edit the cache. Full mechanics: [`rules/dev/plugin-version-bump.md`](rules/dev/plugin-version-bump.md).

The version itself is edited in **one** place, `plugin-version.json`, then propagated with `bash scripts/check-version-truth.sh --sync`. Never hand-edit `.claude-plugin/plugin.json`'s version.

## Skill frontmatter on Claude

Every `SKILL.md` validates against the **portable** schema, [`core/schemas/skill-frontmatter.json`](core/schemas/skill-frontmatter.json). Claude Code's own frontmatter fields (invocation gating, tool allowlists, model hints, `effort`) are a documented **extension** of it, validated when present; a skill is not invalid for omitting one. Authoring rules: [`rules/dev/skill-quality-standards.md`](rules/dev/skill-quality-standards.md). Never hand-write a `SKILL.md` — use `skill-creator`. A host-side `maxEffortLevel` silently caps `effort: high`.

**Eval suite.** `claude plugin eval` runs [`evals/`](evals/README.md): eight cases on `skill-creator`, with and without the plugin, so the headline is the uplift (Δ). `Write`/`Edit`/`Bash` come only from the operator's `--allow-tools`; pass `--judge-model sonnet`; never point a case under `.claude/`.

### Invocation tiers (Claude-specific)

The two flags are **independent** — not a package deal:

- `user-invocable: false` — blocks the user typing `/skill-name`. Other skills, sub-agents and workflows can still call it via the `Skill` tool. This alone is what an internal companion wants.
- `disable-model-invocation: true` — blocks context-based auto-triggering **and sub-agent invocation**. It is a much heavier flag than it looks.

| Tier | `user-invocable` | `disable-model-invocation` | Examples |
|------|:---:|:---:|----------|
| User + auto-trigger (default) | `true` | `false` | plan-dev, start-dev, pr-dev, switch-dev, repo-standards, cleanup, retro |
| Explicit-only (slash, no auto) | `true` | `true` | *(none — see below)* |
| Internal companion | `false` | `false` | docs-review, mcp-pagination, changelog-review |

No skill is Explicit-only today. `switch-dev` was, and the gate cost the repo the skill's whole point: it is what an agent should reach for when a session hits a rate limit mid-objective, which is precisely when the user is not in a position to type `/switch-dev`, and the gate also made it unreachable from `orchestrate-dev`/`worker-dev` — so an orchestrated run that hit a limit could not hand off and simply died. Zero invocations across 953 sessions was the measured result.

**Gating warning:** `disable-model-invocation: true` also blocks **subagent and workflow orchestration** — a subagent invoking a skill *is* model invocation, so a gated skill cannot be fanned out across subagents. Gate only a skill that must *never* run autonomously. Prefer putting safety **inside** the skill: `cleanup` stays model-invocable with confirmation gates, a dry-run, and a script that only touches provably-safe targets; `retro` stays model-invocable because it only *proposes* changes and never writes without approval.

Internal-only skills today: `changelog-review`, `docs-review`, `mcp-pagination`. All three carry `user-invocable: false` and `disable-model-invocation: false` — hidden from the slash surface, still reachable from `repo-standards` and `mcp-builder` under orchestration. `docs-review` mutates files, so it confirms before its first write when no parent skill invoked it; that confirmation is the safety, not a gate.

## Surface skills at the moment they apply

Canonical, with the trigger table and the reasoning behind it: [`AGENTS.md`](AGENTS.md#surface-skills-at-the-moment-they-apply). The rule applies unchanged on Claude Code and Claude Desktop — it is written down precisely because `skill_auto_invocation` cannot be relied on everywhere, so a surface where auto-invocation *does* work is not exempt from it.

## Commit trailer

Claude sessions append:

```text
Co-Authored-By: Claude <noreply@anthropic.com>
```

Format and scopes are in [`AGENTS.md`](AGENTS.md#repo-specific-expectations).

## Remote and headless Claude sessions

Same validation commands as the [cloud runbook in `AGENTS.md`](AGENTS.md#cloud-and-headless-runbook). Hooks in `hooks/hooks.json` apply in Claude Code sessions only; a remote session without hook support must not assume worktree hooks ran. `/reload-plugins` works headless (`-p`/SDK). A `claude -p` session with no permission mode may start in `default` mode (2.1.302+), so pass one explicitly where a headless run needs auto.
