#!/usr/bin/env bash
# Tests for hooks/check-done.sh validation-tier gating.
#
# WHAT IS BEING PINNED
#   The hook is advisory, so "did it block?" is not the assertion — the
#   assertion is WHAT IT ASKED FOR. A worker told to prove CI is green has been
#   handed a tier-3 demand it cannot satisfy and was never meant to: its
#   contract ends at commit + handoff. So each case asserts both that the right
#   tier was recognized AND, for tier 1, that the CI demand is absent.
#
#   The no-tier-context case asserts the ORIGINAL message survives verbatim in
#   intent: this hook shipped to real users, and a repo with no objective model
#   must see exactly what it saw before.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/check-done.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required"; exit 1; }
[ -f "$HOOK" ] || { echo "FATAL: hook not found at $HOOK"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
export HOME="$TMPROOT/home"
mkdir -p "$HOME/.claude"

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }
has() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }
judge() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi; }

REPO="$TMPROOT/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@e
git -C "$REPO" config user.name t
git -C "$REPO" commit -q --allow-empty -m init
# An uncommitted code change is the precondition for the hook saying anything.
printf 'echo hi\n' > "$REPO/script.sh"

# run_check [env assignments...] — the hook's stderr (its only output channel).
run_check() {
  ( cd "$REPO" && env "$@" bash "$HOOK" </dev/null 2>&1 >/dev/null )
}

echo "--- no tier context: the original message is preserved ---"

out="$(run_check X=1)"
judge "still warns about changed files" yes "$(has "$out" "changed code file(s)")"
judge "still demands CI evidence" yes "$(has "$out" "gh pr checks")"
judge "carries no tier label" no "$(has "$out" "tier ")"

echo "--- tier 1 (worker): relevant tests only, no CI demand ---"

git -C "$REPO" checkout -q -B worker/auth-system/001
out="$(run_check X=1)"
judge "recognized as tier 1 from the worker/* branch" yes "$(has "$out" "tier 1, worker")"
judge "does NOT demand green CI" no "$(has "$out" "gh pr checks")"
judge "says tier 3 failure is not a tier 1 failure" yes \
  "$(has "$out" "not a tier-1 failure")"
judge "ends the worker at commit + handoff, not a PR" yes \
  "$(has "$out" "not at a PR")"

echo "--- tier 2 (integration): full suite over combined work ---"

git -C "$REPO" checkout -q -B objective/auth-system
out="$(run_check X=1)"
judge "recognized as tier 2 from the objective/* branch" yes "$(has "$out" "tier 2, integration")"
judge "asks for the combined diff" yes "$(has "$out" "combined diff")"
judge "still defers to tier 3" yes "$(has "$out" "final word")"

echo "--- explicit tier wins over the branch ---"

out="$(run_check SUPERPOWERS_VALIDATION_TIER=3)"
judge "SUPERPOWERS_VALIDATION_TIER=3 overrides objective/*" yes "$(has "$out" "tier 3, delivery")"
judge "tier 3 demands CI evidence" yes "$(has "$out" "gh pr checks")"

out="$(run_check SUPERPOWERS_VALIDATION_TIER=worker)"
judge "the tier accepts names as well as numbers" yes "$(has "$out" "tier 1, worker")"

out="$(run_check SUPERPOWERS_VALIDATION_TIER=0)"
judge "tier 0 asks only for cheap edit-time checks" yes "$(has "$out" "tier 0, edit-time")"
judge "tier 0 explicitly forbids the full suite" yes "$(has "$out" "Do not run the full suite")"

echo "--- the task file supplies the tier when the branch cannot ---"

git -C "$REPO" checkout -q -B some-unrelated-branch
mkdir -p "$REPO/.dev-files/objectives/auth-system/tasks"
jq -n '{id:"auth-system", status:"active"}' > "$REPO/.dev-files/objectives/auth-system/objective.json"
jq -n '{id:"task-001", role:"implementer", validation_tier:"worker", status:"ready"}' \
  > "$REPO/.dev-files/objectives/auth-system/tasks/task-001.json"
out="$(run_check SUPERPOWERS_TASK_ID=task-001)"
judge "reads validation_tier from the task json" yes "$(has "$out" "tier 1, worker")"

echo "--- silence when there is nothing to warn about ---"

CLEAN="$TMPROOT/clean"
mkdir -p "$CLEAN"
git -C "$CLEAN" init -q -b main
git -C "$CLEAN" config user.email t@e
git -C "$CLEAN" config user.name t
git -C "$CLEAN" commit -q --allow-empty -m init
out="$( cd "$CLEAN" && bash "$HOOK" </dev/null 2>&1 >/dev/null )"
judge "a clean tree produces no reminder" "" "$out"

out="$( cd "$TMPROOT" && bash "$HOOK" </dev/null 2>&1 >/dev/null )"
judge "outside a git repo produces no reminder" "" "$out"

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'failing: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
