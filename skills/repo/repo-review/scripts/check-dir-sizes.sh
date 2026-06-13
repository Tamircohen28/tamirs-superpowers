#!/usr/bin/env bash
# check-dir-sizes.sh — report directories outside the [2,10] file-count range.
# Usage: bash .claude/skills/repo-review/scripts/check-dir-sizes.sh [ROOT_DIR]

ROOT_DIR="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ALLOWLIST_FILE="$ROOT_DIR/tooling/ci/validate-dir-file-count.sh"

# Build allowlist from the CI validator so we stay in sync with it
ALLOWLIST=()
if [ -f "$ALLOWLIST_FILE" ]; then
  while IFS= read -r line; do
    # Extract bare paths from: "path/here" # comment
    if [[ "$line" =~ ^[[:space:]]*\"([^\"]+)\" ]]; then
      ALLOWLIST+=("${BASH_REMATCH[1]}")
    fi
  done < <(sed -n '/^ALLOWLIST=(/,/^)/p' "$ALLOWLIST_FILE")
fi

is_allowlisted() {
  local rel="$1"
  for item in "${ALLOWLIST[@]}"; do
    [[ "$rel" == "$item" ]] && return 0
  done
  return 1
}

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

echo "--- Overfull (>10 files, NOT in CI allowlist) ---"
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
echo "--- Allowlisted but very large (>20 files — tracked cleanup debt) ---"
while IFS= read -r dir; do
  rel="${dir#$ROOT_DIR/}"
  [ "$rel" = "$dir" ] && rel="."
  count=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -gt 20 ] && is_allowlisted "$rel"; then
    echo "  $rel: $count files (allowlisted)"
  fi
done < "$TMPDIR_LIST"

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
