---
name: repo-review
description: 'Internal read-only repository health audit invoked by repo-polish (Step 6a or optional early pass). Scans the repo at $PROJECT_DIR for: directory violations (overfull/sparse/empty), misplaced files (wrong docs/ subdirectory), unclear file names, redundant/stale files (deleted-agent refs, old LangGraph patterns, dead scripts), over-commented shell scripts, dev-env consistency gaps (stale SKILL.md dates, copilot-instructions count drift), and pipeline reorganisation proposals. Produces docs/repo-review-<date>.md — never edits other files. repo-polish reads the report and applies all P1 findings.'
when_to_use: Invoked automatically by repo-polish Step 6a after scaffolding completes (or as an early optional pass after Step 1 for large/messy repos). May also run when another skill explicitly delegates a full repository health audit.
argument-hint: '[project directory path — defaults to repo root]'
arguments: []
disable-model-invocation: true
user-invocable: false
allowed-tools:
- Bash
- Read
- Write
- Glob
- Grep
disallowed-tools: []
model: claude-sonnet-4-6
effort: low
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
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
  updated-date: '2026-06-16'
---

# repo-review

A **read-only** repository audit that mechanically scans every corner of the codebase and produces a prioritised findings report. The skill never edits files — its only output is `docs/repo-review-${DATE}.md`. **`repo-polish` reads the report and applies P1 fixes.**

## How repo-polish calls this skill

`repo-polish` sets `PROJECT_DIR` to the repo root before invoking `Skill("repo-review")`. Use it as `ROOT` throughout:

```bash
ROOT="${PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
SKILL_DIR="$CLAUDE_SKILL_DIR"   # resolves to this skill's directory at runtime
```

| repo-polish step | Action |
|------------------|--------|
| **Step 6a** — after Step 5 scaffolding | Full audit of `$PROJECT_DIR`; write report under `$PROJECT_DIR/docs/` |
| **Optional** — after Step 1 survey | Early pass if repo is large or visibly messy before planning |

Tag every finding P1/P2/P3. **`repo-polish` must fix all P1 items** before Step 7 — return the report with a clear P1 summary at the top.

## Why this skill exists

Repos accumulate clutter: dirs with one file, scripts nobody calls, docs that still say "LangGraph", ticket-specific filenames committed in the wrong place. A manual sweep takes hours and still misses things. This skill runs the sweep mechanically — bash scripts handle discovery, you handle interpretation and writing — and produces a single doc the team can act on.

## Workflow (follow in order, do not skip sections)

### Step 1 — Run discovery scripts

Run all three helper scripts and capture output. Run them in parallel — each is independent:

```bash
ROOT="${PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
SKILL_DIR="$CLAUDE_SKILL_DIR"

bash "$SKILL_DIR/scripts/check-dir-sizes.sh"        "$ROOT" 2>&1
bash "$SKILL_DIR/scripts/check-stale-refs.sh"       "$ROOT" 2>&1
bash "$SKILL_DIR/scripts/check-comment-density.sh"  "$ROOT" 2>&1
```

Also run these inline commands (fast, cover gaps the scripts miss):

```bash
# Governance violations: top-level docs/*.md outside docs/README.md
find "$ROOT/docs" -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null

# Generic / single-word script names
find "$ROOT/plugin/scripts" "$ROOT/tooling" -name '*.sh' 2>/dev/null \
  | grep -E '/(utils|helpers|common|fix|script|temp|new-|old-)' || true

# Ticket-named files committed outside docs/engineering/
find "$ROOT" -name 'sched-*.md' -o -name '*-investigation-*.md' \
  -o -name '*-2026-*.md' 2>/dev/null \
  | grep -v '.git' | grep -v 'known-regressions-archive' || true

# Markdown files with HTML comment blocks (stale scaffolding)
grep -rl '<!--' "$ROOT/docs" "$ROOT/plugin" "$ROOT/.claude" 2>/dev/null || true

# Potentially dead scripts (≤1 reference across the entire repo)
for f in $(find "$ROOT/plugin/scripts" -name '*.sh' 2>/dev/null | head -40); do
  name=$(basename "$f")
  count=$(grep -rl "$name" "$ROOT" --include='*.md' --include='*.sh' --include='*.json' \
    --exclude-dir='.git' --exclude-dir='dist' 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -le 1 ] && echo "UNREFERENCED: $f"
done

# Pipeline script count (for Section 7)
ls "$ROOT/plugin/scripts/pipeline/"*.sh 2>/dev/null | wc -l
```

### Step 2 — Classify findings before writing

Before opening the report file, reason through each category:
- **P1**: breaks CI or governance today (overfull unlisted dir, empty committed dir, ticket file in root)
- **P2**: real quality debt — fix in next PR (allowlisted-but-bloated dir, stale SKILL.md dates, generic script names)
- **P3**: nice-to-have, low risk (sparse single-file dirs, old comment blocks)

Do not write the report until you have findings across all 7 sections. Even if a section is clean, note it explicitly — a blank section looks like a missed scan.

### Step 3 — Write the report

Write to `$ROOT/docs/repo-review-$(date +%Y-%m-%d).md`.

Read `$CLAUDE_SKILL_DIR/references/report-template.md` and fill every section. Each finding entry must include:
- **Path** — exact relative path from repo root
- **Reason** — one sentence stating why it's flagged
- **Action** — concrete recommended action with P1/P2/P3 tag

## The seven audit sections

### 1. Directory Violations

Source: `check-dir-sizes.sh` output.

| Class | Threshold | Priority |
|-------|-----------|----------|
| **Overfull** | >10 files, NOT in CI allowlist | P1 — CI blocks new additions |
| **Allowlisted-but-bloated** | In allowlist AND >20 files | P2 — tracked cleanup debt |
| **Sparse** | ≤1 file AND no subdirectories | P3 — single-file dirs add nav overhead |
| **Empty** | 0 files, 0 subdirs | P1 — git won't track; usually needs .gitkeep or removal |

### 2. Misplaced Files

Cross-reference paths against `.claude/rules/file-structure-governance.md`.

Known violation patterns:
- `docs/engineering/` containing user-facing how-to guides → should be `docs/user/`
- `docs/user/` containing architecture/internal docs → should be `docs/engineering/`
- `plugin/rules/` containing dev-workflow rules → should be `.claude/rules/`
- Top-level `docs/*.md` other than `docs/README.md`
- Ticket-named files (`sched-*.md`, `*-2026-*.md`) anywhere except `docs/engineering/` or untracked

### 3. Unclear File Names

Flag names that don't communicate purpose at a glance:
- Generic single-word script names: `utils.sh`, `helpers.sh`, `common.sh`, `fix.sh`
- Config names without qualifier: `config.json` (fine as `plugin.config.json`)
- Temp-looking names: `temp-*`, `new-*`, `old-*`, `backup-*`
- Ticket-id names committed as permanent files: `sched-47012-something.md`

For each: suggest a clearer name.

### 4. Redundant / Stale Files

Source: `check-stale-refs.sh` output + inline grep.

#### 4a. False-positive prevention for agent files — DECISION TREE

Agent `.md` files always contain their own name. Never flag `plugin/agents/pm-*.md` as stale based on grep hits alone. Use this decision tree:

```
Q1: Did `git log --diff-filter=D` show this agent's .md was git-rm'd?
  NO  → Not deleted. Do not flag. STOP.
  YES → continue

Q2: Does the agent file still exist on disk right now?
  YES → Was restored. Do not flag. STOP.
  NO  → continue

Q3: Is the agent name still referenced in plugin/skills/investigate/SKILL.md?
  YES → Still active via the investigate skill. Do not flag. STOP.
  NO  → continue

Q4: Is the agent name still referenced in plugin/pipeline/steps.json?
  YES → Still dispatched. Do not flag. STOP.
  NO  → Agent is truly deleted → FLAG as stale reference
```

Every finding in Section 4a must include the output of the Step-1 git command and one of the Step-3/4 grep commands as evidence. A finding without both commands' output is not valid.

#### 4b. Old architecture references

Files (other than agent `.md` files) mentioning `LangGraph`, `src/agents/`, `platforms/claude/agents/`, or `plugin/commands/` as an active directory. `known-regressions-archive.md` is exempt from all stale-ref checks.

#### 4c. Stale investigation reports

`docs/engineering/*-investigation-*.md` or `docs/engineering/*-2026-*.md` files that predate the linear-pipeline refactor. Check creation date with `git log --follow --diff-filter=A -- <file>`.

#### 4d. Potentially dead scripts

Scripts with ≤1 reference across the whole repo (from the inline dead-code grep). Before flagging:
1. Check for indirect invocation: does any script iterate over a list of scripts by glob or variable? (`grep -n "for.*\.sh\|scripts/\*" "$ROOT/plugin/skills/investigate/SKILL.md"`)
2. Check that the script isn't sourced: `grep -rn "source.*$(basename $f)\|\..*$(basename $f)" "$ROOT"`

If either check hits → not dead; skip it.

### 5. Over-commented Files

Source: `check-comment-density.sh` output.

- Shell scripts >40% comment lines → suggest pruning obvious boilerplate comments
- Markdown files with `<!-- ... -->` blocks → stale scaffolding or template placeholders; recommend removing

### 6. Dev Env Consistency Gaps

Run these checks:

```bash
# SKILL.md files with updated-date older than 60 days
# Cross-platform date arithmetic (macOS + Linux safe)
for f in $(find "$ROOT/.claude/skills" "$ROOT/plugin/skills" -name 'SKILL.md' 2>/dev/null); do
  date_str=$(grep 'updated-date:' "$f" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
  [ -z "$date_str" ] && continue
  then_epoch=$(date -j -f '%Y-%m-%d' "$date_str" '+%s' 2>/dev/null || date -d "$date_str" '+%s' 2>/dev/null)
  now_epoch=$(date '+%s')
  [ -z "$then_epoch" ] && continue
  age=$(( (now_epoch - then_epoch) / 86400 ))
  [ "$age" -gt 60 ] && echo "$f: $date_str ($age days old)"
done

# Rules referencing old patterns
grep -rl 'plugin/commands\|src/agents\|platforms/claude' "$ROOT/.claude/rules/" 2>/dev/null || true

# copilot-instructions.md agent count drift
actual_agents=$(ls "$ROOT/plugin/agents/pm-"*.md 2>/dev/null | wc -l | tr -d ' ')
claimed_agents=$(grep -oE '[0-9]+(?= agent)' "$ROOT/.github/copilot-instructions.md" 2>/dev/null | head -1)
[ -n "$claimed_agents" ] && [ "$actual_agents" != "$claimed_agents" ] \
  && echo "copilot-instructions.md: claims $claimed_agents agents, actual: $actual_agents"
```

Flag: stale `updated-date` (>60 days AND related files changed since), docs describing the old TypeScript/LangGraph architecture, copilot-instructions.md count drift.

### 7. Pipeline Scripts Reorganisation Proposal

**Proposal only — no files are moved.**

List all `plugin/scripts/pipeline/*.sh` and assign each to a proposed sub-directory:

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
| `utils/` | sanitize-json, truncate-logs, iso-to-epoch, build-grafana-url, normalize-*, md-to-html, parse-run-request |

Count files per group. List any that don't fit a group. Note: implementing this reorganisation requires updating all path references in `plugin/skills/investigate/SKILL.md` and agent files — it's a follow-up PR, not done here.

## Hard rules

- **Read-only.** The only file this skill creates is the report. Never edit, move, or delete anything else.
- **Report first.** Write the full report before surfacing any fix suggestions. The report is the deliverable.
- **Use scripts, not manual enumeration.** Never list files by typing them out — always use `find`, `grep`, `wc`, or `git log`.
- **Never skip a section.** If a section has no findings, write "No issues found." — a blank section looks like an error.
- **Exempt known-historical files.** `known-regressions-archive.md` intentionally references deleted agents. Never flag it for stale refs.
- **Never flag `plugin/agents/pm-*.md` as stale on grep alone.** Follow the Section 4a decision tree. Both verification commands must appear in the finding as evidence.
- **Verify before recommending deletion.** A finding without the verification command output is not valid — it's a guess.
- **Cross-platform date commands.** Always try macOS `date -j -f` first, then fall back to GNU `date -d`. Never assume only one is available.

## References

- `scripts/check-dir-sizes.sh` — directory file-count scan (overfull, allowlisted-bloated, sparse, empty)
- `scripts/check-stale-refs.sh` — grep for deleted agents + old architecture patterns (uses git history, not hardcoded list)
- `scripts/check-comment-density.sh` — comment-density scan for shell scripts (configurable threshold via `$THRESHOLD`)
- `references/report-template.md` — exact report structure to fill in; read it before writing the report
