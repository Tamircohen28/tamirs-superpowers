#!/usr/bin/env bash
# default-branch.sh — resolve a repository's default branch. Never guess one.
#
# A default branch is a *fact* about a repository, not a preference: this fleet
# is not uniform, and neither is the world. A literal `main` or `master` in a
# script does not fail loudly when it is wrong — it silently compares against a
# ref that does not exist, so `git diff origin/<wrong>` returns nothing and the
# guard it was protecting never fires. Stopping is strictly better.
#
# Resolution order (first answer wins):
#   1. git symbolic-ref --quiet --short refs/remotes/origin/HEAD   (no network)
#   2. gh repo view --json defaultBranchRef                        (when gh is
#      available and authenticated)
#   3. fail, naming which step could not answer and how to fix it
#
# There is deliberately no step 4. Do not add a literal fallback.
#
# Usage:
#   default-branch.sh [<repo_root>]        # print the name, or fail with a cause
#   source default-branch.sh               # defines resolve_default_branch()
#
# As a library:
#   resolve_default_branch [<repo_root>]   # stdout: branch name; rc 0
#                                          # stderr: named cause; rc 1
#
# Exit codes: 0 resolved · 1 unresolvable (cause on stderr) · 2 usage
#
# Validation tier: 0 (edit-time). Requires git. gh is optional.

# _db_is_branch_name <candidate> — a gh call that fails still prints a body on
# stdout (a 404 JSON document, for one), and `|| true` around it would hand that
# body back as a branch name. Require a single line that could actually be a ref.
_db_is_branch_name() {
  case "$1" in
    ''|null) return 1 ;;
    *[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  [ "$(printf '%s' "$1" | wc -l | tr -d ' ')" = "0" ]
}

# resolve_default_branch [<repo_root>]
# Prints the default branch name on stdout. On failure prints nothing on stdout,
# a single "default-branch: <cause>" line on stderr, and returns 1.
resolve_default_branch() {
  local root="${1:-.}" head name slug

  if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    echo "default-branch: '$root' is not inside a git repository" >&2
    return 1
  fi

  # 1. origin/HEAD — local, no network, correct whenever the remote was cloned
  #    or `git remote set-head origin --auto` has been run.
  head="$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  name="${head#origin/}"
  if [ -n "$name" ]; then
    printf '%s\n' "$name"
    return 0
  fi

  # 2. Ask GitHub. Only reachable when gh exists and is authenticated; every
  #    failure below falls through to the named error rather than to a literal.
  if command -v gh >/dev/null 2>&1; then
    if name="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null)" \
       && _db_is_branch_name "$name"; then
      printf '%s\n' "$name"
      return 0
    fi
    slug="$(git -C "$root" remote get-url origin 2>/dev/null \
      | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##' || true)"
    if [ -n "$slug" ]; then
      if name="$(gh api "repos/$slug" --jq '.default_branch' 2>/dev/null)" \
         && _db_is_branch_name "$name"; then
        printf '%s\n' "$name"
        return 0
      fi
    fi
  fi

  if ! git -C "$root" remote get-url origin >/dev/null 2>&1; then
    echo "default-branch: no 'origin' remote in '$root' — the default branch is a fact about a remote, and there is none to read" >&2
  else
    echo "default-branch: 'origin/HEAD' is unset in '$root' and gh could not answer — run 'git remote set-head origin --auto', or authenticate gh. No literal fallback is used, because a wrong branch name fails silently." >&2
  fi
  return 1
}

# Executed, not sourced.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  case "${1:-}" in
    -h|--help)
      sed -n '2,29p' "$0" | sed 's/^#[ ]\{0,1\}//'
      exit 0
      ;;
  esac
  if [ "$#" -gt 1 ]; then
    echo "usage: default-branch.sh [<repo_root>]" >&2
    exit 2
  fi
  resolve_default_branch "${1:-.}"
fi
