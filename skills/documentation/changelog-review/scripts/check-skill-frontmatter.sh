#!/usr/bin/env bash
# check-skill-frontmatter.sh - validate SKILL.md YAML frontmatter for required
# fields and common Claude Code misuse patterns.
#
# Usage:
#   check-skill-frontmatter.sh <SKILL_MD_FILE>
#   check-skill-frontmatter.sh -h | --help
#
# Output (to stdout): JSON with validation results per field and a findings array.
#
# Why this script exists:
#   changelog-review Mode 3 checks frontmatter correctness. This script makes
#   the deterministic checks (field presence, type mismatches, constraint
#   violations) fast and consistent, so the LLM can focus on judgment calls.
#
# Exit codes:
#   0 = file parsed, output is valid JSON (check .passed for pass/fail)
#   1 = usage error or file not found
set -uo pipefail

usage() { sed -n '2,15p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi
if [[ -z "${1:-}" ]]; then echo "ERROR: missing SKILL_MD_FILE" >&2; usage 1; fi

FILE="$1"
[[ -f "$FILE" ]] || { echo "ERROR: $FILE not found" >&2; exit 1; }

# Extract YAML frontmatter (between the first two "---" lines).
FRONTMATTER=$(awk '/^---$/{if(++n==1){p=1;next}if(n==2){exit}} p' "$FILE")

# Field extraction helpers
get_field() {
  local key="$1"
  echo "$FRONTMATTER" | grep -E "^${key}:" | head -1 | sed "s/^${key}:[[:space:]]*//" | tr -d '"'
}

field_exists() {
  echo "$FRONTMATTER" | grep -qE "^${1}:"
}

# Extract fields
NAME=$(get_field "name")
DESCRIPTION=$(get_field "description")
USER_INVOCABLE=$(get_field "user-invocable")
DISABLE_MODEL=$(get_field "disable-model-invocation")
UPDATED_DATE=$(get_field "updated-date")

# allowed-tools: collect all indented list items under the key
ALLOWED_TOOLS=$(awk '/^allowed-tools:/{p=1;next} p && /^[[:space:]]+-/{print} p && /^[^[:space:]-]/{exit}' "$FILE")

FINDINGS=()
PASSED=true

# Required field: name
if ! field_exists "name" || [[ -z "$NAME" ]]; then
  FINDINGS+=('{"severity":"critical","field":"name","message":"Missing required field: name"}')
  PASSED=false
fi

# Required field: description
if ! field_exists "description" || [[ -z "$DESCRIPTION" ]]; then
  FINDINGS+=('{"severity":"critical","field":"description","message":"Missing required field: description"}')
  PASSED=false
else
  DESC_LEN=${#DESCRIPTION}
  if (( DESC_LEN > 500 )); then
    FINDINGS+=("{\"severity\":\"warning\",\"field\":\"description\",\"message\":\"Description is ${DESC_LEN} chars; keep under 500 for marketplace display\"}")
  fi
fi

# Internal-only consistency check:
# Per CLAUDE.md: user-invocable: false should be paired with disable-model-invocation: true
if [[ "$USER_INVOCABLE" == "false" ]] && [[ "$DISABLE_MODEL" != "true" ]]; then
  FINDINGS+=('{"severity":"warning","field":"disable-model-invocation","message":"user-invocable: false should be paired with disable-model-invocation: true to prevent auto-trigger"}')
fi

# allowed-tools present
if ! field_exists "allowed-tools" || [[ -z "$ALLOWED_TOOLS" ]]; then
  FINDINGS+=('{"severity":"warning","field":"allowed-tools","message":"No allowed-tools list found; the skill may be denied tool access at runtime"}')
fi

# updated-date present
if ! field_exists "updated-date" || [[ -z "$UPDATED_DATE" ]]; then
  FINDINGS+=('{"severity":"info","field":"metadata.updated-date","message":"No updated-date in metadata; add one to track freshness"}')
fi

# Build findings JSON array
FINDINGS_JSON="["
for i in "${!FINDINGS[@]}"; do
  [[ $i -gt 0 ]] && FINDINGS_JSON+=","
  FINDINGS_JSON+="${FINDINGS[$i]}"
done
FINDINGS_JSON+="]"

DESC_LEN=${#DESCRIPTION}

# Output
jq -nc \
  --arg file "$FILE" \
  --arg name "$NAME" \
  --argjson desc_len "$DESC_LEN" \
  --arg user_invocable "${USER_INVOCABLE:-not-set}" \
  --arg disable_model "${DISABLE_MODEL:-not-set}" \
  --arg updated_date "${UPDATED_DATE:-not-set}" \
  --argjson passed "$PASSED" \
  --argjson findings "$FINDINGS_JSON" \
  '{
    file: $file,
    fields: {
      name: $name,
      description_length: $desc_len,
      user_invocable: $user_invocable,
      disable_model_invocation: $disable_model,
      updated_date: $updated_date
    },
    passed: $passed,
    findings: $findings
  }'
