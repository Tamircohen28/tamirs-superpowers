#!/usr/bin/env bash
# doctor.sh — health report for a tamirs-superpowers install.
#
# Usage:
#   doctor.sh [repo-root]
#   doctor.sh -h | --help
#
# Reports: detected platform(s), canonical plugin version and any drift, required and
# optional tool presence with versions, which optional features are therefore usable,
# the capabilities the detected platform provides, each detected host CLI's version
# against its permission-levels floor (ADR 004 D9), and a one-line remedy for everything
# missing.
#
# Non-interactive by design: every probe reads from /dev/null, so this never blocks on
# stdin (the statusline shipped with an unguarded read once — that bug does not recur here),
# and runs under a hard deadline (DOCTOR_PROBE_SECONDS, 1-3, default 3), so a CLI that
# hangs on --version (a launcher shim, say) is reported "version unknown (probe timed out)"
# instead of stalling the report. The Cursor desktop app is never launched: its version is
# read from the app bundle's package.json.
#
# Exit 0 when the install is usable, even with optional features missing. Exit 1 only
# when the install is genuinely broken: core files absent or unparseable, a required
# runtime dependency missing, or the version-truth check failing.
#
# Not the same check as Claude Code's own `/doctor` (2.1.257+ warns there about stale
# sandbox mask files left by a killed session): that is host-process state, invisible
# from a plain repo checkout, so it is out of scope here. The two are complementary,
# not overlapping — run this script for the plugin install, `/doctor` inside a live
# session for the sandbox.
set -euo pipefail

usage() { sed -n '2,22p' "$0" | sed -E 's/^# ?//'; exit "${1:-0}"; }
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage 0

ROOT="$(cd "${1:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")}" && pwd)"
# This plugin's own install, which [repo-root] may not be: the permission floors are facts
# about the plugin, read from where it is installed.
PLUGIN_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BROKEN=0
MISSING=()

hdr()  { printf '\n== %s ==\n' "$1"; }
ok()   { printf '  ok      %s\n' "$*"; }
warnl(){ printf '  missing %s\n' "$*"; }
warnv(){ printf '  warn    %s\n' "$*"; }
skipl(){ printf '  n/a     %s\n' "$*"; }
bad()  { printf '  BROKEN  %s\n' "$*"; BROKEN=$(( BROKEN + 1 )); }

# --- repo shape --------------------------------------------------------------
# doctor used to assert that every repo it ran in was a plugin repo: a missing
# plugin-version.json produced a hard `BROKEN  no canonical version`, so running
# doctor in any ordinary app repo reported an UNHEALTHY install and exited 1.
# Whether this repo ships a plugin is an observable fact, not an assumption —
# detect-contract-profile.sh already answers it, so ask it once here and make
# every plugin-only check conditional on the answer.
IS_PLUGIN_REPO=false
SHAPE_DETECTOR="$ROOT/skills/repo/_contract/scripts/detect-contract-profile.sh"
if [[ -f "$SHAPE_DETECTOR" ]]; then
  while IFS='=' read -r k v; do
    case "$k" in IS_PLUGIN_REPO) IS_PLUGIN_REPO="$v" ;; esac
  done < <(bash "$SHAPE_DETECTOR" "$ROOT" --shape </dev/null 2>/dev/null || true)
else
  # The detector itself ships with the plugin; without it, fall back to the same
  # signals it reads rather than to "assume plugin".
  for m in plugin-version.json .claude-plugin/plugin.json .claude-plugin/marketplace.json agent-kit.config.json; do
    [[ -e "$ROOT/$m" ]] && { IS_PLUGIN_REPO=true; break; }
  done
fi

PROBE_SECS="${DOCTOR_PROBE_SECONDS:-3}"
case "$PROBE_SECS" in 1|2|3) ;; *) PROBE_SECS=3 ;; esac
PROBE_TIMED_OUT="version unknown (probe timed out)"

# with_deadline <seconds> <command...> — run it, killed after <seconds> with every process it
# started; its status, or 124/137/143 when the deadline killed it. coreutils timeout/gtimeout
# when installed, else a background job in its own process group and a watchdog (macOS ships
# no timeout): the pattern of hooks/lib/permission-conditions.sh.
with_deadline() {
  local secs="$1" pid wd rc=0 mon=0 sl
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout -k 1 "$secs" "$@" || rc=$?
    return "$rc"
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout -k 1 "$secs" "$@" || rc=$?
    return "$rc"
  fi
  sl="$(command -v sleep 2>/dev/null || echo /bin/sleep)"
  case "$-" in *m*) mon=1 ;; esac
  set -m
  "$@" &
  pid=$!
  [[ "$mon" == 1 ]] || set +m
  ( "$sl" "$secs"; kill -TERM -- "-$pid" 2>/dev/null; "$sl" 1; kill -KILL -- "-$pid" 2>/dev/null ) \
    </dev/null >/dev/null 2>&1 &
  wd=$!
  wait "$pid" || rc=$?
  kill "$wd" 2>/dev/null || true
  wait "$wd" 2>/dev/null || true
  return "$rc"
}

# Print "name version" for a tool, or empty if absent. Never reads stdin; never waits longer
# than the probe deadline.
tool_version() {
  local bin="$1" out="" rc=0
  command -v "$bin" >/dev/null 2>&1 || return 1
  out="$(with_deadline "$PROBE_SECS" "$bin" --version </dev/null 2>/dev/null)" || rc=$?
  case "$rc" in
    124|137|143) printf '%s' "$PROBE_TIMED_OUT"; return 0 ;;
  esac
  out="$(printf '%s\n' "$out" | head -1 || true)"
  printf '%s' "${out:-present}"
}

echo "tamirs-superpowers doctor"
echo "repo: $ROOT"

# --- Detected platform(s) ---
hdr "Detected platform(s)"
detected=()
[[ -n "${CLAUDECODE:-}${CLAUDE_CODE_ENTRYPOINT:-}" ]] && detected+=("claude_code (session env)")
[[ -n "${CURSOR_TRACE_ID:-}${CURSOR_AGENT:-}" ]]                           && detected+=("cursor (session env)")
[[ -n "${CODEX_HOME:-}${CODEX_SANDBOX:-}" ]]                               && detected+=("codex (session env)")
[[ -n "${GEMINI_CLI:-}${GEMINI_API_KEY:-}" ]]                              && detected+=("gemini_cli (session env)")
[[ -n "${OPENCODE:-}${OPENCODE_BIN_PATH:-}" ]]                             && detected+=("opencode (session env)")

for pair in "claude:claude_code" "cursor-agent:cursor" "codex:codex" "gemini:gemini_cli" "opencode:opencode"; do
  bin="${pair%%:*}"; id="${pair##*:}"
  if v="$(tool_version "$bin")"; then
    detected+=("$id (CLI: $v)")
    printf -v "HV_${bin//-/_}" '%s' "$v"   # reused by the permission-floor check below
  fi
done

if (( ${#detected[@]} == 0 )); then
  echo "  none — no harness env var set and no supported CLI on PATH"
  echo "  remedy: run doctor from inside a supported harness, or install one (see docs/user/install/)"
else
  printf '  %s\n' "${detected[@]}"
fi

# --- Version truth ---
hdr "Version"
CANON=""
if [[ -f "$ROOT/plugin-version.json" ]] && command -v jq >/dev/null 2>&1; then
  CANON="$(jq -r '.version // empty' "$ROOT/plugin-version.json" 2>/dev/null || true)"
fi
if [[ -z "$CANON" && "$IS_PLUGIN_REPO" != true ]]; then
  skipl "not a plugin repo (no plugin manifest, marketplace, or agent-kit config) — version truth does not apply"
elif [[ -z "$CANON" ]]; then
  if [[ ! -f "$ROOT/plugin-version.json" ]]; then
    bad "plugin repo without plugin-version.json — the manifests have no canonical version to agree with"
  else
    bad "plugin-version.json is present but unreadable (invalid JSON, no .version, or jq unavailable)"
  fi
else
  ok "canonical version $CANON (plugin-version.json)"
  if [[ -x "$ROOT/scripts/check-version-truth.sh" || -f "$ROOT/scripts/check-version-truth.sh" ]]; then
    if drift="$(bash "$ROOT/scripts/check-version-truth.sh" "$ROOT" </dev/null 2>&1)"; then
      ok "all version consumers agree"
      grep -E '^(warn|skip):' <<<"$drift" | sed 's/^/          /' || true
    else
      bad "version drift across consumers:"
      grep -E '^(ERROR|warn):' <<<"$drift" | sed 's/^/          /' || true
      echo "          remedy: bash scripts/check-version-truth.sh --sync"
    fi
  fi
fi

# --- Core files ---
hdr "Install integrity"
if [[ "$IS_PLUGIN_REPO" != true ]]; then
  skipl "plugin install integrity — this repo does not ship a plugin; nothing to check"
else
  for f in .claude-plugin/plugin.json skills core/capabilities/platforms.json; do
    if [[ -e "$ROOT/$f" ]]; then ok "$f present"; else bad "$f missing"; fi
  done
fi
if command -v jq >/dev/null 2>&1; then
  while IFS= read -r m; do
    if jq empty "$m" 2>/dev/null; then ok "${m#"$ROOT"/} parses"; else bad "${m#"$ROOT"/} is invalid JSON"; fi
  done < <(find "$ROOT" -maxdepth 2 -name 'plugin.json' -path '*-plugin/*' 2>/dev/null | sort)
fi
if [[ -d "$ROOT/skills" ]]; then
  n="$(find "$ROOT/skills" -name SKILL.md 2>/dev/null | grep -vc '_contract/fixtures' || true)"
  ok "$n shipped skills discovered under skills/"
fi

# --- Required runtime dependencies ---
hdr "Required runtime dependencies"
for bin in bash git; do
  if v="$(tool_version "$bin")"; then ok "$bin — $v"; else bad "$bin not on PATH — core workflows cannot run"; fi
done

# --- Optional dependencies ---
hdr "Optional dependencies"
declare -a OPT=(
  "jq|shell helpers, every JSON validator|brew install jq (or apt-get install jq)"
  "gh|GitHub automation in pr-dev / start-dev / cleanup|brew install gh && gh auth login"
  "node|session-report usage analytics|install Node 18+ from nodejs.org or via nvm"
  "python3|skill frontmatter validation and the usage-capture collector|python3 ships with macOS; else install from python.org"
  "shellcheck|contributor lint (make lint)|brew install shellcheck"
)
for row in "${OPT[@]}"; do
  IFS='|' read -r bin what remedy <<<"$row"
  if v="$(tool_version "$bin")"; then
    ok "$bin — $v"
  else
    warnl "$bin — needed for: $what"
    MISSING+=("$bin: $remedy")
  fi
done

# --- Optional features ---
hdr "Optional features"
if command -v gh >/dev/null 2>&1 && with_deadline 5 gh auth status </dev/null >/dev/null 2>&1; then
  ok "GitHub automation — gh installed and authenticated"
else
  warnl "GitHub automation — PR/issue steps will print output for manual filing instead"
  MISSING+=("GitHub automation: gh auth login")
fi

if command -v node >/dev/null 2>&1 && [[ -d "$HOME/.claude/projects" ]]; then
  ok "session-report — node present and Claude JSONL transcripts found"
else
  warnl "session-report — needs node plus ~/.claude/projects transcripts (Claude Code format only)"
  MISSING+=("session-report: install node and run at least one Claude Code session")
fi

if command -v python3 >/dev/null 2>&1 && [[ -d "${TAMIRS_USAGE_CAPTURE_DIR:-$HOME/.local/share/tamirs-superpowers/usage}" ]]; then
  ok "usage-capture — python3 present and log directory exists"
elif command -v python3 >/dev/null 2>&1; then
  warnl "usage-capture — python3 present; no local JSONL dir yet (opt-in via /usage-capture)"
  MISSING+=("usage-capture: bash scripts/usage-capture/enable.sh")
else
  warnl "usage-capture — needs python3 to run the local collector"
  MISSING+=("usage-capture: install python3")
fi

# Pushover credentials are the plugin's sensitive userConfig options, held by the
# host's credential store and visible only to the plugin's own hooks — a script
# outside a hook cannot (and must not) read them, so there is nothing to probe.
ok "notifications — Pushover is opt-in via plugin options (/notify-setup to set up or test)"

# --- Capabilities on the detected platform ---
hdr "Capabilities"
REGISTRY="$ROOT/core/capabilities/platforms.json"
if [[ ! -f "$REGISTRY" ]] || ! command -v jq >/dev/null 2>&1; then
  echo "  unavailable — needs core/capabilities/platforms.json and jq"
else
  primary=""
  for pair in "CLAUDECODE:claude_code" "CURSOR_TRACE_ID:cursor" \
              "CODEX_HOME:codex" "GEMINI_CLI:gemini_cli" "OPENCODE:opencode"; do
    var="${pair%%:*}"; id="${pair##*:}"
    if [[ -n "${!var:-}" ]]; then primary="$id"; break; fi
  done
  if [[ -z "$primary" ]]; then
    echo "  no harness detected from the environment — showing the registry summary for every platform"
    jq -r '
      [ .platforms[] | .display_name as $pn | (.surfaces // {} | to_entries[])
        | select(.value.support != "unverified") ] | .[]
      | .key as $p | .value.display_name as $n
      | (.value.capabilities | to_entries)
      | [ (map(select(.value.status | test("^native"))) | length),
          (map(select(.value.status == "unknown")) | length),
          (length) ] as $c
      | "  \($n) (\($p)): \($c[0]) native, \($c[1]) unknown, of \($c[2])"
    ' "$REGISTRY"
    echo "  remedy: run doctor inside a harness for a per-platform breakdown"
  else
    echo "  platform: $primary"
    jq -r --arg p "$primary" '
      (first(.platforms[]?.surfaces[$p]? | select(. != null)) // .platforms[$p]?).capabilities | to_entries[]
      | "  \(.value.status | (. + "                    ")[0:21])\(.key)"
        + (if .value.fallback then "\n      fallback: \(.value.fallback)" else "" end)
    ' "$REGISTRY" | sed 's/^/  /'
  fi
fi

# --- Permission levels: host floors (ADR 004 D9) ---
# Each host CLI on PATH against the version its permission-level semantics were measured or
# source-cited on. The floors are read from this plugin's platform-targets.json
# (permissions_min, and Cursor's permissions_min_cli for cursor-agent) and, where the
# engineering docs did not ship (every distribution prunes them), from the registry's
# permission_levels `since`, which check-capability-registry.sh holds equal. D9: below the
# floor every level above supervised should run as supervised; an unreadable version is a
# warning only. Only `--version` is ever run, under the probe deadline; nothing here starts a
# session or the Cursor app.
hdr "Permission levels (host floors, ADR 004 D9)"
FLOOR_TARGETS="$PLUGIN_HOME/docs/engineering/build-and-release/platform-targets.json"
FLOOR_REGISTRY="$PLUGIN_HOME/core/capabilities/platforms.json"

# perm_floor <target> <field> — prints "<version> <source>" or nothing.
perm_floor() {
  local t="$1" f="$2" v=""
  if [[ -f "$FLOOR_TARGETS" ]]; then
    v="$(jq -r --arg t "$t" --arg f "$f" '.targets[$t][$f] // empty' "$FLOOR_TARGETS" 2>/dev/null || true)"
    [[ -n "$v" ]] && { printf '%s platform-targets.json' "$v"; return 0; }
  fi
  if [[ "$f" == permissions_min && -f "$FLOOR_REGISTRY" ]]; then
    v="$(jq -r --arg t "$t" 'first(.platforms[].surfaces[$t]? | select(. != null)) | .capabilities.permission_levels.since // empty' \
      "$FLOOR_REGISTRY" 2>/dev/null || true)"
    [[ -n "$v" ]] && printf '%s core/capabilities/platforms.json' "$v"
  fi
  return 0
}

# cursor_app_version — the Cursor desktop app's version from its bundle's package.json, read
# as a file: `cursor --version` can block (the launcher shim waits on the app), so it is never
# run. DOCTOR_CURSOR_APP_DIRS (colon-separated resources/app dirs) replaces the default places.
cursor_app_version() {
  local dirs d v
  dirs="${DOCTOR_CURSOR_APP_DIRS:-$HOME/Applications/Cursor.app/Contents/Resources/app:/Applications/Cursor.app/Contents/Resources/app:/usr/share/cursor/resources/app:/opt/Cursor/resources/app:/opt/cursor/resources/app}"
  local IFS=:
  for d in $dirs; do
    [[ -n "$d" && -f "$d/package.json" ]] || continue
    v="$(jq -r '.version // empty' "$d/package.json" 2>/dev/null || true)"
    printf '%s' "${v:-present}"
    return 0
  done
  return 0
}

# ver_lt <a> <b> — 0 when dotted-numeric a < b (a pre-release suffix is ignored).
ver_lt() {
  awk -v a="$1" -v b="$2" 'BEGIN { n = split(a, x, "."); m = split(b, y, "."); k = (n > m ? n : m)
    for (i = 1; i <= k; i++) { p = (i <= n ? x[i] + 0 : 0); q = (i <= m ? y[i] + 0 : 0)
      if (p < q) exit 0; if (p > q) exit 1 } exit 1 }'
}

# bin | target | floor field | label | what the floor guarantees (ADR 004 D9's feature column)
declare -a FLOORS=(
  "claude|claude_code|permissions_min|Claude Code|the permission guard's ask dialog under bypassPermissions, its headless deny (C4/U3) and the UserPromptSubmit source a --perms= raise needs (C3) were measured from this version"
  "codex|codex|permissions_min|Codex CLI|the deny-only hook contract the permission guard answers in is source-cited from this version; an older build may let an ask or a malformed answer through (X1)"
  "cursor-agent|cursor|permissions_min_cli|Cursor CLI|the preToolUse/beforeShellExecution deny the permission guard answers is source-cited from this build (U1)"
  "@cursor-app|cursor|permissions_min|Cursor desktop|the desktop app's deny-only hooks are assumed from this build (pending spike S2)"
  "gemini|gemini_cli|permissions_min|Gemini CLI|the static ask_user rule for R4 and confirm and its headless deny under --yolo were measured from this version (G1-G3)"
  "opencode|opencode|permissions_min|OpenCode|a plugin permission-hook deny staying final under --auto was measured from this version (O1-O3)"
)
if ! command -v jq >/dev/null 2>&1; then
  skipl "permission floors — needs jq to read them"
elif [[ ! -f "$FLOOR_TARGETS" && ! -f "$FLOOR_REGISTRY" ]]; then
  skipl "permission floors — neither platform-targets.json nor core/capabilities/platforms.json is in this install"
else
  checked=0
  for row in "${FLOORS[@]}"; do
    IFS='|' read -r bin target field label feature <<<"$row"
    if [[ "$bin" == @cursor-app ]]; then
      raw="$(cursor_app_version)"
    else
      var="HV_${bin//-/_}"
      raw="${!var:-}"
      if [[ -z "$raw" ]]; then
        raw="$(tool_version "$bin" || true)"
      fi
    fi
    [[ -n "$raw" ]] || continue
    checked=$(( checked + 1 ))
    floor="$(perm_floor "$target" "$field")"
    if [[ -z "$floor" ]]; then
      skipl "permission levels: $label floor ($field) is not recorded in this install"
      continue
    fi
    fv="${floor%% *}"; fsrc="${floor#* }"
    if [[ "$raw" == "$PROBE_TIMED_OUT" ]]; then
      warnv "permission levels: $label $PROBE_TIMED_OUT after ${PROBE_SECS}s, so its floor $fv is not checked (ADR 004 D9: a warning only)"
      continue
    fi
    have="$(printf '%s\n' "$raw" | grep -Eo '[0-9]+(\.[0-9]+)+' | head -1 || true)"
    if [[ -z "$have" ]]; then
      warnv "permission levels: $label version unreadable ('$raw'), so its floor $fv is not checked (ADR 004 D9: a warning only)"
      continue
    fi
    if ver_lt "$have" "$fv"; then
      warnv "permission levels: $label $have is below the floor $fv ($fsrc, ADR 004 D9): $feature"
      if [[ "$bin" == claude ]] && ver_lt "$have" 2.1.295; then
        warnv "  ... and below 2.1.295, \`onFailure: \"block\"\` is not honoured: the permission guard fails OPEN if it cannot start"
      fi
      if [[ "$bin" == claude ]] && ver_lt "$have" 2.1.271; then
        warnv "  ... and below 2.1.271 the install dialog's permission_level options picker does not load (C2): use scripts/plugin-config.sh"
      fi
      echo "          remedy: upgrade $label to $fv or later; until then every level above supervised runs as supervised there (the resolver's ADR 004 D9 clamp)"
      MISSING+=("permission levels on $label $have: below the floor $fv — upgrade, or stay at supervised")
    else
      ok "permission levels: $label $have meets the floor $fv"
    fi
  done
  if (( checked == 0 )); then
    skipl "permission floors — no host CLI on PATH to compare"
  fi
fi

# --- Summary ---
hdr "Summary"
if (( BROKEN > 0 )); then
  echo "  UNHEALTHY — $BROKEN blocking problem(s) above. The install will not work as shipped."
  exit 1
fi
if (( ${#MISSING[@]} > 0 )); then
  echo "  healthy, with ${#MISSING[@]} optional feature(s) unavailable:"
  printf '    - %s\n' "${MISSING[@]}"
else
  echo "  healthy — everything present."
fi
exit 0
