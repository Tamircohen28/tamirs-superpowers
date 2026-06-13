---
name: docs-review
disable-model-invocation: true
user-invocable: false
description: "Internal: documentation quality sweep used by repo-polish. Audits README.md and docs/**/*.md for visual cleanliness, freshness drift, stray plan/wip files, broken links, and diagram consistency. Not for direct user invocation — run repo-polish instead."
argument-hint: "[optional: subset glob like 'docs/user/**' or single file path]"
when_to_use: "Called by repo-polish to audit Markdown documentation quality. Not invoked directly."
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
    - broken-links
    - freshness
    - stray-files
    - cleanup
    - markdown
  updated-date: "2026-06-13"
---

# docs-review

Internal documentation-quality sweep. Audits every Markdown file in scope against five axes and fixes issues in place. Invoked by `repo-polish`; do not call directly.

## Why this skill exists

Docs drift faster than code. Manual sweeps miss files, misclassify plan dumps as canonical reference material, and leave stale counts and broken links behind. This skill codifies the routine so the audit is exhaustive and every judgement call is explicit — reproducible across sessions without human memory.

The naive approach (read docs, spot-fix what looks wrong) fails because: it skips files with no obvious surface problem, conflates "last touched" with "still accurate", and has no systematic check for broken cross-references.

## Scope

**In scope:** `README.md` (repo root) + every `*.md` under `docs/`.

If a path argument is passed, restrict per-file work to that subset — still run Step 0 first.

**Out of scope:** Source code comments, generated files, `node_modules/`, `dist/`, `coverage/`.

## Quick-reference: five audit axes

| Axis | Name | What it catches |
|------|------|-----------------|
| 1 | Visual cleanliness | Trailing whitespace, mixed bullets, missing code-fence languages, heading level skips, long lines |
| 2 | Freshness vs git | Doc not updated after significant file changes it references |
| 3 | Stray plan/wip files | `-plan`, `-draft`, `-wip`, date-stamped files in `docs/` not linked from anywhere |
| 4 | Link validity | Broken relative links, missing heading anchors, raw-path link text |
| 5 | Cross-ref & diagram | Renamed headings in ToC, duplicate heading IDs, malformed Mermaid blocks |

## Step 0 — Repo state inventory (ALWAYS FIRST)

Run before any per-file work. Produces the file manifest.

```bash
{ find . -maxdepth 1 -name 'README.md'; find docs -name '*.md' -type f 2>/dev/null; } \
  | sort > /tmp/review-docs-manifest.txt
TOTAL=$(wc -l < /tmp/review-docs-manifest.txt | tr -d ' ')
echo "=== $TOTAL files queued for audit ==="
cat /tmp/review-docs-manifest.txt
```

Print the manifest before starting so the caller can see scope.

## Per-file audit — axes 1–5

Walk each in-scope file once and apply all five checks. Fix in place. Print `[✓] path — N fixes applied` or `[·] path — clean` per file.

### Axis 1 — Visual cleanliness

Fix:
- Trailing whitespace; mixed tabs/spaces.
- Code fences without language hints (` ``` ` → ` ```bash `, ` ```json `, ` ```yaml `, etc.).
- Tables with misaligned or mismatched column counts.
- Lines over 200 characters inside prose paragraphs (soft cap 120, hard 200).
- Mixed bullet styles within one file (`-`, `*`, `+`) — normalize to `-`.
- Heading level skips (`####` directly after `#` with no `##`/`###` in between).

Leave alone: deliberate ASCII diagrams; legitimately long single-line commands inside code blocks.

### Axis 2 — Freshness vs git history

```bash
DOC_FILE="<path>"
DOC_UPDATED=$(git log -1 --format="%ai" -- "$DOC_FILE" 2>/dev/null)
echo "Doc last updated: $DOC_UPDATED"
git log --since="$DOC_UPDATED" --oneline --name-only -- . \
  | grep -v '^[a-f0-9]' | grep -v '^$' | sort -u | head -40
```

When significant repo files changed after the doc's last update, READ the doc and check if it references those files. Common fixes: rename broken links, remove references to deleted scripts or commands, update counts and version numbers. Fix only what drifted — do NOT rewrite wholesale.

### Axis 3 — Stray plan / wip files

```bash
find docs -name '*.md' -type f 2>/dev/null | while read f; do
  base=$(basename "$f")
  if echo "$base" | grep -qiE '([-_](plan|research|analysis|review|notes|draft|wip|temp)|[-_]2[0-9]{3}[-_])'; then
    linked=$(grep -rl "$(basename "$f")" docs README.md 2>/dev/null | grep -v "^${f}$" | wc -l | tr -d ' ')
    [ "$linked" -eq 0 ] && echo "CANDIDATE (unlinked plan file): $f"
  fi
done
```

Signals: filename has `-plan`, `-draft`, `-wip`, `-research`, or a date stamp; not linked from any canonical doc; last commit message says "wip" or "from claude session".

For each candidate: **ask the user before removing**. Suggested action: `git rm --cached <file>` and add the pattern to `.gitignore`.

### Axis 4 — Link / cross-reference validity

```bash
DOC_FILE="<path>"
DOC_DIR=$(dirname "$DOC_FILE")
grep -oP '\]\(\K[^)]+' "$DOC_FILE" \
  | grep -v '^https\?://' \
  | sed 's/#.*//' \
  | grep -v '^$' \
  | while read link; do
      target="${DOC_DIR}/${link}"
      [ ! -e "$target" ] && echo "BROKEN: $link  (in $DOC_FILE)"
    done
```

Also check:
- `#anchor` links pointing to headings that don't exist in the target file.
- Raw-path link text: `[./architecture.md](./architecture.md)` → `[Architecture Overview](./architecture.md)`.

External `https://` URLs: sample but do not block the sweep — flag only obviously dead ones (connection refused, 404).

Fix broken relative links or remove them if the target no longer exists. **Never invent a link target.**

### Axis 5 — Cross-reference and diagram consistency

- Table of contents entries pointing to renamed headings.
- Duplicate heading IDs in the same file (two `## Installation` sections).
- Mermaid blocks: verify opening keyword (`graph`, `sequenceDiagram`, `flowchart`, `classDiagram`, `erDiagram`, `gantt`) and that the block closes with a bare ` ``` `.

## End-to-end sweep procedure

1. **Step 0** — build manifest; print file list.
2. **Per-file audit** — for each file in `/tmp/review-docs-manifest.txt`:
   - READ the file (mandatory — never mark reviewed without reading).
   - Apply Axes 1–5; fix in place.
   - Print status line: `[✓] path — N fixes` or `[·] path — clean`.
3. **Stray-file sweep** — run Axis 3 across all docs; list candidates; wait for user confirmation before any deletion.
4. **Print summary** to stdout — do NOT write a review report into `docs/`; that would create exactly the kind of stray file Axis 3 detects.

```
Docs review complete — <DATE>
  Files reviewed : N
  Fixes applied  : M
  Broken links   : K fixed
  Stray files    : J flagged (awaiting confirmation)
  Manual review  : list any items needing human judgement
```

## Hard rules

- **Never mark a file as reviewed without reading it.** `[✓]` requires: file read + all 5 axes checked. Scanning git log is not a substitute.
- **Step 0 MUST run before any per-file audit.** Never skip it, even on partial sweeps.
- **Never delete a doc without user confirmation.** Untrack first (`git rm --cached`), retain working-tree copy.
- **Never rewrite a whole doc wholesale.** Fix only the drifted or broken parts.
- **Never invent links.** If a target doesn't exist, remove the link or flag it for the user.
- **Never write the review report into `docs/`.** Output to stdout only — a report file in `docs/` is a stray plan file by Axis 3's own definition.
- **Never paraphrase command names, file paths, or identifiers.** Use canonical forms from the codebase.

## Anti-patterns

| Wrong | Right |
|-------|-------|
| Skipping Step 0 and guessing which files exist | Always build the manifest first |
| Marking a file `[✓]` after only reading git log | Read the actual file content |
| Rewriting entire docs because they feel outdated | Fix only what the git history proves has drifted |
| Deleting a stray file without asking | Flag as CANDIDATE; ask before any removal |
| Writing `docs/review-YYYY-MM-DD.md` to capture findings | Print summary to stdout; never add report files to `docs/` |
| Treating `https://` link failures as blocking | Flag external broken links; don't stall the sweep |
| Fixing long lines inside code blocks | Only fix long lines in prose paragraphs |
