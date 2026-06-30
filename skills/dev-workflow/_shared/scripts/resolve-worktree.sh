#!/usr/bin/env bash
# resolve-worktree.sh — create or resume a platform-scoped git worktree.
#
# Usage:
#   resolve-worktree.sh <repo_root> <branch_name> [worktree_slug]
#   resolve-worktree.sh -h | --help
#
# Output JSON:
#   { platform, worktree_path, branch, created, resumed }
#
# Worktree path: .<platform>/.worktrees/<slug>
# Slug defaults to branch with slashes replaced by hyphens.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

REPO_ROOT="${1:-}"
BRANCH="${2:-}"
SLUG="${3:-}"

if [[ -z "$REPO_ROOT" || -z "$BRANCH" ]]; then
  echo "ERROR: usage: resolve-worktree.sh <repo_root> <branch_name> [worktree_slug]" >&2
  usage 1
fi

REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
PLATFORM="$(bash "${SCRIPT_DIR}/detect-platform.sh")"

if [[ -z "$SLUG" ]]; then
  SLUG="${BRANCH//\//-}"
fi

WORKTREE_PATH="${REPO_ROOT}/.${PLATFORM}/.worktrees/${SLUG}"
CREATED="false"
RESUMED="false"

mkdir -p "${REPO_ROOT}/.${PLATFORM}/.worktrees"

if [[ -d "$WORKTREE_PATH" ]]; then
  RESUMED="true"
else
  DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || echo main)"
  cd "$REPO_ROOT"
  git fetch origin 2>/dev/null || true

  if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    git worktree add "$WORKTREE_PATH" "$BRANCH"
    RESUMED="true"
  elif git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
    git worktree add "$WORKTREE_PATH" --track -b "$BRANCH" "origin/${BRANCH}"
    CREATED="true"
  else
    git worktree add "$WORKTREE_PATH" -b "$BRANCH" "origin/${DEFAULT_BRANCH}"
    CREATED="true"
  fi
fi

jq -nc \
  --arg platform "$PLATFORM" \
  --arg worktree_path "$WORKTREE_PATH" \
  --arg branch "$BRANCH" \
  --arg created "$CREATED" \
  --arg resumed "$RESUMED" \
  '{platform: $platform, worktree_path: $worktree_path, branch: $branch, created: ($created == "true"), resumed: ($resumed == "true")}'
