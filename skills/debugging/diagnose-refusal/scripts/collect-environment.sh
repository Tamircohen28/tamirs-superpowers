#!/usr/bin/env bash
# collect-environment.sh — safe diagnostic environment snapshot for diagnose-refusal.
#
# Usage:
#   collect-environment.sh [-v|--verbose] [-h|--help]
#   collect-environment.sh > .refusal-debug/environment.md
#
# Prints Markdown to stdout. Records tool versions and environment VARIABLE
# NAMES (SET/UNSET) for model/provider families only — never values.
#
# Example:
#   bash skills/debugging/diagnose-refusal/scripts/collect-environment.sh
set -euo pipefail

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

VERBOSE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -*)
      echo "ERROR: unknown flag: $1" >&2
      usage 1
      ;;
    *)
      echo "ERROR: unexpected argument: $1" >&2
      usage 1
      ;;
  esac
done

log() { if [[ "$VERBOSE" -eq 1 ]]; then printf '%s\n' "$*" >&2; fi; }

ver() {
  local label="$1"
  shift
  if command -v "$1" >/dev/null 2>&1; then
    # shellcheck disable=SC2068
    local out
    out="$("$@" 2>/dev/null | head -n 1 | tr -d '\r')"
    printf -- '- %s: `%s`\n' "$label" "${out:-present}"
  else
    printf -- '- %s: not found\n' "$label"
  fi
}

UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BRANCH="$(git branch --show-current 2>/dev/null || echo none)"
STATUS="$(git status --short 2>/dev/null | head -n 20 || true)"

printf '# Environment\n\n'
printf -- '- captured_at_utc: %s\n' "$UTC"
printf -- '- repo_root: `%s`\n' "$ROOT"
printf -- '- branch: `%s`\n' "$BRANCH"
printf '\n## Tool versions\n\n'
ver "git" git --version
ver "python" python3 --version
ver "node" node --version
ver "opencode" opencode --version
ver "claude" claude --version
ver "cursor-agent" cursor-agent --version
ver "gemini" gemini --version
ver "codex" codex --version

if command -v python3 >/dev/null 2>&1; then
  if python3 -m pip show litellm >/dev/null 2>&1; then
    litellm_ver="$(python3 -m pip show litellm 2>/dev/null | awk -F': ' '/^Version:/{print $2; exit}')"
    printf -- '- litellm (pip): `%s`\n' "${litellm_ver:-installed}"
  else
    printf -- '- litellm (pip): not installed\n'
  fi
fi

printf '\n## Git status (short, capped)\n\n'
if [[ -n "$STATUS" ]]; then
  printf '%s\n' '```'
  printf '%s\n' "$STATUS"
  printf '%s\n' '```'
else
  printf 'clean or not a git repo\n'
fi

printf '\n## Relevant environment variable names (values never recorded)\n\n'
# Name-only probe. Match prefixes / exact names relevant to routing.
# bash 3.2-safe: no mapfile / declare -A.
RELEVANT_REGEX='^(LITELLM|GLM|ZAI|OPENROUTER|ANTHROPIC|OPENAI|MODEL|PROVIDER|API_BASE|OPENCODE|CLAUDE|CURSOR|GEMINI|CODEX|OLLAMA|TOGETHER|FIREWORKS|GROQ|DEEPSEEK|MISTRAL|AZURE_OPENAI|AWS_BEDROCK|VERTEX)'

printf '%s\n' '| Variable | State |'
printf '%s\n' '|----------|-------|'

# Iterate exported names only.
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  if printf '%s' "$name" | grep -Eq "$RELEVANT_REGEX"; then
    printf '| `%s` | SET |\n' "$name"
  fi
done < <(env | cut -d= -f1 | sort -u)

# Explicitly call out common keys even when unset, so absence is visible.
for name in \
  LITELLM_API_KEY LITELLM_MODEL LITELLM_LOG \
  OPENROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY \
  GLM_API_KEY ZAI_API_KEY \
  OPENAI_API_BASE ANTHROPIC_BASE_URL \
  MODEL PROVIDER API_BASE
do
  if ! printenv "$name" >/dev/null 2>&1; then
    # Only list UNSET if we did not already list SET above — printenv fails when unset.
    if ! env | cut -d= -f1 | grep -Fxq "$name"; then
      printf '| `%s` | UNSET |\n' "$name"
    fi
  fi
done

printf '\n_Values intentionally omitted. Treat SET as presence-only._\n'
log "environment snapshot complete"
