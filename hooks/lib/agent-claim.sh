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

# ------------------------------------------------------- git push parsing ---
#
# WHY THIS IS A REAL PARSER AND NOT A REGEX
#   `git push` destinations cannot be read positionally. A leading flag shifts
#   every argument (`git push -q origin feature-x`), refspecs come in several
#   shapes (`branch`, `HEAD:branch`, `src:dst`, `+src:dst`, `:branch`,
#   `--delete branch`), a bare `git push` names no destination at all, and a
#   single invocation may push MANY destinations. A positional read gets all of
#   these wrong, and — worse — its failure mode is silence: it returns an empty
#   branch, the caller substitutes the current/default branch, and the guard
#   then answers a question nobody asked. That is wrong in both directions: it
#   blocks a push to an unclaimed feature branch, and it waves through a push to
#   a claimed branch whenever the argument shape happens to resolve elsewhere.
#
#   So: never guess. If the destination cannot be determined, say so loudly and
#   let the caller deny — the same posture claim_inspect takes for ERROR.

_claim_unquote() {
  local t="$1"
  t="${t#\"}"; t="${t%\"}"
  t="${t#\'}"; t="${t%\'}"
  printf '%s' "$t"
}

# claim_push_destinations <command> [fallback-branch]
#
# Prints one line per resolved destination: DEST<TAB><branch>
# On failure prints exactly one line:      ERROR<TAB><reason>
#
# Returns 0 = destinations printed
#         1 = destination undeterminable (caller MUST fail loud, never allow)
#         2 = the command contains no `git push` at all (nothing to guard)
#
# <fallback-branch> is used ONLY where git itself would use the current branch's
# upstream/name: a bare `git push`, `git push <remote>`, or `git push <remote>
# HEAD`. It is never a default-branch guess; when it is empty in those cases the
# function errors instead.
claim_push_destinations() {
  local cmd="$1" fallback="${2:-}"
  local sep=$'\001' norm tok t2 i j n start=-1
  local -a toks=() positional=()
  local delete=0 broad="" nomoreflags=0

  norm="${cmd//$'\n'/ }"
  norm="${norm//&&/ $sep }"
  norm="${norm//||/ $sep }"
  norm="${norm//|/ $sep }"
  norm="${norm//;/ $sep }"
  read -ra toks <<< "$norm"
  n=${#toks[@]}

  # Locate `push` inside a `git` invocation (allowing `git -C dir push` etc).
  for ((i = 0; i < n; i++)); do
    tok="$(_claim_unquote "${toks[i]}")"
    [ "$tok" = "git" ] || continue
    for ((j = i + 1; j < n; j++)); do
      t2="$(_claim_unquote "${toks[j]}")"
      [ "$t2" = "$sep" ] && break
      case "$t2" in
        -C|-c|--git-dir|--work-tree|--namespace|--exec-path) j=$((j + 1)) ;;
        push) start=$((j + 1)); break ;;
        -*) : ;;
        *) break ;;
      esac
    done
    [ "$start" -ge 0 ] && break
  done
  [ "$start" -ge 0 ] || return 2

  for ((i = start; i < n; i++)); do
    tok="$(_claim_unquote "${toks[i]}")"
    [ "$tok" = "$sep" ] && break
    if [ "$nomoreflags" -eq 1 ]; then positional+=("$tok"); continue; fi
    case "$tok" in
      --) nomoreflags=1 ;;
      -d|--delete) delete=1 ;;
      --all|--mirror) broad="$tok" ;;
      # Flags that consume the NEXT argument — skip both, or their value would
      # be misread as the remote/refspec.
      -o|--push-option|--receive-pack|--exec|--repo) i=$((i + 1)) ;;
      -*) : ;;
      *) positional+=("$tok") ;;
    esac
  done

  if [ -n "$broad" ]; then
    printf 'ERROR\tthe push uses %s, which sends every ref — the set of destination branches cannot be enumerated from the command\n' "$broad"
    return 1
  fi

  local -a dsts=()
  if [ "${#positional[@]}" -le 1 ]; then
    # Bare `git push` / `git push <remote>`: git resolves the destination from
    # the current branch's upstream. Resolve the SAME way, or fail loud.
    if [ "$delete" -eq 1 ]; then
      printf 'ERROR\t--delete was given with no ref to delete, so the destination branch cannot be determined\n'
      return 1
    fi
    if [ -z "$fallback" ]; then
      printf 'ERROR\tthe push names no refspec and the current branch/upstream could not be resolved, so the destination branch cannot be determined\n'
      return 1
    fi
    dsts+=("$fallback")
  else
    local spec dst had_colon
    for spec in "${positional[@]:1}"; do
      dst="${spec#+}"
      had_colon=0
      case "$dst" in *:*) had_colon=1; dst="${dst#*:}" ;; esac
      dst="${dst#refs/heads/}"
      if [ "$dst" = "HEAD" ] && [ "$had_colon" -eq 0 ]; then
        if [ -z "$fallback" ]; then
          printf 'ERROR\tthe push targets HEAD but the current branch could not be resolved, so the destination branch cannot be determined\n'
          return 1
        fi
        dst="$fallback"
      fi
      case "$dst" in
        ""|HEAD|*'*'*)
          printf 'ERROR\trefspec %s does not resolve to a single named destination branch\n' "$spec"
          return 1
          ;;
      esac
      dsts+=("$dst")
    done
  fi

  local d
  for d in "${dsts[@]}"; do printf 'DEST\t%s\n' "$d"; done
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
