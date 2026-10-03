#!/usr/bin/env bash
# parse-mode-args.sh — parse switch-dev mode and target from CLI args.
#
# Usage:
#   parse-mode-args.sh [args...]
#
# Output JSON: { mode, issue, objective, task, target_platform, constraints }
#
# Platforms recognised: claude, cursor, codex, gemini, opencode, any.
# Objective/task selectors: objective=<slug> / obj:<slug>, task-NNN / task=task-NNN.
set -euo pipefail

MODE="handoff"
ISSUE=""
OBJECTIVE=""
TASK=""
TARGET_PLATFORM=""
CONSTRAINTS=""
REST=("$@")

if [[ ${#REST[@]:-0} -gt 0 && "${REST[0]:-}" =~ ^(handoff|resume|status)$ ]]; then
  MODE="${REST[0]}"
  REST=("${REST[@]:1}")
fi

for arg in ${REST[@]+"${REST[@]}"}; do
  if [[ "$arg" =~ ^#?[0-9]+$ ]]; then
    ISSUE="${arg#\#}"
  elif [[ "$arg" =~ ^(claude|claude-code|cursor|codex|gemini|opencode|any)$ ]]; then
    TARGET_PLATFORM="${arg/claude-code/claude}"
  elif [[ "$arg" =~ ^agent:(claude|cursor|codex|gemini|opencode|any)$ ]]; then
    TARGET_PLATFORM="${arg#agent:}"
  elif [[ "$arg" =~ ^task-[0-9]{3}$ ]]; then
    TASK="$arg"
  elif [[ "$arg" =~ ^task=task-[0-9]{3}$ ]]; then
    TASK="${arg#task=}"
  elif [[ "$arg" =~ ^(objective|obj)[=:][a-z0-9][a-z0-9-]*$ ]]; then
    OBJECTIVE="${arg#*[=:]}"
  else
    CONSTRAINTS+="${CONSTRAINTS:+ }${arg}"
  fi
done

jq -nc \
  --arg mode "$MODE" \
  --arg issue "$ISSUE" \
  --arg objective "$OBJECTIVE" \
  --arg task "$TASK" \
  --arg target_platform "$TARGET_PLATFORM" \
  --arg constraints "$CONSTRAINTS" \
  '{mode: $mode,
    issue: ($issue | if . == "" then null else . end),
    objective: ($objective | if . == "" then null else . end),
    task: ($task | if . == "" then null else . end),
    target_platform: ($target_platform | if . == "" then null else . end),
    constraints: $constraints}'
