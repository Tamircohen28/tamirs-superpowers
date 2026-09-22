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
#   cursor      — no automated source; reported like claude_code. Cursor's download
#                 API returns the desktop BUILD (3.21.x), but Cursor documents
#                 changes at FEATURE granularity (changelog_feature, e.g. "3.11")
#                 with no per-build release notes, so latest_known/reviewed_through
#                 advance by changelog review (see platform-targets.md), never
#                 against the build. Comparing the two produced a permanent,
#                 un-closeable DRIFT line: V1-04 forbids advancing latest_known
#                 without a matching review, and no build-granularity changelog
#                 exists to review. The build is not fetched — its value could not
#                 be acted on, so the call would gate nothing.
#   codex       — GitHub releases API on openai/codex; tags are "rust-vX.Y.Z".
#   gemini_cli  — npm registry dist-tags.latest for @google/gemini-cli.
#   opencode    — npm registry dist-tags.latest for @opencode/cli, the v2 line.
#                 NOT opencode-ai: that is the v1 package, frozen at 1.18.32, and
#                 watching it hid the entire v2 major from this probe.
#
# A platform whose endpoint cannot be reached is reported "unreachable" and excluded
# from the drift count — it must never be silently reported as "no drift".
#
# Exit 0 if no reachable platform drifted; 1 if at least one did.
set -euo pipefail

# Prints every leading comment line after the shebang, stopping at the first line that
# is not a comment. A fixed `sed -n '2,26p'` range silently truncated --help mid-sentence
# the moment the header grew; this cannot.
usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
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

# --- cursor: no automated source, same treatment as claude_code ---
#
# Cursor's download API returns the desktop BUILD (3.21.x); Cursor documents changes
# at FEATURE granularity (changelog_feature) with no per-build notes. The build is
# therefore not fetched at all: its value could never be acted on here — advancing
# latest_known without a readable changelog is what the contract's V1-04 rejects —
# so a live HTTP call on every nightly run would gate nothing. The build baseline
# stays recorded in platform-targets.json's targets.cursor.latest_known for anyone
# who needs it.
cursor_pinned=$(jq -r ".targets.cursor.changelog_feature // empty" "$TARGETS_JSON")
echo "cursor: pinned=$cursor_pinned current=n/a — no automated feature-changelog source; advance changelog_feature via changelog review"

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

# --- opencode: npm registry dist-tags.latest, @opencode/cli (v2 line) ---
#
# WATCH THE PACKAGE THE PLATFORM ACTUALLY SHIPS FROM.
#
# OpenCode 2 is published under a NEW npm scope, `@opencode/cli`. The v1 package,
# `opencode-ai`, is frozen at 1.18.32 — so this probe watched it across a major
# version boundary and reported "no drift" the entire time. A probe that pins a
# package name cannot see a major that renames the package; that blindness is the
# bug this line fixes, not the version number it happened to print.
#
# The scope must be URL-encoded (%2F) for the registry path.
opencode_pinned=$(pinned opencode)
opencode_current=$(curl -fsSL --max-time 10 \
  "https://registry.npmjs.org/@opencode%2Fcli/latest" 2>/dev/null \
  | jq -r '.version // empty' 2>/dev/null || true)
report opencode "$opencode_pinned" "$opencode_current"

echo
echo "Summary: $drift_count drifted, $unreachable_count unreachable"

if [[ "$drift_count" -gt 0 ]]; then
  exit 1
fi
exit 0
