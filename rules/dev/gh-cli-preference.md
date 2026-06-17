---
alwaysApply: false
globs: ["tooling/**/*", ".github/**/*", ".claude/skills/{plan-dev,start-dev,pr-dev}/**/*"]
---

# gh CLI Preference in Dev Context

In **development context** (contributor tooling, CI scripts, governance checks), use `gh` CLI for all GitHub operations. Do NOT use GitHub MCP tools for dev-time work.

## Rule

| Context | Use |
|---------|-----|
| Writing CI scripts, governance checks, build tooling | `gh` CLI |
| Writing `dev-env/` rules or commands | `gh` CLI examples |
| Plugin runtime agents investigating production issues | GitHub MCP (`octocode`, `githubSearchCode`, etc.) |

## Why

GitHub MCP tools are authenticated via `MCP_ACCESS_KEY` — a runtime credential tied to the investigation context. Using MCP tools in development scripts would:
1. Require a live MCP session for tasks that should be self-contained
2. Mix runtime and dev-time authentication paths
3. Create brittle CI scripts that fail without VPN + key

`gh` CLI uses `~/.config/gh/hosts.yml` — a separate, stable developer credential that works offline from VPN in many cases.

## Examples

```bash
# CORRECT — dev context
gh pr list --repo anthropics/production-master --state open
gh issue create --repo anthropics/production-master --title "..."
gh api repos/anthropics/claude-code/releases/latest

# WRONG — dev context
# githubSearchPullRequests(...)  ← MCP tool, runtime only
# githubGetFileContent(...)      ← MCP tool, runtime only
```

## Exceptions

- A plugin agent that investigates a GitHub repo as part of a production investigation uses GitHub MCP — that is runtime, not dev context.
- `docs/engineering/` instructions describing how an agent works may reference MCP tools.
