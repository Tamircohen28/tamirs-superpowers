#!/usr/bin/env bash
# End-to-end tests for the agent-concurrency guard (hooks/protect-other-branches.sh
# + hooks/lib/agent-claim.sh).
#
# WHY END-TO-END AND NOT UNIT
#   The guard's value is entirely in the seam: a command string on one side, a
#   claim file written by some *other* agent on the other. A unit test of the
#   parser alone would pass against a parser whose output the hook then ignores,
#   and a unit test of claim_inspect alone would pass against a hook that asks
#   it about the wrong branch — which is exactly the defect this file exists to
#   pin. So every case here feeds real JSON to the real hook against a real
#   temporary repo and a real planted claim, and asserts on the real decision.
#
# WHY BOTH DIRECTIONS
#   A guard that only ever blocks is indistinguishable from a broken guard.
#   Half of these cases assert ALLOW.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/protect-other-branches.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required to run these tests"; exit 1; }
[ -f "$HOOK" ] || { echo "FATAL: hook not found at $HOOK"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# A throwaway repo whose origin is acme/repo and whose checked-out branch is
# `main` — so a naive positional parser that falls back to the current branch
# resolves to exactly the branch our synthetic claim holds.
REPO="$TMPROOT/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" remote add origin https://github.com/acme/repo.git
git -C "$REPO" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init

# plant_claim <resource> <age-seconds>
# Writes a claim held by a DIFFERENT agent, on a DIFFERENT host (so the
# same-host pid liveness short-circuit does not apply and `age` governs).
plant_claim() {
  local resource="$1" age="$2" dir="$3" key
  mkdir -p "$dir"
  key="$(printf '%s' "$resource" | tr '/:@#' '____' | tr -c 'A-Za-z0-9._-' '_')"
  jq -n --arg r "$resource" --argjson hb "$(( $(date +%s) - age ))" \
    '{schema:"agent-work-claim/1", resource:$r, agent_id:"other-agent",
      tool:"codex", host:"some-other-host", pid:1, heartbeat_at:$hb,
      note:"synthetic claim"}' > "$dir/${key}.json"
}

# run_hook <command> <claim-dir> — prints the decision: ALLOW | DENY:<reason>
run_hook() {
  local cmd="$1" dir="$2" out decision reason
  out=$(jq -n --arg c "$cmd" --arg cwd "$REPO" \
          '{tool_name:"Bash", tool_input:{command:$c}, cwd:$cwd, session_id:"test-session"}' \
        | AGENT_CLAIM_DIR="$dir" AGENT_CLAIM_ID="test-agent" AGENT_CLAIM_TOOL="claude-code" \
          bash "$HOOK" 2>/dev/null)
  if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    printf 'MALFORMED:%s' "$out"; return
  fi
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
  if [ "$decision" = "deny" ]; then printf 'DENY:%s' "$reason"; else printf 'ALLOW'; fi
}

# judge <name> <expect> <result>
judge() {
  local name="$1" expect="$2" result="$3" ok=0
  case "$expect" in
    ALLOW)     [ "$result" = "ALLOW" ] && ok=1 ;;
    BLOCKED)   case "$result" in DENY:BLOCKED*) ok=1 ;; esac ;;
    CANNOTRUN) case "$result" in DENY*"CONCURRENCY GUARD CANNOT RUN"*) ok=1 ;; esac ;;
  esac

  if [ "$ok" = 1 ]; then
    PASS=$((PASS + 1)); printf '  ok   %-58s [%s]\n' "$name" "$expect"
  else
    FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
    printf '  FAIL %-58s expected %s, got: %s\n' "$name" "$expect" "${result%%$'\n'*}"
  fi
}

# check <name> <expect: ALLOW|BLOCKED|CANNOTRUN> <command> [claim-age-seconds]
check() {
  local name="$1" expect="$2" cmd="$3" age="${4:-0}"
  local dir
  dir="$TMPROOT/claims.$((PASS + FAIL))"
  plant_claim "git:acme/repo@main" "$age" "$dir"
  judge "$name" "$expect" "$(run_hook "$cmd" "$dir")"
}

# check_extra <name> <expect> <command> <extra-resource>
# As check(), plus a second live claim on <extra-resource> held by another
# agent - so a `gh` target can be asserted BLOCKED rather than merely unclaimed.
# Without it, "not treated as a gh command" and "treated as a gh command on a
# free artifact" both read as ALLOW and the assertion proves nothing.
check_extra() {
  local name="$1" expect="$2" cmd="$3" extra="$4"
  local dir
  dir="$TMPROOT/claims.$((PASS + FAIL))"
  plant_claim "git:acme/repo@main" 0 "$dir"
  plant_claim "$extra" 0 "$dir"
  judge "$name" "$expect" "$(run_hook "$cmd" "$dir")"
}

# check_parse <name> <command> <expected-rc> [expected-dest-count]
# Asserts on claim_push_destinations directly. This is the exact shape the
# defect was reported in - a plain `git commit` yielding phantom destinations -
# so it is pinned at the parser as well as end-to-end.
check_parse() {
  local name="$1" cmd="$2" want_rc="$3" want_n="${4:-0}"
  local out rc n
  out=$(bash -c 'source "$1"; claim_push_destinations "$2" main' _ \
        "$ROOT/hooks/lib/agent-claim.sh" "$cmd")
  rc=$?
  n=$(printf '%s' "$out" | grep -c '^DEST')
  [ -n "$out" ] || n=0
  if [ "$rc" = "$want_rc" ] && [ "$n" = "$want_n" ]; then
    PASS=$((PASS + 1)); printf '  ok   %-58s [rc=%s, %s dest]\n' "$name" "$want_rc" "$want_n"
  else
    FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
    printf '  FAIL %-58s expected rc=%s/%s dest, got rc=%s/%s dest: %s\n' \
      "$name" "$want_rc" "$want_n" "$rc" "$n" "${out%%$'\n'*}"
  fi
}

echo "--- concurrency guard: git push destination resolution ---"
echo "    (synthetic live claim on git:acme/repo@main, held by another agent)"

# The regression. A leading flag used to shift the positional read, the parse
# came back empty, and the guard silently fell back to the current branch
# (`main`) — blocking a push that cannot possibly collide.
check "push -q to a feature branch is allowed"      ALLOW   "git push -q origin feature-x"
check "push HEAD:feature-x is allowed"              ALLOW   "git push origin HEAD:feature-x"
check "push -u to a feature branch is allowed"      ALLOW   "git push -u origin feature-x"
check "push --force-with-lease to feature allowed"  ALLOW   "git push --force-with-lease origin feature-x"
check "push +src:feature-x is allowed"              ALLOW   "git push origin +HEAD:feature-x"
check "push -o ci.skip origin feature-x allowed"    ALLOW   "git push -o ci.skip origin feature-x"

# The other direction: the claimed branch must still be blocked in every shape.
check "push -q to the claimed branch is blocked"    BLOCKED "git push -q origin main"
check "push HEAD:main is blocked"                   BLOCKED "git push origin HEAD:main"
check "push --force-with-lease main is blocked"     BLOCKED "git push --force-with-lease origin main"
check "push refs/heads/main is blocked"             BLOCKED "git push origin refs/heads/main"
check "multiple refspecs: main among them blocked"  BLOCKED "git push origin feature-x main"
check "push --delete origin main is blocked"        BLOCKED "git push --delete origin main"
check "bare push (upstream is main) is blocked"     BLOCKED "git push"
check "push origin (no refspec) is blocked"         BLOCKED "git push origin"
check "push origin HEAD is blocked"                 BLOCKED "git push origin HEAD"
check "push chained after && is blocked"            BLOCKED "git add -A && git push -q origin main"

# Undeterminable destination: must be LOUD. Not allowed (would miss a real
# collision) and not silently blocked (would be the old guessing bug wearing a
# different hat).
check "push --all cannot be resolved -> CANNOT RUN" CANNOTRUN "git push --all origin"
check "push --mirror cannot be resolved"            CANNOTRUN "git push --mirror origin"

# Staleness still releases: a claim whose heartbeat is older than the threshold
# (900s) is not a live holder.
check "stale claim on main releases the branch"     ALLOW   "git push origin main" 1000

echo "--- concurrency guard: non-push targets (regression guard, must not change) ---"
# Bug B: an issue number that is not in the literal command string (a shell
# variable, or a wrapper function) is NOT determinable, and the guard says so
# rather than reporting 'free'.
check "gh issue comment with non-literal number"    CANNOTRUN 'gh issue comment "$ISSUE" --body hi'
check "unrelated command is allowed"                ALLOW   "ls -la"

echo "--- concurrency guard: a mention is not an invocation ---"
# The second defect. Target detection matched the RAW command string, so any
# `git push` / `gh issue comment` text inside a quoted argument, a -m message or a
# heredoc body was parsed as if it were a command being run: a plain
# `git commit` produced four phantom push destinations, one of them `main`, and
# was denied against the live claim. The parse must be structure-aware - only
# the first word of a real shell segment names a command.
check "commit message mentioning a push is allowed" ALLOW \
  'git commit -m "fixed: git push -q origin feature-x resolved to main"'
check_parse "that commit yields ZERO push destinations" \
  'git commit -m "fixed: git push -q origin feature-x resolved to main"' 2 0
check "heredoc body mentioning a push is allowed" ALLOW \
  "$(printf 'git commit -F - <<%sMSG%s\nfix: run git push origin main afterwards\nMSG\n' "'" "'")"
check "echo of a push instruction is allowed"       ALLOW \
  'echo "run git push origin main to deploy"'
check "single-quoted mention is allowed"            ALLOW \
  "git commit -m 'see git push origin main'"

# ...and the trap in the other direction: dropping quoted regions must NOT lose
# a REAL command that follows one. A push after a quoted argument is still a
# push, and must still be seen.
check "real push AFTER a quoted arg is blocked"     BLOCKED \
  'git commit -m "wip" && git push origin main'
check "real push after quoted arg, other branch"    ALLOW \
  'git commit -m "wip" && git push origin feature-x'
check "push before ; is still seen"                 BLOCKED \
  'git push origin main; echo done'
check "push inside sh -c is still seen"             BLOCKED \
  "bash -c 'git push origin main'"

# Same two-sided test for the `gh` targets: a mention inside a quoted string is
# text; a real invocation is still guarded exactly as before. Both run against a
# live claim on the issue, so the two outcomes are distinguishable - without the
# planted claim, "not a command" and "a command on a free artifact" both ALLOW.
check_extra "gh comment quoted inside a message"    ALLOW \
  'git commit -m "then: gh issue comment 42 --body done"' "github:acme/repo#issue-42"
check_extra "real gh issue comment 42 is blocked"          BLOCKED \
  'gh issue comment 42 --body done' "github:acme/repo#issue-42"
check_extra "real gh pr comment 42 is blocked"      BLOCKED \
  'gh pr comment 42 --body done' "github:acme/repo#pr-42"
check_extra "real gh comment on a free issue"       ALLOW \
  'gh issue comment 43 --body done' "github:acme/repo#issue-42"

echo "--- liveness probe uses ps -p, not kill -0 ---"
# `kill -0` returns EPERM for a live process owned by another user, which reads
# as "dead" and would release a live claim. pin the implementation.
if grep -q 'ps -p' "$ROOT/hooks/lib/agent-claim.sh" \
   && ! grep -qE '^[^#]*kill -0' "$ROOT/hooks/lib/agent-claim.sh"; then
  PASS=$((PASS + 1)); printf '  ok   %-58s [PIN]\n' "claim_pid_alive uses ps -p and not kill -0"
else
  FAIL=$((FAIL + 1)); FAILED_NAMES+=("ps -p liveness pin")
  printf '  FAIL %-58s\n' "claim_pid_alive must use ps -p, never kill -0"
fi

# --- redirections are not arguments (2>&1 minting a branch named "2") ---
#
# `2>&1` used to tokenize into a positional argument `2`, so every redirected
# git command claimed a branch named "2" for 900s and blocked unrelated pushes.
# Both directions: the phantom must not block, and a REAL push to the claimed
# branch must still block when it carries the same redirect — otherwise the fix
# is indistinguishable from switching the parser off.
check_redir() {
  local name="$1" expect="$2" cmd="$3" claimed="$4"
  local dir
  dir="$TMPROOT/claims.redir.$((PASS + FAIL))"
  plant_claim "$claimed" 0 "$dir"
  judge "$name" "$expect" "$(run_hook "$cmd" "$dir")"
}

echo "--- redirections are not branch names ---"
check_redir "2>&1 does not claim a branch named 2"      ALLOW \
  'git push origin feature-x 2>&1 | tail -4'            "git:acme/repo@2"
check_redir "2>/dev/null does not claim /dev/null"      ALLOW \
  'git push origin feature-x 2>/dev/null'               "git:acme/repo@/dev/null"
check_redir ">&2 does not claim a branch named 2"       ALLOW \
  'git push origin feature-x >&2'                       "git:acme/repo@2"
check_redir ">out.log does not claim the log file"      ALLOW \
  'git push origin feature-x >out.log 2>&1'             "git:acme/repo@out.log"
# The other direction: detection still works THROUGH a redirect.
check_redir "real push still blocked despite 2>&1"      BLOCKED \
  'git push origin main 2>&1 | tail -4'                 "git:acme/repo@main"
check_redir "real push still blocked despite 2>/dev/null" BLOCKED \
  'git push origin main 2>/dev/null'                    "git:acme/repo@main"

check_parse "redirect yields no phantom destination" \
  'git push origin feature-x 2>&1 | tail -4' 0 1

# --- the command's own `cd` decides which repo is claimed ---
#
# The hook payload's cwd is the SESSION's directory. An agent working in a
# worktree writes `cd <worktree> && git push`, and resolving the remote from the
# session directory attributed every push to the session's repo — blocking a
# repository nobody was editing while protecting nothing in the one they were.
OTHER="$TMPROOT/other"
mkdir -p "$OTHER"
git -C "$OTHER" init -q -b main
git -C "$OTHER" remote add origin https://github.com/acme/other.git
git -C "$OTHER" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init

echo "--- repo attribution follows the command, not the session ---"
dir="$TMPROOT/claims.cd.1"
plant_claim "git:acme/repo@main" 0 "$dir"
judge "cd into another repo is not claimed against the session repo" ALLOW \
  "$(run_hook "cd $OTHER && git push origin main" "$dir")"

dir="$TMPROOT/claims.cd.2"
plant_claim "git:acme/other@main" 0 "$dir"
judge "cd into another repo IS claimed against that repo" BLOCKED \
  "$(run_hook "cd $OTHER && git push origin main" "$dir")"

dir="$TMPROOT/claims.cd.3"
plant_claim "git:acme/other@main" 0 "$dir"
judge "git -C targets the other repo too" BLOCKED \
  "$(run_hook "git -C $OTHER push origin main" "$dir")"

dir="$TMPROOT/claims.cd.4"
plant_claim "git:acme/repo@main" 0 "$dir"
judge "no cd: the session repo is still the target" BLOCKED \
  "$(run_hook "git push origin main" "$dir")"

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'failing: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
