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

# --- permission level (ADR 004 D3, D7, D10) ----------------------------------
# The one setup step that is not a module: it writes the plugin's USER policy
# file, not a host config file, and the file is the user's from the moment it
# exists. So it is never "rendered" onto the machine, never backed up and
# restored by `remove`, and never rewritten without the user seeing the diff.
#
# WHERE IT WRITES
#   Exactly where the resolver reads: scripts/lib/permission-common.sh resolves
#   the passwd home (never HOME or XDG_*, SR S-04), so this step asks that library
#   for the path instead of computing one. When TAMIRS_PERMISSION_TEST_ROOT is set
#   but the library refused it, the step refuses to write at all: a test that
#   meant a temp root must never land in the real home.
#
# WHAT IT WRITES (D3, D10.2)
#   permissions.json (0600, dir 0700) with `version` and `level`, every other key
#   of an existing file kept, and its lock {sha256, by: plugin-config, at} --
#   written by scripts/plugin-config.sh (`set <level>`), the D6 writer, never by
#   this file: one writer, one lock format. This step is the writer's
#   out-of-session path (D5: `make setup`, asks once on a TTY); inside an agent
#   session the writer holds a raise pending until it is confirmed.
#
# WHEN IT WRITES
#   * --permission-level <level> or the TTY prompt picks a level.
#   * Non-interactive (--yes, no TTY, CI): never prompts. No flag => nothing is
#     written (an absent file means supervised). A flag writes a NEW file only:
#     an existing file changes only after its diff is confirmed on a terminal, and
#     a raise is refused outright without one.
#   * An existing file that is unreadable or fails the schema is never touched.

SETUP_PERM_DIR=""; SETUP_PERM_FILE=""; SETUP_PERM_LOCK=""
SETUP_PERM_HOME_SOURCE=""; SETUP_PERM_WRITABLE=""
SETUP_PERM_STATE=""; SETUP_PERM_CUR_LEVEL=""; SETUP_PERM_LOCK_STATE=""; SETUP_PERM_REASON=""

setup_perm_valid_level() {
  case "$1" in supervised|standard|unattended) return 0 ;; *) return 1 ;; esac
}

setup_perm_rank() {
  case "$1" in standard) printf 1 ;; unattended) printf 2 ;; *) printf 0 ;; esac
}

# setup_perm_lib — source the resolver library once. Returns 1 when it is absent
# or unusable; the step then reports and writes nothing.
setup_perm_lib() {
  local lib="${SETUP_REPO_ROOT:-}/scripts/lib/permission-common.sh"
  if command -v perm_dirs >/dev/null 2>&1; then return 0; fi
  [ -f "$lib" ] || return 1
  # shellcheck source=scripts/lib/permission-common.sh
  . "$lib" || return 1
  command -v perm_dirs >/dev/null 2>&1
}

# setup_perm_paths — sets SETUP_PERM_DIR/FILE/LOCK/HOME_SOURCE and
# SETUP_PERM_WRITABLE ("yes" or "no:<reason>"). Returns 1 when no path resolves.
setup_perm_paths() {
  local j=""
  SETUP_PERM_DIR=""; SETUP_PERM_FILE=""; SETUP_PERM_LOCK=""; SETUP_PERM_HOME_SOURCE=""
  if ! setup_perm_lib; then
    SETUP_PERM_WRITABLE="no:scripts/lib/permission-common.sh is missing from this checkout"
    return 1
  fi
  j="$(perm_dirs 2>/dev/null)" || j=""
  if [ -n "$j" ]; then
    SETUP_PERM_DIR="$(printf '%s' "$j" | jq -r '.config_dir // empty' 2>/dev/null)" || SETUP_PERM_DIR=""
    SETUP_PERM_HOME_SOURCE="$(printf '%s' "$j" | jq -r '.home_source // empty' 2>/dev/null)" || SETUP_PERM_HOME_SOURCE=""
  fi
  case "$SETUP_PERM_DIR" in
    /*) ;;
    *) SETUP_PERM_WRITABLE="no:the permission library could not resolve the passwd home (python3 is required)"
       SETUP_PERM_DIR=""
       return 1 ;;
  esac
  SETUP_PERM_FILE="$SETUP_PERM_DIR/permissions.json"
  SETUP_PERM_LOCK="$SETUP_PERM_DIR/permissions.lock"
  if [ -n "${TAMIRS_PERMISSION_TEST_ROOT:-}" ] && [ "$SETUP_PERM_HOME_SOURCE" != test-root ]; then
    SETUP_PERM_WRITABLE="no:TAMIRS_PERMISSION_TEST_ROOT is set but the resolver refused it, so the path is the real home; refusing to write there"
  else
    SETUP_PERM_WRITABLE=yes
  fi
  return 0
}

# setup_perm_state — the user file as the resolver sees it: SETUP_PERM_STATE
# (absent | invalid | verified | tighten-only), SETUP_PERM_CUR_LEVEL (empty when
# the file has no `level`), SETUP_PERM_LOCK_STATE and SETUP_PERM_REASON.
setup_perm_state() {
  local j=""
  SETUP_PERM_STATE=""; SETUP_PERM_CUR_LEVEL=""; SETUP_PERM_LOCK_STATE=""; SETUP_PERM_REASON=""
  j="$(perm_load_user_file 2>/dev/null)" || j=""
  if [ -z "$j" ] || ! printf '%s' "$j" | jq -e 'type == "object"' >/dev/null 2>&1; then
    SETUP_PERM_STATE=invalid
    SETUP_PERM_REASON="the permission library could not read it"
    return 0
  fi
  SETUP_PERM_STATE="$(printf '%s' "$j" | jq -r '.state // "invalid"')"
  SETUP_PERM_CUR_LEVEL="$(printf '%s' "$j" | jq -r '.level // empty')"
  SETUP_PERM_LOCK_STATE="$(printf '%s' "$j" | jq -r '.lock // empty')"
  SETUP_PERM_REASON="$(printf '%s' "$j" | jq -r '.reason // empty')"
}

# setup_perm_render <level> — the file as it should be, on stdout. An existing
# valid file keeps every other key; the writer's formatting (jq -S, 2 spaces).
setup_perm_render() {
  local level="$1"
  if [ -f "$SETUP_PERM_FILE" ] && [ "$SETUP_PERM_STATE" != absent ] && [ "$SETUP_PERM_STATE" != invalid ]; then
    jq -S --indent 2 --arg l "$level" '.level = $l' "$SETUP_PERM_FILE"
  else
    jq -n -S --indent 2 --arg l "$level" '{version: 1, level: $l}'
  fi
}

# setup_perm_write <level> — through the D6 writer, scripts/plugin-config.sh, the
# one writer of the user file and its lock (ADR 004 D6): the same schema check,
# sorted-key serialisation, atomic replace, .bak and lock (hashed with the
# library's sha256, `by: plugin-config`) as /plugin-config. Every other key of the
# file is kept. Run from the user's own terminal (no agent host in the process
# ancestry) the writer applies a raise at once; run inside an agent session it
# records a raise pending and prints the `confirm <nonce>` that applies it under a
# host-attested human proof (D5) -- setup then reports the level as not written.
setup_perm_write() {
  local level="$1" out rc writer="${SETUP_REPO_ROOT:-}/scripts/plugin-config.sh"
  case "$SETUP_PERM_WRITABLE" in
    yes) ;;
    *) setup_err "permission level not written: ${SETUP_PERM_WRITABLE#no:}"; return 1 ;;
  esac
  [ -f "$writer" ] || { setup_err "permission level not written: scripts/plugin-config.sh is missing from this checkout"; return 1; }
  out="$(bash "$writer" set "$level" 2>&1)" && rc=0 || rc=$?
  case "$rc" in
    0) return 0 ;;
    4) printf '%s\n' "$out" | sed 's/^/  /'
       setup_err "permission level not written yet: this runs inside an agent session, so the raise waits for the confirm above (ADR 004 D5)"
       return 1 ;;
    *) printf '%s\n' "$out" | sed 's/^/  /'
       setup_err "permission level not written (scripts/plugin-config.sh exited $rc)"
       return 1 ;;
  esac
}

# setup_perm_menu — the choice, on stderr (human output; never stdout, never stdin).
setup_perm_menu() {
  local def="$1"
  {
    printf '\n%sPermission level%s — how much the plugin'"'"'s skills do without asking you (ADR 004)\n' "$SETUP_C_BOLD" "$SETUP_C_OFF"
    printf '  1) supervised   the default. Asks before anything that leaves this machine:\n'
    printf '                  push, open a PR, comment, merge, delete a branch.\n'
    printf '  2) standard     pushes its own branches, opens PRs and comments without asking;\n'
    printf '                  still asks before merging, closing or deleting anything.\n'
    printf '  3) unattended   also arms auto-merge, deletes merged branches and closes finished\n'
    printf '                  PRs and issues, each only when its safety precondition holds.\n'
    printf '  The riskiest actions (releases, repository create/delete, force-push to the default\n'
    printf '  branch, editing policy) ask at every level. A level governs the plugin, never the\n'
    printf '  host: its own approval prompts stay. On Codex, Cursor and OpenCode an "ask" arrives\n'
    printf '  as a refusal that names the command for you to run.\n'
    printf '  Stored in %s (0600, locked); k keeps things as they are.\n' "$(setup_tilde "$SETUP_PERM_FILE")"
    printf '  Enter = %s\n' "$def"
  } >&2
}

# setup_perm_choose <default> — prints supervised | standard | unattended | keep.
# Three unrecognised answers mean keep: a typo never picks a level.
setup_perm_choose() {
  local def="$1" ans n=0
  setup_perm_menu "$def"
  while [ "$n" -lt 3 ]; do
    n=$((n + 1))
    ans="$(setup_lower "$(setup_ask "Level [1/2/3, k = keep] (${def}): " "$def")")"
    case "$ans" in
      1|supervised) printf 'supervised'; return 0 ;;
      2|standard) printf 'standard'; return 0 ;;
      3|unattended) printf 'unattended'; return 0 ;;
      k|keep|skip|n|no|none) printf 'keep'; return 0 ;;
      *) setup_note "'$ans' is not one of 1, 2, 3 or k" ;;
    esac
  done
  printf 'keep'
}

# setup_permission_level_step <plan|apply|remove>
#   Globals read: SETUP_PERMISSION_LEVEL (the --permission-level value),
#   SETUP_PERM_PROMPT_ROUTE (yes when a target in scope has no install-time level
#   option: Codex, Cursor, OpenCode, D7) and SETUP_PERM_NOTES (one line per host
#   whose own installer sets the level: Claude, Gemini).
#   Returns 1 only when an explicit --permission-level could not be applied.
setup_permission_level_step() {
  local mode="$1" flag="${SETUP_PERMISSION_LEVEL:-}" want="" def cur new curf rank_want rank_cur ans line
  if [ -z "$flag" ] && [ "${SETUP_PERM_PROMPT_ROUTE:-no}" != yes ] && [ -z "${SETUP_PERM_NOTES:-}" ]; then
    return 0
  fi
  # remove: the file is the user's policy, never an installed artefact. Say so
  # when one exists; print nothing else.
  if [ "$mode" = remove ]; then
    if setup_perm_paths && [ -f "$SETUP_PERM_FILE" ]; then
      printf '\n%sPermission level%s\n' "$SETUP_C_BOLD" "$SETUP_C_OFF"
      printf '  %s left in place: it is your policy, not an installed file. Delete it to return to supervised.\n' "$(setup_tilde "$SETUP_PERM_FILE")"
    fi
    return 0
  fi
  printf '\n%sPermission level%s\n' "$SETUP_C_BOLD" "$SETUP_C_OFF"
  if [ -n "${SETUP_PERM_NOTES:-}" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && printf '  %s\n' "$line"
    done <<EOT
$SETUP_PERM_NOTES
EOT
  fi
  if [ -z "$flag" ] && [ "${SETUP_PERM_PROMPT_ROUTE:-no}" != yes ]; then
    return 0
  fi

  if ! setup_perm_paths; then
    setup_warn "permission level: ${SETUP_PERM_WRITABLE#no:}"
    [ -n "$flag" ] && return 1
    return 0
  fi
  setup_perm_state
  case "$SETUP_PERM_STATE" in
    absent) printf '  %s: none yet, so every host runs supervised\n' "$(setup_tilde "$SETUP_PERM_FILE")" ;;
    invalid) printf '  %s: INVALID (%s)\n' "$(setup_tilde "$SETUP_PERM_FILE")" "$SETUP_PERM_REASON" ;;
    *) printf '  %s: level %s, lock %s%s\n' "$(setup_tilde "$SETUP_PERM_FILE")" \
         "${SETUP_PERM_CUR_LEVEL:-unset (supervised)}" "${SETUP_PERM_LOCK_STATE:-unknown}" \
         "$( [ "$SETUP_PERM_STATE" = verified ] || printf ' — read tighten-only: %s' "$SETUP_PERM_REASON")" ;;
  esac

  case "$mode" in
    plan)
      if [ -n "$flag" ]; then printf '  apply would set the level to %s\n' "$flag"
      else printf '  apply asks for a level on a terminal; --permission-level <level> sets it\n'; fi
      return 0 ;;
  esac

  if [ "$SETUP_PERM_STATE" = invalid ]; then
    setup_warn "permission level: $(setup_tilde "$SETUP_PERM_FILE") is not touched while it is invalid; fix or delete it (D3: until then it reads as supervised)"
    [ -n "$flag" ] && return 1
    return 0
  fi

  def="${SETUP_PERM_CUR_LEVEL:-supervised}"
  if [ -n "$flag" ]; then
    want="$flag"
  elif setup_can_prompt; then
    want="$(setup_perm_choose "$def")"
  elif [ "$SETUP_PERM_STATE" = absent ]; then
    printf '  nothing written (no terminal to ask on). Set one with --permission-level <level>.\n'
    return 0
  else
    printf '  kept as is (no terminal to ask on)\n'
    return 0
  fi
  if [ "$want" = keep ]; then
    printf '  kept as is\n'
    return 0
  fi

  new="$(mktemp)"
  if ! setup_perm_render "$want" > "$new" 2>/dev/null; then
    rm -f "$new"; setup_err "permission level: cannot render $(setup_tilde "$SETUP_PERM_FILE")"; return 1
  fi

  if [ "$SETUP_PERM_STATE" = absent ]; then
    if setup_perm_write "$want"; then
      rm -f "$new"
      setup_perm_report_written "$want"
      return 0
    fi
    rm -f "$new"; return 1
  fi

  curf="$(mktemp)"
  jq -S --indent 2 '.' "$SETUP_PERM_FILE" > "$curf" 2>/dev/null || cp "$SETUP_PERM_FILE" "$curf"
  if cmp -s "$curf" "$new" && [ "$SETUP_PERM_LOCK_STATE" = match ] && [ "$SETUP_PERM_STATE" = verified ]; then
    rm -f "$new" "$curf"
    printf '  already %s — nothing to do\n' "$want"
    return 0
  fi
  printf '%s\n' "$(setup_diff "$curf" "$new")"
  rm -f "$curf"

  if ! setup_can_prompt; then
    rm -f "$new"
    cur="${SETUP_PERM_CUR_LEVEL:-supervised}"
    rank_want="$(setup_perm_rank "$want")"; rank_cur="$(setup_perm_rank "$cur")"
    if [ "$rank_want" -gt "$rank_cur" ]; then
      setup_err "permission level not raised ($cur -> $want): a raise needs your confirmation on a terminal (ADR 004 D10). Run: bash scripts/setup.sh apply --permission-level $want"
    else
      setup_err "permission level not written: an existing $(setup_tilde "$SETUP_PERM_FILE") changes only after you confirm its diff on a terminal. Run: bash scripts/setup.sh apply --permission-level $want"
    fi
    return 1
  fi

  if [ "$SETUP_PERM_LOCK_STATE" != match ] || [ "$SETUP_PERM_STATE" != verified ]; then
    setup_warn "this file is not verified (${SETUP_PERM_REASON:-lock ${SETUP_PERM_LOCK_STATE:-absent}}). Confirming re-locks ALL of its content, shown in full:"
    sed 's/^/    /' "$SETUP_PERM_FILE" >&2
  fi
  ans="$(setup_lower "$(setup_ask 'Write this permission level? [y/N] ' n)")"
  case "$ans" in
    y|yes) ;;
    *) rm -f "$new"; printf '  kept as is\n'; return 0 ;;
  esac
  if setup_perm_write "$want"; then
    rm -f "$new"
    setup_perm_report_written "$want"
    return 0
  fi
  rm -f "$new"; return 1
}

# setup_perm_report_written <level> — say what landed, and whether the resolver
# reads it as verified (a dotfiles repo at the home, a group-writable parent and
# the like make it tighten-only, D3).
setup_perm_report_written() {
  setup_perm_state
  printf '  %swritten%s: level %s -> %s (0600, locked)\n' "$SETUP_C_GREEN" "$SETUP_C_OFF" "$1" "$(setup_tilde "$SETUP_PERM_FILE")"
  if [ "$SETUP_PERM_STATE" != verified ]; then
    setup_warn "the resolver reads it as $SETUP_PERM_STATE (${SETUP_PERM_REASON:-no reason given})"
  fi
}
