---
name: repo-review
disable-model-invocation: true
user-invocable: false
description: "Internal: read-only repository health audit — misplaced files, stale refs, directory violations, over-commented scripts, dev-env gaps. Invoked by repo-polish during Step 6a. Produces docs/repo-review-<date>.md; repo-polish applies P1 fixes. Not for direct user invocation — run repo-polish instead."
when_to_use: "Invoked automatically by repo-polish Step 6a after scaffolding (or early after Step 1 for large repos). May also run standalone only when another skill explicitly delegates a repo audit."
model: claude-sonnet-4-6
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
metadata:
  capability: repository-audit
  provider: developer-workflow
  agents:
    - repo-review
  platforms:
    - claude
  tags:
    - audit
    - cleanup
    - repo-health
    - misplaced-files
    - stale-refs
    - pipeline-reorg
  updated-date: "2026-06-13"
---

# repo-review

A **read-only** repository audit that scans every corner of the codebase and produces a prioritised findings report. The skill never edits files — its only output is `docs/repo-review-${DATE}.md`. **`repo-polish` reads the report and applies P1 fixes.**

## When repo-polish invokes this skill

| repo-polish step | Action |
|------------------|--------|
| **Step 6a** — after Step 5 scaffolding | Full audit of `$PROJECT_DIR`; write report under `$PROJECT_DIR/docs/` |
| **Optional** — after Step 1 survey | Early pass if repo is large or visibly messy before planning |

`repo-polish` sets `cd "$PROJECT_DIR"` before calling `Skill("repo-review")`. Use `$PROJECT_DIR` as `ROOT` for all discovery scripts:

```bash
ROOT="$PROJECT_DIR"
bash "$CLAUDE_SKILL_DIR/scripts/check-dir-sizes.sh" "$ROOT"
bash "$CLAUDE_SKILL_DIR/scripts/check-stale-refs.sh" "$ROOT"
bash "$CLAUDE_SKILL_DIR/scripts/check-comment-density.sh" "$ROOT"
```

Tag every finding P1/P2/P3. **`repo-polish` must fix all P1 items** before Step 7 — return the report with a clear P1 summary at the top.

## Why this skill exists

Repos accumulate clutter: dirs with one file, scripts nobody calls, docs that still say "LangGraph", ticket-specific filenames committed in the wrong place. A manual sweep takes hours and still misses things. This skill runs the sweep mechanically — bash scripts handle discovery, you handle interpretation and writing — and produces a single doc the team can act on.

## Workflow (follow this order)

### Step 1 — Run discovery scripts

Run all three helper scripts from the repo root. Capture their output; you'll reference it throughout:

```bash
ROOT="$(git rev-parse --show-toplevel)"
bash "$ROOT/.claude/skills/repo-review/scripts/check-dir-sizes.sh"    "$ROOT" 2>&1
bash "$ROOT/.claude/skills/repo-review/scripts/check-stale-refs.sh"   "$ROOT" 2>&1
bash "$ROOT/.claude/skills/repo-review/scripts/check-comment-density.sh" "$ROOT" 2>&1
```

Also run these inline commands — they're fast and cover gaps the scripts don't:

```bash
# Top-level docs/*.md outside docs/README.md (governance violation)
find docs -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null

# Single-word / generic filenames in scripts
find plugin/scripts tooling -name '*.sh' 2>/dev/null \
  | grep -E '/(utils|helpers|common|fix|script|temp|new-|old-)' || true

# Ticket-named files committed outside docs/engineering/
find . -name 'sched-*.md' -o -name '*-investigation-*.md' \
  -o -name '*-2026-*.md' 2>/dev/null \
  | grep -v '.git' | grep -v 'known-regressions-archive' || true

# Markdown files with HTML comment blocks
grep -rl '<!--' docs plugin/agents plugin/skills .claude 2>/dev/null || true

# Files that look like they might be dead (not referenced elsewhere)
for f in $(find plugin/scripts -name '*.sh' 2>/dev/null | head -40); do
  name=$(basename "$f")
  count=$(grep -rl "$name" . --include='*.md' --include='*.sh' --include='*.json' \
    --exclude-dir='.git' --exclude-dir='dist' 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -le 1 ] && echo "UNREFERENCED: $f"
done

# Pipeline scripts by proposed group (for reorg proposal)
ls plugin/scripts/pipeline/*.sh 2>/dev/null | wc -l
```

### Step 2 — Interpret findings

Before writing the report, reason briefly about each category:
- Which violations are P1 (break CI or governance today)?
- Which are P2 (real quality debt, fix next PR)?
- Which are P3 (nice-to-have, low risk)?

Don't write the report until you have findings across all 7 sections — even if a section is "none found."

### Step 3 — Write the report

Write to `docs/repo-review-$(date +%Y-%m-%d).md`. Use the template in `references/report-template.md`. Fill every section; mark empty sections explicitly as "No issues found."

Each finding entry must include:
- **Path** — exact relative file or directory path
- **Reason** — one sentence explaining why it's flagged
- **Action** — concrete recommended action (P1/P2/P3 tagged)

## The seven audit sections

### 1. Directory Violations
Sources: `check-dir-sizes.sh` output.

Flag three classes:
- **Overfull** — >10 files, NOT in `tooling/ci/validate-dir-file-count.sh` allowlist → P1 (CI blocks new additions)
- **Allowlisted-but-still-bloated** — in allowlist but >20 files → P2 (tracked cleanup debt)
- **Sparse** — ≤1 file AND no subdirectories → P3 (single-file dirs add nav overhead; consider merging)
- **Empty** — 0 files, 0 subdirs → P1 (git won't track them; usually .gitkeep candidate or stale dir)

### 2. Misplaced Files
Cross-reference paths against `.claude/rules/file-structure-governance.md` canonical table.

Known violation patterns to check:
- `docs/engineering/` containing user-facing how-to guides (should be `docs/user/`)
- `docs/user/` containing architecture/internal docs (should be `docs/engineering/`)
- `plugin/rules/` containing dev-workflow rules (should be `.claude/rules/`)
- Top-level `docs/*.md` that isn't `docs/README.md`
- Ticket-named files (`sched-*.md`, `*-2026-*.md`) anywhere except `docs/engineering/` or untracked

### 3. Unclear File Names
Flag names that don't communicate purpose at a glance:

- Generic single-word script names: `utils.sh`, `helpers.sh`, `common.sh`, `fix.sh`, `script.sh`
- Generic config names with no qualifier: `config.json` (fine as `plugin.config.json`; not fine alone)
- Temporary-looking names: `temp-*`, `new-*`, `old-*`, `backup-*`
- Ticket-id names committed as permanent files: `sched-47012-something.md`

For each: suggest a clearer name.

### 4. Redundant / Stale Files
Sources: `check-stale-refs.sh` output + inline grep above.

> **CRITICAL verification rule for agents:** `plugin/agents/pm-*.md` files reference their own agent names — they will ALWAYS appear in a grep for their own name. NEVER flag a `plugin/agents/` file as stale based on grep output alone. Agent files must be verified through a different path (see below).

**4a. Truly deleted agents** — agents whose .md file was git-rm'd AND are no longer dispatched:

```bash
# Step 1: find agents whose .md file was actually deleted from git
git log --diff-filter=D --name-only -- 'plugin/agents/pm-*.md' | grep 'pm-' | sort -u

# Step 2: for each candidate name, verify it is NOT still active
grep -n '<agent-name>' plugin/skills/investigate/SKILL.md plugin/pipeline/steps.json 2>/dev/null
```

Only flag an agent as deleted if BOTH are true: (a) `git log --diff-filter=D` shows its .md was removed, AND (b) it is NOT referenced in `investigate/SKILL.md` or `steps.json`. If step 2 finds a reference, the agent is still active — do not flag it.

**4b. Old architecture references** — files (other than agent .md files) mentioning `LangGraph`, `src/agents/`, `platforms/claude/agents/`, `plugin/commands/` as an active directory. Known-regressions-archive.md is exempt.

**4c. Stale investigation reports** — `docs/engineering/*-investigation-*.md` or `docs/engineering/*-2026-*.md` that predate the linear-pipeline refactor (check `git log` date)

**4d. Potentially dead scripts** — scripts with ≤1 reference across the whole repo (from the inline dead-code grep); flag for human confirmation before deletion. Before flagging: verify the script is not invoked indirectly via a variable or via a list of scripts (e.g., `validate-install/SKILL.md` lists scripts by name in a loop).

### 5. Over-commented Files
Source: `check-comment-density.sh` output.

- Shell scripts >40% comment lines → suggest pruning obvious boilerplate comments
- Markdown files with `<!-- HTML comment -->` blocks → these are usually stale scaffolding or template placeholders; recommend removing

### 6. Dev Env Consistency Gaps
Run these checks manually:

```bash
# SKILL.md files with updated-date > 60 days ago
for f in $(find .claude/skills plugin/skills -name 'SKILL.md' 2>/dev/null); do
  date_str=$(grep 'updated-date:' "$f" 2>/dev/null | grep -oP '\d{4}-\d{2}-\d{2}' | head -1)
  [ -z "$date_str" ] && continue
  age=$(( ( $(date +%s) - $(date -j -f '%Y-%m-%d' "$date_str" +%s 2>/dev/null || \
            date -d "$date_str" +%s 2>/dev/null) ) / 86400 ))
  [ "$age" -gt 60 ] && echo "$f: $date_str ($age days)"
done

# .claude/rules/ files still referencing old patterns
grep -rl 'plugin/commands\|src/agents\|platforms/claude' .claude/rules/ 2>/dev/null || true

# copilot-instructions.md count check
actual_agents=$(ls plugin/agents/pm-*.md 2>/dev/null | wc -l | tr -d ' ')
claimed_agents=$(grep -oP '\d+(?= agent)' .github/copilot-instructions.md 2>/dev/null | head -1)
[ "$actual_agents" != "$claimed_agents" ] && echo "copilot-instructions.md: claims $claimed_agents agents, actual $actual_agents"
```

Flag: stale `updated-date`, docs describing the old TypeScript/LangGraph architecture, copilot-instructions.md count drift.

### 7. Pipeline Scripts Reorganization Proposal
This section is always a **proposal only** — no files are moved.

List all `plugin/scripts/pipeline/*.sh` files and assign each to a proposed sub-directory using this grouping:

| Group | Pattern |
|-------|---------|
| `core/` | setup, config, mcp-probe, trace, now-iso |
| `dispatch/` | dispatch-*, with-flock, with-time-budget |
| `steps/` | write-step, finalize-step, finalize, finalize-report, with-step |
| `evidence/` | gather-evidence-*, collect-evidence, build-evidence-*, plan-gather, extract-* |
| `validate/` | validate-* |
| `quality/` | quality-gate, should-publish-report, score-*, classify-*, route-*, emit-*, checklist-* |
| `state/` | reconcile-state, state-get, cost-summary, synthesize-step-*, aggregate-* |
| `rescue/` | rescue-* |
| `utils/` | sanitize-json, truncate-logs, iso-to-epoch, build-grafana-url, build-platform-fact, normalize-*, md-to-html, log-priority-sql, funnel, parse-run-request |

Count files per group. List any that don't fit. Note: implementing this reorganization requires updating all path references in `plugin/skills/investigate/SKILL.md` and agent files — it's a follow-up PR, not done here.

## Hard rules

- **Read-only.** The only file this skill creates is the report itself. Never edit, move, or delete anything else.
- **Report first.** Write the full report before suggesting any fixes. The report is the deliverable.
- **Use scripts, not manual enumeration.** Never list files by typing them out — always use `find`, `grep`, `wc`, or `git log`.
- **Never skip a section.** If a section has no findings, write "No issues found." — a blank section looks like an error.
- **Exempt known-historical files.** `known-regressions-archive.md` intentionally references deleted agents. Don't flag it for stale refs.
- **Never flag `plugin/agents/pm-*.md` as stale based on grep alone.** Agent files contain their own names — any grep for "pm-artifact-resolver" WILL match `pm-artifact-resolver.md`. The only valid way to confirm an agent is dead: `git log --diff-filter=D` shows its file was deleted AND it is absent from `investigate/SKILL.md` and `steps.json`.
- **Verify before recommending deletion.** For any file flagged as redundant, the report must include the verification command and its output — not just the assertion. A finding without evidence is a guess.

## References

- `scripts/check-dir-sizes.sh` — directory file-count scan (overfull + sparse)
- `scripts/check-stale-refs.sh` — grep for deleted agents + old architecture patterns
- `scripts/check-comment-density.sh` — comment-density scan for shell scripts
- `references/report-template.md` — exact report structure to fill in
