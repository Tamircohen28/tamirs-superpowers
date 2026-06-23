---
name: plugin-compat
description: 'Use when the user wants to make a plugin, extension, or tool repo compatible with one or more AI coding assistants — Claude Code, Cursor, or OpenAI Codex. Triggers: ''make this compatible with Claude and Cursor'', ''add Codex support'', ''port this plugin to Cursor'', ''make this work with all AI assistants'', ''add AGENTS.md'', ''add cursor rules'', ''generate .cursor/rules'', ''add claude code plugin files'', ''plugin compatibility'', ''multi-platform AI support'', ''set up for Claude Cursor and Codex''.'
when_to_use: 'User wants to generate or update platform-specific config files so their repo works as a plugin/extension for Claude Code, Cursor, and/or OpenAI Codex. Example phrases: ''make this compatible with Claude and Cursor'', ''add Codex AGENTS.md'', ''generate cursor rules for this repo'', ''set up plugin files for all three AI assistants'', ''add multi-platform AI support''.'
argument-hint: '[platform(s) to target — e.g. ''all'', ''cursor'', ''codex'', ''claude'' — defaults to all three]'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- Bash
- Read
- Write
- Edit
- Glob
- Grep
- WebFetch
disallowed-tools: []
model: claude-sonnet-4-6
effort: medium
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  capability: developer-workflow
  tags:
  - plugin
  - compatibility
  - claude-code
  - cursor
  - codex
  - multi-platform
  updated-date: '2026-06-17'
---

# plugin-compat

Make any repo compatible with Claude Code, Cursor, and OpenAI Codex by fetching each platform's current documentation at runtime and generating or repairing the required config files.

## Supporting files

| File | When to use |
|---|---|
| `references/platform-specs.md` | Load for schema details and canonical field lists during Phase 3 |

---

## Why this skill exists

Each AI coding assistant has its own plugin/extension format that evolves quickly. Keeping a repo compatible with all three manually means tracking three separate doc sites and hand-writing boilerplate that drifts out of date. This skill fetches authoritative docs fresh each run, inventories what's missing, and generates or repairs the platform-specific files — so the repo stays compatible without manual doc-chasing.

**Key cross-platform insight:** `AGENTS.md` is shared — both Cursor and Codex read it. Write it once and both platforms benefit. Only Claude Code needs its own separate manifest and skill format.

---

## Phase 1 — Fetch Latest Docs

**Always fetch first.** Never rely on cached knowledge of platform formats — these specs change.

Run all fetches in parallel:

### Claude Code
- `https://code.claude.com/docs/en/plugins` — plugin layout and plugin.json schema
- `https://code.claude.com/docs/en/skills` — full SKILL.md frontmatter field list
- `https://code.claude.com/docs/en/plugin-marketplaces` — marketplace.json schema (only if repo is a marketplace)

### Cursor
- `https://cursor.com/docs/rules` — .mdc frontmatter schema, rule types, file layout

### OpenAI Codex
- `https://developers.openai.com/codex/guides/agents-md` — AGENTS.md structure and discovery
- `https://developers.openai.com/codex/config-basic` — .codex/config.toml fields

**If a fetch fails:** log it and proceed with `references/platform-specs.md` as fallback for that platform. Note which platforms could not be verified in the final report.

Read `$CLAUDE_SKILL_DIR/references/platform-specs.md` as a structural guide. Cross-check its schemas against what the live fetches return — if they conflict, prefer the live fetch.

---

## Phase 2 — Inventory the Repo

Understand what the repo does and what already exists, so generated files are accurate and not generic.

```bash
# Identity
ls -la
cat README.md 2>/dev/null | head -80
cat CLAUDE.md 2>/dev/null

# Claude Code
cat .claude-plugin/plugin.json 2>/dev/null
cat marketplace.json 2>/dev/null
find skills/ -name "SKILL.md" 2>/dev/null | head -30
cat hooks/hooks.json 2>/dev/null
cat statusline.sh 2>/dev/null

# Cursor
ls .cursor/rules/ 2>/dev/null
cat .cursorrules 2>/dev/null

# Codex / shared
cat AGENTS.md 2>/dev/null
cat .codex/config.toml 2>/dev/null

# Tech stack fingerprint
ls package.json pyproject.toml Cargo.toml go.mod Makefile 2>/dev/null
```

**Synthesize from the inventory:**
- One-sentence description of what this repo does (for use in generated descriptions)
- Which platform configs are present and complete per the fetched specs
- Which are absent or have gaps

Only generate files for platforms that have gaps. **Do not overwrite files that are already correct** per the freshly-fetched spec.

---

## Phase 3 — Generate / Update

Work through each platform. Apply schemas from the live fetch; use `references/platform-specs.md` if the fetch failed.

### Claude Code

**`.claude-plugin/plugin.json`** — only `name` is truly required. Generate with common fields:

```json
{
  "name": "<repo-name-kebab>",
  "description": "<one-line from README>",
  "version": "<from existing version or 1.0.0>",
  "author": { "name": "<from git config or README>" },
  "repository": "<git remote url>",
  "license": "<from repo or MIT>",
  "skills": "skills/",
  "hooks": "hooks/hooks.json"
}
```

**`marketplace.json`** — only generate if this repo declares itself a plugin marketplace (check README or existing file). Schema requires `name`, `owner.name`, and `plugins` array with at minimum `name` and `source` per entry.

**`hooks/hooks.json`** — if `hooks/*.sh` files exist but `hooks.json` is absent, wire them. Use only events supported per the fetched docs. Each entry needs `matcher` and `hooks` array with `type` + `command`.

**`SKILL.md` frontmatter audit** — for each existing `SKILL.md`, run `python3 scripts/validate-skill-frontmatter.py` and report failures. All 16 official Claude Code fields plus `metadata.updated-date` are required in this repo.

### Cursor

**`.cursor/rules/*.mdc`** — file extension MUST be `.mdc`. Files named `.md` inside `.cursor/rules/` are silently ignored by Cursor.

Derive rule files from the repo's existing content:

1. Read `CLAUDE.md` → extract each distinct topic (commit conventions, tooling constraints, testing rules, etc.) → one `.mdc` file per topic
2. Read `README.md` → extract setup/contribution guidance → `setup.mdc` (alwaysApply: false, description-only)
3. If the repo has skills → `skills-guide.mdc` explaining how to invoke and extend them

MDC format:
```markdown
---
description: "When this rule is relevant — used by Agent to decide whether to include it"
alwaysApply: false
globs: "src/**/*.ts"
---

Rule content here.
```

Rule mode selection:
- `alwaysApply: true` → used sparingly, only for universal non-negotiable conventions
- `globs` set → auto-attach when those files are open
- `description` only → Agent evaluates relevance per request
- Neither description nor globs → manual `@rule-name` invocation only

Keep each `.mdc` file under 500 lines. Split large content across multiple focused files.

**Note:** Skip `.cursorrules` (root-level legacy file) — generate `.cursor/rules/*.mdc` instead, which is the current format.

### OpenAI Codex + Cursor shared

**`AGENTS.md`** (repo root) — plain Markdown, no YAML frontmatter. Both Cursor and Codex read this file. Write it once for both.

Derive content from `CLAUDE.md`, `README.md`, and `Makefile`/scripts. Use conventional sections:

```markdown
# <Repo Name>

<One-paragraph description of what this repo is and what an AI agent should know upfront>

## Working agreements

<Coding standards, dependency preferences, commit format, branch naming>

## Repository expectations

<Testing requirements, linting, documentation standards — include the actual commands>

## Key files

| Path | Purpose |
|---|---|
| ... | ... |

## Off-limits

<What must never be modified, deleted, or committed>
```

Keep `AGENTS.md` under 32 KiB (Codex truncates at that limit by default).

**Portability rule:** `AGENTS.md` must contain no Claude-Code-specific syntax (no `!` live commands, no `$CLAUDE_SKILL_DIR`, no `#` directives). It is plain prose Markdown consumed by multiple agents.

**`.codex/config.toml`** — generate only if the fetched docs show fields that meaningfully apply to this repo (e.g., `approval_policy`, `sandbox_mode`). Skip if default values are fine.

---

## Phase 4 — Validate

```bash
# Claude Code — run repo validator if available
make validate 2>/dev/null || make test 2>/dev/null || echo "no validator found"

# JSON sanity
for f in marketplace.json .claude-plugin/plugin.json hooks/hooks.json; do
  [ -f "$f" ] && python3 -m json.tool "$f" > /dev/null 2>&1 && echo "$f OK" || echo "$f INVALID or missing"
done

# Cursor rules
ls .cursor/rules/*.mdc 2>/dev/null && echo ".cursor/rules: OK" || echo ".cursor/rules: none"

# Shared instructions
ls AGENTS.md 2>/dev/null && wc -c AGENTS.md || echo "AGENTS.md: missing"
```

---

## Output Report

After all phases, present:

```
## plugin-compat results

### Docs fetched
- Claude Code: ✓ / ✗ <note if failed, fell back to references/>
- Cursor: ✓ / ✗ <note>
- Codex: ✓ / ✗ <note>

### Claude Code
- .claude-plugin/plugin.json: created / already correct / updated (<fields changed>)
- marketplace.json: created / skipped (not a marketplace) / already correct
- hooks/hooks.json: created / already correct / not applicable
- SKILL.md audit: N skills checked, M updated (list which fields were added)

### Cursor
- .cursor/rules/<name>.mdc: created (<rule type>) — list each file
- .cursor/rules/: already complete / nothing to do

### Codex + Cursor shared
- AGENTS.md: created / already correct / updated (<sections changed>)
- .codex/config.toml: created / skipped (defaults are fine)

### Notes
<Warnings about failed fetches, fields that couldn't be verified,
 files skipped because already correct, anything the user should review>
```

---

## Hard Rules

- **Always fetch docs first** — do not generate from memory. Platform formats change; stale generation defeats the point.
- **Never overwrite a correct file** — compare against the freshly-fetched spec; skip if it matches.
- **Derive all descriptions from the actual repo** — no placeholder text like "My Plugin" or "TODO: add description". Read `README.md` first.
- **`.cursor/rules/` files must use `.mdc` extension** — `.md` files there are silently ignored.
- **`AGENTS.md` must be portable plain Markdown** — no Claude-Code-specific syntax; it is consumed by Cursor and Codex as well.
- **`AGENTS.md` must stay under 32 KiB** — Codex truncates at that limit.
- **`statusLine` in `plugin.json` must be an object** — `{"type": "command", "command": "..."}` not a string.
- **Do not commit** — report what was created and let the user review first.
