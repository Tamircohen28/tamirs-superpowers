#!/usr/bin/env bash
set -euo pipefail

# PreToolUse — block repo file edits outside ~/.claude/worktrees/<repo>/<task-slug>.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktree-common.sh
source "${SCRIPT_DIR}/lib/worktree-common.sh"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

input="$(cat)"
hook_detect_platform "$input"
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"
session_id="$(echo "$input" | jq -r '.session_id // .conversation_id // empty')"
cwd="$(echo "$input" | jq -r '.cwd // empty')"
if [[ -z "$cwd" ]]; then
  cwd="$(echo "$input" | jq -r '.workspace_roots[0] // empty')"
fi

case "$tool_name" in
  Edit|Write|MultiEdit|NotebookEdit|StrReplace) ;;
  *) hook_allow ;;
esac

if [[ -z "$cwd" ]]; then
  hook_allow
fi
if ! is_git_repo "$cwd"; then
  hook_allow
fi

if is_global_worktree_path "$cwd"; then
  hook_allow
fi

repo_root="$(repo_root_for "$cwd")"

file_path="$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')"
if [[ -n "$file_path" && "$file_path" != "null" ]]; then
  # Only enforce if the file being edited is inside this repo
  case "$file_path" in
    "$repo_root"/*) ;;  # inside repo — fall through to deny
    *) hook_allow ;;    # outside repo — allow
  esac
fi

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

hook_deny "$reason"
