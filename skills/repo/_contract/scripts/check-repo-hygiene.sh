#!/usr/bin/env bash
# check-repo-hygiene.sh — generalized repo hygiene signals (no employer-specific paths).
#
# Usage: check-repo-hygiene.sh <repo-root>
set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd || { echo '{"error":"not a directory"}'; exit 0; })"

misplaced_docs=0
ticket_named=0
empty_dirs=0
self_hosted_ci=0
root_shell_scripts=0

root_shell_scripts=$(find "$ROOT" -maxdepth 1 -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')

if [[ -d "$ROOT/docs" ]]; then
  misplaced_docs=$(find "$ROOT/docs" -maxdepth 1 -name '*.md' \
    ! -name 'README.md' ! -name 'CHANGELOG.md' ! -name 'CONTRIBUTING.md' \
    2>/dev/null | wc -l | tr -d ' ')
fi

ticket_named=$(find "$ROOT" \
  \( -name 'sched-*.md' -o -name '*-investigation-*.md' \) \
  -not -path '*/.git/*' -not -path '*/docs/engineering/*' 2>/dev/null | wc -l | tr -d ' ')

TMPDIRS=$(mktemp)
trap 'rm -f "$TMPDIRS"' EXIT
find "$ROOT" \
  \( -name .git -o -name node_modules -o -name dist -o -name __pycache__ -o -name .venv \) -prune \
  -o -type d -print 2>/dev/null | while read -r d; do
  rel="${d#"$ROOT"/}"
  [[ -z "$rel" ]] && continue
  count=$(find "$d" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
  sub=$(find "$d" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$count" -eq 0 && "$sub" -eq 0 ]]; then
    echo "$rel"
  fi
done > "$TMPDIRS"
empty_dirs=$(wc -l < "$TMPDIRS" | tr -d ' ')

if grep -rq 'runs-on:\s*\[self-hosted' "$ROOT/.github" 2>/dev/null; then
  self_hosted_ci=1
fi

jq -nc \
  --arg root "$ROOT" \
  --argjson misplaced_docs "$misplaced_docs" \
  --argjson ticket_named "$ticket_named" \
  --argjson empty_dirs "$empty_dirs" \
  --argjson self_hosted_ci "$self_hosted_ci" \
  --argjson root_shell_scripts "$root_shell_scripts" \
  '{root: $root, hygiene: {misplaced_top_level_docs: $misplaced_docs, ticket_named_outside_engineering: $ticket_named, empty_dirs: $empty_dirs, self_hosted_ci: ($self_hosted_ci == 1), root_shell_scripts: $root_shell_scripts}}'
