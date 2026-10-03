#!/usr/bin/env bash
# check-template.sh — per-file conformance check vs documentation-standards.md.
#
# Usage:
#   check-template.sh <FILE>
#   check-template.sh -h | --help
#
# Output (to stdout): JSON with audience, footer_present, mermaid_violations,
#   has_purpose_sentence, link_text_uses_path.
#
# Why this script exists:
#   The standards rule is enforced by reviewers today; this script makes the
#   most-checked items deterministic so reviewers focus on judgment calls.
set -uo pipefail

usage() { sed -n '2,12p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi
if [[ -z "${1:-}" ]]; then echo "ERROR: missing FILE" >&2; usage 1; fi

FILE="$1"
[[ -f "$FILE" ]] || { echo "ERROR: $FILE not found" >&2; exit 1; }

# Audience inference (path-based; user content under user/, eng under engineering/).
case "$FILE" in
  docs/user/*) AUDIENCE="user" ;;
  docs/engineering/*) AUDIENCE="engineering" ;;
  README.md|docs/README.md) AUDIENCE="root" ;;
  docs/*) AUDIENCE="top-level" ;;
  *) AUDIENCE="other" ;;
esac

# Footer check — only required for docs/user/**. For non-user docs we emit
# false (not null) so jq --argjson never sees a literal null.
FOOTER_PRESENT=false
FOOTER_REQUIRED=false
if [[ "$AUDIENCE" == "user" ]]; then
  FOOTER_REQUIRED=true
  if grep -q 'github.com/anthropics/production-master/issues' "$FILE" \
     && grep -qi 'slack' "$FILE" \
     && grep -q 'badge' "$FILE"; then
    FOOTER_PRESENT=true
  fi
fi

# Mermaid violations: classDef / class / fill: / style — forbidden per docs std.
MERMAID_VIOLATIONS=$(awk '
  /^```mermaid/ { in_mermaid=1; next }
  /^```$/       { in_mermaid=0; next }
  in_mermaid && /(classDef|^[[:space:]]*class[[:space:]]|fill:|^[[:space:]]*style[[:space:]])/ { c++ }
  END { print c+0 }
' "$FILE")

# Purpose sentence: first non-heading non-empty line should look like a one-line purpose.
PURPOSE_LINE=$(awk '
  NR==1 && /^---$/ { in_fm=1; next }
  in_fm && /^---$/ { in_fm=0; next }
  in_fm { next }
  /^#/ { next }
  /^[[:space:]]*$/ { next }
  { print; exit }
' "$FILE")
HAS_PURPOSE=false
if [[ -n "$PURPOSE_LINE" ]] && (( ${#PURPOSE_LINE} >= 20 )) && (( ${#PURPOSE_LINE} <= 300 )); then
  HAS_PURPOSE=true
fi

# Link text that's a raw path (e.g. [docs/user/foo.md](docs/user/foo.md)).
# grep -c exits non-zero when count is 0; use || true to keep stdout to one line.
LINK_TEXT_USES_PATH=$(grep -cE '\[[^]]*/[^]]*\.md\]\([^)]+\)' "$FILE" 2>/dev/null || true)
LINK_TEXT_USES_PATH=${LINK_TEXT_USES_PATH:-0}

jq -nc \
  --arg file "$FILE" \
  --arg audience "$AUDIENCE" \
  --argjson footer_required "$FOOTER_REQUIRED" \
  --argjson footer "$FOOTER_PRESENT" \
  --argjson mermaid "$MERMAID_VIOLATIONS" \
  --argjson purpose "$HAS_PURPOSE" \
  --argjson link_text_uses_path "$LINK_TEXT_USES_PATH" \
  '{
    file: $file,
    audience: $audience,
    footer_required: $footer_required,
    footer_present: $footer,
    mermaid_violations: $mermaid,
    has_purpose_sentence: $purpose,
    link_text_uses_path_count: $link_text_uses_path
  }'
