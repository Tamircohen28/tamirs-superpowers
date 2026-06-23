# SKILL.md frontmatter template

Canonical reference for tamirs-superpowers skills. Every field below is **required**
in this repo (CI enforces via `scripts/validate-skill-frontmatter.py`).

Official docs: https://code.claude.com/docs/en/skills

## Field list (16 official + metadata)

| Field | Type | Default when unused |
|-------|------|---------------------|
| `name` | string | Must match directory name (kebab-case) |
| `description` | string | "Use when …" trigger text; ≤1,536 chars combined with `when_to_use` |
| `when_to_use` | string | Concrete user phrases |
| `argument-hint` | string | Shown in `/` autocomplete |
| `arguments` | list | `[]` |
| `disable-model-invocation` | bool | `false` (auto-trigger); `true` for slash-only workflows |
| `user-invocable` | bool | `true`; `false` for internal companion skills |
| `allowed-tools` | list | Every tool the body uses |
| `disallowed-tools` | list | `[]` |
| `model` | string | `claude-sonnet-4-6` unless specific reason |
| `effort` | string | `low` / `medium` / `high` / `xhigh` / `max` |
| `context` | string | `""` (main session) or `fork` |
| `agent` | string | `""` or subagent type when `context: fork` (e.g. `Explore`) |
| `hooks` | mapping | `{}` |
| `paths` | list | `[]` (no path-scoped auto-load) |
| `shell` | string | `bash` |
| `metadata` | mapping | `updated-date: "YYYY-MM-DD"` required |

Optional repo extension: `license` (only when a LICENSE file is bundled).

## Skill-type presets

### User-facing auto-trigger (discovery)

```yaml
disable-model-invocation: false
user-invocable: true
effort: medium
context: ''
agent: ''
```

Examples: `find-skill`, `mcp-builder`, `multi-agent-repo`.

### Slash-command workflow (manual invoke)

```yaml
disable-model-invocation: true
user-invocable: true
effort: high
context: ''
agent: ''
```

Examples: `plan-dev`, `start-dev`, `repo-standards`.

### Internal companion (Skill tool only)

```yaml
disable-model-invocation: true
user-invocable: false
effort: low
context: ''
agent: ''
```

Examples: `docs-review`, `mcp-pagination`, `changelog-review`.

### Forked subagent

```yaml
context: fork
agent: Explore   # or Plan, etc. — see Claude Code sub-agents docs
disable-model-invocation: true
```

Example: `targeted-debug`.

## Full skeleton

```yaml
---
name: my-skill
description: "Use when …"
when_to_use: "User says …"
argument-hint: "[what the user passes]"
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
  - Read
  - Bash
disallowed-tools: []
model: claude-sonnet-4-6
effort: medium
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  capability: domain-name
  tags:
    - tag-one
  updated-date: "2026-06-23"
---
```

## Validation

```bash
make validate                              # includes frontmatter gate
python3 scripts/validate-skill-frontmatter.py path/to/SKILL.md
python3 scripts/normalize-skill-frontmatter.py   # batch-fill defaults (rare)
```
