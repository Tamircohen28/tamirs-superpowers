# Multi-agent audit rubric

Walk every section for review mode. Record each item as **pass**, **gap (P1/P2/P3)**, or **n/a**.

Severity guide:

- **P1** — blocks reliable multi-agent development; fix before claiming setup complete
- **P2** — real quality debt; fix in same remediation pass when possible
- **P3** — optional polish; document if deferred

---

## Layer 1 — AGENTS.md (canonical source of truth)

| ID | Check | P |
|----|-------|---|
| L1-01 | `AGENTS.md` exists at repo root | P1 |
| L1-02 | Plain Markdown — no YAML frontmatter | P1 |
| L1-03 | No Claude-only syntax (`!` blocks, `$CLAUDE_SKILL_DIR`, `#` directives) | P1 |
| L1-04 | File size ≤ 32 KiB (32768 bytes) | P1 |
| L1-05 | Length roughly 100–200 lines (warn if >250) | P2 |
| L1-06 | Has **install** command with exact package manager | P1 |
| L1-07 | Has **lint / typecheck / test** commands (actual shell commands) | P1 |
| L1-08 | Has **full validation** command (`make validate`, `pnpm agent:check`, etc.) | P1 |
| L1-09 | Lists non-negotiable constraints (secrets, force-push, CI, etc.) | P1 |
| L1-10 | Names exact paths for business logic / tests / shared utils | P2 |
| L1-11 | No vague advice ("write clean code") without concrete rules | P2 |
| L1-12 | No duplicated long architecture essay (prefer `docs/agent-guidelines/`) | P2 |
| L1-13 | Git / PR expectations section present | P2 |
| L1-14 | "When stuck" guidance (search codebase, read tests, ask user) | P3 |

---

## Layer 2 — CLAUDE.md (thin adapter)

| ID | Check | P |
|----|-------|---|
| L2-01 | `CLAUDE.md` exists | P1 |
| L2-02 | Imports or references `AGENTS.md` (`@AGENTS.md` or explicit "follow AGENTS.md") | P1 |
| L2-03 | Does not duplicate full AGENTS.md policy text | P1 |
| L2-04 | Claude-only addenda are short (< 30 lines) | P2 |
| L2-05 | No conflicting commands vs AGENTS.md | P1 |

---

## Layer 3 — Cursor rules (scoped adapters)

| ID | Check | P |
|----|-------|---|
| L3-01 | `.cursor/rules/` directory exists | P2 |
| L3-02 | All rule files use `.mdc` extension (no `.md` in rules dir) | P1 |
| L3-03 | At least one rule references `AGENTS.md` as canonical | P1 |
| L3-04 | ≤ 2 rules with `alwaysApply: true` | P1 |
| L3-05 | Scoped rules use `globs` for path-specific concerns | P2 |
| L3-06 | No full policy duplication — wrappers point to AGENTS.md | P1 |
| L3-07 | Legacy `.cursorrules` absent or migrated | P2 |
| L3-08 | Each `.mdc` file < 500 lines | P2 |

---

## Layer 4 — Skills portability

| ID | Check | P |
|----|-------|---|
| L4-01 | Repo type identified (app / claude-plugin / hybrid) | P1 |
| L4-02 | **App:** `.agents/skills/` exists OR documented alternative | P2 |
| L4-03 | **Plugin:** `skills/` declared in `.claude-plugin/plugin.json` | P1 |
| L4-04 | Skills use portable `SKILL.md` format (YAML frontmatter + body) | P2 |
| L4-05 | **Plugin:** frontmatter passes validate-skill-frontmatter if validator present | P2 |
| L4-06 | Bridge exists if skills only in one tool path (symlink or docs) | P1 |
| L4-07 | Skills hold workflows — not general standards (those belong in AGENTS.md) | P2 |
| L4-08 | `.codex-plugin/plugin.json` / `.cursor-plugin/plugin.json` if distributing as plugin | P3 |

---

## Layer 5 — Long-form agent docs

| ID | Check | P |
|----|-------|---|
| L5-01 | `docs/agent-guidelines/` directory exists | P2 |
| L5-02 | `architecture.md` (optional — linked from AGENTS.md) | P3 |
| L5-03 | `testing.md` | P2 |
| L5-04 | `security.md` | P2 |
| L5-05 | `style.md` | P3 |
| L5-06 | Long docs referenced from AGENTS.md, not inlined | P2 |

---

## Layer 6 — Mechanical enforcement

| ID | Check | P |
|----|-------|---|
| L6-01 | Linter configured and documented | P1 |
| L6-02 | Tests runnable via documented command | P1 |
| L6-03 | `agent:check` or equivalent in Makefile/package.json | P1 |
| L6-04 | CI runs same validation command as AGENTS.md states | P1 |
| L6-05 | Secret scanning in CI or pre-commit | P2 |
| L6-06 | `CODEOWNERS` for high-risk paths (optional for small repos) | P3 |
| L6-07 | Typechecker wired if typed language | P2 |
| L6-08 | Pre-commit hooks optional but documented | P3 |

---

## Layer 7 — Drift prevention

| ID | Check | P |
|----|-------|---|
| L7-01 | `scripts/check-agent-drift.sh` or equivalent exists | P2 |
| L7-02 | Drift script wired into `make validate` or `agent:rules` | P2 |
| L7-03 | `CLAUDE.md` references AGENTS.md (verified by drift script) | P1 |
| L7-04 | Primary Cursor rule references AGENTS.md | P1 |
| L7-05 | No conflicting test/lint policy across AGENTS / CLAUDE / .mdc | P1 |
| L7-06 | Optional `check-no-agent-drift.mjs` for Node ecosystems | P3 |

---

## Layer 8 — Codex-specific

| ID | Check | P |
|----|-------|---|
| L8-01 | Codex reads `AGENTS.md` — no separate `codex.md` required | n/a |
| L8-02 | `.codex/config.toml` present if repo documents Codex MCP/setup | P3 |
| L8-03 | AGENTS.md under 32 KiB for Codex instruction budget | P1 |

---

## Layer 8b — Gemini CLI-specific

| ID | Check | P |
|----|-------|---|
| L8b-01 | `gemini-extension.json` present when the repo declares `gemini_cli` support | P1 |
| L8b-02 | Manifest reuses the canonical `skills/` tree rather than a copied one | P1 |
| L8b-03 | `contextFileName` points at a file that exists (`GEMINI.md` or `AGENTS.md`) | P2 |
| L8b-04 | `gemini extensions validate .` runs clean, or is recorded as unrun with a reason | P2 |
| L8b-05 | No Node dependency added purely for the extension | P3 |

## Layer 8c — OpenCode-specific

| ID | Check | P |
|----|-------|---|
| L8c-01 | `opencode.json` points `skills.paths` at the canonical tree | P1 |
| L8c-02 | `.opencode/agent/` is generated and drift-checked, never hand-copied | P1 |
| L8c-03 | Guards are carried by in-skill steps + CI, not by a ported `hooks.json` (OpenCode has no hook config file) | P1 |
| L8c-04 | No capability is assumed for the OpenCode CLI surface without reading its registry row first | P1 |

**Do not pin a status in this rubric.** Every row above asks whether the repo *consulted*
the registry, never what the registry says. Statuses are re-measured and move; a rubric that
quotes one becomes wrong silently, which is the failure mode Layer 8d exists to prevent.

## Layer 8d — Capability registry

| ID | Check | P |
|----|-------|---|
| L8d-01 | `core/capabilities/platforms.json` exists when the repo targets ≥2 harnesses | P1 (plugin) / P2 (app) |
| L8d-02 | Validates against `core/capabilities/schema.json`; every **supported surface** covers every capability key | P1 |
| L8d-03 | Registry's supported-surface set equals `platform-targets.json` `supported_targets` plus surfaces carrying `runtime_surface_of` | P1 |
| L8d-04 | Every `native` claim carries a validation command; every non-native status carries a fallback or note | P1 |
| L8d-05 | No document restates a capability status the registry already owns | P2 |
| L8d-06 | Every `unverified` surface carries an `unverified_reason` and **no** `capabilities` block | P1 |
| L8d-07 | No document presents an `unverified` surface as a supported target, or counts it in a "N supported targets" claim | P1 |

The registry is rooted at the **platform** — one entry per vendor — with that platform's
runtime **surfaces** underneath, keyed by surface id. Capabilities hang off a surface, not
off a platform: the question a consumer asks is "can the harness I am running in do this?",
and Claude Code and Claude Desktop are one platform and two harnesses. Check a surface with:

```bash
jq --arg p claude_desktop '(first(.platforms[]?.surfaces[$p]? | select(. != null)) // .platforms[$p]?)' \
   core/capabilities/platforms.json
```

The `//` tail keeps the lookup working against an older flat `schema_version` 1 registry.
`scripts/lib/registry.sh` does this walk once and returns a flat, one-entry-per-supported-
surface view; scoring scripts read that rather than re-deriving the path.

Claude Desktop is a **supported surface** with its own measured capability rows, but it is
not a separate distribution format: it carries `runtime_surface_of: claude_code`, consumes
the Claude Code plugin, and is deliberately absent from `supported_targets`. Do not create
a Desktop manifest.

A surface whose `support` is `"unverified"` was never measured. It carries no capabilities
block, and the registry claims nothing about it in either direction — not that a feature
works there, and not that it fails. It gets no install guide, no badge, and no row in a
matrix that implies measurement.

---

## Layer 9 — Agent-kit distribution

Use when `repo_type` is `agent-kit` or contract profile is `plugin-gold`.

| ID | Check | P |
|----|-------|---|
| L9-01 | `canonical/rules/core.md` exists and is tool-neutral | P1 |
| L9-02 | `scripts/build.mjs` + `scripts/validate.mjs` present | P1 |
| L9-03 | `.claude-plugin/marketplace.json` lists `plugins/<name>` | P1 |
| L9-04 | `plugins/<name>/.claude-plugin/plugin.json` declares skills path | P1 |
| L9-05 | `dist/codex/AGENTS.md` and `dist/cursor/` rules have GENERATED markers | P2 |
| L9-06 | CI includes `validate` job (`npm run build && npm run validate`) | P2 |
| L9-07 | CODEOWNERS covers `canonical/`, `plugins/`, `scripts/`, `hooks/` | P2 |
| L9-08 | README documents marketplace install + build workflow | P2 |
| L9-09 | Skills authored in `canonical/skills/` — plugin copy is generated | P1 |

Auto-scored PK* gaps overlap L9-01–L9-07 — use inventory JSON + `score-plugin-gaps.sh` first.

---

## Report format

For each gap, record in the review report:

```markdown
### [L1-01] AGENTS.md missing
- **Severity:** P1
- **Evidence:** inventory JSON `agents_md.exists: false`
- **Remediation:** Create canonical AGENTS.md from README + Makefile commands
- **Phase:** 0
```

Summarize at top:

```markdown
| Severity | Count |
|----------|-------|
| P1 | N |
| P2 | N |
| P3 | N |
```


---

## Layer 10 — Feature equivalence (E-layer)

Auto-scored via `score-equivalence-gaps.sh`. Spec: `_contract/feature-equivalence.json`.

---

## Layer 11 — Platform target versions (V-layer)

Auto-scored via `score-platform-target-gaps.sh`. Canonical file: `docs/engineering/build-and-release/platform-targets.json`.
