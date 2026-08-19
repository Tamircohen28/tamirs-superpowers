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

# setup_ask <prompt> <default> — echoes the answer, lowercased-ish by the caller.
# Returns <default> immediately when we cannot prompt, so no caller ever blocks.
setup_ask() {
  local prompt="$1" default="$2" ans=''
  if ! setup_can_prompt; then printf '%s' "$default"; return 0; fi
  printf '%s' "$prompt" > /dev/tty
  IFS= read -r ans < /dev/tty || ans=''
  printf '\n' > /dev/tty
  [ -n "$ans" ] || ans="$default"
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
# Deep merge with array UNION. This is the "merge, never clobber" rule expressed
# as one jq function: third-party wiring (cmux, gortex) living in an object we
# also write survives, and a user's extra permission entries are additive rather
# than replaced. Scalars are the one place the repo wins outright — that is what
# "the repo is the source of truth" means for a setting like `model`.
SETUP_JQ_DEEPMERGE='
def deepmerge($b):
  . as $a
  | reduce ($b | keys_unsorted[]) as $k ($a;
      if ($a[$k] | type) == "object" and ($b[$k] | type) == "object" then
        .[$k] = ($a[$k] | deepmerge($b[$k]))
      elif ($a[$k] | type) == "array" and ($b[$k] | type) == "array" then
        .[$k] = ($a[$k] + ($b[$k] - $a[$k]))
      else
        .[$k] = $b[$k]
      end);
'

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
