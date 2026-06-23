---
alwaysApply: false
globs: ["skills/**/SKILL.md", ".claude/skills/**/SKILL.md"]
---

# Skill Quality Standards — tamirs-superpowers

Rules for creating and maintaining skills in `skills/<domain>/<skill-name>/`.

Based on [Claude Code Skills](https://code.claude.com/docs/en/skills) and
`skills/meta/skill-creator/references/frontmatter-template.md`.

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
- [ ] Script paths use `$CLAUDE_SKILL_DIR`, never hardcoded absolute paths
- [ ] Internal skills: `user-invocable: false` + `disable-model-invocation: true`
- [ ] No employer IP, internal domains, or private org references

## Validation

```bash
python3 scripts/validate-skill-frontmatter.py path/to/SKILL.md
make validate          # shellcheck + JSON + all skills
make plugin-validate   # full Claude Code plugin schema (requires claude CLI)
```
