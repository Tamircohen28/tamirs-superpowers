---
name: docs-review
description: "Audit and fix every Markdown doc in this repo (README.md + docs/**) — visual cleanliness, freshness vs git history, removal of stray plan/work files, and validity of all links. Use whenever the user wants a docs sweep, refresh, audit, cleanup, link-check, or consistency pass."
when_to_use: "User asks to review, audit, clean up, refresh, sweep, or validate documentation — phrases like 'docs-review', 'review the docs', 'check README', 'docs are stale', 'validate doc links', 'docs sweep', 'docs cleanup', 'tidy up docs'."
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
  tags:
    - documentation
    - audit
    - links
    - freshness
    - cleanup
    - workflow
  updated-date: "2026-06-07"
---

# docs-review

A documentation-quality sweep: every Markdown file under `README.md` and `docs/**` is audited across five axes, then fixed in place. The goal is to finish with zero broken links, no stray plan files, and every doc reflecting the current state of the codebase.

## Scope

**Full audit:** `README.md` (repo root), every `*.md` under `docs/`.
**Partial audit:** If `$ARGUMENTS` is a path or glob, restrict to that subset.

## Step 0 — Build file manifest (ALWAYS FIRST)

```bash
{ find . -maxdepth 1 -name 'README.md'; find docs -name '*.md' -type f 2>/dev/null; } \
  | sort > /tmp/docs-manifest.txt
echo "=== $(wc -l < /tmp/docs-manifest.txt | tr -d ' ') files queued ==="
cat /tmp/docs-manifest.txt
```

Print the list so the user can see scope before work begins.

## The five audit axes

Walk each file once and apply all checks. Fix in-place. Print `[✓] path — N fixes applied` or `[·] path — clean` for each file.

### Axis 1 — Visual cleanliness

Fix:
- Trailing whitespace on lines
- Code fences without language hints (` ``` ` → ` ```bash `, ` ```json `, ` ```yaml `, etc.)
- Tables with misaligned or inconsistent column counts
- Inconsistent bullet styles (mix of `-`, `*`, `+` in one file) — normalize to `-`
- Heading level skips (e.g. `####` directly after `#` with no `##` or `###` in between)
- Long lines inside prose paragraphs (soft 120 char limit — flag, don't hard-wrap)

Leave alone: ASCII diagrams, code blocks with legitimately long single-line commands.

### Axis 2 — Freshness vs git history

For each file, check what changed in the repo since the doc was last touched:

```bash
DOC_FILE="<path>"
DOC_UPDATED=$(git log -1 --format="%ai" -- "$DOC_FILE" 2>/dev/null)
echo "Doc last updated: $DOC_UPDATED"
git log --since="$DOC_UPDATED" --oneline --name-only -- . \
  | grep -v '^[a-f0-9]' | grep -v '^$' | sort -u | head -40
```

When significant repo files changed after the doc's last update, READ the doc and check if it references those files. Update stale references — renamed scripts, deleted commands, changed paths, wrong counts.

Do NOT rewrite wholesale — fix only what drifted.

### Axis 3 — Stray plan / work files

Detect files that look like one-off work artifacts committed to docs by mistake:

```bash
find docs -name '*.md' -type f 2>/dev/null | while read f; do
  base=$(basename "$f")
  # Flag filenames that signal temporary work
  if echo "$base" | grep -qiE '([-_](plan|research|analysis|review|notes|draft|wip|temp)|[-_]2[0-9]{3}[-_])'; then
    # Check if the file is linked from anywhere else
    linked=$(grep -rl "$(basename "$f")" docs README.md 2>/dev/null | grep -v "^${f}$" | wc -l | tr -d ' ')
    [ "$linked" -eq 0 ] && echo "CANDIDATE (unlinked plan file): $f"
  fi
done
```

For each candidate: **ask the user before removing**. Never delete without confirmation.
Suggested action: `git rm --cached <file>` and add the pattern to `.gitignore`.

### Axis 4 — Link validity

For each file, extract and validate all relative links:

```bash
DOC_FILE="<path>"
DOC_DIR=$(dirname "$DOC_FILE")
grep -oE '\[([^\]]*)\]\(([^)]+)\)' "$DOC_FILE" \
  | grep -oE '\(([^)]+)\)' | tr -d '()' \
  | grep -v '^https\?://' \
  | sed 's/#.*//' \
  | grep -v '^$' \
  | while read link; do
      target="${DOC_DIR}/${link}"
      [ ! -e "$target" ] && echo "BROKEN: $link  (in $DOC_FILE)"
    done
```

Fix broken relative links or remove them if the target no longer exists. Never invent a link target that doesn't exist.

### Axis 5 — Cross-reference consistency

- Table of contents entries that point to headings that were renamed
- Raw file paths used as visible link text (should be descriptive labels like `[Architecture Overview](./architecture.md)` not `[./architecture.md](./architecture.md)`)
- Duplicate heading IDs in the same file (two `## Installation` sections)

## End-to-end sweep procedure

1. **Step 0** — build manifest; print file list.
2. **Per-file audit** — for each file in `/tmp/docs-manifest.txt`:
   - **READ the file** (mandatory — never mark reviewed without reading)
   - Apply Axes 1–5; fix in-place
   - Print status line
3. **Stray-file sweep** — run Axis 3 detection across all docs; list candidates for user to confirm.
4. **Write report** — save findings to `docs/review-$(date +%Y-%m-%d).md`:

```markdown
# Docs Review — <DATE>

## Summary
Reviewed N files. M fixes applied. K broken links fixed. J stray files flagged.

## Fixes Applied
| File | Axis | Fix |
|------|------|-----|
| ...  | ...  | ... |

## Broken Links Fixed
...

## Stray File Candidates (awaiting user confirmation)
...

## Manually Verify
Items that need human judgement (external URLs, content accuracy checks, etc.)
```

5. **Final summary** — print: `Reviewed N files. M fixes applied. K files need attention.`

## Hard rules

- **Never mark a file reviewed without reading it.** Status lines require: file read + all 5 axes checked.
- **Step 0 MUST run before any per-file audit.** Never skip, even on partial sweeps.
- **Never delete a doc without user confirmation.** Untrack only after the user says yes.
- **Never rewrite a whole doc wholesale.** Fix only the drifted parts.
- **Never invent links.** If a target doesn't exist, remove the link or flag it for the user.
- **Never paraphrase command names, file paths, or identifiers.** Use exact names from the codebase.
