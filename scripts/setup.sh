#!/usr/bin/env bash
# setup.sh — render this repo's canonical config onto this machine.
#
# USAGE
#   bash scripts/setup.sh [plan|apply|remove] [flags]
#   make setup
#
# VERBS
#   plan     detect targets and print exactly what would change. NEVER writes.
#            This is the default when there is no terminal to prompt on.
#   apply    plan, then show a diff and confirm each change before writing.
#            This is the default when a terminal is present.
#   remove   undo what apply wrote, scoped to this installer's own backups and
#            keys. Symmetric with apply and confirmed the same way.
#
# FLAGS
#   --targets a,b   restrict to these targets (a FILTER over detection, and an
#                   explicit request: a named target is planned even if absent)
#   --only <module> restrict to one module; matches `x` and `x-*`
#   --yes, -y       do not prompt; take the default action for every change
#   --dry-run       synonym for the `plan` verb
#   --json          machine-readable plan on stdout, humans on stderr
#   --verbose, -v   detailed logging to stderr
#   --help, -h      this text
#
# ENV TWINS (for CI and dotfiles bootstraps)
#   SETUP_YES=1              same as --yes
#   SETUP_TARGETS=a,b        same as --targets
#   SETUP_ONLY=<module>      same as --only
#   SETUP_DESTRUCTIVE=skip   never touch a user-customised file, even with --yes
#
# EXAMPLES
#   bash scripts/setup.sh plan
#   bash scripts/setup.sh apply --targets claude
#   bash scripts/setup.sh apply --yes --only notifications
#   bash scripts/setup.sh remove --targets claude
#
# EXIT CODES
#   0  success, or "no TTY so here is the plan instead"
#   1  failure (bad flag, unknown target, missing required dependency)
#
# STDIN IS NEVER READ. Prompts go to /dev/tty. A run with no terminal and no
# --yes prints the plan and exits 0 — it never adopts silently and never blocks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/setup-common.sh
. "${SCRIPT_DIR}/lib/setup-common.sh"

SETUP_ALL_TARGETS="claude cursor codex gemini opencode"
SETUP_DELETE_SENTINEL="@@tamirs-superpowers-delete-this-file@@"

VERB=""
OPT_TARGETS="${SETUP_TARGETS:-}"
OPT_ONLY="${SETUP_ONLY:-}"
OPT_JSON=""
SETUP_YES="${SETUP_YES:-}"
SETUP_VERBOSE="${SETUP_VERBOSE:-}"

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; }

# ---------------------------------------------------------------------------
# Argument parsing (rules/dev/user-facing-script-standards.md §1)
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    plan|apply|remove)
      [ -z "$VERB" ] || setup_die "more than one verb given ('$VERB' then '$1')"
      VERB="$1" ;;
    --targets) shift; [ $# -gt 0 ] || setup_die "--targets needs a value"; OPT_TARGETS="$1" ;;
    --targets=*) OPT_TARGETS="${1#*=}" ;;
    --only)    shift; [ $# -gt 0 ] || setup_die "--only needs a value"; OPT_ONLY="$1" ;;
    --only=*)  OPT_ONLY="${1#*=}" ;;
    --yes|-y)  SETUP_YES=1 ;;
    --dry-run) VERB="plan" ;;
    --json)    OPT_JSON=1 ;;
    --verbose|-v) SETUP_VERBOSE=1 ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    -*) setup_err "unknown flag: $1"; printf 'Try: bash scripts/setup.sh --help\n' >&2; exit 1 ;;
    *)  setup_err "unexpected argument: $1"; printf 'Try: bash scripts/setup.sh --help\n' >&2; exit 1 ;;
  esac
  shift
done

# Verb default follows the terminal, per the research: a human at a prompt means
# `apply`, anything else means `plan`. Both are safe; only one writes.
if [ -z "$VERB" ]; then
  if [ -t 1 ] || [ -n "$SETUP_YES" ]; then VERB="apply"; else VERB="plan"; fi
fi

setup_require jq "brew install jq / apt-get install jq — required to merge JSON config"

# Reject unknown targets before doing any work.
REQUESTED=""
if [ -n "$OPT_TARGETS" ]; then
  for t in $(printf '%s' "$OPT_TARGETS" | tr ',' ' '); do
    known=no
    for k in $SETUP_ALL_TARGETS; do [ "$t" = "$k" ] && known=yes; done
    [ "$known" = yes ] || setup_die "unknown target '$t' (known: $(printf '%s' "$SETUP_ALL_TARGETS" | tr ' ' ','))"
    REQUESTED="$REQUESTED $t"
  done
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/items"
ITEM_N=0

# In --json mode stdout belongs to the JSON document alone (§6).
out() { if [ -z "$OPT_JSON" ]; then printf '%s\n' "$*"; else printf '%s\n' "$*" >&2; fi; }

# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------
SOURCED_WRITERS=""

# load_target <name> — resets then sources platforms/<name>/setup.conf, then the
# writer library it names. Resetting first means a conf that forgets a field
# fails loudly instead of inheriting the previous target's value.
load_target() {
  local name="$1" conf
  SETUP_NAME=""; SETUP_DISPLAY=""; SETUP_DETECT=""; SETUP_CONFIG_DIR=""
  SETUP_ENV_OVERRIDE=""; SETUP_MARKER=""; SETUP_WRITERS=""; SETUP_MODULES=""
  SETUP_STATUS=""
  conf="${SETUP_REPO_ROOT}/platforms/${name}/setup.conf"
  [ -f "$conf" ] || { setup_warn "no setup.conf for target '$name' — skipping"; return 1; }
  # shellcheck source=/dev/null
  . "$conf"
  [ -n "$SETUP_NAME" ] || { setup_warn "$conf declares no SETUP_NAME — skipping"; return 1; }
  if [ -n "$SETUP_WRITERS" ] && [ "$(has "$SOURCED_WRITERS" "|$SETUP_WRITERS|")" = no ]; then
    # shellcheck source=/dev/null
    . "${SCRIPT_DIR}/lib/${SETUP_WRITERS}"
    SOURCED_WRITERS="${SOURCED_WRITERS}|${SETUP_WRITERS}|"
  fi
  # The config dir the platform's own env var points at wins over the default.
  if [ -n "$SETUP_ENV_OVERRIDE" ]; then
    local override; eval "override=\${${SETUP_ENV_OVERRIDE}:-}"
    [ -n "$override" ] && SETUP_CONFIG_DIR="$override"
  fi
  SETUP_TARGET_DIR="$SETUP_CONFIG_DIR"
  return 0
}

has() { case "$1" in *"$2"*) printf 'yes' ;; *) printf 'no' ;; esac; }

# fn <prefix> <suffix> — module function name; `-` is not legal in one.
fn() { printf '%s_%s_%s' "$(printf '%s' "$1" | tr '-' '_')" "$(printf '%s' "$2" | tr '-' '_')" "$3"; }
callable() { type "$1" >/dev/null 2>&1; }
call() { local f="$1"; shift; if callable "$f"; then "$f" "$@"; fi; }

target_requested() {
  [ -n "$REQUESTED" ] || return 1
  case " $REQUESTED " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# --only accepts one module or a comma list, and a bare family name selects the
# whole family (`--only notifications` picks up notifications-creds and
# notifications-hook) so the user does not have to know how a module is split up.
module_selected() {
  local want
  [ -n "$OPT_ONLY" ] || return 0
  for want in $(printf '%s' "$OPT_ONLY" | tr ',' ' '); do
    [ "$1" = "$want" ] && return 0
    case "$1" in "${want}-"*) return 0 ;; esac
  done
  return 1
}

# ---------------------------------------------------------------------------
# Detection — never a question (research pattern 1)
# ---------------------------------------------------------------------------
DETECT_LINES="$WORK/detect"
: > "$DETECT_LINES"

detect_target() {
  local bin=""
  DETECTED=no; DETECT_WHY="not installed"
  if [ -n "$SETUP_DETECT" ] && bin="$(command -v "$SETUP_DETECT" 2>/dev/null)"; then
    DETECTED=yes; DETECT_WHY="$bin"
  elif [ -d "$SETUP_TARGET_DIR" ]; then
    DETECTED=yes; DETECT_WHY="$SETUP_TARGET_DIR (config dir)"
  fi
  # An explicit --targets is a request, not just a filter: a fresh machine has
  # neither the binary nor the config dir yet, and `install.sh` must still work.
  if [ "$DETECTED" = no ] && target_requested "$SETUP_NAME"; then
    DETECTED=yes; DETECT_WHY="requested with --targets; not detected on this machine"
  fi
}

# ---------------------------------------------------------------------------
# Plan construction — every module renders, nothing writes
# ---------------------------------------------------------------------------

# add_item <target> <display> <module> <label> <kind> <path> <status> <note> [<content-file>] [<destructive>]
add_item() {
  local d; ITEM_N=$((ITEM_N + 1))
  d="$(printf '%s/items/%04d' "$WORK" "$ITEM_N")"
  mkdir -p "$d"
  printf '%s' "$1" > "$d/target";  printf '%s' "$2" > "$d/display"
  printf '%s' "$3" > "$d/module";  printf '%s' "$4" > "$d/label"
  printf '%s' "$5" > "$d/kind";    printf '%s' "$6" > "$d/path"
  printf '%s' "$7" > "$d/status";  printf '%s' "$8" > "$d/note"
  [ -n "${9:-}" ] && [ -f "${9:-}" ] && cp "$9" "$d/new"
  printf '%s' "${10:-no}" > "$d/destructive"
}

field() { cat "$1/$2" 2>/dev/null || printf ''; }

# SHADOW STATE — why the plan does not render against the real file
#   `settings`, `plugins`, `statusline` and `notifications-hook` all manage the
#   SAME ~/.claude/settings.json. If each rendered against the file on disk, the
#   plan would show four independent diffs that each silently discard the other
#   three, and applying them in order would leave only the last one's changes.
#   So planning runs against a private copy that accumulates: module N renders on
#   top of modules 1..N-1, exactly as the apply order will play out.
#
#   The shadow mirrors the real absolute path inside $WORK so that a renderer
#   which looks at a sibling file — `remove` reading the .pre-tamirs-superpowers
#   backup — still finds it. Seeding copies those siblings across.
shadow_for() {
  local p="$1" sp bak
  sp="${WORK}/shadow${p}"
  if [ ! -e "${sp}.tamirs-seeded" ]; then
    mkdir -p "$(dirname "$sp")"
    [ -f "$p" ] && cp "$p" "$sp"
    bak="$(setup_backup_path "$p")"
    [ -f "$bak" ] && cp "$bak" "$(setup_backup_path "$sp")"
    : > "${sp}.tamirs-seeded"
  fi
  printf '%s' "$sp"
}

plan_file_module() {
  local tgt="$1" disp="$2" mod="$3" pfx path shadow label avail render new cur destructive note status
  pfx="$tgt"
  label="$(call "$(fn "$pfx" "$mod" label)")"; [ -n "$label" ] || label="$mod"
  path="$(call "$(fn "$pfx" "$mod" path)")"
  shadow="$(shadow_for "$path")"

  avail="$(call "$(fn "$pfx" "$mod" available)")"; [ -n "$avail" ] || avail=yes
  if [ "$avail" != yes ]; then
    add_item "$tgt" "$disp" "$mod" "$label" file "$path" skip "${avail#no:}"
    return 0
  fi

  # The verb picks the renderer; everything downstream is identical. This is why
  # `remove` cannot drift from `apply` — they are the same code path.
  if [ "$VERB" = remove ]; then render="$(fn "$pfx" "$mod" unrender)"
  else render="$(fn "$pfx" "$mod" render)"; fi
  callable "$render" || { add_item "$tgt" "$disp" "$mod" "$label" file "$path" skip "no $render implemented"; return 0; }

  new="$WORK/new.$$"
  "$render" "$shadow" > "$new" 2>/dev/null || { add_item "$tgt" "$disp" "$mod" "$label" file "$path" skip "renderer failed"; return 0; }

  if [ "$(cat "$new")" = "$SETUP_DELETE_SENTINEL" ]; then
    if [ -f "$shadow" ]; then
      rm -f "$shadow"
      add_item "$tgt" "$disp" "$mod" "$label" file "$path" delete "remove file"
    else
      add_item "$tgt" "$disp" "$mod" "$label" file "$path" ok "already absent"
    fi
    rm -f "$new"; return 0
  fi

  # Normalise the CURRENT file through the same renderer-independent path we use
  # for the new one, so "already up to date" is a content question and never a
  # whitespace question.
  cur="$WORK/cur.$$"
  normalize_current "$path" "$shadow" > "$cur"

  if [ -f "$shadow" ] && cmp -s "$cur" "$new"; then
    add_item "$tgt" "$disp" "$mod" "$label" file "$path" ok "already up to date"
    rm -f "$new" "$cur"; return 0
  fi
  if [ ! -f "$shadow" ] && [ ! -s "$new" ]; then
    add_item "$tgt" "$disp" "$mod" "$label" file "$path" ok "nothing to do"
    rm -f "$new" "$cur"; return 0
  fi

  destructive="$(call "$(fn "$pfx" "$mod" destructive)" "$shadow")"; [ -n "$destructive" ] || destructive=no
  note="$(call "$(fn "$pfx" "$mod" summary)" "$shadow" "$new")"
  if [ -f "$shadow" ]; then status=modify; else status=create; fi
  [ -n "$note" ] || note="$status"
  add_item "$tgt" "$disp" "$mod" "$label" file "$path" "$status" "$note" "$new" "$destructive"
  cp "$new" "$shadow"          # module N+1 plans on top of this one
  rm -f "$new" "$cur"
}

# normalize_current <real-path-for-type> <file-to-read> — canonical rendering of
# a file as it stands, so "up to date" is never a whitespace question.
normalize_current() {
  local kind_path="$1" src="$2"
  if [ ! -f "$src" ]; then return 0; fi
  case "$kind_path" in
    *.json) setup_json_read "$src" | setup_json_normalize ;;
    *) cat "$src" ;;
  esac
}

plan_dir_module() {
  local tgt="$1" disp="$2" mod="$3" pfx label path avail pairs n_change n_total src dest
  pfx="$tgt"
  label="$(call "$(fn "$pfx" "$mod" label)")"; [ -n "$label" ] || label="$mod"
  path="$(call "$(fn "$pfx" "$mod" path)")"
  avail="$(call "$(fn "$pfx" "$mod" available)")"; [ -n "$avail" ] || avail=yes
  if [ "$avail" != yes ]; then
    add_item "$tgt" "$disp" "$mod" "$label" dir "$path" skip "${avail#no:}"; return 0
  fi

  pairs="$WORK/pairs.$$"
  "$(fn "$pfx" "$mod" dir_pairs)" > "$pairs"
  n_total=0; n_change=0
  while IFS="$(printf '\t')" read -r src dest; do
    [ -n "$src" ] || continue
    n_total=$((n_total + 1))
    if [ "$VERB" = remove ]; then
      [ -f "$dest" ] && n_change=$((n_change + 1))
    else
      cmp -s "$src" "$dest" 2>/dev/null || n_change=$((n_change + 1))
    fi
  done < "$pairs"

  if [ "$n_change" -eq 0 ] && [ "$VERB" = remove ]; then
    add_item "$tgt" "$disp" "$mod" "$label" dir "$path" ok "already removed"
  elif [ "$n_change" -eq 0 ]; then
    add_item "$tgt" "$disp" "$mod" "$label" dir "$path" ok "$n_total file(s) already up to date"
  elif [ "$VERB" = remove ]; then
    add_item "$tgt" "$disp" "$mod" "$label" dir "$path" delete "$n_change of $n_total file(s)" "$pairs"
  else
    add_item "$tgt" "$disp" "$mod" "$label" dir "$path" modify "$n_change of $n_total file(s)" "$pairs"
  fi
  rm -f "$pairs"
}

build_plan() {
  local t mod kind
  for t in $SETUP_ALL_TARGETS; do
    if [ -n "$REQUESTED" ] && ! target_requested "$t"; then continue; fi
    load_target "$t" || continue
    detect_target
    printf '%s\t%s\t%s\t%s\t%s\n' "$SETUP_NAME" "$SETUP_DISPLAY" "$DETECTED" "$DETECT_WHY" "$SETUP_STATUS" >> "$DETECT_LINES"
    [ "$DETECTED" = yes ] || continue

    if [ -z "$SETUP_MODULES" ]; then
      add_item "$SETUP_NAME" "$SETUP_DISPLAY" "-" "-" none "$SETUP_TARGET_DIR" skip \
        "no modules implemented yet (Phase 3)"
      continue
    fi
    call "$(printf '%s_target_init' "$(printf '%s' "$t" | tr '-' '_')")"
    for mod in $SETUP_MODULES; do
      module_selected "$mod" || continue
      kind="$(call "$(fn "$t" "$mod" kind)")"
      case "$kind" in
        dir) plan_dir_module "$SETUP_NAME" "$SETUP_DISPLAY" "$mod" ;;
        file) plan_file_module "$SETUP_NAME" "$SETUP_DISPLAY" "$mod" ;;
        *) setup_warn "target $t module $mod declares no kind — skipping" ;;
      esac
    done
  done
}

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------
count_status() {
  local want="$1" n=0 d
  for d in "$WORK"/items/*; do
    [ -d "$d" ] || continue
    [ "$(field "$d" status)" = "$want" ] && n=$((n + 1))
  done
  printf '%s' "$n"
}

print_detection() {
  local name disp det why st mark
  out ""
  out "${SETUP_C_BOLD}tamirs-superpowers setup — detecting targets${SETUP_C_OFF}"
  out ""
  while IFS="$(printf '\t')" read -r name disp det why st; do
    [ -n "$name" ] || continue
    if [ "$det" = yes ]; then mark="${SETUP_C_GREEN}ok${SETUP_C_OFF}"; else mark="${SETUP_C_DIM}--${SETUP_C_OFF}"; fi
    if [ "$st" = not-yet-implemented ] && [ "$det" = yes ]; then
      out "$(printf '  %s  %-14s %-42s %s' "$mark" "$disp" "$why" "no modules implemented yet")"
    else
      out "$(printf '  %s  %-14s %s' "$mark" "$disp" "$why")"
    fi
  done < "$DETECT_LINES"
}

print_plan() {
  local d last="" tgt n_change n_ok n_skip
  n_ok="$(count_status ok)"; n_skip="$(count_status skip)"
  n_change=$(( $(count_status modify) + $(count_status create) + $(count_status delete) ))
  out ""
  out "$(printf '%sPlan (%s change(s), %s already up to date, %s skipped)%s' \
    "$SETUP_C_BOLD" "$n_change" "$n_ok" "$n_skip" "$SETUP_C_OFF")"
  out ""
  for d in "$WORK"/items/*; do
    [ -d "$d" ] || continue
    tgt="$(field "$d" display)"
    if [ "$tgt" != "$last" ]; then out "  $tgt"; last="$tgt"; fi
    out "$(printf '    %-18s %-7s %-46s %s' \
      "$(field "$d" label)" "$(field "$d" status)" "$(setup_tilde "$(field "$d" path)")" "${SETUP_C_DIM}$(field "$d" note)${SETUP_C_OFF}")"
  done
  out ""
}

print_json() {
  local d first=1
  printf '{"ok":true,"verb":"%s","targets":[' "$VERB"
  local name disp det why st
  while IFS="$(printf '\t')" read -r name disp det why st; do
    [ -n "$name" ] || continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    jq -nc --arg n "$name" --arg d "$disp" --arg det "$det" --arg why "$why" --arg st "$st" \
      '{name:$n,display:$d,detected:($det=="yes"),detection:$why,status:$st}' | tr -d '\n'
  done < "$DETECT_LINES"
  printf '],"changes":['
  first=1
  for d in "$WORK"/items/*; do
    [ -d "$d" ] || continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    jq -nc --arg t "$(field "$d" target)" --arg m "$(field "$d" module)" \
           --arg l "$(field "$d" label)" --arg p "$(field "$d" path)" \
           --arg s "$(field "$d" status)" --arg note "$(field "$d" note)" \
           --arg dz "$(field "$d" destructive)" \
      '{target:$t,module:$m,label:$l,path:$p,status:$s,note:$note,destructive:($dz=="yes")}' | tr -d '\n'
  done
  printf '],"summary":{"changes":%s,"up_to_date":%s,"skipped":%s}}\n' \
    "$(( $(count_status modify) + $(count_status create) + $(count_status delete) ))" \
    "$(count_status ok)" "$(count_status skip)"
}

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------
ALL_YES=""
QUIT=""
N_WRITTEN=0
N_SKIPPED_BY_USER=0

# backup_once <file> — the fixed name is taken exactly once and never rotated
# away, so `remove` always restores the file as it was before we ever ran.
backup_once() {
  local f="$1" fixed
  [ -f "$f" ] || return 0
  fixed="$(setup_backup_path "$f")"
  [ -f "$fixed" ] && return 0
  cp "$f" "$fixed"
  printf '%s' "$fixed"
}

# show_diff <item-dir> <new-content-file>
show_diff() {
  local d="$1" new="$2" path tmp _src _dest
  path="$(field "$d" path)"
  out ""
  out "──────────────────────────────────────────────────────────────"
  out "$(field "$d" display) · $(field "$d" label) · $(setup_tilde "$path")"
  out "──────────────────────────────────────────────────────────────"
  if [ "$(field "$d" kind)" = dir ]; then
    # One line per file, destination-relative: the source is always this repo.
    while IFS="$(printf '\t')" read -r _src _dest; do
      [ -n "$_src" ] || continue
      if [ "$VERB" = remove ]; then [ -f "$_dest" ] || continue
      else cmp -s "$_src" "$_dest" 2>/dev/null && continue; fi
      out "  $(basename "$_src")  ->  $(setup_tilde "$_dest")"
    done < "$new"
    return 0
  fi
  if [ "$(cat "$new")" = "$SETUP_DELETE_SENTINEL" ]; then
    out "  the file would be removed"
    return 0
  fi
  tmp="$WORK/diffcur"
  normalize_current "$path" "$path" > "$tmp"
  out "$(setup_diff "$tmp" "$new")"
}

# confirm_normal — the [y/N/a/q] loop. Default is No, always.
# Returns: 0 proceed, 1 skip, 2 quit.
confirm_normal() {
  local ans
  [ -n "$ALL_YES" ] && return 0
  if [ -n "$SETUP_YES" ]; then return 0; fi
  ans="$(setup_lower "$(setup_ask 'Proceed? [y/N/a/q] ' n)")"
  case "$ans" in
    y|yes) return 0 ;;
    a|all) ALL_YES=1; return 0 ;;
    q|quit) return 2 ;;
    *) return 1 ;;
  esac
}

# confirm_destructive — a file the user customised. Show what is at stake first
# (research pattern 10), then offer three named choices with unique prefixes,
# defaulting to the one that cannot lose data.
# Returns: 0 overwrite, 3 backup-and-write, 1 skip, 2 quit.
confirm_destructive() {
  local d="$1" ans path
  path="$(field "$d" path)"
  out ""
  out "${SETUP_C_YELLOW}This replaces a file you have customised.${SETUP_C_OFF}"
  out "  $(setup_tilde "$path")"
  out "  A backup would be written to $(setup_tilde "$(setup_backup_path "$path")")"
  if [ "${SETUP_DESTRUCTIVE:-}" = skip ]; then
    out "  SETUP_DESTRUCTIVE=skip — leaving it alone."
    return 1
  fi
  if [ -n "$SETUP_YES" ] || [ -n "$ALL_YES" ]; then return 3; fi
  ans="$(setup_lower "$(setup_ask 'overwrite / backup-and-write / skip / quit [backup-and-write] ' b)")"
  case "$ans" in
    o|ov|over|overwrite) return 0 ;;
    s|sk|ski|skip) return 1 ;;
    q|qu|qui|quit) return 2 ;;
    *) return 3 ;;
  esac
}

apply_file_item() {
  local d="$1" path new cur backup rc mod tgt render
  path="$(field "$d" path)"
  tgt="$(field "$d" target)"; mod="$(field "$d" module)"

  # RE-RENDER, do not replay the plan. Earlier modules in this run may have been
  # declined, so the file on disk is not necessarily what the plan assumed. The
  # diff shown below is therefore the diff that actually happens — approving it
  # can never write something the user did not see.
  if [ "$VERB" = remove ]; then render="$(fn "$tgt" "$mod" unrender)"
  else render="$(fn "$tgt" "$mod" render)"; fi
  new="$WORK/live.new"
  if callable "$render"; then
    "$render" "$path" > "$new" 2>/dev/null || cp "$d/new" "$new"
  else
    cp "$d/new" "$new"
  fi

  if [ "$(cat "$new")" = "$SETUP_DELETE_SENTINEL" ] && [ ! -f "$path" ]; then
    out "  ${SETUP_C_DIM}==${SETUP_C_OFF}  $(field "$d" display)  $(field "$d" label)  already absent"; return 0
  fi
  if [ "$(field "$d" status)" != delete ] && [ "$(cat "$new")" != "$SETUP_DELETE_SENTINEL" ]; then
    cur="$WORK/live.cur"
    normalize_current "$path" "$path" > "$cur"
    if [ -f "$path" ] && cmp -s "$cur" "$new"; then
      out "  ${SETUP_C_DIM}==${SETUP_C_OFF}  $(field "$d" display)  $(field "$d" label)  already up to date"; return 0
    fi
  fi

  show_diff "$d" "$new"

  if [ "$(cat "$new")" = "$SETUP_DELETE_SENTINEL" ]; then
    confirm_normal; rc=$?
    case $rc in
      1) out "  ${SETUP_C_DIM}--${SETUP_C_OFF}  $(field "$d" display)  $(field "$d" label)  skipped"
         N_SKIPPED_BY_USER=$((N_SKIPPED_BY_USER + 1)); return 0 ;;
      2) QUIT=1; return 0 ;;
    esac
    rm -f "$path"
    out "  ${SETUP_C_GREEN}ok${SETUP_C_OFF}  $(field "$d" display)  $(field "$d" label)  removed"
    N_WRITTEN=$((N_WRITTEN + 1)); return 0
  fi

  backup=""
  if [ "$(field "$d" destructive)" = yes ]; then
    confirm_destructive "$d"; rc=$?
    case $rc in
      1) out "  ${SETUP_C_DIM}--${SETUP_C_OFF}  $(field "$d" display)  $(field "$d" label)  skipped"
         N_SKIPPED_BY_USER=$((N_SKIPPED_BY_USER + 1)); return 0 ;;
      2) QUIT=1; return 0 ;;
      3) backup="$(setup_backup "$path")" ;;
      0) : ;;
    esac
  else
    confirm_normal; rc=$?
    case $rc in
      1) out "  ${SETUP_C_DIM}--${SETUP_C_OFF}  $(field "$d" display)  $(field "$d" label)  skipped"
         N_SKIPPED_BY_USER=$((N_SKIPPED_BY_USER + 1)); return 0 ;;
      2) QUIT=1; return 0 ;;
    esac
    # On `remove` the file on disk may hold months of hand edits made AFTER the
    # install, and restoring the pristine backup would discard them. Rotate a
    # dated copy first so the undo is itself undoable.
    if [ "$VERB" = remove ]; then backup="$(setup_backup "$path")"
    else backup="$(backup_once "$path")"; fi
  fi

  setup_write "$path" < "$new"
  call "$(fn "$tgt" "$mod" postwrite)" "$path"
  if [ -n "$backup" ]; then
    out "  ${SETUP_C_GREEN}ok${SETUP_C_OFF}  $(field "$d" display)  $(field "$d" label)  written (backup: $backup)"
  else
    out "  ${SETUP_C_GREEN}ok${SETUP_C_OFF}  $(field "$d" display)  $(field "$d" label)  written"
  fi
  N_WRITTEN=$((N_WRITTEN + 1))
}

apply_dir_item() {
  local d="$1" rc src dest n=0
  confirm_normal; rc=$?
  case $rc in
    1) out "  ${SETUP_C_DIM}--${SETUP_C_OFF}  $(field "$d" display)  $(field "$d" label)  skipped"
       N_SKIPPED_BY_USER=$((N_SKIPPED_BY_USER + 1)); return 0 ;;
    2) QUIT=1; return 0 ;;
  esac
  while IFS="$(printf '\t')" read -r src dest; do
    [ -n "$src" ] || continue
    if [ "$(field "$d" status)" = delete ]; then
      [ -f "$dest" ] && { rm -f "$dest"; n=$((n + 1)); }
    else
      cmp -s "$src" "$dest" 2>/dev/null && continue
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"; n=$((n + 1))
    fi
  done < "$d/new"
  out "  ${SETUP_C_GREEN}ok${SETUP_C_OFF}  $(field "$d" display)  $(field "$d" label)  $n file(s)"
  N_WRITTEN=$((N_WRITTEN + 1))
}

apply_plan() {
  local d st
  out ""
  for d in "$WORK"/items/*; do
    [ -d "$d" ] || continue
    [ -n "$QUIT" ] && break
    st="$(field "$d" status)"
    case "$st" in
      ok)   out "  ${SETUP_C_DIM}==${SETUP_C_OFF}  $(field "$d" display)  $(field "$d" label)  already up to date"; continue ;;
      skip) out "  ${SETUP_C_DIM}--${SETUP_C_OFF}  $(field "$d" display)  $(field "$d" label)  skipped — $(field "$d" note)"; continue ;;
    esac
    if [ "$(field "$d" kind)" = dir ]; then
      [ -f "$d/new" ] || continue
      show_diff "$d" "$d/new"; apply_dir_item "$d"
    else
      apply_file_item "$d"
    fi
  done
}

# ---------------------------------------------------------------------------
main() {
  build_plan

  if [ -n "$OPT_JSON" ]; then
    print_detection; print_plan; print_json; exit 0
  fi

  print_detection
  print_plan

  local n_change
  n_change=$(( $(count_status modify) + $(count_status create) + $(count_status delete) ))

  if [ "$VERB" = plan ]; then
    out "Nothing has been written. Re-run with 'apply' to make these changes."
    exit 0
  fi

  if [ "$n_change" -eq 0 ]; then
    out "Everything is already up to date. Nothing to do."
    exit 0
  fi

  # The stdin resolution, in one place: with no way to ask and no explicit --yes,
  # a plan is a useful, safe, zero-side-effect result. Never adopt silently,
  # never error, never block.
  if ! setup_can_prompt && [ -z "$SETUP_YES" ]; then
    setup_note "no TTY — cannot prompt. Showing the plan instead; re-run with --yes to apply."
    exit 0
  fi

  apply_plan

  out ""
  if [ -n "$QUIT" ]; then
    out "Stopped at your request. $N_WRITTEN change(s) written before quitting."
  else
    out "Done. $N_WRITTEN written, $(count_status ok) already up to date, $(( $(count_status skip) + N_SKIPPED_BY_USER )) skipped."
  fi
  out ""
  out "  Verify:   bash scripts/doctor.sh ."
  if [ "$VERB" = apply ]; then out "  Undo:     bash scripts/setup.sh remove"; fi
  exit 0
}

main
