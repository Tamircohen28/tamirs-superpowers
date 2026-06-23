---
paths:
  - "skills/**/SKILL.md"
  - ".claude/skills/**/SKILL.md"
---

# SKILL.md frontmatter — required fields

Every `SKILL.md` in this repo must include **all 16 official Claude Code frontmatter
fields** plus `metadata.updated-date`. CI enforces this via
`scripts/validate-skill-frontmatter.py`.

Reference: `skills/meta/skill-creator/references/frontmatter-template.md`
Official docs: https://code.claude.com/docs/en/skills

## Required fields

`name`, `description`, `when_to_use`, `argument-hint`, `arguments`,
`disable-model-invocation`, `user-invocable`, `allowed-tools`, `disallowed-tools`,
`model`, `effort`, `context`, `agent`, `hooks`, `paths`, `shell`, `metadata`

## Defaults for unused behavior

| Field | When not applicable |
|-------|---------------------|
| `arguments` | `[]` |
| `disallowed-tools` | `[]` |
| `hooks` | `{}` |
| `paths` | `[]` |
| `shell` | `bash` |
| `context` / `agent` | `''` (empty string) unless `context: fork` |

## Skill-type rules

| Type | `user-invocable` | `disable-model-invocation` | Typical `effort` |
|------|------------------|----------------------------|------------------|
| User slash workflow | `true` | `true` | `high` |
| Auto-trigger discovery | `true` | `false` | `medium` |
| Internal companion | `false` | `true` | `low` |
| Forked subagent | `true` | `true` | `medium` + `context: fork` + `agent` |

**Hard rule:** `user-invocable: false` must pair with `disable-model-invocation: true`.

## After editing any SKILL.md

```bash
python3 scripts/validate-skill-frontmatter.py path/to/SKILL.md
make validate
```

Never hand-write a skill from scratch without the `skill-creator` skill and the
template above.
