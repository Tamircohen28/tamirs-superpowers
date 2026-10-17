#!/usr/bin/env bash
# The GitHub repository description must name the skill and agent counts the tree
# ships (it said 29 skills after 5.0.0 shipped the thirtieth). Hermetic through
# --description; the live read is exercised only when gh and a token are present.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
CHECK="$ROOT/scripts/check-repo-description.sh"
skills=$(find "$ROOT/skills" -name SKILL.md | grep -v '_contract/fixtures' | wc -l | tr -d ' ')
agents=$(find "$ROOT/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
rc_of() { bash "$CHECK" "$ROOT" --description "$1" >/dev/null 2>&1; echo $?; }

section "counts in the description are held to the tree"
judge "the tree's own counts pass" 0 "$(rc_of "A toolkit — $skills skills, $agents specialist agents — shipped everywhere.")"
judge "role-based agents is the README's wording and passes too" 0 "$(rc_of "$skills skills, $agents role-based agents")"
judge "a stale skill count fails" 1 "$(rc_of "A toolkit — $((skills - 1)) skills, $agents specialist agents.")"
judge "a stale agent count fails" 1 "$(rc_of "$skills skills, $((agents + 1)) specialist agents")"
judge "a description with no counts fails" 1 "$(rc_of "A portable agent toolkit.")"
judge "an absent (empty) description fails by hand" 1 "$(rc_of "")"
judge "an absent description honours --warn (exit 0)" 0 "$(bash "$CHECK" "$ROOT" --description "" --warn >/dev/null 2>&1; echo $?)"
judge "a stale count honours --warn (exit 0)" 0 "$(bash "$CHECK" "$ROOT" --description "$((skills - 1)) skills, $agents specialist agents" --warn >/dev/null 2>&1; echo $?)"
out="$(bash "$CHECK" "$ROOT" --description "" --warn 2>&1)"
judge "the absent-description warning proposes a full description with the counts" yes "$(has "$out" "$skills skills, $agents specialist agents")"
out="$(bash "$CHECK" "$ROOT" --description "$((skills - 1)) skills, $agents specialist agents" 2>&1)"
judge "the failure prints the corrected description" yes "$(has "$out" "$skills skills, $agents specialist agents")"
judge "and the gh repo edit command" yes "$(has "$out" "gh repo edit")"

section "live read"
if command -v gh >/dev/null 2>&1 && gh api repos/Tamircohen28/tamirs-superpowers >/dev/null 2>&1; then
  out="$(bash "$CHECK" "$ROOT" 2>&1)"; rc=$?
  case "$out" in *SKIP*) skip "live description" "gh present but the read was skipped: $out" ;;
    *) judge "the live description matches the tree (or says exactly how to fix it)" yes "$(if [ "$rc" = 0 ] || [ "$(has "$out" "gh repo edit")" = yes ]; then echo yes; else echo no; fi)" ;;
  esac
else
  skip "live description" "no gh or no token"
fi
harness_summary
