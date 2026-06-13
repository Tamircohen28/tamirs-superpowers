#!/usr/bin/env bash
# Scan a project directory for employer IP that must be removed before public release.
# Usage: ip-scan.sh <project-dir> [patterns-file]
#
# Optional patterns-file: path to a file with one grep-E pattern per line.
# If not provided, falls back to ~/.claude/skills/repo-polish/scan-patterns.txt
# Built-in patterns cover generic credential and self-hosted CI leaks only.
set -euo pipefail

DIR="${1:?Usage: ip-scan.sh <project-dir> [patterns-file]}"
DIR="$(cd "$DIR" && pwd)"
PATTERNS_FILE="${2:-}"

# Fall back to local patterns file if not passed explicitly
if [[ -z "$PATTERNS_FILE" ]]; then
  LOCAL_PATTERNS="$HOME/.claude/skills/repo-polish/scan-patterns.txt"
  [[ -f "$LOCAL_PATTERNS" ]] && PATTERNS_FILE="$LOCAL_PATTERNS"
fi

# Built-in generic patterns (no employer-specific content)
declare -a BUILTIN_PATTERNS=(
  # Credentials / secrets
  "['\"]?[A-Za-z_]*(SECRET|TOKEN|PASSWORD|API_KEY|ACCESS_KEY)['\"]?\\s*[:=]\\s*['\"][^'\"]{8,}"
  # Self-hosted CI — always wrong in a public repo
  "runs-on:\\s*\\[self-hosted"
  # Hardcoded localhost with non-standard ports (often internal services)
  "https?://localhost:[0-9]{4,5}/[a-zA-Z]"
)

# Load extra patterns from file (one ERE pattern per line, # comments ignored)
declare -a FILE_PATTERNS=()
if [[ -n "$PATTERNS_FILE" && -f "$PATTERNS_FILE" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    FILE_PATTERNS+=("$line")
  done < "$PATTERNS_FILE"
fi

# Merge patterns — use array expansion guard for empty FILE_PATTERNS (bash -u safe on macOS)
PATTERNS=("${BUILTIN_PATTERNS[@]}" ${FILE_PATTERNS[@]+"${FILE_PATTERNS[@]}"})

# File extensions to scan
INCLUDE_ARGS=(
  --include="*.md"
  --include="*.yml"
  --include="*.yaml"
  --include="*.json"
  --include="*.ts"
  --include="*.js"
  --include="*.mjs"
  --include="*.cjs"
  --include="*.sh"
  --include="*.py"
  --include="*.env*"
  --include="*.toml"
  --include="*.txt"
  --include="*.html"
  --include="*.css"
)

# Directories to skip
EXCLUDE_DIRS=(
  ".git"
  "node_modules"
  "vendor"
  ".venv"
  "dist"
  "build"
  "__pycache__"
  ".cache"
)

build_exclude_args() {
  for d in "${EXCLUDE_DIRS[@]}"; do
    echo "--exclude-dir=$d"
  done
}

EXCLUDE_ARGS=()
while IFS= read -r line; do
  EXCLUDE_ARGS+=("$line")
done < <(build_exclude_args)

echo "=== Employer IP Scan: $DIR ==="
echo "Scanned at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ -n "$PATTERNS_FILE" ]]; then
  echo "Extra patterns from: $PATTERNS_FILE (${#FILE_PATTERNS[@]} pattern(s))"
fi
echo ""

FOUND_ANY=0
TOTAL_HITS=0

for pattern in "${PATTERNS[@]}"; do
  matches=$(grep -rn \
    "${INCLUDE_ARGS[@]}" \
    "${EXCLUDE_ARGS[@]}" \
    -E "$pattern" \
    "$DIR" 2>/dev/null || true)

  if [[ -n "$matches" ]]; then
    FOUND_ANY=1
    count=$(echo "$matches" | wc -l | tr -d ' ')
    TOTAL_HITS=$((TOTAL_HITS + count))
    echo "### Pattern: \`$pattern\`  ($count occurrence(s))"
    echo ""
    shown=0
    while IFS= read -r line && [[ $shown -lt 20 ]]; do
      echo "${line//$DIR\//}"
      shown=$((shown + 1))
    done <<< "$matches"
    if [[ $count -gt 20 ]]; then
      echo "  ... and $((count - 20)) more"
    fi
    echo ""
  fi
done

echo "---"
if [[ $FOUND_ANY -eq 0 ]]; then
  echo "RESULT: CLEAN — no employer IP patterns found."
  exit 0
else
  echo "RESULT: $TOTAL_HITS hit(s) found. Review and remove all hits before publishing."
  exit 0
fi
