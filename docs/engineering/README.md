# Engineering documentation

How the toolkit works under the hood. Users want [docs/user/](../user/README.md);
contributors want [CONTRIBUTING](../CONTRIBUTING.md).

## Architecture

| Doc | What it covers |
|---|---|
| [Overview](architecture/overview.md) | Layer map, the five subsystems, data flow |
| [Capability model](architecture/capability-model.md) | The registry, status vocabulary, how degradation works |
| [Adapter contract](architecture/adapter-contract.md) | What a platform adapter may and may not be |
| [Adding a platform](architecture/adding-a-platform.md) | The checklist, from registry entry to CI |
| [Skill schema](architecture/skill-schema.md) | Portable three-tier frontmatter, validation profiles |
| [Hooks classification](architecture/hooks-classification.md) | Which hooks port to which platform, and what replaces them |
| [Orchestration state machine](architecture/orchestration-state-machine.md) | Objective / task / handoff states, transitions, resume |
| [Branch and worktree model](architecture/branch-worktree-model.md) | Branch layout, worktree layout, legacy migration |
| [Validation tiers](architecture/validation-tiers.md) | Tiers 0–3: who runs what, and how a tier is declared |
| [Statusline](statusline.md) | Input schema, rendering, color coding |

## Build and release

| Doc | What it covers |
|---|---|
| [Versioning and release](build-and-release/versioning.md) | Canonical version, consumers, bump rules, release steps |
| [Testing matrix](build-and-release/testing-matrix.md) | Every check, where it runs, what it proves |
| [CI workflow](build-and-release/ci-workflow.md) | The CI jobs, explained |
| [Development workflow](build-and-release/development-workflow.md) | How to contribute code |
| [Platform targets](build-and-release/platform-targets.md) | Version floors and the co-change rule |

## Decisions and history

| Doc | What it covers |
|---|---|
| [ADR index](decisions/README.md) | Design decisions and their rationale |
| [Refactor artifacts](refactor/README.md) | Point-in-time inventory from the portable-orchestration refactor |
| [Agent-kit contract](../user/agent-kit.md) | User guide for `plugin-gold` distribution repos |
