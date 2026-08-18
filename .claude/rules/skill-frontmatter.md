---
paths:
  - "skills/**/SKILL.md"
  - ".claude/skills/**/SKILL.md"
---

# SKILL.md frontmatter — Claude Code adapter view

**Canonical rule:** [`rules/dev/skill-quality-standards.md`](../../rules/dev/skill-quality-standards.md)
**Canonical schema:** [`core/schemas/skill-frontmatter.json`](../../core/schemas/skill-frontmatter.json)
**Reference:** [`docs/engineering/architecture/skill-schema.md`](../../docs/engineering/architecture/skill-schema.md)

This file is a thin Claude Code view. It does not restate the contract — read
the canonical rule for the full three-tier definition and for the
`metadata.tamirs` field semantics.

## What Claude Code contributors need to know

1. **Only `name` and `description` are universally required.** The old "all 16
   official fields on every skill" requirement is retired.
2. **Claude extension fields are optional and validated when present** —
   `when_to_use`, `argument-hint`, `arguments`, `disable-model-invocation`,
   `user-invocable`, `allowed-tools`, `disallowed-tools`, `model`, `effort`,
   `context`, `background`, `agent`, `hooks`, `paths`, `shell`.
   Add one because the skill uses it, not to satisfy a validator.
3. **`metadata.tamirs` carries the framework semantics** (visibility, category,
   capabilities, role, updated-date). Add it to every skill you touch.
4. `--profile claude-strict` still enforces the legacy full-field gate, so
   existing skills must not lose fields they already have.

## Claude-specific pairings the validator enforces

| Rule | Why |
|------|-----|
| `user-invocable: false` requires `disable-model-invocation: true` | An internal companion must be unreachable both ways |
| `context: fork` requires a non-empty `agent` | A fork with no agent type has nothing to run |
| `context` not `fork` requires `agent: ''` | Prevents a dead agent reference |
| `description` + `when_to_use` <= 1536 chars | Claude Code's skill listing cap |
| `allowed-tools` non-empty when present | An empty list silently disables the skill |

`disable-model-invocation: true` also blocks sub-agent and Workflow
orchestration. See the canonical rule before gating a skill.

## After editing any SKILL.md

```bash
python3 scripts/validate-skill-frontmatter.py path/to/SKILL.md
python3 scripts/validate-skill-frontmatter.py --profile claude-strict
make validate
```

Use the `skill-creator` skill rather than hand-writing frontmatter.
