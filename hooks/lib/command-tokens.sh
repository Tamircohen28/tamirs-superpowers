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
#       `then`, `do`, `{`, `!`, `function NAME`, `coproc [NAME]`, …) dropped,
#       assignments and wrappers KEPT (the catalog matches env assignments such
#       as HUSKY=0 and GH_REPO=…), and the string a shell runs replaced by its
#       commands, marked CMDTOK_NESTED, with the outer segment's assignments
#       prepended to each (they are the child's environment): `sh|bash|zsh -c
#       '<string>'` (also `-lc`, `-ec`, after `-o`/`-O`/`--rcfile` values),
#       `su|runuser -c`, `env -S '<string>'`, `watch <words>`, a herestring
#       fed to a shell, and each `find -exec … ;` / `fd -x …` command.
#
# KEEP MODE READS WHAT A SHELL READS (ADR 004 D1, SR S-07)
#   The guard must not see a different command from the one that runs, so
#   keep mode also follows `# comments`, ANSI-C `$'…'` quotes, `((…))`,
#   process substitution `<(…)`/`>(…)` (its commands nested), nested
#   backticks, `||` (no pipe), and here-documents: the body of one fed to a
#   shell (`bash <<EOF`, `cat <<EOF | sh`) is read as commands, and the
#   `$(…)` of an unquoted-delimiter body as nested commands. A segment whose
#   stdin is a pipe starts with the CMDTOK_PIPED token (dropped by
#   cmdtok_argv_segments). Wrappers it looks through: sudo, doas, env,
#   command, builtin, exec (-a), nohup, nice, time, timeout, gtimeout, stdbuf,
#   caffeinate, arch, setsid, xargs, ionice, each with its value options.
#
#   Where it cannot be sure it reads the command as a shell would, it says
#   so: a line `CMDTOK_ANOMALY<what>` (unterminated quote, here-document or
#   substitution, `$'`, `((`, `case` inside a substitution, nested
#   backticks, a substitution inside `$((…))`, shell nesting deeper than 4, a
#   shell reading its script from a pipe or a process substitution). The
#   guard treats any such line as UNCLASSIFIED (R4: never automatic).
#
#   Default mode (agent-claim's cmdtok_segments and cmdtok_effective_segments)
#   is unchanged by all of this: every keep-mode reading above is gated on
#   `keep`, so the concurrency guard's claims stay byte-identical.
#
# NOT SEEN (the residual ADR 004 D1 names): aliases (never expanded), eval,
# make, interpreters (`python3 -c`, `node -e`), a script file's contents,
# and anything built at runtime from variables.

# The five separators are control characters, built from their code points by jq (which every hook
# that loads this file already requires), so this file holds neither the bytes themselves (a text file
# stays a text file for the plugin directory's validator) nor a numeric escape (which the directory's scan
# reads as a possibly hidden character). Objective hook-answer-proof.
#   CMDTOK_SEP     Unit separator (31): cannot occur in a shell word we care about, so it is a safe
#                  in-band delimiter between tokens of one segment (segments are newline-separated).
#   CMDTOK_NESTED  Record separator (30): leads a segment line that runs in a subshell (keep mode).
#   CMDTOK_ANOMALY Group separator (29), keep mode only: leads a line naming a construct the tokeniser
#                  could not read the way a shell does (the guard fails closed on it).
#   CMDTOK_HERESTR File separator (28): leads a token that is a herestring's data (`<<< word`).
#   CMDTOK_PIPED   Substitute (26): a token leading a segment whose stdin is a pipe.
# Without jq the separators cannot be built and nothing here can tokenise safely: loading fails, and both
# callers turn that into a fail-closed exit (permission-guard.sh `|| exit 1`, agent-claim.sh likewise).
IFS=' ' read -r CMDTOK_SEP CMDTOK_NESTED CMDTOK_ANOMALY CMDTOK_HERESTR CMDTOK_PIPED \
  < <(jq -nr '[31, 32, 30, 32, 29, 32, 28, 32, 26] | implode' 2>/dev/null) || true
if [ "${#CMDTOK_SEP}" != 1 ] || [ "${#CMDTOK_NESTED}" != 1 ] || [ "${#CMDTOK_ANOMALY}" != 1 ] \
   || [ "${#CMDTOK_HERESTR}" != 1 ] || [ "${#CMDTOK_PIPED}" != 1 ]; then
  echo "command-tokens.sh: jq is required to build the tokeniser's separators" >&2
  return 1 2>/dev/null || exit 1
fi
# The characters that end a run of literal text unquoted and inside double
# quotes: up to the next one, a run is appended in one step rather than one
# character at a time (the per-character append is what made a long command
# quadratic). The single quote in _CMDTOK_STOP0 is its own double-quoted part.
_CMDTOK_STOP0=$' \t\n'"'"'"\$()|;&<>`'
_CMDTOK_STOPD=$'\\"$`'

# _hook_put <text> writes <text> to stdout exactly as given: no trailing newline,
# no option or backslash processing. _hook_putln adds one newline. They stand in
# for format-string prints, so this file holds no printf conversion: the plugin
# directory's scan reads every printf carrying a % conversion as an answer it
# cannot prove harmless (objective hook-answer-proof). A bare echo would read a
# value that starts with "-" (say "-n") as its own option, so leading dashes go
# out one at a time first. Kept identical in command-tokens.sh,
# objective-common.sh and worktree-common.sh: whichever file loads last
# redefines the same body.
_hook_put() {
  local s="${1-}"
  while [[ "$s" == -* ]]; do echo -nE -; s="${s#-}"; done
  echo -nE "$s"
}
_hook_putln() { _hook_put "${1-}"; echo; }

# The helpers below deliberately operate on the caller's locals (bash is
# dynamically scoped). They are only ever called from cmdtok_segments.

_cmdtok_emit_tok() {
  if [ "$have_tok" -eq 1 ]; then
    if [ "$expect_hd" -eq 1 ]; then
      # This word is a heredoc delimiter, not an argument: record it so the
      # body it introduces can be skipped, and do not emit it. Keep mode also
      # records whether it was quoted (a quoted delimiter expands nothing).
      expect_hd=0
      pending_hd[${#pending_hd[@]}]="$tok"
      pending_hdq[${#pending_hdq[@]}]="$tok_q"
    else
      tok="${tok//$'\n'/ }"
      if [ "$hs_next" -eq 1 ]; then tok="${CMDTOK_HERESTR}${tok}"; hs_next=0; fi
      if [ -n "$seg_line" ]; then seg_line="${seg_line}${CMDTOK_SEP}"; fi
      seg_line="${seg_line}${tok}"
    fi
  fi
  tok=""
  have_tok=0
  tok_q=0
}

_cmdtok_emit_seg() {
  _cmdtok_emit_tok
  # seg_pfx is empty except inside a keep-mode substitution.
  if [ -n "$seg_line" ]; then
    if [ -n "$keep" ]; then
      _cmdtok_note_seg
      if [ "$pipe_next" -eq 1 ]; then seg_line="${CMDTOK_PIPED}${CMDTOK_SEP}${seg_line}"; pipe_next=0; fi
    fi
    out="${out}${seg_pfx}${seg_line}"$'\n'
  fi
  seg_line=""
}

# Keep mode: record an anomaly once (the caller's `anomalies`).
_cmdtok_anomaly() {
  case "$anomalies" in *"${CMDTOK_ANOMALY}$1"$'\n'*) return 0 ;; esac
  anomalies="${anomalies}${CMDTOK_ANOMALY}$1"$'\n'
}

# _cmdtok_is_shell <word> — 0 when the basename of <word> is a POSIX-family
# shell, in any case (a case-insensitive file system runs `BASH`).
_cmdtok_is_shell() {
  local b="${1##*/}" r=1 nc=0
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  case "$b" in sh|bash|zsh|ksh|dash|mksh|yash|ash|posh|rbash|fish) r=0 ;; esac
  [ "$nc" = 1 ] || shopt -u nocasematch
  return "$r"
}

# _cmdtok_wrapper_name <word> — sets _ct_w to the wrapper <word> names (any
# case), or "" when it names none. A wrapper runs the command that follows it.
_cmdtok_wrapper_name() {
  local b="${1##*/}" nc=0
  _ct_w=""
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  case "$b" in
    sudo) _ct_w="sudo" ;; doas) _ct_w="doas" ;; env) _ct_w="env" ;; command) _ct_w="command" ;;
    builtin) _ct_w="builtin" ;; exec) _ct_w="exec" ;; nohup) _ct_w="nohup" ;; nice) _ct_w="nice" ;;
    time) _ct_w="time" ;; timeout|gtimeout) _ct_w="timeout" ;; stdbuf) _ct_w="stdbuf" ;;
    caffeinate) _ct_w="caffeinate" ;; arch) _ct_w="arch" ;; setsid) _ct_w="setsid" ;;
    xargs) _ct_w="xargs" ;; ionice) _ct_w="ionice" ;;
  esac
  [ "$nc" = 1 ] || shopt -u nocasematch
}

# _cmdtok_wrapper_takes <wrapper> <option> — 0 when the option takes the next
# word as its value (so that word is not the program).
_cmdtok_wrapper_takes() {
  case "$1:$2" in
    sudo:-u|sudo:-g|sudo:-h|sudo:-p|sudo:-C|sudo:-U|sudo:-r|sudo:-t|sudo:-D|sudo:-R|sudo:-T) return 0 ;;
    sudo:--user|sudo:--group|sudo:--host|sudo:--prompt|sudo:--close-from|sudo:--other-user) return 0 ;;
    sudo:--role|sudo:--type|sudo:--chdir|sudo:--chroot|sudo:--command-timeout) return 0 ;;
    doas:-u|doas:-C) return 0 ;;
    env:-u|env:-C|env:-P|env:--unset|env:--chdir) return 0 ;;
    exec:-a) return 0 ;;
    nice:-n|nice:--adjustment) return 0 ;;
    timeout:-s|timeout:-k|timeout:--signal|timeout:--kill-after) return 0 ;;
    caffeinate:-t|caffeinate:-w) return 0 ;;
    arch:-arch|arch:-e|arch:-d) return 0 ;;
    xargs:-I|xargs:-L|xargs:-n|xargs:-P|xargs:-s|xargs:-E|xargs:-e|xargs:-d|xargs:-a|xargs:-J|xargs:-R|xargs:-S) return 0 ;;
    xargs:--max-args|xargs:--max-lines|xargs:--max-procs|xargs:--max-chars|xargs:--delimiter|xargs:--arg-file) return 0 ;;
    xargs:--eof|xargs:--process-slot-var) return 0 ;;
    ionice:-c|ionice:-n|ionice:-p|ionice:-P|ionice:-u|ionice:--class|ionice:--classdata) return 0 ;;
    stdbuf:-i|stdbuf:-o|stdbuf:-e|stdbuf:--input|stdbuf:--output|stdbuf:--error) return 0 ;;
  esac
  return 1
}

# _cmdtok_find_prog — on the caller's toks[] (m entries), from index k: set p
# to the index of the program behind assignments, wrappers and the wrappers'
# options (their values skipped), append each assignment to `assigns`, and set
# split_at to the index of an `env -S`/`--split-string` (else -1).
_cmdtok_find_prog() {
  local t
  p="$k"; wrapped=0; wname=""; split_at=-1
  while [ "$p" -lt "$m" ]; do
    t="${toks[$p]}"
    case "$t" in
      [A-Za-z_]*=*) assigns="${assigns}${t}${CMDTOK_SEP}"; p=$((p + 1)); continue ;;
    esac
    _cmdtok_wrapper_name "$t"
    if [ -n "$_ct_w" ]; then wname="$_ct_w"; wrapped=1; p=$((p + 1)); continue; fi
    if [ "$wrapped" -eq 1 ]; then
      if [ "$wname" = env ]; then
        case "$t" in -S*|--split-string|--split-string=*) split_at="$p"; return 0 ;; esac
      fi
      case "$t" in
        -*|+*) if _cmdtok_wrapper_takes "$wname" "$t"; then p=$((p + 2)); else p=$((p + 1)); fi; continue ;;
        [0-9]*) p=$((p + 1)); continue ;;
      esac
    fi
    return 0
  done
}

# _cmdtok_prog_kind <basename> — sets _ct_kind to source, su, watch, find or "".
_cmdtok_prog_kind() {
  local nc=0
  _ct_kind=""
  case "$1" in source|.) _ct_kind=source; return 0 ;; esac
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  case "$1" in
    su|runuser) _ct_kind="su" ;;
    watch) _ct_kind="watch" ;;
    find|fd|fdfind) _ct_kind="find" ;;
  esac
  [ "$nc" = 1 ] || shopt -u nocasematch
}

# Keep mode, per emitted segment: a `case` inside a substitution (whose `)`
# patterns this tokeniser reads as the substitution's end), and whether the
# line runs a shell (then a here-document on it is that shell's script).
_cmdtok_note_seg() {
  local first="${seg_line%%"$CMDTOK_SEP"*}"
  if [ "$kd" -gt 0 ] && [ "$first" = case ]; then
    _cmdtok_anomaly "a case statement inside a command substitution"
  fi
  case "$seg_line" in
    *[sS][hH]*) _cmdtok_seg_runs_shell "$seg_line" && line_interp=1 ;;
  esac
  return 0
}

_cmdtok_seg_runs_shell() {
  local -a toks=()
  local m k p wrapped wname split_at assigns=""
  IFS="$CMDTOK_SEP" read -ra toks <<< "$1"
  m=${#toks[@]}
  k=0
  while [ "$k" -lt "$m" ]; do
    case "${toks[$k]}" in
      "$CMDTOK_PIPED"|'!'|'{'|'}'|if|then|elif|else|fi|do|done|while|until) k=$((k + 1)) ;;
      *) break ;;
    esac
  done
  _cmdtok_find_prog
  [ "$p" -lt "$m" ] && _cmdtok_is_shell "${toks[$p]}"
}

# Keep mode: the commands of <text> become nested segments of this command
# (a shell's here-document, the text of `((…))`/`$((…))`). With `subst`, only
# the command substitutions inside <text> are kept (its words are data).
_cmdtok_descend() {
  local text="$1" only="${2:-}" sub ln
  if [ "${_cmdtok_hd_depth:-0}" -ge 4 ]; then
    _cmdtok_anomaly "nesting deeper than 4 levels"
    return 0
  fi
  sub="$(_cmdtok_hd_depth=$(( ${_cmdtok_hd_depth:-0} + 1 )) cmdtok_segments "$text" keep)"
  while IFS= read -r ln; do
    [ -n "$ln" ] || continue
    case "$ln" in
      "$CMDTOK_ANOMALY"*) anomalies="${anomalies}${ln}"$'\n' ;;
      "$CMDTOK_NESTED"*) out="${out}${ln}"$'\n' ;;
      *) [ -n "$only" ] || out="${out}${CMDTOK_NESTED}${ln}"$'\n' ;;
    esac
  done <<< "$sub"
}

# Skip every pending heredoc body. Called after a newline is consumed at depth
# zero — exactly where the shell itself starts reading heredoc content.
_cmdtok_skip_heredocs() {
  local delim dq j ln trimmed body found
  while [ "${#pending_hd[@]}" -gt 0 ]; do
    delim="${pending_hd[0]}"
    dq="${pending_hdq[0]:-0}"
    if [ "${#pending_hd[@]}" -gt 1 ]; then
      pending_hd=("${pending_hd[@]:1}")
      pending_hdq=("${pending_hdq[@]:1}")
    else
      pending_hd=()
      pending_hdq=()
    fi
    body="" found=0
    while [ "$i" -lt "$n" ]; do
      j="$i"
      while [ "$j" -lt "$n" ] && [ "${s:j:1}" != $'\n' ]; do j=$((j + 1)); done
      ln="${s:i:j - i}"
      if [ "$j" -lt "$n" ]; then i=$((j + 1)); else i="$n"; fi
      trimmed="${ln#"${ln%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      if [ "$trimmed" = "$delim" ]; then found=1; break; fi
      [ -n "$keep" ] && body="${body}${ln}"$'\n'
    done
    if [ -n "$keep" ]; then
      [ "$found" -eq 1 ] || _cmdtok_anomaly "a here-document is not terminated"
      if [ "$line_interp" -eq 1 ]; then
        # The body is a shell's script: `bash <<EOF`, `cat <<EOF | sh`.
        _cmdtok_descend "$body"
      elif [ "$dq" = 0 ]; then
        # An unquoted delimiter expands the body like a double-quoted string:
        # its command substitutions run, whatever reads the text.
        case "$body" in *'$('*|*'`'*) _cmdtok_descend "\"${body//\"/\\\"}\"" subst ;; esac
      fi
    fi
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
  k_pipe[kd]="$pipe_next"
  kd=$((kd + 1))
  seg_line=""
  tok=""
  have_tok=0
  state=0
  pipe_next=0
  seg_pfx="$CMDTOK_NESTED"
  case "$1" in paren|tick2) i=$((i + 2)) ;; *) i=$((i + 1)) ;; esac
}

# Keep mode: close the innermost substitution at s[i] (or at the end of the
# string when <end> is given). The outer word gets the substitution's raw text.
_cmdtok_close_subst() {
  local start len
  _cmdtok_emit_seg
  kd=$((kd - 1))
  start="${k_start[kd]}"
  if [ -n "${1:-}" ]; then len=$((n - start))
  elif [ "${k_kind[kd]}" = tick2 ]; then len=$((i + 2 - start))
  else len=$((i + 1 - start)); fi
  seg_line="${k_seg[kd]}"
  tok="${k_tok[kd]}${s:start:len}"
  have_tok=1
  state="${k_state[kd]}"
  pipe_next="${k_pipe[kd]:-0}"
  [ "$kd" -gt 0 ] || seg_pfx=""
  i=$((start + len))
}

# Keep mode: the text of ((…)) or $((…)): a command substitution in it runs.
_cmdtok_arith_subst() {
  case "$1" in
    *'$('*|*'`'*)
      _cmdtok_anomaly "a command substitution inside an arithmetic expression"
      _cmdtok_descend "$1" subst ;;
  esac
  return 0
}

cmdtok_segments() {
  local s="$1" keep="${2:-}"
  local n=${#s}
  local i=0 c c2 state=0
  local tok="" have_tok=0 seg_line="" out="" expect_hd=0 seg_pfx="" rest arith
  local -a stack=()
  local -a pending_hd=() pending_hdq=()
  local kd=0
  local -a k_seg=() k_tok=() k_state=() k_start=() k_kind=() k_par=() k_pipe=()
  # Keep mode only: a quote or backslash in the current word, a herestring word
  # next, a pipe into the next segment, a shell on this line, the anomalies.
  local tok_q=0 hs_next=0 pipe_next=0 line_interp=0 anomalies="" run

  while [ "$i" -lt "$n" ]; do
    c="${s:i:1}"

    # --- keep mode, inside ANSI-C quotes $'…': a backslash escapes the next character ---
    if [ "$state" -eq 3 ]; then
      if [ "$c" = "\\" ] && [ $((i + 1)) -lt "$n" ]; then tok="${tok}${s:i+1:1}"; i=$((i + 2)); continue; fi
      if [ "$c" = "'" ]; then state=0; else tok="${tok}${c}"; fi
      i=$((i + 1))
      continue
    fi

    # --- inside single quotes: everything is literal until the next quote ---
    if [ "$state" -eq 1 ]; then
      run="${s:i:512}"; run="${run%%"'"*}"
      if [ -n "$run" ]; then tok="${tok}${run}"; i=$((i + ${#run})); continue; fi
      if [ "$c" = "'" ]; then state=0; else tok="${tok}${c}"; fi
      i=$((i + 1))
      continue
    fi

    # --- inside double quotes: literal apart from escapes and $( ) ---
    if [ "$state" -eq 2 ]; then
      if [ "$c" = "\\" ] && [ $((i + 1)) -lt "$n" ]; then
        c2="${s:i+1:1}"
        if [ -n "$keep" ] && [ "$c2" = '`' ] && [ "$kd" -gt 0 ]; then
          _cmdtok_anomaly "nested backticks"
        fi
        case "$c2" in
          '"'|"\\"|'$'|'`') tok="${tok}${c2}"; i=$((i + 2)); continue ;;
        esac
        tok="${tok}${c}"; i=$((i + 1)); continue
      fi
      if [ "$c" = '"' ]; then state=0; i=$((i + 1)); continue; fi
      if [ -n "$keep" ]; then
        if [ "$c" = '$' ] && [ "${s:i+1:2}" = '((' ]; then
          rest="${s:i}"
          arith="${rest%%"))"*}"
          if [ "$arith" != "$rest" ]; then
            _cmdtok_arith_subst "${arith#???}"
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
      run="${s:i:512}"; run="${run%%["$_CMDTOK_STOPD"]*}"
      if [ -n "$run" ]; then tok="${tok}${run}"; have_tok=1; i=$((i + ${#run})); continue; fi
      tok="${tok}${c}"
      have_tok=1
      i=$((i + 1))
      continue
    fi

    # --- unquoted ---
    if [ -n "$keep" ]; then
      # $'…' (ANSI-C quoting): its escapes (\x69, \', …) are not decoded here.
      if [ "$c" = '$' ] && [ "${s:i+1:1}" = "'" ]; then
        _cmdtok_anomaly "ANSI-C quoting (\$'...')"
        state=3; have_tok=1; tok_q=1; i=$((i + 2)); continue
      fi
      # A `#` that starts a word starts a comment, to the end of the line.
      if [ "$c" = '#' ] && [ "$have_tok" -eq 0 ]; then
        while [ "$i" -lt "$n" ] && [ "${s:i:1}" != $'\n' ]; do i=$((i + 1)); done
        continue
      fi
      # ((…)), an arithmetic command: its text is not commands (and `<<` in it
      # is a shift, not a here-document), though a substitution in it runs.
      if [ "$c" = '(' ] && [ "${s:i+1:1}" = '(' ] && [ "$have_tok" -eq 0 ]; then
        rest="${s:i+2}"
        arith="${rest%%"))"*}"
        _cmdtok_anomaly "an arithmetic command ((...))"
        if [ "$arith" != "$rest" ]; then
          _cmdtok_arith_subst "$arith"
          _cmdtok_emit_seg
          tok="((${arith}))"; have_tok=1
          i=$((i + ${#arith} + 4))
          continue
        fi
      fi
      case "$c" in "'"|'"'|"\\") tok_q=1 ;; esac
    fi
    case "$c" in
      "'") state=1; have_tok=1; i=$((i + 1)); continue ;;
      '"') state=2; have_tok=1; i=$((i + 1)); continue ;;
      "\\")
        if [ $((i + 1)) -lt "$n" ]; then
          c2="${s:i+1:1}"
          if [ -n "$keep" ] && [ "$c2" = '`' ] && [ "$kd" -gt 0 ]; then
            # `…\`…\`…`: a backquote nested in a backquote substitution.
            _cmdtok_anomaly "nested backticks"
            if [ "${k_kind[$((kd - 1))]}" = tick2 ]; then _cmdtok_close_subst; continue; fi
            if [ "${k_kind[$((kd - 1))]}" = tick ]; then _cmdtok_open_subst tick2; continue; fi
          fi
          if [ "$c2" != $'\n' ]; then tok="${tok}${c2}"; have_tok=1; fi
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        continue
        ;;
    esac

    if [ -n "$keep" ]; then
      # $(( arithmetic )): text, never a command (a substitution in it runs).
      if [ "$c" = '$' ] && [ "${s:i+1:2}" = '((' ]; then
        rest="${s:i}"
        arith="${rest%%"))"*}"
        if [ "$arith" != "$rest" ]; then
          _cmdtok_arith_subst "${arith#???}"
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

    # Keep mode: <(…) and >(…), process substitution, run their commands.
    if [ -n "$keep" ] && { [ "$c" = '<' ] || [ "$c" = '>' ]; } && [ "${s:i+1:1}" = '(' ]; then
      _cmdtok_open_subst paren
      continue
    fi

    # Heredoc / herestring operators. `<<WORD` introduces a body that is pure
    # data — the single most misleading place for a command-shaped string to
    # sit — so the delimiter is recorded and the body skipped wholesale.
    if [ "$c" = '<' ] && [ "${s:i+1:1}" = '<' ]; then
      _cmdtok_emit_tok
      if [ "${s:i+2:1}" = '<' ]; then
        i=$((i + 3))          # <<< herestring: the word after it is data
        [ -n "$keep" ] && hs_next=1
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
      if [ -n "$keep" ]; then
        case "${s:i:2}" in '<('|'>(') continue ;; esac   # `< <(…)`: the substitution is read next
      fi
      while [ "$i" -lt "$n" ]; do           # the operand word
        c2="${s:i:1}"
        case "$c2" in
          ' '|$'\t'|$'\n'|';'|'&'|'|'|'('|')') break ;;
        esac
        i=$((i + 1))
      done
      continue
    fi

    if [ -n "$keep" ] && [ "$c" = '|' ]; then
      _cmdtok_emit_seg
      if [ "${s:i+1:1}" = '|' ]; then i=$((i + 2)); else pipe_next=1; i=$((i + 1)); fi
      continue
    fi
    case "$c" in
      ' '|$'\t') _cmdtok_emit_tok; i=$((i + 1)); continue ;;
      $'\n')     _cmdtok_emit_seg; i=$((i + 1)); _cmdtok_skip_heredocs; line_interp=0; continue ;;
      ';'|'&'|'|'|'('|')') _cmdtok_emit_seg; i=$((i + 1)); continue ;;
      '`')       _cmdtok_emit_seg; i=$((i + 1)); continue ;;
    esac

    run="${s:i:512}"; run="${run%%["$_CMDTOK_STOP0"]*}"
    if [ -n "$run" ]; then tok="${tok}${run}"; have_tok=1; i=$((i + ${#run})); continue; fi
    tok="${tok}${c}"
    have_tok=1
    i=$((i + 1))
  done

  if [ -n "$keep" ]; then
    [ "$state" -ne 0 ] && _cmdtok_anomaly "an unterminated quote"
    [ "$kd" -gt 0 ] && _cmdtok_anomaly "an unterminated command substitution"
  fi
  # Keep mode: a substitution left open at the end of the string closes there.
  while [ "$kd" -gt 0 ]; do
    _cmdtok_close_subst end
  done

  _cmdtok_emit_seg
  if [ -n "$keep" ]; then
    [ "${#pending_hd[@]}" -gt 0 ] || [ "$expect_hd" -eq 1 ] && _cmdtok_anomaly "a here-document is not terminated"
    out="${out}${anomalies}"
  fi
  _hook_put "$out"
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

  _hook_put "$out"
}

# cmdtok_argv_segments <command> [depth] [prefix-assignments]
#
# The permission guard's view; see the header. A line that starts with
# CMDTOK_NESTED runs in a subshell (a substitution or an `sh -c` string): its
# `cd` does not move the commands after it. CMDTOK_ANOMALY lines pass through.
cmdtok_argv_segments() {
  local depth="${2:-0}" pre="${3:-}"
  local seg pfx out="" k p m t wrapped wname split_at line inner nested assigns nline piped ci tt pos stdin_script j q esc
  local -a toks=()
  # esc is the four characters quote, backslash, quote, quote: how a single
  # quote is re-spelled inside a single-quoted word.
  q="'"
  esc="${q}\\${q}${q}"

  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    case "$seg" in
      "$CMDTOK_ANOMALY"*) out="${out}${seg}"$'\n'; continue ;;
    esac
    pfx=""
    case "$seg" in
      "$CMDTOK_NESTED"*) pfx="$CMDTOK_NESTED"; seg="${seg#"$CMDTOK_NESTED"}" ;;
    esac
    [ "$depth" -gt 0 ] && pfx="$CMDTOK_NESTED"
    [ -n "$seg" ] || continue
    IFS="$CMDTOK_SEP" read -ra toks <<< "$seg"
    m=${#toks[@]}
    k=0
    piped=0
    while [ "$k" -lt "$m" ]; do
      case "${toks[$k]}" in
        "$CMDTOK_PIPED") piped=1; k=$((k + 1)) ;;
        '!'|'{'|'}'|if|then|elif|else|fi|do|done|while|until) k=$((k + 1)) ;;
        function) k=$((k + 2)) ;;   # `function NAME { …`: the body follows
        coproc) if [ "${toks[$((k + 2))]:-}" = '{' ]; then k=$((k + 2)); else k=$((k + 1)); fi ;;
        *) break ;;
      esac
    done
    [ "$k" -lt "$m" ] || continue

    # The program behind assignments and wrappers.
    assigns="$pre"
    _cmdtok_find_prog
    inner="" ci=-1

    if [ "$split_at" -ge 0 ]; then
      # env -S '<string>' (--split-string): the string is split into the command.
      t="${toks[$split_at]}"
      case "$t" in
        -S|--split-string) inner="${toks[$((split_at + 1))]:-}"; j=$((split_at + 2)) ;;
        --split-string=*) inner="${t#--split-string=}"; j=$((split_at + 1)) ;;
        *) inner="${t#-S}"; j=$((split_at + 1)) ;;
      esac
      while [ "$j" -lt "$m" ]; do inner="${inner} ${q}${toks[$j]//$q/$esc}${q}"; j=$((j + 1)); done
      ci=0
    elif [ "$p" -lt "$m" ]; then
      t="${toks[$p]}"
      if _cmdtok_is_shell "$t"; then
        # The string of -c (after -o/-O/--rcfile values; -lc, -ec), else a
        # herestring; with neither, the script is the first positional.
        pos="" stdin_script=0 j=$((p + 1))
        while [ "$j" -lt "$m" ]; do
          tt="${toks[$j]}"
          case "$tt" in
            "$CMDTOK_HERESTR"*) [ -n "$inner" ] || inner="${tt#"$CMDTOK_HERESTR"}"; ci=0 ;;
            --rcfile|--init-file|-o|+o|-O|+O) j=$((j + 1)) ;;
            --*) : ;;
            -c|-*c*) inner="${toks[$((j + 1))]:-}"; ci=$((j + 1)); break ;;
            -*s*) stdin_script=1 ;;
            -|+*|-*) [ "$tt" = - ] && stdin_script=1 ;;
            *) [ -n "$pos" ] || pos="$tt" ;;
          esac
          j=$((j + 1))
        done
        if [ "$ci" -lt 0 ]; then
          case "$pos" in
            '<('*|'>('*) out="${out}${CMDTOK_ANOMALY}a shell runs a script from a process substitution"$'\n' ;;
            /dev/stdin|/dev/fd/*) stdin_script=1 ;;
            '') stdin_script=1 ;;
          esac
          if [ "$piped" -eq 1 ] && [ "$stdin_script" -eq 1 ]; then
            out="${out}${CMDTOK_ANOMALY}a shell reads its script from a pipe"$'\n'
          fi
        fi
      else
        # External programs: any case (a case-insensitive file system runs `FIND`).
        _cmdtok_prog_kind "${t##*/}"
        case "$_ct_kind" in
          source)
            case "${toks[$((p + 1))]:-}" in
              '<('*|'>('*|/dev/stdin|/dev/fd/*|-) out="${out}${CMDTOK_ANOMALY}a shell runs a script from a process substitution or stdin"$'\n' ;;
            esac ;;
          su)
            j=$((p + 1))
            while [ "$j" -lt "$m" ]; do
              tt="${toks[$j]}"
              case "$tt" in
                -c|--command) inner="${toks[$((j + 1))]:-}"; ci=$((j + 1)); break ;;
                --command=*) inner="${tt#--command=}"; ci="$j"; break ;;
                -s|--shell|-g|--group|-G|--supp-group) j=$((j + 1)) ;;
              esac
              j=$((j + 1))
            done ;;
          watch)
            # watch joins its words and hands them to `sh -c`.
            j=$((p + 1))
            while [ "$j" -lt "$m" ]; do
              case "${toks[$j]}" in
                -n|--interval|-q|--equexit) j=$((j + 2)) ;;
                -*) j=$((j + 1)) ;;
                *) break ;;
              esac
            done
            while [ "$j" -lt "$m" ]; do inner="${inner}${inner:+ }${toks[$j]}"; j=$((j + 1)); done
            [ -n "$inner" ] && ci=0 ;;
          find)
            # Every -exec/-execdir/-ok/-okdir (find) or -x/-X (fd) runs a command.
            j=$((p + 1))
            while [ "$j" -lt "$m" ]; do
              case "${toks[$j]}" in
                -exec|-execdir|-ok|-okdir|-x|--exec|-X|--exec-batch)
                  nested="" j=$((j + 1))
                  while [ "$j" -lt "$m" ] && [ "${toks[$j]}" != ';' ] && [ "${toks[$j]}" != '+' ]; do
                    nested="${nested} ${q}${toks[$j]//$q/$esc}${q}"; j=$((j + 1))
                  done
                  if [ -n "$nested" ]; then
                    if [ "$depth" -ge 4 ]; then
                      out="${out}${CMDTOK_ANOMALY}nesting deeper than 4 levels"$'\n'
                    else
                      nested="$(cmdtok_argv_segments "$nested" $((depth + 1)) "$assigns")"
                      [ -n "$nested" ] && out="${out}${nested}"$'\n'
                    fi
                  fi ;;
              esac
              j=$((j + 1))
            done ;;
        esac
      fi
    fi

    if [ "$ci" -ge 0 ] && [ -n "$inner" ]; then
      if [ "$depth" -ge 4 ]; then
        out="${out}${CMDTOK_ANOMALY}nesting deeper than 4 levels"$'\n'
      else
        # Command substitution eats the trailing newline; restore it so the
        # nested segments stay one-per-line.
        nested="$(cmdtok_argv_segments "$inner" $((depth + 1)) "$assigns")"
        [ -n "$nested" ] && out="${out}${nested}"$'\n'
        continue
      fi
    fi

    line="${pre}"
    while [ "$k" -lt "$m" ]; do
      line="${line}${toks[$k]}"
      k=$((k + 1))
      [ "$k" -lt "$m" ] && line="${line}${CMDTOK_SEP}"
    done
    line="${line//$CMDTOK_HERESTR/}"
    nline="${pfx}${line}"
    [ -n "$line" ] && out="${out}${nline}"$'\n'
  done <<< "$(cmdtok_segments "$1" keep)"

  _hook_put "$out"
}
