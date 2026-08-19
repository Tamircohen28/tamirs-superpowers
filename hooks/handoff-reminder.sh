#!/usr/bin/env bash
# handoff-reminder.sh — SessionEnd reminder to run switch-dev handoff from active worktrees.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

input="$(hook_read_stdin)"
cwd="$(echo "$input" | jq -r '.cwd // empty')"

in_worktree=false
case "$cwd" in
  */.claude/.worktrees/*|*/.cursor/.worktrees/*|*/.codex/.worktrees/*|*/.claude/worktrees/*)
    in_worktree=true
    ;;
esac

if [[ "$in_worktree" != true ]]; then
  echo '{"suppressOutput": true}'
  exit 0
fi

issue=""
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  issue="$(
    git -C "$cwd" log -10 --pretty=%B 2>/dev/null \
      | grep -Eo '(Closes|Fixes|Refs) #[0-9]+|#[0-9]+' \
      | grep -Eo '[0-9]+' \
      | head -1 \
      || true
  )"
fi

if [[ -n "$issue" ]]; then
  msg="Active worktree detected at ${cwd}. Before closing: push commits and run /switch-dev handoff #${issue} so another platform can resume."
else
  msg="Active worktree detected at ${cwd}. Before closing: push commits and run /switch-dev handoff #N (linked issue) so another platform can resume."
fi

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionEnd",
    "additionalContext": $(echo "$msg" | jq -Rs .)
  }
}
EOF
