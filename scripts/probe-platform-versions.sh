#!/usr/bin/env bash
# probe-platform-versions.sh — check upstream platform versions against the pinned
# baseline, live.
#
# Usage:
#   probe-platform-versions.sh [repo-root]
#   probe-platform-versions.sh -h | --help
#
# For each of the five supported platforms, hits a real upstream endpoint for the
# current version and compares it against docs/engineering/build-and-release/
# platform-targets.json's targets.<key>.latest_known. Meant to run nightly (cron/CI)
# so drift is caught without a manual audit.
#
#   claude_code — no reliable public version-check API exists. Reports the pinned
#                 value only; advancing it stays a changelog-review decision, not
#                 something this script can verify live.
#   cursor      — Cursor's public download API (used by cursor.com's own download
#                 page): GET /api/download?platform=darwin-universal&releaseTrack=stable
#                 returns {"version": "..."} for the current stable build.
#   codex       — GitHub releases API on openai/codex; tags are "rust-vX.Y.Z".
#   gemini_cli  — npm registry dist-tags.latest for @google/gemini-cli.
#   opencode    — npm registry dist-tags.latest for opencode-ai.
#
# A platform whose endpoint cannot be reached is reported "unreachable" and excluded
# from the drift count — it must never be silently reported as "no drift".
#
# Exit 0 if no reachable platform drifted; 1 if at least one did.
set -euo pipefail

usage() {
  sed -n '2,26p' "$0" | sed -E 's/^# ?//'
  exit "${1:-0}"
}
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

ROOT="${1:-.}"
TARGETS_JSON="$ROOT/docs/engineering/build-and-release/platform-targets.json"

if [[ ! -f "$TARGETS_JSON" ]]; then
  echo "probe-platform-versions: missing $TARGETS_JSON" >&2
  exit 1
fi

drift_count=0
unreachable_count=0

pinned() {
  jq -r ".targets.$1.latest_known // empty" "$TARGETS_JSON"
}

report() {
  local key="$1" pinned_v="$2" current_v="$3"
  if [[ -z "$current_v" ]]; then
    echo "$key: pinned=$pinned_v current=unreachable — could not reach upstream endpoint"
    unreachable_count=$((unreachable_count + 1))
  elif [[ "$pinned_v" == "$current_v" ]]; then
    echo "$key: pinned=$pinned_v current=$current_v — no drift"
  else
    echo "$key: pinned=$pinned_v current=$current_v — DRIFT"
    drift_count=$((drift_count + 1))
  fi
}

# --- claude_code: no public version-check API; report pinned only ---
claude_pinned=$(pinned claude_code)
echo "claude_code: pinned=$claude_pinned current=n/a — no automated upstream source; advance via changelog review"

# --- cursor: public download API ---
cursor_pinned=$(pinned cursor)
cursor_current=$(curl -fsSL --max-time 10 \
  "https://www.cursor.com/api/download?platform=darwin-universal&releaseTrack=stable" 2>/dev/null \
  | jq -r '.version // empty' 2>/dev/null || true)
report cursor "$cursor_pinned" "$cursor_current"

# --- codex: GitHub releases API, rust-vX.Y.Z tags ---
codex_pinned=$(pinned codex)
codex_current=$(curl -fsSL --max-time 10 \
  "https://api.github.com/repos/openai/codex/releases/latest" 2>/dev/null \
  | jq -r '.tag_name // empty' 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+.*' || true)
report codex "$codex_pinned" "$codex_current"

# --- gemini_cli: npm registry dist-tags.latest ---
gemini_pinned=$(pinned gemini_cli)
gemini_current=$(curl -fsSL --max-time 10 \
  "https://registry.npmjs.org/@google/gemini-cli/latest" 2>/dev/null \
  | jq -r '.version // empty' 2>/dev/null || true)
report gemini_cli "$gemini_pinned" "$gemini_current"

# --- opencode: npm registry dist-tags.latest ---
opencode_pinned=$(pinned opencode)
opencode_current=$(curl -fsSL --max-time 10 \
  "https://registry.npmjs.org/opencode-ai/latest" 2>/dev/null \
  | jq -r '.version // empty' 2>/dev/null || true)
report opencode "$opencode_pinned" "$opencode_current"

echo
echo "Summary: $drift_count drifted, $unreachable_count unreachable"

if [[ "$drift_count" -gt 0 ]]; then
  exit 1
fi
exit 0
