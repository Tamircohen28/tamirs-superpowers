# mcp-builder permission gates

`scripts/gate.sh` asks `scripts/resolve-permission.sh` (ADR 004 D4) about one step and prints one line; SKILL.md's
[Permission gates](../SKILL.md#permission-gates) section says what to do with each exit code.

## Which step is which action

| Step | `<action-id>` | R | Target to pass |
|---|---|---|---|
| `npm install …`, `pip install …` (Phase 2) | `pkg.install.network` | R3 | the exact command, flags included |
| `npx @modelcontextprotocol/inspector…`, `fastmcp dev …` (Phase 4) | `pkg.exec.network` | R3 | the exact command |
| a client config outside the project directory (Phase 6): the user-level Claude Code config, `claude_desktop_config.json`, anything under `~/.codex/`, `~/.cursor/`, `~/.gemini/`, `~/.config/opencode/` | `config.global.write` | R4 | the absolute path of the file |

Writes inside the project (the scaffold, `.mcp.json`, `.cursor/mcp.json`, `.gemini/settings.json`, `opencode.json`,
a project `.codex/config.toml`) are ordinary repo edits: no gate.

## Why each step is approved on its own

The target is what the user approves. A yes to `npm install --ignore-scripts` is not a yes to the same install with
scripts on, and an early "go ahead with everything" was given before the user could see the command or file. So every
gated step is asked with its own exact target, and there is no `--yes` flag: an unknown flag is a usage error.

## Headless

A subagent, a workflow, `claude -p` or CI has no one to answer an ask. Pass `--headless` (`CI=true` in the
environment implies it) and the resolver turns ask into a block. `config.global.write` is R4, which no setting makes
automatic: headless, it is always blocked — hand the user the entry and the file instead.

## Fail closed

No resolver, a non-zero exit, output that is not JSON or carries no verdict, or no `jq`: exit 3. The resolver is found
from the script's own location inside the plugin, never from an environment variable.
