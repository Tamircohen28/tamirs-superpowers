---
name: docs-review
disable-model-invocation: true
user-invocable: false
description: "Internal: documentation quality sweep used by repo-polish. Audits every Markdown doc (README.md + docs/**) for visual cleanliness, freshness, stray plan files, and broken links. Not for direct user invocation — run repo-polish instead."
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
  updated-date: "2026-06-13"
---

# docs-review

A documentation-quality sweep: every Markdown file under `README.md` (root) and
`docs/**` is audited against five axes, then fixed in place. The goal is to
finish a sweep with a clean working tree, zero broken links, no stray plan
files, and every doc reflecting the current state of the codebase.

## Why this skill exists

Docs drift faster than code. A sweep that's "by hand" misses files,
mis-classifies plan dumps as canonical reference material, and leaves behind
stale counts and broken links. This skill codifies the routine so the audit is
exhaustive and its judgement calls are explicit.

## Scope

**Full audit (all 5 axes):** `README.md` (repo root), every `*.md` under `docs/`.

If the user passes a path argument, restrict the per-file audit to that subset (still run Step 0 first).

**Out of scope:** Source code files, generated files, `node_modules/`, `dist/`.

## Step 0 — Repo State Inventory (ALWAYS FIRST)

**Run before any per-file work.** Generates the file manifest.

```bash
{ find . -maxdepth 1 -name 'README.md'; find docs -name '*.md' -type f 2>/dev/null; } | sort > /tmp/review-docs-manifest.txt
TOTAL=$(wc -l < /tmp/review-docs-manifest.txt | tr -d ' ')
echo "=== $TOTAL files queued for audit ==="
cat /tmp/review-docs-manifest.txt
```

Print the manifest so the user can see scope before work begins.

## The five audit axes

Walk each in-scope file once and apply all five checks. Fix in-place. Print `[✓] path — N fixes applied` or `[·] path — clean` for each file.

### Axis 1 — Visual cleanliness

Goal: a reader scanning the doc isn't tripped by formatting noise.

What to fix:
- Stray trailing whitespace, mixed tabs/spaces, inconsistent heading levels.
- Code fences without language hints (` ``` ` instead of ` ```bash `, ` ```json `, ` ```yaml `, etc.).
- Tables with mismatched column counts.
- Long lines inside paragraphs (soft 120 chars; hard cap 200).
- Bullets: pick `-` consistently (avoid mixing `-`, `*`, `+` within one file).
- Heading level skips (e.g. `####` directly after `#` with no `##` or `###` in between).

What to leave alone:
- Deliberate ASCII diagrams. Code blocks of legitimately long single-line commands.

### Axis 2 — Freshness vs git history

Goal: every doc reflects the current state of the codebase.

For each file, check what changed in the repo since the doc was last touched:

```bash
DOC_FILE="<path>"
DOC_UPDATED=$(git log -1 --format="%ai" -- "$DOC_FILE" 2>/dev/null)
echo "Doc last updated: $DOC_UPDATED"
git log --since="$DOC_UPDATED" --oneline --name-only -- . \
  | grep -v '^[a-f0-9]' | grep -v '^$' | sort -u | head -40
```

When significant repo files changed after the doc's last update, READ the doc and check if it references those files.

Common fixes: rename broken links, remove references to deleted scripts or commands, update counts. Do NOT rewrite wholesale — fix only what drifted.

### Axis 3 — Stray plan / work files

Goal: `docs/` is canonical reference material, not a dumping ground.

```bash
find docs -name '*.md' -type f 2>/dev/null | while read f; do
  base=$(basename "$f")
  if echo "$base" | grep -qiE '([-_](plan|research|analysis|review|notes|draft|wip|temp)|[-_]2[0-9]{3}[-_])'; then
    linked=$(grep -rl "$(basename "$f")" docs README.md 2>/dev/null | grep -v "^${f}$" | wc -l | tr -d ' ')
    [ "$linked" -eq 0 ] && echo "CANDIDATE (unlinked plan file): $f"
  fi
done
```

Signals: filename has `-plan`, `-research`, `-analysis`, `-review`, or a date stamp; located directly under `docs/` and not linked from any README; last commit message says "wip" or "from claude session".

For each confirmed one-off: **ask the user before removing**. Never delete without confirmation.
Suggested action: `git rm --cached <file>` and add the pattern to `.gitignore`.

### Axis 4 — Link / cross-reference validity

Goal: every relative link resolves; no raw-file-path link text.

For each file, validate all relative links:

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

Also check:
- Missing heading anchors (a `#some-heading` link that points to a heading that doesn't exist in the file)
- Raw-file-path link text: `[./architecture.md](./architecture.md)` → should be `[Architecture Overview](./architecture.md)`

External `https://` URLs: sample but do not block on — flag only if obviously dead.

Fix broken relative links or remove them if the target no longer exists. Never invent a link target.

### Axis 5 — Cross-reference and diagram consistency

Goal: internal references are accurate; diagrams parse.

- Table of contents entries that point to headings that were renamed
- Duplicate heading IDs in the same file (two `## Installation` sections)
- Mermaid blocks: verify opening keywords (`graph`, `sequenceDiagram`, `flowchart`, `classDiagram`, etc.) and that blocks close properly

## End-to-end sweep procedure

1. **Step 0** — build manifest; print file list.
2. **Per-file audit** — for each file in `/tmp/review-docs-manifest.txt`:
   - **READ the file** (mandatory — never mark reviewed without reading)
   - Apply Axes 1–5; fix in-place
   - Print status line
3. **Stray-file sweep** — run Axis 3 detection across all docs; list candidates for user to confirm.
4. **Write review report** — save findings to `docs/review-$(date +%Y-%m-%d).md`:

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

## Hard rules (do NOT break these)

- **Never mark a file as reviewed without reading it.** `[✓]` requires: file read + all 5 axes checked. Scanning git log is not a substitute.
- **Step 0 MUST run before any per-file audit.** Never skip it, even on partial sweeps.
- **Never delete a doc the user has not confirmed.** Untrack first, retain working-tree copy.
- **Never rewrite a whole doc wholesale.** Fix only the drifted parts.
- **Never invent links.** If a target doesn't exist, remove the link or flag for the user.
- **Never paraphrase command names, file paths, or identifiers.** Use canonical forms from the codebase.
- **Plan files are not always trash.** The detector flags candidates; the human confirms.
