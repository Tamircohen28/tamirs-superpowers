# OpenCode 2.2.5 — live characterization (2026-10-31)

Evidence for the `opencode-v2-cutover` objective (task-001, issue #315). Binary: `opencode v2.2.5`
(`@opencode/cli` npm `latest`). Every probe ran from a fresh `HOME`/`XDG_*` so no user config leaked in.
Probes against the repo ran in a linked worktree of `origin/master` c424716.

## 1. `plugin list` / `mcp list` "empty" — a cold-start artifact, not a regression

| Probe | Result |
|---|---|
| `opencode --standalone plugin list` / `mcp list` (private server) | always `No plugins found` / `No MCP servers configured`, repo and a bare control project alike |
| service mode, **first** call on a fresh service | empty |
| service mode, **second** call onward (after ~5 s) | `tamirs-superpowers.guard` listed; `github` MCP listed with the launcher's own "github_token is not set" message |
| control project (`echo` MCP server), warm | server listed as `failed: exited with code 0` |

Conclusion: the directory is bootstrapped lazily; the first list call triggers the load and reports
nothing. `--standalone` never showed the lists. **Verification recipe for the docs: run the service
(no `--standalone`), call `opencode mcp list` / `plugin list` twice, ~5 s apart.** The 2.0.32
recipe in `docs/user/install/opencode.md` ran them once and happened to be warm.

Side observation: in a linked git worktree `plugin list` shows the plugin from **both** the worktree
path and the main checkout path (same id `tamirs-superpowers.guard`). Not yet known whether the guard
then runs twice; task-004 should check.

## 2. Config and agents

- `opencode --standalone debug config` loads this repo's `opencode.json` with keys `mcp`, `permissions`,
  `plugins`, `skills` and the `.opencode/` directory. `debug agents` loads all 10 generated agents.
- `api skill.list` returns only the three built-ins (OpenCode, Report, Browser) in both this repo and a
  control project that has `.opencode/skills/demo/SKILL.md` and a `skills` config path — user skills do
  not appear there, warm or cold. **Skill discovery stays unverifiable from the CLI** (unchanged from 2.0.32).

## 3. Permissions

`bash scripts/check-opencode-permission-keys.sh . --refresh`: published schema still types
`Permission.Rule {action: string, resource, effect}` with `action` unenumerated; every pinned action
is still named at https://opencode.ai/v2/docs/permissions/; the 10 generated agents emit only v2 Core
actions, no v1 keys. The pin does not need to change for 2.2.5.

`bash` alias (2.2.5): the guard's permission hook keys on `e.action === "edit"` / `"shell"`
(`platforms/opencode/plugin/guard.ts:231,243`), and 2.2.5 runs a `bash` tool call as `shell` with the same
permissions, so the alias does not bypass the guard. A test should still pin it (task-006).

## 4. What changed between 2.0.32 and 2.2.5 (this repo's surface only)

Sources: release notes v2.2.0–v2.2.5; the 942 commits of `v2.0.32...v2.2.0` (2.1.x publishes no notes);
PR #57260 "v2.1 minor breaking changes".

| Change | Where | Affects us |
|---|---|---|
| `@opencode/plugin` peers `@opentui/core` + `@opentui/solid` `>=0.8.0` (0.7 in 2.2.0, 0.8 in 2.2.3); `solid-js >=1.9.0`; `@opencode/theme 2.2.5` | npm peerDependencies of `@opencode/plugin@2.2.5` | **yes** — our peer range is `>=0.5.17` |
| OpenTUI 0.8: ScrollBox wrapper/viewport/content are facades; custom `RenderContext` needs `clock` | v2.2.3 notes | `tui.tsx` to re-check |
| 2.1: provider replay fields `state`/`providerState`/`resultState` renamed `native` | #57260 | our TUI reads only `session.step.ended` and `session.tool.success` events; neither reads those fields — typecheck against 2.2.5 types to confirm |
| `ctx.session.instructions.entry.put/list/remove` | #56550 / v2.2.0 | optional adoption (task-004) |
| Managed policy: `mcp.use`, `skill.use`, `plugin.use` actions; old `mcp:`/`skill:`/`plugin:` prefixes auto-converted | v2.2.3 | no repo change; document for managed users |
| `bash` tool calls run as `shell` | v2.2.5 | none (see section 3) |
| `compaction.buffer` accepts a percentage | v2.2.5 | not adopted |
| GitHub Action removed; `@opencode/ai` root is the Promise API | v2.2.0 | none (we use neither) |
| Skill discovery bounded, compatibility-skill reloads debounced | #55597, #56260 | none |

## 5. Not verified

- That a `deny` effect or a thrown shell hook actually stops an action: needs a provider key.
- User-skill discovery (section 2).
- Whether the guard double-runs under the duplicate plugin listing (section 1).

## 6. Consequences for the objective

- task-002/005: install/verify docs must use the warm, service-mode recipe, not `--standalone`.
- task-004: raise the OpenTUI peer to `>=0.8.0`; check the duplicate-load behaviour.
- task-003/006: the permission pin and generator need no 2.2.5 change.
