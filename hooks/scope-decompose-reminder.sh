#!/usr/bin/env bash
# UserPromptSubmit hook — nudges decomposition when a prompt is a sweeping mandate.
# Sweeping "do everything at once" prompts are the top cause of context/token-limit
# failures (output-token max, "prompt too long"). Advisory only — never blocks.
#
# On Cursor (beforeSubmitPrompt, via platforms/cursor/hooks.json) the nudge goes
# out as `{"continue": true, "user_message": ...}` — that event has no
# model-visible channel, so it reaches the user, and the wording already reads
# as advice to either. Nothing to say is an explicit `{"continue": true}` there.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"
# shellcheck source=lib/cursor-output.sh
source "${SCRIPT_DIR}/lib/cursor-output.sh"

input="$(hook_read_stdin)"
hook_detect_platform "$input"
prompt="$(echo "$input" | jq -r '.prompt // empty')"

MSG="⚠ Large-scope mandate detected. To avoid context/token-limit failures: decompose into bounded sub-tasks, write large outputs incrementally to separate files (outline first, then <400-line sections), and delegate heavy reads to scoped sub-agents rather than reading whole repos in the main thread."

if echo "$prompt" | grep -qiE 'complete everything|transform .* (into|to)|all open .*(pr|pull request)|portfolio-grade|merge all|do everything|entire (repo|codebase|roadmap)'; then
  if [ "${HOOK_PLATFORM:-claude}" = "cursor" ]; then
    cursor_prompt_pass "$MSG"
  fi
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "⚠ Large-scope mandate detected. To avoid context/token-limit failures: decompose into bounded sub-tasks, write large outputs incrementally to separate files (outline first, then <400-line sections), and delegate heavy reads to scoped sub-agents rather than reading whole repos in the main thread."
  }
}
EOF
elif [ "${HOOK_PLATFORM:-claude}" = "cursor" ]; then
  cursor_prompt_pass
fi
