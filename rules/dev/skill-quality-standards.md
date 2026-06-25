---
alwaysApply: false
globs: ["skills/**/SKILL.md"]
---

# Skill Quality Standards — tamirs-superpowers

Rules for creating and maintaining skills in `skills/<domain>/<skill-name>/`.

Applies when authoring plugin skills consumed by **Claude Code**, **Cursor**, and **Codex** (see multi-platform distribution below).

Based on [Claude Code Skills](https://code.claude.com/docs/en/skills) and
`skills/toolkit/skill-creator/references/frontmatter-template.md`.

## Multi-platform distribution

This repo ships the same `skills/` tree through three plugin manifests:

| Platform | Manifest | Skills path |
|----------|----------|-------------|
| Claude Code | `.claude-plugin/plugin.json` | `./skills/<domain>` |
| Cursor | `.cursor-plugin/plugin.json` | `./skills/<domain>` |
| Codex | `.codex-plugin/plugin.json` | `./skills/<domain>` |

Keep skill bodies **portable** — policy and workflows must not assume only Claude Code is available. Platform-specific mechanics belong in short callouts (e.g. `$CLAUDE_SKILL_DIR`, `EnterWorktree`, Cursor subagents).

| Concern | Claude Code | Cursor | Codex |
|---------|-------------|--------|-------|
| Skill discovery | Plugin `skills/` + `/skill-name` | Plugin `skills/` + agent skills | Plugin `skills/` + `AGENTS.md` pointers |
| Script dir variable | `$CLAUDE_SKILL_DIR` | Resolve as directory containing the active `SKILL.md` | Same as Cursor |
| Hooks | `hooks/hooks.json` (Claude + Codex plugins) | Not loaded from `.cursor-plugin` | `hooks/hooks.json` |
| Contributor rules | `rules/dev/*.md` | `.cursor/rules/*.mdc` adapters | `AGENTS.md` + `rules/dev/` |

## Directory layout

```
skills/<domain>/<skill-name>/
├── SKILL.md              # Required — full frontmatter + instructions (<500 lines)
├── references/           # Deep docs loaded on demand
├── scripts/              # Deterministic bash/node helpers
├── templates/            # Reply bodies, issue templates, etc.
└── evals/evals.json      # Optional golden cases
```

**Invocation name** comes from the **directory name** (`<skill-name>`), not frontmatter `name` — keep them identical.

## Frontmatter (all fields required)

CI validates every skill via `scripts/validate-skill-frontmatter.py`.

```yaml
---
name: <skill-name>                    # MUST match directory name
description: "Use when ..."           # ≤1,536 chars combined with when_to_use
when_to_use: "Concrete trigger phrases"
argument-hint: "[what the user passes]"
arguments: []
disable-model-invocation: false       # true for slash-only workflows
user-invocable: true                  # false for internal companions
allowed-tools:                        # Every tool the body uses
  - Bash
  - Skill
disallowed-tools: []
model: claude-sonnet-4-6
effort: medium                        # low | medium | high | xhigh | max
context: ''                           # fork + agent for subagent skills
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  capability: <domain-capability>
  tags: [<tag>, ...]
  updated-date: "YYYY-MM-DD"
---
```

### Internal vs user-facing

| Type | `user-invocable` | `disable-model-invocation` | `effort` | Examples |
|------|------------------|----------------------------|----------|----------|
| User slash command | `true` | `true` | `high` | plan-dev, start-dev, pr-dev |
| Auto-trigger discovery | `true` | `false` | `medium` | find-skill, mcp-builder |
| Internal companion | `false` | `true` | `low` | docs-review, mcp-pagination, changelog-review |
| Forked subagent | `true` | `true` | `medium` | targeted-debug (`context: fork`, `agent: Explore`) |

Parent skills invoke internal companions with `Skill("skill-name")` — never duplicate their checklists inline.

## Body structure

1. **Why this skill exists** — 2–3 sentences (WHY-first)
2. **Internal skills** (if any) — when to invoke companions
3. **Core workflow** — numbered steps
4. **Hard rules** — non-negotiable constraints
5. **Error handling** — table with 3+ common failures (workflow skills)
6. **References** — pointers to `references/`, `scripts/`, `templates/`

## Quality checklist

- [ ] All 16 official frontmatter fields + `metadata.updated-date` present
- [ ] `python3 scripts/validate-skill-frontmatter.py` passes
- [ ] `name` matches directory name
- [ ] `description` + `when_to_use` combined ≤1,536 characters
- [ ] SKILL.md under 500 lines (`wc -l`)
- [ ] `allowed-tools` lists every tool used in the body
- [ ] Script paths use `$CLAUDE_SKILL_DIR` in Claude-oriented skills; document equivalent resolution for Cursor/Codex when scripts are required
- [ ] Internal skills: `user-invocable: false` + `disable-model-invocation: true`
- [ ] No employer IP, internal domains, or private org references
- [ ] No Claude-only assumptions without a Cursor/Codex fallback note where behavior differs

## Validation

```bash
python3 scripts/validate-skill-frontmatter.py path/to/SKILL.md
make validate          # shellcheck + JSON + all skills + plugin manifests
make plugin-validate   # full Claude Code plugin schema (requires claude CLI)
```

After changing skills, confirm all three manifests still list the same `skills/` roots:

```bash
jq -r '.skills[]' .claude-plugin/plugin.json .cursor-plugin/plugin.json .codex-plugin/plugin.json
```
