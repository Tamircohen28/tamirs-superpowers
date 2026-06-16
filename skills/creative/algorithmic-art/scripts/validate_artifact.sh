#!/usr/bin/env bash
# validate_artifact.sh — Check a generated algorithmic-art HTML artifact for required elements.
# Usage: bash validate_artifact.sh <path-to-artifact.html>
# Exit 0 = all checks pass. Exit 1 = one or more checks failed.

set -euo pipefail

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "Usage: validate_artifact.sh <artifact.html>" >&2
  exit 1
fi

PASS=0
FAIL=0

check() {
  local label="$1"
  local pattern="$2"
  if grep -qE "$pattern" "$FILE"; then
    echo "  PASS  $label"
    ((PASS++)) || true
  else
    echo "  FAIL  $label  (pattern: $pattern)"
    ((FAIL++)) || true
  fi
}

echo "=== Validating: $FILE ==="
echo ""
echo "--- Seeding ---"
check "randomSeed called"         "randomSeed\s*\("
check "noiseSeed called"          "noiseSeed\s*\("
check "seed in params object"     "seed\s*:"

echo ""
echo "--- Canvas ---"
check "1200x1200 canvas"          "createCanvas\s*\(\s*1200\s*,\s*1200"

echo ""
echo "--- p5.js from CDN ---"
check "p5.js CDN link"            "cdnjs\.cloudflare\.com.*p5"

echo ""
echo "--- Seed navigation UI ---"
check "prevSeed function"         "prevSeed\s*\("
check "nextSeed function"         "nextSeed\s*\("
check "randomSeedFn / randomize"  "randomSeed(Fn)?\s*\(\s*\)"

echo ""
echo "--- Action buttons ---"
check "regenerate button/function" "regenerate\s*\("
check "resetDefaults function"     "resetDefaults\s*\("
check "saveCanvas (download)"      "saveCanvas\s*\("

echo ""
echo "--- No external JS files ---"
# Warn if a local .js src is referenced (CDN links are fine)
if grep -qE '<script[^>]+src=["\'][^h][^t][^t][^p]' "$FILE"; then
  echo "  WARN  Local .js script src detected — artifact may not be self-contained"
  ((FAIL++)) || true
else
  echo "  PASS  No local .js src references"
  ((PASS++)) || true
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
