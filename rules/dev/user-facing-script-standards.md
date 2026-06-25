---
alwaysApply: false
---

# User-Facing Script Standards

User-facing scripts must expose a consistent CLI interface and self-documentation.

Applies when authoring scripts for this repo regardless of agent (Claude Code, Cursor, Codex).

## Scope

This rule applies to scripts intended for direct human invocation, including:
- Repository-root scripts (for example install/build helper scripts)
- Skill helper scripts under `skills/**/scripts/` invoked by users or agents

This rule does not require internal-only helper scripts to expose the same UX surface.

## Required CLI contract

Every new user-facing script must:

1. Support `--help` and `-h`
   - Must print usage with script name, arguments, and flags.
   - Must exit successfully after printing help.
2. Support `--verbose` and `-v`
   - Must enable more detailed execution logging.
3. Document primary behavior
   - Must include a top-of-file usage/help section explaining:
     - purpose
     - accepted arguments
     - supported flags
     - at least one concrete example command

## Behavior expectations

- Scripts that mutate state should support explicit preview/safety behavior when relevant (for example `--dry-run`).
- Unknown flags must fail fast with a clear error message and usage hint.
- Help text must stay updated when flags or positional arguments change.

## Hook Script Standards

Hook scripts (`hooks/*.sh`, wired via `hooks/hooks.json`) must never use `echo` to produce output. This rule applies to platforms that load plugin hooks:

| Platform | Loads `hooks/hooks.json` |
|----------|--------------------------|
| Claude Code | Yes (`.claude-plugin/plugin.json`) |
| Codex | Yes (`.codex-plugin/plugin.json`) |
| Cursor | No — `.cursor-plugin/plugin.json` does not wire hooks |

Unexpected stdout from hook subprocesses can interfere with hook response parsing on Claude Code and Codex.

**Required alternatives:**

| Instead of | Use |
|------------|-----|
| `echo "message" >> "$TIMELINE"` | `pm_timeline_append "$TIMELINE" "$TS" "$tool_name" "$agent"` |
| `echo "event" \| pm_trace_append` | `pm_emit_event ...` |
| `\|\| echo "fallback"` in `$()` | `\|\| printf '%s\n' "fallback"` |
| `echo "value" > "$FILE"` | `printf '%s\n' "$value" > "$FILE"` |

Do not add new `echo` calls to hook scripts.

This rule applies to any hook scripts added in the future.

## Documentation synchronization

When adding or changing a user-facing script interface:

- Update command examples in user-facing docs (`README.md` and relevant docs under `docs/user/`).
- Update internal docs when script location or purpose changes (`docs/engineering/`).
