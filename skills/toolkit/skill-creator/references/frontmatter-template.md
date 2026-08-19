# SKILL.md frontmatter — the portable-first contract

Canonical machine-readable source: **`core/schemas/skill-frontmatter.json`**.
Executable form: **`scripts/validate-skill-frontmatter.py`**.
This file is the human-readable companion; where it and the schema disagree, the schema wins.

A skill is an **Agent Skill first** and a Claude Code skill second. The old rule — "all 16
official Claude fields are required on every skill" — is gone. It made every skill in this
repo carry Claude-only fields that no other harness reads, which is not a portable contract;
it is one vendor's shape imposed on all of them.

## The three tiers

| Tier | What it is | Required? |
|---|---|---|
| **1 — portable core** | The Agent Skills standard: `name`, `description`, optionally `license` and `compatibility` | **Yes, on every skill, for every platform.** Violations fail the build. |
| **2 — `metadata.tamirs`** | This framework's own semantics, namespaced under `metadata` so foreign harnesses ignore it | Validated whenever present; `--require-tamirs` makes absence a failure |
| **3 — platform extensions** | Harness-specific fields other harnesses safely ignore | Permitted, **never universally required**; validated only when present |

Unknown top-level keys are ignored by every supported harness. That is what makes tier 3
safe — and what makes forcing tier 3 onto every skill pointless.

---

## Tier 1 — portable core

```yaml
name: my-skill                 # kebab-case; MUST equal the directory name
description: >-                # what it does AND when to use it
  Use when …  Triggers: '…', '…'.
```

| Field | Type | Rules |
|---|---|---|
| `name` | string | `^[a-z0-9]+(-[a-z0-9]+)*$`, ≤64 chars, equals the containing directory name |
| `description` | string | ≤1536 chars. **On platforms without `when_to_use`, this is the only trigger signal** — so the trigger phrases must live here, not only in the Claude field |
| `license` | string | optional; SPDX id or license name |
| `compatibility` | mapping | optional; platform id → `supported` \| `partial` \| `emulated` \| `unsupported` |

**Declare `compatibility` whenever the skill is genuinely not universal.** Omitting it means
"assumed portable", so silence on a platform-specific skill is a false claim. `session-report`
and `notify-setup` are the worked examples: both declare `unsupported` rows rather than
implying they work everywhere.

## Tier 2 — `metadata.tamirs`

```yaml
metadata:
  tamirs:
    visibility: public          # public | internal
    category: dev-workflow      # MUST equal the domain dir under skills/
    role: implementer           # provider-independent orchestration role
    validation-tier: 1          # 0 edit-time | 1 worker | 2 integration | 3 delivery
    updated-date: '2026-08-19'
    capabilities:
      required: [skills, shell] # ids from core/capabilities/schema.json ONLY
      optional: [subagents, git]
    tags: [example, portable]
```

`visibility`, `category`, `role` and `updated-date` are required **once the block is present**.

**`capabilities` is the honesty field, and it is the one most easily got wrong.**

- `required` — the skill cannot do its job without this. On a platform where the capability
  is `unsupported`, the skill must say so and stop, not half-run.
- `optional` — the skill is better with it and works without it. Every optional capability
  needs a real fallback written in the body.
- Every id must exist in `core/capabilities/schema.json` → `$defs.capabilityKey.enum`.
  Inventing an id fails validation, by design.
- **Do not pad `required`.** Listing `subagents` as required when the skill has a perfectly
  good sequential path makes the skill falsely unavailable. Do not under-declare either: a
  skill that silently produces garbage without a capability must declare it required.

Roles come from `core/roles/`; use `none` when the skill is not part of the orchestration
graph (`notify-setup`, `session-report`, `retro`).

## Tier 3 — platform extensions

Claude Code / Claude Desktop fields — all optional, all validated when present:

| Field | Notes |
|---|---|
| `when_to_use` | Claude trigger text. Counts toward the 1536-char listing cap with `description` |
| `argument-hint`, `arguments` | Slash-command surface |
| `user-invocable`, `disable-model-invocation` | Invocation tier — see below |
| `allowed-tools`, `disallowed-tools` | Tool names |
| `model`, `effort` | `effort`: `low`\|`medium`\|`high`\|`xhigh`\|`max` |
| `context`, `agent` | `context: fork` requires a non-empty `agent`; otherwise `agent` must be `''` |
| `hooks`, `paths`, `shell` | `shell`: `bash` \| `powershell` |

Two pairings the validator enforces:

- `context: fork` ⇒ `agent` non-empty; otherwise `agent: ''`.
- `user-invocable: false` ⇒ `disable-model-invocation: true`. A skill users cannot invoke
  must not be model-invocable either.

**Do not set `model` without a reason.** A pinned model id is a claim that ages; leave it out
and the user's configured model is used.

## Invocation tiers (Claude)

| Tier | `user-invocable` | `disable-model-invocation` | Use for |
|---|:--:|:--:|---|
| User + auto-trigger (default) | `true` | `false` | Most skills |
| Explicit-only | `true` | `true` | Skills whose autonomous run would surprise |
| Internal companion | `false` | `true` | Called only by another skill |

Gating a skill also blocks sub-agent and orchestration invocation — a sub-agent invoking a
skill *is* model invocation. Prefer safety inside the skill (confirmation gates, dry-run)
over gating it.

---

## Skeletons

### Minimum portable skill — valid everywhere

```yaml
---
name: my-skill
description: >-
  Use when … Triggers: 'phrase one', 'phrase two'.
metadata:
  tamirs:
    visibility: public
    category: toolkit
    role: none
    validation-tier: 0
    updated-date: 'YYYY-MM-DD'
    capabilities:
      required: [skills]
      optional: []
---
```

### Portable core + Claude extensions

```yaml
---
name: my-skill
description: >-
  Use when … Triggers: 'phrase one', 'phrase two'.
compatibility:
  claude-code: supported
  opencode: supported
when_to_use: |
  - "phrase one"
  - "phrase two"
argument-hint: '[input]'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools: [Read, Write, Bash]
disallowed-tools: []
effort: medium
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  tamirs:
    visibility: public
    category: dev-workflow
    role: implementer
    validation-tier: 1
    updated-date: 'YYYY-MM-DD'
    capabilities:
      required: [skills, shell]
      optional: [git, github_cli]
    tags: [example]
---
```

### Internal companion

Same as above with `user-invocable: false`, `disable-model-invocation: true`, and
`metadata.tamirs.visibility: internal`.

---

## Validation

```bash
# default: portable core enforced, tamirs validated when present
python3 scripts/validate-skill-frontmatter.py path/to/SKILL.md

# make the tamirs block mandatory
python3 scripts/validate-skill-frontmatter.py --require-tamirs
```

Claude extension fields are validated **only when present**. Add one because the skill uses
it — never to pad a new skill with fields it does not need.
