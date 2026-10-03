#!/usr/bin/env bash
# ensure-branch-protection.sh — DEPRECATED SHIM. Delegates to scripts/github-policy.sh.
#
# WHAT THIS USED TO DO, AND WHY IT WAS WRONG
#   It read and wrote CLASSIC branch protection at
#   `repos/{o}/{r}/branches/{b}/protection`. On a repository correctly governed by
#   branch RULESETS that endpoint returns 404, so the old --verify-only path
#   reported this very repository — protected by two active rulesets — as
#   unprotected, and the apply path would have written a second, weaker, legacy
#   mechanism alongside the real one.
#
#   It also defaulted to MIN_REVIEWS=1 and a single literal status check named
#   "CI". Both are wrong here: the canonical policy runs 0 required approving
#   reviews with review-thread resolution ON (the solo-contributor posture), and
#   required contexts are per-repository — 9 on this repo out of 15 CI jobs —
#   never one globalised name. REQUIRED_CHECK and MIN_REVIEWS are therefore
#   IGNORED by this shim rather than honoured; honouring them would reintroduce
#   the drift.
#
# WHAT TO CALL INSTEAD
#   bash scripts/github-policy.sh audit  --repo <owner/name>   # read-only
#   bash scripts/github-policy.sh plan   --repo <owner/name>   # diff, no writes
#   bash scripts/github-policy.sh apply  --repo <owner/name>   # confirmed writes
#
#   Policy content — ruleset names, rules, required contexts, enforcement — lives
#   in config/github/repository-policy.json. Nothing is restated here.
#
# WHY A SHIM AND NOT A DELETION
#   `_contract/templates/`, both repo skills, and consumer repos scaffolded from
#   earlier versions call this path by name. The shim keeps those callers working
#   while routing every read and write through the one abstraction. Delete it once
#   no caller names it.
#
# Usage (unchanged surface):
#   ensure-branch-protection.sh [--verify-only] [owner/repo] [branch]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SCRIPT_DIR/../../../.." 2>/dev/null && pwd || true)"
POLICY_CLI="${GITHUB_POLICY_CLI:-$SRC_ROOT/scripts/github-policy.sh}"

VERIFY_ONLY=false
REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify-only) VERIFY_ONLY=true; shift ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'
      exit 0 ;;
    *)
      # The second positional was a branch name. It is dropped on purpose: the
      # policy targets the default branch through GitHub's ~DEFAULT_BRANCH magic
      # ref, and this fleet is main x15 / master x4 — a literal is wrong on one
      # of those sets and stops matching the day a default branch is renamed.
      [[ -z "$REPO" ]] && REPO="$1"
      shift ;;
  esac
done

echo "ensure-branch-protection.sh is deprecated — delegating to github-policy.sh." >&2
echo "  Call 'bash scripts/github-policy.sh ${VERIFY_ONLY:+audit}' directly; see the header." >&2

if [[ ! -f "$POLICY_CLI" ]]; then
  echo "ensure-branch-protection: github-policy.sh not found at $POLICY_CLI" >&2
  echo "  This checkout does not carry the policy tooling; branch governance cannot be applied here." >&2
  exit 1
fi

VERB=apply
[[ "$VERIFY_ONLY" == true ]] && VERB=audit

set -- "$VERB"
[[ -n "$REPO" ]] && set -- "$@" --repo "$REPO"

exec bash "$POLICY_CLI" "$@"
