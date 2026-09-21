#!/usr/bin/env bash
# check-platform-version-pins.sh — assert the three root version pins agree with
# docs/engineering/build-and-release/platform-targets.json.
#
# Usage:
#   check-platform-version-pins.sh [repo-root]
#   check-platform-version-pins.sh -h | --help
#
# .claude-code-version, .codex-version and .cursor-version are root-level, hand-maintained
# mirrors of platform-targets.json's per-target version fields (see CLAUDE.md's "Claude
# Code CLI baseline" section and docs/engineering/refactor/file-inventory.md, which names
# them a fourth version-truth source held in sync purely by hand, read by no script).
# This is that script.
#
# Each pin file's unlabeled first line is treated as a mirror of that target's
# `latest_known`. That is a best-effort reading of an undocumented convention, not a
# fact confirmed by a schema — on every target measured so far, latest_known happens to
# equal reviewed_through (and, for cursor, validated_against/supported_min too), so this
# line alone cannot prove which field it mirrors.
#
# .claude-code-version's `last_reviewed` has no `last_reviewed` field on
# targets.claude_code — it is compared against that target's `verified_on`, which carries
# the same meaning (the date this target was last checked) and the same value.
# `source_of_truth` names this very JSON file and is not a claim to verify, so it is
# skipped.
#
# .cursor-version's `cli_changelog_date` and `frontier_model` have no matching top-level
# field on targets.cursor at all — both are drawn from that target's free-text
# verification_method / features_adopted. They are checked as a best-effort substring
# match against the whole target block and WARNED (not failed) on a miss: prose drift is
# a different class of claim than a structured field disagreeing, and a substring miss
# does not prove the pin is wrong, only that it could not be confirmed.
#
# Exit 0 if every structured field matches (warnings allowed). Exit 1 and name each
# disagreement if any structured field's pin value differs from platform-targets.json.
set -euo pipefail

usage() { sed -n '2,29p' "$0" | sed -E 's/^# ?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required by check-platform-version-pins.sh" >&2; exit 1; }

TARGETS_JSON="$ROOT/docs/engineering/build-and-release/platform-targets.json"
[[ -f "$TARGETS_JSON" ]] || { echo "ERROR: no platform-targets.json at $TARGETS_JSON" >&2; exit 1; }
jq empty "$TARGETS_JSON" 2>/dev/null || { echo "ERROR: $TARGETS_JSON is not valid JSON" >&2; exit 1; }

FAILED=0
err()  { echo "ERROR: $*" >&2; FAILED=$(( FAILED + 1 )); }
warn() { echo "warn:  $*" >&2; }
ok()   { printf 'ok:    %s\n' "$*"; }

target_field() {
  # target_field <target-key> <json-field>
  jq -r ".targets[\"$1\"].$2 // empty" "$TARGETS_JSON"
}

check_field() {
  # check_field <pin-file> <target-key> <label> <pin-value> <json-field>
  local pin_file="$1" target_key="$2" label="$3" pin_value="$4" json_field="$5"
  local json_value
  json_value="$(target_field "$target_key" "$json_field")"
  if [[ -z "$json_value" ]]; then
    warn "$pin_file: $label — no targets.$target_key.$json_field in platform-targets.json to compare against"
    return 0
  fi
  if [[ "$pin_value" == "$json_value" ]]; then
    ok "$pin_file: $label matches ($pin_value)"
  else
    err "$pin_file: $label — file says '$pin_value', platform-targets.json says '$json_value' (targets.$target_key.$json_field)"
  fi
}

check_substring() {
  # best-effort: pin_value must appear somewhere inside the target's whole JSON block
  local pin_file="$1" target_key="$2" label="$3" pin_value="$4"
  local blob
  blob="$(jq -c ".targets[\"$target_key\"]" "$TARGETS_JSON")"
  if [[ "$blob" == *"$pin_value"* ]]; then
    ok "$pin_file: $label ('$pin_value') found in targets.$target_key"
  else
    warn "$pin_file: $label — '$pin_value' not found anywhere in targets.$target_key (no structured field for this claim; may be stale)"
  fi
}

parse_pin_file() {
  # Reads a pin file: line 1 is the bare version, handled by the caller separately.
  # Every subsequent "key: value" line is emitted as "key<TAB>value".
  local file="$1"
  tail -n +2 "$file" | grep -E '^[A-Za-z_]+: ' | sed -E 's/^([A-Za-z_]+): /\1\t/'
}

# --- .claude-code-version --------------------------------------------------------------
CC_FILE="$ROOT/.claude-code-version"
if [[ -f "$CC_FILE" ]]; then
  CC_VERSION="$(head -1 "$CC_FILE")"
  check_field "$CC_FILE" claude_code "latest_known (unlabeled line 1)" "$CC_VERSION" latest_known
  while IFS=$'\t' read -r key value; do
    case "$key" in
      validated_against) check_field "$CC_FILE" claude_code "validated_against" "$value" validated_against ;;
      reviewed_through)  check_field "$CC_FILE" claude_code "reviewed_through" "$value" reviewed_through ;;
      latest_known)      check_field "$CC_FILE" claude_code "latest_known" "$value" latest_known ;;
      last_reviewed)     check_field "$CC_FILE" claude_code "last_reviewed (-> verified_on)" "$value" verified_on ;;
      source_of_truth)   : ;;  # self-referential pointer to this JSON file, nothing to compare
      *)                 warn "$CC_FILE: unrecognized field '$key' — not checked" ;;
    esac
  done < <(parse_pin_file "$CC_FILE")
else
  warn "$CC_FILE not present, skipping"
fi

# --- .codex-version ----------------------------------------------------------------------
CODEX_FILE="$ROOT/.codex-version"
if [[ -f "$CODEX_FILE" ]]; then
  CODEX_VERSION="$(head -1 "$CODEX_FILE")"
  check_field "$CODEX_FILE" codex "latest_known (unlabeled line 1)" "$CODEX_VERSION" latest_known
else
  warn "$CODEX_FILE not present, skipping"
fi

# --- .cursor-version ---------------------------------------------------------------------
CURSOR_FILE="$ROOT/.cursor-version"
if [[ -f "$CURSOR_FILE" ]]; then
  CURSOR_VERSION="$(head -1 "$CURSOR_FILE")"
  check_field "$CURSOR_FILE" cursor "latest_known (unlabeled line 1)" "$CURSOR_VERSION" latest_known
  while IFS=$'\t' read -r key value; do
    case "$key" in
      changelog_feature)  check_field "$CURSOR_FILE" cursor "changelog_feature" "$value" changelog_feature ;;
      changelog_date)     check_field "$CURSOR_FILE" cursor "changelog_date" "$value" changelog_date ;;
      cli_changelog_date) check_substring "$CURSOR_FILE" cursor "cli_changelog_date" "$value" ;;
      frontier_model)     check_substring "$CURSOR_FILE" cursor "frontier_model" "$value" ;;
      *)                  warn "$CURSOR_FILE: unrecognized field '$key' — not checked" ;;
    esac
  done < <(parse_pin_file "$CURSOR_FILE")
else
  warn "$CURSOR_FILE not present, skipping"
fi

if (( FAILED > 0 )); then
  echo "Platform version pin check FAILED ($FAILED disagreement(s))." >&2
  exit 1
fi

echo "Platform version pin check passed."
