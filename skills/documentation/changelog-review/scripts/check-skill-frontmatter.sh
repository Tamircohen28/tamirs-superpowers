#!/usr/bin/env bash
# check-skill-frontmatter.sh - validate SKILL.md YAML frontmatter (full official field set).
#
# Usage:
#   check-skill-frontmatter.sh <SKILL_MD_FILE>
#   check-skill-frontmatter.sh -h | --help
#
# Output (to stdout): JSON with validation results.
#
# Exit codes:
#   0 = file parsed, output is valid JSON (check .passed for pass/fail)
#   1 = usage error or file not found
set -uo pipefail

usage() { sed -n '2,14p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi
if [[ -z "${1:-}" ]]; then echo "ERROR: missing SKILL_MD_FILE" >&2; usage 1; fi

FILE="$1"
[[ -f "$FILE" ]] || { echo "ERROR: $FILE not found" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../" && pwd)"
VALIDATOR="$REPO_ROOT/scripts/validate-skill-frontmatter.py"

if [[ ! -f "$VALIDATOR" ]]; then
  echo "ERROR: validator not found at $VALIDATOR" >&2
  exit 1
fi

RESULT="$(python3 "$VALIDATOR" --json "$FILE" 2>/dev/null | tail -1)"
PASSED="$(echo "$RESULT" | jq -r '.passed')"
ERRORS_JSON="$(echo "$RESULT" | jq -c '.errors')"

FINDINGS_JSON="[]"
if [[ "$PASSED" != "true" ]]; then
  FINDINGS_JSON="$(echo "$ERRORS_JSON" | jq -c '[.[] | {severity: "critical", field: "frontmatter", message: .}]')"
fi

NAME="$(awk '/^---$/{c++; next} c==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$FILE" | tr -d "'\"")"
DESCRIPTION_LEN="$(awk '/^---$/{c++; next} c==1 && /^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$FILE" | wc -c | tr -d ' ')"

jq -nc \
  --arg file "$FILE" \
  --arg name "${NAME:-}" \
  --argjson desc_len "${DESCRIPTION_LEN:-0}" \
  --argjson passed "$([[ "$PASSED" == "true" ]] && echo true || echo false)" \
  --argjson findings "$FINDINGS_JSON" \
  '{
    file: $file,
    fields: {
      name: $name,
      description_length: $desc_len
    },
    passed: $passed,
    findings: $findings
  }'
