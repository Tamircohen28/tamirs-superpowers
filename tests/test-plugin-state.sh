#!/usr/bin/env bash
# Tests for hooks/lib/plugin-state.sh and the hooks that use it.
#
# WHAT THESE PIN
#   1. With CLAUDE_PLUGIN_DATA set, state lands under it. That is the whole point:
#      the host directory survives plugin updates, the old cache path does not.
#   2. WITHOUT it, state lands exactly where it used to. hooks/hooks.json is loaded
#      by the Codex CLI as well, and Codex exports no such variable — a hook that
#      assumed it would resolve an empty path and write to the filesystem root, or
#      silently stop remembering anything. The fallback is not a nicety.
#   3. The resolver never fails, even pointed at an unwritable base, because every
#      caller is an advisory hook that must not break a session over its own cache.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/hooks/lib/plugin-state.sh"
PASS=0; FAIL=0; FAILED=()
[ -f "$LIB" ] || { echo "FATAL: $LIB missing"; exit 1; }
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); FAILED+=("$1"); echo "  FAIL $1 — $2"; }

echo "--- plugin-state: host variable is honoured ---"
PD="$TMPROOT/hostdata"
got="$(CLAUDE_PLUGIN_DATA="$PD" bash -c 'source "$1"; plugin_state_dir skill-suggest' _ "$LIB")"
[ "$got" = "$PD/skill-suggest" ] && ok "resolves under CLAUDE_PLUGIN_DATA" || bad "resolves under CLAUDE_PLUGIN_DATA" "got: $got"
[ -d "$got" ] && ok "creates the directory on demand" || bad "creates the directory on demand" "not created"

got2="$(CLAUDE_PLUGIN_DATA="$PD/" bash -c 'source "$1"; plugin_state_dir x' _ "$LIB")"
[ "$got2" = "$PD/x" ] && ok "a trailing slash does not double up" || bad "a trailing slash does not double up" "got: $got2"

echo "--- plugin-state: fallback when the host provides nothing (Codex) ---"
got3="$(env -u CLAUDE_PLUGIN_DATA bash -c 'source "$1"; plugin_state_dir skill-suggest' _ "$LIB")"
case "$got3" in
  "$HOME/.claude/cache/skill-suggest") ok "falls back to the previous cache path" ;;
  *) bad "falls back to the previous cache path" "got: $got3" ;;
esac
case "$got3" in
  /*/*) ok "fallback is never a bare root path" ;;
  *) bad "fallback is never a bare root path" "got: $got3" ;;
esac

echo "--- plugin-state: never fails an advisory hook ---"
UNW="$TMPROOT/unwritable"; mkdir -p "$UNW"; chmod 500 "$UNW"
if CLAUDE_PLUGIN_DATA="$UNW" bash -c 'source "$1"; plugin_state_dir s >/dev/null' _ "$LIB"; then
  ok "returns 0 even when the directory cannot be created"
else
  bad "returns 0 even when the directory cannot be created" "non-zero exit"
fi
chmod 700 "$UNW"

echo "--- consumers actually use it ---"
for f in hooks/skill-suggest.sh hooks/show-changelog.sh; do
  if grep -q 'plugin_state_dir' "$ROOT/$f"; then ok "$f uses plugin_state_dir"
  else bad "$f uses plugin_state_dir" "still hard-codes a path"; fi
  if grep -qE '\$\{?HOME\}?/\.claude/cache/(skill-suggest|changelog|last_changelog)' "$ROOT/$f"; then
    bad "$f no longer hard-codes the cache path" "hard-coded path still present"
  else ok "$f no longer hard-codes the cache path"; fi
done

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -gt 0 ] && { printf 'failing:'; printf ' %s' "${FAILED[@]}"; echo; exit 1; }
exit 0
