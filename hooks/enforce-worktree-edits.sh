#!/usr/bin/env bash
set -euo pipefail

# PreToolUse — block repo file edits outside ~/.claude/worktrees/<repo>/<task-slug>.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktree-common.sh
source "${SCRIPT_DIR}/lib/worktree-common.sh"

input="$(cat)"
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"
session_id="$(echo "$input" | jq -r '.session_id // empty')"
cwd="$(echo "$input" | jq -r '.cwd // empty')"

case "$tool_name" in
  Edit|Write|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

if [[ -z "$cwd" ]]; then
  exit 0
fi
if ! is_git_repo "$cwd"; then
  exit 0
fi

if is_global_worktree_path "$cwd"; then
  exit 0
fi

repo_root="$(repo_root_for "$cwd")"
repo_name="$(repo_name_for "$cwd")"
state="$(load_session_state "$session_id")"
task_slug="$(echo "$state" | jq -r '.task_slug // empty')"
worktree_path="$(echo "$state" | jq -r '.worktree_path // empty')"

if [[ -z "$worktree_path" || "$worktree_path" == "null" ]]; then
  if [[ -n "$task_slug" && "$task_slug" != "null" ]]; then
    worktree_path="$(worktree_path_for "$repo_name" "$task_slug")"
  fi
fi

reason="Repo edits must happen in a dedicated worktree under ~/.claude/worktrees/${repo_name}/<task-slug>, not the main checkout (${repo_root})."
if [[ -n "$worktree_path" && "$worktree_path" != "null" ]]; then
  reason="${reason} Use: cd \"${worktree_path}\" or EnterWorktree before editing."
else
  reason="${reason} Submit your task prompt first so the worktree slug is derived from it, then cd into the worktree."
fi

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": $(echo "$reason" | jq -Rs .)
  }
}
EOF
