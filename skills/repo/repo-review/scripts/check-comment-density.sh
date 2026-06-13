#!/usr/bin/env bash
# check-comment-density.sh — find shell scripts where comment lines exceed THRESHOLD%.
# Usage: bash .claude/skills/repo-review/scripts/check-comment-density.sh [ROOT_DIR]
# Env: THRESHOLD (default 40)

ROOT_DIR="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
THRESHOLD="${THRESHOLD:-40}"

echo "=== Comment Density Report (threshold: >${THRESHOLD}%) ==="
echo "ROOT: $ROOT_DIR"
echo ""

found=0
while IFS= read -r file; do
  total=$(wc -l < "$file" 2>/dev/null | tr -d ' ')
  [ "${total:-0}" -le 5 ] && continue  # skip tiny files

  # Count lines that are pure comments (# after optional whitespace)
  comments=$(grep -cE '^\s*#' "$file" 2>/dev/null || true)
  comments="${comments:-0}"

  # Subtract shebang line (not really a comment)
  has_shebang=$(head -1 "$file" 2>/dev/null | grep -c '^#!' || true)
  has_shebang="${has_shebang:-0}"
  comments=$(( comments - has_shebang ))
  [ "$comments" -lt 0 ] && comments=0

  pct=$(( comments * 100 / total ))
  if [ "$pct" -gt "$THRESHOLD" ]; then
    rel="${file#$ROOT_DIR/}"
    echo "  ${pct}%  $rel  ($comments comment / $total total lines)"
    found=$((found + 1))
  fi
done < <(
  find "$ROOT_DIR" \
    \( -name .git -o -name node_modules -o -name dist -o -name __pycache__ -o -name .venv -o -name .worktrees \) -prune \
    -o -name "*.sh" -type f -print | sort
)

echo ""
[ "$found" -eq 0 ] && echo "  (none above threshold)" || echo "TOTAL: $found scripts above ${THRESHOLD}% threshold"
