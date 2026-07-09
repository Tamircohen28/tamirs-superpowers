#!/usr/bin/env bash
# check-platform-targets.sh — platform tool version documentation and badge sync.
#
# Usage:
#   check-platform-targets.sh [repo-root] [--sync] [--assert-current] [--require-co-change]
#   check-platform-targets.sh -h | --help
#
# Exit 0 if checks pass; 1 on failure.
set -euo pipefail

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

ROOT="."
SYNC=false
ASSERT_CURRENT=false
REQUIRE_CO_CHANGE=false

for arg in "$@"; do
  case "$arg" in
    --sync) SYNC=true ;;
    --assert-current) ASSERT_CURRENT=true ;;
    --require-co-change) REQUIRE_CO_CHANGE=true ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *) ROOT="$arg" ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
FAILED=0
TARGETS_JSON="$ROOT/docs/engineering/build-and-release/platform-targets.json"
TARGETS_MD="$ROOT/docs/engineering/build-and-release/platform-targets.md"
README="$ROOT/README.md"

err() { echo "ERROR: $*" >&2; FAILED=1; }

# --- require-co-change (CI) ---
if [[ "$REQUIRE_CO_CHANGE" == true ]]; then
  WATCH_PATHS=(
    'skills/repo/multi-agent-repo/'
    'skills/repo/repo-standards/'
    'skills/repo/_contract/references/platform-specs.md'
    'skills/repo/_contract/feature-equivalence.json'
    'skills/documentation/platform-sync/'
    'skills/documentation/platform-sync-claude/'
    'skills/documentation/platform-sync-cursor/'
    'skills/documentation/platform-sync-codex/'
  )
  changed=false
  targets_changed=false
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    for p in "${WATCH_PATHS[@]}"; do
      if git -C "$ROOT" diff --name-only HEAD~1 HEAD 2>/dev/null | grep -q "^${p}"; then
        changed=true
        break
      fi
    done
    if git -C "$ROOT" diff --name-only HEAD~1 HEAD 2>/dev/null | grep -q 'platform-targets.json'; then
      targets_changed=true
    fi
    if [[ "$changed" == true && "$targets_changed" != true ]]; then
      err "PR changes repo skills/platform-specs but not docs/engineering/build-and-release/platform-targets.json"
    fi
  fi
  if (( FAILED > 0 )); then exit 1; fi
  echo "Platform targets co-change check passed"
  exit 0
fi

# --- multi-platform gate ---
multi_platform=false
ai_count=0
[[ -f "$ROOT/AGENTS.md" ]] && ai_count=$((ai_count + 1))
[[ -f "$ROOT/CLAUDE.md" ]] && ai_count=$((ai_count + 1))
[[ -d "$ROOT/.cursor/rules" ]] && ai_count=$((ai_count + 1))
[[ -f "$ROOT/.claude-plugin/plugin.json" ]] && ai_count=$((ai_count + 1))
[[ -f "$ROOT/.cursor-plugin/plugin.json" ]] && ai_count=$((ai_count + 1))
[[ -f "$ROOT/.codex-plugin/plugin.json" ]] && ai_count=$((ai_count + 1))
(( ai_count >= 2 )) && multi_platform=true

if [[ "$multi_platform" != true ]]; then
  echo "Single-platform repo — platform-targets check skipped"
  exit 0
fi

# --- --sync: fetch latest_known (best-effort) ---
if [[ "$SYNC" == true && -f "$TARGETS_JSON" ]] && command -v curl >/dev/null 2>&1; then
  codex_latest=""
  codex_latest=$(curl -fsSL "https://api.github.com/repos/openai/codex/releases/latest" 2>/dev/null \
    | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//' || true)
  # Codex GitHub releases use rust-v* tags — only sync semver-style versions.
  if [[ -n "$codex_latest" && "$codex_latest" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    tmp=$(mktemp)
    jq --arg v "$codex_latest" '.targets.codex.latest_known = $v' "$TARGETS_JSON" >"$tmp"
    mv "$tmp" "$TARGETS_JSON"
    echo "Updated codex.latest_known to $codex_latest"
  fi
fi

# --- offline validation ---
if [[ ! -f "$TARGETS_JSON" ]]; then
  err "Missing $TARGETS_JSON (required for multi-platform repos)"
  exit 1
fi

if ! jq empty "$TARGETS_JSON" 2>/dev/null; then
  err "Invalid JSON: $TARGETS_JSON"
  exit 1
fi

for key in claude_code cursor codex; do
  jq -e ".targets.$key.validated_against" "$TARGETS_JSON" >/dev/null 2>&1 \
    || err "platform-targets.json missing targets.$key.validated_against"
done

last_reviewed=$(jq -r '.last_reviewed // empty' "$TARGETS_JSON")
[[ -n "$last_reviewed" ]] || err "platform-targets.json missing last_reviewed"

if [[ ! -f "$TARGETS_MD" ]]; then
  err "Missing human mirror: $TARGETS_MD"
fi

# README badge vs JSON
if [[ -f "$README" ]]; then
  check_badge() {
    local key="$1" prefix="$2"
    local validated
    validated=$(jq -r ".targets.$key.validated_against // empty" "$TARGETS_JSON")
    [[ -n "$validated" ]] || return 0
    if ! grep -qF "${prefix}-${validated}" "$README" 2>/dev/null; then
      err "README missing $key badge for validated_against=$validated (expected ${prefix}-${validated})"
    fi
  }
  check_badge claude_code "Claude%20Code"
  check_badge cursor "Cursor"
  check_badge codex "Codex"
fi

# stale targets
if [[ "$ASSERT_CURRENT" == true ]]; then
  for key in claude_code cursor codex; do
    v=$(jq -r ".targets.$key.validated_against // empty" "$TARGETS_JSON")
    l=$(jq -r ".targets.$key.latest_known // empty" "$TARGETS_JSON")
    if [[ -n "$v" && -n "$l" && "$v" != "$l" ]]; then
      err "Stale platform target $key: validated_against=$v latest_known=$l"
    fi
  done
fi

# last_reviewed > 90 days (warn only unless assert)
if [[ -n "$last_reviewed" ]]; then
  # shellcheck disable=SC2209
  if date -v-90d +%Y-%m-%d >/dev/null 2>&1; then
    cutoff=$(date -v-90d +%Y-%m-%d)
  else
    cutoff=$(date -d '90 days ago' +%Y-%m-%d 2>/dev/null || echo "")
  fi
  if [[ -n "$cutoff" && "$last_reviewed" < "$cutoff" ]]; then
    echo "WARN: platform-targets last_reviewed ($last_reviewed) is older than 90 days" >&2
  fi
fi

if (( FAILED > 0 )); then
  echo "Platform targets check failed ($FAILED error(s))" >&2
  exit 1
fi

echo "Platform targets check passed"
