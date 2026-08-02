#!/usr/bin/env bash
set -euo pipefail

# DirectoryAdded (Claude Code 2.1.219+) — fires after /add-dir (or the SDK
# register_repo_root request) registers a new working directory mid-session.
#
# The worktree policy in this plugin denies Edit/Write in a main checkout
# (enforce-worktree-edits.sh), but that denial only surfaces at the first edit
# attempt — often long after the directory was added. This hook moves the
# feedback to registration time: if the added directory is a main checkout
# rather than a registered session worktree, warn immediately and point at the
# worktree flow. Advisory only — never blocks the add.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktree-common.sh
source "${SCRIPT_DIR}/lib/worktree-common.sh"

input="$(cat)"
added_dir="$(echo "$input" | jq -r '.directory // .path // .added_dir // empty')"

# Unknown payload shape or missing dir — stay silent rather than guessing.
[[ -z "$added_dir" || "$added_dir" == "null" || ! -d "$added_dir" ]] && exit 0

# Not a git repo: nothing for the worktree policy to enforce there.
is_git_repo "$added_dir" || exit 0

# Session worktrees (ours or Claude Code's native layout) are exactly where
# edits belong — no warning needed.
if is_global_worktree_path "$added_dir" || is_registered_claude_worktree "$added_dir"; then
  exit 0
fi

repo_name="$(repo_name_for "$added_dir")"
printf '⚠️  Added directory %s is a main checkout. Repo edits there will be denied by the worktree policy — create/use a worktree under ~/.claude/worktrees/%s/<task-slug> (WorktreeCreate or EnterWorktree) before editing.\n' \
  "$added_dir" "$repo_name" >&2
exit 0
