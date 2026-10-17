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

section "--fix is a live write, never a dry one"
judge "--fix with --description is refused" 2 "$(bash "$CHECK" "$ROOT" --fix --description "x" >/dev/null 2>&1; echo $?)"
judge "--fix with --warn is refused" 2 "$(bash "$CHECK" "$ROOT" --fix --warn >/dev/null 2>&1; echo $?)"
judge "--help names --fix" yes "$(has "$(bash "$CHECK" --help)" "--fix")"
judge "--help names --warn" yes "$(has "$(bash "$CHECK" --help)" "--warn")"

# A stub gh on PATH: GET answers with $STUB_DESC (or fails when STUB_GET_FAILS=1), PATCH
# records the description it was given. Exercises the write without a token or network.
STUB="$(mktemp -d)"; trap 'rm -rf "$STUB"' EXIT
cat > "$STUB/gh" <<'GH'
#!/usr/bin/env bash
if [ "$1" = api ] && [ "$2" = -X ] && [ "$3" = PATCH ]; then
  printf '%s\n' "${6#description=}" > "$STUB_LOG"; [ "${STUB_PATCH_FAILS:-0}" = 1 ] && exit 1; exit 0
fi
[ "${STUB_GET_FAILS:-0}" = 1 ] && exit 1
jq -n --arg d "$STUB_DESC" '{description: $d}'
GH
chmod +x "$STUB/gh"
fix_with() { # <live description> -> exit code; the PATCHed text lands in $STUB_LOG
  : > "$STUB_LOG"
  STUB_DESC="$1" PATH="$STUB:$PATH" GITHUB_REPOSITORY=o/r bash "$CHECK" "$ROOT" --fix >/dev/null 2>&1; echo $?
}
export STUB_LOG="$STUB/patched"
judge "--fix leaves a correct description alone (exit 0)" 0 "$(fix_with "$skills skills, $agents specialist agents")"
judge "  and writes nothing" yes "$(if [ ! -s "$STUB_LOG" ]; then echo yes; else echo no; fi)"
judge "--fix patches a stale count in place" 0 "$(fix_with "A toolkit — $((skills - 1)) skills, $agents specialist agents — shipped.")"
judge "  keeping the rest of the sentence" yes "$(has "$(cat "$STUB_LOG")" "A toolkit — $skills skills, $agents specialist agents — shipped.")"
judge "--fix replaces a description naming no count with the canonical sentence" 0 "$(fix_with "A portable agent toolkit.")"
judge "  which names both counts" yes "$(has "$(cat "$STUB_LOG")" "$skills skills, $agents specialist agents")"
judge "--fix replaces a description naming only one count" 0 "$(fix_with "$skills skills and some agents")"
judge "  so the written text names both" yes "$(has "$(cat "$STUB_LOG")" "$skills skills, $agents specialist agents")"
judge "--fix writes the canonical sentence for an empty description" 0 "$(fix_with "")"
judge "  naming both counts" yes "$(has "$(cat "$STUB_LOG")" "$skills skills, $agents specialist agents")"
judge "the written text passes the check itself" 0 "$(rc_of "$(cat "$STUB_LOG")")"
judge "--fix fails when the PATCH is refused (a Contents-only token)" 1 "$(STUB_PATCH_FAILS=1 fix_with "$((skills - 1)) skills, $agents specialist agents")"
judge "--fix fails, never skips, when the read fails (no or revoked token)" 1 "$(STUB_GET_FAILS=1 fix_with "x")"
judge "--fix fails, never skips, without gh on PATH" 1 "$(cd "$STUB" && PATH=/nonexistent:/usr/bin:/bin GITHUB_REPOSITORY=o/r bash "$CHECK" "$ROOT" --fix >/dev/null 2>&1; echo $?)"
judge "the plain check still SKIPs without gh (exit 0)" 0 "$(PATH=/nonexistent:/usr/bin:/bin GITHUB_REPOSITORY=o/r bash "$CHECK" "$ROOT" >/dev/null 2>&1; echo $?)"

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
