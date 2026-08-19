#!/usr/bin/env bash
set -euo pipefail

# WorktreeRemove hook — remove agent worktrees in either layout.
#
# WHAT IT WILL REMOVE
#   ~/.claude/worktrees/<repo>/<slug>              (legacy global)
#   <repo>/.agent-worktrees/<objective>/<unit>     (objective model)
#
# WHAT IT WILL NOT REMOVE
#   Anything else — above all a main checkout. The path is classified before
#   anything is deleted, and an unrecognized shape is a silent no-op rather than
#   a best-effort `rm -rf`.
#
#   A worktree with uncommitted changes is also left alone unless --force is
#   passed in the payload: an integrator has not yet cherry-picked from a worker
#   whose work is uncommitted, so deleting it destroys the only copy.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktree-common.sh
source "${SCRIPT_DIR}/lib/worktree-common.sh"
# shellcheck source=lib/objective-common.sh
source "${SCRIPT_DIR}/lib/objective-common.sh"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

input="$(hook_read_stdin)"
worktree_path="$(echo "$input" | jq -r '.worktree_path // empty')"
force="$(echo "$input" | jq -r '.force // false')"

if [[ -z "$worktree_path" || ! -d "$worktree_path" ]]; then
  exit 0
fi

kind="$(classify_worktree_path "$worktree_path")"
case "$kind" in
  legacy-global|objective-integration|objective-worker|objective-other) ;;
  *)
    # Not ours to delete. Say so rather than failing silently — a caller that
    # expected a removal should learn that nothing happened.
    printf 'WorktreeRemove: refusing to remove %s (classified as %s, not an agent worktree)\n' \
      "$worktree_path" "$kind" >&2
    exit 0
    ;;
esac

if [[ "$force" != "true" && -n "$(git -C "$worktree_path" status --porcelain 2>/dev/null || true)" ]]; then
  printf 'WorktreeRemove: %s has uncommitted changes — not removed. Commit or pass force:true.\n' \
    "$worktree_path" >&2
  exit 0
fi

main_root="$(git -C "$worktree_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | xargs dirname 2>/dev/null || true)"

if [[ -n "$main_root" && -d "$main_root" ]]; then
  git -C "$main_root" worktree remove "$worktree_path" --force 2>/dev/null \
    || rm -rf "$worktree_path"
  git -C "$main_root" worktree prune 2>/dev/null || true
else
  rm -rf "$worktree_path"
fi

exit 0
