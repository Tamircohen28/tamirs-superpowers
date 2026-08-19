# Install — Claude Desktop

**Claude Desktop is a runtime surface of the Claude adapter, not a separate plugin format.**

There is no Desktop manifest in this repo, and none should be created. Desktop consumes the
same [`.claude-plugin/plugin.json`](../../../.claude-plugin/plugin.json) from the same
marketplace listing as [Claude Code](claude-code.md). If you have already installed the
plugin for Claude Code, there is nothing else to install — the skills are there.

Registry id: `claude_desktop`, declared with `runtime_surface_of: claude_code`.

---

## Install

Install the plugin from the same marketplace listing used by Claude Code:

```text
/plugin marketplace add Tamircohen28/tamirs-superpowers
/plugin install tamirs-superpowers@tamirs-superpowers
```

or, from the catalog, `@tamirs-marketplace`. Installed plugins and their skills surface in
Desktop alongside its own commands.

MCP is configured differently here: Desktop is a long-standing MCP host, and server
configuration lives in the Desktop app's settings rather than in this repo's `.mcp.json`.

## Verify

Desktop has no CLI of its own, so verification is split.

**Repo-side, from a terminal with the Claude Code CLI available:**

```bash
claude plugin validate .
bash scripts/doctor.sh .
```

**Desktop-side, by hand** (this is a GUI surface; CI cannot exercise it):

1. Open Desktop and start a session in your project.
2. Confirm the toolkit's skills appear in the command list.
3. Invoke one by name — *"use the retro skill"* — and confirm it loads.

If a skill loads, the install is good. That is the whole check.

## Update

Update through Claude Code (`/plugin update tamirs-superpowers@tamirs-superpowers`) or from
Desktop's own plugin surface, then restart Desktop. Both read the same manifest `version`,
so an update without a version bump reaches neither.

## Uninstall

Uninstall the plugin the same way — once, from either surface. Removing it affects both,
because there is only one install.

---

## Capabilities and limitations

Desktop is the surface with the most honest gaps in the registry. Several capabilities are
`unknown`, which means **this repo has not exercised them there** and they are treated as
unavailable until someone records evidence.

| Capability | Status | What it means for you |
|---|---|---|
| skills · auto-invocation | native | Same plugin runtime as Claude Code |
| slash commands | native | Plugin commands surface alongside skills |
| MCP | native | Configured in the Desktop app, not in `.mcp.json` |
| plugin marketplace | native | Same listing as Claude Code |
| shell · git | partial | Available in coding sessions; absent in plain chat. Skills that need them will say so |
| subagents · parallel subagents | unknown | Assume roles run inline and sequentially |
| hooks | unknown | Assume no hooks fire; guards are in-skill steps plus CI |
| background tasks · worktree isolation · structured questions | unknown | Assume unavailable; stated fallbacks apply |
| GitHub CLI | unknown | Depends on the session's shell environment |
| session transcripts | unknown | No documented on-disk format — `/session-report` refuses rather than guessing |
| statusline | unsupported | No terminal chrome to render into. Cosmetic; nothing depends on it |
| extension install | unsupported | Not a Claude mechanism |
| artifacts | partial | A first-class Desktop feature, but nothing here can drive or validate one |

**Practical guidance:** use Desktop to invoke skills and read results; run heavy
orchestration in Claude Code, where subagents, hooks, and worktree automation are verified.

Source of truth: [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json).
Comparison: [platform differences](../platform-differences.md).
