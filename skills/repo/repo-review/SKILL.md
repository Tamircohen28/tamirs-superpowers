---
name: repo-review
disable-model-invocation: true
user-invocable: false
description: "Internal: repo health audit used by repo-polish. Scans for misplaced files, overfull dirs, unclear names, dead scripts, and over-commented shell files. Outputs a prioritised findings report. Not for direct user invocation — run repo-polish instead."
model: claude-sonnet-4-6
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
metadata:
  capability: repository-audit
  tags:
    - audit
    - cleanup
    - repo-health
    - misplaced-files
    - stale-refs
  updated-date: "2026-06-13"
---

# repo-review

A **read-only** repository audit that scans every corner of the codebase and produces a prioritised findings report. The skill never edits files — its only output is `docs/repo-review-${DATE}.md`.

## Why this skill exists

Repos accumulate clutter: dirs with one file, scripts nobody calls, docs that still reference old patterns, ticket-specific filenames committed in the wrong place. A manual sweep takes hours and still misses things. This skill runs the sweep mechanically and produces a single doc the team can act on.

## Workflow (follow this order)

### Step 1 — Run discovery scripts

Run the helper scripts from the repo root. Capture their output; you'll reference it throughout:

```bash
ROOT="$(git rev-parse --show-toplevel)"
bash "$CLAUDE_SKILL_DIR/scripts/check-dir-sizes.sh"      "$ROOT" 2>&1
bash "$CLAUDE_SKILL_DIR/scripts/check-comment-density.sh" "$ROOT" 2>&1
```

Also run these inline commands — they're fast and cover gaps the scripts don't:

```bash
# Single-word / generic filenames in scripts directories
find . -name '*.sh' 2>/dev/null \
  | grep -E '/(utils|helpers|common|fix|script|temp|new-|old-)' \
  | grep -v '.git' || true

# Ticket-named files that look like one-off artifacts
find . -name '*.md' 2>/dev/null \
  | grep -iE '[-_](investigation|spike|2[0-9]{3}[-_])' \
  | grep -v '.git' || true

# Markdown files with HTML comment blocks (often stale scaffolding)
grep -rl '<!--' . --include='*.md' 2>/dev/null | grep -v '.git' || true

# Potentially dead scripts (≤1 reference across the repo)
for f in $(find . -name '*.sh' 2>/dev/null | grep -v '.git' | head -60); do
  name=$(basename "$f")
  count=$(grep -rl "$name" . --include='*.md' --include='*.sh' --include='*.json' \
    --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='dist' 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -le 1 ] && echo "UNREFERENCED: $f"
done

# Stale skill updated-dates (>60 days old)
for f in $(find . -name 'SKILL.md' 2>/dev/null | grep -v '.git'); do
  date_str=$(grep 'updated-date:' "$f" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
  [ -z "$date_str" ] && continue
  age=$(( ( $(date +%s) - $(date -d "$date_str" +%s 2>/dev/null || date -j -f '%Y-%m-%d' "$date_str" +%s 2>/dev/null) ) / 86400 ))
  [ "$age" -gt 60 ] && echo "STALE ($age days): $f — updated-date: $date_str"
done
```

### Step 2 — Interpret findings

Before writing the report, reason briefly about each category:
- Which violations are P1 (active quality problem, fix next PR)?
- Which are P2 (real debt, schedule for cleanup)?
- Which are P3 (nice-to-have, low risk)?

Don't write the report until you have findings across all five sections — even if a section is "none found."

### Step 3 — Write the report

Write to `docs/repo-review-$(date +%Y-%m-%d).md`. Fill every section; mark empty sections as "No issues found."

Each finding entry must include:
- **Path** — exact relative file or directory path
- **Reason** — one sentence explaining why it's flagged
- **Action** — concrete recommended action (P1/P2/P3 tagged)

## The five audit sections

### 1. Directory Violations

Source: `check-dir-sizes.sh` output.

Flag three classes:
- **Overfull** — >10 direct files → P2 (consider splitting into subdirectories)
- **Sparse** — ≤1 file AND no subdirectories → P3 (single-file dirs add nav overhead; consider merging)
- **Empty** — 0 files, 0 subdirs → P1 (git won't track empty dirs; usually a stale dir or needs a `.gitkeep`)

### 2. Misplaced Files

Flag files that appear to be in the wrong location:
- Docs describing internal architecture placed in a user-facing `docs/` location (or vice versa)
- Ticket-named files (`sched-*.md`, `issue-1234-*.md`) committed as permanent docs
- Temporary-looking files (`*.tmp`, `*.bak`, `*-copy.*`) in tracked directories
- Top-level docs that should be in a `docs/` subdirectory

### 3. Unclear File Names

Flag names that don't communicate purpose at a glance:
- Generic single-word script names: `utils.sh`, `helpers.sh`, `common.sh`, `fix.sh`, `script.sh`
- Temporary-looking names: `temp-*`, `new-*`, `old-*`, `backup-*`
- Ticket-id names committed as permanent files

For each: suggest a clearer name.

### 4. Redundant / Stale Files

**4a. Dead scripts** — scripts with ≤1 reference across the whole repo (from the inline grep above). Before flagging: verify the script is not invoked via a variable or a dynamic list. Include the verification command and its output in the report.

**4b. Old architecture references** — files mentioning patterns from a previous architecture (e.g. a migrated framework name, a deleted directory path, a removed tool) that are no longer valid. Check:

```bash
# Find any stale references to common migration patterns
# Edit this grep to match your repo's history — examples:
git log --since=90.days.ago --oneline --name-only -- '*.md' | grep -v '^[a-f0-9]' | sort -u | head -30
```

Read the git log and then check if docs still reference recently-deleted paths.

**4c. Stale investigation or one-off docs** — `*.md` files that look like they were written for a specific incident or spike and were never cleaned up. Candidates: filenames with dates, "investigation", "spike", "analysis" — that are not linked from any README.

### 5. Over-commented Files

Source: `check-comment-density.sh` output.

- Shell scripts >40% comment lines → suggest pruning obvious boilerplate
- Markdown files with `<!-- HTML comment -->` blocks → usually stale scaffolding or template placeholders; recommend removing

## Report template

```markdown
# Repo Review — <DATE>

## Summary
Scanned <N> directories, <N> shell scripts, <N> markdown files.
P1 issues: N | P2 issues: N | P3 issues: N

---

## 1. Directory Violations
| Path | Issue | Files | Action |
|------|-------|-------|--------|
| ... | overfull / sparse / empty | N | P1/P2/P3: ... |

---

## 2. Misplaced Files
| Path | Reason | Action |
|------|--------|--------|
| ... | ... | P?: ... |

---

## 3. Unclear File Names
| Path | Suggested Name |
|------|---------------|
| ... | ... |

---

## 4. Redundant / Stale Files
| Path | Evidence | Action |
|------|----------|--------|
| ... | grep count: N | P?: ... |

---

## 5. Over-commented Files
| Path | Comment % | Action |
|------|-----------|--------|
| ... | XX% | P?: ... |

---

## No Issues Found
- Section N: clean
```

## Hard rules

- **Read-only.** The only file this skill creates is the report itself. Never edit, move, or delete anything.
- **Report first.** Write the full report before suggesting any fixes. The report is the deliverable.
- **Use bash, not manual enumeration.** Never list files by typing them out — always use `find`, `grep`, `wc`, or `git log`.
- **Never skip a section.** If a section has no findings, write "No issues found." — a blank section looks like an error.
- **Verify before recommending deletion.** For any file flagged as redundant, the report must include the verification command and its output — not just the assertion.

## References

- `scripts/check-dir-sizes.sh` — directory file-count scan (overfull + sparse)
- `scripts/check-comment-density.sh` — comment-density scan for shell scripts
