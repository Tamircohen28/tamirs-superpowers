---
alwaysApply: false
globs: ["skills/**/SKILL.md"]
---

# Skill Quality Standards — tamirs-superpowers

Rules for creating and maintaining skills in `skills/<domain>/<skill-name>/`.

Based on [Claude Code Skills](https://code.claude.com/docs/en/skills) and [Plugins reference](https://code.claude.com/docs/en/plugins-reference).

## Directory layout

```
skills/<domain>/<skill-name>/
├── SKILL.md              # Required — frontmatter + instructions (<500 lines)
├── references/           # Deep docs loaded on demand
├── scripts/                # Deterministic bash/node helpers
├── templates/            # Reply bodies, issue templates, etc.
└── evals/evals.json        # Optional golden cases
```

**Invocation name** comes from the **directory name** (`<skill-name>`), not frontmatter `name` — keep them identical.

## Frontmatter (required)

```yaml
---
name: <skill-name>                    # MUST match directory name
description: "Use when ..."           # ≤1,536 chars; key trigger first
when_to_use: "Concrete trigger phrases"
argument-hint: "[what the user passes]"
model: claude-sonnet-4-6
allowed-tools:                        # Every tool the body uses
  - Bash
  - Skill                            # Required if invoking internal skills
disable-model-invocation: true        # Slash-command-only workflow skills
user-invocable: false                 # Internal skills (invoked via Skill tool)
effort: high                          # Optional — complex workflow skills
metadata:
  capability: <domain-capability>
  tags: [<tag>, ...]
  updated-date: "YYYY-MM-DD"
---
```

### Internal vs user-facing

| Type | `user-invocable` | `disable-model-invocation` | Examples |
|------|------------------|----------------------------|----------|
| User slash command | `true` (default) | `true` | plan-dev, start-dev, pr-dev |
| Auto-trigger discovery | `true` (default) | `false` (default) | find-skill, mcp-builder |
| Internal companion | `false` | `true` | docs-review, repo-review, mcp-pagination |

Parent skills invoke internal companions with `Skill("skill-name")` — never duplicate their checklists inline.

## Body structure

1. **Why this skill exists** — 2–3 sentences (WHY-first)
2. **Internal skills** (if any) — when to invoke companions
3. **Core workflow** — numbered steps
4. **Hard rules** — non-negotiable constraints
5. **Error handling** — table with 3+ common failures (workflow skills)
6. **References** — pointers to `references/`, `scripts/`, `templates/`

## Quality checklist

- [ ] `name` matches directory name
- [ ] `description` + `when_to_use` combined ≤1,536 characters
- [ ] SKILL.md under 500 lines (`wc -l`)
- [ ] `allowed-tools` lists every tool used in the body
- [ ] Script paths use `$CLAUDE_SKILL_DIR`, never hardcoded absolute paths
- [ ] Internal skills marked `user-invocable: false`
- [ ] Workflow slash commands have `disable-model-invocation: true`
- [ ] `metadata.updated-date` reflects last edit
- [ ] No employer IP, internal domains, or private org references

## Plugin enhancements (from plugins-reference)

- **`effort: high`** on plan-dev, start-dev, babysit-pr — full model capability for multi-step workflows
- **`!`cmd`` live context blocks** — inject git/gh state at skill load (start-dev, plan-dev pattern)
- **`Skill` tool** — parent skills delegate to internal companions (repo-polish, mcp-builder)
- **`Monitor` tool** — long-running CI watch loops (babysit-pr)
- **Reload after non-SKILL changes** — hooks, `.mcp.json`, `plugin.json` need `/reload-plugins`

## Validation

```bash
make validate          # frontmatter name + description
make plugin-validate   # full Claude Code plugin schema (requires claude CLI)
```
