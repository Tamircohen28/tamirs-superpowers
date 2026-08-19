# Skill frontmatter schema

Canonical reference for `SKILL.md` frontmatter in this repo.

| Artifact | Path |
|----------|------|
| Schema (JSON Schema 2020-12) | `core/schemas/skill-frontmatter.json` |
| Validator | `scripts/validate-skill-frontmatter.py` |
| Normalizer | `scripts/normalize-skill-frontmatter.py` |
| Authoring rule | `rules/dev/skill-quality-standards.md` |
| Claude adapter view | `.claude/rules/skill-frontmatter.md` |
| Capability registry | `core/capabilities/` |

## Why three tiers

This repo ships one `skills/` tree to six targets: Claude Code, Claude Desktop,
Codex, Cursor, Gemini CLI, and OpenCode. Those targets do not agree on a
frontmatter vocabulary. OpenCode and Gemini CLI implement the smaller Agent
Skills standard and ignore unknown keys; Claude Code extends the standard with
invocation and runtime fields.

The previous contract — "every `SKILL.md` carries all 16 official Claude Code
fields" — made one harness's field list the canonical schema for all six. It
also forced inert values (`hooks: {}`, `paths: []`, `shell: bash`) onto skills
that never use them, which is noise that reads as meaning.

The replacement separates *what every platform needs* from *what this framework
needs* from *what one harness understands*:

| Tier | Name | Contents | Enforcement |
|------|------|----------|-------------|
| 1 | **portable core** | `name`, `description`, optional `license`, `compatibility` | Required everywhere. Violations **fail the build**. |
| 2 | **tamirs metadata** | `metadata.tamirs.*` | Validated when present; absence warns. `--require-tamirs` fails instead. |
| 3 | **platform extensions** | Claude Code fields at top level | Validated when present. **Never universally required.** |

Tier 2 lives under `metadata` so that every non-Claude harness ignores it by the
standard's own rule, rather than by luck.

## Annotated example

```yaml
---
# ---- Tier 1: portable core (required on every platform) -------------------
name: worker-dev                    # kebab-case; MUST equal the directory name
# description: <=1536 chars. On platforms with no when_to_use this is the ONLY
# trigger signal, so it must carry the trigger phrases itself.
description: "Use when implementing a scoped task through to commit + handoff..."
license: MIT                        # optional, SPDX id
compatibility:                      # optional — declare when NOT universal
  claude-code: supported
  claude-desktop: partial
  codex: supported
  cursor: supported
  gemini: partial
  opencode: emulated

# ---- Tier 3: Claude Code / Claude Desktop extensions (optional) -----------
# Present because this skill uses them. Other harnesses ignore unknown keys.
when_to_use: "implement issue #N, build the feature, work on this spec"
argument-hint: "[issue number | task description | spec path]"
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools: [Bash, Read, Edit, Skill]
disallowed-tools: []
model: claude-sonnet-4-6
effort: high
context: ''                         # 'fork' + a non-empty `agent` to run forked
agent: ''
hooks: {}
paths: []
shell: bash

# ---- Tier 2: framework metadata ------------------------------------------
metadata:
  updated-date: "2026-08-19"        # legacy mirror of metadata.tamirs.updated-date
  tamirs:
    visibility: public              # public | internal
    category: dev-workflow          # MUST equal the domain dir under skills/
    capabilities:
      required: [skills, shell, git]
      optional: [subagents, github_cli, worktree_isolation]
    role: implementer               # provider-independent orchestration role
    updated-date: "2026-08-19"
    validation-tier: 1              # optional 0-3
---
```

### Tier 2 field semantics

| Field | Required | Meaning |
|-------|:---:|---------|
| `visibility` | yes | `internal` iff `user-invocable: false`; otherwise `public` |
| `category` | yes | Domain directory. Mismatch with the path is a hard error, so a moved skill cannot keep a stale domain |
| `role` | yes | One of `planner`, `orchestrator`, `implementer`, `test-engineer`, `reviewer`, `security-reviewer`, `performance-reviewer`, `debugger`, `integrator`, `research-agent`, `none`. Never a model or platform name |
| `updated-date` | yes | `YYYY-MM-DD`, quoted or bare |
| `capabilities` | no | `{required: [], optional: []}`; ids must exist in `core/capabilities/`. Omit the key rather than writing empty lists |
| `validation-tier` | no | Integer 0-3 — highest validation tier the skill participates in |
| `tags` | no | Free-form list of strings |

`required` means the skill **cannot run** without the capability. Anything the
skill can degrade around belongs in `optional`. This is what makes
capability-based degradation checkable rather than aspirational.

The runtime meaning is precise (see
[`capability-model.md` → How a skill declares capabilities](capability-model.md#how-a-skill-declares-capabilities)):

- **`required`** — on a platform where the capability is `unsupported` **or
  `unknown`**, the skill declares itself unavailable by name. Unknown is treated
  as absent: an unverified capability is not a capability.
- **`optional`** — the skill must have a working path when it is absent. If it
  does not, the capability was never optional.

**There is no filesystem capability**, deliberately: every harness has one, so a
capability that is always present carries no information. A skill that reads
files declares nothing; a skill that shells out declares `shell`. (Spec §3.4's
`filesystem-read` example predates the registry and is not a valid id.)

### `compatibility` values vs registry statuses

The capability registry uses a seven-value status vocabulary
(`native`, `native-experimental`, `adapter`, `partial`, `emulated`,
`unsupported`, `unknown`). A skill's `compatibility:` block uses five. That is
deliberate, not drift — the two describe **different kinds of claim**:

- A registry status is a **mechanism** claim about a platform: *how* it provides
  a capability. Whether OpenCode's subagents are native or a generated adapter
  is a real and useful distinction **for the registry**.
- `compatibility:` is a **works / doesn't work** claim about a **skill**. A skill
  author neither knows nor should assert the mechanism — from the skill's point
  of view, a working adapter *is* support.

Forcing mechanism vocabulary onto skill authors would make the field harder to
fill in honestly, which is the opposite of what it is for.

**The mapping itself lives in
[`capability-model.md` → "Derivation"](capability-model.md#derivation)**, together
with the precedence rule for when required capabilities land on different values.
It is not repeated here: it agrees exactly with what this page would have said
(`native` / `native-experimental` / `adapter` → `supported`, the rest 1:1), and a
second copy would be the drift this page spent a paragraph arguing against.
`scripts/check-capability-registry.sh` asserts the mapping is total in both
directions, so neither enum can grow a value with no counterpart.

**`unknown` is the one value that means the same thing at both levels**, because
it is epistemic rather than mechanistic: nobody has measured it. It resolves to
*unavailable* at runtime, exactly as in the registry — an unverified platform is
not a supported platform.

> **Canonical definitions live in
> [`capability-model.md`](capability-model.md).** That document owns the seven
> [registry statuses](capability-model.md#status-values), the
> [`required` / `optional` contract](capability-model.md#how-a-skill-declares-capabilities),
> and the [derivation](capability-model.md#derivation) of a skill's compatibility
> from its `capabilities.required` against a platform's capability rows. This
> page deliberately **links rather than restates** them: a mirrored table is a
> second source of truth, and the one thing guaranteed about two copies of a
> table is that they diverge.
>
> What this page owns is the *explanation of why the two vocabularies differ* —
> a frontmatter-authoring concern that has no place in the registry's own
> documentation. Every rule and every table lives on the other side of these
> links.

### Deriving `compatibility` instead of writing it

The five values are not only hand-written. A skill that declares
`metadata.tamirs.capabilities.required` has already said enough to *compute* its
compatibility per platform: take each required capability, look up its status in
the platform's registry row, and reduce to the worst outcome.

The table and the worst-wins precedence that resolves ties are maintained in
[`capability-model.md` → "Derivation"](capability-model.md#derivation) — that
ordering is deliberately not restated here, because a skill with one `partial`
and one `unsupported` required capability needs exactly one answer, and two
copies of a precedence rule is how you end up with two answers.

Where a skill's declared `compatibility` and its derived compatibility disagree, **the derivation is
right and the declaration is stale** — the hand-written block is a claim, the
derivation is computed from measured rows. Prefer declaring accurate
`capabilities` and letting compatibility follow; write an explicit
`compatibility` block for constraints the capability model cannot see, such as
`session-report` depending on a Claude-specific session transcript format, or
`notify-setup` assuming macOS.

Write `unknown` when you have not tested a platform. Do not write `supported`
and hope; "evidence over declarations" is a non-negotiable of this project, and
`unknown` is the value that lets you comply with it truthfully.

Omitting the whole `compatibility` block still asserts "assumed portable", which
is right for the majority of skills. Once you declare the block at all, every
platform you list is a claim you are making — use `unknown` for the ones you
cannot back.

### Two id namespaces — do not mix them

| Where | Casing | Example |
|-------|--------|---------|
| Capability ids (`metadata.tamirs.capabilities`) | snake_case | `github_cli`, `worktree_isolation` |
| Platform keys inside the capability registry | snake_case | `claude_code`, `gemini_cli` |
| Platform keys in a skill's `compatibility:` block | kebab-case | `claude-code`, `gemini` |

The `compatibility` keys are frontmatter, and follow frontmatter convention; the
registry keys match `docs/engineering/build-and-release/platform-targets.json`.
The validator enforces each set in its own place, so a kebab-case id in
`capabilities` fails with "unknown capability id".

## Per-platform field support

| Field | Claude Code | Claude Desktop | Codex | Cursor | Gemini CLI | OpenCode |
|-------|:---:|:---:|:---:|:---:|:---:|:---:|
| `name` | read | read | read | read | read | read |
| `description` | read | read | read | read | read | read |
| `license` | ignored | ignored | ignored | ignored | ignored | ignored |
| `compatibility` | ignored | ignored | ignored | ignored | ignored | ignored |
| `metadata` (incl. `tamirs`) | ignored | ignored | ignored | ignored | ignored | ignored |
| `when_to_use` | read | read | ignored | ignored | ignored | ignored |
| `argument-hint` / `arguments` | read | read | ignored | ignored | ignored | ignored |
| `user-invocable` | read | read | ignored | ignored | ignored | ignored |
| `disable-model-invocation` | read | read | ignored | ignored | ignored | ignored |
| `allowed-tools` / `disallowed-tools` | read | read | ignored | ignored | ignored | ignored |
| `model` / `effort` | read | read | ignored | ignored | ignored | ignored |
| `context` / `agent` / `background` | read | read | ignored | ignored | ignored | ignored |
| `hooks` / `paths` / `shell` | read | read | ignored | ignored | ignored | ignored |

"ignored" is the Agent Skills standard's stated behaviour for unrecognised
frontmatter keys — it is what makes tier 3 safe to keep in the canonical file.
It is also the load-bearing assumption of this design: **if a target ever starts
erroring on an unknown key, that field moves out of the canonical `SKILL.md`
into a generated Claude adapter representation.** The per-platform contract
tests (REFACTOR-SPEC §22.4) are where that would surface.

## Validation

```bash
# Default: portable fails, tamirs warns, claude validates what is present
python3 scripts/validate-skill-frontmatter.py

# One file / one directory
python3 scripts/validate-skill-frontmatter.py skills/dev-workflow/plan-dev/SKILL.md

# Migration enforcement — missing metadata.tamirs becomes a failure
python3 scripts/validate-skill-frontmatter.py --require-tamirs

# Machine-readable, for orchestration
python3 scripts/validate-skill-frontmatter.py --json | jq '.tier_failures'
```

Exit code is 0 only when no tier reports an error. Warnings never fail the
build; they are how the tree stays green while `metadata.tamirs` rolls out.

### `--json` shape

```json
{
  "profile": "portable",
  "require_tamirs": false,
  "capability_registry": ["core/capabilities/schema.json"],
  "total": 34,
  "failed": 0,
  "warned": 34,
  "tier_failures": { "portable": 0, "tamirs": 0, "claude": 0 },
  "results": [
    {
      "file": "skills/dev-workflow/plan-dev/SKILL.md",
      "passed": true,
      "tiers": {
        "portable": { "errors": [], "warnings": [] },
        "tamirs":   { "errors": [], "warnings": ["metadata.tamirs is absent — ..."] },
        "claude":   { "errors": [], "warnings": [] }
      },
      "errors": [],
      "warnings": ["[tamirs] metadata.tamirs is absent — ..."]
    }
  ]
}
```

`capability_registry` is `null` when no registry file was found — that is how a
consumer tells "no capability problems" apart from "capabilities unverified".

### Additional checks

- `name` must equal the containing directory name (plugin-root
  `.claude/skills/` is exempt).
- `description` alone <=1536 chars; `description` + `when_to_use` <=1536 chars.
- `user-invocable` and `disable-model-invocation` are **independent**. `user-invocable: false` alone stops `/slash` invocation, which is all an internal
  companion needs. Adding `disable-model-invocation: true` on top additionally blocks
  **sub-agent and orchestration** invocation — a sub-agent calling a skill *is* model
  invocation — so gating a companion that a parent skill calls breaks it under
  `orchestrate-dev`. Gate only a skill that must never run autonomously.
- `context: fork` requires a non-empty `agent`; otherwise `agent` must be `''`.
- Every `references/…` and `evals/…` path named in the body, and every
  `$CLAUDE_SKILL_DIR/…` path, must resolve. Bare `scripts/`, `assets/` and
  `templates/` mentions are **not** checked — repo-generating skills
  (`repo-scaffold`, `multi-agent-repo`) legitimately name paths in the repo they
  scaffold, and flagging those would be a false positive rather than a finding.
- Declared capability ids must exist in `core/capabilities/`. If the registry
  file is absent the check is skipped and reported as skipped, never silently
  passed.

### Where each vocabulary actually comes from

The validator hardcodes nothing it can derive. Each vocabulary has exactly one
owner, and the validator reads it from that owner at runtime:

| Vocabulary | Canonical source | How the validator gets it |
|---|---|---|
| **Roles** | `core/roles/` — one `<role>.md` per role | Derived from the directory listing, plus the `none` sentinel. **Adding an eleventh role is a new `.md` file and nothing else** — no schema edit, no validator edit. |
| Capability ids | `core/capabilities/` | `$defs.capabilityKey.enum`, else `capability_definitions` keys |
| `compatibility` platforms | this schema (curated) | `$defs.compatibility.propertyNames.enum` |
| `compatibility` levels | this schema | `$defs.compatibility.additionalProperties.enum` |
| visibility, effort, shell, context | this schema | read from the matching `$defs` |

Hardcoded fallbacks exist only so the script still runs against a partial
checkout. Dependency profile is python3 + PyYAML
(`scripts/requirements-validate.txt`) — no `jsonschema` dependency.

**Roles: `core/roles/` wins, this schema documents.** The `role` enum in
`skill-frontmatter.json` is documentation of record, not the source. If the two
disagree, the validator accepts what `core/roles/` defines and reports the enum
as stale **by name**, without failing:

```
role vocabulary: 12 role(s) from core/roles/
  ~ drift: core/schemas/skill-frontmatter.json role enum is missing:
    release-manager (defined in core/roles/; accepted anyway)
```

A role in the enum with no `core/roles/` file is rejected and reported the other
way. Drift is visible, never silent, and never blocks the role owner's work.

**Platforms are curated on purpose.** The `compatibility` platform list is not
derived from the capability registry's platform ids or their aliases. The
registry is snake_case (`claude_code`, `gemini_cli`) and the kebab mapping is
not a pure transform — `gemini_cli` maps to `gemini`, not `gemini-cli` — so it
cannot be computed. Deriving from the alias sets would accept several spellings
for one platform and let two skills spell the same target differently, which is
worse than a six-entry curated list. `scripts/check-capability-registry.sh`
asserts that every value here resolves to a registry entry, so a divergence
fails loudly rather than drifting.

## Migrating an existing skill

1. **Look at the current shape.**

   ```bash
   python3 scripts/normalize-skill-frontmatter.py --dry-run skills/<domain>/<skill>/SKILL.md
   ```

   The diff shows exactly what the canonical shape adds — normally just the
   `metadata.tamirs` block and field reordering.

2. **Apply it**, either by writing the block by hand or by dropping `--dry-run`.
   The normalizer never invents Claude fields a skill does not already have, and
   never guesses capabilities.

3. **Fill in what the normalizer cannot infer.** `role` defaults to `none` and
   `capabilities` is left empty; both need a human decision. Add
   `compatibility` if the skill is not universal.

4. **Verify.**

   ```bash
   python3 scripts/validate-skill-frontmatter.py skills/<domain>/<skill>/SKILL.md
   ```

5. **Once the whole tree carries `metadata.tamirs`,** flip CI to
   `--require-tamirs` so the warning becomes a gate.

## Authoring a new skill

Use the `skill-creator` skill. A new skill needs only the portable core plus
`metadata.tamirs`; add Claude extension fields as the body starts to use them.

```yaml
---
name: my-skill
description: "Use when ..."
metadata:
  tamirs:
    visibility: public
    category: toolkit
    role: none
    updated-date: "2026-08-19"
---
```

That file passes today. Every field beyond it must earn its place.
