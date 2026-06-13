---
name: repo-review
disable-model-invocation: true
user-invocable: false
description: "Internal: repo health audit used by repo-polish. Scans for misplaced files, overfull dirs, sparse dirs, unclear names, dead scripts, stale docs, and over-commented shell files. Outputs a prioritised findings report to docs/. Not for direct user invocation — run repo-polish instead."
model: claude-sonnet-4-6
when_to_use: |
  Invoked automatically by repo-polish when the user asks for a repo health check,
  codebase audit, cleanup sweep, dead code scan, or stale file review.
  Never triggered directly by users — always called as a sub-skill from repo-polish.
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
    - dead-scripts
    - comment-density
  updated-date: "2026-06-13"
---

# Repo Review — Internal Repository Health Audit

A **read-only** audit that scans a repository's structure and produces a prioritised findings report. Never edits source files — the only output is `docs/repo-review-<DATE>.md`.

## Why this skill exists

Repos accumulate debt invisibly: directories with one file, scripts nobody calls, docs that reference deleted paths, ticket-id filenames committed as permanent files, and shell scripts buried under boilerplate comments. A manual sweep takes hours and still misses things. Naive grep-and-list approaches produce false positives (e.g., flagging files as "dead" when they're loaded dynamically). This skill runs a structured mechanical sweep — combining helper scripts with inline targeted queries — and produces a single actionable report the team can triage.

## Workflow (follow this order exactly)

### Step 1 — Locate the repo root

```bash
ROOT="$(git rev-parse --show-toplevel)"
echo "Auditing: $ROOT"
```

### Step 2 — Run the helper scripts

The helper scripts are bundled alongside this skill. `$CLAUDE_SKILL_DIR` is set to the directory containing this SKILL.md when invoked via the Skill tool from repo-polish.

```bash
bash "$CLAUDE_SKILL_DIR/scripts/check-dir-sizes.sh"      "$ROOT" 2>&1
bash "$CLAUDE_SKILL_DIR/scripts/check-comment-density.sh" "$ROOT" 2>&1
```

Capture the full output — you'll reference it in Sections 1 and 5 of the report.

### Step 3 — Run inline discovery queries

Run all of these from `$ROOT`. They cover gaps the scripts don't:

```bash
# Generic / unclear script names — utils.sh, helpers.sh, fix.sh, temp.sh, etc.
find "$ROOT" -name '*.sh' 2>/dev/null \
  | grep -E '/(utils|helpers|common|fix|script|temp|new[-_]|old[-_])' \
  | grep -v '\.git' || true

# Ticket-named or dated markdown files (likely one-off artifacts)
find "$ROOT" -name '*.md' 2>/dev/null \
  | grep -iE '[-_](investigation|spike|analysis|2[0-9]{3}[-_][0-9]{2})' \
  | grep -v '\.git' || true

# Markdown files containing HTML comment blocks (stale scaffolding / template placeholders)
grep -rl '<!--' "$ROOT" --include='*.md' 2>/dev/null | grep -v '\.git' || true

# Potentially dead scripts (≤1 reference across .md, .sh, .json files)
for f in $(find "$ROOT" -name '*.sh' 2>/dev/null | grep -v '\.git' | head -60); do
  name=$(basename "$f")
  count=$(grep -rl "$name" "$ROOT" \
    --include='*.md' --include='*.sh' --include='*.json' \
    --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='dist' \
    2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -le 1 ] && echo "UNREFERENCED: $f (count=$count)"
done

# Stale SKILL.md updated-dates (>60 days old); works on both macOS and Linux
TODAY=$(date +%s)
for f in $(find "$ROOT" -name 'SKILL.md' 2>/dev/null | grep -v '\.git'); do
  date_str=$(grep 'updated-date:' "$f" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
  [ -z "$date_str" ] && continue
  # macOS: date -j -f '%Y-%m-%d'; Linux: date -d
  file_ts=$(date -j -f '%Y-%m-%d' "$date_str" +%s 2>/dev/null \
            || date -d "$date_str" +%s 2>/dev/null) || continue
  age=$(( (TODAY - file_ts) / 86400 ))
  [ "$age" -gt 60 ] && echo "STALE ($age days): $f — updated-date: $date_str"
done

# Docs referencing recently-deleted paths (last 90 days of deletions)
git -C "$ROOT" log --since=90.days.ago --diff-filter=D --name-only --pretty=format: \
  | grep -v '^$' | sort -u | head -30
```

### Step 4 — Reason before writing

Before drafting the report, classify each finding:

| Priority | Criterion |
|----------|-----------|
| **P1** | Active quality problem — misleads contributors, breaks tooling, or causes confusion right now. Fix next PR. |
| **P2** | Real debt — slows onboarding or causes drift. Schedule for cleanup within a sprint. |
| **P3** | Nice-to-have — low risk, no urgency. Worth a future tidy-up PR. |

Do not skip empty sections. If a section has no findings, mark it "No issues found."

### Step 5 — Write the report

Write to `docs/repo-review-$(date +%Y-%m-%d).md` (create `docs/` with `mkdir -p` if absent).

Each finding row must include: **Path**, **Reason** (one sentence), **Action** (P-tagged).

## The five audit sections

### 1. Directory Violations

Source: `check-dir-sizes.sh` output.

| Class | Threshold | Default Priority |
|-------|-----------|-----------------|
| **Overfull** | >10 direct files in one dir | P2 — consider splitting into subdirectories |
| **Sparse** | ≤1 file AND 0 subdirectories | P3 — single-file dirs add navigation overhead; consider merging |
| **Empty** | 0 files, 0 subdirs | P1 — git won't track empty dirs; add `.gitkeep` or remove |

### 2. Misplaced Files

Flag files that appear to be in the wrong location:
- Ticket-named files (`issue-1234-*.md`, `sched-*.md`) committed as permanent docs
- Temporary-looking tracked files (`*.tmp`, `*.bak`, `*-copy.*`)
- Internal architecture docs placed in user-facing `docs/` (or vice versa)
- Top-level files that belong in a subdirectory

### 3. Unclear File Names

Flag names that don't communicate purpose at a glance:
- Generic single-word script names: `utils.sh`, `helpers.sh`, `common.sh`, `fix.sh`
- Temporary-looking names: `temp-*`, `new-*`, `old-*`, `backup-*`
- Ticket-id names committed as permanent files

For every flagged file, suggest a concrete clearer name.

### 4. Redundant / Stale Files

**4a. Dead scripts** — ≤1 reference across the repo (from the inline loop above).
Before flagging: verify the script is not loaded dynamically via a variable or a generated list. Include the verification command and its output in the report.

```bash
# Confirm a specific script is truly unreferenced
name="suspect-script.sh"
grep -rn "$name" "$ROOT" \
  --include='*.md' --include='*.sh' --include='*.json' \
  --exclude-dir='.git' --exclude-dir='node_modules'
```

**4b. Stale architecture references** — docs mentioning paths, tools, or frameworks that were deleted or replaced. Cross-reference the git-deleted-paths list from Step 3 against `grep -rl <deleted-path> .`.

**4c. One-off investigation docs** — `*.md` files with "investigation", "spike", "analysis", or date-stamped names that are not linked from any README or index.

### 5. Over-commented Files

Source: `check-comment-density.sh` output (default threshold: 40%).

| Signal | Recommendation |
|--------|---------------|
| Shell script >40% comment lines | Suggest pruning obvious boilerplate or outdated commentary |
| Markdown with `<!-- HTML comment -->` blocks | Likely stale scaffolding or template placeholders; recommend removing |

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
| path/to/dir | overfull | 14 | P2: Split into two subdirectories |
| path/to/empty | empty | 0 | P1: Add .gitkeep or remove |

---

## 2. Misplaced Files
| Path | Reason | Action |
|------|--------|--------|
| SPIKE-123-auth.md | Ticket-named file committed as permanent doc | P2: Move to docs/archive/ or delete |

---

## 3. Unclear File Names
| Current Path | Suggested Name |
|-------------|---------------|
| scripts/fix.sh | scripts/fix-broken-symlinks.sh |

---

## 4. Redundant / Stale Files
| Path | Evidence | Action |
|------|----------|--------|
| scripts/old-deploy.sh | grep count: 0 references | P1: Delete or archive |

---

## 5. Over-commented Files
| Path | Comment % | Action |
|------|-----------|--------|
| hooks/setup.sh | 62% | P3: Prune boilerplate comment blocks |

---

## Sections with no issues
- Section N: No issues found.
```

## Hard rules

- **Read-only.** The only file this skill creates is the report itself. Never edit, move, or delete source files.
- **All five sections must appear.** A missing section looks like an error. Write "No issues found." if a section is clean.
- **Use bash, not manual enumeration.** Never type out a file list — always use `find`, `grep`, `wc`, or `git log`.
- **Verify before recommending deletion.** For any file flagged redundant, the report must include the verification command and its actual output — not just the assertion.
- **No false positives from dynamic loading.** Before marking a script dead, check if its name is referenced via a variable, `ls`/`find` pipeline, or sourced glob pattern.
- **macOS/Linux portable date commands.** Use the two-variant `date -j -f` / `date -d` pattern from Step 3 — not Linux-only `date -d` alone.

## What NOT to do

- **Don't flag files just because they look old** — age alone is not a signal. Flag stale-date SKILL.md files only if the updated-date field is >60 days behind today.
- **Don't open or read every file** to check for stale content — use targeted `grep -rl` queries. Reading every file is O(n) on repo size and blows token budgets.
- **Don't write the report incrementally** — gather all findings first, then write once. Partial reports are confusing.
- **Don't suggest renames for files outside your audit scope** — the report covers the five defined sections only.

## References

- `scripts/check-dir-sizes.sh` — directory file-count scan (overfull, sparse, empty)
- `scripts/check-comment-density.sh` — comment-density scan for shell scripts
