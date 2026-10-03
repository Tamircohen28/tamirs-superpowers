#!/usr/bin/env bash
# file-freshness.sh — emit a freshness verdict for a markdown doc.
#
# Usage:
#   file-freshness.sh <FILE>
#   file-freshness.sh -h | --help
#
# Output (to stdout): JSON with last_doc_update, repo_changes_since, verdict.
#   verdict ∈ { fresh | review | stale }
#     fresh   — doc updated in the last 14 days OR no relevant changes since
#     review  — relevant files changed since the doc but ≤10 of them
#     stale   — relevant files changed since the doc AND >10 of them
#
# Why this script exists:
#   Eyeballing "is the doc stale" is unreliable. This script grounds the verdict
#   in two signals: (a) the doc's last commit date, and (b) the set of repo
#   files that changed since, intersected with files the doc references via
#   relative links. The intersection is what makes it useful — most repo
#   churn doesn't matter to most docs.
set -uo pipefail

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi
if [[ -z "${1:-}" ]]; then echo "ERROR: missing FILE" >&2; usage 1; fi

FILE="$1"
if [[ ! -f "$FILE" ]]; then
  echo "ERROR: $FILE not found" >&2
  exit 1
fi

# 1. Last commit that touched this doc.
LAST_DOC_SHA=$(git log -n 1 --pretty=format:%H -- "$FILE" 2>/dev/null || echo "")
LAST_DOC_DATE=""
if [[ -n "$LAST_DOC_SHA" ]]; then
  LAST_DOC_DATE=$(git log -n 1 --pretty=format:%cI "$LAST_DOC_SHA" 2>/dev/null || echo "")
fi

if [[ -z "$LAST_DOC_DATE" ]]; then
  jq -nc --arg file "$FILE" \
    '{file: $file, last_doc_update: null, repo_changes_since: [], verdict: "review", reason: "no git history for this file"}'
  exit 0
fi

# 2. Relative links the doc references — used to scope "what changed since" to
#    files the doc actually points at. (Bash-3-portable: write to a temp file.)
DOC_DIR=$(dirname "$FILE")
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

REFERENCED_FILE=$(mktemp -t pmreview.XXXXXX)
CHANGED_FILE=$(mktemp -t pmreview.XXXXXX)
RELEVANT_FILE=$(mktemp -t pmreview.XXXXXX)
trap 'rm -f "$REFERENCED_FILE" "$CHANGED_FILE" "$RELEVANT_FILE"' EXIT

grep -oE '\]\([^)]+\)' "$FILE" 2>/dev/null \
  | sed 's/^](//;s/)$//' \
  | grep -vE '^https?://|^mailto:|^#' \
  | sed 's/#.*//' \
  | sort -u \
  | while IFS= read -r link; do
      [[ -z "$link" ]] && continue
      target_dir="$DOC_DIR/$(dirname "$link")"
      if [[ -d "$target_dir" ]]; then
        abs=$(cd "$target_dir" && pwd)
        rel="${abs#"$REPO_ROOT"/}"
        printf '%s/%s\n' "$rel" "$(basename "$link")"
      fi
    done > "$REFERENCED_FILE"

# 3. Files changed since LAST_DOC_SHA, intersected with referenced paths.
git diff --name-only "${LAST_DOC_SHA}..HEAD" 2>/dev/null > "$CHANGED_FILE" || true
: > "$RELEVANT_FILE"
while IFS= read -r changed; do
  [[ -z "$changed" ]] && continue
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    case "$changed" in
      "$ref"|"$ref"/*) echo "$changed" >> "$RELEVANT_FILE"; break;;
    esac
  done < "$REFERENCED_FILE"
done < "$CHANGED_FILE"

RELEVANT_COUNT=$(wc -l < "$RELEVANT_FILE" | tr -d ' ')

# 4. Compute verdict.
NOW_EPOCH=$(date -u +%s)
DOC_EPOCH=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "${LAST_DOC_DATE%%[+-]*}" +%s 2>/dev/null \
            || date -u -d "$LAST_DOC_DATE" +%s 2>/dev/null \
            || echo "$NOW_EPOCH")
AGE_DAYS=$(( (NOW_EPOCH - DOC_EPOCH) / 86400 ))

if (( RELEVANT_COUNT == 0 )) || (( AGE_DAYS <= 14 )); then
  VERDICT="fresh"
elif (( RELEVANT_COUNT <= 10 )); then
  VERDICT="review"
else
  VERDICT="stale"
fi

# 5. Emit.
relevant_json=$(jq -R -s 'split("\n") | map(select(length>0))' < "$RELEVANT_FILE")
jq -nc \
  --arg file "$FILE" \
  --arg last "$LAST_DOC_DATE" \
  --argjson age "$AGE_DAYS" \
  --argjson relevant "$relevant_json" \
  --arg verdict "$VERDICT" \
  '{
    file: $file,
    last_doc_update: $last,
    age_days: $age,
    repo_changes_since: $relevant,
    relevant_count: ($relevant | length),
    verdict: $verdict
  }'
