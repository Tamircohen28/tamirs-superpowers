#!/usr/bin/env bash
# check-marketplace-schema.sh — guard the Claude Code extraKnownMarketplaces shape.
#
# Usage:
#   check-marketplace-schema.sh [repo-root]
#   check-marketplace-schema.sh -h | --help
#
# Claude Code parses extraKnownMarketplaces as a RECORD keyed by marketplace name.
# The array form is accepted by JSON but rejected by the settings schema, and the key
# is dropped silently — no startup error, no warning, the marketplace never registers.
# A repo can look healthy for months because a global ~/.claude/settings.json happens
# to declare the same marketplace; the breakage only surfaces on a clean machine.
#
# This check fails on the array form and on the invented `sourceUrl` field, in both
# real settings files and the scaffold templates that generate them.
#
# Exit 0 if checks pass; 1 on failure.
set -euo pipefail

usage() {
  # -E so `?` is portable: BSD sed ignores GNU's `\?`, which prints a literal "# " prefix.
  sed -n '2,17p' "$0" | sed -E 's/^# ?//'
  exit "${1:-0}"
}
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

ROOT="$(cd "${1:-.}" && pwd)"
FAILED=0

err() { echo "ERROR: $*" >&2; FAILED=$(( FAILED + 1 )); }

# --- 1. Real settings files: validate the parsed shape ---
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  jq empty "$f" 2>/dev/null || { err "$f: invalid JSON"; continue; }

  kind=$(jq -r 'if has("extraKnownMarketplaces") then (.extraKnownMarketplaces | type) else "absent" end' "$f")
  case "$kind" in
    absent) continue ;;
    object) ;;
    *) err "$f: extraKnownMarketplaces is of type '$kind' — Claude Code expects a record keyed by marketplace name, and drops the key silently when it is not"
       continue ;;
  esac

  # Every entry needs source.source; sourceUrl is not a schema field.
  bad=$(jq -r '.extraKnownMarketplaces | to_entries[]
        | select((.value.source.source // "") == "")
        | .key' "$f")
  if [[ -n "$bad" ]]; then
    while IFS= read -r name; do
      err "$f: marketplace '$name' has no source.source (expected {\"source\":{\"source\":\"github\",\"repo\":\"owner/name\"}})"
    done <<<"$bad"
  fi

  stray=$(jq -r '.extraKnownMarketplaces | to_entries[]
          | select(.value | has("sourceUrl"))
          | .key' "$f")
  if [[ -n "$stray" ]]; then
    while IFS= read -r name; do
      err "$f: marketplace '$name' uses sourceUrl, which is not a settings-schema field — use source.repo or source.url"
    done <<<"$stray"
  fi
done < <(find "$ROOT" -name settings.json \
           -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)

# --- 2. Templates and docs: catch the array form before it is ever scaffolded ---
while IFS= read -r hit; do
  err "$hit — array form of extraKnownMarketplaces in a template/doc; scaffolded repos inherit the bug"
done < <(grep -rn '"extraKnownMarketplaces"[[:space:]]*:[[:space:]]*\[' "$ROOT" \
           --include='*.md' --include='*.json' --include='*.sh' 2>/dev/null \
           | grep -v '/.git/' || true)

if (( FAILED > 0 )); then
  echo "Marketplace schema check failed ($FAILED error(s))" >&2
  echo "Reference: https://code.claude.com/docs/en/plugin-marketplaces" >&2
  exit 1
fi

echo "Marketplace schema check passed"
