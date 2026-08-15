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

# ------------------------------------------------- shell structure parsing ---
#
# WHY A TOKENIZER AND NOT A TEXT SEARCH
#   The guard's question is "which commands does this string invoke?", and a
#   substring search cannot answer it. `git commit -m "fixed: git push -q origin
#   feature-x resolved to main"` invokes no push at all, yet a text scan reads
#   four phantom destinations out of the message — one of them `main` — and
#   denies an ordinary commit. The failure is two-sided: with no notion of where
#   a command begins, a *real* push sitting after a quoted argument or a `;` is
#   just as easily missed or attributed to the wrong invocation.
#
#   So the string is read the way a shell reads it. Quoted text and heredoc
#   bodies are ARGUMENTS and can never be commands; only the first word of a
#   real segment — after leading `FOO=bar` assignments and wrappers such as
#   `sudo` — names the program being run. Everything downstream (git push
#   destinations, `gh` artifact targets) keys on that first word, never on the
#   raw text.
#
#   Stripping quoted regions before matching would be only half a fix: it
#   correctly drops `git commit -m "git push origin main"`, but it must not lose
#   the real push in `git commit -m "wip" && git push origin main`. Segmenting
#   on separators that are themselves outside quotes is what keeps both true.

# Unit separator: cannot occur in a shell word we care about, so it is a safe
# in-band delimiter between tokens of one segment (segments are newline-separated).
_CLAIM_TOKSEP=$'\037'

# The three helpers below deliberately operate on the caller's locals (bash is
# dynamically scoped). They are only ever called from claim_shell_segments.

_claim_emit_tok() {
  if [ "$have_tok" -eq 1 ]; then
    if [ "$expect_hd" -eq 1 ]; then
      # This word is a heredoc delimiter, not an argument: record it so the
      # body it introduces can be skipped, and do not emit it.
      expect_hd=0
      pending_hd[${#pending_hd[@]}]="$tok"
    else
      tok="${tok//$'\n'/ }"
      if [ -n "$seg_line" ]; then seg_line="${seg_line}${_CLAIM_TOKSEP}"; fi
      seg_line="${seg_line}${tok}"
    fi
  fi
  tok=""
  have_tok=0
}

_claim_emit_seg() {
  _claim_emit_tok
  if [ -n "$seg_line" ]; then out="${out}${seg_line}"$'\n'; fi
  seg_line=""
}

# Skip every pending heredoc body. Called after a newline is consumed at depth
# zero — exactly where the shell itself starts reading heredoc content.
_claim_skip_heredocs() {
  local delim j ln trimmed
  while [ "${#pending_hd[@]}" -gt 0 ]; do
    delim="${pending_hd[0]}"
    if [ "${#pending_hd[@]}" -gt 1 ]; then
      pending_hd=("${pending_hd[@]:1}")
    else
      pending_hd=()
    fi
    while [ "$i" -lt "$n" ]; do
      j="$i"
      while [ "$j" -lt "$n" ] && [ "${s:j:1}" != $'\n' ]; do j=$((j + 1)); done
      ln="${s:i:j - i}"
      if [ "$j" -lt "$n" ]; then i=$((j + 1)); else i="$n"; fi
      trimmed="${ln#"${ln%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      [ "$trimmed" = "$delim" ] && break
    done
  done
}

# claim_shell_segments <command>
#
# Prints one line per shell command segment. Tokens within a segment are
# separated by _CLAIM_TOKSEP. Quotes are consumed (their content stays inside
# one token), heredoc bodies are dropped entirely, and `;`, `&`, `|`, newline,
# `(`/`)` and command substitutions start a new segment — but only when they
# appear outside quotes.
claim_shell_segments() {
  local s="$1"
  local n=${#s}
  local i=0 c c2 state=0
  local tok="" have_tok=0 seg_line="" out="" expect_hd=0
  local -a stack=()
  local -a pending_hd=()

  while [ "$i" -lt "$n" ]; do
    c="${s:i:1}"

    # --- inside single quotes: everything is literal until the next quote ---
    if [ "$state" -eq 1 ]; then
      if [ "$c" = "'" ]; then state=0; else tok="${tok}${c}"; fi
      i=$((i + 1))
      continue
    fi

    # --- inside double quotes: literal apart from escapes and $( ) ---
    if [ "$state" -eq 2 ]; then
      if [ "$c" = '\' ] && [ $((i + 1)) -lt "$n" ]; then
        c2="${s:i+1:1}"
        case "$c2" in
          '"'|'\'|'$'|'`') tok="${tok}${c2}"; i=$((i + 2)); continue ;;
        esac
        tok="${tok}${c}"; i=$((i + 1)); continue
      fi
      if [ "$c" = '"' ]; then state=0; i=$((i + 1)); continue; fi
      if [ "$c" = '$' ] && [ "${s:i+1:1}" = '(' ]; then
        stack[${#stack[@]}]=2
        _claim_emit_seg
        state=0
        i=$((i + 2))
        continue
      fi
      tok="${tok}${c}"
      have_tok=1
      i=$((i + 1))
      continue
    fi

    # --- unquoted ---
    case "$c" in
      "'") state=1; have_tok=1; i=$((i + 1)); continue ;;
      '"') state=2; have_tok=1; i=$((i + 1)); continue ;;
      '\')
        if [ $((i + 1)) -lt "$n" ]; then
          c2="${s:i+1:1}"
          if [ "$c2" != $'\n' ]; then tok="${tok}${c2}"; have_tok=1; fi
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        continue
        ;;
    esac

    if [ "$c" = '$' ] && [ "${s:i+1:1}" = '(' ]; then
      stack[${#stack[@]}]=0
      _claim_emit_seg
      i=$((i + 2))
      continue
    fi
    if [ "$c" = ')' ] && [ "${#stack[@]}" -gt 0 ]; then
      _claim_emit_seg
      state="${stack[$((${#stack[@]} - 1))]}"
      unset "stack[$((${#stack[@]} - 1))]"
      i=$((i + 1))
      continue
    fi

    # Heredoc / herestring operators. `<<WORD` introduces a body that is pure
    # data — the single most misleading place for a command-shaped string to
    # sit — so the delimiter is recorded and the body skipped wholesale.
    if [ "$c" = '<' ] && [ "${s:i+1:1}" = '<' ]; then
      _claim_emit_tok
      if [ "${s:i+2:1}" = '<' ]; then
        i=$((i + 3))          # <<< herestring: the word after it is data
      else
        i=$((i + 2))
        [ "${s:i:1}" = '-' ] && i=$((i + 1))
        expect_hd=1
      fi
      continue
    fi

    # Redirections are not arguments, and their operands are files or file
    # descriptors — never refs. Both halves have to go:
    #
    #   `2>&1`        the leading 2 is an fd, not a positional argument
    #   `2>/dev/null` /dev/null is a path, not a positional argument
    #
    # Emitting either one as a token is what made `git push origin br 2>&1`
    # read as a push to a branch named `2`, minting a 900s phantom claim on
    # every redirected git command. Consume the operator and its operand here.
    if [ "$c" = '>' ] || [ "$c" = '<' ] ||
       { [ "$c" = '&' ] && [ "${s:i+1:1}" = '>' ]; }; then
      # A pending all-digits token is this redirect's fd prefix, not an arg.
      case "$tok" in
        ''|*[!0-9]*) : ;;
        *) tok=""; have_tok=0 ;;
      esac
      _claim_emit_tok
      [ "$c" = '&' ] && i=$((i + 1))        # &>
      i=$((i + 1))                          # the > or <
      [ "${s:i:1}" = '>' ] && i=$((i + 1))  # >> append
      [ "${s:i:1}" = '&' ] && i=$((i + 1))  # >& duplicate
      while [ "$i" -lt "$n" ] && { [ "${s:i:1}" = ' ' ] || [ "${s:i:1}" = $'\t' ]; }; do
        i=$((i + 1))
      done
      while [ "$i" -lt "$n" ]; do           # the operand word
        c2="${s:i:1}"
        case "$c2" in
          ' '|$'\t'|$'\n'|';'|'&'|'|'|'('|')') break ;;
        esac
        i=$((i + 1))
      done
      continue
    fi

    case "$c" in
      ' '|$'\t') _claim_emit_tok; i=$((i + 1)); continue ;;
      $'\n')     _claim_emit_seg; i=$((i + 1)); _claim_skip_heredocs; continue ;;
      ';'|'&'|'|'|'('|')') _claim_emit_seg; i=$((i + 1)); continue ;;
      '`')       _claim_emit_seg; i=$((i + 1)); continue ;;
    esac

    tok="${tok}${c}"
    have_tok=1
    i=$((i + 1))
  done

  _claim_emit_seg
  printf '%s' "$out"
}

# claim_effective_segments <command> [depth]
#
# claim_shell_segments, with each segment reduced to the argv the shell would
# actually exec: leading `FOO=bar` assignments and wrapper programs (`sudo`,
# `env`, `timeout`, …) removed, so token 0 is always the program being run.
#
# `sh -c '<string>'` is descended into rather than dropped: the string it
# carries IS a command, and treating it as an opaque argument would be a false
# negative of exactly the kind this parser exists to avoid. Depth is capped so a
# pathological nesting cannot spin.
claim_effective_segments() {
  local depth="${2:-0}"
  local seg out="" k m t wrapped line base ci inner nested
  local -a toks=()

  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    IFS="$_CLAIM_TOKSEP" read -ra toks <<< "$seg"
    m=${#toks[@]}
    k=0
    wrapped=0
    while [ "$k" -lt "$m" ]; do
      t="${toks[$k]}"
      case "$t" in
        [A-Za-z_]*=*) k=$((k + 1)) ;;
        sudo|env|command|builtin|exec|nohup|nice|time|timeout|stdbuf)
          k=$((k + 1)); wrapped=1 ;;
        -*|[0-9]*)
          if [ "$wrapped" -eq 1 ]; then k=$((k + 1)); else break; fi ;;
        *) break ;;
      esac
    done
    [ "$k" -lt "$m" ] || continue

    base="${toks[$k]##*/}"
    case "$base" in
      sh|bash|zsh|ksh|dash)
        if [ "$depth" -lt 4 ]; then
          ci=$((k + 1))
          inner=""
          while [ "$ci" -lt "$m" ]; do
            if [ "${toks[$ci]}" = "-c" ] && [ $((ci + 1)) -lt "$m" ]; then
              inner="${toks[$((ci + 1))]}"
              break
            fi
            ci=$((ci + 1))
          done
          if [ -n "$inner" ]; then
            # Command substitution eats the trailing newline; restore it so the
            # nested segments stay one-per-line.
            nested="$(claim_effective_segments "$inner" $((depth + 1)))"
            [ -n "$nested" ] && out="${out}${nested}"$'\n'
            continue
          fi
        fi
        ;;
    esac

    line=""
    while [ "$k" -lt "$m" ]; do
      if [ -n "$line" ]; then line="${line}${_CLAIM_TOKSEP}"; fi
      line="${line}${toks[$k]}"
      k=$((k + 1))
    done
    [ -n "$line" ] && out="${out}${line}"$'\n'
  done <<< "$(claim_shell_segments "$1")"

  printf '%s' "$out"
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

# _claim_push_segment_dests <fallback>
# Reads the caller's `toks`, `argstart` and `m`; appends to the caller's `dsts`
# and, on failure, sets the caller's `push_err` and returns 1. It deliberately
# writes nothing to stdout: capturing its output would put it in a subshell, and
# the destinations it appends to `dsts` would be discarded with that subshell.
_claim_push_segment_dests() {
  local fallback="$1" i tok delete=0 broad="" nomoreflags=0
  local -a positional=()

  i="$argstart"
  while [ "$i" -lt "$m" ]; do
    tok="${toks[$i]}"
    if [ "$nomoreflags" -eq 1 ]; then
      positional[${#positional[@]}]="$tok"
      i=$((i + 1))
      continue
    fi
    case "$tok" in
      --) nomoreflags=1 ;;
      -d|--delete) delete=1 ;;
      --all|--mirror) broad="$tok" ;;
      # Flags that consume the NEXT argument — skip both, or their value would
      # be misread as the remote/refspec.
      -o|--push-option|--receive-pack|--exec|--repo) i=$((i + 1)) ;;
      -*) : ;;
      *) positional[${#positional[@]}]="$tok" ;;
    esac
    i=$((i + 1))
  done

  if [ -n "$broad" ]; then
    push_err="the push uses ${broad}, which sends every ref — the set of destination branches cannot be enumerated from the command"
    return 1
  fi

  if [ "${#positional[@]}" -le 1 ]; then
    # Bare `git push` / `git push <remote>`: git resolves the destination from
    # the current branch's upstream. Resolve the SAME way, or fail loud.
    if [ "$delete" -eq 1 ]; then
      push_err="--delete was given with no ref to delete, so the destination branch cannot be determined"
      return 1
    fi
    if [ -z "$fallback" ]; then
      push_err="the push names no refspec and the current branch/upstream could not be resolved, so the destination branch cannot be determined"
      return 1
    fi
    dsts[${#dsts[@]}]="$fallback"
    return 0
  fi

  local spec dst had_colon
  for spec in "${positional[@]:1}"; do
    dst="${spec#+}"
    had_colon=0
    case "$dst" in *:*) had_colon=1; dst="${dst#*:}" ;; esac
    dst="${dst#refs/heads/}"
    if [ "$dst" = "HEAD" ] && [ "$had_colon" -eq 0 ]; then
      if [ -z "$fallback" ]; then
        push_err="the push targets HEAD but the current branch could not be resolved, so the destination branch cannot be determined"
        return 1
      fi
      dst="$fallback"
    fi
    case "$dst" in
      ""|HEAD|*'*'*)
        push_err="refspec ${spec} does not resolve to a single named destination branch"
        return 1
        ;;
    esac
    dsts[${#dsts[@]}]="$dst"
  done
  return 0
}

# claim_push_destinations <command> [fallback-branch]
#
# Prints one line per resolved destination: DEST<TAB><branch>
# On failure prints exactly one line:      ERROR<TAB><reason>
#
# Returns 0 = destinations printed
#         1 = destination undeterminable (caller MUST fail loud, never allow)
#         2 = the command invokes no `git push` at all (nothing to guard)
#
# Only a segment whose FIRST word is `git` (with subcommand `push`) counts. A
# `git push` appearing inside a quoted argument, a `-m` message or a heredoc
# body is text, not an invocation, and yields no destinations.
#
# <fallback-branch> is used ONLY where git itself would use the current branch's
# upstream/name: a bare `git push`, `git push <remote>`, or `git push <remote>
# HEAD`. It is never a default-branch guess; when it is empty in those cases the
# function errors instead.
claim_push_destinations() {
  local cmd="$1" fallback="${2:-}"
  local seg base j m argstart found=0 push_err=""
  local -a toks=()
  local -a dsts=()

  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    IFS="$_CLAIM_TOKSEP" read -ra toks <<< "$seg"
    m=${#toks[@]}
    [ "$m" -gt 0 ] || continue
    base="${toks[0]##*/}"
    [ "$base" = "git" ] || continue

    # Locate `push` as the subcommand, tolerating git's global options
    # (`git -C dir push`, `git -c k=v push`).
    argstart=-1
    j=1
    while [ "$j" -lt "$m" ]; do
      case "${toks[$j]}" in
        -C|-c|--git-dir|--work-tree|--namespace|--exec-path) j=$((j + 2)) ;;
        push) argstart=$((j + 1)); break ;;
        -*) j=$((j + 1)) ;;
        *) break ;;
      esac
    done
    [ "$argstart" -ge 0 ] || continue

    found=1
    if ! _claim_push_segment_dests "$fallback"; then
      printf 'ERROR\t%s\n' "$push_err"
      return 1
    fi
  done <<< "$(claim_effective_segments "$cmd")"

  [ "$found" -eq 1 ] || return 2

  if [ "${#dsts[@]}" -eq 0 ]; then
    printf 'ERROR\ta git push was invoked but no destination branch could be extracted from it\n'
    return 1
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
