#!/usr/bin/env bash
# fetch-pr-state.sh — fetch fresh PR state, checks, and unresolved review threads.
#
# Usage:
#   fetch-pr-state.sh <PR_NUMBER>
#   fetch-pr-state.sh -h | --help
#
# Output: three sections to stdout, separated by lines beginning with '##':
#   ## PR        — gh pr view JSON (title,state,headRefName,body,statusCheckRollup)
#   ## CHECKS    — gh pr checks summary
#   ## THREADS   — GraphQL response with all review threads (unresolved + resolved)
#
# Use the THREADS section to identify thread IDs to resolve via resolve-thread.sh.
set -euo pipefail

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

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
    -h|--help) usage 0;;
    -v|--verbose) VERBOSE=1; shift;;
    *) PR="$1"; shift;;
  esac
done

PR="${PR:-}"
if [[ -z "$PR" ]]; then
  echo "ERROR: missing <PR_NUMBER>" >&2
  usage 1
fi

OWNER=$(gh repo view --json owner --jq .owner.login)
REPO_NAME=$(gh repo view --json name --jq .name)

[[ "$VERBOSE" == 1 ]] && echo "OWNER=$OWNER REPO=$REPO_NAME PR=$PR" >&2

printf '## PR\n'
gh pr view "$PR" --json title,state,headRefName,baseRefName,body,statusCheckRollup,mergeable,reviewDecision

printf '\n## CHECKS\n'
gh pr checks "$PR" || true

printf '\n## THREADS\n'
gh api graphql -f query="
{
  repository(owner: \"$OWNER\", name: \"$REPO_NAME\") {
    pullRequest(number: $PR) {
      reviewThreads(first: 100) {
        totalCount
        nodes {
          id
          isResolved
          comments(first: 20) {
            nodes {
              author { login }
              body
              path
              line
              originalLine
            }
          }
        }
      }
    }
  }
}"
