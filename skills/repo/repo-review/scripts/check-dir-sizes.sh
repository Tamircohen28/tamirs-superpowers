#!/usr/bin/env bash
# check-dir-sizes.sh — report directories outside the [2,10] file-count range.
# Usage: bash .claude/skills/repo-review/scripts/check-dir-sizes.sh [ROOT_DIR]

ROOT_DIR="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# No allowlist — all directories with >10 files are reported.
is_allowlisted() { return 1; }

echo "=== Directory Size Report ==="
echo "ROOT: $ROOT_DIR"
echo ""

overfull=0
sparse=0
empty_dirs=0

# Run find once; reuse for all three classification passes
TMPDIR_LIST=$(mktemp)
trap 'rm -f "$TMPDIR_LIST"' EXIT
find "$ROOT_DIR" \
  \( -name .git -o -name node_modules -o -name dist -o -name __pycache__ -o -name .venv -o -name .worktrees \) -prune \
  -o -type d -print | sort > "$TMPDIR_LIST"

echo "--- Overfull (>10 files) ---"
while IFS= read -r dir; do
  rel="${dir#$ROOT_DIR/}"
  [ "$rel" = "$dir" ] && rel="."
  count=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -gt 10 ] && ! is_allowlisted "$rel"; then
    echo "  $rel: $count files"
    overfull=$((overfull + 1))
  fi
done < "$TMPDIR_LIST"
[ "$overfull" -eq 0 ] && echo "  (none)"


echo ""
echo "--- Sparse (≤1 file with no subdirectories) ---"
while IFS= read -r dir; do
  rel="${dir#$ROOT_DIR/}"
  [ "$rel" = "$dir" ] && rel="."
  file_count=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
  subdir_count=$(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  if [ "$file_count" -le 1 ] && [ "$subdir_count" -eq 0 ]; then
    echo "  $rel: $file_count files, $subdir_count subdirs"
    if [ "$file_count" -eq 0 ]; then
      empty_dirs=$((empty_dirs + 1))
    else
      sparse=$((sparse + 1))
    fi
  fi
done < "$TMPDIR_LIST"
[ "$((sparse + empty_dirs))" -eq 0 ] && echo "  (none)"

echo ""
echo "SUMMARY: $overfull overfull | $sparse sparse | $empty_dirs empty"
