#!/usr/bin/env bash
# enable-repo-merge-settings.sh — allow PR auto-merge and delete head branch on merge.
#
# Required by start-dev / pr-dev (gh pr merge --auto --delete-branch).
# Usage: enable-repo-merge-settings.sh [owner/repo]
set -euo pipefail

REPO="${1:-}"
if [[ -z "$REPO" ]]; then
  command -v gh &>/dev/null || { echo "enable-repo-merge-settings: gh required" >&2; exit 1; }
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
fi

gh api -X PATCH "repos/$REPO" \
  -f allow_auto_merge=true \
  -f delete_branch_on_merge=true
