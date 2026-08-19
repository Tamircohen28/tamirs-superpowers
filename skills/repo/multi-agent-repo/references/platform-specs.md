# Platform Specification Quick Reference

This file is loaded when the skill needs schema details. Always fetch fresh docs first — use these as a structural guide, not as a substitute for live docs.

## Doc URLs (fetch these fresh each run)

| Platform | URL |
|---|---|
| Claude Code — plugins overview | https://code.claude.com/docs/en/plugins |
| Claude Code — plugins reference | https://code.claude.com/docs/en/plugins-reference |
| Claude Code — marketplace | https://code.claude.com/docs/en/plugin-marketplaces |
| Claude Code — skills | https://code.claude.com/docs/en/skills |
| Cursor — rules | https://cursor.com/docs/rules |
| Codex — AGENTS.md | https://developers.openai.com/codex/guides/agents-md |
| Codex — config basics | https://developers.openai.com/codex/config-basic |
| Codex — advanced config | https://developers.openai.com/codex/config-advanced |
| Gemini CLI — extensions | https://google-gemini.github.io/gemini-cli/docs/extensions/ |
| OpenCode — skills | https://opencode.ai/docs/skills/ |
| OpenCode — agents | https://opencode.ai/docs/agents/ |
| OpenCode — config schema | https://opencode.ai/config.json |

## Targets and where support is stated

Six targets, one source of truth. `core/capabilities/platforms.json` — validated against
`core/capabilities/schema.json` — records an explicit status for all 19 capability keys on
every target. Read it before recommending anything; never restate a status in prose.

| Registry id | Display | Distribution artifact |
|---|---|---|
| `claude_code` | Claude Code | `.claude-plugin/plugin.json` + marketplace |
| `claude_desktop` | Claude Desktop | **runtime surface of `claude_code`** — consumes the same plugin. Do not create a Desktop manifest. |
| `codex` | Codex CLI | `.codex-plugin/plugin.json` + `AGENTS.md` |
| `cursor` | Cursor | `.cursor-plugin/plugin.json` + `.cursor/rules/*.mdc` |
| `gemini_cli` | Gemini CLI | `gemini-extension.json`, installed from a git URL |
| `opencode` | OpenCode | `opencode.json` (`skills.paths`) + generated `.opencode/agent/` |

Statuses are `native`, `native-experimental`, `partial`, `emulated`, `adapter`,
`unsupported`, `unknown`. Anything short of `native` must carry a `fallback` or a note;
`unknown` means unverified and must be treated as unavailable at runtime, never advertised.

---

## Gemini CLI Extension Layout

Gemini installs an extension straight from a git repository. An extension can package
Agent Skills, MCP servers, hooks, sub-agents, custom commands, and context — so the
canonical `skills/` tree is reused directly rather than translated.

```
<repo-root>/
  gemini-extension.json    # manifest: name, version, contextFileName, skills, mcpServers, hooks
  GEMINI.md                # context file named by contextFileName
  skills/
    <skill-name>/SKILL.md  # canonical tree, reused as-is
```

```jsonc
{
  "name": "<extension-name>",
  "version": "0.1.0",
  "description": "…",
  "contextFileName": "GEMINI.md",
  "skills": ["./skills"],
  "mcpServers": "./.mcp.json",
  "hooks": "./hooks/hooks.json"
}
```

Install: `gemini extensions install <repo-url>`. Local development: `gemini extensions link .`.
Validate: `gemini extensions validate .`. Keep it dependency-free — declarative extension
content needs no Node toolchain, so do not add one just because a template offers it.

## OpenCode Layout

OpenCode discovers Agent Skills natively (recursively, including domain-nested
directories) and reads a smaller frontmatter set, ignoring unknown fields. It has no
plugin manifest, no marketplace, and no `hooks.json` — lifecycle automation is a JS/TS
plugin module only.

```
<repo-root>/
  opencode.json            # { "skills": { "paths": ["./skills"] }, "mcp": { … } }
  .opencode/agent/*.md     # GENERATED from canonical agents/ — frontmatter genuinely differs
```

Install is by path (`skills.paths` or a symlink), never by marketplace. Agent adapters are
generated and drift-checked; never hand-copy an agent definition into `.opencode/agent/`.

---

## Claude Code Plugin Layout

```
<plugin-root>/
  .claude-plugin/
    plugin.json          # manifest (only "name" is required)
  skills/
    <skill-name>/
      SKILL.md           # required; supporting files alongside
  hooks/
    hooks.json           # hook event wiring
  .mcp.json              # MCP server definitions
  agents/                # subagent .md files
  marketplace.json       # only if this repo IS a marketplace
```

`plugin.json` must live at `.claude-plugin/plugin.json`. `skills/`, `hooks/`, `agents/` live at the plugin root — NOT inside `.claude-plugin/`.

### `plugin.json` fields

Only `name` is required. Commonly used:

```json
{
  "name": "plugin-name",
  "description": "...",
  "version": "1.0.0",
  "author": { "name": "..." },
  "homepage": "https://...",
  "repository": "https://github.com/...",
  "license": "MIT",
  "keywords": [],
  "dependencies": [],
  "skills": "skills/",
  "hooks": "hooks/hooks.json"
}
```

Optional component-path overrides: `commands`, `agents`, `mcpServers`, `lspServers`, `outputStyles`, `experimental.monitors`, `experimental.themes`, `userConfig`, `channels`, `defaultEnabled`.

### `SKILL.md` frontmatter — all fields

| Field | Type | Notes |
|---|---|---|
| `name` | string | Display label; sets command name for plugin-root SKILL.md |
| `description` | string | How Claude decides when to auto-invoke. Strongly recommended. |
| `when_to_use` | string | Appended to description in listing |
| `argument-hint` | string | Shown in autocomplete, e.g. `[issue-number]` |
| `arguments` | list | Named positional arg names |
| `disable-model-invocation` | bool | `true` = user-only, no auto-trigger |
| `user-invocable` | bool | `false` = hidden from `/` menu, internal only |
| `allowed-tools` | list | Tools available without prompts while skill is active |
| `disallowed-tools` | list | Tools removed from pool while skill is active |
| `model` | string | Override model for this skill's turn |
| `effort` | string | `low`/`medium`/`high`/`xhigh`/`max` |
| `context` | string | `fork` to run in a forked subagent |
| `agent` | string | Subagent type to use with `context: fork` |
| `hooks` | object | Inline hooks scoped to this skill's lifecycle |
| `paths` | list | Glob patterns limiting when skill auto-activates |
| `shell` | string | `bash` (default) or `powershell` |

### `hooks/hooks.json` format

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "..." }
        ]
      }
    ]
  }
}
```

**All hook events:** `SessionStart`, `Setup`, `UserPromptSubmit`, `UserPromptExpansion`, `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `Notification`, `MessageDisplay`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `Stop`, `StopFailure`, `TeammateIdle`, `InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact`, `Elicitation`, `ElicitationResult`, `SessionEnd`.

**Hook types:** `command`, `http`, `mcp_tool`, `prompt`, `agent`.

### `marketplace.json` schema

```json
{
  "name": "marketplace-name",
  "owner": { "name": "...", "email": "..." },
  "description": "...",
  "plugins": [
    {
      "name": "plugin-name",
      "source": "./relative/path",
      "description": "...",
      "version": "1.0.0"
    }
  ]
}
```

Required at marketplace level: `name`, `owner.name`, `plugins`. Required per plugin entry: `name`, `source`.

Plugin source types: relative path string, `{ "source": "github", "repo": "owner/repo" }`, `{ "source": "url", "url": "..." }`, `{ "source": "git-subdir", ... }`, `{ "source": "npm", "package": "..." }`.

`strict: false` in a plugin entry skips requiring `plugin.json` in the plugin dir.

---

## Cursor Rules

### File layout

```
<project-root>/
  .cursor/
    rules/
      my-rule.mdc       # MUST use .mdc extension — .md is silently ignored
  AGENTS.md             # Cursor also reads this (plain markdown, shared with Codex)
```

### MDC frontmatter

```yaml
---
description: "What this rule does — used by Agent to decide relevance"
globs: "**/*.ts,**/*.tsx"
alwaysApply: false
---
```

| Field | Type | Notes |
|---|---|---|
| `description` | string | Agent uses this to decide relevance. Required when `alwaysApply: false` and no globs. |
| `globs` | string | Comma-separated patterns; rule auto-attaches when matching file is open |
| `alwaysApply` | boolean | `true` = included in every session |

### Rule application modes

| `alwaysApply` | `globs` | `description` | Behavior |
|---|---|---|---|
| `true` | — | — | Every session |
| `false` | set | — | Auto-attach when files match |
| `false` | — | set | Agent evaluates relevance |
| `false` | — | — | Manual `@rule-name` only |

Keep each `.mdc` file under 500 lines. `.md` files in `.cursor/rules/` are silently ignored.

**Key insight:** Cursor also reads `AGENTS.md` at the project root. A well-written `AGENTS.md` satisfies both Cursor and Codex — write it once, reference it from `.mdc` rules when needed.

---

## OpenAI Codex CLI

### File layout

```
<project-root>/
  AGENTS.md                    # project instructions (plain markdown, no frontmatter)
  .codex/
    config.toml                # project-level config overrides

~/.codex/
  config.toml                  # user-level config
  AGENTS.md                    # global instructions
  AGENTS.override.md           # temporary override without deleting base
```

**There is no `codex.md` file.** Only `AGENTS.md` (and its `.override.md` variant) is recognized.

### `AGENTS.md` format

Plain markdown, no YAML frontmatter. Free-form with conventional sections:

```markdown
# <Repo Name>

<One-paragraph description of what this repo is>

## Working agreements
Always run `npm test` after modifying JavaScript files.
Prefer `pnpm` when installing dependencies.

## Repository expectations
<Standards for linting, testing, documentation>

## Key files
<Table or list of important paths and their purpose>

## Off-limits
<What must never be modified, deleted, or committed>
```

Discovery: git root → subdirectories down to cwd, all concatenated. Closest files override earlier ones.
Truncation: capped at `project_doc_max_bytes` (default 32 KiB).

### `.codex/config.toml` — common fields

```toml
model = "gpt-5.5"
approval_policy = "on-request"    # "untrusted" | "on-request" | "never"
sandbox_mode = "workspace-write"  # "workspace-write" | "danger-full-access"
web_search = "cached"             # "cached" | "live" | "disabled"
model_reasoning_effort = "high"
project_doc_max_bytes = 32768
project_doc_fallback_filenames = ["TEAM_GUIDE.md"]

[features]
memories = true
web_search = true

[analytics]
enabled = false
```
