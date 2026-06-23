#!/usr/bin/env bash
# parse-mode-args.sh — parse repo-standards mode and target from CLI args.
#
# Usage:
#   parse-mode-args.sh [args...]
#   parse-mode-args.sh -h | --help
#
# Output JSON: { mode, target, doc_path, constraints }
set -euo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

find_repo_root() {
  local dir
  dir="$(cd "$1" && pwd)"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.git" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "$(cd "$1" && pwd)"
}

MODE="review"
TARGET=""
DOC_PATH=""
CONSTRAINTS=""
REST=("$@")

if [[ ${#REST[@]} -gt 0 && "${REST[0]}" =~ ^(review|plan|polish)$ ]]; then
  MODE="${REST[0]}"
  REST=("${REST[@]:1}")
fi

if [[ ${#REST[@]} -gt 0 ]]; then
  FIRST="${REST[0]}"
  if [[ -d "$FIRST" ]]; then
    TARGET="$(cd "$FIRST" && pwd)"
    CONSTRAINTS="${REST[*]:1}"
  elif [[ -f "$FIRST" && "$FIRST" == *.md ]]; then
    DOC_PATH="$(cd "$(dirname "$FIRST")" && pwd)/$(basename "$FIRST")"
    TARGET="$(find_repo_root "$(dirname "$FIRST")")"
    CONSTRAINTS="${REST[*]:1}"
  else
    CONSTRAINTS="${REST[*]}"
  fi
fi

if [[ -z "$TARGET" ]]; then
  TARGET="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  TARGET="$(cd "$TARGET" && pwd)"
fi

jq -nc \
  --arg mode "$MODE" \
  --arg target "$TARGET" \
  --arg doc_path "$DOC_PATH" \
  --arg constraints "$CONSTRAINTS" \
  '{mode: $mode, target: $target, doc_path: ($doc_path | if . == "" then null else . end), constraints: $constraints}'
