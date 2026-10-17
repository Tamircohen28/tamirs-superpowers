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
#   A subagent's tool calls carry no agent field and share the parent's
#   conversation_id / generation_id / session_id. The `Task` call that starts the
#   subagent carries `tool_input.subagent_type`.
#
#   Desktop ≥ 3.22 also sends `parent_tool_call_id` on subagent tool calls (the
#   Task call's `tool_use_id`), and desktop ≥ 3.24 keeps `tool_use_id` stable
#   across preToolUse and shell/MCP hooks. When those ids are present this guard
#   attributes a call to exactly one frame — concurrent subagents no longer
#   collapse to an intersection.
#
#   Fallback (older Cursor / missing ids): reconstruct from event ORDER —
#     preToolUse  Task  -> push that agent's allowlist
#     preToolUse  other -> deny if an allowlist is active and the tool is not in it
#     postToolUse Task  -> pop
#   Under that fallback, concurrency still uses INTERSECTION (safer than guessing).
#
# FAILS SAFE, NOT OPEN
#   If a `postToolUse` is missed the allowlist stays active and the session becomes
#   over-restrictive rather than unguarded. State older than STALE_SECONDS is dropped
#   so a crashed session cannot wedge the next one.
#
# NOT A SANDBOX. Path-based guards (enforce-worktree-edits.sh,
# guard-sensitive-files.sh) remain the layer that constrains WHERE writes land.
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
# Prefer tool_use_id (3.24 correlation); accept tool_call_id as an alias.
tool_use_id="$(printf '%s' "$input" | jq -r '.tool_use_id // .tool_call_id // empty' 2>/dev/null || true)"
parent_tool_call_id="$(printf '%s' "$input" | jq -r '.parent_tool_call_id // empty' 2>/dev/null || true)"

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
# Pure bash rather than `tr -c`: GNU tr parses the trailing '-' of a set as a
# reverse range and errors, which under `set -e` kills the hook before it can
# print anything. That failed on Linux CI while passing on macOS.
conv_key="${conv//[^a-zA-Z0-9_-]/_}"
STACK="${DIR}/${conv_key}.stack"
FRAMES="${DIR}/${conv_key}.frames"

# Drop state left behind by a crashed session rather than inheriting its rules.
# find -mmin rather than stat: on Linux, GNU stat's -f flag means --file-system,
# NOT "the BSD format flag". So the chain `stat -f ... || stat -c ...` never falls
# back there - the first form SUCCEEDS at a different job and returns non-numeric
# text. The arithmetic that followed then read that text as a variable name and
# died under `set -u` with "File: unbound variable", before the hook printed
# anything at all. A fallback that never fires because the first command succeeded
# at something else is worse than no fallback: it looks defensive and is not.
stale_minutes=$(( STALE_SECONDS / 60 ))
[ "$stale_minutes" -ge 1 ] || stale_minutes=1
for state_file in "$STACK" "$FRAMES"; do
  if [ -f "$state_file" ] && [ -n "$(find "$state_file" -mmin "+${stale_minutes}" 2>/dev/null || true)" ]; then
    rm -f "$state_file"
  fi
done

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

safe_id_key() {
  local id="$1"
  printf '%s' "${id//[^a-zA-Z0-9_-]/_}"
}

frame_put() {
  # frame_put <tool_use_id> <agent> <allowlist>
  local id="$1" agent="$2" list="$3" key tmp
  key="$(safe_id_key "$id")"
  [ -n "$key" ] || return 1
  tmp="${FRAMES}.tmp.$$"
  if [ -f "$FRAMES" ]; then
    # Drop any prior row for this id, then append.
    awk -F'\t' -v k="$key" '$1 != k { print }' "$FRAMES" > "$tmp" 2>/dev/null || true
  else
    : > "$tmp"
  fi
  printf '%s\t%s\t%s\n' "$key" "$agent" "$list" >> "$tmp"
  mv "$tmp" "$FRAMES"
}

frame_get() {
  # frame_get <parent_tool_call_id> -> prints "agent<TAB>list" or fails
  local id="$1" key
  key="$(safe_id_key "$id")"
  [ -n "$key" ] && [ -f "$FRAMES" ] || return 1
  awk -F'\t' -v k="$key" '$1 == k { print $2 "\t" $3; found=1; exit } END { exit !found }' "$FRAMES"
}

frame_del() {
  local id="$1" key tmp
  key="$(safe_id_key "$id")"
  [ -n "$key" ] && [ -f "$FRAMES" ] || return 0
  tmp="${FRAMES}.tmp.$$"
  awk -F'\t' -v k="$key" '$1 != k { print }' "$FRAMES" > "$tmp" 2>/dev/null || true
  if [ -s "$tmp" ]; then
    mv "$tmp" "$FRAMES"
  else
    rm -f "$tmp" "$FRAMES"
  fi
}

stack_push() {
  local agent="$1" list="$2"
  printf '%s\t%s\n' "$agent" "$list" >> "$STACK"
}

stack_pop() {
  if [ -s "$STACK" ]; then
    tmp="${STACK}.tmp.$$"
    if [ "$(grep -c . "$STACK" 2>/dev/null || echo 0)" -le 1 ]; then
      rm -f "$STACK"
    else
      head -n -1 "$STACK" > "$tmp" 2>/dev/null \
        || awk 'NR>1{print prev} {prev=$0}' "$STACK" > "$tmp" 2>/dev/null || true
      [ -s "$tmp" ] && mv "$tmp" "$STACK" || rm -f "$tmp" "$STACK"
    fi
  fi
}

if [ "$tool" = "Task" ]; then
  agent="$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)"
  if [ -n "$agent" ]; then
    if list="$(allowlist_for "$agent")"; then
      if [ "$event" = "postToolUse" ]; then
        if [ -n "$tool_use_id" ]; then
          frame_del "$tool_use_id"
        fi
        # Always pop the order stack too (keeps fallback in sync).
        stack_pop
      else
        if [ -n "$tool_use_id" ]; then
          frame_put "$tool_use_id" "$agent" "$list"
        fi
        stack_push "$agent" "$list"
      fi
    fi
  fi
  hook_allow
fi

# Preferred path (desktop ≥ 3.22): attribute via parent_tool_call_id → Task frame.
if [ -n "$parent_tool_call_id" ]; then
  if frame_row="$(frame_get "$parent_tool_call_id")"; then
    agent="${frame_row%%$'\t'*}"
    list="${frame_row#*$'\t'}"
    case " $list " in
      *" $tool "*) hook_allow ;;
      *)
        hook_deny "The '${agent}' agent declares tools: ${list} — '${tool}' is not among them. Cursor does not enforce this list itself, so this guard does (keyed by parent_tool_call_id). Use a tool the agent declares, or hand the work to an agent that declares this one."
        ;;
    esac
  fi
  # Unknown parent id: fall through to stack fallback (or allow if none).
fi

# Fallback: no parent id (or unknown) — order-stack / intersection.
[ -s "$STACK" ] || hook_allow

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
