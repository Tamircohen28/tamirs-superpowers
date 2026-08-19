#!/usr/bin/env bash
# capture-common.sh — shared helpers for scripts/capture-config.sh.
#
# Sourced, never executed.
#
# WHAT THIS IS
#   `setup.sh` renders repo -> machine. `capture-config.sh` proposes the inverse:
#   machine -> repo. Render only ever writes files this repo authored, so it needs
#   no judgement. Capture READS FILES A PERSON EDITED, so every value that crosses
#   the boundary is classified, scanned and shown before it can land — and it
#   lands as a reviewed PR, never as a silent commit.
#
# THE ONE DIFFER
#   Capture does not implement its own idea of "what the repo says". It calls the
#   SAME module renderers `setup.sh` calls — `<target>_<module>_render` from
#   scripts/lib/setup-<target>.sh — and the same normalisation primitives from
#   scripts/lib/setup-common.sh. The only thing capture changes is the ARGUMENT:
#
#       setup:    render(<the machine file>)   -> "what the machine should become"
#       capture:  render(<a file that is not there>) -> "what the repo asserts, alone"
#
#   That second call is the reversal. Because `render` deep-merges the repo onto
#   whatever it is given, render(machine) always CONTAINS the machine's own keys —
#   diffing against it would report nothing. Rendering against an absent file
#   strips the machine out, and what remains in the machine file but not in that
#   render is exactly the set of things a person added by hand.
#
#   tests/test-capture.sh pins the agreement directly: for every module, capture's
#   "differs / identical" verdict is asserted equal to `setup.sh plan --json`'s
#   status for the same path. The two directions cannot drift apart silently.
#
# PORTABILITY CONTRACT — same as setup-common.sh
#   bash 3.2: no associative arrays, no `mapfile`, no `${var^^}`, no `declare -A`.
#   No `timeout(1)`. jq required. shellcheck -S warning --exclude SC2034 clean.
#
# STDIN CONTRACT
#   Nothing here reads stdin. Prompts go through setup_ask, which reads /dev/tty.

# shellcheck shell=bash

if [ -n "${CAPTURE_COMMON_LOADED:-}" ]; then return 0; fi
CAPTURE_COMMON_LOADED=1

# The classification vocabulary, in the order capture_classify tries them. The
# order is the safety property: `secret` and `third-party` are decided before
# anything can be called portable, and the absolute-path test runs before the
# portable allowlist so an allowlisted key with a machine path is still demoted.
CAPTURE_CLASSES="secret third-party machine-local portable unknown"

# Where a user keeps additions to the two lists capture cannot know for them.
# Both are optional; absence is not an error.
CAPTURE_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}/tamirs-superpowers"
CAPTURE_THIRD_PARTY_FILE="${CAPTURE_THIRD_PARTY_FILE:-${CAPTURE_CONFIG_HOME}/third-party-owners.txt}"
CAPTURE_SCAN_PATTERNS_FILE="${CAPTURE_SCAN_PATTERNS_FILE:-${CAPTURE_CONFIG_HOME}/scan-patterns.txt}"

# ---------------------------------------------------------------------------
# Target registry — platforms/<name>/capture.conf, sourced exactly the way
# setup.sh sources platforms/<name>/setup.conf. Reset first, so a conf that
# forgets a field fails loudly instead of inheriting the previous target's.
# ---------------------------------------------------------------------------
capture_load_target() {
  local name="$1" conf
  CAPTURE_NAME=""; CAPTURE_DISPLAY=""; CAPTURE_REGISTRY_KEY=""
  CAPTURE_MODULES=""; CAPTURE_MACHINE_LOCAL=""; CAPTURE_PORTABLE=""
  CAPTURE_THIRD_PARTY_KEYS=""; CAPTURE_SINKS=""; CAPTURE_SINK_CAPS=""
  conf="${SETUP_REPO_ROOT}/platforms/${name}/capture.conf"
  [ -f "$conf" ] || { setup_warn "no capture.conf for target '$name' — skipping"; return 1; }
  # shellcheck source=/dev/null
  . "$conf"
  [ -n "$CAPTURE_NAME" ] || { setup_warn "$conf declares no CAPTURE_NAME — skipping"; return 1; }
  return 0
}

# capture_match_any <subject> <newline-separated-glob-list>
# Unquoted `$pat` in the case is deliberate — these ARE globs.
capture_match_any() {
  local subject="$1" list="$2" pat
  [ -n "$list" ] || return 1
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    case "$pat" in '#'*) continue ;; esac
    # shellcheck disable=SC2254
    case "$subject" in $pat) return 0 ;; esac
  done <<CAPTURE_MATCH_EOF
$list
CAPTURE_MATCH_EOF
  return 1
}

# ---------------------------------------------------------------------------
# Gate 1 — secrets. REFUSED, never offered, and the value is never printed.
# ---------------------------------------------------------------------------
# Shapes, not entropy. A value this repo has ever been able to name is a value
# that must not travel; an unrecognised high-entropy string is caught by the
# key-name half of the rule below instead.
CAPTURE_TOKEN_SHAPE='(ghp_|gho_|ghs_|ghu_|ghr_|github_pat_)[A-Za-z0-9_]{16,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|ey[A-Za-z0-9_-]{10,}\.ey[A-Za-z0-9_-]{10,}\.'
CAPTURE_SECRET_KEY='(^|[._-])(secret|token|password|passwd|api_?key|access_?key|client_?secret|credential|private_?key|auth)([._-]|$)'

# capture_is_env_ref <value> — `${FOO}` / `$FOO` and nothing else. An env
# reference is the NAME of a secret, which is portable; the value is not.
capture_is_env_ref() {
  printf '%s' "$1" | grep -qE '^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$'
}

# capture_secret_reason <keypath> <value> — prints a reason, or nothing.
# Never echoes the value back: a reason that quotes the token defeats the gate.
capture_secret_reason() {
  local key="$1" val="$2" lower
  if printf '%s' "$val" | grep -qE "$CAPTURE_TOKEN_SHAPE"; then
    printf 'value is token-shaped'
    return 0
  fi
  lower="$(setup_lower "$key")"
  if printf '%s' "$lower" | grep -qE "$CAPTURE_SECRET_KEY"; then
    # A name is not a value: `${GITHUB_TOKEN}` is exactly what we DO want in the
    # repo, and an empty string carries nothing.
    if capture_is_env_ref "$val"; then return 1; fi
    if [ -z "$val" ] || [ "$val" = '""' ]; then return 1; fi
    printf 'key name denotes a credential'
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Gate 2 — third-party wiring. Named by STRUCTURE, not by vendor.
# ---------------------------------------------------------------------------
# A hardcoded vendor list would be wrong twice: it goes stale the moment the user
# installs something else, and this repo's own static scan refuses to ship a
# foreign orchestrator's name in an executable or a manifest. So ownership is
# derived from the value: a command path, a plugin's `@marketplace` suffix or a
# hook script that does not live in this plugin's cache belongs to whoever wrote
# it, and capture names that owner from the value itself.
CAPTURE_OURS='tamirs-superpowers|tamirs-marketplace|tamirs-plugins'

# capture_owner_of <value> — the owning token, or nothing.
capture_owner_of() {
  local val="$1" owner=""
  # `name@marketplace` — the marketplace owns the entry.
  owner="$(printf '%s' "$val" | sed -n 's/.*@\([A-Za-z0-9][A-Za-z0-9._-]*\).*/\1/p' | head -1)"
  if [ -n "$owner" ]; then printf '%s' "$owner"; return 0; fi
  # A path under a per-tool config or cache directory: the directory after the
  # dotdir is the tool.
  owner="$(printf '%s' "$val" | sed -n 's|.*/\.\([A-Za-z0-9][A-Za-z0-9._-]*\)/.*|\1|p' | head -1)"
  if [ -n "$owner" ]; then printf '%s' "$owner"; return 0; fi
  return 1
}

# capture_third_party_reason <platform> <keypath> <value>
capture_third_party_reason() {
  local plat="$1" key="$2" val="$3" owner line pat who
  # (a) per-platform key paths the conf declares foreign-owned.
  if capture_match_any "$key" "$CAPTURE_THIRD_PARTY_KEYS"; then
    printf 'key path is declared foreign-owned for %s' "$plat"
    return 0
  fi
  # (b) the user's own owner list: "<regex>\t<owner>".
  if [ -f "$CAPTURE_THIRD_PARTY_FILE" ]; then
    while IFS="$(printf '\t')" read -r pat who; do
      [ -n "$pat" ] || continue
      case "$pat" in '#'*) continue ;; esac
      if printf '%s\t%s' "$key" "$val" | grep -qE "$pat"; then
        printf 'owned by %s (declared in %s)' "${who:-a third party}" "$(setup_tilde "$CAPTURE_THIRD_PARTY_FILE")"
        return 0
      fi
    done < "$CAPTURE_THIRD_PARTY_FILE"
  fi
  # (c) structural: a marketplace or tool token in the value that is not ours.
  case "$key" in
    enabledPlugins*|*hooks*|*command*|*plugin*|extraKnownMarketplaces*|*mcp*|*Servers*)
      # Key AND value: `enabledPlugins."x@some-marketplace"` carries its owner in
      # the key and a bare `true` as the value. Reading only the value would call
      # another marketplace's plugin portable.
      if owner="$(capture_owner_of "${key} ${val}")"; then
        printf '%s' "$owner" | grep -qE "$CAPTURE_OURS" && return 1
        printf 'owned by %s, not by this repo' "$owner"
        return 0
      fi ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# Gate 3 — machine-local. Absolute home paths first: this is the exact route by
# which a third-party or employer path would otherwise arrive in the repo.
# ---------------------------------------------------------------------------
CAPTURE_HOMEPATH='(^|[^A-Za-z0-9._-])/(Users|home)/[A-Za-z0-9._-]+'
CAPTURE_PATH_PLACEHOLDER='/(Users|home)/(you|username|your-name|<[A-Za-z_]+>|\$USER|\$\{USER\})'

# capture_abs_path_reason <keypath> <value> — split out from the key-path list
# below because it is tested EARLIER than third-party ownership. A value holding
# this machine's home directory is machine-local whoever wrote it; deciding
# ownership first would have labelled `~/.claude/plugins/marketplaces/x` as
# third-party wiring and buried the fact that it is a path that exists nowhere
# else. Absolute paths are the exact route by which a foreign reference would
# otherwise reach the repo, so this gate goes first among the non-secret ones.
capture_abs_path_reason() {
  local val="$2"
  if printf '%s' "$val" | grep -qE "$CAPTURE_HOMEPATH" \
     && ! printf '%s' "$val" | grep -qE "$CAPTURE_PATH_PLACEHOLDER"; then
    printf 'holds an absolute home path — parameterise it or keep it local'
    return 0
  fi
  return 1
}

# capture_machine_local_reason <keypath> <value>
capture_machine_local_reason() {
  local key="$1"
  if capture_match_any "$key" "$CAPTURE_MACHINE_LOCAL"; then
    printf 'key path is machine state, not policy'
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# capture_classify <platform> <keypath> <value> [kind]  ->  "<class>\t<reason>"
#
# `kind` is the hunk shape: `scalar`, `array-item` or `line`. A `line` is a
# markdown rule captured from a rules file, and it is portable by construction —
# core/global-rules.md exists precisely so that one prose rule is true on every
# platform, and there is no key path to look up in a portable list. It still
# passes through every gate above it: a rule naming a credential, a home
# directory or an internal host is refused exactly as a JSON value would be.
# ---------------------------------------------------------------------------
capture_classify() {
  local plat="$1" key="$2" val="$3" kind="${4:-scalar}" why
  if why="$(capture_secret_reason "$key" "$val")"; then
    printf 'secret\t%s' "$why"; return 0
  fi
  if why="$(capture_abs_path_reason "$key" "$val")"; then
    printf 'machine-local\t%s' "$why"; return 0
  fi
  if why="$(capture_third_party_reason "$plat" "$key" "$val")"; then
    printf 'third-party\t%s' "$why"; return 0
  fi
  if why="$(capture_machine_local_reason "$key" "$val")"; then
    printf 'machine-local\t%s' "$why"; return 0
  fi
  if [ "$kind" = line ]; then
    printf 'portable\ta rules line — canonical prose, true on every platform'; return 0
  fi
  if capture_match_any "$key" "$CAPTURE_PORTABLE"; then
    printf 'portable\tdeclared portable for %s' "$plat"; return 0
  fi
  printf 'unknown\tno rule covers this key path'
}

# ---------------------------------------------------------------------------
# Gate 4 — the IP scan, per hunk.
# ---------------------------------------------------------------------------
# The repo already owns exactly one scanner: skills/repo/_contract/scripts/ip-scan.sh.
# Capture does not reimplement it — it writes ONE hunk into an otherwise empty
# directory and runs that scanner over it. Scanning per hunk is the whole point:
# a hit blocks the hunk that carries it, and every other hunk in the run is
# still offered.
#
# The scanner's built-in patterns are shape-based (credential assignments,
# self-hosted runners, localhost URLs). The employer / internal-hostname half is
# necessarily site-specific — a public repo cannot ship a private employer's
# name — so it comes from two places, both optional:
#   * $CAPTURE_SCAN_PATTERNS_FILE (default ~/.config/tamirs-superpowers/scan-patterns.txt)
#   * $TAMIRS_EMPLOYER_PATTERN, one extended regex, for a one-off run
# plus the generic internal-hostname shapes below, which need no private name.
#
# The single-label forms `.local`, `.lan`, `.prod` and `.staging` are NOT here.
# They were, and they fired on `extraKnownMarketplaces.local-thing.source` — a
# dotted KEY PATH, not a hostname. A scanner that cries wolf on ordinary key
# names is a scanner people learn to answer `y` through, which is the failure
# mode this gate exists to prevent. Every shape below needs a hostname context:
# an internal-only suffix, or a URL, or a known internal-registry product name.
CAPTURE_INTERNAL_SHAPES='\b[A-Za-z0-9][A-Za-z0-9-]*\.(corp|internal|intranet)\b
\b[A-Za-z0-9][A-Za-z0-9-]*\.(corp|internal|intra)\.[A-Za-z]{2,}\b
https?://[A-Za-z0-9.-]*\.(corp|internal|intra|intranet|lan)[:/]
\b(artifactory|nexus|jfrog)\.[A-Za-z0-9.-]+\b'

capture_ip_scanner() { printf '%s/skills/repo/_contract/scripts/ip-scan.sh' "$SETUP_REPO_ROOT"; }

# capture_scan_patterns_file — the merged pattern file for one run. Built once
# into $CAPTURE_WORK and reused, so the scanner is configured identically for
# every hunk.
capture_scan_patterns_file() {
  local f="${CAPTURE_WORK}/scan-patterns.txt"
  if [ ! -f "$f" ]; then
    {
      printf '%s\n' "$CAPTURE_INTERNAL_SHAPES"
      [ -n "${TAMIRS_EMPLOYER_PATTERN:-}" ] && printf '%s\n' "$TAMIRS_EMPLOYER_PATTERN"
      [ -f "$CAPTURE_SCAN_PATTERNS_FILE" ] && cat "$CAPTURE_SCAN_PATTERNS_FILE"
    } > "$f"
  fi
  printf '%s' "$f"
}

# capture_ip_scan <keypath> <value> — 0 clean, 1 blocked. On a block the reason
# is printed on stdout. Both the key path and the value are scanned: an internal
# hostname is as likely to be the key as the value.
capture_ip_scan() {
  local key="$1" val="$2" dir scanner out
  scanner="$(capture_ip_scanner)"
  [ -x "$scanner" ] || [ -f "$scanner" ] || { return 0; }
  dir="${CAPTURE_WORK}/scan.$$"
  rm -rf "$dir"; mkdir -p "$dir"
  # `.md` and `.json` are both in the scanner's include list; .txt keeps the
  # content verbatim with no risk of a JSON escape hiding a match.
  printf '%s\n%s\n' "$key" "$val" > "${dir}/hunk.txt"
  out="$(bash "$scanner" "$dir" "$(capture_scan_patterns_file)" 2>/dev/null || true)"
  rm -rf "$dir"
  case "$out" in
    *"RESULT: CLEAN"*) return 0 ;;
    *) printf 'IP scan hit: %s' \
         "$(printf '%s' "$out" | grep -E '^### Pattern' | head -1 | sed 's/^### Pattern: //; s/  ([0-9]* occurrence(s))$//')"
       return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# `_`-prefixed metadata must never round-trip
# ---------------------------------------------------------------------------
# The repo's JSON fragments carry `_comment` / `_tally` to explain themselves to
# the next reader. setup.sh strips them on the way out (rules_json_fragment,
# claude_settings_fragment). If capture did not strip them on the way back in,
# a machine that had somehow acquired one would reimport it as data and it would
# be written into the fragment as a real setting. Same rule, both directions.
CAPTURE_JQ_STRIPMETA='
def stripmeta:
  if type == "object" then with_entries(select(.key | startswith("_") | not)) | map_values(stripmeta)
  elif type == "array" then map(stripmeta)
  else . end;
'
capture_strip_meta() { jq "${CAPTURE_JQ_STRIPMETA} stripmeta"; }

# ---------------------------------------------------------------------------
# The reversed differ
# ---------------------------------------------------------------------------
# capture_json_hunks <machine-json> <repo-json>
#   Emits TSV: kind \t keypath \t path-json \t machine-value-json \t repo-value-json
#   kind is `scalar` or `array-item`; repo value is the literal string `absent`
#   when the repo asserts nothing at that path.
#
# Array elements are compared ELEMENT BY ELEMENT rather than array against
# array. A permissions.allow list that the user appended one rule to must offer
# that one rule, not the whole fifty-entry list as a single take-it-or-leave-it.
capture_json_hunks() {
  jq -n -r --slurpfile M "$1" --slurpfile R "$2" '
    ($M[0] // {}) as $m | ($R[0] // {}) as $r
    | ($m | [paths(scalars)])[]
    | . as $p
    | ([$p[] | select(type == "string")]) as $par
    | ($par | join(".")) as $key
    | ($m | getpath($p)) as $mv
    | (if ($p | last | type) == "number" then "array-item" else "scalar" end) as $kind
    | if $kind == "array-item" then
        ((try ($r | getpath($par)) catch null)) as $ra
        | if ($ra | type) == "array" and ($ra | index($mv)) != null then empty
          else [$kind, $key, ($par | tojson), ($mv | tojson), "absent"] end
      else
        ((try ($r | getpath($p)) catch null)) as $rv
        | if $rv == $mv then empty
          elif $rv == null then [$kind, $key, ($par | tojson), ($mv | tojson), "absent"]
          else [$kind, $key, ($par | tojson), ($mv | tojson), ($rv | tojson)] end
      end
    | @tsv'
}

# capture_md_hunks <machine-md> <repo-md>
#   Emits TSV: kind \t heading \t "" \t line-as-json \t absent
#   The value is JSON-encoded exactly as capture_json_hunks encodes its own, so
#   every consumer downstream decodes one way and only one way.
#   One hunk per machine-only line, attributed to the markdown heading it sits
#   under. Content inside this installer's own marker block is skipped: that
#   block is a build artifact, and re-capturing it would loop the renderer's
#   output back into its own input.
capture_md_hunks() {
  local machine="$1" repo="$2"
  [ -f "$machine" ] || return 0
  awk -v mopen="${SETUP_MD_OPEN:-<!-- >>> tamirs-superpowers >>> -->}" \
      -v mclose="${SETUP_MD_CLOSE:-<!-- <<< tamirs-superpowers <<< -->}" \
      -v repofile="$repo" '
    BEGIN {
      while ((getline line < repofile) > 0) {
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        if (line != "") seen[line] = 1
      }
      close(repofile)
      heading = "body"
    }
    $0 == mopen { inblock = 1; next }
    $0 == mclose { inblock = 0; next }
    inblock { next }
    /^<!--/ { incomment = 1 }
    incomment { if ($0 ~ /-->/) incomment = 0; next }
    {
      line = $0
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      if (line == "") next
      if (line ~ /^#+ /) { heading = line; sub(/^#+ /, "", heading); next }
      if (line in seen) next
      printf "line\t%s\t\t%s\tabsent\n", heading, jsonstr(line)
    }
    function jsonstr(s,   t) {
      t = s
      gsub(/\\/, "\\\\", t)
      gsub(/"/, "\\\"", t)
      gsub(/\t/, "\\t", t)
      return "\"" t "\""
    }
  ' "$machine"
}

# ---------------------------------------------------------------------------
# Sinks — an adopted hunk lands in the CANONICAL SOURCE, never in a platform file
# ---------------------------------------------------------------------------
# Writing a captured Claude permission straight into ~/.claude/settings.json's
# repo twin would make the repo a second copy of the machine. It goes into
# platforms/claude/settings.d/ instead, which is the thing `setup.sh` renders
# FROM — so the next `apply` on any machine reproduces it. A captured rule goes
# to core/global-rules.md, which all five renderers read.
#
# CAPTURE_SINKS lines are "<module>\t<keypath-glob>\t<repo-relative-sink>",
# first match wins. Declared per platform in platforms/<t>/capture.conf.
capture_sink_for() {
  local mod="$1" key="$2" m g sink
  while IFS="$(printf '\t')" read -r m g sink; do
    [ -n "$m" ] || continue
    case "$m" in '#'*) continue ;; esac
    [ "$m" = "$mod" ] || [ "$m" = '*' ] || continue
    # shellcheck disable=SC2254
    case "$key" in $g) printf '%s' "$sink"; return 0 ;; esac
  done <<CAPTURE_SINK_EOF
$CAPTURE_SINKS
CAPTURE_SINK_EOF
  return 1
}

# capture_stage_json <sink-abs> <path-json-array> <kind> <value-json>
# Scalars are set at the path; array items are APPENDED if not already present,
# which preserves the ordering of a hand-curated list like permissions.allow.
capture_stage_json() {
  local sink="$1" pathjson="$2" kind="$3" value="$4" tmp
  mkdir -p "$(dirname "$sink")"
  [ -f "$sink" ] || printf '{}\n' > "$sink"
  tmp="${sink}.capture-tmp.$$"
  if [ "$kind" = array-item ]; then
    jq --argjson p "$pathjson" --argjson v "$value" '
      setpath($p; ((getpath($p) // []) as $a
                   | if ($a | index($v)) != null then $a else $a + [$v] end))' \
      "$sink" > "$tmp"
  else
    jq --argjson p "$pathjson" --argjson v "$value" 'setpath($p; $v)' "$sink" > "$tmp"
  fi
  mv "$tmp" "$sink"
}

# capture_stage_md <sink-abs> <heading> <line>
# Appended under one clearly-labelled section rather than guessed into the middle
# of the user's prose. A person reviewing the PR can move it; a script guessing
# where a rule belongs cannot be reviewed at all.
CAPTURE_MD_SECTION='## Captured from a machine'
capture_stage_md() {
  local sink="$1" heading="$2" line="$3"
  mkdir -p "$(dirname "$sink")"
  [ -f "$sink" ] || : > "$sink"
  if ! grep -qF "$CAPTURE_MD_SECTION" "$sink" 2>/dev/null; then
    printf '\n%s\n\nAdopted by `scripts/capture-config.sh`. Move each line into the section it\nbelongs in — capture appends rather than guessing where prose goes.\n' \
      "$CAPTURE_MD_SECTION" >> "$sink"
  fi
  if ! grep -qxF "$line" "$sink" 2>/dev/null; then
    if [ -n "$heading" ] && [ "$heading" != body ] \
       && ! grep -qxF "<!-- from: ${heading} -->" "$sink" 2>/dev/null; then
      printf '\n<!-- from: %s -->\n' "$heading" >> "$sink"
    fi
    printf '%s\n' "$line" >> "$sink"
  fi
}

# ---------------------------------------------------------------------------
# Propagation — run the renderers, show the downstream blast radius
# ---------------------------------------------------------------------------
# capture_render_snapshot <outdir> — for every target and every file module,
# render against an ABSENT file and store the result as <outdir>/<target>__<module>.
# That is the repo's own assertion with no machine content mixed in, which is
# both the left-hand side of the reversed diff and, taken before and after
# staging, the honest measure of what adopting a hunk changes everywhere else.
capture_render_snapshot() {
  local out="$1" t mod kind render nofile
  mkdir -p "$out"
  nofile="${CAPTURE_WORK}/absent-by-design"
  rm -f "$nofile"
  for t in $CAPTURE_ALL_TARGETS; do
    capture_setup_load "$t" || continue
    for mod in $SETUP_MODULES; do
      kind="$(capture_call "$(capture_fn "$t" "$mod" kind)")"
      [ "$kind" = file ] || continue
      render="$(capture_fn "$t" "$mod" render)"
      capture_callable "$render" || continue
      "$render" "$nofile" > "${out}/${t}__${mod}" 2>/dev/null || : > "${out}/${t}__${mod}"
    done
  done
}

# capture_propagation_report <before-dir> <after-dir>
# Prints one section per target: the rendered diff, or an honest note when the
# platform has no way to express what was captured. Silence is not an option —
# a setting that cannot cross to a platform must be SAID, not dropped.
capture_propagation_report() {
  local before="$1" after="$2" t mod f changed d cap reg
  reg="${SETUP_REPO_ROOT}/core/capabilities/platforms.json"
  for t in $CAPTURE_ALL_TARGETS; do
    capture_load_target "$t" >/dev/null 2>&1 || continue
    changed=no
    for f in "$after"/${t}__*; do
      [ -f "$f" ] || continue
      mod="$(basename "$f")"; mod="${mod#*__}"
      if ! cmp -s "${before}/$(basename "$f")" "$f" 2>/dev/null; then
        changed=yes
        printf '\n  %s — %s\n' "$CAPTURE_DISPLAY" "$mod"
        d="$(setup_diff "${before}/$(basename "$f")" "$f" | sed -n '3,$p' | grep -E '^[+-]' | head -20)"
        printf '%s\n' "$d" | sed 's/^/      /'
      fi
    done
    if [ "$changed" = no ]; then
      cap="$(capture_sink_capability)"
      if [ -n "$cap" ] && [ -f "$reg" ]; then
        printf '\n  %s — no rendered change. Registry: %s = %s\n' "$CAPTURE_DISPLAY" "$cap" \
          "$(jq -r --arg p "$CAPTURE_REGISTRY_KEY" --arg c "$cap" \
               '.platforms[$p].capabilities[$c].status // "unknown"' "$reg" 2>/dev/null)"
      else
        printf '\n  %s — no rendered change: this platform has no equivalent for what was captured.\n' \
          "$CAPTURE_DISPLAY"
      fi
    fi
  done
}

# capture_sink_capability — the capability id (if any) that the sinks adopted in
# this run map to, so the "no equivalent" note can cite the registry rather than
# just asserting it. Set by the caller as CAPTURE_ADOPTED_CAP.
capture_sink_capability() { printf '%s' "${CAPTURE_ADOPTED_CAP:-}"; }

# ---------------------------------------------------------------------------
# Borrowing setup.sh's registry — the same setup.conf, the same writer libraries
# ---------------------------------------------------------------------------
# Capture must resolve `<target>_<module>_render` to the SAME function object
# setup.sh calls. It therefore sources platforms/<t>/setup.conf and the writer
# library that conf names, exactly as setup.sh's load_target does, and never
# keeps a list of modules of its own: SETUP_MODULES from the conf is the list.
CAPTURE_ALL_TARGETS="claude cursor codex gemini opencode"
CAPTURE_SOURCED_WRITERS=""

capture_setup_load() {
  local name="$1" conf override
  SETUP_NAME=""; SETUP_DISPLAY=""; SETUP_DETECT=""; SETUP_CONFIG_DIR=""
  SETUP_ENV_OVERRIDE=""; SETUP_MARKER=""; SETUP_WRITERS=""; SETUP_MODULES=""
  SETUP_STATUS=""
  conf="${SETUP_REPO_ROOT}/platforms/${name}/setup.conf"
  [ -f "$conf" ] || return 1
  # shellcheck source=/dev/null
  . "$conf"
  [ -n "$SETUP_NAME" ] || return 1
  case "$CAPTURE_SOURCED_WRITERS" in
    *"|${SETUP_WRITERS}|"*) : ;;
    *) if [ -n "$SETUP_WRITERS" ] && [ -f "${SETUP_REPO_ROOT}/scripts/lib/${SETUP_WRITERS}" ]; then
         # shellcheck source=/dev/null
         . "${SETUP_REPO_ROOT}/scripts/lib/${SETUP_WRITERS}"
         CAPTURE_SOURCED_WRITERS="${CAPTURE_SOURCED_WRITERS}|${SETUP_WRITERS}|"
       fi ;;
  esac
  if [ -n "$SETUP_ENV_OVERRIDE" ]; then
    eval "override=\${${SETUP_ENV_OVERRIDE}:-}"
    [ -n "$override" ] && SETUP_CONFIG_DIR="$override"
  fi
  SETUP_TARGET_DIR="$SETUP_CONFIG_DIR"
  capture_call "$(printf '%s_target_init' "$(printf '%s' "$name" | tr '-' '_')")"
  return 0
}

# The module-function naming rule, identical to setup.sh's `fn`: `-` is not legal
# in a shell function name, so it maps to `_` on both sides.
capture_fn() { printf '%s_%s_%s' "$(printf '%s' "$1" | tr '-' '_')" "$(printf '%s' "$2" | tr '-' '_')" "$3"; }
capture_callable() { type "$1" >/dev/null 2>&1; }
capture_call() { local f="$1"; shift; if capture_callable "$f"; then "$f" "$@"; fi; }

# capture_normalize_machine <path> — the machine file as the engine sees it.
# JSON goes through setup_json_read + setup_json_normalize, the same two lib
# functions setup.sh's normalize_current calls, so "differs" means the same thing
# in both directions and cannot become a whitespace question in one of them.
capture_normalize_machine() {
  local path="$1"
  [ -f "$path" ] || return 0
  case "$path" in
    *.json) setup_json_read "$path" | setup_json_normalize ;;
    *) cat "$path" ;;
  esac
}

# ---------------------------------------------------------------------------
# The review decision, as a pure function
# ---------------------------------------------------------------------------
# The [y/N/a/q/s] answer is interpreted HERE and not inside the prompt loop, so
# "skip is the default" is a property that can be tested without a terminal.
# It is the single most important default in this script — it is what stands
# between a distracted return key and a committed machine path — and a default
# that can only be verified by hand is a default nobody verifies.
#
# capture_decide <answer> -> adopt | adopt-all | skip | quit | show
capture_decide() {
  case "$(setup_lower "${1:-}")" in
    y|ye|yes)      printf 'adopt' ;;
    a|al|all)      printf 'adopt-all' ;;
    q|qu|qui|quit) printf 'quit' ;;
    s|sh|show)     printf 'show' ;;
    *)             printf 'skip' ;;   # empty input included, by design
  esac
}
