#!/usr/bin/env bash
# cleanup-after-merge.sh — after a PR merged: sync the default branch, remove
# the PR branch's worktree, delete its remote and local branch, prune refs.
# Worktree-aware: safe to run from inside a linked pr-dev worktree (never fails
# hard on checking out the default branch when the main worktree already holds
# it, and never removes or deletes the worktree/branch it stands in).
#
# Usage:
#   cleanup-after-merge.sh [--repo <owner/name>] [-v] <PR_NUMBER>
#   cleanup-after-merge.sh -h | --help
#
# Nothing is deleted unless ALL of these are established from GitHub (audit
# finding D-1); a check that cannot be answered counts as failed:
#   - the PR is MERGED
#   - its head branch is neither the PR's base nor the repository's default
#   - the PR is not cross-repository (a fork head named like an origin branch)
#   - remote delete only: the branch is not protected on GitHub (the branch's
#     `protected` flag and the rulesets that apply to it), and the remote tip
#     holds no commit the merged PR did not carry
#
# A worktree holding uncommitted changes is never force-removed, and a local
# branch holding commits no remote ref and no merged PR contains is kept.
#
# Steps:
#   1. cd to repo root; read the PR and the repository's default branch
#   2. Sync default branch — checkout+pull only when it is not checked out elsewhere
#   3. Remove the worktree for this PR's branch (skip if it is the current dir)
#   4. Delete the remote branch on origin (if it still exists)
#   5. Delete the local branch (skip if it is the current branch)
#   6. git remote prune origin; drop a ghost origin/<branch> ref
#   7. Print git branch -a for verification
#
# Exit: 0 everything that existed was cleaned · 3 one or more deletions were
# skipped (each is listed under "skipped:") · 1 error · 2 usage.
set -euo pipefail

usage() {
  sed -n '2,34p' "$0" | sed 's/^#[ ]\{0,1\}//'
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
    -*) echo "ERROR: unknown flag: $1" >&2; usage 2;;
    *) PR="$1"; shift;;
  esac
done

PR="${PR:-}"
if [[ -z "$PR" ]]; then
  echo "ERROR: missing <PR_NUMBER>" >&2
  usage 2
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

SKIPPED=()
skip_note() { SKIPPED+=("$1"); echo "Skipped: $1"; }

# --- What the PR is -----------------------------------------------------------
PR_INFO=$(gh pr view "$PR" --json state,headRefName,headRefOid,baseRefName,isCrossRepository \
  --jq '[.state, .headRefName, .headRefOid, .baseRefName, (.isCrossRepository | tostring)] | @tsv' 2>/dev/null || true)
IFS=$'\t' read -r PR_STATE BRANCH HEAD_OID BASE_REF CROSS <<<"$PR_INFO" || true
if [[ -z "${BRANCH:-}" ]]; then
  echo "ERROR: cannot read PR $PR (gh pr view failed) — nothing deleted." >&2
  exit 1
fi

# Resolve the repo's default branch dynamically — never a literal: GitHub's
# answer first, then the shared resolver (origin/HEAD, then gh), which fails
# rather than guessing. The sync target is the PR's own base when known.
# shellcheck source=../../_shared/scripts/default-branch.sh
. "$SCRIPT_DIR/../../_shared/scripts/default-branch.sh"
REPO_INFO=$(gh repo view --json defaultBranchRef,nameWithOwner \
  --jq '[.defaultBranchRef.name, .nameWithOwner] | @tsv' 2>/dev/null || true)
IFS=$'\t' read -r REPO_DEFAULT OWNER_REPO <<<"$REPO_INFO" || true
OWNER_REPO="${OWNER_REPO:-${GH_REPO:-}}"
if [[ -z "${REPO_DEFAULT:-}" ]]; then
  REPO_DEFAULT="$(resolve_default_branch "$REPO_ROOT" 2>/dev/null)" || REPO_DEFAULT=""
fi
DEFAULT_BRANCH="${BASE_REF:-$REPO_DEFAULT}"
if [[ -z "$DEFAULT_BRANCH" ]]; then
  echo "ERROR: cannot determine the default branch to sync — nothing deleted." >&2
  exit 1
fi

# The D-1 checks every deletion needs. Unknown is a failure, never a pass.
WHY_NOT=""
if [[ "${PR_STATE:-}" != MERGED ]]; then
  WHY_NOT="PR #$PR is ${PR_STATE:-in an unknown state}, not MERGED"
elif [[ -z "${REPO_DEFAULT:-}" ]]; then
  WHY_NOT="the repository's default branch could not be read, so '$BRANCH' cannot be shown not to be it"
elif [[ "$BRANCH" == "$REPO_DEFAULT" || "$BRANCH" == "${BASE_REF:-}" ]]; then
  WHY_NOT="'$BRANCH' is the PR's base or the repository's default branch"
elif [[ "${CROSS:-}" != false ]]; then
  WHY_NOT="PR #$PR is cross-repository (head from a fork) or that could not be read — '$BRANCH' on origin is not its head"
fi

CUR_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# Which worktree (if any) currently has a given branch checked out.
worktree_of() {
  git worktree list --porcelain \
    | awk -v b="$1" '/^worktree /{p=substr($0, 10)} /^branch refs\/heads\//{if($2=="refs/heads/"b){print p; exit}}'
}
DEFAULT_WT=$(worktree_of "$DEFAULT_BRANCH")
WORKTREE_PATH=$(worktree_of "$BRANCH")

[[ "$VERBOSE" == 1 ]] && echo "BRANCH=$BRANCH STATE=${PR_STATE:-} BASE=${BASE_REF:-} REPO_DEFAULT=${REPO_DEFAULT:-} CROSS=${CROSS:-} CUR_BRANCH=$CUR_BRANCH REPO_ROOT=$REPO_ROOT DEFAULT_WT=$DEFAULT_WT WORKTREE_PATH=$WORKTREE_PATH" >&2

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
  CUR_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
fi

if [[ -n "$WHY_NOT" ]]; then
  skip_note "every deletion for '$BRANCH' — $WHY_NOT"
  echo "--- branches (nothing deleted) ---"
  git branch -a
  exit 3
fi

# contained_remotely <commit> — true when a remote-tracking ref holds it, or the
# merged PR's head does (a squash merge leaves the head reachable only there).
contained_remotely() {
  local c="$1"
  [[ -n "$(git for-each-ref --contains "$c" refs/remotes 2>/dev/null | head -n 1)" ]] && return 0
  [[ -n "${HEAD_OID:-}" ]] && git merge-base --is-ancestor "$c" "$HEAD_OID" 2>/dev/null && return 0
  return 1
}

# Measured before anything is deleted: once origin/<branch> is gone, a local
# branch whose only copy was there would read as unpushed.
LOCAL_TIP=$(git rev-parse --verify --quiet "refs/heads/$BRANCH^{commit}" 2>/dev/null || true)
LOCAL_UNMERGED=unknown
if [[ -n "$LOCAL_TIP" ]]; then
  if contained_remotely "$LOCAL_TIP"; then LOCAL_UNMERGED=false; else LOCAL_UNMERGED=true; fi
fi

# --- Remove the PR branch's worktree (never the one we are standing in) ---------
if [[ -n "$WORKTREE_PATH" && -d "$WORKTREE_PATH" ]]; then
  if [[ "$WORKTREE_PATH" == "$REPO_ROOT" ]]; then
    echo "Note: the PR branch worktree is the current directory ($WORKTREE_PATH) — skipping self-removal; the session's worktree lifecycle reclaims it."
  elif [[ -n "$(git -C "$WORKTREE_PATH" status --porcelain 2>/dev/null || echo unreadable)" ]]; then
    # Never --force over uncommitted changes: that would discard work.
    skip_note "worktree $WORKTREE_PATH — it holds uncommitted changes; commit or stash them, then re-run"
  else
    # A clean worktree: plain remove first. --force only when the plain form
    # refused a clean one (a submodule): on a clean, pushed worktree it discards
    # nothing.
    git worktree remove "$WORKTREE_PATH" 2>/dev/null \
      || git worktree remove --force "$WORKTREE_PATH" 2>/dev/null \
      || skip_note "worktree $WORKTREE_PATH — git worktree remove failed (locked?)"
  fi
fi

# --- Delete the remote branch if it survived the merge --------------------------
if git ls-remote --exit-code --heads origin "refs/heads/$BRANCH" >/dev/null 2>&1; then
  REMOTE_TIP=$(git ls-remote --heads origin "refs/heads/$BRANCH" 2>/dev/null | awk 'NR==1{print $1}')
  PROTECTED=unknown
  if [[ -n "$OWNER_REPO" ]]; then
    FLAG=$(gh api "repos/$OWNER_REPO/branches/$BRANCH" --jq '.protected' 2>/dev/null || true)
    RULES=$(gh api "repos/$OWNER_REPO/rules/branches/$BRANCH" --jq '[.[].type] | join(",")' 2>/dev/null) || RULES="?"
    if [[ "$FLAG" == true ]] || [[ ",$RULES," =~ ,(deletion|update|non_fast_forward), ]]; then
      PROTECTED=true
    elif [[ "$FLAG" == false && "$RULES" != "?" ]]; then
      PROTECTED=false
    fi
  fi
  UNMERGED=true
  if [[ -n "$REMOTE_TIP" && "$REMOTE_TIP" == "${HEAD_OID:-}" ]]; then
    UNMERGED=false
  elif [[ -n "$REMOTE_TIP" ]] && git cat-file -e "$REMOTE_TIP^{commit}" 2>/dev/null \
       && git merge-base --is-ancestor "$REMOTE_TIP" "refs/remotes/origin/$REPO_DEFAULT" 2>/dev/null; then
    UNMERGED=false
  fi
  if [[ "$PROTECTED" != false ]]; then
    skip_note "remote branch origin/$BRANCH — protected on GitHub, or its protection could not be read (branch flag '${FLAG:-unreadable}', rules '${RULES:-none}')"
  elif [[ "$UNMERGED" != false ]]; then
    skip_note "remote branch origin/$BRANCH — its tip ${REMOTE_TIP:0:12} holds commits PR #$PR did not merge"
  else
    if git push origin --delete "refs/heads/$BRANCH"; then
      git branch -r -d "origin/$BRANCH" >/dev/null 2>&1 || true
    else
      skip_note "remote branch origin/$BRANCH — git push --delete failed"
    fi
  fi
else
  # Already gone on origin: a ghost tracking ref is safe to drop.
  git branch -r -d "origin/$BRANCH" >/dev/null 2>&1 || true
fi

# --- Delete the local branch (cannot delete one that is checked out) ------------
if [[ -z "$LOCAL_TIP" ]]; then
  :
elif [[ "$CUR_BRANCH" == "$BRANCH" ]]; then
  echo "Note: '$BRANCH' is the current branch of this worktree — leaving it; it is removed with the worktree."
elif [[ -n "$(worktree_of "$BRANCH")" ]]; then
  skip_note "local branch $BRANCH — still checked out in a worktree that was kept"
elif [[ "$LOCAL_UNMERGED" != false ]]; then
  skip_note "local branch $BRANCH — it holds commits no remote ref and no merged PR contains"
else
  git branch -D "$BRANCH" >/dev/null 2>&1 || skip_note "local branch $BRANCH — git branch -D failed"
fi
git remote prune origin >/dev/null 2>&1 || true

echo "--- branches after cleanup ---"
git branch -a
if [[ "${#SKIPPED[@]}" -gt 0 ]]; then
  echo "skipped:"
  printf '  - %s\n' "${SKIPPED[@]}"
  exit 3
fi
exit 0
