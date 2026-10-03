#!/usr/bin/env bash
# detect-multi-platform-repo.sh — true when repo ships multi-platform agent setup.
#
# Usage: bash detect-multi-platform-repo.sh [repo-root]
# Exit 0 if multi-platform; 1 otherwise.
set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"

score=0
[[ -f "$ROOT/AGENTS.md" ]] && score=$((score + 1))
[[ -f "$ROOT/CLAUDE.md" ]] && score=$((score + 1))
[[ -d "$ROOT/.cursor/rules" ]] && score=$((score + 1))
[[ -f "$ROOT/.claude-plugin/plugin.json" ]] && score=$((score + 1))
[[ -f "$ROOT/.cursor-plugin/plugin.json" ]] && score=$((score + 1))
[[ -f "$ROOT/.codex-plugin/plugin.json" ]] && score=$((score + 1))
[[ -f "$ROOT/docs/engineering/build-and-release/platform-targets.json" ]] && score=$((score + 1))

if (( score >= 2 )); then
  exit 0
fi
exit 1
