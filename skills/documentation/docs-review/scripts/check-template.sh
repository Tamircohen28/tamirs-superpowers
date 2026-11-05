#!/usr/bin/env bash
# check-template.sh — per-file conformance check vs the documentation standard.
#
# Usage:
#   check-template.sh <FILE>
#   check-template.sh -h | --help
#
# Output (to stdout): JSON with audience, footer_required, footer_present,
#   mermaid_violations, mermaid_init_missing, doc_standards (the repo's own
#   checker's findings for this file), has_purpose_sentence,
#   link_text_uses_path_count.
#
# Why this script exists:
#   The standard is enforced by reviewers today; this script makes the most-
#   checked items deterministic so reviewers focus on judgment calls. Nothing
#   here names one repository: the audience comes from the audited repo's
#   config/docs/doc-standards.json when it has one (path-based otherwise), the
#   footer check is structural (two links under a --- rule), and when the repo
#   ships scripts/check-doc-standards.sh its verdict for this file is passed
#   through verbatim. The old version hardcoded another repository's issue URL,
#   so it could never pass anywhere else.
#
#   DOC_STANDARDS_REPORT=<file> — optional: the saved stdout of one whole-repo
#   `check-doc-standards.sh` run, consulted instead of re-running the checker
#   per file during a sweep.
set -uo pipefail

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi
if [[ -z "${1:-}" ]]; then echo "ERROR: missing FILE" >&2; usage 1; fi

FILE="${1#./}"
[[ -f "$FILE" ]] || { echo "ERROR: $FILE not found" >&2; exit 1; }

CONFIG="config/docs/doc-standards.json"
CHECKER="scripts/check-doc-standards.sh"

# `[[ == ]]` pattern matching lets `*` cross `/`, so `**/` and `**` both collapse to `*`.
glob_match() {
  local p="$1" pat="$2"
  pat="${pat//\*\*\//*}"
  pat="${pat//\*\*/*}"
  # shellcheck disable=SC2053
  [[ "$p" == $pat ]]
}

# Audience: the repo's config decides when it has one; a path-based guess otherwise.
AUDIENCE="other"
AUDIENCE_SOURCE="path"
if [[ -f "$CONFIG" ]] && jq empty "$CONFIG" 2>/dev/null; then
  AUDIENCE_SOURCE="$CONFIG"
  inc=0
  while IFS= read -r pat; do
    [[ -n "$pat" ]] || continue
    glob_match "$FILE" "$pat" && { inc=1; break; }
  done < <(jq -r '.human_facing.include[]?' "$CONFIG")
  if [[ $inc -eq 1 ]]; then
    AUDIENCE="human"
    while IFS= read -r pat; do
      [[ -n "$pat" ]] || continue
      glob_match "$FILE" "$pat" && { AUDIENCE="agent"; break; }
    done < <(jq -r '.human_facing.exclude[]?' "$CONFIG")
  else
    AUDIENCE="agent"
  fi
else
  case "$FILE" in
    docs/agent-guidelines/*|docs/changelog/*|docs/CHANGELOG.md) AUDIENCE="agent" ;;
    README.md|docs/*) AUDIENCE="human" ;;
    *) AUDIENCE="other" ;;
  esac
fi

# Footer: required on every human-facing doc. Present when the last non-blank
# line is one centred paragraph holding two links, under a --- rule (a license
# line such as `MIT © …` may sit between the rule and the footer).
FOOTER_REQUIRED=false
[[ "$AUDIENCE" == "human" ]] && FOOTER_REQUIRED=true
FOOTER_PRESENT=$(LC_ALL=C awk '
  NF { l3 = l2; l2 = l1; l1 = $0 }
  END {
    if (l1 ~ /^<p align="center">.*<a href=.*<a href=.*<\/p>$/ && (l2 == "---" || (l2 ~ /^[A-Za-z0-9.+-]+ © / && l3 == "---"))) print "true"; else print "false"
  }' "$FILE")

# Mermaid: per-node styling is forbidden, and every block opens with an init directive.
MERMAID_VIOLATIONS=$(awk '
  /^```mermaid/ { in_mermaid=1; next }
  /^```$/       { in_mermaid=0; next }
  in_mermaid && /(classDef|^[[:space:]]*class[[:space:]]|fill:|^[[:space:]]*style[[:space:]])/ { c++ }
  END { print c+0 }
' "$FILE")
MERMAID_INIT_MISSING=$(awk '
  /^```mermaid/ { expect=1; next }
  expect { if ($0 !~ /^%%\{init/) c++; expect=0 }
  END { print c+0 }
' "$FILE")

# The repo's own checker, when it ships one: its lines for this file, verbatim.
DOC_STD_CHECKER=null
DOC_STD_LINES=""
if [[ -n "${DOC_STANDARDS_REPORT:-}" && -f "$DOC_STANDARDS_REPORT" ]]; then
  DOC_STD_CHECKER="\"$CHECKER\""
  DOC_STD_LINES=$(awk -v f="$FILE:" 'index($0, f) == 1' "$DOC_STANDARDS_REPORT")
elif [[ -f "$CHECKER" ]]; then
  DOC_STD_CHECKER="\"$CHECKER\""
  DOC_STD_LINES=$(bash "$CHECKER" . 2>/dev/null | awk -v f="$FILE:" 'index($0, f) == 1')
fi
DOC_STD_JSON=$(printf '%s\n' "$DOC_STD_LINES" | jq -R . | jq -s 'map(select(length > 0))')

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
  --arg audience_source "$AUDIENCE_SOURCE" \
  --argjson footer_required "$FOOTER_REQUIRED" \
  --argjson footer "$FOOTER_PRESENT" \
  --argjson mermaid "$MERMAID_VIOLATIONS" \
  --argjson mermaid_init_missing "$MERMAID_INIT_MISSING" \
  --argjson doc_std_checker "$DOC_STD_CHECKER" \
  --argjson doc_std "$DOC_STD_JSON" \
  --argjson purpose "$HAS_PURPOSE" \
  --argjson link_text_uses_path "$LINK_TEXT_USES_PATH" \
  '{
    file: $file,
    audience: $audience,
    audience_source: $audience_source,
    footer_required: $footer_required,
    footer_present: $footer,
    mermaid_violations: $mermaid,
    mermaid_init_missing: $mermaid_init_missing,
    doc_standards: { checker: $doc_std_checker, violations: $doc_std },
    has_purpose_sentence: $purpose,
    link_text_uses_path_count: $link_text_uses_path
  }'
