#!/usr/bin/env bash
# ensure-branch-protection.sh — apply and verify branch protection on the default branch.
#
# Tamir Cohen standard: 1 required PR review + required CI status check on master (or default branch).
# Required by repo-scaffold and repo-standards polish phase 4.
#
# Usage:
#   ensure-branch-protection.sh [owner/repo] [branch]
#   ensure-branch-protection.sh --verify-only [owner/repo] [branch]
#   REQUIRED_CHECK=CI MIN_REVIEWS=1 ensure-branch-protection.sh
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ensure-branch-protection.sh [--verify-only] [owner/repo] [branch]

Apply (if missing) and verify branch protection:
  - required_pull_request_reviews >= MIN_REVIEWS (default 1)
  - required_status_checks includes REQUIRED_CHECK (default CI)

Environment:
  REQUIRED_CHECK   Status check context name (default: CI)
  MIN_REVIEWS      Minimum approving reviews (default: 1)
EOF
}

VERIFY_ONLY=false
REPO=""
BRANCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify-only) VERIFY_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$REPO" ]]; then
        REPO="$1"
      elif [[ -z "$BRANCH" ]]; then
        BRANCH="$1"
      else
        echo "ensure-branch-protection: unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

command -v gh &>/dev/null || { echo "ensure-branch-protection: gh required" >&2; exit 1; }
command -v jq &>/dev/null || { echo "ensure-branch-protection: jq required" >&2; exit 1; }

if [[ -z "$REPO" ]]; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
fi
if [[ -z "$BRANCH" ]]; then
  BRANCH=$(gh repo view "$REPO" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo master)
fi

REQUIRED_CHECK="${REQUIRED_CHECK:-CI}"
MIN_REVIEWS="${MIN_REVIEWS:-1}"

fetch_protection() {
  gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null || true
}

apply_protection() {
  gh api "repos/$REPO/branches/$BRANCH/protection" \
    --method PUT \
    --silent \
    -F 'required_status_checks[strict]=true' \
    -F "required_status_checks[contexts][]=$REQUIRED_CHECK" \
    -F "required_pull_request_reviews[required_approving_review_count]=$MIN_REVIEWS" \
    -F 'enforce_admins=false' \
    -F 'restrictions=null'
}

verify_protection() {
  local prot reviews has_check
  prot="$(fetch_protection)"
  if [[ -z "$prot" ]]; then
    echo "ensure-branch-protection: no protection on $REPO@$BRANCH" >&2
    return 1
  fi

  reviews=$(echo "$prot" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')
  has_check=$(echo "$prot" | jq -r --arg c "$REQUIRED_CHECK" \
    '(.required_status_checks.contexts // []) | index($c) != null')

  if (( reviews < MIN_REVIEWS )); then
    echo "ensure-branch-protection: need >= $MIN_REVIEWS review(s), got $reviews on $REPO@$BRANCH" >&2
    return 1
  fi
  if [[ "$has_check" != true ]]; then
    echo "ensure-branch-protection: missing required status check '$REQUIRED_CHECK' on $REPO@$BRANCH" >&2
    return 1
  fi

  echo "Branch protection OK: $REPO@$BRANCH ($MIN_REVIEWS review(s), check $REQUIRED_CHECK)"
}

if [[ "$VERIFY_ONLY" == true ]]; then
  verify_protection
  exit $?
fi

if verify_protection 2>/dev/null; then
  exit 0
fi

echo "Applying branch protection to $REPO@$BRANCH..." >&2
apply_protection
verify_protection
