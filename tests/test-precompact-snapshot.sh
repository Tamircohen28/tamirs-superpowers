#!/usr/bin/env bash
# Tests for hooks/precompact-snapshot.sh (PreCompact).
#
# WHAT THESE PIN
#   1. The FILE is the deliverable, not the message. `hookSpecificOutput` is not
#      documented for PreCompact and `systemMessage` may be discarded by the
#      host, so the snapshot on disk is the only thing guaranteed to survive.
#      A test that only asserted on stdout would pass while the hook wrote
#      nothing — i.e. while it did nothing useful at all.
#   2. It stays silent, and writes nothing, when there is no working state.
#   3. It never hangs, never exits non-zero, and never blocks a compaction.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
H="$ROOT/hooks/precompact-snapshot.sh"

PASS=0; FAIL=0; FAILED_NAMES=()
[ -f "$H" ] || { echo "FATAL: hook not found at $H"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required"; exit 1; }

TMPROOT="$(mktemp -d)"
cleanup() { [ -n "${TMPROOT:-}" ] && rm -rf "$TMPROOT"; }
trap cleanup EXIT

ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); echo "  FAIL $1 — $2"; }

mkrepo() {
  local d="$1"; mkdir -p "$d"; git -C "$d" init -q
  git -C "$d" config user.email t@e.x; git -C "$d" config user.name t
}

echo "--- precompact: work in flight => writes the snapshot file ---"

R="$TMPROOT/dirty"; mkrepo "$R"
echo seed > "$R/seed.txt"; git -C "$R" add -A >/dev/null 2>&1
git -C "$R" commit -qm "seed commit" >/dev/null 2>&1
echo changed > "$R/changed.txt"

out="$(printf '{"cwd":"%s","trigger":"auto"}' "$R" | bash "$H" 2>&1)"
SNAP="$R/.dev-files/compaction/latest.md"

if [ -f "$SNAP" ]; then ok "writes the snapshot file"
else bad "writes the snapshot file" "no file at $SNAP; stdout: $out"; fi

if grep -q "changed.txt" "$SNAP" 2>/dev/null; then ok "the snapshot names the uncommitted file"
else bad "the snapshot names the uncommitted file" "$(cat "$SNAP" 2>/dev/null)"; fi

if grep -q "seed commit" "$SNAP" 2>/dev/null; then ok "the snapshot carries recent commit subjects"
else bad "the snapshot carries recent commit subjects" "$(cat "$SNAP" 2>/dev/null)"; fi

if grep -q "trigger: auto" "$SNAP" 2>/dev/null; then ok "the snapshot records what triggered compaction"
else bad "the snapshot records what triggered compaction" "$(cat "$SNAP" 2>/dev/null)"; fi

msg="$(printf '%s' "$out" | jq -r '.systemMessage // empty' 2>/dev/null)"
case "$msg" in
  *".dev-files/compaction/latest.md"*) ok "the message points at the file it wrote" ;;
  *) bad "the message points at the file it wrote" "got: $msg" ;;
esac

echo "--- precompact: an open objective alone is enough ---"

O="$TMPROOT/obj"; mkrepo "$O"; mkdir -p "$O/.dev-files/objectives/auth-system"
printf '{"cwd":"%s","trigger":"manual"}' "$O" | bash "$H" >/dev/null 2>&1
if grep -q "auth-system" "$O/.dev-files/compaction/latest.md" 2>/dev/null; then
  ok "snapshots a clean tree that has an open objective"
else
  bad "snapshots a clean tree that has an open objective" "no objective in snapshot"
fi

echo "--- precompact: nothing in flight => writes nothing, says nothing ---"

C="$TMPROOT/clean"; mkrepo "$C"
out="$(printf '{"cwd":"%s"}' "$C" | bash "$H" 2>&1)"
if printf '%s' "$out" | jq -e '.suppressOutput == true' >/dev/null 2>&1; then
  ok "suppresses output on a clean repo"
else bad "suppresses output on a clean repo" "got: $out"; fi
if [ ! -e "$C/.dev-files/compaction/latest.md" ]; then
  ok "writes no file when there is nothing to save"
else bad "writes no file when there is nothing to save" "file was created anyway"; fi

N="$TMPROOT/nogit"; mkdir -p "$N"
out="$(printf '{"cwd":"%s"}' "$N" | bash "$H" 2>&1)"
if printf '%s' "$out" | jq -e '.suppressOutput == true' >/dev/null 2>&1; then
  ok "suppresses output outside a git repo"
else bad "suppresses output outside a git repo" "got: $out"; fi

echo "--- precompact: never blocks a compaction ---"

for label in empty malformed devnull; do
  start="$(date +%s)"
  case "$label" in
    empty)     printf ''                | bash "$H" >/dev/null 2>&1; rc=$? ;;
    malformed) printf 'not json at all' | bash "$H" >/dev/null 2>&1; rc=$? ;;
    devnull)   bash "$H" </dev/null     >/dev/null 2>&1; rc=$? ;;
  esac
  elapsed=$(( $(date +%s) - start ))
  if [ "$rc" -eq 0 ] && [ "$elapsed" -lt 5 ]; then
    ok "$label stdin exits 0 promptly (${elapsed}s)"
  else bad "$label stdin exits 0 promptly" "rc=$rc elapsed=${elapsed}s"; fi
done

echo "--- precompact: wired ---"
CMD="$(jq -r '(.hooks.PreCompact // .PreCompact // [])[0].hooks[0].command // empty' "$ROOT/hooks/hooks.json" 2>/dev/null)"
case "$CMD" in
  *precompact-snapshot.sh) ok "hooks.json wires PreCompact to this hook" ;;
  *) bad "hooks.json wires PreCompact to this hook" "got: $CMD" ;;
esac

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then printf 'failing:'; printf ' %s' "${FAILED_NAMES[@]}"; echo; exit 1; fi
exit 0
