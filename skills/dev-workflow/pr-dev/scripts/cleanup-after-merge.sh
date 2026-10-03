#!/usr/bin/env bash
# cleanup-after-merge.sh — sync default branch, remove worktree, prune refs.
# Worktree-aware: safe to run from inside a linked pr-dev worktree (never fails
# hard on checking out the default branch when the main worktree already holds
# it, and never tries to remove or delete the worktree/branch it stands in).
#
# Usage:
#   cleanup-after-merge.sh <PR_NUMBER>
#   cleanup-after-merge.sh -h | --help
#
# Steps:
#   1. cd to repo root
#   2. Sync default branch — checkout+pull only when it is not checked out elsewhere
#   3. Remove the worktree for this PR's branch (skip if it is the current dir)
#   4. Delete the remote branch on origin (if it still exists)
#   5. Delete the local branch (skip if it is the current branch)
#   6. git remote prune origin
#   7. Force-remove ghost refs via git branch -r -d origin/<branch>
#   8. Print git branch -a for verification
set -euo pipefail

usage() {
  sed -n '2,19p' "$0" | sed 's/^#[ ]\{0,1\}//'
  exit "${1:-0}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

VERBOSE=0
# --repo <owner/name> — pin the repository explicitly.
#
# WHY THIS EXISTS
#   Every `gh` call below resolves the repository from the CURRENT DIRECTORY.
#   That is invisible and silently wrong when the cwd is not the repo you mean:
#   running this against PR 102 from a sibling checkout returns *that* repo's
#   PR 102 — a real, plausible-looking, completely unrelated pull request. It
#   happened three times while developing this change, once returning a PR that
#   had been merged in July, which read as "already merged, nothing to do".
#
#   A wrong repo is not an error here, it is a different answer. So the fix is
#   to make the target statable rather than inferred. `gh` honours GH_REPO for
#   resolution, so exporting it once pins every call in this script — including
#   `gh api repos/{owner}/{repo}` — with no per-call change.
_pin_repo() {
  case "$1" in
    */*) : ;;
    *) printf 'error: --repo expects <owner>/<name>, got %s\n' "$1" >&2; exit 2 ;;
  esac
  export GH_REPO="$1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) _pin_repo "${2:-}"; shift 2;;
    --repo=*) _pin_repo "${1#--repo=}"; shift;;
    -v|--verbose) VERBOSE=1; shift;;
    *) PR="$1"; shift;;
  esac
done

PR="${PR:-}"
if [[ -z "$PR" ]]; then
  echo "ERROR: missing <PR_NUMBER>" >&2
  usage 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

BRANCH=$(gh pr view "$PR" --json headRefName --jq .headRefName)

# Resolve the repo's default branch dynamically — never a literal. Prefer the
# PR's own base ref (most accurate: it is the branch this PR actually merged
# into); otherwise the shared resolver, which reads origin/HEAD then gh and
# fails rather than guessing. A guessed name would make step 2 check out a
# branch that does not exist.
# shellcheck source=../../_shared/scripts/default-branch.sh
. "$SCRIPT_DIR/../../_shared/scripts/default-branch.sh"
DEFAULT_BRANCH=$(gh pr view "$PR" --json baseRefName --jq .baseRefName 2>/dev/null || true)
if [[ -z "$DEFAULT_BRANCH" ]]; then
  DEFAULT_BRANCH="$(resolve_default_branch "$REPO_ROOT")" || {
    echo "ERROR: cannot determine the default branch to sync — see the cause above." >&2
    exit 1
  }
fi

CUR_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# Which worktree (if any) currently has a given branch checked out.
worktree_of() {
  git worktree list --porcelain \
    | awk -v b="$1" '/^worktree /{p=$2} /^branch refs\/heads\//{if($2=="refs/heads/"b){print p; exit}}'
}
DEFAULT_WT=$(worktree_of "$DEFAULT_BRANCH")
WORKTREE_PATH=$(worktree_of "$BRANCH")

[[ "$VERBOSE" == 1 ]] && echo "BRANCH=$BRANCH DEFAULT_BRANCH=$DEFAULT_BRANCH CUR_BRANCH=$CUR_BRANCH REPO_ROOT=$REPO_ROOT DEFAULT_WT=$DEFAULT_WT WORKTREE_PATH=$WORKTREE_PATH" >&2

# --- Update the default branch without disrupting other worktrees --------------
# A linked worktree cannot check out the default branch while the main worktree
# holds it — git errors "already used by worktree". Only switch when it is safe.
git fetch --prune origin >/dev/null 2>&1 || true
if [[ "$CUR_BRANCH" == "$DEFAULT_BRANCH" ]]; then
  git pull --ff-only || true
elif [[ -n "$DEFAULT_WT" ]]; then
  echo "Note: '$DEFAULT_BRANCH' is checked out at $DEFAULT_WT — skipping checkout here (its owner can pull)."
else
  git checkout "$DEFAULT_BRANCH" && git pull --ff-only || true
fi

# --- Remove the PR branch's worktree (never the one we are standing in) ---------
if [[ -n "$WORKTREE_PATH" && -d "$WORKTREE_PATH" ]]; then
  if [[ "$WORKTREE_PATH" == "$REPO_ROOT" ]]; then
    echo "Note: the PR branch worktree is the current directory ($WORKTREE_PATH) — skipping self-removal; the session's worktree lifecycle reclaims it."
  else
    git worktree remove "$WORKTREE_PATH" || git worktree remove --force "$WORKTREE_PATH"
  fi
fi

# --- Delete the remote branch if it survived the merge --------------------------
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  git push origin --delete "$BRANCH"
fi

# --- Delete the local branch (cannot delete one that is checked out) ------------
if [[ "$CUR_BRANCH" == "$BRANCH" ]]; then
  echo "Note: '$BRANCH' is the current branch of this worktree — leaving it; it is removed with the worktree."
else
  git branch -D "$BRANCH" 2>/dev/null || true
fi
git remote prune origin
git branch -r -d "origin/$BRANCH" 2>/dev/null || true

echo "--- branches after cleanup ---"
git branch -a
