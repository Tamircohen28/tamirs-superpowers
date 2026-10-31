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

SELF_HOSTED_PATTERN="runs-on:\\s*\\[self-hosted"
declare -a BUILTIN_PATTERNS=(
  "['\"]?[A-Za-z_]*(SECRET|TOKEN|PASSWORD|API_KEY|ACCESS_KEY)['\"]?\\s*[:=]\\s*['\"][^'\"]{8,}"
  "$SELF_HOSTED_PATTERN"
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

# drop_self_hosted_waived <matches> — keep only self-hosted hits WITHOUT a waiver.
# A waiver is `# self-hosted-ok: <reason>` in the comment part of the line (same
# rule as check-repo-hygiene.sh and `action-pin-ok:`). It applies to the
# self-hosted pattern alone: the same comment on a credential line waives nothing.
# Runs in a command substitution, so the caller counts what it dropped.
# "Comment" means a `#` at the start or after whitespace, outside quotes, so a
# quoted runner label such as `"# self-hosted-ok: x"` waives nothing.
WAIVED=0
self_hosted_ok() {
  local s waiver='(^|[[:space:]])#.*self-hosted-ok:[[:space:]]*[^[:space:]]'
  s="$(printf '%s' "$1" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g")"
  [[ "$s" =~ $waiver ]]
}
drop_self_hosted_waived() {
  local input="${1:-}" line content
  [[ -z "$input" ]] && return 0
  while IFS= read -r line; do
    content="${line#*:}"; content="${content#*:}"        # drop "path:line:"
    self_hosted_ok "$content" && continue
    printf '%s\n' "$line"
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
  if [[ "$pattern" == "$SELF_HOSTED_PATTERN" ]]; then
    before=$(grep -c . <<< "$matches" || true)
    matches=$(drop_self_hosted_waived "$matches")
    WAIVED=$(( before - $(grep -c . <<< "$matches" || true) ))
  fi
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

[[ "$WAIVED" -gt 0 ]] && echo "Waived: $WAIVED self-hosted runner line(s) carry \`# self-hosted-ok: <reason>\`." && echo ""
echo "---"
if [[ $FOUND_ANY -eq 0 ]]; then
  echo "RESULT: CLEAN — no employer IP patterns found."
else
  echo "RESULT: $TOTAL_HITS hit(s) found. Review and remove all hits before publishing."
fi
