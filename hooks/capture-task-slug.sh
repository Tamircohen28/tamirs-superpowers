#!/usr/bin/env bash
set -euo pipefail

# UserPromptSubmit — derive task slug from the first user prompt of the session.
# Creates or reuses a global worktree for git repos before edits begin.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktree-common.sh
source "${SCRIPT_DIR}/lib/worktree-common.sh"

input="$(cat)"
session_id="$(echo "$input" | jq -r '.session_id // empty')"
prompt="$(echo "$input" | jq -r '.prompt // empty')"
cwd="$(echo "$input" | jq -r '.cwd // empty')"

state="$(load_session_state "$session_id")"
prompt_count="$(echo "$state" | jq -r '.prompt_count // 0')"
task_slug="$(echo "$state" | jq -r '.task_slug // empty')"
now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ "$prompt_count" == "0" || -z "$task_slug" || "$task_slug" == "null" ]]; then
  task_slug="$(slugify_text "$prompt" 48)"
  if [[ -z "$task_slug" ]]; then
    short_id="${session_id:0:8}"
    task_slug="session-${short_id}"
  fi

  state="$(echo "$state" | jq \
    --arg task_slug "$task_slug" \
    --arg initial_prompt "$prompt" \
    --arg now "$now_iso" \
    --argjson prompt_count 1 \
    '. + {
      task_slug: $task_slug,
      initial_prompt: $initial_prompt,
      prompt_count: $prompt_count,
      created_at: (if .created_at == null then $now else .created_at end),
      updated_at: $now
    }')"
  save_session_state "$session_id" "$state"
else
  state="$(echo "$state" | jq --argjson prompt_count $((prompt_count + 1)) --arg now "$now_iso" \
    '. + {prompt_count: $prompt_count, updated_at: $now}')"
  save_session_state "$session_id" "$state"
fi

context_lines=()
session_title="$(echo "$state" | jq -r '.task_slug')"

if is_git_repo "$cwd"; then
  repo_root="$(repo_root_for "$cwd")"
  repo_name="$(repo_name_for "$cwd")"
  worktree_path="$(worktree_path_for "$repo_name" "$session_title")"

  if is_global_worktree_path "$cwd"; then
    session_files_dir="$(ensure_session_files_dir "${cwd}/session-files")"
  else
  if [[ ! -d "$worktree_path" ]]; then
    mkdir -p "${WORKTREE_ROOT}/${repo_name}"
    branch_name="$(branch_name_for "$session_title")"
    git -C "$repo_root" worktree add -B "$branch_name" "$worktree_path" "$(resolve_worktree_base_ref "$repo_root")" >&2 || true
    copy_worktreeinclude_files "$repo_root" "$worktree_path"
    write_worktree_env_local "$worktree_path" "$branch_name" 2>/dev/null || true
    # Install deps in the background so a slow npm/yarn install never blocks the hook timeout.
    ( run_worktree_post_setup "$worktree_path" >/dev/null 2>&1 & )
  fi
    session_files_dir="$(ensure_session_files_dir "${worktree_path}/session-files")"
  fi

  state="$(echo "$state" | jq \
    --arg repo_root "$repo_root" \
    --arg repo_name "$repo_name" \
    --arg worktree_path "$worktree_path" \
    --arg session_files_dir "$session_files_dir" \
  '. + {
    repo_root: $repo_root,
    repo_name: $repo_name,
    worktree_path: $worktree_path,
    session_files_dir: $session_files_dir
  }')"
  save_session_state "$session_id" "$state"

  if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
    append_env_exports "$CLAUDE_ENV_FILE" \
      "CLAUDE_TASK_SLUG=\"${session_title}\"" \
      "CLAUDE_WORKTREE_PATH=\"${worktree_path}\"" \
      "CLAUDE_SESSION_FILES_DIR=\"${session_files_dir}\"" \
      "CLAUDE_REPO_ROOT=\"${repo_root}\""
  fi

  if ! is_global_worktree_path "$cwd"; then
    context_lines+=("Git repo task detected. Dedicated worktree: ${worktree_path}")
    context_lines+=("Before Edit/Write, run: cd \"${worktree_path}\" or use EnterWorktree.")
    context_lines+=("Session artifacts (plans, reviews, investigations) go in: ${session_files_dir}")
    context_lines+=("Do NOT use repo .dev-files/ — use \$CLAUDE_SESSION_FILES_DIR instead.")
  fi
else
  short_id="${session_id:0:8}"
  session_slug="${session_title:-session-${short_id}}"
  session_dir="${HOME}/.claude/outputs/${session_slug}"
  session_files_dir="$(ensure_session_files_dir "${session_dir}/session-files")"
  sync_session_files_archive "$session_files_dir" "$session_slug"

  state="$(echo "$state" | jq \
    --arg session_slug "$session_slug" \
    --arg session_dir "$session_dir" \
    --arg session_files_dir "$session_files_dir" \
  '. + {
    session_slug: $session_slug,
    session_dir: $session_dir,
    session_files_dir: $session_files_dir
  }')"
  save_session_state "$session_id" "$state"

  if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
    append_env_exports "$CLAUDE_ENV_FILE" \
      "CLAUDE_SESSION_SLUG=\"${session_slug}\"" \
      "CLAUDE_OUTPUT_DIR=\"${session_dir}\"" \
      "CLAUDE_SESSION_FILES_DIR=\"${session_files_dir}\""
  fi

  context_lines+=("Non-repo session. Session files: ${session_files_dir}")
  context_lines+=("Archive copy: ${SESSION_FILES_ARCHIVE}/${session_slug}/")
fi

if ((${#context_lines[@]})); then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "sessionTitle": "${session_title}",
    "additionalContext": "$(printf '%s\n' "${context_lines[@]}" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')"
  }
}
EOF
else
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "sessionTitle": "${session_title}"
  }
}
EOF
fi
