#!/usr/bin/env bash
# Every hook in hooks/ must return promptly no matter what stdin does.
#
# WHY THIS IS A SUITE-WIDE SWEEP AND NOT A PER-HOOK CASE
#   `input=$(cat)` waits for EOF. In normal operation the harness supplies JSON
#   and closes the descriptor, so it returns instantly and the bug is invisible
#   — which is exactly why it spread to nineteen hooks unnoticed. A per-hook
#   test would only ever be written for the hook someone already suspected.
#   This enumerates hooks/ from disk, so a NEW hook that reads stdin unguarded
#   is caught the day it lands, without anyone remembering to add a case.
#
# WHY A STALLED READ IS A CORRECTNESS BUG, NOT A SLOWNESS BUG
#   A PreToolUse hook killed by the harness timeout writes nothing to stdout,
#   and per hooks/lib/hook-output.sh's contract Cursor fail-closes on empty
#   stdout. So a guard whose answer would have been ALLOW instead DENIES the
#   user's tool call — for a reason unrelated to what it guards. The two stdin
#   shapes below are the ones that produce that: no writer, and a terminal.
#
# NO EXTERNAL `timeout` BINARY: coreutils is absent on a stock macOS, this
# repo's primary platform. The watchdog is bash built-ins, and it is proven
# against a known-hanging command before any hook is judged.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
FAILED_NAMES=()

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
export HOME="$TMPROOT/home"
mkdir -p "$HOME/.claude"
# Keep the opt-in network check inert and claims contained.
unset CLAUDE_EXIT_PROXY CLAUDE_EXIT_PUBLIC_IP 2>/dev/null || true
export AGENT_CLAIM_DIR="$TMPROOT/claims"

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }

# run_with_timeout <seconds> <command...> — bash built-ins only; 124 on expiry.
run_with_timeout() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  (
    local waited=0
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$waited" -ge "$secs" ]; then kill -9 "$pid" 2>/dev/null; exit 0; fi
      sleep 1
      waited=$((waited + 1))
    done
  ) &
  local watcher=$!
  wait "$pid" 2>/dev/null
  local rc=$?
  kill "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  [ "$rc" = 137 ] && rc=124
  return "$rc"
}

echo "--- watchdog self-test (nothing below is meaningful without it) ---"
run_with_timeout 2 sleep 30
if [ $? != 124 ]; then
  echo "  FATAL: watchdog failed to kill a 30s sleep. Every case below would"
  echo "         pass vacuously. SKIPPING LOUDLY rather than reporting green."
  exit 1
fi
ok "watchdog kills an over-running command and reports 124"

# The hook's own exit status is irrelevant here — a hook handed an empty
# payload may legitimately exit non-zero ("missing cwd"). The ONLY question is
# whether it returned at all.
# NEVER RUN A HOOK FROM THE REAL REPO.
#   A hook handed an empty payload has no cwd to work from, and a hook that
#   then falls back to the process's working directory will act on whatever
#   repository the test happens to be launched in — the developer's checkout.
#   This suite ran hooks in place and registered two stray worktrees and two
#   `wt/session*` branches in the real repo before that was caught. The hooks
#   are fixed to stand down without a cwd; running from a scratch directory is
#   the second lock, so a future hook that reintroduces the fallback damages
#   nothing but a temp dir.
SCRATCH_CWD="$TMPROOT/scratch"
mkdir -p "$SCRATCH_CWD"

returns_promptly() {
  local hook="$1" label="$2" stdin_spec="$3" secs="${4:-6}"
  local name
  name="$(basename "$hook") [$label]"
  run_with_timeout "$secs" bash -c 'cd "$2" || exit 1; bash "$1" '"$stdin_spec"' >/dev/null 2>&1' _ "$hook" "$SCRATCH_CWD"
  if [ $? = 124 ]; then
    bad "$name" "TIMED OUT after ${secs}s — this hook blocks on stdin"
    return 1
  fi
  ok "$name"
}

# `mapfile` is bash 4+; macOS ships bash 3.2 and is this repo's primary
# platform, so the list is built with a plain read loop.
HOOKS=()
while IFS= read -r _h; do
  [ -n "$_h" ] && HOOKS+=("$_h")
done < <(find "$ROOT/hooks" -maxdepth 1 -name '*.sh' | sort)
[ "${#HOOKS[@]}" -gt 0 ] || { echo "  FATAL: no hooks found under $ROOT/hooks"; exit 1; }
echo "--- ${#HOOKS[@]} hooks: stdin closed (</dev/null) ---"
for h in "${HOOKS[@]}"; do returns_promptly "$h" "no stdin" "</dev/null"; done

echo "--- ${#HOOKS[@]} hooks: stdin is an open pipe with no writer (the real hang) ---"
FIFO="$TMPROOT/fifo"
mkfifo "$FIFO"
for h in "${HOOKS[@]}"; do
  # A fresh holder per hook: the previous hook consumed nothing, but the writer
  # must outlive the read for the descriptor to stay open without EOF.
  sleep 12 > "$FIFO" &
  holder=$!
  returns_promptly "$h" "open pipe" "< '$FIFO'" 8
  kill "$holder" 2>/dev/null
  wait "$holder" 2>/dev/null
done

echo "--- a real payload still reaches the hook unchanged ---"

# The guard must still SEE its input: a bounded read that silently dropped the
# payload would pass every timing case above while breaking every hook.
# NOTE the filename: the guard's pattern is `*.lock`, which does NOT match
# `package-lock.json` — an easy assertion to get wrong, and a wrong one here
# would read as a regression in the stdin change rather than a bad expectation.
payload="$(jq -n '{tool_name:"Edit", tool_input:{file_path:"/tmp/x/yarn.lock"}, cwd:"/tmp"}')"
out="$(printf '%s' "$payload" | bash "$ROOT/hooks/guard-sensitive-files.sh" 2>/dev/null)"
if printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  ok "guard-sensitive-files still denies a lockfile edit (payload was received)"
else
  bad "guard-sensitive-files still denies a lockfile edit" "got: $out"
fi

# The converse, pinned so the guard is not mistaken for one that denies
# everything: a file matching no pattern is still allowed.
#
# The example used to be package-lock.json, which the old fixed glob happened
# not to match. It is a lockfile, so it is now denied on purpose; an ordinary
# source file is the honest "unmatched" case.
payload="$(jq -n '{tool_name:"Edit", tool_input:{file_path:"/tmp/x/src/util.ts"}, cwd:"/tmp"}')"
out="$(printf '%s' "$payload" | bash "$ROOT/hooks/guard-sensitive-files.sh" 2>/dev/null)"
if printf '%s' "$out" | jq -e '(.hookSpecificOutput.permissionDecision // "allow") == "allow"' >/dev/null 2>&1; then
  ok "an unmatched path is still allowed (the guard did not become deny-all)"
else
  bad "an unmatched path is still allowed" "got: $out"
fi

# Multi-line (pretty-printed) JSON must survive: `cat` preserves newlines, and
# a reader that joined lines could merge tokens or corrupt embedded strings.
#
# The path must be one the guard denies UNCONDITIONALLY, or this test would be
# measuring the guard's detection instead of its stdin read. dist/bundle.js is
# no longer such a path — it is denied only when git ignores it (see
# tests/test-shape.sh) — so a lockfile carries the payload here.
pretty="$(jq -n '{tool_name:"Edit", tool_input:{file_path:"/tmp/x/deps.lock"}, cwd:"/tmp"}')"
out="$(printf '%s\n' "$pretty" | bash "$ROOT/hooks/guard-sensitive-files.sh" 2>/dev/null)"
if printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  ok "multi-line pretty-printed JSON payload survives the bounded read"
else
  bad "multi-line pretty-printed JSON payload survives the bounded read" "got: $out"
fi

# And an allow decision still comes back as valid JSON — Cursor fail-closes on
# empty stdout, so "allowed" must be spoken, never implied by silence.
allow="$(jq -n '{tool_name:"Edit", tool_input:{file_path:"/tmp/x/src/app.ts"}, cwd:"/tmp"}')"
out="$(printf '%s' "$allow" | bash "$ROOT/hooks/guard-sensitive-files.sh" 2>/dev/null)"
if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
  ok "an allow decision is still emitted as valid JSON"
else
  bad "an allow decision is still emitted as valid JSON" "got: '$out'"
fi

echo "--- an empty payload creates nothing (worktree leak regression) ---"

# A local clone stands in for "the developer's repo": if a hook reaches for a
# repository it was never given, it damages this instead of the real one, and
# the assertion sees it. Asserting on the real repo would be both unsafe and
# useless — the leak it is looking for is already there.
LEAKREPO="$TMPROOT/leakrepo"
if git clone -q --local --no-hardlinks "$ROOT" "$LEAKREPO" 2>/dev/null; then
  before="$(git -C "$LEAKREPO" worktree list | wc -l | tr -d ' ')"
  for h in "$ROOT/hooks/capture-task-slug.sh" "$ROOT/hooks/session-init.sh" "$ROOT/hooks/worktree-create.sh"; do
    ( cd "$LEAKREPO" && bash "$h" </dev/null >/dev/null 2>&1 )
  done
  after="$(git -C "$LEAKREPO" worktree list | wc -l | tr -d ' ')"
  if [ "$before" = "$after" ]; then
    ok "an empty payload registers no worktree (was: wt/session, wt/session-)"
  else
    bad "an empty payload registers no worktree" \
        "worktree count went $before -> $after: $(git -C "$LEAKREPO" worktree list | tail -n +2 | tr '\n' ' ')"
  fi

  # The empty-CWD path was the first trigger found. These are the others: a
  # payload that parses but carries no task, and one that does not parse at
  # all. Each reaches the slug derivation by a different route, and each used
  # to invent a placeholder there. Case 2 is the one that produced BOTH
  # observed branches from a single call (`wt/session-`, then `wt/session`
  # after the self-heal re-slugify).
  export HOME="$TMPROOT/leakhome2"; mkdir -p "$HOME/.claude"
  ( cd "$LEAKREPO" && jq -n --arg c "$LEAKREPO" '{cwd:$c, prompt:"   ", session_id:""}' \
      | bash "$ROOT/hooks/capture-task-slug.sh" >/dev/null 2>&1 )
  ( cd "$LEAKREPO" && jq -n --arg c "$LEAKREPO" '{cwd:$c}' \
      | bash "$ROOT/hooks/capture-task-slug.sh" >/dev/null 2>&1 )
  ( cd "$LEAKREPO" && printf 'this is not json' \
      | bash "$ROOT/hooks/capture-task-slug.sh" >/dev/null 2>&1 )
  after2="$(git -C "$LEAKREPO" worktree list | wc -l | tr -d ' ')"
  if [ "$before" = "$after2" ]; then
    ok "a task-less payload (blank prompt / no session_id / non-JSON) creates no worktree"
  else
    bad "a task-less payload creates no worktree" \
        "count went $before -> $after2: $(git -C "$LEAKREPO" worktree list | tail -n +2 | tr '\n' ' ')"
  fi

  # An unparseable payload must not merely avoid damage — it must exit 0, or the
  # harness treats a content-free prompt as a hook failure.
  ( cd "$LEAKREPO" && printf 'this is not json' | bash "$ROOT/hooks/capture-task-slug.sh" >/dev/null 2>&1 )
  rc=$?
  if [ "$rc" = 0 ]; then
    ok "an unparseable payload exits 0 (harness not disrupted)"
  else
    bad "an unparseable payload exits 0" "exited $rc"
  fi

  strays="$(git -C "$LEAKREPO" branch --list 'wt/*' | tr -d ' ' | tr '\n' ' ')"
  if [ -z "$strays" ]; then
    ok "an empty payload creates no wt/* branch"
  else
    bad "an empty payload creates no wt/* branch" "created: $strays"
  fi

  # And the positive half: a WELL-FORMED payload must still create one, or the
  # fix above would "pass" by breaking the feature outright.
  export HOME="$TMPROOT/leakhome"; mkdir -p "$HOME/.claude"
  ( cd "$LEAKREPO" && jq -n --arg c "$LEAKREPO" '{session_id:"leak-1", prompt:"add a widget", cwd:$c}' \
      | bash "$ROOT/hooks/capture-task-slug.sh" >/dev/null 2>&1 )
  if [ -d "$HOME/.claude/worktrees/leakrepo/add-a-widget" ]; then
    ok "a well-formed payload still creates its worktree"
  else
    bad "a well-formed payload still creates its worktree" "nothing at \$HOME/.claude/worktrees/leakrepo/add-a-widget"
  fi
else
  bad "worktree leak regression" "could not clone $ROOT to test against"
fi

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'failing: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
