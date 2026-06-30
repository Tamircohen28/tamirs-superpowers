#!/usr/bin/env bash
# parse-mode-args.sh — parse switch-dev mode and target from CLI args.
#
# Usage:
#   parse-mode-args.sh [args...]
#
# Output JSON: { mode, issue, target_platform, constraints }
set -euo pipefail

MODE="handoff"
ISSUE=""
TARGET_PLATFORM=""
CONSTRAINTS=""
REST=("$@")

if [[ ${#REST[@]} -gt 0 && "${REST[0]}" =~ ^(handoff|resume|status)$ ]]; then
  MODE="${REST[0]}"
  REST=("${REST[@]:1}")
fi

for arg in "${REST[@]}"; do
  if [[ "$arg" =~ ^#?[0-9]+$ ]]; then
    ISSUE="${arg#\#}"
  elif [[ "$arg" =~ ^(claude|cursor|codex|any)$ ]]; then
    TARGET_PLATFORM="$arg"
  elif [[ "$arg" =~ ^agent:(claude|cursor|codex|any)$ ]]; then
    TARGET_PLATFORM="${arg#agent:}"
  else
    CONSTRAINTS+="${CONSTRAINTS:+ }${arg}"
  fi
done

if [[ -z "$ISSUE" && "$MODE" != "status" && "$MODE" != "handoff" ]]; then
  :
fi

if [[ -z "$ISSUE" && "$MODE" == "handoff" && ${#REST[@]} -gt 0 && "${REST[0]}" =~ ^#?[0-9]+$ ]]; then
  ISSUE="${REST[0]#\#}"
fi

jq -nc \
  --arg mode "$MODE" \
  --arg issue "$ISSUE" \
  --arg target_platform "$TARGET_PLATFORM" \
  --arg constraints "$CONSTRAINTS" \
  '{mode: $mode, issue: ($issue | if . == "" then null else . end), target_platform: ($target_platform | if . == "" then null else . end), constraints: $constraints}'
