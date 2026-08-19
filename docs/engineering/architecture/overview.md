# Architecture overview

`tamirs-superpowers` is a **portable agent toolkit**: one canonical body of skills, roles,
rules, and policies, delivered to six agent platforms through thin adapters. It is not a
Node/Python/Go application — there is no build step, no `package.json`, no compiled output.
All content is Markdown, JSON, and bash.

Two rules shape the whole design:

1. **One canonical source, thin adapters.** Nothing is duplicated per platform. A
   per-platform file is either a reference to canonical content or a *generated* artifact
   whose drift fails CI.
2. **Capability-based degradation.** Nothing assumes subagents, hooks, or a statusline
   exist. A missing capability produces a stated fallback or an explicit "unsupported" —
   never a silent pretence.

---

## Layer map

```text
tamirs-superpowers/
├── core/                        ← the canonical model (platform-agnostic)
│   ├── capabilities/            ← platforms.json (registry) + schema.json (vocabulary)
│   ├── policies/                ← safety, git, validation, delivery
│   ├── roles/                   ← the ten role contracts
│   ├── providers/               ← provider selection
│   ├── schemas/                 ← skill frontmatter schema
│   └── workflow/                ← objective / task / handoff JSON schemas
├── skills/<domain>/<name>/SKILL.md   ← 30 skills, consumed directly by every platform
├── agents/                      ← ten agent definitions, each declaring a role:
├── rules/                       ← canonical project rules
├── platforms/                   ← per-platform adapter.yaml descriptors
├── hooks/                       ← Claude-shaped lifecycle hooks (+ shared bash lib)
├── scripts/                     ← doctor, drift checks, generators, statusline
├── tests/                       ← behavior tests for hooks and adapters
└── per-platform manifests       ← .claude-plugin/, .cursor-plugin/, .codex-plugin/,
                                    .agents/plugins/, gemini-extension.json, opencode.json
```

The direction of dependency only ever points inward: adapters read `core/`, never the
reverse.

## The five subsystems

### 1. Capability registry

[`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json) is the
single source of truth for what each platform supports, with a status
(`native` / `adapter` / `emulated` / `partial` / `unknown` / `unsupported`), a validation
command where one exists, and a fallback where the status is not `native`. Skills read it at
runtime; docs render from it; `scripts/check-capability-registry.sh` validates it.
Details: [capability-model.md](capability-model.md).

### 2. Roles and agents

[`core/roles/`](../../../core/roles/README.md) defines ten roles as contracts. Each
`agents/*.md` declares which `role:` it plays and adds nothing that contradicts it —
`scripts/validate-roles.sh` enforces the agreement. Role is separate from **provider**
(claude, codex, cursor, gemini, opencode), which is metadata only and never appears in a
branch name or path.

### 3. Skills

Portable three-tier frontmatter: a required portable core (`name`, `description`), the
`metadata.tamirs` framework block, and optional Claude-specific extensions validated only
when present. The old "all 16 Claude fields, always" requirement is retired; nothing
regresses, because `--profile claude-strict` still enforces it for skills that carry them.
Details: [skill-schema.md](skill-schema.md).

### 4. Orchestration

An objective is decomposed into tasks with disjoint write scopes, each ending at
**commit + handoff**, merged onto one integration branch, reviewed as one diff, and delivered
as **one PR**. State is plain files under `.dev-files/objectives/<id>/`, so an objective
resumes after any interruption — including under a different platform.
Details: [orchestration-state-machine.md](orchestration-state-machine.md),
[branch-worktree-model.md](branch-worktree-model.md).

### 5. Adapters

Each platform gets a `platforms/<id>/adapter.yaml` descriptor plus whatever manifest that
platform actually resolves. Generated artifacts (`.opencode/agent/`, `.cursor/rules/*.mdc`)
have a generator and a drift check; hand-editing them is a bug.
Details: [adapter-contract.md](adapter-contract.md),
[adding-a-platform.md](adding-a-platform.md).

---

## Hooks

Hooks are the Claude-shaped lifecycle mechanism in [`hooks/hooks.json`](../../../hooks/hooks.json):
worktree creation from the first prompt, edit isolation, sensitive-file guards, changelog
display on update, session bookkeeping, notifications. They run **as shipped only on Claude
Code**. Codex has a differently shaped manifest `hooks` field; Cursor runs project-level
guards; Gemini documents hooks as an extension payload; OpenCode has no hook mechanism that
does not require a Node runtime, so none is shipped.

Because of that, no guarantee may depend on a hook. Every hook-enforced rule also exists as
an explicit step inside the relevant skill and as a check in CI. Per-platform
classification: [hooks-classification.md](hooks-classification.md).

## Validation tiers

Tier 0 edit-time · Tier 1 worker · Tier 2 integration · Tier 3 delivery/CI. Every skill and
script declares its tier; a validation step with an unstated tier is a bug.
Details: [validation-tiers.md](validation-tiers.md).

## Version truth

[`plugin-version.json`](../../../plugin-version.json) is the canonical version. Every other
occurrence — four manifests, the README badge, `platform-targets.json` — is a declared
*consumer*, checked by `scripts/check-version-truth.sh` and repaired by its `--sync` flag.
Never hand-edit a consumer. Details: [../build-and-release/versioning.md](../build-and-release/versioning.md).

## Data flow for one skill invocation

```text
user invokes /orchestrate-dev
  → platform loads skills/dev-workflow/orchestrate-dev/SKILL.md
  → skill reads core/capabilities/platforms.json  → picks concurrent | serialized | sequential
  → skill reads core/roles/ + core/policies/      → contracts it will not restate
  → writes .dev-files/objectives/<id>/            → objective + task state
  → dispatches worker-dev per task                → commit + handoff, Tier 1
  → integrates, reviews combined diff             → Tier 2
  → deliver-dev                                   → one PR → pr-dev → Tier 3 (CI)
```

## Where to go next

| Topic | Doc |
|---|---|
| What each platform supports and why | [capability-model.md](capability-model.md) |
| What an adapter must provide | [adapter-contract.md](adapter-contract.md) |
| Adding a sixth… seventh platform | [adding-a-platform.md](adding-a-platform.md) |
| Skill frontmatter contract | [skill-schema.md](skill-schema.md) |
| Objective/task/handoff states | [orchestration-state-machine.md](orchestration-state-machine.md) |
| Branch and worktree layout | [branch-worktree-model.md](branch-worktree-model.md) |
| What runs where, and when | [validation-tiers.md](validation-tiers.md) · [../build-and-release/testing-matrix.md](../build-and-release/testing-matrix.md) |
