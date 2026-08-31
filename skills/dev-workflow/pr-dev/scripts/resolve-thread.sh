#!/usr/bin/env bash
# resolve-thread.sh — resolve a single PR review thread by GraphQL ID.
#
# Usage:
#   resolve-thread.sh <THREAD_ID>
#   resolve-thread.sh -h | --help
#
# Example:
#   resolve-thread.sh PRRT_kwDOABCDEF12345
set -euo pipefail

# --repo <owner/name> pins the repository for the GraphQL mutation's implicit
# repo resolution; see the note in resolve-merge-policy.sh. Accepted before the
# thread id so every script in this directory takes the same flag.
if [[ "${1:-}" == "--repo" ]]; then
  case "${2:-}" in
    */*) export GH_REPO="$2"; shift 2 ;;
    *) printf 'error: --repo expects <owner>/<name>, got %s\n' "${2:-}" >&2; exit 2 ;;
  esac
elif [[ "${1:-}" == --repo=* ]]; then
  export GH_REPO="${1#--repo=}"; shift
fi

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

TID="${1:-}"
if [[ -z "$TID" ]]; then
  echo "ERROR: missing <THREAD_ID>" >&2
  usage 1
fi

gh api graphql -f query="mutation {
  resolveReviewThread(input: {threadId: \"$TID\"}) {
    thread { isResolved }
  }
}"
