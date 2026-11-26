#!/usr/bin/env bash
# setup-common.sh — shared helpers for scripts/setup.sh and the per-platform
# writer libraries in scripts/lib/setup-<target>.sh.
#
# Sourced, never executed.
#
# PORTABILITY CONTRACT (rules/dev/user-facing-script-standards.md §3)
#   bash 3.2: no associative arrays, no `mapfile`, no `${var^^}`, no `declare -A`.
#   No `timeout(1)` (absent on stock macOS). No GNU-only `sed -i`.
#   Timestamps via `date -u +%Y-%m-%dT%H:%M:%SZ`.
#
# STDIN CONTRACT (§4)
#   Nothing here ever reads stdin. Prompts read /dev/tty, so the caller's stdin —
#   a hook's JSON, an inherited descriptor, an idle terminal — is never touched
#   and can never block us. When /dev/tty is unreadable we do not prompt at all.

# shellcheck shell=bash

# --- naming conventions the whole engine keys off ---------------------------
# The backup name is FIXED and documented so `setup.sh remove` can find it years
# later (oh-my-zsh's `~/.zshrc.pre-oh-my-zsh` convention). The first backup ever
# taken for a file is never overwritten; later runs rotate to a UTC-stamped name.
SETUP_BACKUP_SUFFIX=".pre-tamirs-superpowers"
SETUP_MARKER_OPEN="# >>> tamirs-superpowers >>>"
SETUP_MARKER_CLOSE="# <<< tamirs-superpowers <<<"

# --- output -----------------------------------------------------------------
# Colour only on a real terminal, and honour NO_COLOR. Human progress goes to
# stderr so that `--json` owns stdout alone (§6).
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  SETUP_C_DIM=$'\033[2m'; SETUP_C_BOLD=$'\033[1m'
  SETUP_C_GREEN=$'\033[32m'; SETUP_C_YELLOW=$'\033[33m'; SETUP_C_RED=$'\033[31m'
  SETUP_C_OFF=$'\033[0m'
else
  SETUP_C_DIM=''; SETUP_C_BOLD=''
  SETUP_C_GREEN=''; SETUP_C_YELLOW=''; SETUP_C_RED=''
  SETUP_C_OFF=''
fi

setup_say()  { printf '%s\n' "$*"; }
setup_note() { printf 'note: %s\n' "$*" >&2; }
setup_warn() { printf '%swarning:%s %s\n' "$SETUP_C_YELLOW" "$SETUP_C_OFF" "$*" >&2; }
setup_err()  { printf '%serror:%s %s\n' "$SETUP_C_RED" "$SETUP_C_OFF" "$*" >&2; }
setup_die()  { setup_err "$*"; exit 1; }
setup_debug() { [ -n "${SETUP_VERBOSE:-}" ] && printf '%s  %s%s\n' "$SETUP_C_DIM" "$*" "$SETUP_C_OFF" >&2; return 0; }

# --- dependencies (§5) ------------------------------------------------------
setup_have()    { command -v "$1" >/dev/null 2>&1; }
setup_require() {
  setup_have "$1" || setup_die "$1 is required — $2"
}

# --- time -------------------------------------------------------------------
setup_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# --- interactivity ----------------------------------------------------------
# `[ -t 1 ]` (stdout is a terminal) is the honest interactivity signal here, not
# `[ -t 0 ]` — we never read stdin, so its state says nothing about whether a
# human is watching. SETUP_YES suppresses prompting entirely.
setup_can_prompt() {
  [ -z "${SETUP_YES:-}" ] || return 1
  [ -r /dev/tty ] || return 1
  [ -t 1 ] || return 1
  return 0
}

# setup_ask_into <var> <prompt> <default> — asks on /dev/tty and lands the
# answer in <var>, in THIS shell. Returns <default> without asking when we
# cannot prompt, so no caller ever blocks.
#
# THIS IS THE ONE TO CALL. The older `ans="$(setup_ask ...)"` form is a bug at a
# real terminal: inside a command substitution fd 1 is the capture pipe, so
# setup_can_prompt's `[ -t 1 ]` is false, the prompt is never shown, and the
# default comes back as if the person had declined. Eight call sites did that
# and `github-labels.sh apply` at a terminal reported "skipped — not confirmed"
# without ever asking (PR #374). `printf -v` is bash 3.2.
#
# The locals carry a prefix on purpose: bash scopes dynamically, so a local
# named `ans` here would be the one `printf -v ans` assigned when the caller
# also said `ans` — the caller's variable would stay empty, and "empty" reads
# as "declined". The first version of this helper did exactly that.
setup_ask_into() {
  local __sa_var="$1" __sa_prompt="$2" __sa_default="$3" __sa_ans=''
  if setup_can_prompt; then
    printf '%s' "$__sa_prompt" > /dev/tty
    IFS= read -r __sa_ans < /dev/tty || __sa_ans=''
    printf '\n' > /dev/tty
  fi
  [ -n "$__sa_ans" ] || __sa_ans="$__sa_default"
  printf -v "$__sa_var" '%s' "$__sa_ans"
}

# setup_ask <prompt> <default> — echoes the answer. Kept for compatibility;
# it only prompts when its stdout is the terminal, which is never the case in
# `$( )`. New code uses setup_ask_into.
setup_ask() {
  local ans
  setup_ask_into ans "$1" "$2"
  printf '%s' "$ans"
}

# setup_lower <string> — bash 3.2 has no ${var,,}.
setup_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# setup_tilde <path> — abbreviate $HOME to `~` for display. Plan tables are read
# at a glance; a 90-column absolute path buries the column that matters.
setup_tilde() {
  case "$1" in
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# --- files ------------------------------------------------------------------
# setup_write <path> — content on stdin, written atomically (temp + mv) so a
# killed run can never leave a half-written settings.json behind.
setup_write() {
  local path="$1" dir tmp
  dir="$(dirname "$path")"
  mkdir -p "$dir"
  tmp="${path}.tamirs-tmp.$$"
  cat > "$tmp"
  mv "$tmp" "$path"
}

# setup_backup <file> — prints the backup path it created, or nothing if the
# file does not exist. First backup keeps the fixed name forever; subsequent
# runs rotate so `remove` always finds the pristine original.
setup_backup() {
  local f="$1" fixed stamped
  [ -f "$f" ] || return 0
  fixed="${f}${SETUP_BACKUP_SUFFIX}"
  if [ ! -f "$fixed" ]; then
    cp "$f" "$fixed"
    printf '%s' "$fixed"
    return 0
  fi
  stamped="${fixed}-$(setup_utc)"
  cp "$f" "$stamped"
  printf '%s' "$stamped"
}

# setup_backup_path <file> — the fixed name, whether or not it exists.
setup_backup_path() { printf '%s' "${1}${SETUP_BACKUP_SUFFIX}"; }

# setup_diff <old-file> <new-file> — unified diff, never fails the script.
# `diff -u` is POSIX and present on macOS and Linux alike.
setup_diff() {
  local old="$1" new="$2"
  [ -f "$old" ] || old=/dev/null
  diff -u "$old" "$new" 2>/dev/null || true
}

# --- JSON -------------------------------------------------------------------
# Deep merge. Objects recurse; everything else — scalars AND arrays — is
# asserted from the repo.
#
# WHY ARRAYS ARE ASSERTED, NOT UNIONED
#   Union looks safer and is not. If `permissions.allow` unions, the repo can
#   never RETRACT a permission: delete an entry judged too broad from the
#   fragment and it stays live forever on every machine that ever applied it,
#   invisibly. It also stops the fragment describing its own result, which is the
#   property that made settings.d reviewable in the first place.
#
#   The "merge, never clobber" rule is still honoured exactly where clobbering
#   would destroy someone else's work, because third-party wiring is OBJECT
#   shaped, not array shaped: hooks, enabledPlugins, extraKnownMarketplaces and
#   mcpServers all recurse and survive. Verified on this machine — the keys other
#   tools had written into ~/.claude/settings.json were `hooks` and
#   `enabledPlugins`; nothing external writes into a permissions array.
#
#   A user's own additions have a documented home upstream of us:
#   ~/.claude/settings.local.json, which this installer never touches and which
#   Claude Code already merges on top. That is where an incremental "always
#   allow" grant lands.
SETUP_JQ_DEEPMERGE='
def deepmerge($b):
  . as $a
  | reduce ($b | keys_unsorted[]) as $k ($a;
      if ($a[$k] | type) == "object" and ($b[$k] | type) == "object" then
        .[$k] = ($a[$k] | deepmerge($b[$k]))
      else
        .[$k] = $b[$k]
      end);
'

# setup_json_strip_meta — JSON on stdin, same JSON minus top-level keys that
# begin with `_`, on stdout.
#
# THE CONVENTION, ONCE, FOR EVERY TARGET
#   JSON has no comments, so repo-side fragments carry their rationale in keys
#   like `_comment` and `_tally` — "these 15 false entries are deliberate" is
#   exactly the kind of thing a reviewer needs and a user's settings file must
#   never contain. An underscore prefix means REPO-SIDE METADATA, NEVER RENDERED.
#   Every renderer must pipe each fragment through this before merging, so the
#   next person who adds a `_note` to a Cursor or Codex fragment inherits the
#   guarantee instead of rediscovering the bug.
setup_json_strip_meta() {
  jq 'with_entries(select(.key | startswith("_") | not))'
}

# setup_json_read <file> — the file as JSON, or `{}` when absent/unparseable.
setup_json_read() {
  local f="$1"
  if [ -s "$f" ] && jq empty "$f" >/dev/null 2>&1; then
    cat "$f"
  else
    printf '{}\n'
  fi
}

# setup_json_normalize — JSON on stdin, canonical 2-space rendering on stdout.
# Both sides of every comparison go through this, so "is it already up to date"
# is a content question and never a whitespace question. Key ORDER is preserved
# (no `-S`): sorting would reformat the user's whole file on first apply for no
# benefit, and jq's insertion order is stable across runs.
setup_json_normalize() { jq --indent 2 '.'; }

# setup_json_merge <base-json-string> <fragment-json-string> — deep merge.
setup_json_merge() {
  printf '%s' "$1" | jq --argjson b "$2" "${SETUP_JQ_DEEPMERGE} deepmerge(\$b)"
}
