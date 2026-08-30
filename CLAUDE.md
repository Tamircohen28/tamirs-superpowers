# CLAUDE.md — tamirs-superpowers

Claude Code and Claude Desktop specifics for contributors. **Everything that is not Claude-specific lives elsewhere — start with [`AGENTS.md`](AGENTS.md)**, which is the shared entrypoint into [`core/`](core/) and [`rules/`](rules/README.md). This file adds only what is true of the Claude platform's two surfaces.

When this file and a canonical rule disagree, the canonical rule wins.

## What this repo is

A multi-platform agent plugin (skills, agents, hooks, MCP stubs) shipped to six supported surfaces across five platforms: Claude (Claude Code, Claude Desktop), Codex (Codex CLI), Cursor (Cursor IDE), Gemini (Gemini CLI), and OpenCode (OpenCode CLI). No build step, no `package.json`, no compiled output — Markdown, JSON, and Bash.

Claude Code and Claude Desktop are **one distribution**, not two formats: the same `.claude-plugin/plugin.json`, the same `skills/`, the same `agents/`. They are two **surfaces** of one platform: what differs is the runtime (installation path, no CLI flags, and the capability rows Desktop has never had measured), documented in [`docs/user/install/claude-desktop.md`](docs/user/install/claude-desktop.md).

## Commands

See [`AGENTS.md`](AGENTS.md#commands) for the full list. `make validate` before every push.

## Claude-only capabilities

Do not assume these exist on other providers — check [`core/capabilities/platforms.json`](core/capabilities/platforms.json) before relying on any of them, and degrade explicitly per [`core/policies/safety.md`](core/policies/safety.md).

- **Subagents** (`Agent` tool) — parallel worker execution, measured on Claude Code; not exercised on Desktop. Other providers run tasks sequentially or through their own mechanism. Since **Claude Code 2.1.243**, `/tasks` and the agent detail dialogs also show which model and effort level each subagent ran on — useful for spot-checking `orchestrate-dev`/`worker-dev` fan-outs without instrumenting anything here. The same release fixed background subagents not waking when their last background Bash task finished; if a fanned-out worker previously seemed to hang after its shell command completed, that was a host bug, not this repo's orchestration. Since **Claude Code 2.1.246**, a subagent that stops because it hit its own `maxTurns` limit now returns its output marked `partial` with a hint to continue it via `SendMessage` — this repo's own handoff vocabulary (`completed`/`partial`/`failed`/`blocked`, see [`worker-dev`](skills/dev-workflow/worker-dev/SKILL.md)) already treats `partial` as "decide, never quietly integrate around it," so a `maxTurns`-truncated worker now surfaces the same way a worker that self-reports `partial` does — no orchestrator change needed, but worth knowing the label can now come from the host, not just from the worker's own handoff file. Since **Claude Code 2.1.247**, a subagent whose first model call 404s no longer dies outright — it now falls back through the session's own fallback model chain with a detailed error, the same reliability class of fix as the two above; a fanned-out `worker-dev` task that previously looked like a hard failure on a transient model-routing error may now simply continue on a fallback model instead. Since **Claude Code 2.1.251**, `CLAUDE_CODE_SUBAGENT_MODEL` sets only the *default* subagent model instead of overriding every spawn: an agent definition's own `model:` field (every `agents/*.md` here pins one explicitly, e.g. `model: sonnet`) and an explicit per-spawn model now take precedence over it. Before this fix, a user or CI environment exporting `CLAUDE_CODE_SUBAGENT_MODEL` could silently run every specialist agent on the wrong model regardless of its frontmatter pin; that can no longer happen.
- **Hooks** — `hooks/hooks.json` is loaded by Claude Code and the Codex CLI only — the Cursor IDE plugin does not wire it; Gemini CLI and OpenCode CLI have their own or none. Since **Claude Code 2.1.247**, hook and background-task error output that previously could overflow the conversation with a "Prompt is too long" error, or leak memory unboundedly on repeated output-file write failures, is fixed host-side — relevant here given the volume of hooks this plugin wires (25 scripts across `PreToolUse`/`PostToolUse`/`SessionStart`/`SessionEnd`/`UserPromptSubmit`/worktree events), though no hook here needed a change: none of them write to an unbounded log file themselves.
- **Statusline** — wired via `.claude-plugin/plugin.json` `settings.statusLine` → `scripts/statusline.sh`. Claude Code only — Desktop has no terminal chrome to render into. Test with piped JSON: `echo '<session-json>' | bash scripts/statusline.sh` — it blocks forever on unpiped stdin.
- **`EnterWorktree`** — automates worktree creation under `.claude/.worktrees/<name>`. That is the *legacy* layout; it stays supported and is never orphaned, but new objectives use `.agent-worktrees/<objective>/` per [`rules/dev/git-worktree-agent-workflow.md`](rules/dev/git-worktree-agent-workflow.md). `resolve-worktree.sh` understands both.
- **Project memory** — `.claude/memory/` (versioned backup, reviewable in PRs) mirrored into a per-project transcript directory (auto-loaded each session). Keep them in sync; commit new memory files to `.claude/memory/`. The transcript directory name is normally *derived* from the clone's absolute path (`-Users-<you>-Projects-tamirs-superpowers`), which shifts per machine/username and breaks if the clone moves. Since **Claude Code 2.1.234**, `CLAUDE_CODE_PROJECT_DIR_NAME` overrides that derivation — pin it (e.g. in `~/.zshrc`/`~/.bashrc`, or per-session) for a stable, machine-independent name:

  ```bash
  export CLAUDE_CODE_PROJECT_DIR_NAME=tamirs-superpowers
  ```

  Restoring memory on a new machine prefers the pin when set, falling back to the derived path otherwise:

  ```bash
  MEMORY_DIR=~/.claude/projects/${CLAUDE_CODE_PROJECT_DIR_NAME:--Users-$(whoami)-Projects-tamirs-superpowers}/memory
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

Internal-only skills today: `changelog-review`, `docs-review`, `mcp-pagination`. All three carry `user-invocable: false` and `disable-model-invocation: false` — hidden from the slash surface, still reachable from `repo-standards` and `mcp-builder` when those run under orchestration. `docs-review` mutates files, so it confirms before its first write when no parent skill invoked it; that confirmation is the safety, not a gate.

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

## Commit trailer

Claude sessions append:

```text
Co-Authored-By: Claude <noreply@anthropic.com>
```

Format and scopes are in [`AGENTS.md`](AGENTS.md#repo-specific-expectations).

## Remote and headless Claude sessions

Same validation commands as the [cloud runbook in `AGENTS.md`](AGENTS.md#cloud-and-headless-runbook). Hooks in `hooks/hooks.json` apply in Claude Code sessions only; a remote session without hook support must not assume worktree hooks ran.
