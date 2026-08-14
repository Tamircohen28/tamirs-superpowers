#!/usr/bin/env bash
# Cross-tool agent work-claim primitives.
#
# PURPOSE
#   Let concurrently running coding agents — Claude Code, Cursor, Codex, or
#   anything else — see each other's *active* work and stay out of each other's
#   way. The unit of coordination is a "claim": a small JSON file under a
#   shared, tool-neutral directory, keyed by the resource being worked on
#   (a GitHub PR, a GitHub issue, or a repo+branch).
#
# WHY NOT AUTHORSHIP
#   "Who created this PR/issue/branch" is a permanent, immutable fact. A guard
#   keyed on it can never release: an artifact authored by another agent (or a
#   bot such as app/cursor) stays blocked forever even when nothing is working
#   on it. Concurrency is a transient fact, so the guard must key on a
#   transient signal — a claim that expires.
#
# LIVENESS MODEL
#   A claim is LIVE only if BOTH hold:
#     1. its heartbeat is newer than AGENT_CLAIM_STALE_SECONDS, and
#     2. if it was written on THIS host, its recorded pid is still alive.
#   Otherwise it is STALE and the resource is free to take over.
#
#   Default staleness threshold: 900s (15 minutes). Rationale: a single agent
#   tool call can legitimately run long (a test suite, a CI watch, a build), and
#   heartbeats are only written when the agent next touches the resource. A
#   threshold below ~10 minutes would release a resource out from under an agent
#   that is merely busy. Above ~15 minutes, an agent that crashed or was killed
#   would block real work for an unreasonable stretch. The same-host pid check
#   short-circuits the wait entirely in the common case (agent died locally →
#   released immediately), so the 15-minute timer only actually governs the
#   remote-host / lost-machine case.
#
# ERROR DISCIPLINE
#   Every function distinguishes "nothing is there" from "I could not find out".
#   claim_inspect returns the literal status ERROR when the claim state cannot
#   be read or parsed, and callers MUST treat ERROR as a hard failure — never as
#   FREE. A check that cannot run does not get to report a pass.

# Shared, deliberately NOT under ~/.claude — Codex and Cursor must be able to
# read and write the same directory.
AGENT_CLAIM_DIR="${AGENT_CLAIM_DIR:-$HOME/.agent-work-claims}"
AGENT_CLAIM_STALE_SECONDS="${AGENT_CLAIM_STALE_SECONDS:-900}"

# Last error message set by a claim_* function that returned non-zero.
CLAIM_ERROR=""

claim_now() { date +%s; }

# claim_require_deps — verify the tools the claim layer needs.
claim_require_deps() {
  if ! command -v jq >/dev/null 2>&1; then
    CLAIM_ERROR="jq is not installed; agent-claim state cannot be read or written."
    return 1
  fi
  return 0
}

# claim_ensure_dir — create the shared claim dir; fail loudly if impossible.
claim_ensure_dir() {
  if [ -e "$AGENT_CLAIM_DIR" ] && [ ! -d "$AGENT_CLAIM_DIR" ]; then
    CLAIM_ERROR="Claim path '$AGENT_CLAIM_DIR' exists but is not a directory."
    return 1
  fi
  if ! mkdir -p "$AGENT_CLAIM_DIR" 2>/dev/null; then
    CLAIM_ERROR="Cannot create claim directory '$AGENT_CLAIM_DIR'."
    return 1
  fi
  if [ ! -r "$AGENT_CLAIM_DIR" ] || [ ! -w "$AGENT_CLAIM_DIR" ] || [ ! -x "$AGENT_CLAIM_DIR" ]; then
    CLAIM_ERROR="Claim directory '$AGENT_CLAIM_DIR' is not readable/writable."
    return 1
  fi
  return 0
}

# claim_tool_label — which agent tool is running, best effort but never empty.
claim_tool_label() {
  if [ -n "${AGENT_CLAIM_TOOL:-}" ]; then printf '%s' "$AGENT_CLAIM_TOOL"; return 0; fi
  if [ -n "${CODEX_SESSION_ID:-}${CODEX_THREAD_ID:-}${CODEX_HOME:-}" ]; then printf 'codex'; return 0; fi
  if [ -n "${CURSOR_SESSION_ID:-}${CURSOR_TRACE_ID:-}${CURSOR_AGENT:-}" ]; then printf 'cursor'; return 0; fi
  case "${HOOK_PLATFORM:-}" in
    cursor) printf 'cursor'; return 0 ;;
    claude) printf 'claude-code'; return 0 ;;
  esac
  if [ -n "${CLAUDE_SESSION_ID:-}${CLAUDE_PLUGIN_ROOT:-}" ]; then printf 'claude-code'; return 0; fi
  printf 'unknown-agent'
}

# claim_agent_id <session-id-from-hook-input>
# Stable identity for "this agent run". Session id is preferred because it is
# the same across every tool call of one agent; pid is the fallback.
claim_agent_id() {
  local session="${1:-}"
  if [ -n "${AGENT_CLAIM_ID:-}" ]; then printf '%s' "$AGENT_CLAIM_ID"; return 0; fi
  local tool
  tool="$(claim_tool_label)"
  if [ -n "$session" ] && [ "$session" != "null" ]; then
    printf '%s:%s' "$tool" "$session"
  else
    printf '%s:pid-%s' "$tool" "${PPID:-$$}"
  fi
}

# claim_pid_alive <pid> — ownership-independent liveness probe.
# `ps -p` reports existence regardless of who owns the process; `kill -0`
# returns EPERM for a live process owned by another user, which would be
# misread as death.
claim_pid_alive() {
  ps -p "$1" -o pid= >/dev/null 2>&1
}

# claim_key <resource> — filesystem-safe key for a resource identifier.
claim_key() {
  printf '%s' "$1" | tr '/:@#' '____' | tr -c 'A-Za-z0-9._-' '_'
}

claim_path() {
  printf '%s/%s.json' "$AGENT_CLAIM_DIR" "$(claim_key "$1")"
}

# claim_inspect <resource> <my-agent-id>
# Prints one line: STATUS<TAB>holder_id<TAB>tool<TAB>age_seconds<TAB>detail
# STATUS is one of FREE | MINE | LIVE | STALE | ERROR.
# Returns 0 for FREE/MINE/LIVE/STALE, 1 for ERROR (with CLAIM_ERROR set).
claim_inspect() {
  local resource="$1" me="$2" file json holder tool pid host hb now age
  file="$(claim_path "$resource")"

  if [ ! -e "$file" ]; then
    printf 'FREE\t-\t-\t-\tno claim file\n'
    return 0
  fi
  if [ ! -r "$file" ]; then
    CLAIM_ERROR="Claim file '$file' exists but is not readable — cannot determine whether another agent holds $resource."
    printf 'ERROR\t-\t-\t-\t%s\n' "$CLAIM_ERROR"
    return 1
  fi
  if ! json="$(cat "$file" 2>/dev/null)"; then
    CLAIM_ERROR="Claim file '$file' could not be read — cannot determine whether another agent holds $resource."
    printf 'ERROR\t-\t-\t-\t%s\n' "$CLAIM_ERROR"
    return 1
  fi
  if ! printf '%s' "$json" | jq -e . >/dev/null 2>&1; then
    CLAIM_ERROR="Claim file '$file' is not valid JSON — claim state for $resource is corrupt and cannot be evaluated."
    printf 'ERROR\t-\t-\t-\t%s\n' "$CLAIM_ERROR"
    return 1
  fi

  holder="$(printf '%s' "$json" | jq -r '.agent_id // ""')"
  tool="$(printf '%s' "$json" | jq -r '.tool // "unknown"')"
  pid="$(printf '%s' "$json" | jq -r '.pid // ""')"
  host="$(printf '%s' "$json" | jq -r '.host // ""')"
  hb="$(printf '%s' "$json" | jq -r '.heartbeat_at // ""')"

  if [ -z "$holder" ] || [ -z "$hb" ] || ! printf '%s' "$hb" | grep -qE '^[0-9]+$'; then
    CLAIM_ERROR="Claim file '$file' is missing required fields (agent_id/heartbeat_at) — claim state for $resource cannot be evaluated."
    printf 'ERROR\t-\t-\t-\t%s\n' "$CLAIM_ERROR"
    return 1
  fi

  now="$(claim_now)"
  age=$(( now - hb ))
  [ "$age" -lt 0 ] && age=0

  if [ "$holder" = "$me" ]; then
    printf 'MINE\t%s\t%s\t%s\tself\n' "$holder" "$tool" "$age"
    return 0
  fi

  # Same host + dead pid = the holder is definitively gone; release now.
  # Only applied when `ps` is available: `kill -0` alone cannot distinguish a
  # dead process (ESRCH) from a live one owned by another user (EPERM), and
  # reading EPERM as "dead" would release a live claim.
  if [ -n "$host" ] && [ "$host" = "$(hostname)" ] && [ -n "$pid" ] \
     && printf '%s' "$pid" | grep -qE '^[0-9]+$' && command -v ps >/dev/null 2>&1; then
    if ! claim_pid_alive "$pid"; then
      printf 'STALE\t%s\t%s\t%s\tholder pid %s is gone on this host\n' "$holder" "$tool" "$age" "$pid"
      return 0
    fi
  fi

  if [ "$age" -gt "$AGENT_CLAIM_STALE_SECONDS" ]; then
    printf 'STALE\t%s\t%s\t%s\theartbeat older than %ss\n' "$holder" "$tool" "$age" "$AGENT_CLAIM_STALE_SECONDS"
    return 0
  fi

  printf 'LIVE\t%s\t%s\t%s\theartbeat %ss ago\n' "$holder" "$tool" "$age" "$age"
  return 0
}

# claim_write <resource> <my-agent-id> <note>
# Take or refresh the claim. Atomic (temp file + mv). Fails loudly.
claim_write() {
  local resource="$1" me="$2" note="${3:-}" file tmp now
  file="$(claim_path "$resource")"
  now="$(claim_now)"
  tmp="${file}.tmp.$$"

  if ! jq -n \
    --arg resource "$resource" \
    --arg agent_id "$me" \
    --arg tool "$(claim_tool_label)" \
    --arg host "$(hostname)" \
    --arg note "$note" \
    --argjson pid "${PPID:-$$}" \
    --argjson heartbeat_at "$now" \
    '{schema:"agent-work-claim/1", resource:$resource, agent_id:$agent_id, tool:$tool,
      host:$host, pid:$pid, heartbeat_at:$heartbeat_at, note:$note}' > "$tmp" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
    CLAIM_ERROR="Could not write claim for $resource to '$file'."
    return 1
  fi
  if ! mv -f "$tmp" "$file" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
    CLAIM_ERROR="Could not install claim file '$file'."
    return 1
  fi
  return 0
}

# claim_release_all <my-agent-id> — drop every claim held by this agent.
claim_release_all() {
  local me="$1" f holder released=0
  [ -d "$AGENT_CLAIM_DIR" ] || { printf '0'; return 0; }
  for f in "$AGENT_CLAIM_DIR"/*.json; do
    [ -e "$f" ] || continue
    holder="$(jq -r '.agent_id // ""' "$f" 2>/dev/null)"
    if [ "$holder" = "$me" ]; then
      rm -f "$f" 2>/dev/null && released=$((released + 1))
    fi
  done
  printf '%s' "$released"
}
