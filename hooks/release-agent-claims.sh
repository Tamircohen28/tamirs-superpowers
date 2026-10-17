#!/usr/bin/env bash
# SessionEnd — drop every work-claim held by this agent run.
#
# Claims also expire on their own (see lib/agent-claim.sh), but an explicit
# release at session end means a clean exit frees the artifact immediately
# instead of after the staleness window.
#
# Runs unchanged on Cursor's sessionEnd (platforms/cursor/hooks.json): the
# session key already falls back to conversation_id, the tool label comes from
# HOOK_PLATFORM, and stdout is empty on every host — Cursor documents no output
# for sessionEnd, and this hook reports only on stderr.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"
# shellcheck source=lib/agent-claim.sh
source "${SCRIPT_DIR}/lib/agent-claim.sh"

INPUT="$(hook_read_stdin)"
hook_detect_platform "$INPUT"

if ! claim_require_deps; then
  printf 'agent-claim release SKIPPED: %s\n' "$CLAIM_ERROR" >&2
  exit 0
fi

SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // .conversation_id // ""' 2>/dev/null)
ME="$(claim_agent_id "$SESSION")"

RELEASED="$(claim_release_all "$ME")"
printf 'agent-claim: released %s claim(s) held by %s\n' "$RELEASED" "$ME" >&2
exit 0
