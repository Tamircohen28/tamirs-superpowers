#!/usr/bin/env bash
# test-hook-conformance.sh — one scenario corpus, every host dialect, one set of invariants.
#
# WHY THIS SUITE EXISTS BESIDE THE PER-HOST ONES
#   tests/hooks/test-codex-contract.sh, tests/test-cursor-lifecycle.sh and
#   tests/test-gemini-hooks.sh each replay a captured payload corpus through the hooks
#   the way that one host does, and assert that host's rules. None of them asks the
#   question this plugin's one-script-per-hook design rests on: given the SAME
#   situation, does the SAME hook answer the SAME thing on every host, in that
#   host's dialect, without tripping that host's parser? This suite builds two
#   situations once (a plain checkout; a checkout with an active objective whose
#   worktree sits beside a main-checkout file) and runs every wired hook under the
#   Claude Code, Codex, Cursor and Gemini dialects, judging:
#
#     1. exit code     Claude/Codex: 0, or 2 only from a PreToolUse guard that denies.
#                      Cursor: 0 (Cursor reads JSON on exit 0 and fail-closes on
#                      anything else for a failClosed hook). Gemini (through
#                      hooks/gemini-wrap.sh): 0, always.
#     2. stdout        empty, or exactly ONE JSON object. Never two objects, never a
#                      fragment, never a bare string — every host's parser rejects
#                      those, and Cursor fail-closes on them.
#     3. vocabulary    the object's keys are the host's documented keys for that
#                      event, and never `followup_message` on Cursor (which Cursor
#                      would auto-submit as the person's next message).
#     4. stderr        no interpreter trace: no `Traceback`, `jq: error`, `: line N:`,
#                      `command not found`, `unbound variable`.
#     5. time          under the timeout the hooks file declares for it.
#     6. selectivity   in the plain checkout no guard denies an ordinary edit or
#                      command on any host (a blanket deny is a broken guard).
#     7. equivalence   under the active objective, enforce-worktree-edits.sh denies a
#                      main-checkout write on EVERY host, each in its own dialect, and
#                      allows the same write inside the task worktree on every host.
#
#   A hook that passes here and fails on a real host has found a host edge the
#   dialect libraries do not know yet: add the shape to the per-host suite AND the
#   invariant here.
#
# shellcheck disable=SC2016  # ${CLAUDE_PLUGIN_ROOT} in hook commands is expanded by the shell that runs them, on purpose
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
harness_require jq python3 git

TMP="$(harness_tmpdir)"
export HOME="$TMP/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 SUPERPOWERS_WORKTREE_CLEANUP=0
export AGENT_CLAIM_DIR="$TMP/claims"
export CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PLUGIN_DATA="$TMP/plugin-data"
mkdir -p "$CLAUDE_PLUGIN_DATA" "$AGENT_CLAIM_DIR"
unset TAMIRS_USAGE_CAPTURE CLAUDE_ENV_FILE SUPERPOWERS_CURSOR_PLUGIN_PATH \
  CLAUDE_PLUGIN_OPTION_PUSHOVER_TOKEN CLAUDE_PLUGIN_OPTION_PUSHOVER_USER \
  PLUGIN_ROOT PLUGIN_DATA CODEX_HOME GEMINI_CWD GEMINI_PROJECT_DIR 2>/dev/null || true

# --- the two situations ------------------------------------------------------------------
PLAIN="$TMP/plain"; harness_new_repo "$PLAIN"
mkdir -p "$PLAIN/src" && printf 'export const x = 1\n' > "$PLAIN/src/app.ts"
git -C "$PLAIN" add -A >/dev/null && git -C "$PLAIN" commit -qm init

OBJ="$TMP/objective"; harness_new_repo "$OBJ"
mkdir -p "$OBJ/src" && printf 'export const x = 1\n' > "$OBJ/src/app.ts"
git -C "$OBJ" add -A >/dev/null && git -C "$OBJ" commit -qm init
mkdir -p "$OBJ/.dev-files/objectives/auth/handoffs" "$OBJ/.dev-files/objectives/auth/tasks"
jq -n '{id:"auth", status:"active", title:"Auth system", created_at:"2026-10-17T00:00:00Z"}' > "$OBJ/.dev-files/objectives/auth/objective.json"
git -C "$OBJ" worktree add -q -B agent/auth/task-001 "$OBJ/.agent-worktrees/auth/task-001" HEAD 2>/dev/null
WT="$OBJ/.agent-worktrees/auth/task-001"
# Every fixture path must live under the suite's temp dir: a hook run against an empty
# or repository path would write into the real checkout.
for d in "$PLAIN" "$OBJ" "$WT"; do
  case "$d" in "$TMP"/*) ;; *) echo "fixture path '$d' is not under $TMP; refusing to run" >&2; exit 2 ;; esac
  [ -d "$d" ] || { echo "fixture '$d' was not created" >&2; exit 2; }
done

# --- the hook tables, read from the shipped files ------------------------------------------
CLAUDE_HOOKS="$ROOT/hooks/hooks.json"
CODEX_HOOKS="$ROOT/platforms/codex/hooks.json"
CURSOR_HOOKS="$ROOT/platforms/cursor/hooks.json"
GEMINI_HOOKS="$ROOT/platforms/gemini/hooks.json"
for f in "$CLAUDE_HOOKS" "$CODEX_HOOKS" "$CURSOR_HOOKS" "$GEMINI_HOOKS"; do
  [ -f "$f" ] || { echo "missing $f" >&2; exit 2; }
done

# --- payloads (Claude shape is canonical; the dialects derive from it) ---------------------
# claude_payload <event> <cwd> [tool] [file-or-command]
claude_payload() {
  local ev="$1" cwd="$2" tool="${3:-}" arg="${4:-}"
  jq -n --arg ev "$ev" --arg cwd "$cwd" --arg tool "$tool" --arg arg "$arg" '
    {session_id:"conf-0001", transcript_path:($cwd+"/.transcript.jsonl"), cwd:$cwd, hook_event_name:$ev, permission_mode:"default"}
    | if $ev == "SessionStart" then . + {source:"startup"}
      elif $ev == "SessionEnd" then . + {reason:"exit"}
      elif $ev == "UserPromptSubmit" then . + {prompt:"Fix the login redirect bug in src/app.ts"}
      elif $ev == "PreToolUse" or $ev == "PostToolUse" then
        . + {tool_name:$tool, tool_use_id:"call-0001"}
        + (if $tool == "Bash" then {tool_input:{command:$arg, description:"probe"}}
           else {tool_input:{file_path:$arg, old_string:"1", new_string:"2"}} end)
        + (if $ev == "PostToolUse" then {tool_response:{success:true}} else {} end)
      elif $ev == "Stop" then . + {stop_hook_active:false}
      elif $ev == "SubagentStop" then . + {stop_hook_active:false, agent_id:"agent-0001"}
      elif $ev == "PreCompact" then . + {trigger:"auto", custom_instructions:""}
      elif $ev == "Notification" then . + {message:"Claude is waiting for your input", notification_type:"idle_prompt"}
      elif $ev == "StopFailure" then . + {error_type:"rate_limit", error:"rate limit reached"}
      elif $ev == "DirectoryAdded" then . + {directory:$cwd}
      else . end'
}
# codex_payload: the Claude shape plus the Codex-only turn_id (the payload fallback
# hook_detect_platform documents); the environment carries PLUGIN_ROOT/PLUGIN_DATA.
codex_payload() { claude_payload "$@" | jq -c '. + {turn_id:"01a1480e-39dc-7131-8dd0-5becbd825a5e", model:"placeholder"}'; }
# cursor_payload <cursorEvent> <cwd> [tool] [file-or-command]
cursor_payload() {
  local ev="$1" cwd="$2" tool="${3:-}" arg="${4:-}"
  jq -n --arg ev "$ev" --arg cwd "$cwd" --arg tool "$tool" --arg arg "$arg" '
    {conversation_id:"conv-0123456789abcdef", generation_id:"gen-0001", model:"auto", model_id:"auto",
     hook_event_name:$ev, cursor_version:"3.24.12", workspace_roots:[$cwd],
     transcript_path:($cwd+"/.cursor/transcripts/conv.jsonl")}
    | if $ev == "preToolUse" or $ev == "postToolUse" then
        . + {tool_name:$tool, tool_use_id:"call-0001", cwd:$cwd, tool_input:{file_path:$arg, contents:"hello"}, agent_message:""}
        + (if $ev == "postToolUse" then {result:{success:true}} else {} end)
      elif $ev == "beforeShellExecution" then . + {tool_use_id:"call-0001", command:$arg, cwd:$cwd, sandbox:"disabled"}
      elif $ev == "beforeSubmitPrompt" then . + {prompt:"Fix the login redirect bug in src/app.ts", attachments:[]}
      elif $ev == "sessionStart" then . + {is_background_agent:false, composer_mode:"agent"}
      elif $ev == "sessionEnd" then . + {reason:"user_exit"}
      elif $ev == "stop" then . + {status:"completed", loop_count:1}
      elif $ev == "subagentStop" then . + {status:"completed", subagent_id:"sub-0001"}
      elif $ev == "preCompact" then . + {trigger:"auto"}
      elif $ev == "workspaceOpen" then .
      else . end'
}
# gemini_payload <geminiEvent> <cwd> [geminiTool] [file-or-command]
gemini_payload() {
  local ev="$1" cwd="$2" tool="${3:-}" arg="${4:-}"
  jq -n --arg ev "$ev" --arg cwd "$cwd" --arg tool "$tool" --arg arg "$arg" '
    {session_id:"s", transcript_path:"/t", cwd:$cwd, hook_event_name:$ev, timestamp:"2026-10-17T00:00:00Z"}
    | if $ev == "BeforeTool" or $ev == "AfterTool" then
        . + {tool_name:$tool}
        + (if $tool == "run_shell_command" then {tool_input:{command:$arg}} else {tool_input:{file_path:$arg, content:"x"}} end)
        + (if $ev == "AfterTool" then {tool_response:{output:"ok"}} else {} end)
      elif $ev == "BeforeAgent" then . + {prompt:"Fix the login redirect bug in src/app.ts"}
      elif $ev == "AfterAgent" then . + {prompt_response:"done"}
      elif $ev == "SessionStart" then . + {source:"startup"}
      elif $ev == "SessionEnd" then . + {reason:"exit"}
      elif $ev == "PreCompress" then . + {trigger:"auto"}
      elif $ev == "Notification" then . + {message:"waiting", notification_type:"idle"}
      else . end'
}

# --- the runner ---------------------------------------------------------------------------
# run_cmd <dialect> <cwd> <command> <payload> <timeout-seconds>  -> sets RC OUT ERR SECS
RC=0; OUT=""; ERR=""; SECS=0
run_cmd() {
  local dialect="$1" cwd="$2" cmd="$3" payload="$4" tmo="$5" t0 t1
  local errf="$TMP/err.$$"
  t0="$(date +%s)"
  case "$dialect" in
    codex)
      OUT="$(cd "$cwd" && printf '%s' "$payload" | PLUGIN_ROOT="$ROOT" PLUGIN_DATA="$CLAUDE_PLUGIN_DATA" CODEX_HOME="$TMP/codex-home" bash -c "$cmd" 2>"$errf")"; RC=$? ;;
    cursor)
      OUT="$(cd "$cwd" && printf '%s' "$payload" | CURSOR_PLUGIN_ROOT="$ROOT" bash -c "$cmd" 2>"$errf")"; RC=$? ;;
    gemini)
      OUT="$(cd "$cwd" && printf '%s' "$payload" | extensionPath="$ROOT" bash -c "$cmd" 2>"$errf")"; RC=$? ;;
    *)
      OUT="$(cd "$cwd" && printf '%s' "$payload" | bash -c "$cmd" 2>"$errf")"; RC=$? ;;
  esac
  t1="$(date +%s)"; SECS=$((t1 - t0))
  ERR="$(cat "$errf" 2>/dev/null)"; rm -f "$errf"
  [ "$SECS" -le "$tmo" ] || bad "$dialect: $cmd finished in time" "took ${SECS}s, timeout ${tmo}s"
}

# one_object <stdout> -> yes if empty or exactly one JSON object
one_object() {
  [ -z "${1//[[:space:]]/}" ] && { echo yes; return; }
  local n; n="$(printf '%s' "$1" | jq -s 'length' 2>/dev/null || echo 0)"
  if [ "$n" = "1" ] && printf '%s' "$1" | jq -e 'type == "object"' >/dev/null 2>&1; then echo yes; else echo no; fi
}
keys_of() { printf '%s' "$1" | jq -r 'keys[]' 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//'; }
# keys_within <stdout> <allowed words...> -> "" if every key is allowed, else the stray keys
keys_within() {
  local out="$1"; shift; local k stray=""
  [ -z "${out//[[:space:]]/}" ] && { echo ""; return; }
  for k in $(keys_of "$out"); do
    case " $* " in *" $k "*) ;; *) stray="$stray $k" ;; esac
  done
  echo "${stray# }"
}
trace_in() { printf '%s' "$1" | grep -E 'Traceback|jq: error|: line [0-9]+:|command not found|unbound variable' | head -1; }

CLAUDE_KEYS="continue suppressOutput stopReason decision reason systemMessage hookSpecificOutput"
# sessionTitle (SessionStart/UserPromptSubmit) and terminalSequence (Notification) are
# documented Claude Code fields the hooks here use.
CLAUDE_HSO_KEYS="hookEventName permissionDecision permissionDecisionReason additionalContext updatedInput sessionTitle terminalSequence"
GEMINI_KEYS="decision reason systemMessage hookSpecificOutput suppressOutput continue stopReason"
cursor_keys_for() {
  case "$1" in
    preToolUse|beforeShellExecution) echo "permission user_message agent_message" ;;
    postToolUse) echo "user_message" ;;
    beforeSubmitPrompt) echo "continue user_message" ;;
    sessionStart) echo "additional_context env" ;;
    sessionEnd) echo "" ;;
    stop|subagentStop|preCompact) echo "user_message" ;;
    workspaceOpen) echo "pluginPaths" ;;
    *) echo "" ;;
  esac
}

# judge_common <label> <dialect> <event> <allowed-exit-codes>
judge_common() {
  local label="$1" dialect="$2" ev="$3" allowed="$4" stray tr
  case " $allowed " in *" $RC "*) ok "$label: exit $RC" ;; *) bad "$label: exit code" "got $RC (allowed: $allowed); stderr: $(printf '%s' "$ERR" | head -c 200)" ;; esac
  judge "$label: stdout is empty or one JSON object" yes "$(one_object "$OUT")"
  tr="$(trace_in "$ERR")"; [ -z "$tr" ] && ok "$label: no interpreter trace on stderr" || bad "$label: no interpreter trace on stderr" "$tr"
  case "$dialect" in
    claude|codex)
      stray="$(keys_within "$OUT" $CLAUDE_KEYS)"
      [ -z "$stray" ] && ok "$label: keys are the Claude hook vocabulary" || bad "$label: keys are the Claude hook vocabulary" "stray: $stray"
      if printf '%s' "$OUT" | jq -e '.hookSpecificOutput' >/dev/null 2>&1; then
        stray="$(keys_within "$(printf '%s' "$OUT" | jq -c '.hookSpecificOutput')" $CLAUDE_HSO_KEYS)"
        [ -z "$stray" ] && ok "$label: hookSpecificOutput keys are documented" || bad "$label: hookSpecificOutput keys are documented" "stray: $stray"
        hev="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName // empty')"
        [ -z "$hev" ] || judge "$label: hookEventName names the event" "$ev" "$hev"
      fi
      if [ "$dialect" = codex ] && { [ "$ev" = Stop ] || [ "$ev" = SubagentStop ]; }; then
        [ -n "${OUT//[[:space:]]/}" ] && ok "$label: a Codex Stop-family hook prints JSON" || bad "$label: a Codex Stop-family hook prints JSON" "stdout empty (Codex reads that as a failed hook)"
      fi ;;
    cursor)
      # shellcheck disable=SC2046  # the allowed keys are a word list on purpose
      stray="$(keys_within "$OUT" $(cursor_keys_for "$ev"))"
      [ -z "$stray" ] && ok "$label: keys are Cursor's for $ev" || bad "$label: keys are Cursor's for $ev" "stray: $stray"
      printf '%s' "$OUT" | jq -e 'has("followup_message")' >/dev/null 2>&1 && bad "$label: never followup_message" "Cursor would auto-submit it as the user's next message" || ok "$label: never followup_message" ;;
    gemini)
      stray="$(keys_within "$OUT" $GEMINI_KEYS)"
      [ -z "$stray" ] && ok "$label: keys are Gemini's envelope" || bad "$label: keys are Gemini's envelope" "stray: $stray"
      [ -n "${OUT//[[:space:]]/}" ] && ok "$label: the wrapper printed one object" || bad "$label: the wrapper printed one object" "stdout empty"
      if [ "$ev" != BeforeTool ] && printf '%s' "$OUT" | jq -e '.decision == "deny"' >/dev/null 2>&1; then
        bad "$label: deny only on BeforeTool" "a $ev hook denied"
      fi ;;
  esac
}

denied() { # denied <dialect> <stdout> <rc> -> yes/no
  case "$1" in
    claude|codex) { [ "$3" = 2 ] || printf '%s' "$2" | jq -e '.hookSpecificOutput.permissionDecision == "deny" or .decision == "block"' >/dev/null 2>&1; } && echo yes || echo no ;;
    cursor) printf '%s' "$2" | jq -e '.permission == "deny"' >/dev/null 2>&1 && echo yes || echo no ;;
    gemini) printf '%s' "$2" | jq -e '.decision == "deny"' >/dev/null 2>&1 && echo yes || echo no ;;
  esac
}

# --- 1. Claude and Codex: every wired hook, both situations --------------------------------
for dialect in claude codex; do
  section "$dialect dialect: every hook in $( [ "$dialect" = claude ] && echo hooks/hooks.json || echo platforms/codex/hooks.json )"
  HF="$CLAUDE_HOOKS"; [ "$dialect" = codex ] && HF="$CODEX_HOOKS"
  while IFS=$'\t' read -r ev matcher cmd tmo; do
    [ -n "$cmd" ] || continue
    tmo="${tmo:-60}"
    case "$ev" in
      WorktreeCreate|WorktreeRemove) continue ;;   # create/remove a worktree: the lifecycle suite covers them
      PreToolUse|PostToolUse)
        if printf '%s' "$matcher" | grep -qE 'Bash|Shell'; then tool=Bash; arg="git status --short"
        else tool=Edit; arg="src/app.ts"; fi ;;
      *) tool=""; arg="" ;;
    esac
    for scen in plain objective; do
      cwd="$PLAIN"; [ "$scen" = objective ] && cwd="$OBJ"
      a="$arg"; [ "$tool" = Edit ] && a="$cwd/src/app.ts"
      if [ "$dialect" = codex ]; then pl="$(codex_payload "$ev" "$cwd" "$tool" "$a")"; else pl="$(claude_payload "$ev" "$cwd" "$tool" "$a")"; fi
      name="$(basename "${cmd##*/hooks/}" | sed 's/[" ].*//')"
      label="$dialect/$scen/$ev/$name"
      run_cmd "$dialect" "$cwd" "$cmd" "$pl" "$tmo"
      judge_common "$label" "$dialect" "$ev" "0 2"
      # selectivity: in the plain checkout nothing denies an ordinary edit or command.
      # enforce-worktree-edits.sh is the one guard whose purpose is to deny the main
      # checkout (the equivalence section below holds it to the same answer on every
      # host), so it is not a selectivity probe.
      if [ "$scen" = plain ] && [ "$ev" = PreToolUse ] && [ "$name" != enforce-worktree-edits.sh ]; then
        judge "$label: an ordinary $tool in a plain checkout is not denied" no "$(denied "$dialect" "$OUT" "$RC")"
      fi
      # exit 2 is a deny and nothing else
      if [ "$RC" = 2 ] && [ "$ev" != PreToolUse ]; then bad "$label: exit 2 outside PreToolUse" "a non-guard hook blocked"; fi
    done
  done < <(jq -r '.hooks | to_entries[] | .key as $ev | .value[] | (.matcher // "-") as $m | .hooks[] | [$ev, $m, .command, (.timeout // 60 | tostring)] | @tsv' "$HF")
done

# --- 2. Cursor: every hook in the bundle, both situations ----------------------------------
section "cursor dialect: every hook in platforms/cursor/hooks.json"
while IFS=$'\t' read -r ev cmd tmo; do
  [ -n "$cmd" ] || continue
  case "$ev" in
    preToolUse|postToolUse) tool=Write ;;
    beforeShellExecution) tool=Shell ;;
    *) tool="" ;;
  esac
  for scen in plain objective; do
    cwd="$PLAIN"; [ "$scen" = objective ] && cwd="$OBJ"
    a=""; [ "$tool" = Write ] && a="$cwd/src/app.ts"; [ "$tool" = Shell ] && a="git status --short"
    pl="$(cursor_payload "$ev" "$cwd" "$tool" "$a")"
    name="$(basename "${cmd##*/hooks/}")"
    label="cursor/$scen/$ev/$name"
    run_cmd cursor "$cwd" "$cmd" "$pl" "${tmo:-60}"
    judge_common "$label" cursor "$ev" "0"
    if [ "$scen" = plain ] && { [ "$ev" = preToolUse ] || [ "$ev" = beforeShellExecution ]; } && [ "$name" != enforce-worktree-edits.sh ]; then
      judge "$label: an ordinary $tool in a plain checkout is not denied" no "$(denied cursor "$OUT" "$RC")"
    fi
    if [ "$ev" = preToolUse ] || [ "$ev" = beforeShellExecution ]; then
      printf '%s' "$OUT" | jq -e 'has("permission")' >/dev/null 2>&1 && ok "$label: a Cursor permission hook answers permission" || bad "$label: a Cursor permission hook answers permission" "stdout: $OUT (a failClosed hook with no permission key is a deny)"
    fi
  done
done < <(jq -r '.hooks | to_entries[] | .key as $ev | .value[] | [$ev, .command, (.timeout // 60 | tostring)] | @tsv' "$CURSOR_HOOKS")

# --- 3. Gemini: every hook in the generated file, through the wrapper, both situations -----
section "gemini dialect: every hook in platforms/gemini/hooks.json"
while IFS=$'\t' read -r ev matcher cmd tmo_ms; do
  [ -n "$cmd" ] || continue
  tmo=$(( ${tmo_ms:-60000} / 1000 )); [ "$tmo" -ge 1 ] || tmo=1
  case "$ev" in
    BeforeTool|AfterTool)
      if printf '%s' "$matcher" | grep -q run_shell_command; then tool=run_shell_command; arg="git status --short"
      else tool=replace; arg="src/app.ts"; fi ;;
    *) tool=""; arg="" ;;
  esac
  for scen in plain objective; do
    cwd="$PLAIN"; [ "$scen" = objective ] && cwd="$OBJ"
    a="$arg"; [ "$tool" = replace ] && a="$cwd/src/app.ts"
    pl="$(gemini_payload "$ev" "$cwd" "$tool" "$a")"
    name="$(printf '%s' "$cmd" | sed -n 's/.*gemini-wrap.sh" "\${extensionPath}\/hooks\/\([^"]*\)".*/\1/p')"
    label="gemini/$scen/$ev/${name:-?}"
    run_cmd gemini "$cwd" "$cmd" "$pl" "$tmo"
    judge_common "$label" gemini "$ev" "0"
    if [ "$scen" = plain ] && [ "$ev" = BeforeTool ] && [ "$name" != enforce-worktree-edits.sh ]; then
      judge "$label: an ordinary $tool in a plain checkout is not denied" no "$(denied gemini "$OUT" "$RC")"
    fi
  done
done < <(jq -r '.hooks | to_entries[] | .key as $ev | .value[] | (.matcher // "-") as $m | .hooks[] | [$ev, $m, .command, (.timeout // 60000 | tostring)] | @tsv' "$GEMINI_HOOKS")

# --- 4. Equivalence: the same guard, the same situation, four dialects, one answer --------
section "equivalence: enforce-worktree-edits.sh under an active objective"
MAIN_FILE="$OBJ/src/app.ts"; WT_FILE="$WT/src/app.ts"
CL_CMD='bash "${CLAUDE_PLUGIN_ROOT}"/hooks/enforce-worktree-edits.sh'
CU_CMD='bash ${CURSOR_PLUGIN_ROOT}/hooks/enforce-worktree-edits.sh'
GE_CMD='bash "${extensionPath}/hooks/gemini-wrap.sh" "${extensionPath}/hooks/enforce-worktree-edits.sh"'
for dialect in claude codex cursor gemini; do
  case "$dialect" in
    claude) run_cmd claude "$OBJ" "$CL_CMD" "$(claude_payload PreToolUse "$OBJ" Edit "$MAIN_FILE")" 15 ;;
    codex)  run_cmd codex  "$OBJ" "$CL_CMD" "$(codex_payload  PreToolUse "$OBJ" Edit "$MAIN_FILE")" 15 ;;
    cursor) run_cmd cursor "$OBJ" "$CU_CMD" "$(cursor_payload preToolUse "$OBJ" Write "$MAIN_FILE")" 15 ;;
    gemini) run_cmd gemini "$OBJ" "$GE_CMD" "$(gemini_payload BeforeTool "$OBJ" replace "$MAIN_FILE")" 15 ;;
  esac
  judge "$dialect: a main-checkout write under an active objective is DENIED" yes "$(denied "$dialect" "$OUT" "$RC")"
  judge "$dialect: the deny is one JSON object" yes "$(one_object "$OUT")"
  reason="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // .reason // .user_message // .agent_message // empty' 2>/dev/null)"
  [ -n "$reason" ] && ok "$dialect: the deny carries a reason" || bad "$dialect: the deny carries a reason" "stdout: $OUT stderr: $(printf '%s' "$ERR" | head -c 120)"
  case "$dialect" in
    claude) run_cmd claude "$OBJ" "$CL_CMD" "$(claude_payload PreToolUse "$WT" Edit "$WT_FILE")" 15 ;;
    codex)  run_cmd codex  "$OBJ" "$CL_CMD" "$(codex_payload  PreToolUse "$WT" Edit "$WT_FILE")" 15 ;;
    cursor) run_cmd cursor "$OBJ" "$CU_CMD" "$(cursor_payload preToolUse "$WT" Write "$WT_FILE")" 15 ;;
    gemini) run_cmd gemini "$OBJ" "$GE_CMD" "$(gemini_payload BeforeTool "$WT" replace "$WT_FILE")" 15 ;;
  esac
  judge "$dialect: the same write inside the task worktree is ALLOWED" no "$(denied "$dialect" "$OUT" "$RC")"
  judge "$dialect: the allow exits 0" 0 "$RC"
done

section "equivalence: enforce-worktree-edits.sh in a plain checkout (no objective)"
for dialect in claude codex cursor gemini; do
  case "$dialect" in
    claude) run_cmd claude "$PLAIN" "$CL_CMD" "$(claude_payload PreToolUse "$PLAIN" Edit "$PLAIN/src/app.ts")" 15 ;;
    codex)  run_cmd codex  "$PLAIN" "$CL_CMD" "$(codex_payload  PreToolUse "$PLAIN" Edit "$PLAIN/src/app.ts")" 15 ;;
    cursor) run_cmd cursor "$PLAIN" "$CU_CMD" "$(cursor_payload preToolUse "$PLAIN" Write "$PLAIN/src/app.ts")" 15 ;;
    gemini) run_cmd gemini "$PLAIN" "$GE_CMD" "$(gemini_payload BeforeTool "$PLAIN" replace "$PLAIN/src/app.ts")" 15 ;;
  esac
  judge "$dialect: a main-checkout write with no worktree is DENIED with a remedy" yes "$(denied "$dialect" "$OUT" "$RC")"
  reason="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // .reason // .user_message // .agent_message // empty' 2>/dev/null)"
  case "$reason" in *worktree*) ok "$dialect: the remedy names a worktree" ;; *) bad "$dialect: the remedy names a worktree" "reason: $reason" ;; esac
done

section "equivalence: guard-sensitive-files.sh on a protected path"
PROT="$PLAIN/.github/workflows/ci.yml"; mkdir -p "$PLAIN/.github/workflows"
CL_CMD='bash "${CLAUDE_PLUGIN_ROOT}"/hooks/guard-sensitive-files.sh'
CU_CMD='bash ${CURSOR_PLUGIN_ROOT}/hooks/guard-sensitive-files.sh'
GE_CMD='bash "${extensionPath}/hooks/gemini-wrap.sh" "${extensionPath}/hooks/guard-sensitive-files.sh"'
for dialect in claude codex cursor gemini; do
  case "$dialect" in
    claude) run_cmd claude "$PLAIN" "$CL_CMD" "$(claude_payload PreToolUse "$PLAIN" Edit "$PROT")" 15 ;;
    codex)  run_cmd codex  "$PLAIN" "$CL_CMD" "$(codex_payload  PreToolUse "$PLAIN" Edit "$PROT")" 15 ;;
    cursor) run_cmd cursor "$PLAIN" "$CU_CMD" "$(cursor_payload preToolUse "$PLAIN" Write "$PROT")" 15 ;;
    gemini) run_cmd gemini "$PLAIN" "$GE_CMD" "$(gemini_payload BeforeTool "$PLAIN" replace "$PROT")" 15 ;;
  esac
  judge "$dialect: a workflow write is DENIED" yes "$(denied "$dialect" "$OUT" "$RC")"
  judge "$dialect: the deny is one JSON object" yes "$(one_object "$OUT")"
done

harness_summary
