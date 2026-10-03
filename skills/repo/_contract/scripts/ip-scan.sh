#!/usr/bin/env bash
# Scan a project directory for employer IP that must be removed before public release.
# Usage: ip-scan.sh <project-dir> [patterns-file]
set -euo pipefail

DIR="${1:?Usage: ip-scan.sh <project-dir> [patterns-file]}"
DIR="$(cd "$DIR" && pwd)"
PATTERNS_FILE="${2:-}"

if [[ -z "$PATTERNS_FILE" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  LOCAL_PATTERNS="$SCRIPT_DIR/scan-patterns.txt"
  [[ -f "$LOCAL_PATTERNS" ]] && PATTERNS_FILE="$LOCAL_PATTERNS"
fi

declare -a BUILTIN_PATTERNS=(
  "['\"]?[A-Za-z_]*(SECRET|TOKEN|PASSWORD|API_KEY|ACCESS_KEY)['\"]?\\s*[:=]\\s*['\"][^'\"]{8,}"
  "runs-on:\\s*\\[self-hosted"
  "https?://localhost:[0-9]{4,5}/[a-zA-Z]"
)

declare -a FILE_PATTERNS=()
if [[ -n "$PATTERNS_FILE" && -f "$PATTERNS_FILE" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    FILE_PATTERNS+=("$line")
  done < "$PATTERNS_FILE"
fi

PATTERNS=("${BUILTIN_PATTERNS[@]}" ${FILE_PATTERNS[@]+"${FILE_PATTERNS[@]}"})

INCLUDE_ARGS=(--include="*.md" --include="*.yml" --include="*.yaml" --include="*.json"
  --include="*.ts" --include="*.js" --include="*.sh" --include="*.py" --include="*.env*"
  --include="*.toml" --include="*.txt")
EXCLUDE_DIRS=(".git" "node_modules" "vendor" ".venv" "dist" "build" "__pycache__" ".cache")

EXCLUDE_ARGS=()
for d in "${EXCLUDE_DIRS[@]}"; do EXCLUDE_ARGS+=("--exclude-dir=$d"); done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOWLIST_FILE="$SCRIPT_DIR/scan-allowlist.txt"

filter_allowlisted() {
  local input="${1:-}"
  [[ -z "$input" ]] && return 0
  if [[ ! -f "$ALLOWLIST_FILE" ]]; then
    printf '%s\n' "$input"
    return 0
  fi
  local line allow keep
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    keep=1
    while IFS= read -r allow || [[ -n "$allow" ]]; do
      [[ -z "$allow" || "$allow" == \#* ]] && continue
      if echo "$line" | grep -qE "$allow"; then
        keep=0
        break
      fi
    done < "$ALLOWLIST_FILE"
    [[ "$keep" -eq 1 ]] && printf '%s\n' "$line"
  done <<< "$input"
  return 0
}

echo "=== Employer IP Scan: $DIR ==="
echo "Scanned at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

FOUND_ANY=0
TOTAL_HITS=0

for pattern in "${PATTERNS[@]}"; do
  matches=$(grep -rn "${INCLUDE_ARGS[@]}" "${EXCLUDE_ARGS[@]}" -E "$pattern" "$DIR" 2>/dev/null || true)
  matches=$(filter_allowlisted "$matches")
  if [[ -n "$matches" ]]; then
    FOUND_ANY=1
    count=$(echo "$matches" | wc -l | tr -d ' ')
    TOTAL_HITS=$((TOTAL_HITS + count))
    echo "### Pattern: \`$pattern\`  ($count occurrence(s))"
    echo ""
    head -20 <<< "$matches" | sed "s|$DIR/||"
    [[ "$count" -gt 20 ]] && echo "  ... and $((count - 20)) more"
    echo ""
  fi
done

echo "---"
if [[ $FOUND_ANY -eq 0 ]]; then
  echo "RESULT: CLEAN — no employer IP patterns found."
else
  echo "RESULT: $TOTAL_HITS hit(s) found. Review and remove all hits before publishing."
fi
