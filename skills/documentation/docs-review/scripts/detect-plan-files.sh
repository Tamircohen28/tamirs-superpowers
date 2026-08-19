#!/usr/bin/env bash
# detect-plan-files.sh — heuristic detector for stray plan/work files in docs/.
#
# Usage:
#   detect-plan-files.sh            # scan tracked files
#   detect-plan-files.sh --all      # also include untracked .md under docs/
#   detect-plan-files.sh -h | --help
#
# Output (to stdout): one suspect per line, JSON object with:
#   path, signals (filename, location, content, commit_msg), score
#
# Signals (each contributes to score):
#   filename  — matches *-plan.md, *-fix-plan.md, *-research.md, *-analysis.md,
#               *-review.md, *-audit.md, *-report.md, or has a YYYY-MM-DD prefix
#   location  — directly under docs/ (not a subdir)
#   unlinked  — not referenced from docs/README.md or any subdir README.md
#   commit    — last commit message contains 'wip', 'draft', 'save', 'plan'
#
# Score >= 2 = strong candidate. Confirm with the user before deletion.
#
# Why this script exists:
#   docs/ ends up collecting one-off plan dumps from agent sessions. Detecting
#   them by hand is slow and inconsistent; the heuristics here capture the
#   common signals so the human only confirms instead of hunting.
set -uo pipefail

usage() { sed -n '2,18p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

INCLUDE_UNTRACKED=0
[[ "${1:-}" == "--all" ]] && INCLUDE_UNTRACKED=1

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
cd "$REPO_ROOT" || { echo "cannot cd to repo root: $REPO_ROOT" >&2; exit 1; }

# 1. Inventory: tracked .md under docs/ + optionally untracked.
# Bash 3.2 portable — write to a temp file rather than mapfile.
CANDIDATES_FILE=$(mktemp -t pmplan.XXXXXX)
LINKED_FILE=$(mktemp -t pmplan.XXXXXX)
trap 'rm -f "$CANDIDATES_FILE" "$LINKED_FILE"' EXIT

git ls-files 'docs/**/*.md' 'docs/*.md' > "$CANDIDATES_FILE"
if [[ "$INCLUDE_UNTRACKED" == 1 ]]; then
  git ls-files --others --exclude-standard 'docs/**/*.md' 'docs/*.md' 2>/dev/null >> "$CANDIDATES_FILE" || true
fi

# 2. Files that ARE linked from any README in docs/.
find docs -name 'README.md' -type f -exec grep -hoE '\]\([^)]+\.md[^)]*\)' {} + 2>/dev/null \
  | sed 's/^](//;s/)$//' \
  | sed 's/#.*//' > "$LINKED_FILE" || true

is_linked() {
  local needle="$1"
  local needle_base
  needle_base=$(basename "$needle")
  while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    case "$needle" in
      *"$l"|"$l") return 0;;
    esac
    if [[ "$needle_base" == "$(basename "$l")" ]]; then
      return 0
    fi
  done < "$LINKED_FILE"
  return 1
}

PLAN_NAME_RE='(plan|fix-plan|research|analysis|review|audit|report)\.md$|^[0-9]{4}-[0-9]{2}-[0-9]{2}'

# 3. Score each candidate.
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  [[ "$(basename "$f")" == "README.md" ]] && continue

  signals_str=""
  score=0

  # filename signal
  if [[ "$(basename "$f")" =~ $PLAN_NAME_RE ]]; then
    signals_str="$signals_str filename"
    score=$((score + 1))
  fi

  # location signal — directly under docs/, not a subdir
  parent=$(dirname "$f")
  if [[ "$parent" == "docs" ]]; then
    signals_str="$signals_str location"
    score=$((score + 1))
  fi

  # unlinked signal
  if ! is_linked "$f"; then
    signals_str="$signals_str unlinked"
    score=$((score + 1))
  fi

  # commit msg signal
  msg=$(git log -n 1 --pretty=format:%s -- "$f" 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")
  if [[ "$msg" =~ (wip|draft|save|plan|scratch|temp) ]]; then
    signals_str="$signals_str commit"
    score=$((score + 1))
  fi

  if [[ "$score" -ge 2 ]]; then
    sj=$(printf '%s\n' $signals_str | jq -R -s 'split("\n") | map(select(length>0))')
    jq -nc \
      --arg path "$f" \
      --argjson signals "$sj" \
      --argjson score "$score" \
      '{path: $path, signals: $signals, score: $score}'
  fi
done < "$CANDIDATES_FILE"
