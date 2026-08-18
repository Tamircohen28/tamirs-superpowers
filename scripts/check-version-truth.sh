#!/usr/bin/env bash
# check-version-truth.sh — assert one canonical plugin version, everywhere.
#
# Usage:
#   check-version-truth.sh [repo-root]           # --check (default)
#   check-version-truth.sh --check [repo-root]
#   check-version-truth.sh --sync  [repo-root]   # rewrite consumers to match canonical
#   check-version-truth.sh -h | --help
#
# The canonical version lives in plugin-version.json. Every file listed in its
# "consumers" array must agree. This exists because the version was duplicated across
# five places and drifted twice: the README badge sat at 2.0.0 while all three plugin
# manifests said 2.0.1, and platform-targets.json recorded reviewed_by_skill for a
# version that had already shipped.
#
# Consumer kinds:
#   json_field        — a top-level JSON string field rendered from "template"
#   text_pattern      — a literal string in a text file rendered from "template"
#   changelog_heading — the newest released "## [x.y.z]" heading below [Unreleased]
#
# A consumer whose file does not exist is skipped with a note, not failed — adapters
# land at different times. A consumer with "required": false warns instead of failing
# and is never rewritten by --sync.
#
# --sync edits with targeted string replacement only. It never round-trips JSON through
# jq or a serializer: this repo's manifests contain em-dashes that a re-serialize would
# escape, and the reformat would swamp the one-line diff a version bump should be.
#
# Exit 0 when every required consumer agrees (or after a successful --sync); 1 otherwise.
set -euo pipefail

usage() { sed -n '2,28p' "$0" | sed -E 's/^# ?//'; exit "${1:-0}"; }

MODE="check"
ROOT=""
while (( $# > 0 )); do
  case "$1" in
    -h|--help) usage 0 ;;
    --check)   MODE="check" ;;
    --sync)    MODE="sync" ;;
    --*)       echo "ERROR: unknown flag '$1'" >&2; usage 1 ;;
    *)         ROOT="$1" ;;
  esac
  shift
done
ROOT="$(cd "${ROOT:-.}" && pwd)"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required by check-version-truth.sh" >&2; exit 1; }

CANON_FILE="$ROOT/plugin-version.json"
[[ -f "$CANON_FILE" ]] || { echo "ERROR: no canonical version source at $CANON_FILE" >&2; exit 1; }
jq empty "$CANON_FILE" 2>/dev/null || { echo "ERROR: $CANON_FILE is not valid JSON" >&2; exit 1; }

CANON="$(jq -r '.version // empty' "$CANON_FILE")"
[[ "$CANON" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] \
  || { echo "ERROR: plugin-version.json .version ('$CANON') is not semver" >&2; exit 1; }

SEMVER_RE='[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?'
FAILED=0
WARNED=0
SYNCED=0

err()  { echo "ERROR: $*" >&2; FAILED=$(( FAILED + 1 )); }
warn() { echo "warn:  $*" >&2; WARNED=$(( WARNED + 1 )); }
note() { echo "skip:  $*"; }

# Escape a literal for use inside an ERE / a sed s/// pattern.
esc_re() { sed -E 's/[][\.^$*+?(){}|\/&-]/\\&/g' <<<"$1"; }
# Escape a literal for use as a sed replacement.
esc_rep() { sed -E 's/[\/&\\]/\\&/g' <<<"$1"; }

render() { printf '%s' "${1//\{version\}/$2}"; }

# Build an ERE that matches the template with any semver in the {version} slot.
template_re() {
  local tmpl="$1" pre suf
  pre="${tmpl%%\{version\}*}"
  suf="${tmpl#*\{version\}}"
  printf '%s(%s)%s' "$(esc_re "$pre")" "$SEMVER_RE" "$(esc_re "$suf")"
}

check_consumer() {
  local path kind field template required file expected actual
  path="$1"; kind="$2"; field="$3"; template="$4"; required="$5"
  file="$ROOT/$path"
  expected="$(render "$template" "$CANON")"

  if [[ ! -f "$file" ]]; then
    note "$path — not present in this tree, nothing to check"
    return 0
  fi

  case "$kind" in
    json_field)
      jq empty "$file" 2>/dev/null || { err "$path — invalid JSON"; return 0; }
      actual="$(jq -r "$field // empty" "$file")"
      ;;
    text_pattern)
      actual="$(grep -oE "$(template_re "$template")" "$file" | head -1 || true)"
      ;;
    changelog_heading)
      actual="$(grep -oE "^## \[$SEMVER_RE\]" "$file" | head -1 || true)"
      ;;
    *)
      err "$path — unknown consumer kind '$kind' in plugin-version.json"
      return 0
      ;;
  esac

  if [[ -z "$actual" ]]; then
    if [[ "$required" == "true" ]]; then
      err "$path — no version found (expected '$expected')"
    else
      warn "$path — no version found (expected '$expected')"
    fi
    return 0
  fi

  if [[ "$actual" == "$expected" ]]; then
    printf 'ok:    %-58s %s\n' "$path" "$expected"
    return 0
  fi

  if [[ "$MODE" == "sync" && "$required" == "true" ]]; then
    sync_consumer "$file" "$path" "$kind" "$field" "$actual" "$expected"
    return 0
  fi

  local msg="$path — has '$actual', canonical is '$expected'"
  if [[ "$required" == "true" ]]; then err "$msg"; else warn "$msg (advisory)"; fi
}

# Targeted string replacement. Never re-serializes the file.
sync_consumer() {
  local file path kind field actual expected key script
  file="$1"; path="$2"; kind="$3"; field="$4"; actual="$5"; expected="$6"

  case "$kind" in
    json_field)
      key="${field##*.}"
      script="s/(\"$(esc_re "$key")\"[[:space:]]*:[[:space:]]*\")$(esc_re "$actual")(\")/\1$(esc_rep "$expected")\2/"
      ;;
    text_pattern)
      script="s/$(esc_re "$actual")/$(esc_rep "$expected")/g"
      ;;
    *)
      err "$path — kind '$kind' is not auto-syncable; fix it by hand"
      return 0
      ;;
  esac

  local tmp
  tmp="$(mktemp)"
  sed -E "$script" "$file" >"$tmp"
  if cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    err "$path — --sync matched nothing ('$actual' -> '$expected'); fix it by hand"
    return 0
  fi
  cat "$tmp" >"$file"
  rm -f "$tmp"

  if [[ "$kind" == "json_field" ]] && ! jq empty "$file" 2>/dev/null; then
    err "$path — --sync produced invalid JSON; revert this file"
    return 0
  fi
  printf 'sync:  %-58s %s -> %s\n' "$path" "$actual" "$expected"
  SYNCED=$(( SYNCED + 1 ))
}

echo "Canonical version: $CANON  (plugin-version.json)"

count="$(jq -r '.consumers | length' "$CANON_FILE")"
if [[ "$count" == "0" ]]; then
  echo "ERROR: plugin-version.json declares no consumers" >&2
  exit 1
fi

# Read one field at a time: tab is IFS whitespace, so a @tsv row with an empty
# column (consumers that declare no .field) would silently shift every later column.
consumer_field() { jq -r --argjson i "$1" ".consumers[\$i].$2 // \"\"" "$CANON_FILE"; }

for (( i = 0; i < count; i++ )); do
  c_path="$(consumer_field "$i" path)"
  c_kind="$(consumer_field "$i" kind)"
  c_field="$(consumer_field "$i" field)"
  c_template="$(consumer_field "$i" template)"
  # `// true` would swallow an explicit false, so branch on presence instead.
  c_required="$(jq -r --argjson i "$i" \
    '.consumers[$i] | (if has("required") then .required else true end) | tostring' "$CANON_FILE")"
  check_consumer "$c_path" "$c_kind" "$c_field" "$c_template" "$c_required"
done

if (( FAILED > 0 )); then
  echo "Version truth check FAILED ($FAILED disagreement(s), $WARNED warning(s))." >&2
  echo "Run: bash scripts/check-version-truth.sh --sync" >&2
  exit 1
fi

if (( SYNCED > 0 )); then
  echo "Version truth synced ($SYNCED file(s) rewritten to $CANON, $WARNED warning(s))."
else
  echo "Version truth check passed ($CANON, $WARNED warning(s))."
fi
