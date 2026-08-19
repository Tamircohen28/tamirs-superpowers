---
alwaysApply: false
globs: ["skills/**/SKILL.md"]
---

# Skill Quality Standards — tamirs-superpowers

Rules for creating and maintaining skills in `skills/<domain>/<skill-name>/`.

Skills in this repo are **portable Agent Skills first**, with platform extensions
layered on top. They ship to Claude Code, Claude Desktop, Codex, Cursor, Gemini
CLI, and OpenCode.

**Canonical schema:** [`core/schemas/skill-frontmatter.json`](../../core/schemas/skill-frontmatter.json)
**Reference doc:** [`docs/engineering/architecture/skill-schema.md`](../../docs/engineering/architecture/skill-schema.md)
**Validator:** `python3 scripts/validate-skill-frontmatter.py`

## Retired: "all 16 Claude fields, everywhere"

The previous rule required every official Claude Code frontmatter field on every
`SKILL.md`. That made a single harness's field list the canonical contract for a
six-target project, and it forced meaningless values (`hooks: {}`, `paths: []`,
`shell: bash`) onto skills that never use them just to satisfy a validator.

**It is replaced by a three-tier contract:**

| Tier | Scope | Enforcement |
|------|-------|-------------|
| **portable** | The Agent Skills standard: `name`, `description`, optional `license` / `compatibility` | **Required on every skill. Violations fail the build.** |
| **tamirs** | `metadata.tamirs` — this framework's semantics | Validated when present. Absent = warning during migration; `--require-tamirs` promotes it to a failure. |
| **claude** | Claude Code / Claude Desktop extension fields | Validated **only when present**. Never required by the portable tier. |

## Tier 1 — portable core (required)

```yaml
---
name: <skill-name>              # kebab-case, MUST match the directory name
description: "Use when ..."     # <=1536 chars; carries the trigger phrases
---
```

`description` is the **only** trigger signal on platforms without `when_to_use`.
Write it so a harness that reads nothing else still routes correctly.

Optional portable fields:

- `license` — SPDX id, when the skill is separately licensed.
- `compatibility` — declare it whenever the skill is **not** universal:

  ```yaml
  compatibility:
    claude-code: supported
    claude-desktop: partial
    codex: unsupported
    cursor: supported
    gemini: unsupported
    opencode: emulated
  ```

  Platforms: `claude-code`, `claude-desktop`, `codex`, `cursor`, `gemini`, `opencode`.
  Levels: `supported`, `partial`, `emulated`, `unsupported`, `unknown`.

  **Write `unknown` for any platform you have not actually tested.** It resolves
  to *unavailable* at runtime — an unverified platform is not a supported one.
  Writing `supported` and hoping violates "evidence over declarations"; `unknown`
  is how you stay honest without leaving the field blank.

  These five are not the capability registry's seven statuses, deliberately: a
  registry status is a *mechanism* claim about a platform (`native` vs `adapter`),
  while `compatibility:` is a *works/doesn't* claim about a skill. A working
  adapter is `supported` from the skill's side. Status definitions, the mapping,
  and the derivation from `capabilities.required` are all canonical in
  [`capability-model.md`](../../docs/engineering/architecture/capability-model.md);
  [`skill-schema.md`](../../docs/engineering/architecture/skill-schema.md) explains
  why the two vocabularies differ.

  **Prefer declaring accurate `capabilities` over hand-writing `compatibility`.**
  Compatibility can be derived from a skill's required capabilities against the
  registry; a hand-written block is a claim, the derivation is computed. Write one
  explicitly only for constraints the capability model cannot see — e.g.
  `session-report` needs a Claude-specific transcript format, `notify-setup`
  assumes macOS.

  Omitting the block asserts the skill is portable — do not omit it to dodge the
  question.

## Tier 2 — `metadata.tamirs` (framework namespace)

Namespaced under `metadata` precisely so every non-Claude harness ignores it
without error.

```yaml
metadata:
  updated-date: "2026-08-19"    # legacy location; keep it where it already exists
  tamirs:
    visibility: public          # public | internal
    category: dev-workflow      # MUST equal the domain directory under skills/
    capabilities:
      required: [skills, shell]
      optional: [subagents, github_cli]
    role: implementer
    updated-date: "2026-08-19"
    validation-tier: 1          # optional, 0-3 (see rules/dev + REFACTOR-SPEC §9)
```

- `visibility: internal` iff `user-invocable: false`.
- `category` must equal the domain directory — a mismatch is a hard error, so a
  moved skill cannot silently keep a stale domain.
- `role` is one of `planner`, `orchestrator`, `implementer`, `test-engineer`,
  `reviewer`, `security-reviewer`, `performance-reviewer`, `debugger`,
  `integrator`, `research-agent`, `none`. **Roles are provider-independent** —
  never name a model or a platform here.
- `capabilities` ids must exist in the capability registry under
  `core/capabilities/`, and are **snake_case** (`github_cli`, not `github-cli`).
  Omit the key rather than writing empty lists.
  - `required` — the skill declares itself unavailable by name where the
    capability is `unsupported` **or `unknown`**. Unknown counts as absent: an
    unverified capability is not a capability.
  - `optional` — the skill must have a working path when it is absent. If it
    does not, it was never optional.
  - There is **no filesystem capability** — every harness has one. A skill that
    reads files declares nothing; a skill that shells out declares `shell`.

  Note the two namespaces: capability ids and the registry's platform keys are
  snake_case (`claude_code`), while the `compatibility:` block above uses
  kebab-case (`claude-code`). See
  [`docs/engineering/architecture/capability-model.md`](../../docs/engineering/architecture/capability-model.md).

## Tier 3 — platform extensions

Claude Code fields (`when_to_use`, `argument-hint`, `arguments`,
`user-invocable`, `disable-model-invocation`, `allowed-tools`,
`disallowed-tools`, `model`, `effort`, `context`, `background`, `agent`,
`hooks`, `paths`, `shell`) stay at the top level of the canonical `SKILL.md`.

That is allowed **only** because the Agent Skills standard specifies that
unknown frontmatter keys are ignored, and because the validator confirms they do
not affect the portable tier. The rules:

1. **Add a platform field only when the skill actually uses it.** Do not pad.
2. **Never encode required behaviour in a platform field alone.** If the skill
   cannot work without it, the skill needs a `compatibility` declaration and a
   capability entry, not just a Claude key.
3. **If a field ever stops being safely ignorable** on another target, it moves
   out of the canonical skill into a generated Claude adapter.

Still enforced whenever the relevant fields are present:

- `name` == directory name.
- `description` + `when_to_use` <= 1536 chars combined.
- `user-invocable: false` requires `disable-model-invocation: true`.
- `context: fork` requires a non-empty `agent`; otherwise `agent` is `''`.
- `allowed-tools` must be non-empty when present.

### Invocation tiers

| Type | `user-invocable` | `disable-model-invocation` | Examples |
|------|:---:|:---:|----------|
| User workflow (slash + auto-trigger) | `true` | `false` | plan-dev, pr-dev, repo-standards, cleanup, retro |
| Auto-trigger discovery | `true` | `false` | find-skill, mcp-builder |
| Explicit-only (slash, no auto) | `true` | `true` | switch-dev |
| Internal companion | `false` | `true` | docs-review, mcp-pagination, changelog-review |
| Forked subagent | `true` | `true` | targeted-debug (`context: fork`, `agent: Explore`) |

**`disable-model-invocation: true` also blocks sub-agent and Workflow
orchestration** — a sub-agent invoking a skill *is* model invocation, so a gated
skill can never be fanned out. Prefer safety *inside* the skill over gating it:
`cleanup` stays model-invocable behind confirmation gates and a dry-run;
`retro` only ever proposes changes. Gate only what must never run autonomously.

Parent skills invoke internal companions with `Skill("skill-name")` — never
duplicate a companion's checklist inline.

## Directory layout

```
skills/<domain>/<skill-name>/
├── SKILL.md              # portable core + extensions + instructions (<500 lines)
├── references/           # deep docs loaded on demand
├── scripts/              # deterministic bash/node helpers
├── templates/            # reply bodies, issue templates, etc.
└── evals/evals.json      # optional golden cases
```

The **invocation name is the directory name** — keep `name` identical to it.

Every `references/…` and `evals/…` path named in the body, and every
`$CLAUDE_SKILL_DIR/…` path, must exist; the validator checks it. Bare `scripts/`,
`assets/` and `templates/` mentions are deliberately not checked, because
repo-generating skills legitimately name paths in the repo they scaffold.

## Portability rules for skill bodies

- Write instructions against **roles and capabilities**, not providers.
- Resolve helper scripts as "the directory containing the active `SKILL.md`";
  mention `$CLAUDE_SKILL_DIR` as the Claude-specific spelling, not the only one.
- Every platform-specific mechanic gets an explicit fallback or an explicit
  "unsupported on X" — never silently assume subagents, hooks, or a statusline.
- No employer IP, internal domains, or private org references.

## Body structure

1. **Why this skill exists** — 2-3 sentences, WHY-first
2. **Internal skills** (if any) — when to invoke companions
3. **Core workflow** — numbered steps
4. **Hard rules** — non-negotiable constraints
5. **Error handling** — table with 3+ common failures (workflow skills)
6. **References** — pointers to `references/`, `scripts/`, `templates/`

## Quality checklist

- [ ] `name` + `description` present; `name` matches the directory
- [ ] `description` carries the trigger phrases and is <=1536 chars
- [ ] `metadata.tamirs` present with `visibility`, `category`, `role`, `updated-date`
- [ ] Declared capabilities exist in `core/capabilities/`
- [ ] `compatibility` declared if the skill is not universal
- [ ] Platform fields present only where the skill uses them
- [ ] SKILL.md under 500 lines (`wc -l`)
- [ ] `python3 scripts/validate-skill-frontmatter.py <path>` passes

## Validation

```bash
python3 scripts/validate-skill-frontmatter.py path/to/SKILL.md
python3 scripts/validate-skill-frontmatter.py                       # whole tree
python3 scripts/validate-skill-frontmatter.py --json                # machine-readable
python3 scripts/normalize-skill-frontmatter.py --dry-run path/to/SKILL.md
make validate
```

Never hand-write a skill from scratch — use the `skill-creator` skill.
