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
  <a href="plugin-version.json">
    <img src="https://img.shields.io/badge/version-3.0.0-blue" alt="Version" />
  </a>
</p>

<p align="center">
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Claude%20Code-2.1.233-blueviolet" alt="Claude Code" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Cursor-3.16.17-000000" alt="Cursor" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Codex-0.146.0-412991" alt="Codex" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Gemini%20CLI-0.55.1-4285F4" alt="Gemini CLI" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/OpenCode-1.18.11-fab283" alt="OpenCode" /></a>
</p>

# tamirs-superpowers

A portable agent toolkit: **25 skills**, 10 role-based agents, worktree hooks, and MCP
stubs, shipped from one canonical source to six agent platforms.

## What problem it solves

Agent harnesses disagree about everything — skill frontmatter, subagents, hooks, install
mechanics — so multi-platform setups either duplicate content per platform until it drifts,
or quietly claim features a platform does not have. And a single feature request typically
lands as five disconnected pull requests, one per task, with no place the combined diff is
ever reviewed.

This repo takes the other path:

- **One canonical source, thin adapters.** Skills, roles, rules, and policies live once
  under `skills/`, `core/`, and `rules/`. Per-platform files are generated or referenced,
  and drift is a CI failure.
- **Honest capability degradation.** [`core/capabilities/platforms.json`](core/capabilities/platforms.json)
  records what each platform actually supports — including `unknown` and `unsupported` —
  and every skill states its fallback instead of pretending.
- **One objective = one pull request.** Work is decomposed into tasks that end at
  *commit + handoff*, merged onto a single integration branch, reviewed as one diff, and
  delivered once.

## Supported platforms

| Platform | Registry id | Install |
|---|---|---|
| Claude Code | `claude_code` | [guide](docs/user/install/claude-code.md) |
| Claude Desktop | `claude_desktop` | [guide](docs/user/install/claude-desktop.md) — same plugin, different runtime surface |
| Codex CLI | `codex` | [guide](docs/user/install/codex.md) |
| Cursor | `cursor` | [guide](docs/user/install/cursor.md) |
| Gemini CLI | `gemini_cli` | [guide](docs/user/install/gemini.md) |
| OpenCode | `opencode` | [guide](docs/user/install/opencode.md) |

Capabilities differ per platform, sometimes a lot. The honest, registry-generated
comparison is [docs/user/platform-differences.md](docs/user/platform-differences.md).

## Install in 5 minutes

Pick your platform. Each guide covers install, **verify**, update, and uninstall.

```text
Claude Code      /plugin marketplace add Tamircohen28/tamirs-superpowers
                 /plugin install tamirs-superpowers@tamirs-superpowers
Claude Desktop   same marketplace listing as Claude Code
Cursor           Plugins → Team Marketplaces → Import from Repo → Tamircohen28/tamirs-superpowers
Codex CLI        codex plugin marketplace add Tamircohen28/tamirs-superpowers
                 codex plugin add tamirs-superpowers@tamirs-superpowers
Gemini CLI       gemini extensions install https://github.com/Tamircohen28/tamirs-superpowers --consent
                 gemini skills install   https://github.com/Tamircohen28/tamirs-superpowers --path .gemini/skills --consent
OpenCode         point opencode.json skills.paths at a clone
```

Gemini takes two commands on purpose: the extension carries context and MCP, while skills
come from a generated flat mirror at `.gemini/skills/` — `--path` is not optional there.
[Why](docs/user/install/gemini.md).

Requires `git` 2.30+ and `jq`. `gh` is an optional feature dependency (PR and issue
workflows). Nothing here needs Node, Python, or a build step.

Then check the install: `bash scripts/doctor.sh .`

> Contributing to this repo is a **different** setup — `git clone`, then `make validate`.
> See [contributor bootstrap](docs/engineering/build-and-release/development-workflow.md).
> Do not run `make install` to use the plugin; it bootstraps a Claude machine profile, not
> an install.

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

Orchestration works with **no subagents at all**: the same task graph runs sequentially,
same handoffs, same one PR. See [docs/user/orchestration.md](docs/user/orchestration.md).

## Links

- [Getting started](docs/user/getting-started.md) · [Concepts](docs/user/concepts.md) · [Configuration](docs/user/configuration.md) · [Troubleshooting](docs/user/troubleshooting.md)
- [Skills](docs/user/skills.md) · [Agents](docs/user/agents.md) · [Orchestration](docs/user/orchestration.md) · [Platform differences](docs/user/platform-differences.md)
- [Engineering docs](docs/engineering/README.md) — architecture, capability model, adapter contract, skill schema, release process
- [Changelog](CHANGELOG.md) · [Contributing](docs/CONTRIBUTING.md) · [Contributor bootstrap](docs/engineering/build-and-release/development-workflow.md) · [License](LICENSE)

---

Tamir Cohen · https://github.com/Tamircohen28
