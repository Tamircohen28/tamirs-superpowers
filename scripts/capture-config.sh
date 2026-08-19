#!/usr/bin/env bash
# capture-config.sh — propose this machine's hand-edits back into the repo.
#
# USAGE
#   bash scripts/capture-config.sh [detect|review|deliver] [flags]
#   make capture
#
# THE DIRECTION THIS RUNS IN
#   scripts/setup.sh renders repo -> machine. This is the inverse: machine -> repo,
#   reviewed, landing as a pull request. It answers "I tuned something by hand;
#   make it permanent and available on every platform and every machine."
#   It is a separate entrypoint on purpose. Render only ever writes files this
#   repo authored. Capture reads files a PERSON edited, so every value that
#   crosses the boundary is classified, IP-scanned and shown before it can land —
#   and it lands as a reviewed PR, never as a silent commit.
#
# VERBS
#   detect   diff the machine against what the repo would render and print the
#            classified change set. NEVER writes. The default.
#   review   detect, then ask about each offerable hunk one at a time, stage the
#            adopted ones into the repo's CANONICAL SOURCE, and show what they
#            then render to on every other platform.
#   deliver  branch, one commit per platform touched, auto-written PR body.
#            Runs `make validate` first and NEVER merges.
#
# FLAGS
#   --targets a,b     restrict to these targets
#   --only <module>   restrict to one module; matches `x` and `x-*`
#   --adopt <ids>     adopt these hunk ids without prompting (`all` for every
#                     offerable one). An explicit list is a decision; this is the
#                     only way to adopt without a terminal, and it is never a
#                     default.
#   --json            machine-readable change set on stdout, humans on stderr
#   --verbose, -v     detailed logging to stderr
#   --help, -h        this text
#
# CLASSIFICATION — every hunk carries one
#   portable       belongs in the repo, true on every machine        -> OFFERED
#   machine-local  true here only (absolute paths, project lists)    -> skipped
#   secret         credentials or token-shaped values                -> REFUSED,
#                  never offered and never printed
#   third-party    wiring another tool owns                          -> skipped,
#                  with the owner named
#   unknown        no rule covers it                                 -> ASKED
#
# SAFETY GATES, ALL BLOCKING AND ALL PER HUNK
#   * the repo's own IP scan runs over every hunk; a hit blocks THAT hunk only
#   * token-shaped values are refused outright — only an env var NAME travels
#   * an absolute /Users/... path is reclassified machine-local, never adopted
#   * `_`-prefixed metadata keys are stripped; repo-side documentation must not
#     round-trip into captured data
#   * `make validate` must pass before `deliver` opens anything
#
# EXAMPLES
#   bash scripts/capture-config.sh detect
#   bash scripts/capture-config.sh detect --targets claude --json
#   bash scripts/capture-config.sh review --targets claude
#   bash scripts/capture-config.sh review --adopt 3,7
#   bash scripts/capture-config.sh deliver
#
# EXIT CODES
#   0  success, or "no TTY so here is the change set instead"
#   1  failure (bad flag, unknown target, missing dependency, failed gate)
#
# STDIN IS NEVER READ. Prompts go to /dev/tty. A run with no terminal prints the
# change set and exits 0 — it never adopts silently.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/setup-common.sh
. "${SCRIPT_DIR}/lib/setup-common.sh"
# shellcheck source=scripts/lib/capture-common.sh
. "${SCRIPT_DIR}/lib/capture-common.sh"

SETUP_DELETE_SENTINEL="@@tamirs-superpowers-delete-this-file@@"

VERB=""
OPT_TARGETS="${CAPTURE_TARGETS:-}"
OPT_ONLY="${CAPTURE_ONLY:-}"
OPT_ADOPT="${CAPTURE_ADOPT:-}"
OPT_JSON=""
SETUP_VERBOSE="${SETUP_VERBOSE:-}"

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; }

while [ $# -gt 0 ]; do
  case "$1" in
    detect|review|deliver)
      [ -z "$VERB" ] || setup_die "more than one verb given ('$VERB' then '$1')"
      VERB="$1" ;;
    --targets) shift; [ $# -gt 0 ] || setup_die "--targets needs a value"; OPT_TARGETS="$1" ;;
    --targets=*) OPT_TARGETS="${1#*=}" ;;
    --only)   shift; [ $# -gt 0 ] || setup_die "--only needs a value"; OPT_ONLY="$1" ;;
    --only=*) OPT_ONLY="${1#*=}" ;;
    --adopt)   shift; [ $# -gt 0 ] || setup_die "--adopt needs a value"; OPT_ADOPT="$1" ;;
    --adopt=*) OPT_ADOPT="${1#*=}" ;;
    --json)   OPT_JSON=1 ;;
    --verbose|-v) SETUP_VERBOSE=1 ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    -*) setup_err "unknown flag: $1"; printf 'Try: bash scripts/capture-config.sh --help\n' >&2; exit 1 ;;
    *)  setup_err "unexpected argument: $1"; printf 'Try: bash scripts/capture-config.sh --help\n' >&2; exit 1 ;;
  esac
  shift
done

# `detect` is the default in every case. Unlike setup.sh there is no
# terminal-sensitive default that writes: capture writing to the repo is never
# something the user gets by pressing return on a bare command.
[ -n "$VERB" ] || VERB="detect"

setup_require jq "brew install jq / apt-get install jq — required to read JSON config"

REQUESTED=""
if [ -n "$OPT_TARGETS" ]; then
  for t in $(printf '%s' "$OPT_TARGETS" | tr ',' ' '); do
    known=no
    for k in $CAPTURE_ALL_TARGETS; do [ "$t" = "$k" ] && known=yes; done
    [ "$known" = yes ] || setup_die "unknown target '$t' (known: $(printf '%s' "$CAPTURE_ALL_TARGETS" | tr ' ' ','))"
    REQUESTED="$REQUESTED $t"
  done
fi

CAPTURE_WORK="$(mktemp -d)"
trap 'rm -rf "$CAPTURE_WORK"' EXIT
mkdir -p "$CAPTURE_WORK/hunks"
HUNK_N=0

out() { if [ -z "$OPT_JSON" ]; then printf '%s\n' "$*"; else printf '%s\n' "$*" >&2; fi; }
field() { cat "$1/$2" 2>/dev/null || printf ''; }

target_requested() {
  [ -n "$REQUESTED" ] || return 1
  case " $REQUESTED " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

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
# Building the change set
# ---------------------------------------------------------------------------

# add_hunk <target> <display> <module> <machine-file> <kind> <keypath> <pathjson>
#          <machine-value-json> <repo-value-json> <class> <reason> <sink> <blocked>
add_hunk() {
  local d; HUNK_N=$((HUNK_N + 1))
  d="$(printf '%s/hunks/%04d' "$CAPTURE_WORK" "$HUNK_N")"
  mkdir -p "$d"
  printf '%s' "$1"  > "$d/target";   printf '%s' "$2"  > "$d/display"
  printf '%s' "$3"  > "$d/module";   printf '%s' "$4"  > "$d/file"
  printf '%s' "$5"  > "$d/kind";     printf '%s' "$6"  > "$d/keypath"
  printf '%s' "$7"  > "$d/pathjson"; printf '%s' "$8"  > "$d/machine"
  printf '%s' "$9"  > "$d/repo";     printf '%s' "${10}" > "$d/class"
  printf '%s' "${11}" > "$d/reason"; printf '%s' "${12}" > "$d/sink"
  printf '%s' "${13}" > "$d/blocked"
  printf '%s' "$HUNK_N" > "$d/id"
}

# offerable <hunk-dir> — `portable` and `unknown` are the only two classes a
# person is ever asked about, and only when no gate blocked them. Every other
# class is reported and skipped without a question, which is what keeps the
# review loop short enough to actually read.
offerable() {
  local d="$1"
  [ -z "$(field "$d" blocked)" ] || return 1
  case "$(field "$d" class)" in portable|unknown) return 0 ;; *) return 1 ;; esac
}

# scan_and_record <target> <display> <module> <file> <tsv-line>
# The gate order is fixed here, not per platform: classify, then IP-scan
# anything that survived as offerable. Scanning a secret would print it into the
# scanner's output, so the scan runs strictly after the refusal.
scan_and_record() {
  local tgt="$1" disp="$2" mod="$3" file="$4" line="$5"
  local kind key pathjson mval rval cls reason sink blocked plain mtype rtype

  kind="$(printf '%s' "$line" | cut -f1)"
  key="$(printf '%s' "$line" | cut -f2)"
  pathjson="$(printf '%s' "$line" | cut -f3)"
  mval="$(printf '%s' "$line" | cut -f4)"
  rval="$(printf '%s' "$line" | cut -f5)"

  # The plain (decoded) value is what the classifier and the scanner read; the
  # JSON form is what gets staged. Decoding once here keeps the two in step.
  plain="$(printf '%s' "$mval" | jq -r 'if type=="string" then . else tojson end' 2>/dev/null || printf '%s' "$mval")"

  cls="$(capture_classify "$tgt" "$key" "$plain" "$kind")"
  reason="$(printf '%s' "$cls" | cut -f2)"
  cls="$(printf '%s' "$cls" | cut -f1)"

  # capture_ip_scan prints its reason and returns 1 on a hit. A secret is never
  # handed to it: the scanner echoes what it matched, and a reason that quotes a
  # token defeats the refusal it is reporting.
  blocked=""
  if [ "$cls" != secret ] && [ "$cls" != third-party ]; then
    blocked="$(capture_ip_scan "$key" "$plain")" || true
  fi

  # TYPE CONFLICT. The repo asserting an array where the machine holds a scalar
  # (Gemini's `context.fileName` is exactly this) is not a value to adopt: the
  # staging step sets the path, so taking the machine's string would REPLACE the
  # repo's list and quietly narrow it. Blocked, with the shapes named, so the
  # user edits the canonical file deliberately instead.
  if [ "$rval" != absent ] && [ -z "$blocked" ]; then
    mtype="$(printf '%s' "$mval" | jq -r 'type' 2>/dev/null || printf '?')"
    rtype="$(printf '%s' "$rval" | jq -r 'type' 2>/dev/null || printf '?')"
    if [ "$mtype" != "$rtype" ]; then
      blocked="the repo asserts $rtype here and the machine holds $mtype — adopting would narrow it; edit the canonical file by hand"
    fi
  fi

  sink=""
  if [ "$cls" = portable ] || [ "$cls" = unknown ]; then
    sink="$(capture_sink_for "$mod" "$key" || printf '')"
    [ -n "$sink" ] || blocked="${blocked:-no sink is declared for this key path}"
  fi

  add_hunk "$tgt" "$disp" "$mod" "$file" "$kind" "$key" "$pathjson" \
           "$mval" "$rval" "$cls" "$reason" "$sink" "$blocked"
}

# scan_module <target> <display> <module>
# THE REVERSED COMPARISON LIVES HERE, in five lines:
#   machine = the file as setup.sh's own normalisation sees it
#   repo    = the SAME renderer setup.sh calls, given a file that is not there
# Rendering against an absent file is the reversal. `render` deep-merges the repo
# onto whatever it is handed, so render(machine) always contains the machine's
# own keys and diffing against it would find nothing. Handed nothing, it emits
# the repo's assertion alone — and what the machine has that this lacks is
# exactly the set of things a person added by hand.
scan_module() {
  local tgt="$1" disp="$2" mod="$3" path avail render machine repo nofile line
  path="$(capture_call "$(capture_fn "$tgt" "$mod" path)")"
  [ -n "$path" ] || return 0
  avail="$(capture_call "$(capture_fn "$tgt" "$mod" available)")"; [ -n "$avail" ] || avail=yes
  [ "$avail" = yes ] || { setup_debug "$tgt/$mod unavailable: ${avail#no:}"; return 0; }
  [ -f "$path" ] || { setup_debug "$tgt/$mod: $path absent on this machine"; return 0; }

  render="$(capture_fn "$tgt" "$mod" render)"
  capture_callable "$render" || return 0

  nofile="${CAPTURE_WORK}/absent-by-design"
  rm -f "$nofile"
  machine="${CAPTURE_WORK}/machine.$$"
  repo="${CAPTURE_WORK}/repo.$$"
  capture_normalize_machine "$path" | capture_meta_filter "$path" > "$machine"
  repo_assertion "$tgt" "$path" > "$repo"

  case "$path" in
    *.json)
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        scan_and_record "$tgt" "$disp" "$mod" "$path" "$line"
      done <<CAPTURE_JSON_EOF
$(capture_json_hunks "$machine" "$repo")
CAPTURE_JSON_EOF
      ;;
    *)
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        scan_and_record "$tgt" "$disp" "$mod" "$path" "$line"
      done <<CAPTURE_MD_EOF
$(capture_md_hunks "$machine" "$repo")
CAPTURE_MD_EOF
      ;;
  esac
  rm -f "$machine" "$repo"
}

# repo_assertion <target> <path> — what the repo asserts for one file, ALONE.
#
# Every module that writes this path is rendered, in setup.conf order, each on
# top of the last, starting from a file that is not there. That accumulation is
# the same one setup.sh performs against its shadow copy, and it is load-bearing
# in this direction too: four Claude modules write ~/.claude/settings.json, so
# rendering only the first would leave `statusLine` and `enabledPlugins` out of
# the repo's assertion — and capture would then offer back to the repo the very
# values setup.sh had just written to the machine.
repo_assertion() {
  local tgt="$1" path="$2" m mpath render acc next
  acc="${CAPTURE_WORK}/assert.$$"
  : > "$acc"
  rm -f "${acc}.seed"
  next="${CAPTURE_WORK}/assert-next.$$"
  for m in $SETUP_MODULES; do
    [ "$(capture_call "$(capture_fn "$tgt" "$m" kind)")" = file ] || continue
    mpath="$(capture_call "$(capture_fn "$tgt" "$m" path)")"
    [ "$mpath" = "$path" ] || continue
    case "$(capture_call "$(capture_fn "$tgt" "$m" available)")" in no:*|no) continue ;; esac
    render="$(capture_fn "$tgt" "$m" render)"
    capture_callable "$render" || continue
    if [ -s "$acc" ]; then
      "$render" "$acc" > "$next" 2>/dev/null || cp "$acc" "$next"
    else
      "$render" "${CAPTURE_WORK}/absent-by-design" > "$next" 2>/dev/null || : > "$next"
    fi
    [ "$(cat "$next")" = "$SETUP_DELETE_SENTINEL" ] && : > "$next"
    mv "$next" "$acc"
  done
  case "$path" in
    *.json) [ -s "$acc" ] || printf '{}\n' > "$acc" ;;
  esac
  cat "$acc"
  rm -f "$acc" "$next"
}

# capture_meta_filter <path> — drop `_`-prefixed keys from the machine side
# before anything else looks at it. This repo's fragments carry `_comment` and
# `_tally` for the next reader; setup.sh strips them on the way OUT, and this is
# the same rule on the way back IN. Without it, repo-side documentation would
# round-trip into captured data and be written back as a real setting.
capture_meta_filter() {
  case "$1" in
    *.json) capture_strip_meta ;;
    *) cat ;;
  esac
}

build_change_set() {
  local t mod path seen
  for t in $CAPTURE_ALL_TARGETS; do
    if [ -n "$REQUESTED" ] && ! target_requested "$t"; then continue; fi
    capture_load_target "$t" || continue
    capture_setup_load "$t" || continue
    # ONE SCAN PER FILE, not per module. Four Claude modules manage the single
    # ~/.claude/settings.json; scanning once per module reported every hand-edit
    # four times over. Which module read the file does not change what is in it,
    # and the sink is decided by key path (see platforms/claude/capture.conf).
    seen=""
    for mod in $CAPTURE_MODULES; do
      module_selected "$mod" || continue
      case " $SETUP_MODULES " in
        *" $mod "*) : ;;
        *) setup_warn "$t/capture.conf names module '$mod', which setup.conf does not — skipping"; continue ;;
      esac
      [ "$(capture_call "$(capture_fn "$t" "$mod" kind)")" = file ] || continue
      path="$(capture_call "$(capture_fn "$t" "$mod" path)")"
      case " $seen " in *" $path "*) continue ;; esac
      seen="$seen $path"
      scan_module "$CAPTURE_NAME" "$CAPTURE_DISPLAY" "$mod"
    done
  done
}

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------
count_class() {
  local want="$1" n=0 d
  for d in "$CAPTURE_WORK"/hunks/*; do
    [ -d "$d" ] || continue
    [ "$(field "$d" class)" = "$want" ] && n=$((n + 1))
  done
  printf '%s' "$n"
}
count_offerable() {
  local n=0 d
  for d in "$CAPTURE_WORK"/hunks/*; do
    [ -d "$d" ] || continue
    offerable "$d" && n=$((n + 1))
  done
  printf '%s' "$n"
}

# show_value <hunk-dir> — the machine value, EXCEPT for a secret, whose value is
# never rendered anywhere: not in the table, not in the diff, not in --json.
show_value() {
  local d="$1"
  if [ "$(field "$d" class)" = secret ]; then printf '<refused — not printed>'; return 0; fi
  printf '%s' "$(field "$d" machine)" | cut -c1-72
}

class_colour() {
  case "$1" in
    portable) printf '%s' "$SETUP_C_GREEN" ;;
    secret)   printf '%s' "$SETUP_C_RED" ;;
    unknown)  printf '%s' "$SETUP_C_YELLOW" ;;
    *)        printf '%s' "$SETUP_C_DIM" ;;
  esac
}

print_change_set() {
  local d last="" hdr
  out ""
  out "${SETUP_C_BOLD}capture — machine differences against what this repo would render${SETUP_C_OFF}"
  if [ "$HUNK_N" -eq 0 ]; then
    out ""
    out "  No differences. Every value on this machine is one the repo already asserts."
    return 0
  fi
  for d in "$CAPTURE_WORK"/hunks/*; do
    [ -d "$d" ] || continue
    hdr="$(field "$d" display) · $(setup_tilde "$(field "$d" file)")"
    if [ "$hdr" != "$last" ]; then out ""; out "  $hdr"; last="$hdr"; fi
    out "$(printf '    %-4s %s%-13s%s %-34s %s' \
      "[$(field "$d" id)]" "$(class_colour "$(field "$d" class)")" "$(field "$d" class)" "$SETUP_C_OFF" \
      "$(field "$d" keypath)" "$(show_value "$d")")"
    if [ -n "$(field "$d" blocked)" ]; then
      out "$(printf '         %sblocked: %s%s' "$SETUP_C_RED" "$(field "$d" blocked)" "$SETUP_C_OFF")"
    else
      out "$(printf '         %s%s%s' "$SETUP_C_DIM" "$(field "$d" reason)" "$SETUP_C_OFF")"
    fi
  done
  out ""
  out "$(printf '  %s offerable · %s portable · %s machine-local · %s secret (refused) · %s third-party · %s unknown' \
    "$(count_offerable)" "$(count_class portable)" "$(count_class machine-local)" \
    "$(count_class secret)" "$(count_class third-party)" "$(count_class unknown)")"
}

# print_json — the value of a `secret` hunk is omitted from the document too.
# A machine-readable refusal that still carries the credential is not a refusal.
print_json() {
  local d first=1
  printf '{"ok":true,"verb":"%s","hunks":[' "$VERB"
  for d in "$CAPTURE_WORK"/hunks/*; do
    [ -d "$d" ] || continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    jq -nc --arg id "$(field "$d" id)" --arg t "$(field "$d" target)" \
           --arg m "$(field "$d" module)" --arg f "$(field "$d" file)" \
           --arg k "$(field "$d" keypath)" --arg kind "$(field "$d" kind)" \
           --arg c "$(field "$d" class)" --arg r "$(field "$d" reason)" \
           --arg s "$(field "$d" sink)" --arg b "$(field "$d" blocked)" \
           --arg mv "$(if [ "$(field "$d" class)" = secret ]; then printf ''; else field "$d" machine; fi)" \
           --arg rv "$(field "$d" repo)" \
      '{id:($id|tonumber),platform:$t,module:$m,file:$f,key:$k,kind:$kind,
        classification:$c,reason:$r,sink:(if $s=="" then null else $s end),
        blocked:(if $b=="" then null else $b end),
        machine_value:(if $mv=="" then null else $mv end),
        repo_value:(if $rv=="absent" then null else $rv end)}' | tr -d '\n'
  done
  printf '],"summary":{"offerable":%s,"portable":%s,"machine_local":%s,"secret":%s,"third_party":%s,"unknown":%s}}\n' \
    "$(count_offerable)" "$(count_class portable)" "$(count_class machine-local)" \
    "$(count_class secret)" "$(count_class third-party)" "$(count_class unknown)"
}

# ---------------------------------------------------------------------------
# The review loop
# ---------------------------------------------------------------------------
ADOPT_ALL=""
QUIT=""
N_ADOPTED=0
N_DECLINED=0
ADOPTED_IDS=""
TOUCHED_SINKS=""

adopt_requested() {
  local id="$1" want
  [ -n "$OPT_ADOPT" ] || return 1
  [ "$OPT_ADOPT" = all ] && return 0
  for want in $(printf '%s' "$OPT_ADOPT" | tr ',' ' '); do
    [ "$want" = "$id" ] && return 0
  done
  return 1
}

# show_hunk <hunk-dir> — one hunk, as a diff. Repo on the left, machine on the
# right, because that is the direction the change travels.
show_hunk() {
  local d="$1"
  out ""
  out "──────────────────────────────────────────────────────────────"
  out "  [$(field "$d" id)] $(field "$d" display) · $(setup_tilde "$(field "$d" file)")"
  out "  key   $(field "$d" keypath)   ($(field "$d" kind))"
  out "  class $(class_colour "$(field "$d" class)")$(field "$d" class)${SETUP_C_OFF} — $(field "$d" reason)"
  out "  lands in $(field "$d" sink)"
  out "──────────────────────────────────────────────────────────────"
  if [ "$(field "$d" repo)" = absent ]; then
    out "  ${SETUP_C_DIM}- (the repo asserts nothing here)${SETUP_C_OFF}"
  else
    out "  ${SETUP_C_RED}- $(field "$d" repo)${SETUP_C_OFF}"
  fi
  out "  ${SETUP_C_GREEN}+ $(field "$d" machine)${SETUP_C_OFF}"
}

# show_context <hunk-dir> — the `s` answer. For JSON, the whole parent object as
# it stands on the machine; for a rules line, the surrounding lines. Enough to
# answer "what else is in here" without leaving the loop.
show_context() {
  local d="$1" file key
  file="$(field "$d" file)"; key="$(field "$d" keypath)"
  out ""
  out "  ${SETUP_C_DIM}context from $(setup_tilde "$file")${SETUP_C_OFF}"
  case "$file" in
    *.json)
      setup_json_read "$file" | capture_strip_meta \
        | jq --argjson p "$(field "$d" pathjson)" 'getpath($p[0:-1]) // getpath($p)' 2>/dev/null \
        | head -30 | sed 's/^/      /' | while IFS= read -r l; do out "$l"; done ;;
    *)
      grep -nF -- "$(printf '%s' "$(field "$d" machine)" | jq -r . 2>/dev/null || field "$d" machine)" "$file" 2>/dev/null \
        | head -5 | sed 's/^/      /' | while IFS= read -r l; do out "$l"; done ;;
  esac
}

# ask_hunk — [y/N/a/q/s]. Default is skip, always. `s` re-asks rather than
# consuming the answer, so showing more context is never a decision.
# Returns: 0 adopt, 1 skip, 2 quit.
ask_hunk() {
  local d="$1" ans
  [ -n "$ADOPT_ALL" ] && return 0
  adopt_requested "$(field "$d" id)" && return 0
  [ -n "$OPT_ADOPT" ] && return 1
  while :; do
    ans="$(setup_ask 'Adopt into the repo? [y/N/a/q/s] ' n)"
    case "$(capture_decide "$ans")" in
      adopt)     return 0 ;;
      adopt-all) ADOPT_ALL=1; return 0 ;;
      quit)      return 2 ;;
      show)      show_context "$d" ;;   # re-asks: seeing more is not a decision
      *)         return 1 ;;
    esac
  done
}

# stage_hunk <hunk-dir> — write the adopted value into the CANONICAL SOURCE.
stage_hunk() {
  local d="$1" sink abs cap
  sink="$(field "$d" sink)"
  abs="${SETUP_REPO_ROOT}/${sink}"
  case "$sink" in
    *.json) capture_stage_json "$abs" "$(field "$d" pathjson)" "$(field "$d" kind)" "$(field "$d" machine)" ;;
    *)      capture_stage_md   "$abs" "$(field "$d" keypath)" \
              "$(printf '%s' "$(field "$d" machine)" | jq -r . 2>/dev/null || field "$d" machine)" ;;
  esac
  case " $TOUCHED_SINKS " in *" $sink "*) : ;; *) TOUCHED_SINKS="$TOUCHED_SINKS $sink" ;; esac
  ADOPTED_IDS="$ADOPTED_IDS $(field "$d" id)"
  N_ADOPTED=$((N_ADOPTED + 1))
  # Cite the capability registry, when the platform that produced this hunk
  # declares one for the sink, in the propagation report below.
  capture_load_target "$(field "$d" target)" >/dev/null 2>&1 || true
  cap="$(printf '%s' "$CAPTURE_SINK_CAPS" | awk -F'\t' -v s="$sink" '$1 == s { print $2; exit }')"
  [ -n "$cap" ] && CAPTURE_ADOPTED_CAP="$cap"
  return 0
}

review_loop() {
  local d
  for d in "$CAPTURE_WORK"/hunks/*; do
    [ -d "$d" ] || continue
    [ -n "$QUIT" ] && break
    if ! offerable "$d"; then continue; fi
    show_hunk "$d"
    rc=0; ask_hunk "$d" || rc=$?
    case $rc in
      0) stage_hunk "$d"
         out "  ${SETUP_C_GREEN}adopted${SETUP_C_OFF} -> $(field "$d" sink)" ;;
      1) N_DECLINED=$((N_DECLINED + 1))
         out "  ${SETUP_C_DIM}skipped${SETUP_C_OFF}" ;;
      2) QUIT=1 ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Propagation — the step that makes capture worth building
# ---------------------------------------------------------------------------
# A hunk adopted once must reach all five targets. It does so by construction:
# nothing is written to a platform file, only to the canonical source the
# renderers read. This report re-runs those renderers and shows what changed on
# every platform, so the blast radius is visible BEFORE the PR exists.
#
# A platform whose render did not move is named too, with the registry's word
# for why. Silence would be indistinguishable from "we forgot".
BEFORE_DIR=""
snapshot_before() {
  BEFORE_DIR="${CAPTURE_WORK}/render-before"
  capture_render_snapshot "$BEFORE_DIR"
}

report_propagation() {
  local after="${CAPTURE_WORK}/render-after" s
  out ""
  out "${SETUP_C_BOLD}Propagation — what the adopted hunks now render to${SETUP_C_OFF}"
  out ""
  out "  canonical files written:"
  for s in $TOUCHED_SINKS; do out "    $s"; done
  capture_render_snapshot "$after"
  capture_propagation_report "$BEFORE_DIR" "$after" | while IFS= read -r l; do out "$l"; done
}

# ---------------------------------------------------------------------------
# Delivery — branch, one commit per platform, generated PR body. NEVER merges.
# ---------------------------------------------------------------------------
capture_slug() {
  local s
  s="$(printf '%s' "${1:-config}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')"
  printf '%s' "${s:-config}" | cut -c1-40
}

# THE ADOPTION STATE FILE — why `deliver` is not just a second `detect`
#   `review` and `deliver` are separate processes, and by the time `deliver`
#   runs, the machine differences it would re-detect are gone: the adopted ones
#   are in the repo now, so a fresh scan reports them as "already asserted" and
#   the PR body comes out empty, with every adopted hunk listed under "not
#   captured". So `review` records what it decided. It writes into `.git/`,
#   which is never committed and is scoped to this checkout.
capture_state_file() { printf '%s/.git/capture-state.json' "$SETUP_REPO_ROOT"; }

write_state() {
  local d id f
  f="$(capture_state_file)"
  [ -d "${SETUP_REPO_ROOT}/.git" ] || return 0
  {
    printf '{"generated":"%s","adopted":[' "$(setup_utc)"
    first=1
    for d in "$CAPTURE_WORK"/hunks/*; do
      [ -d "$d" ] || continue
      id="$(field "$d" id)"
      case " $ADOPTED_IDS " in *" $id "*) : ;; *) continue ;; esac
      [ "$first" -eq 1 ] || printf ','
      first=0
      jq -nc --arg id "$id" --arg k "$(field "$d" keypath)" --arg f "$(field "$d" file)" \
             --arg disp "$(field "$d" display)" --arg p "$(field "$d" target)" \
             --arg c "$(field "$d" class)" --arg s "$(field "$d" sink)" \
        '{id:$id,key:$k,file:$f,display:$disp,platform:$p,classification:$c,sink:$s}' | tr -d '\n'
    done
    printf '],"skipped":['
    first=1
    for d in "$CAPTURE_WORK"/hunks/*; do
      [ -d "$d" ] || continue
      id="$(field "$d" id)"
      case " $ADOPTED_IDS " in *" $id "*) continue ;; esac
      [ "$first" -eq 1 ] || printf ','
      first=0
      # The value is NOT recorded for a secret. A state file on disk that holds
      # the credential would undo the refusal it is recording.
      jq -nc --arg k "$(field "$d" keypath)" --arg c "$(field "$d" class)" \
             --arg r "$(field "$d" reason)" --arg b "$(field "$d" blocked)" \
        '{key:$k,classification:$c,reason:$r,blocked:(if $b=="" then null else $b end)}' | tr -d '\n'
    done
    printf '],"sinks":['
    first=1
    for s in $TOUCHED_SINKS; do
      [ "$first" -eq 1 ] || printf ','
      first=0
      printf '"%s"' "$s"
    done
    printf ']}\n'
  } > "$f"
}

# pr_body <file> — written from the adoption state, not from a template. It
# names what was captured, the machine file it came from, where it now renders,
# and what was skipped AND WHY. The "why" is the half that makes the PR
# reviewable: a reviewer has to be able to see that the machine paths and the
# credential were refused on purpose rather than missed.
pr_body() {
  local outf="$1" st
  st="$(capture_state_file)"
  {
    printf '## Captured from a machine\n\n'
    printf 'Generated by `scripts/capture-config.sh review`. Nothing here was adopted\n'
    printf 'without an explicit answer at the prompt.\n\n'
    printf '| key | from | classification | lands in |\n|---|---|---|---|\n'
    jq -r '.adopted[] | "| `\(.key)` | \(.file) (\(.display)) | \(.classification) | `\(.sink)` |"' "$st" \
      | sed "s|${HOME}|~|g"
    printf '\n### Renders to\n\n'
    printf 'Adopted values were written to the canonical source only. `scripts/setup.sh apply`\n'
    printf 'renders them onto every detected platform from there:\n\n'
    jq -r '.sinks[]' "$st" | while IFS= read -r d; do
      case "$d" in
        core/global-rules.md)
          printf -- '- `core/global-rules.md` -> Codex `AGENTS.md`, Gemini `GEMINI.md`, Cursor `.mdc`, OpenCode `AGENTS.md`\n' ;;
        platforms/claude/*)
          printf -- '- `%s` -> Claude Code `settings.json`. No other platform expresses per-tool permission policy; `core/capabilities/platforms.json` records no mechanism for it.\n' "$d" ;;
        *) printf -- '- `%s` -> the platform it names\n' "$d" ;;
      esac
    done
    printf '\n### Deliberately not captured\n\n'
    jq -r '.skipped[] |
      if .classification == "secret" then
        "- `\(.key)` — **refused**: \(.reason). The value is not in this PR and was never printed."
      elif .blocked != null then
        "- `\(.key)` — blocked: \(.blocked)"
      else
        "- `\(.key)` — \(.classification): \(.reason)"
      end' "$st"
    printf '\n---\nOpened by `capture-config`. Drive it with `/pr-dev`. It does not merge itself.\n'
  } > "$outf"
}

deliver() {
  local branch slug body changed platform dir msg
  cd "$SETUP_REPO_ROOT"
  changed="$(git status --porcelain -- core platforms 2>/dev/null | awk '{print $2}')"
  if [ -z "$changed" ]; then
    out "Nothing staged to deliver. Run 'review' and adopt at least one hunk first."
    return 0
  fi
  if [ ! -f "$(capture_state_file)" ]; then
    setup_err "no adoption record at $(setup_tilde "$(capture_state_file)")."
    printf 'Run `bash scripts/capture-config.sh review` first — the PR body is written\nfrom what that run decided, not from a re-scan.\n' >&2
    return 1
  fi

  # BLOCKING GATE. A capture PR that does not validate is worse than no PR: it
  # looks reviewed and is not.
  out ""
  out "Running 'make validate' before touching git..."
  if ! make -C "$SETUP_REPO_ROOT" validate >"${CAPTURE_WORK}/validate.log" 2>&1; then
    setup_err "make validate failed — refusing to open a PR."
    tail -30 "${CAPTURE_WORK}/validate.log" >&2
    return 1
  fi
  out "  ${SETUP_C_GREEN}ok${SETUP_C_OFF}  make validate passed"

  slug="$(capture_slug "$(printf '%s' "$changed" | head -1 | xargs -n1 basename 2>/dev/null | head -1)")"
  branch="capture/$(date -u +%Y%m%d)-${slug}"
  git checkout -q -b "$branch" 2>/dev/null || git checkout -q "$branch"

  # One commit per platform touched: a reviewer reading the log sees which
  # platform's hand-edit produced which canonical change, which is the question
  # a capture PR is actually reviewed on.
  for dir in $(printf '%s\n' "$changed" | sed -n 's|^\(platforms/[^/]*\)/.*|\1|p; s|^\(core\)/.*|\1|p' | sort -u); do
    platform="$(basename "$dir")"
    if [ "$platform" = core ]; then
      msg="feat(capture): adopt hand-edited rules into the canonical source"
    else
      msg="feat(capture): adopt hand-edited ${platform} config"
    fi
    git add -- "$dir"
    git -c commit.gpgsign=false commit -q -m "$msg" || true
  done

  body="${SETUP_REPO_ROOT}/.git/CAPTURE_PR_BODY.md"
  pr_body "$body"
  out ""
  out "Branch ${SETUP_C_BOLD}${branch}${SETUP_C_OFF} created."
  git log --oneline -5 | sed 's/^/    /' | while IFS= read -r l; do out "$l"; done
  out "PR body written to $body"
  out ""
  out "  Open it:  gh pr create --base master --head $branch --title 'feat(capture): adopt hand-edited config' --body-file $body"
  out "  Drive it: /pr-dev"
  out ""
  out "  This command does not push, does not open the PR, and never merges."
}

# ---------------------------------------------------------------------------
main() {
  build_change_set

  if [ -n "$OPT_JSON" ]; then
    print_change_set
    print_json
    exit 0
  fi

  print_change_set

  if [ "$VERB" = detect ]; then
    out ""
    out "Nothing has been written. Re-run with 'review' to go through the offerable hunks."
    exit 0
  fi

  if [ "$VERB" = deliver ]; then
    deliver
    exit $?
  fi

  if [ "$(count_offerable)" -eq 0 ]; then
    out ""
    out "Nothing to offer. Every difference is machine-local, third-party, refused or blocked."
    exit 0
  fi

  # THE STDIN RESOLUTION, in one place. With no terminal and no explicit --adopt
  # list there is no way to ask, and capture never answers on the user's behalf:
  # the change set above IS the result. This is why capture is safe to invoke
  # from a hook or a CI job.
  if ! setup_can_prompt && [ -z "$OPT_ADOPT" ]; then
    setup_note "no TTY — cannot prompt. The change set above is the whole result; nothing was adopted."
    setup_note "to adopt without a terminal, name the hunks explicitly: --adopt 3,7"
    exit 0
  fi

  snapshot_before
  review_loop

  if [ "$N_ADOPTED" -eq 0 ]; then
    out ""
    out "Nothing adopted. The repo is untouched."
    exit 0
  fi

  write_state
  report_propagation

  out ""
  out "Done. $N_ADOPTED adopted, $N_DECLINED declined."
  out ""
  out "  Review:   git diff"
  out "  Deliver:  bash scripts/capture-config.sh deliver"
  out ""
  out "  Nothing has been committed and nothing has been pushed."
  exit 0
}

main
