#!/usr/bin/env bash
# update-issue-resume.sh — update issue Resume block, agent label, and handoff comment.
#
# Usage:
#   update-issue-resume.sh <issue_number> <json_fields_file> [target_agent_label]
#
# json_fields_file JSON keys: done, next, decisions, blocked, branch, worktree, last_agent
# target_agent_label: agent:claude | agent:cursor | agent:codex | agent:any (default agent:any)
#
# Requires gh CLI. Exits 0 on success.
set -euo pipefail

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

ISSUE="${1:-}"
FIELDS_FILE="${2:-}"
TARGET_LABEL="${3:-agent:any}"

if [[ -z "$ISSUE" || -z "$FIELDS_FILE" || ! -f "$FIELDS_FILE" ]]; then
  echo "ERROR: usage: update-issue-resume.sh <issue> <json_fields_file> [target_agent_label]" >&2
  usage 1
fi

ISSUE="${ISSUE#\#}"
DONE="$(jq -r '.done // ""' "$FIELDS_FILE")"
NEXT="$(jq -r '.next // ""' "$FIELDS_FILE")"
DECISIONS="$(jq -r '.decisions // ""' "$FIELDS_FILE")"
BLOCKED="$(jq -r '.blocked // "none"' "$FIELDS_FILE")"
BRANCH="$(jq -r '.branch // ""' "$FIELDS_FILE")"
WORKTREE="$(jq -r '.worktree // ""' "$FIELDS_FILE")"
LAST_AGENT="$(jq -r '.last_agent // ""' "$FIELDS_FILE")"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

BODY="$(gh issue view "$ISSUE" --json body --jq '.body // ""')"

NEW_RESUME="$(cat <<EOF
## Resume
- **Done:** ${DONE}
- **Next:** ${NEXT}
- **Decisions:** ${DECISIONS}
- **Blocked:** ${BLOCKED}
- **Branch:** ${BRANCH}
- **Worktree:** ${WORKTREE}
- **Last agent:** ${LAST_AGENT} @ ${TIMESTAMP}
EOF
)"

RESUME_TMP="$(mktemp)"
printf '%s\n' "$NEW_RESUME" > "$RESUME_TMP"

NEW_BODY="$(python3 - "$BODY" "$RESUME_TMP" "$TARGET_LABEL" <<'PY'
import sys

body = sys.argv[1]
with open(sys.argv[2], encoding="utf-8") as f:
    new_resume = f.read().rstrip("\n")
target_label = sys.argv[3]

lines = body.splitlines()
out = []
in_resume = False
resume_done = False
in_agent = False

for line in lines:
    if line.startswith("## Resume"):
        if not resume_done:
            out.append(new_resume)
            resume_done = True
        in_resume = True
        continue
    if in_resume and line.startswith("## "):
        in_resume = False
    if in_resume:
        continue
    if line.startswith("## Agent routing"):
        in_agent = True
        out.append(line)
        continue
    if in_agent and line.strip().startswith("- **Owner:**"):
        out.append(f"- **Owner:** {target_label}")
        continue
    if in_agent and line.startswith("## "):
        in_agent = False
    out.append(line)

if not resume_done:
    out.extend(["", new_resume])

print("\n".join(out))
PY
)"

TMP_BODY="$(mktemp)"
printf '%s' "$NEW_BODY" > "$TMP_BODY"
gh issue edit "$ISSUE" --body-file "$TMP_BODY"
rm -f "$TMP_BODY" "$RESUME_TMP"

CURRENT_LABELS="$(gh issue view "$ISSUE" --json labels --jq '.labels[].name' | grep '^agent:' || true)"
for lbl in $CURRENT_LABELS; do
  gh issue edit "$ISSUE" --remove-label "$lbl" 2>/dev/null || true
done
if ! gh label list --json name --jq '.[].name' | grep -qx "$TARGET_LABEL"; then
  gh label create "$TARGET_LABEL" --description "Agent platform ownership" --color "1D76DB" 2>/dev/null || true
fi
gh issue edit "$ISSUE" --add-label "$TARGET_LABEL"

COMMENT="$(cat <<EOF
### Handoff @ ${TIMESTAMP}

**From:** ${LAST_AGENT}
**Branch:** \`${BRANCH}\`
**Worktree:** \`${WORKTREE}\`

**Next:** ${NEXT}

---
🤖 Handoff via tamirs-superpowers switch-dev
EOF
)"
gh issue comment "$ISSUE" --body "$COMMENT"

jq -nc \
  --argjson issue "$ISSUE" \
  --arg target_label "$TARGET_LABEL" \
  --arg timestamp "$TIMESTAMP" \
  '{issue: ($issue | tonumber), target_label: $target_label, timestamp: $timestamp, updated: true}'
