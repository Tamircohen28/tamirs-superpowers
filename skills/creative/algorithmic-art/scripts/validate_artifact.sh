#!/usr/bin/env bash
# validate_artifact.sh — Check a generated algorithmic-art HTML page for required elements.
# Usage: bash validate_artifact.sh [--vendored] <path-to-page.html>
#   --vendored  the page inlines p5.js instead of linking the CDN (offline / strict-CSP mode).
#               Requires an inline p5 payload AND fails if a CDN script link is still present.
# Exit 0 = all checks pass. Exit 1 = one or more checks failed.
# Dependencies: bash + grep only. No network access; nothing is fetched.

set -euo pipefail

VENDORED=0
FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vendored) VENDORED=1; shift ;;
    -h|--help)  echo "Usage: validate_artifact.sh [--vendored] <page.html>"; exit 0 ;;
    -*)         echo "Unknown option: $1" >&2; exit 1 ;;
    *)          FILE="$1"; shift ;;
  esac
done

if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "Usage: validate_artifact.sh [--vendored] <page.html>" >&2
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
if [[ $VENDORED -eq 1 ]]; then
  echo "--- p5.js vendored inline ---"
  # Markers that appear in the p5 source itself, not in a CDN URL.
  check "inline p5 payload"       "p5\.prototype|_main\.default|vendored"
  # A vendored page must not also fetch p5 at view time, or it is not offline-capable.
  if grep -qE '<script[^>]+src=["'"'"']https?://[^"'"'"']*p5' "$FILE"; then
    echo "  FAIL  CDN p5 <script src> still present in a --vendored page"
    ((FAIL++)) || true
  else
    echo "  PASS  No CDN p5 script link"
    ((PASS++)) || true
  fi
else
  echo "--- p5.js from CDN ---"
  check "p5.js CDN link"          "cdnjs\.cloudflare\.com.*p5"
fi

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
# Fail if a script src points at anything that is not http(s) — i.e. a local/relative file.
# Remote p5 links are handled by the block above: allowed in CDN mode, already failed
# in --vendored mode. Written with a POSIX character class rather than an escaped quote
# so the pattern survives shell quoting (the previous form did not parse).
if grep -qE "<script[^>]+src=[\"'][^h]" "$FILE" \
  || grep -qE "<script[^>]+src=[\"']h[^t]" "$FILE"; then
  echo "  FAIL  Local .js script src detected — page is not self-contained"
  ((FAIL++)) || true
else
  echo "  PASS  No local .js src references"
  ((PASS++)) || true
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
