#!/usr/bin/env bash
set -euo pipefail

# WorktreeRemove hook — remove agent worktrees in either layout.
#
# WHAT IT WILL REMOVE
#   <worktree root>/<repo>/<slug>                  (session, configured root)
#   ~/.claude/worktrees/<repo>/<slug>              (legacy global)
#   <repo>/.agent-worktrees/<objective>/<unit>     (objective model)
#
# WHAT IT WILL NOT REMOVE
#   Anything else — above all a main checkout. The path is classified before
#   anything is deleted, and an unrecognized shape is a no-op rather than a
#   best-effort `rm -rf`.
#
#   Nor anything it cannot VERIFY: the worktree's repository must resolve, the
#   path must be a linked worktree in that repository's `git worktree list`
#   (compared canonically, so a symlinked root cannot hide it), and
#   `git status` must succeed. Removal is `git worktree remove` and nothing
#   else — there is no `rm -rf` fallback. Before this, a failed status read as
#   "clean" and a worktree whose registration had broken was `rm -rf`ed with its
#   uncommitted work.
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
  session-global|legacy-global|objective-integration|objective-worker|objective-other) ;;
  *)
    # Not ours to delete. Say so rather than failing silently — a caller that
    # expected a removal should learn that nothing happened.
    printf 'WorktreeRemove: refusing to remove %s (classified as %s, not an agent worktree) — not removed\n' \
      "$worktree_path" "$kind" >&2
    exit 0
    ;;
esac

refuse() {
  printf 'WorktreeRemove: %s — not removed.\n' "$1" >&2
  exit 0
}

common="$(git -C "$worktree_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
[[ -n "$common" && -d "$common" ]] \
  || refuse "${worktree_path}: its repository cannot be found (broken registration)"
main_root="$(dirname "$common")"
is_linked_worktree_of "$main_root" "$worktree_path" \
  || refuse "${worktree_path} is not a registered linked worktree of ${main_root}"

if ! status="$(git -C "$worktree_path" status --porcelain 2>/dev/null)"; then
  refuse "${worktree_path}: git status failed, so its changes cannot be checked"
fi
if [[ "$force" != "true" && -n "$status" ]]; then
  refuse "${worktree_path} has uncommitted changes. Commit or pass force:true"
fi

if [[ "$force" == "true" ]]; then
  git -C "$main_root" worktree remove --force "$worktree_path" >&2 \
    || refuse "git worktree remove refused ${worktree_path}"
else
  git -C "$main_root" worktree remove "$worktree_path" >&2 \
    || refuse "git worktree remove refused ${worktree_path}"
fi
git -C "$main_root" worktree prune 2>/dev/null || true

exit 0
