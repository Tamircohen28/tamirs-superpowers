#!/usr/bin/env bash
# The UserPromptSubmit worktree hint (issue #337): emitted once per repo per
# session, scoped to the repo it is for, on a slug that carries no prompt text.
#
# WHAT THIS PINS
#   capture-task-slug.sh used to re-emit "Dedicated worktree: <path>" on every
#   prompt — 15–20 copies in one session — and the path was the FIRST repo's
#   even when every edit belonged in worktrees of other repos. Followed
#   literally, "Before Edit/Write, run: cd <path>" put the work in the wrong
#   repo. The slug was the prompt's first ~48 characters, so prompt text landed
#   in filesystem paths and `wt/*` branch names, and the same task got a
#   different worktree every time it was phrased differently.
#
# WHY END-TO-END
#   Every case runs the real hook against a real temporary repo and asserts on
#   the hook's output and the state file it writes. HOME is redirected for the
#   whole run: the hook writes session state and worktrees under $HOME/.claude,
#   and a test must never touch the developer's.

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
export SUPERPOWERS_WORKTREE_CLEANUP=0

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }
judge() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi; }
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

# run_capture <cwd> <prompt> <session-id> — the hook's stdout
run_capture() {
  jq -n --arg cwd "$1" --arg p "$2" --arg s "$3" \
    '{session_id:$s, prompt:$p, cwd:$cwd}' \
    | bash "$ROOT/hooks/capture-task-slug.sh" 2>/dev/null
}

# context <hook-output> — the additionalContext string, or "" when absent
context() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""'; }
title()   { printf '%s' "$1" | jq -r '.hookSpecificOutput.sessionTitle // ""'; }

state_field() { jq -r --arg k "$2" '.[$k] // "none"' "$HOME/.claude/session-state/$1.json" 2>/dev/null; }

TODAY="$(date +%Y%m%d)"

# ---------------------------------------------------------------------------
echo "--- the first prompt announces the worktree, and says which repo it is for ---"

PROJ="$TMPROOT/proj"
new_repo "$PROJ"
PWT="$HOME/.claude/worktrees/proj/$TODAY-sess-1"

ctx="$(context "$(run_capture "$PROJ" "add a login form" "sess-1")")"
judge "the worktree exists" "yes" "$(exists "$PWT/.git")"
judge "the hint is emitted" "yes" "$(has "$ctx" "Dedicated worktree")"
judge "the hint names the repo it is for" "yes" "$(has "$ctx" "Dedicated worktree for proj: $PWT")"
judge "the cd instruction names the repo too" "yes" "$(has "$ctx" "Before Edit/Write in proj,")"
judge "it says where other repos' edits go" "yes" "$(has "$ctx" "Edits to other repos go in their own ~/.claude/worktrees/<repo>/<slug>")"
judge "it says it will not repeat" "yes" "$(has "$ctx" "once per repo per session")"
judge "the hinted path is recorded" "$PWT" "$(state_field sess-1 worktree_hint_path)"

echo "--- the second prompt in the same repo gets no hint ---"

out="$(run_capture "$PROJ" "now add the tests" "sess-1")"
judge "no hint on the second prompt" "no" "$(has "$(context "$out")" "Dedicated worktree")"
judge "no additionalContext at all" "" "$(context "$out")"
judge "the session title is still reported" "add-a-login-form" "$(title "$out")"

out="$(run_capture "$PROJ" "and the docs" "sess-1")"
judge "nor on the third" "no" "$(has "$(context "$out")" "Dedicated worktree")"
judge "the worktree is untouched" "yes" "$(exists "$PWT/.git")"

# ---------------------------------------------------------------------------
echo "--- a cwd that moves to another repo re-emits the hint once, for THAT repo ---"

OTHER="$TMPROOT/other"
new_repo "$OTHER"
OWT="$HOME/.claude/worktrees/other/$TODAY-sess-1"

ctx="$(context "$(run_capture "$OTHER" "fix the thing over here" "sess-1")")"
judge "the hint comes back for the other repo" "yes" "$(has "$ctx" "Dedicated worktree for other: $OWT")"
judge "and does not point at the first repo" "no" "$(has "$ctx" "/worktrees/proj/")"
judge "the other repo is not reported as removed" "no" "$(has "$ctx" "was removed")"
judge "the other repo's worktree was created" "yes" "$(exists "$OWT/.git")"
judge "the slug is the same across repos within the session" "yes" "$(has "$OWT" "/$TODAY-sess-1")"
judge "the first repo's lifecycle is parked, not lost" "yes" \
  "$(jq -e --arg r "$(cd "$PROJ" && pwd -P)" '.repos[$r].worktree_created_at' "$HOME/.claude/session-state/sess-1.json" >/dev/null 2>&1 && echo yes || echo no)"

ctx="$(context "$(run_capture "$OTHER" "keep going" "sess-1")")"
judge "then silent again in the other repo" "no" "$(has "$ctx" "Dedicated worktree")"

echo "--- and back again: once more, then silence ---"

ctx="$(context "$(run_capture "$PROJ" "back to the first repo" "sess-1")")"
judge "returning to the first repo re-emits it" "yes" "$(has "$ctx" "Dedicated worktree for proj: $PWT")"
judge "the first repo's worktree is still the same one" "yes" "$(exists "$PWT/.git")"
judge "it is not reported as removed" "no" "$(has "$ctx" "was removed")"

ctx="$(context "$(run_capture "$PROJ" "carry on" "sess-1")")"
judge "and is silent after that" "no" "$(has "$ctx" "Dedicated worktree")"

# ---------------------------------------------------------------------------
echo "--- a removed worktree clears the record, so a rebuild is announced again ---"

git -C "$PROJ" worktree remove --force "$PWT"
ctx="$(context "$(run_capture "$PROJ" "what happened" "sess-1")")"
judge "the removal is reported" "yes" "$(has "$ctx" "was removed")"
judge "the hint record is cleared" "none" "$(state_field sess-1 worktree_hint_path)"

# The edit guard is the demand signal that rebuilds it (test-worktree-resurrection.sh).
jq -n --arg f "$PROJ/src/app.ts" --arg cwd "$PROJ" \
  '{tool_name:"Edit", tool_input:{file_path:$f}, cwd:$cwd, session_id:"sess-1"}' \
  | bash "$ROOT/hooks/enforce-worktree-edits.sh" >/dev/null 2>&1
judge "the guard rebuilt it" "yes" "$(exists "$PWT/.git")"
ctx="$(context "$(run_capture "$PROJ" "retry" "sess-1")")"
judge "the rebuilt worktree is announced once more" "yes" "$(has "$ctx" "Dedicated worktree for proj: $PWT")"
ctx="$(context "$(run_capture "$PROJ" "ok" "sess-1")")"
judge "and then not again" "no" "$(has "$ctx" "Dedicated worktree")"

# ---------------------------------------------------------------------------
echo "--- the slug is stable and carries no prompt text ---"

# A non-repo cwd keeps these cases to the slug logic alone; the state file is
# written either way.
PLAIN="$TMPROOT/plain-dir"
mkdir -p "$PLAIN"

run_capture "$PLAIN" "start-dev #337" "s-hash" >/dev/null
judge "'#337' slugs to issue-337" "issue-337" "$(state_field s-hash task_slug)"
judge "the title is still the prompt's words" "start-dev-337" "$(state_field s-hash session_title)"

run_capture "$PLAIN" "resume issue 42 on this branch" "s-word" >/dev/null
judge "'issue 42' slugs to issue-42" "issue-42" "$(state_field s-word task_slug)"

run_capture "$PLAIN" "look at https://github.com/o/r/issues/7 please" "s-url" >/dev/null
judge "an issue URL slugs to issue-7" "issue-7" "$(state_field s-url task_slug)"

run_capture "$PLAIN" "run task-003 of objective auth" "s-task" >/dev/null
judge "'task-003' slugs to task-003" "task-003" "$(state_field s-task task_slug)"

run_capture "$PLAIN" "Add a Login Form, please!" "deadbeef-cafe-0001" >/dev/null
judge "free text slugs to <date>-<session id prefix>" "$TODAY-deadbeef" "$(state_field deadbeef-cafe-0001 task_slug)"
judge "and its title is the prompt's words" "add-a-login-form-please" "$(state_field deadbeef-cafe-0001 session_title)"

out="$(run_capture "$PLAIN" "   " "blank-prompt-0001")"
judge "a blank prompt still gets the session slug" "$TODAY-blank-pr" "$(state_field blank-prompt-0001 task_slug)"
judge "and the slug stands in for the title" "$TODAY-blank-pr" "$(title "$out")"

echo "--- a host that sends no session id keeps the prompt-derived slug ---"

# Nothing stable to key on; the legacy behaviour beats inventing an identity.
run_capture "$PLAIN" "add a widget" "" >/dev/null
judge "no session id: slug is the prompt's words" "add-a-widget" \
  "$(jq -r '.task_slug // "none"' "$HOME/.claude/session-state/.json" 2>/dev/null)"

echo "--- the same issue in a new session lands in the same worktree ---"

ISS="$TMPROOT/iss"
new_repo "$ISS"
IWT="$HOME/.claude/worktrees/iss/issue-12"
ctx="$(context "$(run_capture "$ISS" "work on #12" "sess-a")")"
judge "session a creates the issue worktree" "yes" "$(exists "$IWT/.git")"
judge "session a is told about it" "yes" "$(has "$ctx" "Dedicated worktree for iss: $IWT")"
ctx="$(context "$(run_capture "$ISS" "resume issue #12" "sess-b")")"
judge "session b adopts the same worktree" "$IWT" "$(state_field sess-b worktree_path)"
judge "session b is told about it once" "yes" "$(has "$ctx" "Dedicated worktree for iss: $IWT")"
judge "only one wt/* branch exists for the issue" "1" \
  "$(git -C "$ISS" branch --list 'wt/*' | wc -l | tr -d ' ')"

echo "--- an objective stand-down and a workspace cwd carry no hint and no record ---"

OBJ="$TMPROOT/obj"
new_repo "$OBJ"
mkdir -p "$OBJ/.dev-files/objectives/auth"
jq -n '{id:"auth", title:"Auth", base_branch:"main", integration_branch:"objective/auth",
        status:"active", tasks:["task-001"], delivery:{strategy:"single-pr"}}' \
  > "$OBJ/.dev-files/objectives/auth/objective.json"
ctx="$(context "$(run_capture "$OBJ" "do the auth work" "sess-obj")")"
judge "no dedicated-worktree hint under an objective" "no" "$(has "$ctx" "Dedicated worktree")"
judge "no hint record under an objective" "none" "$(state_field sess-obj worktree_hint_path)"

ctx="$(context "$(run_capture "$PWT" "editing from inside the worktree" "sess-in")")"
judge "no hint when the cwd is the worktree itself" "no" "$(has "$ctx" "Dedicated worktree")"

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'failing: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
