#!/usr/bin/env bash
# shellcheck shell=bash
# command-tokens.sh — the shell tokeniser shared by the guards that read a Bash
# command: lib/agent-claim.sh (the concurrency guard, protect-other-branches.sh)
# and permission-guard.sh (ADR 004 item 4: "a tokeniser lib shared with
# hooks/lib/agent-claim.sh").
#
# Sourced, never executed. Bash 3.2 compatible, builtins only.
#
# WHY A TOKENIZER AND NOT A TEXT SEARCH
#   A guard's question is "which commands does this string invoke?", and a
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
#   destinations, `gh` artifact targets, permission action ids) keys on that
#   first word, never on the raw text.
#
#   Stripping quoted regions before matching would be only half a fix: it
#   correctly drops `git commit -m "git push origin dev"`, but it must not lose
#   the real push in `git commit -m "wip" && git push origin dev`. Segmenting
#   on separators that are themselves outside quotes is what keeps both true.
#
# FUNCTIONS (each prints; one line per segment, tokens joined by CMDTOK_SEP)
#   cmdtok_segments <command> [keep]
#       The raw segments. Quotes are consumed (their content stays inside one
#       token), heredoc bodies are dropped, and `;`, `&`, `|`, newline, `(`/`)`
#       and command substitutions start a new segment — but only outside quotes.
#       With `keep` (the permission guard's mode) a command substitution
#       `$(...)` or `...` is ALSO kept, verbatim, inside the word it sits in,
#       so `curl -H "token $(gh auth status)" https://…` stays one curl segment;
#       the commands inside the substitution are emitted as their own segments,
#       each line prefixed with CMDTOK_NESTED, so the caller can tell "runs in a
#       subshell" from "runs here". `$((…))` arithmetic stays literal text.
#   cmdtok_effective_segments <command> [depth]
#       agent-claim's view: each segment reduced to the argv the shell would exec
#       (leading assignments and wrappers such as sudo/env/timeout removed, so
#       token 0 is the program), with `sh -c '<string>'` descended into.
#   cmdtok_argv_segments <command> [depth]
#       the permission guard's view (keep mode): leading reserved words (`if`,
#       `then`, `do`, `{`, `!`, …) dropped, assignments and wrappers KEPT (the
#       catalog matches env assignments such as HUSKY=0 and GH_REPO=…), and
#       `sh|bash|zsh -c '<string>'` (also `-lc`, `-ec`) replaced by the commands
#       of its string, marked CMDTOK_NESTED, with the outer segment's
#       assignments prepended to each (they are the child's environment).
#
# NOT SEEN (the residual ADR 004 D1 names): aliases (never expanded), eval,
# xargs, make, interpreters (`python3 -c`, `node -e`), a script file's contents,
# and anything built at runtime from variables.

# Unit separator: cannot occur in a shell word we care about, so it is a safe
# in-band delimiter between tokens of one segment (segments are newline-separated).
CMDTOK_SEP=$'\037'
# Record separator: leads a segment line that runs in a subshell (keep mode).
CMDTOK_NESTED=$'\036'

# The helpers below deliberately operate on the caller's locals (bash is
# dynamically scoped). They are only ever called from cmdtok_segments.

_cmdtok_emit_tok() {
  if [ "$have_tok" -eq 1 ]; then
    if [ "$expect_hd" -eq 1 ]; then
      # This word is a heredoc delimiter, not an argument: record it so the
      # body it introduces can be skipped, and do not emit it.
      expect_hd=0
      pending_hd[${#pending_hd[@]}]="$tok"
    else
      tok="${tok//$'\n'/ }"
      if [ -n "$seg_line" ]; then seg_line="${seg_line}${CMDTOK_SEP}"; fi
      seg_line="${seg_line}${tok}"
    fi
  fi
  tok=""
  have_tok=0
}

_cmdtok_emit_seg() {
  _cmdtok_emit_tok
  # seg_pfx is empty except inside a keep-mode substitution.
  if [ -n "$seg_line" ]; then out="${out}${seg_pfx}${seg_line}"$'\n'; fi
  seg_line=""
}

# Skip every pending heredoc body. Called after a newline is consumed at depth
# zero — exactly where the shell itself starts reading heredoc content.
_cmdtok_skip_heredocs() {
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

# Keep mode: open a substitution (kind paren for `$(`, tick for a backtick).
# The outer word and segment are saved; the substitution's commands become
# nested segments until _cmdtok_close_subst puts the outer context back.
_cmdtok_open_subst() {
  k_seg[kd]="$seg_line"
  k_tok[kd]="$tok"
  k_state[kd]="$state"
  k_start[kd]="$i"
  k_kind[kd]="$1"
  k_par[kd]=0
  kd=$((kd + 1))
  seg_line=""
  tok=""
  have_tok=0
  state=0
  seg_pfx="$CMDTOK_NESTED"
  if [ "$1" = paren ]; then i=$((i + 2)); else i=$((i + 1)); fi
}

# Keep mode: close the innermost substitution at s[i] (or at the end of the
# string when <end> is given). The outer word gets the substitution's raw text.
_cmdtok_close_subst() {
  local start len
  _cmdtok_emit_seg
  kd=$((kd - 1))
  start="${k_start[kd]}"
  if [ -n "${1:-}" ]; then len=$((n - start)); else len=$((i + 1 - start)); fi
  seg_line="${k_seg[kd]}"
  tok="${k_tok[kd]}${s:start:len}"
  have_tok=1
  state="${k_state[kd]}"
  [ "$kd" -gt 0 ] || seg_pfx=""
  i=$((start + len))
}

cmdtok_segments() {
  local s="$1" keep="${2:-}"
  local n=${#s}
  local i=0 c c2 state=0
  local tok="" have_tok=0 seg_line="" out="" expect_hd=0 seg_pfx="" rest arith
  local -a stack=()
  local -a pending_hd=()
  local kd=0
  local -a k_seg=() k_tok=() k_state=() k_start=() k_kind=() k_par=()

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
      if [ -n "$keep" ]; then
        if [ "$c" = '$' ] && [ "${s:i+1:2}" = '((' ]; then
          rest="${s:i}"
          arith="${rest%%"))"*}"
          if [ "$arith" != "$rest" ]; then
            tok="${tok}${arith}))"
            i=$((i + ${#arith} + 2))
            continue
          fi
        fi
        if [ "$c" = '$' ] && [ "${s:i+1:1}" = '(' ]; then
          _cmdtok_open_subst paren
          continue
        fi
        if [ "$c" = '`' ]; then
          if [ "$kd" -gt 0 ] && [ "${k_kind[$((kd - 1))]}" = tick ]; then
            _cmdtok_close_subst
          else
            _cmdtok_open_subst tick
          fi
          continue
        fi
      fi
      if [ "$c" = '$' ] && [ "${s:i+1:1}" = '(' ]; then
        stack[${#stack[@]}]=2
        _cmdtok_emit_seg
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

    if [ -n "$keep" ]; then
      # $(( arithmetic )): text, never a command.
      if [ "$c" = '$' ] && [ "${s:i+1:2}" = '((' ]; then
        rest="${s:i}"
        arith="${rest%%"))"*}"
        if [ "$arith" != "$rest" ]; then
          tok="${tok}${arith}))"
          have_tok=1
          i=$((i + ${#arith} + 2))
          continue
        fi
      fi
      if [ "$c" = '$' ] && [ "${s:i+1:1}" = '(' ]; then
        _cmdtok_open_subst paren
        continue
      fi
      if [ "$kd" -gt 0 ] && [ "${k_kind[$((kd - 1))]}" = paren ]; then
        # A subshell inside the substitution: its parens are separators, and
        # only the paren that balances `$(` closes it.
        if [ "$c" = '(' ]; then k_par[kd - 1]=$(( ${k_par[$((kd - 1))]} + 1 )); fi
        if [ "$c" = ')' ]; then
          if [ "${k_par[$((kd - 1))]}" -eq 0 ]; then
            _cmdtok_close_subst
            continue
          fi
          k_par[kd - 1]=$(( ${k_par[$((kd - 1))]} - 1 ))
        fi
      fi
      if [ "$c" = '`' ]; then
        if [ "$kd" -gt 0 ] && [ "${k_kind[$((kd - 1))]}" = tick ]; then
          _cmdtok_close_subst
        else
          _cmdtok_open_subst tick
        fi
        continue
      fi
    fi

    if [ "$c" = '$' ] && [ "${s:i+1:1}" = '(' ]; then
      stack[${#stack[@]}]=0
      _cmdtok_emit_seg
      i=$((i + 2))
      continue
    fi
    if [ "$c" = ')' ] && [ "${#stack[@]}" -gt 0 ]; then
      _cmdtok_emit_seg
      state="${stack[$((${#stack[@]} - 1))]}"
      unset "stack[$((${#stack[@]} - 1))]"
      i=$((i + 1))
      continue
    fi

    # Heredoc / herestring operators. `<<WORD` introduces a body that is pure
    # data — the single most misleading place for a command-shaped string to
    # sit — so the delimiter is recorded and the body skipped wholesale.
    if [ "$c" = '<' ] && [ "${s:i+1:1}" = '<' ]; then
      _cmdtok_emit_tok
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
      _cmdtok_emit_tok
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
      ' '|$'\t') _cmdtok_emit_tok; i=$((i + 1)); continue ;;
      $'\n')     _cmdtok_emit_seg; i=$((i + 1)); _cmdtok_skip_heredocs; continue ;;
      ';'|'&'|'|'|'('|')') _cmdtok_emit_seg; i=$((i + 1)); continue ;;
      '`')       _cmdtok_emit_seg; i=$((i + 1)); continue ;;
    esac

    tok="${tok}${c}"
    have_tok=1
    i=$((i + 1))
  done

  # Keep mode: a substitution left open at the end of the string closes there.
  while [ "$kd" -gt 0 ]; do
    _cmdtok_close_subst end
  done

  _cmdtok_emit_seg
  printf '%s' "$out"
}

# cmdtok_effective_segments <command> [depth]
#
# cmdtok_segments, with each segment reduced to the argv the shell would
# actually exec: leading `FOO=bar` assignments and wrapper programs (`sudo`,
# `env`, `timeout`, …) removed, so token 0 is always the program being run.
#
# `sh -c '<string>'` is descended into rather than dropped: the string it
# carries IS a command, and treating it as an opaque argument would be a false
# negative of exactly the kind this parser exists to avoid. Depth is capped so a
# pathological nesting cannot spin.
cmdtok_effective_segments() {
  local depth="${2:-0}"
  local seg out="" k m t wrapped line base ci inner nested
  local -a toks=()

  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    IFS="$CMDTOK_SEP" read -ra toks <<< "$seg"
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
            nested="$(cmdtok_effective_segments "$inner" $((depth + 1)))"
            [ -n "$nested" ] && out="${out}${nested}"$'\n'
            continue
          fi
        fi
        ;;
    esac

    line=""
    while [ "$k" -lt "$m" ]; do
      if [ -n "$line" ]; then line="${line}${CMDTOK_SEP}"; fi
      line="${line}${toks[$k]}"
      k=$((k + 1))
    done
    [ -n "$line" ] && out="${out}${line}"$'\n'
  done <<< "$(cmdtok_segments "$1")"

  printf '%s' "$out"
}

# cmdtok_argv_segments <command> [depth] [prefix-assignments]
#
# The permission guard's view; see the header. A line that starts with
# CMDTOK_NESTED runs in a subshell (a substitution or an `sh -c` string): its
# `cd` does not move the commands after it.
cmdtok_argv_segments() {
  local depth="${2:-0}" pre="${3:-}"
  local seg pfx out="" k p m t wrapped line base ci inner nested assigns nline
  local -a toks=()

  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    pfx=""
    case "$seg" in
      "$CMDTOK_NESTED"*) pfx="$CMDTOK_NESTED"; seg="${seg#"$CMDTOK_NESTED"}" ;;
    esac
    [ "$depth" -gt 0 ] && pfx="$CMDTOK_NESTED"
    [ -n "$seg" ] || continue
    IFS="$CMDTOK_SEP" read -ra toks <<< "$seg"
    m=${#toks[@]}
    k=0
    while [ "$k" -lt "$m" ]; do
      case "${toks[$k]}" in
        '!'|'{'|'}'|if|then|elif|else|fi|do|done|while|until) k=$((k + 1)) ;;
        *) break ;;
      esac
    done
    [ "$k" -lt "$m" ] || continue

    # The program behind assignments and wrappers, for the `sh -c` check.
    p="$k"
    wrapped=0
    assigns="$pre"
    while [ "$p" -lt "$m" ]; do
      t="${toks[$p]}"
      case "$t" in
        [A-Za-z_]*=*)
          assigns="${assigns}${t}${CMDTOK_SEP}"
          p=$((p + 1)) ;;
        sudo|env|command|builtin|exec|nohup|nice|time|timeout|stdbuf)
          p=$((p + 1)); wrapped=1 ;;
        -*|[0-9]*)
          if [ "$wrapped" -eq 1 ]; then p=$((p + 1)); else break; fi ;;
        *) break ;;
      esac
    done

    if [ "$p" -lt "$m" ] && [ "$depth" -lt 4 ]; then
      base="${toks[$p]##*/}"
      case "$base" in
        sh|bash|zsh|ksh|dash)
          ci=$((p + 1))
          inner=""
          while [ "$ci" -lt "$m" ]; do
            case "${toks[$ci]}" in
              --*) : ;;
              -c|-*c*)
                if [ $((ci + 1)) -lt "$m" ]; then inner="${toks[$((ci + 1))]}"; fi
                break ;;
            esac
            ci=$((ci + 1))
          done
          if [ -n "$inner" ]; then
            nested="$(cmdtok_argv_segments "$inner" $((depth + 1)) "$assigns")"
            [ -n "$nested" ] && out="${out}${nested}"$'\n'
            continue
          fi
          ;;
      esac
    fi

    line="${pre}"
    while [ "$k" -lt "$m" ]; do
      line="${line}${toks[$k]}"
      k=$((k + 1))
      [ "$k" -lt "$m" ] && line="${line}${CMDTOK_SEP}"
    done
    nline="${pfx}${line}"
    [ -n "$line" ] && out="${out}${nline}"$'\n'
  done <<< "$(cmdtok_segments "$1" keep)"

  printf '%s' "$out"
}
