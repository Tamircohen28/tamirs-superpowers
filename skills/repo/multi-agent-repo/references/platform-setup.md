# Platform setup — dev mode phases 0–1

Use this reference when implementing phases 0–1 in **dev** mode (or quick file generation via `multi-agent-repo dev` without a prior plan). Replaces the former standalone `plugin-compat` skill.

## Step 1 — Fetch latest docs

**Always fetch first.** Run in parallel; on failure use `references/platform-specs.md` as fallback and note which platform could not be verified.

| Platform | URLs |
|----------|------|
| Claude Code | `https://code.claude.com/docs/en/plugins`, `https://code.claude.com/docs/en/skills` |
| Cursor | `https://cursor.com/docs/rules` |
| Codex | `https://developers.openai.com/codex/guides/agents-md`, `https://developers.openai.com/codex/config-basic` |
| Gemini CLI | `https://google-gemini.github.io/gemini-cli/docs/extensions/` |
| OpenCode | `https://opencode.ai/docs/skills/`, `https://opencode.ai/docs/agents/`, `https://opencode.ai/config.json` |

Cross-check live fetches against `references/platform-specs.md`; prefer live docs on conflict.

## Step 2 — Inventory gaps

Use `$INVENTORY` from `inventory-agent-setup.sh`. **Do not overwrite files already correct** per fetched specs.

## Step 3 — Phase 0: canonical AGENTS.md

Create or repair `AGENTS.md` at repo root:

- Plain Markdown — **no** YAML frontmatter, no `!` blocks, no `$CLAUDE_SKILL_DIR`
- Under **32 KiB** (Codex truncates at default limit)
- Derive commands from `Makefile`, `package.json`, or `README.md` — real commands, not placeholders
- Sections: repo description, working agreements, repository expectations, key files, off-limits

## Step 4 — Phase 1: thin adapters

**CLAUDE.md**

- Line 1: `@AGENTS.md` (preferred over symlinks on Windows)
- Claude-only addenda under ~30 lines — no duplicated policy from AGENTS.md

**`.cursor/rules/000-project.mdc`**

```yaml
---
description: "Project-wide conventions — AGENTS.md is canonical"
alwaysApply: true
---
```

Body: one paragraph pointing to `AGENTS.md` as source of truth; no full policy copy.

**Claude plugin repos only** — if gaps exist, also repair `.claude-plugin/plugin.json`, `hooks/hooks.json` per `platform-specs.md`. Skip marketplace.json unless repo is a marketplace.

## Hard rules

- Never duplicate full AGENTS.md policy into CLAUDE.md or `.mdc` files
- `.cursor/rules/` files **must** use `.mdc` — `.md` is silently ignored
- Derive descriptions from actual README — no placeholder text
- Do not commit from review/plan modes; dev mode commits per SKILL.md

After phases 0–1, continue multi-agent-repo dev mode at Phase 2 locally.


## Phase 1b — Codex project config (when MCP documented)

Create `.codex/config.toml` stub with `project_doc_max_bytes = 32768` and a comment pointing to `.codex-plugin/plugin.json` MCP wiring.

## Phase 1c — Gemini CLI extension (when gemini_cli is a declared target)

Write `gemini-extension.json` reusing the canonical `skills/` tree — never a copy. Set
`contextFileName` to a file that exists. Add MCP and hooks fields only for payloads the
repo actually ships. Keep it dependency-free: declarative extension content needs no Node
toolchain. Record `gemini extensions validate .` output, or record explicitly that the CLI
was unavailable — an unrun validation is `"validated_against": "unknown"`, not a guess.

## Phase 1d — OpenCode config (when opencode is a declared target)

Write `opencode.json` with `skills.paths` pointing at the canonical tree, plus `mcp` when
MCP ships. Generate `.opencode/agent/` from the canonical agent definitions and add the
drift check — never hand-copy an agent file. Do not expect `hooks.json`, a marketplace, or
a statusline; the registry records all three as unavailable, and guards move into the
skills and CI instead.

## Phase 3b — App skill bridge

Create `.agents/skills/` as canonical. Sync or symlink `.claude/skills/` to match. Document bridge in `AGENTS.md` if paths differ.

## Phase 5a — Capability registry (do this before platform targets)

Write `core/capabilities/schema.json` and `core/capabilities/platforms.json` from
`_contract/templates/core/capabilities/*.tmpl`. This is the **only** place the repo states
what each target can do; every other file derives from it. Give every target an explicit
status for every capability key — `unknown` where unverified, never an omission, and never
a `native` claim without a validation command.

## Phase 5b — Platform targets

Write `docs/engineering/build-and-release/platform-targets.json` with `supported_targets`
equal to the registry's platforms minus runtime surfaces, then run
`make platform-targets-sync-capabilities` to generate the derived `capabilities` /
`capability_gaps` mirror — do not type those fields by hand. Sync README Row 3 badges (one
per validated target; a target still at `"validated_against": "unknown"` gets no badge
yet). Agent runs `make platform-targets-sync` before `make agent-polish-gate`.

## Phase 4 — Makefile targets

Copy `makefile-agent-targets.mk.tmpl` into the target `Makefile` (or merge targets). Agents use `make agent:check` and `make agent-polish-gate` only.
