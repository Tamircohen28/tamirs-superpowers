<p align="center">
  <img src="assets/banner.png" alt="tamirs-superpowers" width="600" />
</p>

<p align="center">
  <a href="https://github.com/Tamircohen28">
    <img src="https://img.shields.io/badge/author-Tamir%20Cohen-181717?logo=github" alt="Author" />
  </a>
  <a href="https://github.com/Tamircohen28/tamirs-superpowers/actions/workflows/ci.yml">
    <img src="https://github.com/Tamircohen28/tamirs-superpowers/actions/workflows/ci.yml/badge.svg" alt="CI" />
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License" />
  </a>
  <a href=".claude-plugin/plugin.json">
    <img src="https://img.shields.io/badge/version-2.0.0-blue" alt="Version" />
  </a>
</p>

<p align="center">
  <a href="docs/engineering/build-and-release/platform-targets.json">
    <img src="https://img.shields.io/badge/Claude%20Code-2.1.228-blueviolet" alt="Claude Code" />
  </a>
  <a href="docs/engineering/build-and-release/platform-targets.json">
    <img src="https://img.shields.io/badge/Cursor-3.14.7-000000" alt="Cursor" />
  </a>
  <a href="docs/engineering/build-and-release/platform-targets.json">
    <img src="https://img.shields.io/badge/Codex-0.146.0-412991" alt="Codex" />
  </a>
  <a href="docs/engineering/build-and-release/platform-targets.json">
    <img src="https://img.shields.io/badge/OpenCode-1.18.11-fab283" alt="OpenCode" />
  </a>
</p>

# tamirs-superpowers

A multi-platform agent plugin for the **four supported targets — Claude Code, Cursor, Codex, and OpenCode** — bundling 27 skills, 6 specialist agents, smart worktree hooks, and MCP server stubs. It installs **standalone from this repo** on every target, and is also published through the [`tamirs-marketplace`](https://github.com/Tamircohen28/tamirs-marketplace) catalog.

**Per-target install guides:** [Claude Code](docs/user/install/claude-code.md) · [Cursor](docs/user/install/cursor.md) · [Codex](docs/user/install/codex.md) · [OpenCode](docs/user/install/opencode.md) · [index](docs/user/install/README.md)

## Features

- **26 bundled skills** — plan, implement, hand off across Claude/Cursor/Codex, drive PRs to merge, audit repo standards, multi-agent setup, debug, run session retrospectives, create and benchmark skills, and more, all from the Claude Code prompt
- **6 specialist agents** — architecture-reviewer, debugging-specialist, performance-reviewer, research-agent, security-reviewer, test-engineer; available via the Agent tool in any session
- **Smart worktree hooks** that automatically create isolated git worktrees per task, derive task slugs from your first prompt, enforce edit isolation, guard sensitive files, and show Claude Code changelogs on update
- **MCP server stubs** for GitHub and Context7 — fill in your tokens and they're live
- **Statusline** showing git branch, worktree state, and session context in your Claude Code footer
- **Phone notifications (opt-in)** via [Pushover](https://pushover.net) — get pushed when Claude goes idle or needs permission, alongside the macOS desktop banner. Inert until configured; set up with `/tamirs-superpowers:notify-setup`

## Prerequisites

- At least one supported target — **Claude Code** 2.0+, **Cursor** 3.14.7+, **OpenAI Codex CLI** 0.40+, or **OpenCode** 1.16.2+ (see [per-target install](docs/user/install/README.md))
- `jq` (for hooks): `brew install jq`
- `git` 2.30+ (for worktree hooks)
- `gh` CLI (for `pr-dev`, `plan-dev`, `start-dev` skills): `brew install gh`

## Quick Start

### All platforms — bootstrap from clone

```bash
git clone git@github.com:Tamircohen28/tamirs-superpowers.git
cd tamirs-superpowers
make install    # ~/.claude/settings.json + specialist agents
```

`make update` refreshes agents and runs `claude plugin update` when the CLI is available.
`make uninstall` removes installed agents and attempts plugin uninstall.

### Claude Code — [full guide](docs/user/install/claude-code.md)

Via the catalog, or standalone from this repo:

```text
/plugin marketplace add Tamircohen28/tamirs-marketplace
/plugin install tamirs-superpowers@tamirs-marketplace
```

```text
/plugin marketplace add Tamircohen28/tamirs-superpowers   # standalone
/plugin install tamirs-superpowers
```

Since Claude Code 2.1.221, installed plugins activate immediately when safe — no
reload step. On older versions, finish with `/reload-plugins`.

### Cursor — [full guide](docs/user/install/cursor.md)

Dashboard → **Plugins** → **Team Marketplaces** → **Add Marketplace** → **Import from Repo**, pointed at `Tamircohen28/tamirs-superpowers` (or `Tamircohen28/tamirs-marketplace`). Cursor reads [`.cursor-plugin/plugin.json`](.cursor-plugin/plugin.json), `skills/`, [`.cursor/rules/`](.cursor/rules), `agents/`, hooks, and MCP stubs. Enable **Auto Refresh** and pushes propagate without a version bump.

### Codex — [full guide](docs/user/install/codex.md)

```bash
codex plugin marketplace add Tamircohen28/tamirs-superpowers
codex plugin add tamirs-superpowers@tamirs-superpowers
```

Backed by [`.agents/plugins/marketplace.json`](.agents/plugins/marketplace.json) (the manifest Codex actually resolves) and [`.codex-plugin/plugin.json`](.codex-plugin/plugin.json) — `skills/`, [`hooks/hooks.json`](hooks/hooks.json), MCP stubs. Codex reads root [`AGENTS.md`](AGENTS.md) for working agreements.

### OpenCode — [full guide](docs/user/install/opencode.md)

OpenCode has no plugin marketplace; it reads skills from disk. Symlink the clone into a scanned path:

```bash
git clone https://github.com/Tamircohen28/tamirs-superpowers.git ~/src/tamirs-superpowers
ln -s ~/src/tamirs-superpowers/skills ~/.config/opencode/skills
cp ~/src/tamirs-superpowers/.opencode/agent/*.md ~/.config/opencode/agent/
```

Agents ship pre-translated in [`.opencode/agent/`](.opencode/agent) because OpenCode rejects Claude's agent frontmatter. Hooks do not port — OpenCode has no `hooks.json`.

### Verify

Restart the IDE or run `/reload-plugins` (Claude Code). MCP servers (`github`, `context7`) wire from `.mcp.json`; `github` uses `gh auth login` — no manual token env vars.

> **Statusline not showing?** The statusline is wired automatically via
> [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) `settings.statusLine` — no manual
> setup is normally needed. If the footer statusline doesn't appear after restart, add it
> manually: run `/config` in Claude Code and set `statusLine`, or add it directly to
> `~/.claude/settings.json`. Use the **same version-agnostic glob as the manifest** so the entry
> keeps working across plugin updates:
> ```json
> { "statusLine": { "type": "command", "command": "f=$(ls $HOME/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/*/scripts/statusline.sh 2>/dev/null | sort -rV | head -1) && [ -n \"$f\" ] && bash \"$f\"" } }
> ```
> Do **not** hardcode a version directory, and do not drop the `scripts/` path segment. A pinned
> or mistyped path stops matching, and because the command guards with `&& [ -n "$f" ]`, Claude
> Code renders an empty statusline rather than an error — the breakage is silent. A user-level
> `statusLine` entry also takes precedence over the manifest's, so a stale manual copy will
> shadow the working default.

## Bundled Skills

Each skill lives at `skills/<skill-name>/SKILL.md`.

| Skill | What it does |
|---|---|
| `/tamirs-superpowers:plan-dev` | Plan work into phases and create GitHub issues (with Resume blocks for cross-platform handoff). |
| `/tamirs-superpowers:start-dev` | Create platform worktree, implement, validate, push, and open a PR. |
| `/tamirs-superpowers:switch-dev` | Hand off, resume, or list status for work across Claude Code, Cursor, and Codex via GitHub issue Resume blocks. |
| `/tamirs-superpowers:pr-dev` | Drive a PR to merge — address review threads, fix CI, squash-merge after explicit approval. |
| `/tamirs-superpowers:decision` | Summarize a pending decision or GitHub issue/PR in plain language and hand it back as an `AskUserQuestion` menu — walks through multiple open decisions/action items one at a time. |
| `/tamirs-superpowers:multi-agent-repo` | Audit, plan, and implement canonical multi-agent setup (AGENTS.md + thin adapters + drift checks) across Claude Code, Cursor, and Codex — review / plan / dev modes. Replaces former `plugin-compat`. |
| `/tamirs-superpowers:targeted-debug` | Scope-bounded debug from a stack trace — reads only named files. |
| `/tamirs-superpowers:repo-standards` | Audit, plan, and polish repos to Tamir Cohen standards — README, docs, CI/CD, branch rules, employer IP scan, hygiene, and multi-agent setup. Auto-detects `app-gold` vs `plugin-gold` (agent-kit repos with `canonical/`). |
| `/tamirs-superpowers:repo-scaffold` | Create a new private GitHub repo from scratch — app repos (`app-gold`) or agent-kit plugin distribution repos (`--type plugin` → `plugin-gold`: canonical rules/skills, marketplace, dist/ adapters). |
| `/tamirs-superpowers:cleanup` | Full repo housekeeping: delete merged/stale remote branches, drive all open PRs via sub-agents, remove unused local worktrees, rescue or discard uncommitted work, delete build artifacts, and reset local env to match remote. |
| `/tamirs-superpowers:mcp-builder` | Build MCP servers (auto-invokes `mcp-pagination` for list/search tools). |
| `/tamirs-superpowers:find-skill` | Search skill marketplaces and rank matches for a query. |
| `/tamirs-superpowers:retro` | Session postmortem — find friction (low quality, looping, missed parallelism) and propose rule/hook/memory/skill improvements. Proposes, then waits for approval before writing any files. |
| `/tamirs-superpowers:skill-creator` | Create, improve, and benchmark Claude Code skills. |
| `/tamirs-superpowers:session-report` | Generate an HTML report of session token usage. |
| `/tamirs-superpowers:notify-setup` | Set up opt-in Pushover phone notifications so Claude reaches you away from the desk — collects both credentials, validates, wires the hook, sends a test. Complements the macOS desktop banner. |
| `/tamirs-superpowers:algorithmic-art` | Generate algorithmic art with p5.js. |
| `/tamirs-superpowers:field-notebook-ui` | Generate interactive React artifacts in the engineer's field-notebook visual style. |
| `/tamirs-superpowers:dark-terminal-doc` | Generate polished HTML docs with a dark terminal design system. |
| `/tamirs-superpowers:platform-sync` | Audit **any** repo using Claude Code, Codex, or Cursor — detect targets via manifests, CLAUDE.md, AGENTS.md, `.cursor/rules/`, etc.; fetch live docs; synthesize a numbered improvement plan. |

Internal skills (invoked by parent skills, not shown in `/` menu): `docs-review`, `changelog-review`, `mcp-pagination`, `platform-sync-claude`, `platform-sync-codex`, `platform-sync-cursor`.

## Companion plugins (install separately)

`.claude-plugin/plugin.json` declares **no** `dependencies` — nothing auto-installs alongside this plugin. These pair well with it and are worth adding by hand:

| Plugin | Marketplace | What it does |
|---|---|---|
| `superpowers` | `obra/superpowers` | Jesse Vincent's skills framework. |

## Hooks

`hooks/hooks.json` wires 10 lifecycle events:

| Event | Script(s) | Purpose |
|---|---|---|
| `PreToolUse (Bash\|Shell)` | `protect-other-branches.sh` | Block editing PRs from other authors. |
| `PreToolUse (Edit\|Write\|…)` | `enforce-worktree-edits.sh` | Refuse repo edits outside the task worktree. |
| `PreToolUse (Edit\|Write\|…)` | `guard-sensitive-files.sh`, `skill-creator-guard.sh` | Block edits to lockfiles/build output; enforce `/skill-creator` for SKILL.md edits. |
| `PostToolUse (Edit\|Write)` | `plugin-reload-reminder.sh`, `wix-ip-guard.sh` | Remind to reload after plugin file edits; warn on Wix IP references. |
| `PostToolUse (Write)` | `validate-report-links.sh` | Validate URLs in report.md files. |
| `SessionStart` | `show-changelog.sh`, `session-init.sh` | Show Claude Code changelog on update; seed session state. |
| `SessionEnd` | `session-end.sh`, `handoff-reminder.sh` | Archive session-files, prune stale worktrees; remind to run `/switch-dev handoff` from active worktrees. |
| `UserPromptSubmit` | `capture-task-slug.sh`, `goal-compact-reminder.sh`, `ensure-exit.sh` | Derive task slug, create worktree; remind to compact before /goal; check exit node. |
| `WorktreeCreate` | `worktree-create.sh` | Create global worktree under `~/.claude/worktrees/`. |
| `WorktreeRemove` | `worktree-remove.sh` | Tear down global worktree cleanly. |
| `Notification` | `notify.sh` | macOS desktop banner (prefixed with the task slug) when Claude needs attention. |
| `Notification` | `notify-pushover.sh` | **Opt-in** — phone push via [Pushover](https://pushover.net) so Claude reaches you away from the desk. Fires alongside `notify.sh`; inert until configured. See [Phone notifications](docs/user/phone-notifications.md) or run `/tamirs-superpowers:notify-setup`. |
| `Stop` | `check-done.sh` | Remind to verify lint/tests before claiming done. |

When a worktree is created, the hooks also: copy gitignored files matched by
`~/.claude/defaults/worktreeinclude` then the repo's `.worktreeinclude` (e.g.
`.env.local`, credentials); assign a deterministic per-branch `DEV_PORT` in
`.env.local` so parallel worktrees don't collide; and install dependencies in
the background (`npm ci` / `yarn` / `pnpm` / `poetry`, skipped when
`node_modules` already exists), logging to `.session-files/worktree-setup.log`.

## Documentation

- [User docs](docs/user/README.md) — concepts, quick start, troubleshooting
- [Skill reference](docs/user/reference.md) — every skill explained with examples
- [Agent-kit repos](docs/user/agent-kit.md) — scaffold and maintain multi-platform rule/skill distribution repos (`repo-scaffold --type plugin`)
- [Engineering docs](docs/engineering/README.md) — architecture, development workflow, decisions
- [Changelog](CHANGELOG.md)
- [Contributing](docs/CONTRIBUTING.md)

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).

---

Tamir Cohen · https://github.com/Tamircohen28
