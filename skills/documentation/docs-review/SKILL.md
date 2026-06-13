---
name: docs-review
disable-model-invocation: true
user-invocable: false
description: "Internal: audit and fix Markdown docs (README.md + docs/**) — visual cleanliness, freshness vs git history, stray plan files, link validation, and cross-reference consistency. Invoked by repo-polish during Step 6b after scaffolding. Not for direct user invocation — run repo-polish instead."
when_to_use: "Invoked automatically by repo-polish Step 6b after docs are scaffolded. May also run standalone only when another skill explicitly delegates a docs sweep."
argument-hint: "[optional: subset glob like 'docs/user/**' or single file path]"
model: claude-sonnet-4-6
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
metadata:
  capability: documentation-quality
  provider: developer-workflow
  agents:
    - docs-review
  platforms:
    - claude
  tags:
    - documentation
    - audit
    - links
    - freshness
    - cleanup
    - workflow
  updated-date: "2026-06-13"
---

# docs-review

A documentation-quality sweep: every Markdown file under `README.md` (root) and
`docs/**` is audited against eight axes, then fixed in place. The goal is to
finish a sweep with a clean working tree, zero broken links, no stray plan
files in git, and every doc reflecting the current state of the codebase —
including accurate counts of agents, skills, and commands.

## When repo-polish invokes this skill

| repo-polish step | Action |
|------------------|--------|
| **Step 6b** — after Step 5 scaffolding and Step 6a P1 repo fixes | Full audit of `$PROJECT_DIR/README.md` and `$PROJECT_DIR/docs/**` |
| **Re-run** — after manual P1 doc fixes in 6b | Confirm link-clean and counts accurate |

`repo-polish` sets `cd "$PROJECT_DIR"` before calling `Skill("docs-review")`. Treat that directory as the repo root for all axes — not the plugin install path.

When invoked from `repo-polish`, report pass/fail summary at the end. Return control only when P1 doc issues are fixed or explicitly listed for repo-polish to handle.

## Why this skill exists

Docs drift faster than code. A sweep that's "by hand" misses files,
mis-classifies plan dumps as canonical reference material, and leaves behind
stale agent/skill counts. This skill codifies the routine so the audit is
exhaustive and its judgement calls are explicit.

## Scope

**Full audit (all 8 axes):** `README.md` (repo root), every `*.md` under `docs/`.

**Consistency-check only (Axes 0 + 6):**
- `CLAUDE.md` — verify agent/skill counts match filesystem; update stale claims
- `.github/copilot-instructions.md` — verify architecture description, counts, commands
- `docs/engineering/reference/agent-quick-ref.md` — verify every `plugin/agents/pm-*.md` has an entry

**Out of scope:** `plugin/skills/**/*.md`, `plugin/agents/*.md`, `.claude/rules/*.md` — those have their own validators (`validate-skills.sh`, `validate-agents.sh`).

If the user passes a path argument, restrict the per-file audit to that subset (still run Axis 0 first).

## Axis 0 — Repo State Inventory (ALWAYS FIRST)

**Run before any per-file work.** Generates ground truth used by Axes 6 and 7.

```bash
AGENT_COUNT=$(ls plugin/agents/pm-*.md 2>/dev/null | wc -l | tr -d ' ')
PLUGIN_SKILL_COUNT=$(ls -d plugin/skills/*/ 2>/dev/null | wc -l | tr -d ' ')
DEV_SKILL_COUNT=$(ls -d .claude/skills/*/ 2>/dev/null | wc -l | tr -d ' ')
HOOK_COUNT=$(jq '.hooks | length' plugin/hooks/hooks.json 2>/dev/null || echo "?")
CLAUDE_AGENT_CLAIM=$(grep -oP '\d+(?= sub-agent)' CLAUDE.md | head -1)
CLAUDE_SKILL_CLAIM=$(grep -oP '\d+(?= MCP skill)' CLAUDE.md | head -1)
```

Print an inventory table:
```
=== Axis 0 — Repo State Inventory ===
agents:        20  (CLAUDE.md claims: 20) ✓
plugin skills: 32  (CLAUDE.md claims: 29) ✗ → NEEDS UPDATE
dev skills:    11
hooks:         13
```

If counts differ, run the regen script to update CLAUDE.md automatically:
```bash
bash tooling/ci/regen-claude-md.sh
```

Then generate the per-file manifest:
```bash
{ find . -maxdepth 1 -name 'README.md'; find docs -name '*.md' -type f 2>/dev/null; } | sort > /tmp/review-docs-manifest.txt
TOTAL=$(wc -l < /tmp/review-docs-manifest.txt)
echo "=== $TOTAL files queued for audit ==="
```

## The five doc audit axes

The skill walks each in-scope file once and applies all five checks. Fixes are
applied in-place. Findings are appended to `docs/review-${DATE}.md`.

### Axis 1 — Visual cleanliness

Goal: a reader scanning the doc isn't tripped by formatting noise.

What to fix:
- Stray trailing whitespace, mixed tabs/spaces, inconsistent heading levels.
- Code fences without language hints (` ``` ` instead of ` ```bash `).
- Tables with mismatched column counts.
- Long lines inside paragraphs (soft 100 chars; hard cap 200).
- Bullets: pick `-` consistently (avoid mixing `-`, `*`, `+` within one file).

What to leave alone:
- Deliberate ASCII diagrams. Code blocks of legitimately long single-line commands.

### Axis 2 — Freshness vs git history

Goal: every doc reflects the current state of the codebase.

```bash
bash .claude/skills/review-docs/scripts/file-freshness.sh <FILE>
```

Prints `last_doc_update`, `repo_changes_since`, and `verdict` (`fresh` / `review` / `stale`).

When verdict is `stale`: read the listed downstream changes and update the doc.
Common fixes: rename broken links, remove references to deleted scripts/agents,
update counts. Do NOT rewrite wholesale — fix only what drifted.

### Axis 3 — Stray plan / work files

Goal: `docs/` is canonical reference material, not a dumping ground.

```bash
bash .claude/skills/review-docs/scripts/detect-plan-files.sh
```

Signals: filename has `-plan`, `-research`, `-analysis`, `-review`, or ticket id;
located directly under `docs/` and not linked from any README; last commit says
"wip" or "from claude session".

For each confirmed one-off: `git rm --cached <file>` and add pattern to `.gitignore`.

Orphan check:
```bash
python3 tooling/check-doc-orphans.py
```

### Axis 4 — Template / standard conformance

Goal: every doc complies with `.claude/rules/documentation-standards.md`.

```bash
bash .claude/skills/review-docs/scripts/check-template.sh <FILE>
```

Reports: audience path match, `docs/user/**` footer presence, Mermaid violations
(no `classDef`, `class`, `style`, `fill:`), has-purpose-sentence.

### Axis 5 — Link / cross-reference / diagram validity

Goal: every link resolves; every Mermaid diagram parses.

```bash
bash .claude/skills/review-docs/scripts/validate-links.sh <FILE>
```

Reports: broken relative links (with line number), missing heading anchors,
unparseable Mermaid blocks, raw-file-path link text.

External `https://` URLs are sampled but not blocked on (`--skip-external` accepted).

## Axis 6 — CLAUDE.md + Copilot Consistency Check

After Axis 0, verify the consistency-check-only files:

1. **CLAUDE.md** — run `bash tooling/ci/regen-claude-md.sh --dry-run` and show diff. Update if any count or table drifted.
2. **`.github/copilot-instructions.md`** — READ the file and check:
   - Agent count matches `$AGENT_COUNT`
   - Skill count matches `$PLUGIN_SKILL_COUNT`
   - Investigation style: "linear pipeline" not "hypothesis-driven loop"
   - No references to `src/`, `dev-env/`, `platforms/` (not active directories)
   - Commands list reflects skills-based approach; no `plugin/commands/` references
   - Agent registration: "1 file: `plugin/agents/pm-name.md`" not "4 registrations in src/"
   - Apply fixes in-place for any stale content found
3. **`docs/engineering/reference/agent-quick-ref.md`** — verify every `plugin/agents/pm-*.md` has an entry; flag missing ones for the user to fill.

## Axis 7 — Recent Changes Sync

Flag docs that reference entities deleted in the last 45 days:

```bash
git log --since=45.days.ago --oneline --name-only | grep -v '^[a-f0-9]' | sort -u
```

Specifically flag docs that still mention:
- Deleted agents: `pm-step-runner`, `pm-skeptic`, `pm-verifier`, `pm-hypothesis-specificity-check`, `pm-evidence-synthesizer`, `pm-artifact-resolver`, `pm-html-generator`
- `plugin/commands/` (deleted — migrated to skills)
- Agent/skill counts that no longer match the Axis 0 inventory

For each flagged doc: READ it, remove or update the stale references.

## End-to-end sweep procedure

1. **Axis 0** — generate inventory + manifest; update CLAUDE.md if counts differ.
2. **Axis 6** — check consistency-check-only files; fix in-place.
3. **Axis 7** — scan recent changes; flag stale doc references.
4. **Per-file audit** — for each file in `/tmp/review-docs-manifest.txt`:
   - READ the file (required — no skipping based on git alone)
   - Run Axes 1–5; apply fixes in-place
   - Print `[✓] path/to/file.md — N fixes applied` or `[·] path/to/file.md — clean`
5. **Untrack plan files** — for Axis 3 hits confirmed by the user.
6. **Run validators**:
   ```bash
   python3 tooling/check-doc-orphans.py
   bash tooling/ci/validate-skills.sh plugin/skills
   bash tests/unit/skills/footer-center-aligned.sh
   ```
7. **Render review report** — fill `templates/review-report.md.tmpl`; save to `docs/review-${DATE}.md`.
8. **Final summary** — print: `Reviewed X/N files. Y fixes applied. Z files untracked.`

## Hard rules (do NOT break these)

- **Never mark a file as reviewed without reading it.** `[✓]` requires: file read + all 5 axes checked. Scanning git log is not a substitute.
- **Axis 0 MUST run before any per-file audit.** Never skip it, even on partial sweeps.
- **Never delete a doc the user has not confirmed.** Untrack first, retain working-tree copy.
- **Never rewrite a whole doc wholesale.** Fix only the drifted parts.
- **Never invent links.** If a target doesn't exist, remove the link or flag for the user.
- **Never paraphrase command names, file paths, or agent names.** Use canonical forms from `CLAUDE.md`.
- **Plan files are not always trash.** The detector flags candidates; the human confirms.

## References

- **[`scripts/file-freshness.sh`](scripts/file-freshness.sh)** — git-history-driven freshness verdict.
- **[`scripts/detect-plan-files.sh`](scripts/detect-plan-files.sh)** — stray plan/work file detector.
- **[`scripts/check-template.sh`](scripts/check-template.sh)** — audience/footer/Mermaid/purpose checks.
- **[`scripts/validate-links.sh`](scripts/validate-links.sh)** — relative-link, anchor, Mermaid, link-text checks.
- **[`templates/review-report.md.tmpl`](templates/review-report.md.tmpl)** — canonical report shape.
- **[`references/sweep-checklist.md`](references/sweep-checklist.md)** — quick-reference checklist.
- **[`references/known-canonical-plans.md`](references/known-canonical-plans.md)** — plan-shaped filenames that must NOT be untracked.
- **[`evals/evals.json`](evals/evals.json)** — pinned behaviors: orphan detection, freshness verdict, footer compliance, link validity.

## Existing repo validators this skill defers to

- `tooling/check-doc-orphans.py` — orphan detection for `docs/user/` and `docs/engineering/`.
- `tests/unit/skills/footer-center-aligned.sh` — footer block conformance.
- `.claude/rules/documentation-standards.md` — the rule the skill enforces.
- `tooling/ci/regen-claude-md.sh` / `regen-testing-md.sh` — auto-regenerated counts.

This skill orchestrates them; it does NOT re-implement them.
