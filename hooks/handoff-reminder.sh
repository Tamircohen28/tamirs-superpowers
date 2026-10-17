#!/usr/bin/env bash
# handoff-reminder.sh — SessionEnd reminder to run switch-dev handoff from active worktrees.
#
# On Cursor (platforms/cursor/hooks.json, event sessionEnd) the directory comes
# from workspace_roots[0] (Cursor sends no cwd), the Cursor CLI's own
# ~/.cursor/worktrees/<repo>/<name> layout counts as an active worktree, and the
# reminder goes to stderr with NOTHING on stdout: Cursor documents no output
# field for sessionEnd, so a systemMessage there is a Claude key it would at
# best ignore. The Claude path is unchanged.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"
# shellcheck source=lib/cursor-output.sh
source "${SCRIPT_DIR}/lib/cursor-output.sh"

input="$(hook_read_stdin)"
hook_detect_platform "$input"
cwd="$(echo "$input" | jq -r '.cwd // .workspace_roots[0] // empty')"

in_worktree=false
case "$cwd" in
  */.claude/.worktrees/*|*/.cursor/.worktrees/*|*/.codex/.worktrees/*|*/.claude/worktrees/*|*/.cursor/worktrees/*)
    in_worktree=true
    ;;
esac

if [[ "$in_worktree" != true ]]; then
  [[ "${HOOK_PLATFORM:-claude}" == "cursor" ]] && cursor_silent
  echo '{"suppressOutput": true}'
  exit 0
fi

issue=""
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  issue="$(
    git -C "$cwd" log -10 --pretty=%B 2>/dev/null \
      | grep -Eo '(Closes|Fixes|Refs) #[0-9]+|#[0-9]+' \
      | grep -Eo '[0-9]+' \
      | head -1 \
      || true
  )"
fi

if [[ -n "$issue" ]]; then
  msg="Active worktree detected at ${cwd}. Before closing: push commits and run /switch-dev handoff #${issue} so another platform can resume."
else
  msg="Active worktree detected at ${cwd}. Before closing: push commits and run /switch-dev handoff #N (linked issue) so another platform can resume."
fi

if [[ "${HOOK_PLATFORM:-claude}" == "cursor" ]]; then
  printf '%s\n' "$msg" >&2
  cursor_silent
fi

# systemMessage, not hookSpecificOutput.additionalContext: the schema has no
# SessionEnd variant of hookSpecificOutput at all (only PreToolUse,
# PermissionRequest, UserPromptSubmit, PostToolUse, PostToolBatch, and
# Stop/SubagentStop support it), and SessionEnd has no next turn to inject
# context into anyway — the session is already terminating. This is not the
# systemMessage-vs-additionalContext anti-pattern the CHANGELOG documents for
# plugin-version-watch.sh (a Stop hook, where additionalContext is a real,
# supported, model-visible channel); that lesson doesn't transfer to SessionEnd.
jq -n --arg msg "$msg" '{systemMessage: $msg}'
