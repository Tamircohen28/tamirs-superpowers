# Platform setup — dev mode phases 0–1

Use this reference when implementing phases 0–1 in **dev** mode (or quick file generation via `multi-agent-repo dev` without a prior plan). Replaces the former standalone `plugin-compat` skill.

## Step 1 — Fetch latest docs

**Always fetch first.** Run in parallel; on failure use `references/platform-specs.md` as fallback and note which platform could not be verified.

| Platform | URLs |
|----------|------|
| Claude Code | `https://code.claude.com/docs/en/plugins`, `https://code.claude.com/docs/en/skills` |
| Cursor | `https://cursor.com/docs/rules` |
| Codex | `https://developers.openai.com/codex/guides/agents-md`, `https://developers.openai.com/codex/config-basic` |

Cross-check live fetches against `references/platform-specs.md`; prefer live docs on conflict.

## Step 2 — Inventory gaps

Use `$INVENTORY` from `inventory-agent-setup.sh`. **Do not overwrite files already correct** per fetched specs.

## Step 3 — Phase 0: canonical AGENTS.md

Create or repair `AGENTS.md` at repo root:

- Plain Markdown — **no** YAML frontmatter, no `!` blocks, no `$CLAUDE_SKILL_DIR`
- Under **32 KiB** (Codex truncates at default limit)
- Derive commands from `Makefile`, `package.json`, or `README.md` — real commands, not placeholders
- Sections: repo description, working agreements, repository expectations, key files, off-limits

## Step 4 — Phase 1: thin adapters

**CLAUDE.md**

- Line 1: `@AGENTS.md` (preferred over symlinks on Windows)
- Claude-only addenda under ~30 lines — no duplicated policy from AGENTS.md

**`.cursor/rules/000-project.mdc`**

```yaml
---
description: "Project-wide conventions — AGENTS.md is canonical"
alwaysApply: true
---
```

Body: one paragraph pointing to `AGENTS.md` as source of truth; no full policy copy.

**Claude plugin repos only** — if gaps exist, also repair `.claude-plugin/plugin.json`, `hooks/hooks.json` per `platform-specs.md`. Skip marketplace.json unless repo is a marketplace.

## Hard rules

- Never duplicate full AGENTS.md policy into CLAUDE.md or `.mdc` files
- `.cursor/rules/` files **must** use `.mdc` — `.md` is silently ignored
- Derive descriptions from actual README — no placeholder text
- Do not commit from review/plan modes; dev mode commits per SKILL.md

After phases 0–1, continue multi-agent-repo dev mode at Phase 2 locally.
