#!/usr/bin/env bash
# check-doc-claims.sh — assert prose claims match the repo they describe.
#
# Usage:
#   check-doc-claims.sh [repo-root]
#   check-doc-claims.sh -h | --help
#
# Two classes of claim rot this catches, both observed in this repo:
#
#   1. Skill count. "26 skills" is asserted in README, CLAUDE.md, AGENTS.md and every
#      per-target install guide, and "26 bundled skills" in every plugin/marketplace
#      manifest description — the string users see in the install UI. Adding one skill
#      silently falsifies all of them, and nothing failed: AGENTS.md sat at "25 skills"
#      across two releases, and the manifests drifted twice for the same reason.
#   2. Target coverage. Every target in platform-targets.json supported_targets must be
#      named in README and AGENTS.md, and must declare an install_doc that exists.
#      A target added to the JSON but missing from the prose is invisible to users.
#
# Exit 0 if checks pass; 1 on failure.
set -euo pipefail

usage() {
  sed -n '2,18p' "$0" | sed -E 's/^# ?//'
  exit "${1:-0}"
}
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

ROOT="$(cd "${1:-.}" && pwd)"
FAILED=0
TARGETS_JSON="$ROOT/docs/engineering/build-and-release/platform-targets.json"

err() { echo "ERROR: $*" >&2; FAILED=$(( FAILED + 1 )); }

# A count inside double quotes is being *reported*, not asserted — changelog entries
# quote the stale value they fixed ("16 skills in 7 domains"). Skip those; a real claim
# is written as bare prose.
is_quoted() { [[ "$1" =~ \"[^\"]*[0-9]+\ (bundled\ )?skills[^\"]*\" ]]; }

# --- 1. Skill count ---
# Shipped skills = SKILL.md under skills/, excluding contract test fixtures.
actual=$(find "$ROOT/skills" -name SKILL.md 2>/dev/null \
         | grep -v '_contract/fixtures' | wc -l | tr -d ' ')

if [[ "$actual" == "0" ]]; then
  err "found 0 shipped skills under skills/ — refusing to validate counts against an empty tree"
else
  while IFS= read -r hit; do
    file="${hit%%:*}"
    is_quoted "$hit" && continue
    claimed=$(sed -E 's/.*[^0-9]([0-9]+) skills.*/\1/' <<<"$hit")
    [[ "$claimed" =~ ^[0-9]+$ ]] || continue
    if [[ "$claimed" != "$actual" ]]; then
      err "${file#"$ROOT"/} claims $claimed skills; the tree ships $actual"
    fi
  done < <(grep -rn -E '[0-9]+ skills' "$ROOT" --include='*.md' 2>/dev/null \
             | grep -v '/.git/' | grep -v '_contract/fixtures' || true)

  # Manifest descriptions carry the same claim as "N bundled skills". These render in
  # the plugin install UI, so a stale count is user-visible on every target.
  while IFS= read -r hit; do
    file="${hit%%:*}"
    claimed=$(sed -E 's/.*[^0-9]([0-9]+) bundled skills.*/\1/' <<<"$hit")
    [[ "$claimed" =~ ^[0-9]+$ ]] || continue
    if [[ "$claimed" != "$actual" ]]; then
      err "${file#"$ROOT"/} claims $claimed bundled skills; the tree ships $actual"
    fi
  done < <(grep -rn -E '[0-9]+ bundled skills' "$ROOT" --include='*.json' 2>/dev/null \
             | grep -v '/.git/' | grep -v '_contract/fixtures' || true)
fi

# --- 2. Target coverage ---
if [[ -f "$TARGETS_JSON" ]]; then
  jq empty "$TARGETS_JSON" 2>/dev/null || { err "$TARGETS_JSON: invalid JSON"; }

  # Display names for prose matching; keys are snake_case in JSON.
  display_name() {
    case "$1" in
      claude_code) echo "Claude Code" ;;
      cursor)      echo "Cursor" ;;
      codex)       echo "Codex" ;;
      opencode)    echo "OpenCode" ;;
      *)           echo "$1" ;;
    esac
  }

  targets=$(jq -r '(.supported_targets // []) | .[]' "$TARGETS_JSON" 2>/dev/null || true)
  for key in $targets; do
    name=$(display_name "$key")

    for doc in README.md AGENTS.md; do
      [[ -f "$ROOT/$doc" ]] || continue
      grep -qF "$name" "$ROOT/$doc" \
        || err "$doc never names supported target '$name' — users cannot discover it"
    done

    # install_doc must be declared and must exist.
    install_doc=$(jq -r ".targets.\"$key\".install_doc // empty" "$TARGETS_JSON")
    if [[ -z "$install_doc" ]]; then
      err "platform-targets.json: target '$key' declares no install_doc"
    elif [[ ! -f "$ROOT/$install_doc" ]]; then
      err "platform-targets.json: target '$key' install_doc points at missing file '$install_doc'"
    fi
  done
fi

if (( FAILED > 0 )); then
  echo "Doc claims check failed ($FAILED error(s))" >&2
  exit 1
fi

echo "Doc claims check passed ($actual skills, targets consistent)"
