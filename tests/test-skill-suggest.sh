#!/usr/bin/env bash
# hooks/skill-suggest.sh — behaviour tests.
#
# WHAT THESE PIN DOWN, AND WHY EACH ONE IS HERE
#   This hook replaces plugin-version-watch.sh, which fired correctly for months
#   and produced zero skill invocations. Its three defects are each a test below,
#   so the replacement cannot regress into the same shape:
#
#     `emits additionalContext, never systemMessage`
#         plugin-version-watch emitted systemMessage, which renders in the USER's
#         UI and is never injected into the MODEL's context. A hook meant to make
#         the agent act that talks only to the user is inert by construction.
#     `one suggestion per skill per session`
#         The failure mode on the other side: a nudge that fires every turn stops
#         being read.
#     `a fire in one repo does not silence another`
#         plugin-version-watch's cache was one global file with no repo key, so
#         firing in repo A suppressed repo B for 24h.
#
#   Plus the two properties every hook here must hold: silent when it has
#   nothing to say, and never blocking — including with no stdin at all, which
#   is the shape that hangs a `$(cat)`-based hook until the harness kills it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/skill-suggest.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
export HOME="$TMPROOT/home"
mkdir -p "$HOME/.claude"

# A plain directory, not a git repo: keeps the platform-sync `git diff` probe
# and the switch-dev `.dev-files/` probe out of the prompt-regex cases.
WORKDIR="$TMPROOT/work"
mkdir -p "$WORKDIR"

# run <session_id> <prompt> [cwd] — hook stdout.
run() {
  local sid="$1" prompt="$2" cwd="${3:-$WORKDIR}"
  jq -n --arg p "$prompt" --arg s "$sid" --arg c "$cwd" \
    '{prompt:$p, session_id:$s, cwd:$c}' | bash "$HOOK" 2>/dev/null
}

echo "=== hooks/skill-suggest.sh ==="

# --- fires on a cost prompt -------------------------------------------------
out="$(run s-cost 'why is this session so expensive, how many tokens did that cost?')"
if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("session-report")' >/dev/null 2>&1; then
  ok "fires on a cost prompt (suggests session-report)"
else
  bad "fires on a cost prompt" "no session-report in output: ${out:-<empty>}"
fi

# --- fires on a stack trace -------------------------------------------------
TRACE='Traceback (most recent call last):
  File "/srv/app/handler.py", line 42, in dispatch
    return self._route(req)
AttributeError: NoneType object has no attribute route'
out="$(run s-trace "here is what I get: $TRACE")"
if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("targeted-debug")' >/dev/null 2>&1; then
  ok "fires on a pasted stack trace (suggests targeted-debug)"
else
  bad "fires on a pasted stack trace" "no targeted-debug in output: ${out:-<empty>}"
fi

# --- Go panic shape, different language, same detector ----------------------
out="$(run s-panic 'panic: runtime error: invalid memory address or nil pointer dereference')"
if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("targeted-debug")' >/dev/null 2>&1; then
  ok "fires on a Go panic (shape detection is not Python-only)"
else
  bad "fires on a Go panic" "no targeted-debug in output: ${out:-<empty>}"
fi

# --- silent on an unrelated prompt ------------------------------------------
out="$(run s-quiet 'rename the helper function in utils.go to parseHeader')"
if [ -z "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then
  ok "silent on an unrelated prompt"
else
  bad "silent on an unrelated prompt" "expected no output, got: $out"
fi

# --- emits additionalContext, never systemMessage ---------------------------
# The defect that made plugin-version-watch.sh inert.
out="$(run s-channel 'what are my token costs this week?')"
if printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null 2>&1 \
   && printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | type == "string" and length > 0' >/dev/null 2>&1 \
   && printf '%s' "$out" | jq -e 'has("systemMessage") | not' >/dev/null 2>&1; then
  ok "emits valid JSON with additionalContext and no systemMessage"
else
  bad "emits valid JSON with additionalContext and no systemMessage" "got: ${out:-<empty>}"
fi

# --- one suggestion per skill per session -----------------------------------
first="$(run s-once 'how many tokens is this costing me?')"
second="$(run s-once 'seriously though, what is the token cost here?')"
if printf '%s' "$first" | jq -e '.hookSpecificOutput.additionalContext | test("session-report")' >/dev/null 2>&1 \
   && [ -z "$(printf '%s' "$second" | tr -d '[:space:]')" ]; then
  ok "suggests a skill only once per session"
else
  bad "suggests a skill only once per session" "first=${first:-<empty>} second=${second:-<empty>}"
fi

# --- a different session gets its own suggestion ----------------------------
out="$(run s-other 'what is the token cost here?')"
if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("session-report")' >/dev/null 2>&1; then
  ok "a new session is not silenced by an earlier session's marker"
else
  bad "a new session is not silenced by an earlier session's marker" "got: ${out:-<empty>}"
fi

# --- the repo key: a fire in one repo does not silence another --------------
# plugin-version-watch.sh's defect 3, pinned so it cannot come back.
OTHER="$TMPROOT/other-repo"
mkdir -p "$OTHER"
out="$(run s-once 'and what did that cost in tokens?' "$OTHER")"
if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("session-report")' >/dev/null 2>&1; then
  ok "same session in a different repo still gets the suggestion"
else
  bad "same session in a different repo still gets the suggestion" "got: ${out:-<empty>}"
fi

# --- never blocks with no stdin ---------------------------------------------
# No writer on stdin: must return promptly and exit 0, not hang until killed.
"$ROOT/hooks/skill-suggest.sh" < /dev/null > "$TMPROOT/nostdin.out" 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$(tr -d '[:space:]' < "$TMPROOT/nostdin.out")" ]; then
  ok "exits 0 and stays silent with no stdin"
else
  bad "exits 0 and stays silent with no stdin" "rc=$rc out=$(cat "$TMPROOT/nostdin.out")"
fi

# --- malformed stdin is not an error either ---------------------------------
printf 'not json at all\n' | bash "$HOOK" > "$TMPROOT/junk.out" 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  ok "exits 0 on non-JSON stdin"
else
  bad "exits 0 on non-JSON stdin" "rc=$rc out=$(cat "$TMPROOT/junk.out")"
fi

echo
printf 'skill-suggest: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'failed: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
