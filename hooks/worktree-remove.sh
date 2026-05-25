#!/usr/bin/env bash
set -euo pipefail

# WorktreeRemove hook — remove global worktrees under ~/.claude/worktrees.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktree-common.sh
source "${SCRIPT_DIR}/lib/worktree-common.sh"

input="$(cat)"
worktree_path="$(echo "$input" | jq -r '.worktree_path // empty')"

if [[ -z "$worktree_path" || ! -d "$worktree_path" ]]; then
  exit 0
fi

if is_global_worktree_path "$worktree_path"; then
  repo_root="$(git -C "$worktree_path" rev-parse --show-toplevel 2>/dev/null || true)"
  main_root="$(git -C "$worktree_path" rev-parse --git-common-dir 2>/dev/null | xargs dirname 2>/dev/null || true)"

  if [[ -n "$main_root" && -d "$main_root" ]]; then
    git -C "$main_root" worktree remove "$worktree_path" --force 2>/dev/null \
      || rm -rf "$worktree_path"
  else
    rm -rf "$worktree_path"
  fi
fi

exit 0
