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
