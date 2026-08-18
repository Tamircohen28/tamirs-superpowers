#!/usr/bin/env bash
set -euo pipefail

# PreToolUse — block repo file edits outside ~/.claude/worktrees/<repo>/<task-slug>.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktree-common.sh
source "${SCRIPT_DIR}/lib/worktree-common.sh"
# shellcheck source=lib/objective-common.sh
source "${SCRIPT_DIR}/lib/objective-common.sh"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

input="$(hook_read_stdin)"
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

# The Claude config directory is version-controlled for backup, not a project
# checkout. Editing settings, memory, or agent definitions there is machine
# housekeeping, so it must never be forced through a worktree.
claude_config_root() {
  local root="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
  printf '%s' "${root%/}"
}

is_claude_config_path() {
  local path="${1%/}" root
  root="$(claude_config_root)"
  [[ -n "$root" && ( "$path" == "$root" || "$path" == "${root}/"* ) ]]
}

# Walk up to the nearest directory that exists — a Write may target a file in a
# directory that has not been created yet.
nearest_existing_dir() {
  local d="$1"
  while [[ -n "$d" && "$d" != "/" && "$d" != "." && ! -d "$d" ]]; do
    d="$(dirname "$d")"
  done
  printf '%s' "$d"
}

# Judge the FILE being edited, not the session cwd. An incidental `cd` into an
# unrelated repo — reading a config file, inspecting a checkout — used to arm
# the guard for every subsequent edit, including edits outside that repo.
file_path="$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')"
target_dir=""
if [[ -n "$file_path" && "$file_path" != "null" ]]; then
  target_dir="$(nearest_existing_dir "$(dirname "$file_path")")"
fi
if [[ -z "$target_dir" || ! -d "$target_dir" ]]; then
  target_dir="$cwd"
fi

if [[ -z "$target_dir" ]]; then
  hook_allow
fi

if is_claude_config_path "$target_dir"; then
  hook_allow
fi

if ! is_git_repo "$target_dir"; then
  hook_allow
fi

if is_global_worktree_path "$target_dir"; then
  hook_allow
fi

# Any registered session worktree is compliant — including Claude Code's native
# <repo>/.claude/worktrees/<name> layout on a claude/* branch. Never deny based
# on a path rebuilt from session state; the state slug can be stale or mangled.
if is_registered_claude_worktree "$target_dir"; then
  hook_allow
fi

# Every agent workspace shape is compliant, old and new alike:
#
#   objective-integration  .agent-worktrees/<objective>/integration
#   objective-worker       .agent-worktrees/<objective>/task-NNN
#   legacy-platform        .claude/.worktrees, .cursor/.worktrees, .codex/.worktrees
#   legacy-global          ~/.claude/worktrees/<repo>/<slug>
#   native-claude          <repo>/.claude/worktrees/<name>
#
# The legacy shapes are listed deliberately. This hook predates the objective
# model, and a worker or integrator whose worktree it did not recognize would be
# denied every Edit — the work would have nowhere legal to go. Recognizing a
# layout is not endorsing it: nothing here CREATES a platform-shaped path.
workspace_kind="$(classify_worktree_path "$target_dir")"
case "$workspace_kind" in
  objective-integration|objective-worker|objective-other|legacy-platform|legacy-global|native-claude)
    hook_allow
    ;;
esac

repo_root="$(repo_root_for "$target_dir")"
repo_name="$(repo_name_for "$target_dir")"
state="$(load_session_state "$session_id")"
# Re-slugify on read: state files written before slugify_text stripped newlines
# can carry multi-line slugs/paths that would mangle the suggested worktree.
task_slug="$(slugify_text "$(echo "$state" | jq -r '.task_slug // empty')" 48)"
worktree_path="$(echo "$state" | jq -r '.worktree_path // empty')"
case "$worktree_path" in *$'\n'*) worktree_path="" ;; esac

if [[ -z "$worktree_path" || "$worktree_path" == "null" ]]; then
  if [[ -n "$task_slug" && "$task_slug" != "null" ]]; then
    worktree_path="$(worktree_path_for "$repo_name" "$task_slug")"
  fi
fi

# An active objective changes the remedy, not the verdict: the main checkout is
# still off limits, but the correct destination is a worker/integration worktree
# the orchestrator already owns — NOT a fresh session worktree.
objective_id="$(active_objective_id "$target_dir" 2>/dev/null || true)"

if [[ -n "$objective_id" ]]; then
  reason="Repo edits must happen in an objective worktree, not the main checkout (${repo_root}). Objective '${objective_id}' is active: work in $(agent_worktree_root "$repo_root")/${objective_id}/task-NNN (worker) or .../integration (integrator). Ask the orchestrator which one is yours — do not create a new worktree."
else
  reason="Repo edits must happen in a dedicated worktree under ~/.claude/worktrees/${repo_name}/<task-slug>, not the main checkout (${repo_root})."
  if [[ -n "$worktree_path" && "$worktree_path" != "null" ]]; then
    reason="${reason} Use: cd \"${worktree_path}\" or EnterWorktree before editing."
  else
    reason="${reason} Submit your task prompt first so the worktree slug is derived from it, then cd into the worktree."
  fi
fi

hook_deny "$reason"
