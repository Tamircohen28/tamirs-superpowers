#!/usr/bin/env bash
# parse-mode-args.sh — parse multi-agent-repo mode and target from CLI args.
#
# Usage:
#   parse-mode-args.sh [args...]
#   parse-mode-args.sh -h | --help
#
# Output JSON: { "mode", "target", "constraints" }
set -euo pipefail

usage() { sed -n '2,8p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

MODE="review"
TARGET=""
CONSTRAINTS=""
REST=("$@")

if [[ ${#REST[@]} -gt 0 && "${REST[0]}" =~ ^(review|plan|dev)$ ]]; then
  MODE="${REST[0]}"
  REST=("${REST[@]:1}")
fi

if [[ ${#REST[@]} -gt 0 ]]; then
  FIRST="${REST[0]}"
  if [[ -d "$FIRST" ]]; then
    TARGET="$(cd "$FIRST" && pwd)"
    CONSTRAINTS="${REST[*]:1}"
  elif [[ -f "$FIRST" && "$FIRST" == *.md ]]; then
    TARGET="$(cd "$(dirname "$FIRST")" && pwd)/$(basename "$FIRST")"
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
  --arg constraints "$CONSTRAINTS" \
  '{mode: $mode, target: $target, constraints: $constraints}'
