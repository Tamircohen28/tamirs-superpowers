#!/usr/bin/env bash
# doctor.sh — health report for a tamirs-superpowers install.
#
# Usage:
#   doctor.sh [repo-root]
#   doctor.sh -h | --help
#
# Reports: detected platform(s), canonical plugin version and any drift, required and
# optional tool presence with versions, which optional features are therefore usable,
# the capabilities the detected platform provides, and a one-line remedy for everything
# missing.
#
# Non-interactive by design: every probe reads from /dev/null, so this never blocks on
# stdin (the statusline shipped with an unguarded read once — that bug does not recur here).
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

usage() { sed -n '2,17p' "$0" | sed -E 's/^# ?//'; exit "${1:-0}"; }
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage 0

ROOT="$(cd "${1:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")}" && pwd)"
BROKEN=0
MISSING=()

hdr()  { printf '\n== %s ==\n' "$1"; }
ok()   { printf '  ok      %s\n' "$*"; }
warnl(){ printf '  missing %s\n' "$*"; }
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

# Print "name version" for a tool, or empty if absent. Never reads stdin.
tool_version() {
  local bin="$1" ver
  command -v "$bin" >/dev/null 2>&1 || return 1
  ver="$("$bin" --version </dev/null 2>/dev/null | head -1 || true)"
  printf '%s' "${ver:-present}"
}

echo "tamirs-superpowers doctor"
echo "repo: $ROOT"

# --- Detected platform(s) ---
hdr "Detected platform(s)"
detected=()
[[ -n "${CLAUDE_PLUGIN_ROOT:-}${CLAUDECODE:-}${CLAUDE_CODE_ENTRYPOINT:-}" ]] && detected+=("claude_code (session env)")
[[ -n "${CURSOR_TRACE_ID:-}${CURSOR_AGENT:-}" ]]                           && detected+=("cursor (session env)")
[[ -n "${CODEX_HOME:-}${CODEX_SANDBOX:-}" ]]                               && detected+=("codex (session env)")
[[ -n "${GEMINI_CLI:-}${GEMINI_API_KEY:-}" ]]                              && detected+=("gemini_cli (session env)")
[[ -n "${OPENCODE:-}${OPENCODE_BIN_PATH:-}" ]]                             && detected+=("opencode (session env)")

for pair in "claude:claude_code" "cursor-agent:cursor" "codex:codex" "gemini:gemini_cli" "opencode:opencode"; do
  bin="${pair%%:*}"; id="${pair##*:}"
  if v="$(tool_version "$bin")"; then detected+=("$id (CLI: $v)"); fi
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
  "python3|skill frontmatter + capability schema validation|python3 ships with macOS; else install from python.org"
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
if command -v gh >/dev/null 2>&1 && gh auth status </dev/null >/dev/null 2>&1; then
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

if [[ -n "${PUSHOVER_TOKEN:-}" && -n "${PUSHOVER_USER:-}" ]]; then
  ok "notifications — Pushover credentials present in the environment"
else
  warnl "notifications — PUSHOVER_TOKEN / PUSHOVER_USER not set"
  MISSING+=("notifications: run the notify-setup skill")
fi

# --- Capabilities on the detected platform ---
hdr "Capabilities"
REGISTRY="$ROOT/core/capabilities/platforms.json"
if [[ ! -f "$REGISTRY" ]] || ! command -v jq >/dev/null 2>&1; then
  echo "  unavailable — needs core/capabilities/platforms.json and jq"
else
  primary=""
  for pair in "CLAUDE_PLUGIN_ROOT:claude_code" "CLAUDECODE:claude_code" "CURSOR_TRACE_ID:cursor" \
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
