<p align="center">
  <img src="assets/banner.png" alt="tamirs-superpowers" width="600" />
</p>

<p align="center">
  <a href="https://github.com/Tamircohen28"><img src="https://img.shields.io/badge/author-Tamir%20Cohen-181717?logo=github" alt="Author" /></a>
  <a href="https://github.com/Tamircohen28/tamirs-superpowers/actions/workflows/ci.yml"><img src="https://github.com/Tamircohen28/tamirs-superpowers/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License" /></a>
  <a href="plugin-version.json"><img src="https://img.shields.io/badge/version-3.3.0-blue" alt="Version" /></a>
</p>

<p align="center">
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Claude%20Code-2.1.233-blueviolet" alt="Claude Code" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Cursor-3.18.9-000000" alt="Cursor" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Codex-0.146.0-412991" alt="Codex" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Gemini%20CLI-0.55.1-4285F4" alt="Gemini CLI" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/OpenCode-1.18.11-fab283" alt="OpenCode" /></a>
</p>

# tamirs-superpowers

A portable agent toolkit: **27 skills**, 10 role-based agents, worktree hooks, and MCP
stubs, shipped from one canonical source to six agent surfaces across five platforms.

## What problem it solves

Agent harnesses disagree about everything — skill frontmatter, subagents, hooks, install
mechanics, where global config lives — so multi-platform setups duplicate content until it
drifts, or claim features a platform does not have. And one feature request typically lands
as five disconnected pull requests with no place the combined diff is ever reviewed.

- **One canonical source, thin adapters.** Skills, roles, rules, and policies live once
  under `skills/`, `core/`, and `rules/`; per-platform files are generated, and drift fails CI.
- **Honest capability degradation.** [`core/capabilities/platforms.json`](core/capabilities/platforms.json)
  records what each *surface* actually supports — `unknown` and `unsupported` included — and
  every skill states its fallback instead of pretending.
- **One objective = one pull request.** Work is decomposed into tasks that end at
  *commit + handoff*, merged onto one integration branch, reviewed as one diff, delivered once.
- **Your machine is rendered from the repo.** `make setup` writes the same global rules into
  all five platforms' own config formats; nothing is hand-copied per platform.

## Supported platforms

Five platforms. Each one has more than one **surface** — a terminal client, a desktop app,
an editor extension — and they do not all behave alike, so the surface is what carries a
support status, an install path, and a capability row. Six surfaces are supported: those
are the ones this repo installs into and validates. The rest are listed because they are
real surfaces users ask about; nothing has been measured on them, in either direction.

### Claude

One plugin, one marketplace listing, both surfaces.

| Surface | Registry id | Kind | Status | Install |
|---|---|---|---|---|
| Claude Code | `claude_code` | CLI | ✅ supported — validated 2.1.233 | [guide](docs/user/install/claude-code.md) |
| Claude Desktop | `claude_desktop` | desktop | ✅ supported — same plugin, different runtime surface | [guide](docs/user/install/claude-desktop.md) |

### Codex

Installed from the plugin marketplace; the CLI is the measured surface.

| Surface | Registry id | Kind | Status | Install |
|---|---|---|---|---|
| Codex CLI | `codex` | CLI | ✅ supported — validated 0.146.0 | [guide](docs/user/install/codex.md) |
| Codex IDE extension | `codex_ide` | IDE | ⚠️ unverified — reads the same `AGENTS.md` and manifest, but the plugin has never been installed or a skill invoked there | — |

### Cursor

Added as a plugin source in Cursor, then installed from it.

| Surface | Registry id | Kind | Status | Install |
|---|---|---|---|---|
| Cursor IDE | `cursor` | IDE | ✅ supported — validated 3.16.17 | [guide](docs/user/install/cursor.md) |
| Cursor CLI | `cursor_cli` | CLI | ⚠️ unverified — shares the plugin manifest with the IDE, but no CLI run has been recorded here | — |

### Gemini

Two commands: the extension carries context and MCP, skills install separately.

| Surface | Registry id | Kind | Status | Install |
|---|---|---|---|---|
| Gemini CLI | `gemini_cli` | CLI | ✅ supported — validated 0.55.1 | [guide](docs/user/install/gemini.md) |
| Gemini Code Assist | `gemini_code_assist` | IDE | ⚠️ unverified — a different host that does not install CLI extensions, so the `.gemini/` mirror has no established install path there | — |

### OpenCode

Installed by path — `opencode.json` `skills.paths` pointed at this checkout.

| Surface | Registry id | Kind | Status | Install |
|---|---|---|---|---|
| OpenCode CLI | `opencode` | CLI | ✅ supported — validated 1.18.11 | [guide](docs/user/install/opencode.md) |
| OpenCode desktop app | `opencode_desktop` | desktop | ⚠️ unverified — whether it reads the same `skills.paths` this repo installs into has not been checked | — |

`⚠️ unverified` is not a negative result. Those surfaces carry no capability claims at all;
[`core/capabilities/platforms.json`](core/capabilities/platforms.json) records why each one
was never measured rather than guessing from its sibling.

Capabilities differ per surface, sometimes a lot. The honest, registry-generated comparison
is [docs/user/platform-differences.md](docs/user/platform-differences.md).

## Install in 5 minutes

**1. Install the plugin.** Pick your platform and surface from the tables above — each
supported surface's guide covers install, **verify**, update, and uninstall. Gemini alone
takes two commands: the extension carries context and MCP, while skills come from a generated
flat mirror at `.gemini/skills/` that must be installed with `--path`. [Why](docs/user/install/gemini.md).

**2. Configure your machine** — optional, and now the part that changed. `make setup`
renders this repo's canonical config into the config directory of **every** agent CLI it
detects: `~/.claude`, `~/.codex`, `~/.cursor`, `~/.gemini`, `~/.config/opencode`. One set of
global rules, one permissions policy, in each platform's own format.

```bash
git clone https://github.com/Tamircohen28/tamirs-superpowers.git
cd tamirs-superpowers
make setup-plan     # detect targets, print every change, write nothing
make setup          # diff → confirm → write, one change at a time
```

It merges into what is already there, shows a diff before each write, defaults to No, and
`bash scripts/setup.sh remove` undoes it. This supersedes `make install`, which configured
only Claude Code, only partially, and rewrote `~/.claude/settings.json` wholesale — the old
path is now a thin shim over the same engine. **Read [setup](docs/user/setup.md) before the
first `apply`:** it will switch off plugins the canonical set records as deliberately
disabled. The other four platforms: [platform setup](docs/user/platform-setup.md).

Requires `git` 2.30+ and `jq`; `gh` is optional (PR and issue workflows). Nothing here needs
Node, Python, or a build step. Check the result with `bash scripts/doctor.sh .`.

> Contributing to this repo is a **different** setup — `git clone`, then `make validate`.
> See [contributor bootstrap](docs/engineering/build-and-release/development-workflow.md).

## Core workflow

```text
/orchestrate-dev  →  task graph  →  workers (commit + handoff)  →  integration branch
                                          →  combined-diff review  →  ONE PR  →  /pr-dev
```

| Skill | Does |
|---|---|
| [`/plan-dev`](skills/dev-workflow/plan-dev/SKILL.md) | Turn a request into phases and issues |
| [`/orchestrate-dev`](skills/dev-workflow/orchestrate-dev/SKILL.md) | Own an objective: task graph, dispatch, integrate, deliver one PR |
| [`/worker-dev`](skills/dev-workflow/worker-dev/SKILL.md) | Execute one task; end at commit + handoff, never a PR |
| [`/deliver-dev`](skills/dev-workflow/deliver-dev/SKILL.md) | Review the integrated diff, run the gates, open the one PR |
| [`/pr-dev`](skills/dev-workflow/pr-dev/SKILL.md) | Drive that PR to merge |
| [`/start-dev`](skills/dev-workflow/start-dev/SKILL.md) | Compatibility front door — routes to the above |

Orchestration works with **no subagents at all**: same task graph, same handoffs, same one
PR, run sequentially. See [docs/user/orchestration.md](docs/user/orchestration.md).

## Links

- [Getting started](docs/user/getting-started.md) · [Setup](docs/user/setup.md) · [Platform setup](docs/user/platform-setup.md) · [Capture](docs/user/capture.md) · [Configuration](docs/user/configuration.md) · [Troubleshooting](docs/user/troubleshooting.md)
- [Concepts](docs/user/concepts.md) · [Skills](docs/user/skills.md) · [Agents](docs/user/agents.md) · [Orchestration](docs/user/orchestration.md) · [Platform differences](docs/user/platform-differences.md)
- [Engineering docs](docs/engineering/README.md) — architecture, capability model, adapter contract, skill schema, release process
- [Changelog](CHANGELOG.md) · [Contributing](docs/CONTRIBUTING.md) · [Contributor bootstrap](docs/engineering/build-and-release/development-workflow.md) · [License](LICENSE)

---

MIT © [Tamir Cohen](https://github.com/Tamircohen28)
