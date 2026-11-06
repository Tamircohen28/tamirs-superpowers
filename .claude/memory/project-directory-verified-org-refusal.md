---
name: project-directory-verified-org-refusal
description: "Since 5.5.1 (2026-11-06) the plugin directory REFUSES versions with command hooks, local MCP servers, settings commands or a mod from unverified orgs; the claude tag now carries a skills/agents-only 'directory edition' (5.6.2). Supersedes the policy-hold notes"
metadata:
  node_type: memory
  type: project
  originSessionId: 24913b40-9931-473f-97b4-0cc26fdc1a9e
  modified: 2026-11-06T05:28:13.109Z
---

On 2026-11-06 the directory portal showed 5.5.1 and 5.6.0 as **Failed** (an automatic check
stopped them), on four blocking findings: `LOCAL_CODE_HOOK_COMMAND`, `LOCAL_CODE_MCP_SERVER`,
`LOCAL_CODE_SETTINGS_COMMAND`, `LOCAL_CODE_MOD` — "accepted only from Verified organizations",
with no way to apply yet. 5.5.0, picked up earlier, stayed "In review". The earlier policy holds
(`HOOK_GRANTS_PERMISSION`, `COMMAND_NAMES_MOD_FILE`) were already gone by then; the 5.6.1 hook
rewrite still shipped, but did not decide anything for the directory.

**Why:** a directory rule change, not a defect in the plugin. The full plugin is unaffected and
ships from the tamirs-marketplace.

**How to apply:** the `claude` target of `scripts/build-dist.sh` is the *directory edition* —
skills, agents, the output style; no `hooks/`, `mod/`, `.mcp.json`, no `hooks`/`mcpServers`/
`settings`/`types`/`userConfig` in the manifest copy, no `notify-setup` (it needs the
Notification hook). `check-claude-dist.sh` fails a tree that carries any of them. Do not spend
effort on hook/mod/MCP directory findings unless Verified status becomes available. After each
release, read the portal's version status ([[feedback-session-wall-time]]). Supersedes the
structural-hold notes in [[project-directory-submission-holds]].
