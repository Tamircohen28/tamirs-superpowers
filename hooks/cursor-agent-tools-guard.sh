#!/usr/bin/env bash
# cursor-agent-tools-guard.sh — enforce an agent's `tools:` allowlist on Cursor.
#
# WHY THIS EXISTS
#   Cursor does not enforce the frontmatter `tools:` list (measured 2026-09-23 on
#   cursor-agent 2026.07.17-3e2a980: an agent declaring `tools: Read, Grep, Glob`
#   wrote a file when asked). Seven agents here are read-only by declaration, and on
#   Cursor what stops them is the prose in their own system prompt — a model
#   instruction, not a sandbox. Claude enforces the list; OpenCode gets it translated
#   into explicit `permission:` entries by build-opencode-agents.sh. Cursor had
#   nothing, so this supplies it.
#
# HOW IT KNOWS WHICH AGENT IS RUNNING
#   It cannot ask. The subagent's own tool calls DO reach preToolUse, but they carry
#   no agent field and their conversation_id / generation_id / session_id are
#   IDENTICAL to the parent's — there is nothing to correlate on. What does carry the
#   name is the `Task` call that starts the subagent:
#
#       tool_input: {"subagent_type": "architecture-reviewer", ...}
#
#   So this reconstructs the association from event ORDER rather than from an id:
#     preToolUse  Task  -> push that agent's allowlist
#     preToolUse  other -> deny if an allowlist is active and the tool is not in it
#     postToolUse Task  -> pop
#
# CONCURRENCY: INTERSECTION, DELIBERATELY
#   Identical ids mean two concurrent subagents cannot be told apart. Rather than
#   guess which one a call belongs to, every active allowlist must permit the tool —
#   the INTERSECTION. With one subagent that is exactly its own list. With two it is
#   stricter than either, which can refuse a call a lone agent would have been
#   allowed. That is the direction to be wrong in: a refused call is visible and
#   recoverable, a permitted one is not.
#
# FAILS SAFE, NOT OPEN
#   If a `postToolUse` is missed the allowlist stays active and the session becomes
#   over-restrictive rather than unguarded. State older than STALE_SECONDS is dropped
#   so a crashed session cannot wedge the next one.
#
# NOT A SANDBOX. This infers "we are inside a subagent" from event sequence. It
# raises the cost of an unlisted tool call; it does not make one impossible. The
# path-based guards (enforce-worktree-edits.sh, guard-sensitive-files.sh) remain the
# layer that constrains WHERE writes land.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

STALE_SECONDS="${CURSOR_TOOLS_GUARD_STALE_SECONDS:-3600}"

input="$(hook_read_stdin)"
hook_detect_platform "$input"

# Claude tool name -> the name Cursor reports in tool_name. Only the differences are
# listed; Read/Write/Grep/Glob are identical on both, measured from real payloads.
cursor_name_for() {
  case "$1" in
    Bash) printf 'Shell' ;;
    *)    printf '%s' "$1" ;;
  esac
}

event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null || true)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
conv="$(printf '%s' "$input" | jq -r '.conversation_id // .session_id // empty' 2>/dev/null || true)"

# Outside Cursor this guard has nothing to add: Claude enforces the list itself.
[ "${HOOK_PLATFORM:-claude}" = "cursor" ] || hook_allow
[ -n "$conv" ] || hook_allow

state_dir() {
  local base="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}"
  local d="${base%/}/cursor-agent-tools-guard"
  mkdir -p "$d" 2>/dev/null || true
  printf '%s' "$d"
}
DIR="$(state_dir)"
STACK="${DIR}/$(printf '%s' "$conv" | tr -c 'a-zA-Z0-9_-' '_').stack"

# Drop a stack left behind by a crashed session rather than inheriting its rules.
if [ -f "$STACK" ]; then
  mtime="$(stat -f %m "$STACK" 2>/dev/null || stat -c %Y "$STACK" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  if [ $(( now - mtime )) -gt "$STALE_SECONDS" ]; then rm -f "$STACK"; fi
fi

# Resolve an agent's declared tools, translated to the names Cursor reports.
allowlist_for() {
  local name="$1" f tools out=""
  for f in "${SCRIPT_DIR}/../agents/${name}.md" "${CURSOR_PLUGIN_ROOT:-}/agents/${name}.md"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    tools="$(sed -n 's/^tools: *//p' "$f" | head -1)"
    [ -n "$tools" ] || return 1
    local t
    for t in ${tools//,/ }; do
      [ -n "$t" ] && out="${out} $(cursor_name_for "$t")"
    done
    printf '%s' "${out# }"
    return 0
  done
  return 1
}

if [ "$tool" = "Task" ]; then
  agent="$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)"
  if [ -n "$agent" ]; then
    if list="$(allowlist_for "$agent")"; then
      if [ "$event" = "postToolUse" ]; then
        # Task finished: drop its frame.
        [ -f "$STACK" ] && sed -i '' -e '$d' "$STACK" 2>/dev/null || \
          { [ -f "$STACK" ] && sed -i -e '$d' "$STACK" 2>/dev/null; } || true
      else
        printf '%s\t%s\n' "$agent" "$list" >> "$STACK"
      fi
    fi
  fi
  hook_allow
fi

# No frame active: nothing to enforce.
[ -s "$STACK" ] || hook_allow

# Intersection: every active frame must permit the tool.
denied_by=""
while IFS=$'\t' read -r agent list; do
  [ -n "$list" ] || continue
  case " $list " in
    *" $tool "*) ;;
    *) denied_by="$agent"; break ;;
  esac
done < "$STACK"

if [ -n "$denied_by" ]; then
  hook_deny "The '${denied_by}' agent declares tools: $(printf '%s' "$(grep -m1 "^${denied_by}	" "$STACK" | cut -f2)") — '${tool}' is not among them. Cursor does not enforce this list itself, so this guard does. Use a tool the agent declares, or hand the work to an agent that declares this one."
fi

hook_allow
