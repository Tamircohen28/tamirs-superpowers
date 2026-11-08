#!/usr/bin/env bash
# The configurable session worktree root (issue #404).
#
# WHAT THIS PINS
#   Session worktrees used to be hard-coded under ~/.claude/worktrees, a path
#   Claude Code protects: outside bypassPermissions mode every write there
#   prompts, and no allow rule can pre-approve it. The root is now
#   SUPERPOWERS_WORKTREE_ROOT > the worktree_root plugin option
#   (CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT) > ~/.session-worktrees. This suite holds:
#
#     1. resolution — env over option over default, ~ and $HOME expanded,
#        relative values and `/` ignored;
#     2. classification — new root, legacy root, native, objective, a root whose
#        path contains `.agent-worktrees`, and a root reached through a symlink;
#     3. the hooks — deny messages, the session-start and prompt hints and the
#        add-dir warning name the configured root; the rebuild-on-edit path
#        creates under it; a live legacy worktree is still used, never shadowed;
#        the retention pass sweeps both roots;
#     4. scripts/worktrees-migrate.sh — dry run by default; dirty, recently
#        modified, claimed, objective-owned, in-use and already-present
#        worktrees are skipped; an idle one is moved and session state follows.
#
#   Every case runs the real hook or script against real temporary repos, with
#   HOME redirected so nothing touches the developer's machine.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
SKIP=0
FAILED_NAMES=()

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required"; exit 1; }

TMPROOT="$(mktemp -d)"
BUSY_PID=""
cleanup() {
  [ -n "$BUSY_PID" ] && kill "$BUSY_PID" 2>/dev/null
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

export HOME="$TMPROOT/home"
mkdir -p "$HOME/.claude"
export SUPERPOWERS_WORKTREE_CLEANUP=0
unset SUPERPOWERS_WORKTREE_ROOT CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT SUPERPOWERS_AGENT_WORKTREE_ROOT \
  SUPERPOWERS_OBJECTIVE_ID OBJECTIVES_ROOT 2>/dev/null || true
export AGENT_CLAIM_DIR="$HOME/.agent-work-claims"

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }
skip() { SKIP=$((SKIP + 1)); printf '  skip %s — %s\n' "$1" "$2"; }
judge() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi; }
has() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }
exists() { if [ -e "$1" ]; then echo yes; else echo no; fi; }

new_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email t@e
  git -C "$dir" config user.name t
  echo seed > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m init
}

# lib <env-assignments...> -- <shell snippet> — run the snippet with both libs
# sourced, under the given environment.
lib() {
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  env ${envs[@]+"${envs[@]}"} bash -c '
    source "$ROOT/hooks/lib/worktree-common.sh"
    source "$ROOT/hooks/lib/objective-common.sh"
    eval "$1"' _ "$1"
}
export ROOT

# run_enforce <file-path> <cwd> <session-id> [env...] — ALLOW | DENY:<reason>
run_enforce() {
  local f="$1" cwd="$2" sid="$3" out decision
  shift 3
  out=$(jq -n --arg f "$f" --arg cwd "$cwd" --arg s "$sid" \
          '{tool_name:"Edit", tool_input:{file_path:$f}, cwd:$cwd, session_id:$s}' \
        | env "$@" bash "$ROOT/hooks/enforce-worktree-edits.sh" 2>/dev/null)
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
  if [ "$decision" = "deny" ]; then
    printf 'DENY:%s' "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"
  else
    printf 'ALLOW'
  fi
}
verdict() { case "$1" in ALLOW) printf ALLOW ;; DENY:*) printf DENY ;; *) printf '%s' "$1" ;; esac; }

# run_capture <cwd> <prompt> <session-id> [env...] — additionalContext
run_capture() {
  local cwd="$1" p="$2" sid="$3"
  shift 3
  jq -n --arg cwd "$cwd" --arg p "$p" --arg s "$sid" '{session_id:$s, prompt:$p, cwd:$cwd}' \
    | env "$@" bash "$ROOT/hooks/capture-task-slug.sh" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}

state_file() { printf '%s' "$HOME/.claude/session-state/$1.json"; }
put_state() { mkdir -p "$HOME/.claude/session-state"; printf '%s\n' "$2" > "$(state_file "$1")"; }

# ---------------------------------------------------------------------------
echo "--- 1. resolution: env > option > default ---"

judge "default is ~/.session-worktrees" "$HOME/.session-worktrees default" \
  "$(lib -- 'echo "$WORKTREE_ROOT $WORKTREE_ROOT_SOURCE"')"
judge "the plugin option is read" "$HOME/opt-root option" \
  "$(lib 'CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT=~/opt-root' -- 'echo "$WORKTREE_ROOT $WORKTREE_ROOT_SOURCE"')"
judge "the env var beats the option" "/env/root env" \
  "$(lib 'CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT=/opt/root' 'SUPERPOWERS_WORKTREE_ROOT=/env/root/' -- 'echo "$WORKTREE_ROOT $WORKTREE_ROOT_SOURCE"')"
judge "\$HOME is expanded" "$HOME/h-root" \
  "$(lib "SUPERPOWERS_WORKTREE_ROOT=\$HOME/h-root" -- 'echo "$WORKTREE_ROOT"')"
judge "a relative env value falls through to the option" "/opt/root option" \
  "$(lib 'SUPERPOWERS_WORKTREE_ROOT=rel/root' 'CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT=/opt/root' -- 'echo "$WORKTREE_ROOT $WORKTREE_ROOT_SOURCE"')"
judge "/ is refused" "$HOME/.session-worktrees default" \
  "$(lib 'SUPERPOWERS_WORKTREE_ROOT=/' -- 'echo "$WORKTREE_ROOT $WORKTREE_ROOT_SOURCE"')"
judge "the legacy root is still known" "$HOME/.claude/worktrees" \
  "$(lib -- 'echo "$LEGACY_WORKTREE_ROOT"')"
judge "worktree_path_for uses the configured root" "/env/root/repo/slug" \
  "$(lib 'SUPERPOWERS_WORKTREE_ROOT=/env/root' -- 'worktree_path_for repo slug')"
# shellcheck disable=SC2088  # the literal manifest text
judge "the manifest declares the option with the same default" "~/.session-worktrees" \
  "$(jq -r '.userConfig.worktree_root.default' "$ROOT/.claude-plugin/plugin.json")"

# ---------------------------------------------------------------------------
echo "--- 2. classification ---"

C="$TMPROOT/classrepo"
new_repo "$C"
mkdir -p "$HOME/.session-worktrees/classrepo" "$HOME/.claude/worktrees/classrepo"
git -C "$C" worktree add -q -b wt/new-one "$HOME/.session-worktrees/classrepo/new-one" main
git -C "$C" worktree add -q -b wt/old-one "$HOME/.claude/worktrees/classrepo/old-one" main
git -C "$C" worktree add -q -b claude/native "$C/.claude/worktrees/native" main
git -C "$C" worktree add -q -b worker/obj/001 "$C/.agent-worktrees/obj/task-001" main
AW="$TMPROOT/x/.agent-worktrees"
mkdir -p "$AW/classrepo"
git -C "$C" worktree add -q -b wt/aw-one "$AW/classrepo/aw-one" main
mkdir -p "$TMPROOT/real-root/classrepo"
ln -s "$TMPROOT/real-root" "$TMPROOT/link-root"
git -C "$C" worktree add -q -b wt/linked "$TMPROOT/real-root/classrepo/linked" main

classify() { lib "$@" -- 'classify_worktree_path "$D"'; }
judge "a worktree under the new default root is session-global" session-global \
  "$(classify "D=$HOME/.session-worktrees/classrepo/new-one")"
judge "a worktree under ~/.claude/worktrees is legacy-global" legacy-global \
  "$(classify "D=$HOME/.claude/worktrees/classrepo/old-one")"
judge "the native <repo>/.claude/worktrees layout is native-claude" native-claude \
  "$(classify "D=$C/.claude/worktrees/native")"
judge "an objective worker stays objective-worker" objective-worker \
  "$(classify "D=$C/.agent-worktrees/obj/task-001")"
judge "the main checkout is main-checkout" main-checkout "$(classify "D=$C")"
judge "a root containing .agent-worktrees is session-global when configured" session-global \
  "$(classify "D=$AW/classrepo/aw-one" "SUPERPOWERS_WORKTREE_ROOT=$AW")"
judge "...and objective-other when it is not the session root" objective-other \
  "$(classify "D=$AW/classrepo/aw-one")"
judge "an explicit objective root still wins" objective-other \
  "$(classify "D=$AW/classrepo/aw-one" "SUPERPOWERS_WORKTREE_ROOT=$AW" "SUPERPOWERS_AGENT_WORKTREE_ROOT=$AW")"
judge "a root reached through a symlink matches git's physical path" session-global \
  "$(classify "D=$TMPROOT/real-root/classrepo/linked" "SUPERPOWERS_WORKTREE_ROOT=$TMPROOT/link-root")"
judge "is_global_worktree_path accepts the legacy root" yes \
  "$(lib -- "is_global_worktree_path '$HOME/.claude/worktrees/classrepo/old-one/src' && echo yes || echo no")"
judge "is_global_worktree_path accepts the new root" yes \
  "$(lib -- "is_global_worktree_path '$HOME/.session-worktrees/classrepo/new-one/src' && echo yes || echo no")"
judge "is_global_worktree_path rejects the main checkout" no \
  "$(lib -- "is_global_worktree_path '$C/src' && echo yes || echo no")"

# ---------------------------------------------------------------------------
echo "--- 3a. enforce-worktree-edits: messages and the rebuild name the configured root ---"

E="$TMPROOT/enf"
new_repo "$E"
CUSTOM="$TMPROOT/custom-root"

res="$(run_enforce "$E/src/a.ts" "$E" "no-state")"
judge "the main checkout is denied" DENY "$(verdict "$res")"
judge "the deny names the default root" yes "$(has "$res" "under $HOME/.session-worktrees/enf/<task-slug>")"
judge "the deny no longer names ~/.claude/worktrees" no "$(has "$res" ".claude/worktrees")"

res="$(run_enforce "$E/src/a.ts" "$E" "no-state" "SUPERPOWERS_WORKTREE_ROOT=$CUSTOM")"
judge "the deny names a configured root" yes "$(has "$res" "under $CUSTOM/enf/<task-slug>")"

put_state rebuild '{"task_slug":"rebuild-me","worktree_created_at":"2026-01-01T00:00:00Z"}'
res="$(run_enforce "$E/src/a.ts" "$E" "rebuild" "SUPERPOWERS_WORKTREE_ROOT=$CUSTOM")"
judge "rebuild-on-edit creates the worktree under the configured root" yes "$(exists "$CUSTOM/enf/rebuild-me/.git")"
judge "the deny names the rebuilt path" yes "$(has "$res" "recreated at \"$CUSTOM/enf/rebuild-me\"")"
judge "nothing is created at the legacy root" no "$(exists "$HOME/.claude/worktrees/enf/rebuild-me")"
judge "an edit inside the configured-root worktree is allowed" ALLOW \
  "$(verdict "$(run_enforce "$CUSTOM/enf/rebuild-me/src/a.ts" "$E" "rebuild" "SUPERPOWERS_WORKTREE_ROOT=$CUSTOM")")"

echo "--- 3b. a live legacy worktree keeps working ---"

mkdir -p "$HOME/.claude/worktrees/enf"
git -C "$E" worktree add -q -b wt/old-task "$HOME/.claude/worktrees/enf/old-task" main
LEG="$HOME/.claude/worktrees/enf/old-task"

judge "an edit inside a legacy worktree is allowed" ALLOW \
  "$(verdict "$(run_enforce "$LEG/src/a.ts" "$LEG" "legacy")")"

put_state legacy "{\"task_slug\":\"old-task\",\"worktree_path\":\"$LEG\",\"worktree_created_at\":\"2026-01-01T00:00:00Z\"}"
res="$(run_enforce "$E/src/a.ts" "$E" "legacy")"
judge "a recorded live legacy worktree is the remedy" yes "$(has "$res" "cd \"$LEG\"")"
judge "no shadow worktree is built under the new root" no "$(exists "$HOME/.session-worktrees/enf/old-task")"

put_state legacy2 '{"task_slug":"old-task","prompt_count":1,"worktree_created_at":"2026-01-01T00:00:00Z"}'
res="$(run_enforce "$E/src/a.ts" "$E" "legacy2")"
judge "a slug-only state finds the live legacy worktree too" yes "$(has "$res" "cd \"$LEG\"")"

ctx="$(run_capture "$E" "keep going" "legacy2")"
judge "the prompt hook does not report the legacy worktree as removed" no "$(has "$ctx" "was removed")"
judge "the prompt hook records the legacy path" "$LEG" "$(jq -r '.worktree_path' "$(state_file legacy2)")"
judge "...and creates nothing under the new root" no "$(exists "$HOME/.session-worktrees/enf/old-task")"

echo "--- 3c. hints name the configured root ---"

H="$TMPROOT/hintrepo"
new_repo "$H"
ctx="$(run_capture "$H" "add a thing" "hint-1" "SUPERPOWERS_WORKTREE_ROOT=$CUSTOM")"
judge "the prompt hook creates under the configured root" yes "$(has "$ctx" "Dedicated worktree for hintrepo: $CUSTOM/hintrepo/")"
judge "the other-repos line names the configured root" yes "$(has "$ctx" "their own $CUSTOM/<repo>/<slug>")"

si="$(jq -n --arg cwd "$H" '{session_id:"si-1", cwd:$cwd, source:"startup"}' \
  | SUPERPOWERS_WORKTREE_ROOT="$CUSTOM" bash "$ROOT/hooks/session-init.sh" 2>/dev/null \
  | jq -r '.hookSpecificOutput.additionalContext // ""')"
judge "session-init's policy line names the configured root" yes "$(has "$si" "every repo task runs in $CUSTOM/<repo>/<task-slug>")"

da="$(jq -n --arg d "$H" '{directory:$d}' \
  | SUPERPOWERS_WORKTREE_ROOT="$CUSTOM" bash "$ROOT/hooks/directory-added.sh" 2>&1 >/dev/null)"
judge "the add-dir warning names the configured root" yes "$(has "$da" "worktree under $CUSTOM/hintrepo/<task-slug>")"

echo "--- 3d. the retention pass sweeps both roots ---"

sweep_home="$TMPROOT/sweep-home"
new_repo "$TMPROOT/somerepo"
n=0
for r in "$sweep_home/.session-worktrees" "$sweep_home/.claude/worktrees"; do
  n=$((n + 1))
  mkdir -p "$r/somerepo"
  git -C "$TMPROOT/somerepo" worktree add -q -b "wt/old-$n" "$r/somerepo/old-task" main
done
find "$sweep_home" "$TMPROOT/somerepo/.git/worktrees" -exec touch -t 202001010000 {} + 2>/dev/null
HOME="$sweep_home" SUPERPOWERS_WORKTREE_CLEANUP=1 bash -c '
  source "$1/hooks/lib/worktree-common.sh"; cleanup_stale_worktrees' _ "$ROOT" >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  [ -d "$sweep_home/.session-worktrees/somerepo/old-task" ] || [ -d "$sweep_home/.claude/worktrees/somerepo/old-task" ] || break
  sleep 0.2
done
judge "a stale worktree under the new root is retired" no "$(exists "$sweep_home/.session-worktrees/somerepo/old-task")"
judge "a stale worktree under the legacy root is retired" no "$(exists "$sweep_home/.claude/worktrees/somerepo/old-task")"

# ---------------------------------------------------------------------------
echo "--- 4. scripts/worktrees-migrate.sh ---"

M="$TMPROOT/mig"
new_repo "$M"
LR="$HOME/.claude/worktrees/mig"
NR="$HOME/.session-worktrees/mig"
mkdir -p "$LR"
for n in idle dirty recent claimed objtask busy present; do
  git -C "$M" worktree add -q -b "wt/$n" "$LR/$n" main
done
mkdir -p "$LR/idle/session-files" && echo plan > "$LR/idle/session-files/plan.md"
echo change >> "$LR/dirty/README.md"
mkdir -p "$NR/present"

# Age everything except "recent", worktree and git metadata alike.
for n in idle dirty claimed objtask busy present; do
  find "$LR/$n" "$M/.git/worktrees/$n" -exec touch -t 202001010000 {} + 2>/dev/null
done

mkdir -p "$AGENT_CLAIM_DIR"
jq -n --argjson now "$(date +%s)" \
  '{resource:"git:owner/mig@wt/claimed", tool:"codex", host:"another-host", pid:1, heartbeat_at:$now}' \
  > "$AGENT_CLAIM_DIR/git-owner-mig-wt-claimed.json"

mkdir -p "$M/.dev-files/objectives/o1/tasks"
jq -n '{id:"o1", status:"active"}' > "$M/.dev-files/objectives/o1/objective.json"
jq -n '{id:"task-001", status:"running", branch:"wt/objtask"}' > "$M/.dev-files/objectives/o1/tasks/task-001.json"

PROC_OK=no
if command -v lsof >/dev/null 2>&1 || [ -d /proc/self ]; then
  PROC_OK=yes
  ( cd "$LR/busy" && exec sleep 120 ) &
  BUSY_PID=$!
  sleep 0.3
fi

put_state mig-1 "{\"task_slug\":\"idle\",\"worktree_path\":\"$LR/idle\",\"session_files_dir\":\"$LR/idle/session-files\",\"repos\":{\"$M\":{\"worktree_path\":\"$LR/idle\"}},\"unrelated\":\"$LR/idle-not-this-one\"}"

dry="$(bash "$ROOT/scripts/worktrees-migrate.sh" </dev/null 2>&1)"
judge "the dry run says it is one" yes "$(has "$dry" "DRY RUN")"
judge "the dry run plans the idle worktree" yes "$(has "$dry" "MOVE  $LR/idle")"
judge "the dry run moves nothing" yes "$(exists "$LR/idle/.git")"
judge "the dry run leaves state alone" "$LR/idle" "$(jq -r '.worktree_path' "$(state_file mig-1)")"

out="$(bash "$ROOT/scripts/worktrees-migrate.sh" --yes </dev/null 2>&1)"
rc=$?
judge "the apply run exits 0" 0 "$rc"
reason_for() { printf '%s\n' "$out" | awk -v p="SKIP  $LR/$1" '$0 == p {getline; print; exit}'; }

judge "the idle worktree is moved" yes "$(exists "$NR/idle/.git")"
judge "git knows the new path" yes "$(has "$(git -C "$M" worktree list --porcelain)" "worktree $(cd "$NR/idle" && pwd -P)")"
judge "its session-files came along" plan "$(cat "$NR/idle/session-files/plan.md" 2>/dev/null)"
judge "the moved worktree is still on its branch" wt/idle "$(git -C "$NR/idle" symbolic-ref --short HEAD 2>/dev/null)"
judge "state worktree_path follows" "$NR/idle" "$(jq -r '.worktree_path' "$(state_file mig-1)")"
judge "state session_files_dir follows" "$NR/idle/session-files" "$(jq -r '.session_files_dir' "$(state_file mig-1)")"
judge "per-repo state follows" "$NR/idle" "$(jq -r --arg r "$M" '.repos[$r].worktree_path' "$(state_file mig-1)")"
judge "a path that only shares a prefix is not rewritten" "$LR/idle-not-this-one" "$(jq -r '.unrelated' "$(state_file mig-1)")"

judge "a dirty worktree stays" yes "$(exists "$LR/dirty/.git")"
judge "...with the reason" yes "$(has "$(reason_for dirty)" "uncommitted changes")"
judge "a recently modified worktree stays" yes "$(exists "$LR/recent/.git")"
judge "...with the reason" yes "$(has "$(reason_for recent)" "modified in the last 60 min")"
judge "a claimed worktree stays" yes "$(exists "$LR/claimed/.git")"
judge "...with the reason" yes "$(has "$(reason_for claimed)" "live agent claim")"
judge "an objective-owned worktree stays" yes "$(exists "$LR/objtask/.git")"
judge "...with the reason" yes "$(has "$(reason_for objtask)" "objective o1 task-001 is running")"
judge "a worktree whose destination exists stays" yes "$(exists "$LR/present/.git")"
judge "...with the reason" yes "$(has "$(reason_for present)" "already exists")"
if [ "$PROC_OK" = yes ]; then
  judge "a worktree a process is using stays" yes "$(exists "$LR/busy/.git")"
  judge "...with the reason" yes "$(has "$(reason_for busy)" "running process")"
else
  skip "a worktree a process is using stays" "neither lsof nor /proc on this machine"
fi

judge "--idle-minutes 0 lifts only the recency rule" yes \
  "$(has "$(bash "$ROOT/scripts/worktrees-migrate.sh" --idle-minutes 0 </dev/null 2>&1)" "MOVE  $LR/recent")"
judge "an unknown flag is a usage error" 2 \
  "$(bash "$ROOT/scripts/worktrees-migrate.sh" --nope </dev/null >/dev/null 2>&1; echo $?)"
judge "--help exits 0" 0 "$(bash "$ROOT/scripts/worktrees-migrate.sh" --help </dev/null >/dev/null 2>&1; echo $?)"

# ---------------------------------------------------------------------------
# 5. NOTHING IS DELETED OR MOVED ON A PATH COMPARISON THAT WAS NOT CANONICAL.
#
# PR #406 review (P1): with the root reached through a symlink, WorktreeCreate
# compared the root's LOGICAL spelling with git's PHYSICAL worktree list, read an
# existing worktree as unregistered, and `rm -rf`ed it — uncommitted work
# included. Every case below holds uncommitted work and asserts it survives
# WorktreeCreate (session and objective paths), the retention pass, the
# migration script and WorktreeRemove.
echo "--- 5. a symlinked root never loses work ---"

S="$TMPROOT/symrepo"
new_repo "$S"
mkdir -p "$TMPROOT/sym-real/symrepo"
ln -s "$TMPROOT/sym-real" "$TMPROOT/sym-link"
SL="$TMPROOT/sym-link"
git -C "$S" worktree add -q -b wt/keep "$SL/symrepo/keep" main
echo precious > "$SL/symrepo/keep/precious.txt"
echo edit >> "$SL/symrepo/keep/README.md"
put_state symkeep '{"task_slug":"keep","prompt_count":1}'

run_wtc() {  # run_wtc <session-id> <env...> — WorktreeCreate's stdout; rc in WTC_RC
  local sid="$1"
  shift
  WTC_OUT="$(jq -n --arg cwd "$S" --arg s "$sid" '{session_id:$s, name:"x", cwd:$cwd}' \
    | env "$@" bash "$ROOT/hooks/worktree-create.sh" 2>"$TMPROOT/wtc.err")"
  WTC_RC=$?
}

run_wtc symkeep "SUPERPOWERS_WORKTREE_ROOT=$SL"
judge "WorktreeCreate reuses the registered worktree behind a symlinked root" 0 "$WTC_RC"
judge "...and names it" "$SL/symrepo/keep" "$WTC_OUT"
judge "...the untracked file survives" precious "$(cat "$SL/symrepo/keep/precious.txt" 2>/dev/null)"
judge "...the tracked edit survives" yes "$(has "$(cat "$SL/symrepo/keep/README.md" 2>/dev/null)" edit)"
judge "...it is still the same registered worktree" wt/keep "$(git -C "$SL/symrepo/keep" symbolic-ref --short HEAD 2>/dev/null)"

# An unregistered directory with someone's files in it: never deleted, never
# reused, the hook fails and says why.
mkdir -p "$SL/symrepo/stray"
echo notes > "$SL/symrepo/stray/notes.md"
put_state symstray '{"task_slug":"stray","prompt_count":1}'
run_wtc symstray "SUPERPOWERS_WORKTREE_ROOT=$SL"
judge "an unregistered directory with files makes WorktreeCreate fail" 1 "$WTC_RC"
judge "...and its files stay where they were" notes "$(cat "$SL/symrepo/stray/notes.md" 2>/dev/null)"
judge "...and the reason names the directory" yes "$(has "$(cat "$TMPROOT/wtc.err")" "$SL/symrepo/stray")"

# A directory holding a .git file that is not a registered worktree of this repo.
mkdir -p "$SL/symrepo/foreign"
echo "gitdir: /nowhere" > "$SL/symrepo/foreign/.git"
echo mine > "$SL/symrepo/foreign/work.txt"
put_state symforeign '{"task_slug":"foreign","prompt_count":1}'
run_wtc symforeign "SUPERPOWERS_WORKTREE_ROOT=$SL"
judge "a .git directory that is not ours makes WorktreeCreate fail" 1 "$WTC_RC"
judge "...and it is left alone" mine "$(cat "$SL/symrepo/foreign/work.txt" 2>/dev/null)"

# A session-files shell (the only thing the hooks ever leave behind) is fine.
mkdir -p "$SL/symrepo/shell/session-files"
echo plan > "$SL/symrepo/shell/session-files/plan.md"
put_state symshell '{"task_slug":"shell","prompt_count":1}'
run_wtc symshell "SUPERPOWERS_WORKTREE_ROOT=$SL"
judge "a session-files shell becomes the worktree" 0 "$WTC_RC"
judge "...registered" yes "$(exists "$SL/symrepo/shell/.git")"
judge "...with the session files kept" plan "$(cat "$SL/symrepo/shell/session-files/plan.md" 2>/dev/null)"

# The objective path of WorktreeCreate had the same comparison.
mkdir -p "$TMPROOT/obj-real"
ln -s "$TMPROOT/obj-real" "$TMPROOT/obj-link"
git -C "$S" worktree add -q -b worker/o2/001 "$TMPROOT/obj-link/o2/task-001" main
echo precious > "$TMPROOT/obj-link/o2/task-001/precious.txt"
run_wtc symobj "SUPERPOWERS_AGENT_WORKTREE_ROOT=$TMPROOT/obj-link" SUPERPOWERS_OBJECTIVE_ID=o2 SUPERPOWERS_TASK_UNIT=task-001
judge "objective WorktreeCreate reuses its worktree behind a symlinked root" 0 "$WTC_RC"
judge "...the untracked file survives" precious "$(cat "$TMPROOT/obj-link/o2/task-001/precious.txt" 2>/dev/null)"

# Retention: age everything. The dirty worktree must stay; so must one whose
# registration is broken (git status fails, which used to read as "clean").
git -C "$S" worktree add -q -b wt/clean-old "$SL/symrepo/clean-old" main
git -C "$S" worktree add -q -b wt/broken "$SL/symrepo/broken" main
echo precious > "$SL/symrepo/broken/precious.txt"
rm -rf "$(git -C "$SL/symrepo/broken" rev-parse --path-format=absolute --git-dir)"
FH="$TMPROOT/full-clone-home"
mkdir -p "$FH/.session-worktrees/r"
git init -q -b main "$FH/.session-worktrees/r/clone"
# The broken-registration case again under a plain (non-symlinked) root, where
# the pass actually walks: before this fix it read the failed status as clean.
new_repo "$TMPROOT/brkrepo"
git -C "$TMPROOT/brkrepo" worktree add -q -b wt/brk "$FH/.session-worktrees/r/brk" main
echo precious > "$FH/.session-worktrees/r/brk/precious.txt"
rm -rf "$(git -C "$FH/.session-worktrees/r/brk" rev-parse --path-format=absolute --git-dir)"
find "$TMPROOT/sym-real" "$S/.git/worktrees" "$TMPROOT/full-clone-home" -exec touch -t 202001010000 {} + 2>/dev/null
run_retention() {  # run_retention <home> <env...>
  local h="$1"
  shift
  env HOME="$h" SUPERPOWERS_WORKTREE_CLEANUP=1 "$@" bash -c '
    source "$1/hooks/lib/worktree-common.sh"; _cleanup_stale_worktrees_blocking "$WORKTREE_ROOT"' _ "$ROOT" >/dev/null 2>&1
}
run_retention "$HOME" "SUPERPOWERS_WORKTREE_ROOT=$SL"
judge "retention keeps a dirty worktree behind a symlinked root" precious "$(cat "$SL/symrepo/keep/precious.txt" 2>/dev/null)"
judge "retention keeps a worktree whose registration is broken" precious "$(cat "$SL/symrepo/broken/precious.txt" 2>/dev/null)"
judge "retention still retires a clean stale worktree behind a symlinked root" no "$(exists "$SL/symrepo/clean-old")"
judge "...through git, so the registration goes too" no \
  "$(has "$(git -C "$S" worktree list --porcelain)" "clean-old")"
run_retention "$FH"
judge "retention never deletes a full clone (a .git directory)" yes "$(exists "$FH/.session-worktrees/r/clone/.git")"
judge "retention keeps a broken-registration worktree under a plain root" precious "$(cat "$FH/.session-worktrees/r/brk/precious.txt" 2>/dev/null)"

# Migration out of a symlinked root: the dirty one stays, a clean idle one moves.
git -C "$S" worktree add -q -b wt/idle-sym "$SL/symrepo/idle-sym" main
find "$SL/symrepo/idle-sym/" "$S/.git/worktrees/idle-sym" -exec touch -t 202001010000 {} + 2>/dev/null
mig="$(bash "$ROOT/scripts/worktrees-migrate.sh" --yes --from "$SL" --to "$TMPROOT/sym-dest" </dev/null 2>&1)"
judge "migration skips the dirty worktree behind a symlinked root" precious "$(cat "$SL/symrepo/keep/precious.txt" 2>/dev/null)"
judge "migration skips the broken one" precious "$(cat "$SL/symrepo/broken/precious.txt" 2>/dev/null)"
judge "migration moves a clean idle worktree out of a symlinked root" yes "$(exists "$TMPROOT/sym-dest/symrepo/idle-sym/.git")"
judge "...and git agrees" yes "$(has "$(git -C "$S" worktree list --porcelain)" "sym-dest/symrepo/idle-sym")"
[ "$FAIL" -eq 0 ] || printf '%s\n' "$mig" | sed 's/^/      | /'

# WorktreeRemove on a worktree whose registration is broken: never rm -rf.
wr="$(jq -n --arg p "$SL/symrepo/broken" '{worktree_path:$p}' | SUPERPOWERS_WORKTREE_ROOT="$SL" bash "$ROOT/hooks/worktree-remove.sh" 2>&1)"
judge "WorktreeRemove leaves a worktree it cannot verify" precious "$(cat "$SL/symrepo/broken/precious.txt" 2>/dev/null)"
judge "...and says why" yes "$(has "$wr" "not removed")"
wr="$(jq -n --arg p "$SL/symrepo/keep" '{worktree_path:$p}' | SUPERPOWERS_WORKTREE_ROOT="$SL" bash "$ROOT/hooks/worktree-remove.sh" 2>&1)"
judge "WorktreeRemove leaves a dirty worktree behind a symlinked root" precious "$(cat "$SL/symrepo/keep/precious.txt" 2>/dev/null)"
git -C "$S" worktree add -q -b wt/rm-me "$SL/symrepo/rm-me" main
wr="$(jq -n --arg p "$SL/symrepo/rm-me" '{worktree_path:$p}' | SUPERPOWERS_WORKTREE_ROOT="$SL" bash "$ROOT/hooks/worktree-remove.sh" 2>&1)"
judge "WorktreeRemove removes a clean registered worktree behind a symlinked root" no "$(exists "$SL/symrepo/rm-me")"
judge "...through git" no "$(has "$(git -C "$S" worktree list --porcelain)" "rm-me")"

echo
echo "passed: $PASS   failed: $FAIL   skipped: $SKIP"
if [ "$FAIL" -ne 0 ]; then
  printf 'failing: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
