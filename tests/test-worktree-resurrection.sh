#!/usr/bin/env bash
# The session worktree lifecycle: created once, and a removal that STICKS.
#
# WHAT THIS PINS
#   capture-task-slug.sh used to run `[[ ! -d $worktree_path ]] && git worktree
#   add -B` on every prompt. That reads as "keep the worktree present" and
#   behaves as "undo every removal": a repo cleaned with `git worktree remove`
#   grew the worktree and its `wt/*` branch back on the next prompt, minutes
#   later, with nothing naming the actor. The plugin's own stale-worktree
#   retention pass was reversed the same way.
#
#   The fix splits the question by evidence. A prompt arriving says nothing
#   about whether the session will touch the repo, so the prompt hook creates
#   once and then retires. An Edit is real evidence, so the edit guard rebuilds
#   at that moment — and still denies, but with a destination that exists.
#
# WHY END-TO-END
#   Every case runs the real hooks against a real temporary repo with real git
#   worktrees, and asserts on the real side effect. A unit test of
#   is_live_worktree would pass against a capture hook that calls it and then
#   recreates the worktree anyway, which is the exact defect here.
#
#   HOME is redirected for the whole run: these hooks write session state and
#   worktrees under $HOME/.claude, and a test must never touch the developer's.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
FAILED_NAMES=()

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

export HOME="$TMPROOT/home"
mkdir -p "$HOME/.claude"
# The retention pass is a detached `rm -rf` that outlives the hook; it cannot
# reach this tmpdir, but a live ownerless deletion in the middle of a suite is
# misleading evidence when a case loses a directory.
export SUPERPOWERS_WORKTREE_CLEANUP=0

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }
judge() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi; }

# A `case` cannot be written inline inside $( ) — its `)` closes the substitution.
has() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }
exists() { if [ -e "$1" ]; then echo yes; else echo no; fi; }

new_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email t@e
  git -C "$dir" config user.name t
  git -C "$dir" commit -q --allow-empty -m init
}

# run_capture <cwd> <prompt> <session-id>
run_capture() {
  jq -n --arg cwd "$1" --arg p "$2" --arg s "$3" \
    '{session_id:$s, prompt:$p, cwd:$cwd}' \
    | bash "$ROOT/hooks/capture-task-slug.sh" 2>/dev/null
}

# run_enforce <file-path> <cwd> <session-id> — ALLOW | DENY:<reason>
run_enforce() {
  local out decision
  out=$(jq -n --arg f "$1" --arg cwd "$2" --arg s "$3" \
          '{tool_name:"Edit", tool_input:{file_path:$f}, cwd:$cwd, session_id:$s}' \
        | bash "$ROOT/hooks/enforce-worktree-edits.sh" 2>/dev/null)
  printf '%s' "$out" | jq -e . >/dev/null 2>&1 || { printf 'MALFORMED:%s' "$out"; return; }
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  if [ "$decision" = "deny" ]; then
    printf 'DENY:%s' "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"
  else
    printf 'ALLOW'
  fi
}

verdict() { case "$1" in ALLOW) printf ALLOW ;; DENY:*) printf DENY ;; *) printf '%s' "$1" ;; esac; }

state_field() { jq -r --arg k "$2" '.[$k] // "none"' "$HOME/.claude/session-state/$1.json" 2>/dev/null; }

# ---------------------------------------------------------------------------
echo "--- first prompt still creates the worktree ---"

REPO="$TMPROOT/proj"
new_repo "$REPO"
WT="$HOME/.claude/worktrees/proj/add-a-login-form"

out="$(run_capture "$REPO" "add a login form" "sess-1")"

judge "creates ~/.claude/worktrees/<repo>/<slug>" "yes" "$(exists "$WT/.git")"
judge "creates the wt/* branch" "yes" \
  "$(git -C "$REPO" rev-parse --verify -q wt/add-a-login-form >/dev/null && echo yes || echo no)"
judge "announces the worktree" "yes" "$(has "$out" "Dedicated worktree")"
if [ "$(state_field sess-1 worktree_created_at)" = "none" ]; then
  bad "records worktree_created_at" "field absent"
else
  ok "records worktree_created_at"
fi
judge "is not retired" "none" "$(state_field sess-1 worktree_retired_at)"

echo "--- a second prompt changes nothing ---"

created_at="$(state_field sess-1 worktree_created_at)"
out="$(run_capture "$REPO" "keep going" "sess-1")"
judge "worktree still there" "yes" "$(exists "$WT/.git")"
judge "creation timestamp is not rewritten" "$created_at" "$(state_field sess-1 worktree_created_at)"

# ---------------------------------------------------------------------------
echo "--- REMOVAL STICKS: the prompt hook does not rebuild ---"

git -C "$REPO" worktree remove --force "$WT"
git -C "$REPO" branch -q -D wt/add-a-login-form
judge "removal actually removed it" "no" "$(exists "$WT")"

out="$(run_capture "$REPO" "what did we ship" "sess-1")"

judge "worktree stays gone" "no" "$(exists "$WT")"
judge "branch stays gone" "no" \
  "$(git -C "$REPO" rev-parse --verify -q wt/add-a-login-form >/dev/null && echo yes || echo no)"
judge "git knows of no such worktree" "no" \
  "$(has "$(git -C "$REPO" worktree list)" "add-a-login-form")"
if [ "$(state_field sess-1 worktree_retired_at)" = "none" ]; then
  bad "records worktree_retired_at" "field absent"
else
  ok "records worktree_retired_at"
fi
judge "says the worktree was removed" "yes" "$(has "$out" "was removed")"
judge "does not claim a dedicated worktree" "no" "$(has "$out" "Dedicated worktree")"
judge "session files fall back to the output dir" "yes" \
  "$(has "$(state_field sess-1 session_files_dir)" "/.claude/outputs/add-a-login-form/session-files")"
judge "no session-files shell inside the dead path" "no" "$(exists "$WT/session-files")"

echo "--- and it stays gone across further prompts ---"

out="$(run_capture "$REPO" "and now" "sess-1")"
judge "still gone on the next prompt" "no" "$(exists "$WT")"
judge "still reported as removed" "yes" "$(has "$out" "was removed")"

# ---------------------------------------------------------------------------
echo "--- an Edit is the demand signal: the guard rebuilds, and still denies ---"

res="$(run_enforce "$REPO/src/app.ts" "$REPO" "sess-1")"
judge "the main-checkout edit is still denied" "DENY" "$(verdict "$res")"
judge "the worktree is rebuilt on demand" "yes" "$(exists "$WT/.git")"
judge "the deny names the rebuilt path" "yes" "$(has "$res" "$WT")"
judge "the deny says it was recreated" "yes" "$(has "$res" "recreated")"
judge "retirement is cleared" "none" "$(state_field sess-1 worktree_retired_at)"

out="$(run_capture "$REPO" "carry on" "sess-1")"
judge "the next prompt sees a live worktree again" "yes" "$(has "$out" "Dedicated worktree")"
judge "and stops calling it removed" "no" "$(has "$out" "was removed")"

echo "--- editing inside the worktree is allowed, as before ---"

judge "edit inside the worktree" "ALLOW" "$(verdict "$(run_enforce "$WT/src/app.ts" "$WT" "sess-1")")"

# ---------------------------------------------------------------------------
echo "--- a bare directory is not a worktree ---"

# ensure_session_files_dir is a mkdir: pointed at a removed worktree it leaves
# "<worktree>/session-files" behind, and `-d` then answers yes for a directory
# with no working tree in it. That shell is how a removed worktree used to come
# back looking alive.
SHELLY="$TMPROOT/shelly"
new_repo "$SHELLY"
out="$(run_capture "$SHELLY" "shell case" "sess-2")"
SWT="$HOME/.claude/worktrees/shelly/shell-case"
git -C "$SHELLY" worktree remove --force "$SWT"
mkdir -p "$SWT/session-files"

out="$(run_capture "$SHELLY" "again" "sess-2")"
judge "the shell is not mistaken for a worktree" "yes" "$(has "$out" "was removed")"
judge "no worktree is registered for the shell" "no" \
  "$(has "$(git -C "$SHELLY" worktree list)" "shell-case")"

# ---------------------------------------------------------------------------
echo "--- SessionStart does not resurrect a dead path either ---"

SI="$TMPROOT/siproj"
new_repo "$SI"
run_capture "$SI" "session init case" "sess-3" >/dev/null
SIWT="$HOME/.claude/worktrees/siproj/session-init-case"
git -C "$SI" worktree remove --force "$SIWT"

jq -n --arg cwd "$SI" --arg s "sess-3" \
  '{session_id:$s, cwd:$cwd, source:"resume"}' \
  | bash "$ROOT/hooks/session-init.sh" >/dev/null 2>&1

judge "no session-files shell created in the dead path" "no" "$(exists "$SIWT/session-files")"
judge "session files land in the output dir" "yes" \
  "$(has "$(state_field sess-3 session_files_dir)" "/.claude/outputs/")"

# ---------------------------------------------------------------------------
echo "--- a second repo does not inherit the first repo's worktree ---"

OTHER="$TMPROOT/other"
new_repo "$OTHER"
res="$(run_enforce "$OTHER/lib/x.ts" "$OTHER" "sess-1")"
judge "the edit in the other repo is denied" "DENY" "$(verdict "$res")"
judge "it does not point at the first repo's worktree" "no" "$(has "$res" "/worktrees/proj/")"
judge "it names the other repo" "yes" "$(has "$res" "worktrees/other/")"

# ---------------------------------------------------------------------------
echo "--- a session that predates the fix is adopted, not resurrected ---"

# Its state has no worktree_created_at. Without a backfill, a later removal
# leaves BOTH lifecycle fields empty, which reads as "never created" — and the
# next prompt rebuilds. The upgrade path back into the original bug.
UPG="$TMPROOT/upg"
new_repo "$UPG"
UWT="$HOME/.claude/worktrees/upg/ship-the-thing"
run_capture "$UPG" "ship the thing" "sess-u" >/dev/null
jq 'del(.worktree_created_at)' "$HOME/.claude/session-state/sess-u.json" > "$TMPROOT/u.json"
mv "$TMPROOT/u.json" "$HOME/.claude/session-state/sess-u.json"
judge "the marker is gone (pre-upgrade shape)" "none" "$(state_field sess-u worktree_created_at)"

run_capture "$UPG" "carry on" "sess-u" >/dev/null
if [ "$(state_field sess-u worktree_created_at)" = "none" ]; then
  bad "the live worktree backfills the marker" "field still absent"
else
  ok "the live worktree backfills the marker"
fi

git -C "$UPG" worktree remove --force "$UWT"
out="$(run_capture "$UPG" "and again" "sess-u")"
judge "an upgraded session's removal also sticks" "no" "$(exists "$UWT/.git")"
judge "and it is reported as removed" "yes" "$(has "$out" "was removed")"

# ---------------------------------------------------------------------------
echo "--- rebuilding preserves the branch tip, it does not reset it ---"

# `git worktree remove` keeps wt/<slug>. That branch can hold the only copy of
# some commits, and `worktree add -B` is "create or RESET" — it would move the
# branch back to the base ref and strand them.
KEEP="$TMPROOT/keep"
new_repo "$KEEP"
KWT="$HOME/.claude/worktrees/keep/save-my-work"
run_capture "$KEEP" "save my work" "sess-k" >/dev/null
echo "work in progress" > "$KWT/wip.txt"
git -C "$KWT" add wip.txt
git -C "$KWT" -c user.email=t@e -c user.name=t commit -q -m "wip: do not lose me"
TIP="$(git -C "$KEEP" rev-parse wt/save-my-work)"
git -C "$KEEP" worktree remove --force "$KWT"
judge "the branch outlives its worktree" "$TIP" "$(git -C "$KEEP" rev-parse wt/save-my-work)"
judge "and the commit is not on the base branch" "no" \
  "$(git -C "$KEEP" merge-base --is-ancestor "$TIP" main 2>/dev/null && echo yes || echo no)"

res="$(run_enforce "$KEEP/src/a.ts" "$KEEP" "sess-k")"
judge "the edit guard rebuilds it" "yes" "$(exists "$KWT/.git")"
judge "the branch tip is unchanged" "$TIP" "$(git -C "$KEEP" rev-parse wt/save-my-work)"
judge "the commit's file came back with it" "yes" "$(exists "$KWT/wip.txt")"
judge "the edit is still denied" "DENY" "$(verdict "$res")"

# ---------------------------------------------------------------------------
echo "--- a prunable registration does not block the rebuild ---"

# The retention pass deletes the directory with rm -rf and never calls
# `git worktree remove`, so git still holds the registration and reports the
# branch as checked out at a path that is gone.
PRN="$TMPROOT/prn"
new_repo "$PRN"
PWT="$HOME/.claude/worktrees/prn/fix-the-parser"
run_capture "$PRN" "fix the parser" "sess-p" >/dev/null
rm -rf "$PWT"
judge "git still registers the dead worktree" "yes" \
  "$(git -C "$PRN" worktree list --porcelain | grep -q "$PWT" && echo yes || echo no)"

res="$(run_enforce "$PRN/src/p.ts" "$PRN" "sess-p")"
judge "the rebuild succeeds anyway" "yes" "$(exists "$PWT/.git")"
judge "the deny says it was recreated" "yes" "$(has "$res" "recreated")"

# ---------------------------------------------------------------------------
echo "--- a leftover session-files shell is moved aside, not lost ---"

# `git worktree add` refuses a non-empty directory, so without this the rebuild
# never happens and every edit stays denied with no way forward.
SHL="$TMPROOT/shl"
new_repo "$SHL"
SWT="$HOME/.claude/worktrees/shl/write-the-plan"
run_capture "$SHL" "write the plan" "sess-s" >/dev/null
git -C "$SHL" worktree remove --force "$SWT"
mkdir -p "$SWT/session-files"
echo "my plan" > "$SWT/session-files/plan.md"

res="$(run_enforce "$SHL/src/s.ts" "$SHL" "sess-s")"
judge "the rebuild is not blocked by the shell" "yes" "$(exists "$SWT/.git")"
judge "the plan survived" "yes" "$(exists "$SWT/session-files/plan.md")"
judge "and it still says what it says" "my plan" "$(cat "$SWT/session-files/plan.md" 2>/dev/null)"

# ---------------------------------------------------------------------------
echo "--- retiring clears the exported worktree path ---"

# The env file only accumulates. Skipping the export is not clearing it: the
# first prompt's value would still point at the deleted worktree.
ENVR="$TMPROOT/envr"
new_repo "$ENVR"
EWT="$HOME/.claude/worktrees/envr/tidy-the-exports"
ENVFILE="$TMPROOT/claude-env"
: > "$ENVFILE"
CLAUDE_ENV_FILE="$ENVFILE" run_capture "$ENVR" "tidy the exports" "sess-e" >/dev/null
judge "the live worktree is exported" "yes" "$(has "$(cat "$ENVFILE")" "CLAUDE_WORKTREE_PATH=\"$EWT\"")"

git -C "$ENVR" worktree remove --force "$EWT"
CLAUDE_ENV_FILE="$ENVFILE" run_capture "$ENVR" "still here" "sess-e" >/dev/null
judge "the stale export is overwritten with an empty one" "yes" \
  "$(has "$(tail -5 "$ENVFILE")" 'CLAUDE_WORKTREE_PATH=""')"

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'failing: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
