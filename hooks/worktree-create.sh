#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktree-common.sh
source "${SCRIPT_DIR}/lib/worktree-common.sh"

input="$(cat)"
session_id="$(echo "$input" | jq -r '.session_id // empty')"
requested_name="$(echo "$input" | jq -r '.name // empty')"
cwd="$(echo "$input" | jq -r '.cwd // empty')"

if [[ -z "$cwd" ]]; then
  echo "WorktreeCreate: missing cwd" >&2
  exit 1
fi
if ! is_git_repo "$cwd"; then
  echo "WorktreeCreate: not a git repository: ${cwd}" >&2
  exit 1
fi

repo_root="$(repo_root_for "$cwd")"
repo_name="$(repo_name_for "$cwd")"

state="$(load_session_state "$session_id")"
# Re-slugify on read — state files poisoned with multi-line slugs self-heal.
task_slug="$(slugify_text "$(echo "$state" | jq -r '.task_slug // empty')" 48)"

if [[ -z "$task_slug" || "$task_slug" == "null" ]]; then
  task_slug="$(slugify_text "$requested_name" 48)"
fi

if [[ -z "$task_slug" ]]; then
  echo "WorktreeCreate: could not derive task slug" >&2
  exit 1
fi

worktree_path="$(worktree_path_for "$repo_name" "$task_slug")"
branch_name="$(branch_name_for "$task_slug")"
session_files_dir="$(ensure_session_files_dir "${worktree_path}/session-files")"

mkdir -p "${WORKTREE_ROOT}/${repo_name}"

if [[ -d "$worktree_path" ]]; then
  if ! git -C "$repo_root" worktree list --porcelain | awk -v p="$worktree_path" '/^worktree /{if($2==p) found=1} END{exit !found}'; then
    rm -rf "$worktree_path"
    git -C "$repo_root" worktree add -B "$branch_name" "$worktree_path" "$(resolve_worktree_base_ref "$repo_root")" >&2
  fi
else
  git -C "$repo_root" worktree add -B "$branch_name" "$worktree_path" "$(resolve_worktree_base_ref "$repo_root")" >&2
fi

copy_worktreeinclude_files "$repo_root" "$worktree_path"
write_worktree_env_local "$worktree_path" "$branch_name" 2>/dev/null || true
# Install deps in the background so a slow npm/yarn install never blocks the hook timeout.
( run_worktree_post_setup "$worktree_path" >/dev/null 2>&1 & )

now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
state="$(echo "$state" | jq \
  --arg session_id "$session_id" \
  --arg repo_root "$repo_root" \
  --arg repo_name "$repo_name" \
  --arg task_slug "$task_slug" \
  --arg worktree_path "$worktree_path" \
  --arg session_files_dir "$session_files_dir" \
  --arg branch_name "$branch_name" \
  --arg now "$now_iso" \
  '. + {
    session_id: $session_id,
    repo_root: $repo_root,
    repo_name: $repo_name,
    task_slug: $task_slug,
    worktree_path: $worktree_path,
    session_files_dir: $session_files_dir,
    branch_name: $branch_name,
    updated_at: $now
  } | if .created_at == null then .created_at = $now else . end')"

save_session_state "$session_id" "$state"
echo "$worktree_path"
