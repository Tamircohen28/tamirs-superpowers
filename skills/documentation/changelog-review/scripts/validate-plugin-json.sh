#!/usr/bin/env bash
# validate-plugin-json.sh - validate a Claude Code plugin.json for structural
# correctness and common misuse patterns caught by changelog-review Mode 3.
#
# Usage:
#   validate-plugin-json.sh <PLUGIN_JSON_FILE>
#   validate-plugin-json.sh -h | --help
#
# Output (to stdout): JSON with validation results and a findings array.
#
# Why this script exists:
#   plugin.json has a known footgun: statusLine must be an object
#   ({"type":"command","command":"..."}) not a string. This and other structural
#   checks are deterministic -- running them here frees the LLM to focus on
#   semantic review.
#
# Exit codes:
#   0 = file parsed, output is valid JSON (check .passed for pass/fail)
#   1 = usage error, file not found, or file is not valid JSON
set -uo pipefail

usage() { sed -n '2,16p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi
if [[ -z "${1:-}" ]]; then echo "ERROR: missing PLUGIN_JSON_FILE" >&2; usage 1; fi

FILE="$1"
[[ -f "$FILE" ]] || { echo "ERROR: $FILE not found" >&2; exit 1; }

# Validate JSON syntax first
if ! jq empty "$FILE" 2>/dev/null; then
  echo "ERROR: $FILE is not valid JSON" >&2
  exit 1
fi

FINDINGS=()
PASSED=true

# statusLine type check:
# statusLine must be an object with "type" and "command" keys, not a string.
STATUS_LINE_TYPE=$(jq -r 'if has("statusLine") then (.statusLine | type) else "absent" end' "$FILE")

if [[ "$STATUS_LINE_TYPE" == "string" ]]; then
  STATUS_LINE_VAL=$(jq -r '.statusLine' "$FILE")
  FINDINGS+=("{\"severity\":\"critical\",\"field\":\"statusLine\",\"message\":\"statusLine must be an object with type/command keys, not a string. Got: \\\"${STATUS_LINE_VAL}\\\"\"}")
  PASSED=false
elif [[ "$STATUS_LINE_TYPE" == "object" ]]; then
  # Object present -- check required sub-keys
  HAS_TYPE=$(jq -r 'if .statusLine | has("type") then "true" else "false" end' "$FILE")
  HAS_CMD=$(jq -r 'if .statusLine | has("command") then "true" else "false" end' "$FILE")
  if [[ "$HAS_TYPE" != "true" ]] || [[ "$HAS_CMD" != "true" ]]; then
    FINDINGS+=('{"severity":"critical","field":"statusLine","message":"statusLine object is missing required keys: type and/or command"}')
    PASSED=false
  fi
elif [[ "$STATUS_LINE_TYPE" == "absent" ]]; then
  FINDINGS+=('{"severity":"info","field":"statusLine","message":"statusLine is not set; the plugin will show no status indicator"}')
fi

# name present
HAS_NAME=$(jq -r 'has("name")' "$FILE")
if [[ "$HAS_NAME" != "true" ]]; then
  FINDINGS+=('{"severity":"critical","field":"name","message":"Missing required field: name"}')
  PASSED=false
fi

# version present and semver-shaped.
# SHAPE ONLY. Whether this version AGREES with the other manifests, the README badge and
# the platform-target files is not this script's business — plugin-version.json owns the
# consumer list and scripts/check-version-truth.sh validates it. Do not add cross-file
# version comparison here; that would create a second source of truth.
VERSION=$(jq -r '.version // ""' "$FILE")
if [[ -z "$VERSION" ]]; then
  FINDINGS+=('{"severity":"warning","field":"version","message":"Missing version field; use semver (e.g. 1.0.0)"}')
else
  if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then
    FINDINGS+=("{\"severity\":\"warning\",\"field\":\"version\",\"message\":\"version '${VERSION}' does not look like semver (MAJOR.MINOR.PATCH)\"}")
  fi
fi

# skills array type check
HAS_SKILLS=$(jq -r 'has("skills")' "$FILE")
if [[ "$HAS_SKILLS" == "true" ]]; then
  SKILLS_TYPE=$(jq -r '.skills | type' "$FILE")
  if [[ "$SKILLS_TYPE" != "array" ]]; then
    FINDINGS+=('{"severity":"critical","field":"skills","message":"skills must be an array"}')
    PASSED=false
  fi
fi

# Build findings JSON array
FINDINGS_JSON="["
for i in "${!FINDINGS[@]}"; do
  [[ $i -gt 0 ]] && FINDINGS_JSON+=","
  FINDINGS_JSON+="${FINDINGS[$i]}"
done
FINDINGS_JSON+="]"

# Extract summary fields
NAME=$(jq -r '.name // ""' "$FILE")
SKILLS_COUNT=$(jq -r 'if has("skills") then (.skills | length) else 0 end' "$FILE")

# Output
jq -nc \
  --arg file "$FILE" \
  --arg name "$NAME" \
  --arg version "${VERSION:-}" \
  --arg status_line_type "$STATUS_LINE_TYPE" \
  --argjson skills_count "$SKILLS_COUNT" \
  --argjson passed "$PASSED" \
  --argjson findings "$FINDINGS_JSON" \
  '{
    file: $file,
    fields: {
      name: $name,
      version: $version,
      statusLine_type: $status_line_type,
      skills_count: $skills_count
    },
    passed: $passed,
    findings: $findings
  }'
