#!/usr/bin/env bash
# cleanup-after-merge.sh — return to repo root, pull master, remove worktree, prune refs.
#
# Usage:
#   cleanup-after-merge.sh <PR_NUMBER>
#   cleanup-after-merge.sh -h | --help
#
# Steps:
#   1. cd to repo root
#   2. git checkout master && git pull
#   3. Remove the worktree for this PR's branch (if any)
#   4. Delete the local branch
#   5. git remote prune origin
#   6. Force-remove ghost refs via git branch -r -d origin/<branch>
#   7. Print git branch -a for verification
set -euo pipefail

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

VERBOSE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) VERBOSE=1; shift;;
    *) PR="$1"; shift;;
  esac
done

PR="${PR:-}"
if [[ -z "$PR" ]]; then
  echo "ERROR: missing <PR_NUMBER>" >&2
  usage 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

BRANCH=$(gh pr view "$PR" --json headRefName --jq .headRefName)

# Resolve the repo's default branch dynamically — supports both `master` and `main`.
# Prefer the PR's base ref (most accurate); fall back to gh repo view; final fall back
# to `master` for offline / unauthenticated environments.
DEFAULT_BRANCH=$(gh pr view "$PR" --json baseRefName --jq .baseRefName 2>/dev/null || true)
if [[ -z "$DEFAULT_BRANCH" ]]; then
  DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || true)
fi
DEFAULT_BRANCH="${DEFAULT_BRANCH:-master}"

[[ "$VERBOSE" == 1 ]] && echo "BRANCH=$BRANCH DEFAULT_BRANCH=$DEFAULT_BRANCH" >&2

git checkout "$DEFAULT_BRANCH"
git pull --ff-only

WORKTREE_PATH=$(git worktree list --porcelain | awk -v b="$BRANCH" '/^worktree /{p=$2} /^branch refs\/heads\//{if($2=="refs/heads/"b){print p; exit}}')
if [[ -n "$WORKTREE_PATH" && -d "$WORKTREE_PATH" ]]; then
  git worktree remove "$WORKTREE_PATH" || git worktree remove --force "$WORKTREE_PATH"
fi

git branch -D "$BRANCH" 2>/dev/null || true
git remote prune origin
git branch -r -d "origin/$BRANCH" 2>/dev/null || true

echo "--- branches after cleanup ---"
git branch -a
