#!/usr/bin/env bash
# parse-issue-resume.sh — extract Resume and Agent routing fields from a GitHub issue.
#
# Usage:
#   parse-issue-resume.sh <issue_number>
#   parse-issue-resume.sh -h | --help
#
# Output JSON with resume fields (empty string when missing).
set -euo pipefail

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

ISSUE="${1:-}"
if [[ -z "$ISSUE" ]]; then
  echo "ERROR: missing issue number" >&2
  usage 1
fi

ISSUE="${ISSUE#\#}"
BODY="$(gh issue view "$ISSUE" --json body,title,number,labels --jq '.body // ""')"

extract_field() {
  local key="$1"
  local line
  line="$(printf '%s\n' "$BODY" | awk -v k="$key" '
    $0 ~ "^- \\*\\*" k ":\\*\\*" {
      sub(/^- \*\*[^*]+:\*\* */, "")
      print
      exit
    }
  ')"
  echo "${line:-}"
}

RESUME_SECTION="$(printf '%s\n' "$BODY" | awk '/^## Resume/{flag=1; next} /^## /{if(flag) exit} flag{print}')"
AGENT_SECTION="$(printf '%s\n' "$BODY" | awk '/^## Agent routing/{flag=1; next} /^## /{if(flag) exit} flag{print}')"

OWNER="$(printf '%s\n' "$AGENT_SECTION" | awk -F': ' '/\*\*Owner:\*\*/{print $2; exit}')"
SUGGESTED="$(printf '%s\n' "$AGENT_SECTION" | awk -F': ' '/\*\*Suggested platform:\*\*/{print $2; exit}')"

LABELS="$(gh issue view "$ISSUE" --json labels --jq '[.labels[].name] | join(",")')"

jq -nc \
  --argjson number "$ISSUE" \
  --arg done_field "$(extract_field "Done")" \
  --arg next_field "$(extract_field "Next")" \
  --arg decisions "$(extract_field "Decisions")" \
  --arg blocked "$(extract_field "Blocked")" \
  --arg branch "$(extract_field "Branch")" \
  --arg worktree "$(extract_field "Worktree")" \
  --arg last_agent "$(extract_field "Last agent")" \
  --arg owner "${OWNER:-}" \
  --arg suggested_platform "${SUGGESTED:-}" \
  --arg labels "$LABELS" \
  --arg resume_section "$RESUME_SECTION" \
  '{
    number: ($number | tonumber),
    done: $done_field,
    next: $next_field,
    decisions: $decisions,
    blocked: $blocked,
    branch: $branch,
    worktree: $worktree,
    last_agent: $last_agent,
    owner: $owner,
    suggested_platform: $suggested_platform,
    labels: $labels,
    has_resume: ($resume_section | length > 0)
  }'
