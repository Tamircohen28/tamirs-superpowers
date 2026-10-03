# Canonical roles

A **role** is what a unit of work needs done. A **provider** (claude, codex,
cursor, gemini, opencode) is which harness happens to do it. They are separate
concepts and resolve separately — see [REFACTOR-SPEC §2.3] and
[`core/policies/`](../policies/) for the policies every role inherits.

Each file in this directory is the single canonical definition of one role.
Agent definitions under [`agents/`](../../agents/) and skills under
[`skills/`](../../skills/) **reference** these files; they must not restate the
contract, because a restated contract drifts.

## Role list

| Role | File | Writes? | Default validation tier |
|------|------|:-------:|-------------------------|
| planner | [planner.md](planner.md) | no (plan artifacts only) | 0 |
| orchestrator | [orchestrator.md](orchestrator.md) | state files only | 0 |
| implementer | [implementer.md](implementer.md) | yes (task scope) | 1 |
| test-engineer | [test-engineer.md](test-engineer.md) | yes (tests) | 1 |
| reviewer | [reviewer.md](reviewer.md) | no | 2 |
| security-reviewer | [security-reviewer.md](security-reviewer.md) | no | 2 |
| performance-reviewer | [performance-reviewer.md](performance-reviewer.md) | no | 2 |
| debugger | [debugger.md](debugger.md) | no by default | 1 |
| integrator | [integrator.md](integrator.md) | yes (integration branch) | 2 |
| research-agent | [research-agent.md](research-agent.md) | no | 0 |

`scripts/validate-roles.sh` enforces that this list and the files agree, and
that every `agents/*.md` declares a `role:` that exists here.

## Capability keys

Required capabilities are named using keys from
`core/capabilities/schema.json`. A role must degrade explicitly when a
capability is absent: use a stated fallback, or say the feature is unsupported.
Never silently pretend it worked.
