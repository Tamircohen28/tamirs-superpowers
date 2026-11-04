#!/usr/bin/env bash
# test-permission-guard.sh — hooks/permission-guard.sh (PG) under crafted stdin, per host
# dialect (ADR 004 items 4 and 12; D1, D2, D5-D8).
#
# WHAT IT HOLDS
#   1. the fast path: an ordinary command is allowed on every host without the resolver,
#      and the bash pre-filter lets through no command the catalog can map to a guarded id;
#   2. the catalog's own fixture table (tests/test-permission-catalog.sh FIXTURES and
#      MCP_FIXTURES, read from that file, not copied) maps to the same ids through PG's
#      bash tokeniser and matcher as through the reference matcher;
#   3. the D1 equivalents of a merge, a branch delete and a force push, and the R4
#      tty.drive / process.spawn.agent_host forms, answer ask on Claude Code and deny on
#      Codex (whose hook ask fails open, X1) and Cursor (deny only until S1);
#   4. fail closed: no resolver, a resolver that crashes or prints garbage, a corrupt
#      catalog, no python3, no jq, a non-JSON payload, a NUL byte: all deny;
#   5. the conditions PG establishes locally (default branch, tag refs, uncommitted and
#      unpushed work), the ones it reads from GitHub under one 3 s deadline (the default
#      branch with no refs/remotes/<remote>/HEAD, required checks for gh pr merge --admin)
#      and the context it refuses to guess (cd chains, export, GH_REPO=);
#   6. levels through a real user file + lock (standard), the call stamp (D8), the
#      policy.edit forms (setup.sh --permission-level, plugin-config.sh, host config CLIs);
#   7. the OpenCode dialect ("host": "opencode" in the payload, as guard.ts sends it): ask
#      for R2 only, deny for every R3/R4, UNCLASSIFIED and policy.edit call, and never a
#      looser answer on a deny-only host that carries the same marker (D8);
#   8. the active skill from hooks/permission-intent.sh's intent/<sid>.json: --skill and
#      --objective reach the resolver, a skill raise applies only when user_typed, a
#      lowering always, and a missing, corrupt, unsafe, stale or foreign context is the
#      global level (D5, D8, SR S-09);
#   9. plugin-config.sh confirm <nonce>: the Claude dialog names the pending request's
#      skill, level, target and expiry (or its rows), PG stamps asked/<nonce>.json with the
#      bytes it showed, and a nonce with no usable record is a deny (D5, D8 call stamp);
#  10. hook_ask's dialects, the shared tokeniser's two modes, and the hook wiring.
#
# HERMETIC
#   The resolver reads the passwd home, never HOME. Its test override,
#   TAMIRS_PERMISSION_TEST_ROOT, is honoured only under an ancestor shell running one of
#   the permission suites, this one included (scripts/lib/permission-common.sh header).
#   The first check proves the override took; without it the suite stops rather than
#   judge the developer's own permission file. Every gh PG's lookups run is
#   tests/lib/fake-gh.sh, first on PATH, with `gh pr checks` (which the shim does not
#   serve) answered from files in the temp dir by a wrapper that hands every other call
#   to the shim. No network, no model call.
#
# Bash 3.2 compatible.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
# shellcheck source=tests/lib/fake-gh.sh
source "$ROOT/tests/lib/fake-gh.sh"
harness_require jq python3 git

HOOK="$ROOT/hooks/permission-guard.sh"
T="$(harness_tmpdir)"
T="$(cd "$T" && pwd -P)"
chmod 700 "$T"
PH="$T/passwd-home"
mkdir -m 700 "$PH"
export TAMIRS_PERMISSION_TEST_ROOT="$PH"
export HOME="$T/env-home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$T/gitconfig"
: > "$GIT_CONFIG_GLOBAL"
unset CODEX_HOME GEMINI_SESSION_ID GEMINI_PROJECT_DIR GEMINI_CWD TS_PERMISSION_LEVEL \
  CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL TAMIRS_AUTO_MERGE GH_REPO GH_HOST PLUGIN_ROOT PLUGIN_DATA \
  CLAUDE_PLUGIN_ROOT CURSOR_PLUGIN_ROOT 2>/dev/null || true

# gh: tests/lib/fake-gh.sh, first on PATH. Scenario dir $FX/none serves nothing, so a
# lookup PG makes fails (unknown) unless a case switches scenario. `gh pr checks` is
# answered from $CHK.json / $CHK.rc / $CHK.sleep (absent json = gh exits 1, as gh does
# when no required check is reported) and logged beside the shim's own lines.
FX="$T/fx"
mkdir -p "$FX/_defaults" "$FX/none" "$FX/develop" "$FX/feat-default" "$FX/slow"
printf '{"defaultBranchRef":{"name":"develop"}}\n' > "$FX/develop/repo-view.json"
printf '{"defaultBranchRef":{"name":"feat"}}\n' > "$FX/feat-default/repo-view.json"
printf '{"defaultBranchRef":{"name":"develop"}}\n' > "$FX/slow/repo-view.json"
fake_gh_install "$T/bin" "$T/gh.log" "$FX/none"
CHK="$T/checks"
cat > "$T/bin/gh" <<SH
#!/usr/bin/env bash
# fake-gh.sh, plus the two answers it does not serve: gh pr checks, and a slow scenario.
case "\$FAKE_GH_FIXTURES" in */slow) sleep 6 ;; esac
if [ "\${1:-}" = pr ] && [ "\${2:-}" = checks ]; then
  printf '0\tGET\tgh:pr/checks\t-\t%s\n' "\$*" >> "\$FAKE_GH_LOG"
  [ -f "$CHK.sleep" ] && sleep "\$(cat "$CHK.sleep")"
  [ -f "$CHK.json" ] || { echo "no required checks reported on the 'feat' branch" >&2; exit 1; }
  cat "$CHK.json"
  exit "\$(cat "$CHK.rc" 2>/dev/null || echo 0)"
fi
exec bash "$ROOT/tests/lib/fake-gh.sh" "\$@"
SH
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"
checks() { rm -f "$CHK.json" "$CHK.rc" "$CHK.sleep"; [ "$#" -gt 0 ] && printf '%s\n' "$1" > "$CHK.json"; [ -n "${2:-}" ] && printf '%s\n' "$2" > "$CHK.rc"; return 0; }

section "the suite is hermetic"
judge "gh is the fake (tests/lib/fake-gh.sh)" yes "$(gh --version 2>/dev/null | grep -q fake-gh && echo yes || echo no)"
hs="$(bash "$ROOT/scripts/resolve-permission.sh" repo.read --json 2>/dev/null | jq -r '.home_source // empty')"
if [ "$hs" != "test-root" ]; then
  echo "FATAL: the resolver did not take TAMIRS_PERMISSION_TEST_ROOT (home_source=$hs); refusing to judge the real permission file" >&2
  exit 1
fi
ok "the resolver reads the temp passwd home ($PH)"

# --- fixtures ------------------------------------------------------------------------
REPO="$T/repo"
harness_new_repo "$REPO" main
git -C "$REPO" remote add origin https://github.com/me/app.git
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$REPO" checkout -q -b feat
printf 'x\n' > "$REPO/README"
git -C "$REPO" add README && git -C "$REPO" commit -qm readme
git -C "$REPO" update-ref refs/remotes/origin/feat HEAD
git -C "$REPO" branch -q gone refs/remotes/origin/main
git -C "$REPO" branch -q local-only HEAD
git -C "$REPO" tag v1.0 refs/remotes/origin/main
NOHEAD="$T/nohead"
harness_new_repo "$NOHEAD" main
git -C "$NOHEAD" remote add origin https://github.com/me/other.git
git -C "$NOHEAD" checkout -q -b feat
for d in "$REPO" "$NOHEAD"; do
  case "$d" in "$T"/*) ;; *) echo "fixture $d escaped the temp dir" >&2; exit 2 ;; esac
done

PFX='mcp__plugin_tamirs-superpowers_github__'
claude_bash() { jq -nc --arg c "$1" --arg d "${2:-$REPO}" '{session_id:"pg-1",transcript_path:"/t",cwd:$d,hook_event_name:"PreToolUse",permission_mode:"default",tool_name:"Bash",tool_use_id:"call-1",tool_input:{command:$c,description:"probe"}}'; }
codex_bash() { claude_bash "$@" | jq -c '. + {turn_id:"01a1480e-39dc-7131-8dd0-5becbd825a5e", model:"placeholder"}'; }
cursor_pre() { jq -nc --arg t "$1" --arg c "$2" --arg d "${3:-$REPO}" '{conversation_id:"conv-1",generation_id:"g",hook_event_name:"preToolUse",cursor_version:"3.27.22",workspace_roots:[$d],cwd:$d,tool_name:$t,tool_use_id:"call-1",tool_input:{command:$c}}'; }
cursor_shell() { jq -nc --arg c "$1" --arg d "${2:-$REPO}" '{conversation_id:"conv-1",generation_id:"g",hook_event_name:"beforeShellExecution",cursor_version:"3.27.22",workspace_roots:[$d],cwd:$d,command:$c,sandbox:"disabled"}'; }
claude_mcp() { jq -nc --arg t "$1" --argjson a "$2" --arg d "${3:-$REPO}" '{session_id:"pg-1",cwd:$d,hook_event_name:"PreToolUse",tool_name:$t,tool_input:$a}'; }
cursor_mcp() { jq -nc --arg t "$1" --argjson a "$2" --arg d "${3:-$REPO}" '{conversation_id:"conv-1",hook_event_name:"preToolUse",cursor_version:"3.27.22",workspace_roots:[$d],cwd:$d,tool_name:$t,tool_input:$a}'; }

# run_pg <dialect> <payload> [hook]  -> OUT RC ERR
OUT="" RC=0 ERR=""
run_pg() {
  local dialect="$1" payload="$2" hook="${3:-$HOOK}" errf="$T/err.$$"
  case "$dialect" in
    codex)  OUT="$(printf '%s' "$payload" | CODEX_HOME="$T/codex-home" bash "$hook" 2>"$errf")" ;;
    gemini) OUT="$(printf '%s' "$payload" | GEMINI_SESSION_ID=g-1 GEMINI_PROJECT_DIR="$REPO" bash "$hook" 2>"$errf")" ;;
    *)      OUT="$(printf '%s' "$payload" | bash "$hook" 2>"$errf")" ;;
  esac
  RC=$?
  ERR="$(cat "$errf" 2>/dev/null)"
  rm -f "$errf"
}
verdict() { # verdict <dialect> -> allow|ask|deny|<invalid>
  local n
  n="$(printf '%s' "$OUT" | jq -s 'length' 2>/dev/null || echo 0)"
  [ "$n" = 1 ] || { echo "invalid($n objects)"; return; }
  case "$1" in
    cursor) printf '%s' "$OUT" | jq -r '.permission // "none"' ;;
    *) printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' ;;
  esac
}
reason() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // .user_message // ""' 2>/dev/null; }
# expect <label> <dialect> <payload> <verdict> [reason-substring] [hook]
expect() {
  local label="$1" dialect="$2" payload="$3" want="$4" needle="${5:-}" got
  run_pg "$dialect" "$payload" "${6:-$HOOK}"
  got="$(verdict "$dialect")"
  if [ "$got" != "$want" ] || [ "$RC" != 0 ]; then
    bad "$label" "expected $want (exit 0), got $got (exit $RC); reason: $(reason | head -c 300)"
    return
  fi
  if [ -n "$needle" ] && [ "$(has "$(reason)" "$needle")" != yes ]; then
    bad "$label" "verdict $got, but the reason does not name '$needle': $(reason | head -c 300)"
    return
  fi
  ok "$label"
}
classify() { bash "$HOOK" --classify "$1" "${2:-$REPO}"; }

# --- 1. the fast path --------------------------------------------------------------
section "fast path: ordinary commands are allowed on every host"
for c in 'ls -la' 'git status' 'git log --oneline -5' 'echo hello | grep h' 'cat README && wc -l README' 'python3 tests/x.py'; do
  expect "claude: $c" claude "$(claude_bash "$c")" allow
  expect "codex: $c" codex "$(codex_bash "$c")" allow
  expect "cursor preToolUse Shell: $c" cursor "$(cursor_pre Shell "$c")" allow
  expect "cursor beforeShellExecution: $c" cursor "$(cursor_shell "$c")" allow
done
judge "claude allow is {}" '{}' "$(run_pg claude "$(claude_bash 'git status')"; printf '%s' "$OUT")"
judge "cursor allow is {\"permission\":\"allow\"}" '{"permission":"allow"}' "$(run_pg cursor "$(cursor_shell 'git status')"; printf '%s' "$OUT")"
for c in 'ls -la' 'git status' 'git diff HEAD~1 -- README'; do
  judge "fast path takes '$c'" true "$(classify "$c" | jq -r '.fast_path_allows')"
done
# The pre-filter strips quotes, so a quoted mention takes the slow path. There the D1 marker rule applies as in
# the reference matcher: a command that maps to no id but carries `git push` is UNCLASSIFIED (R4). A mention inside
# a command that does map to an id (a commit message) is that id's argument and nothing more.
judge "a quoted mention is not fast-pathed" false "$(classify 'echo "git push --force origin main"' | jq -r '.fast_path_allows')"
expect "…a marker in an unmapped command is UNCLASSIFIED (D1)" claude "$(claude_bash 'echo "git push --force origin main"')" ask "UNCLASSIFIED"
judge "a non-shell, non-MCP tool is not PG's (Edit)" allow "$(run_pg claude "$(jq -nc --arg d "$REPO" '{cwd:$d,tool_name:"Edit",tool_input:{file_path:"/x"}}')"; verdict claude)"
judge "Cursor preToolUse Write is not PG's" allow "$(run_pg cursor "$(cursor_mcp Write '{"file_path":"/x"}')"; verdict cursor)"
expect "an empty payload is allowed (nothing to judge)" claude "" allow

pl="$(claude_bash 'git status')"
t0="$(python3 -c 'import time; print(time.time())')"
for _ in 1 2 3 4 5 6 7 8 9 10; do printf '%s' "$pl" | bash "$HOOK" >/dev/null 2>&1; done
t1="$(python3 -c 'import time; print(time.time())')"
ms="$(python3 -c "print(int(($t1 - $t0) * 100))")"
printf '  info fast-path latency: %s ms per call (git status, mean of 10)\n' "$ms"
[ "$ms" -lt 1000 ] && ok "fast path stays well under the hook timeout (${ms} ms)" || bad "fast path latency" "${ms} ms per call"

section "the pre-filter misses no guarded form the catalog lists"
eval "$(sed -n '/^_pg_candidate() {/,/^}/p' "$HOOK")"
miss=""
while IFS= read -r c; do
  [ -n "$c" ] || continue
  _pg_candidate "$c" || miss="$miss [$c]"
done < <(python3 - "$ROOT/core/permissions/actions.json" <<'PY'
import json, sys
cat = json.load(open(sys.argv[1]))
fill = lambda g: g.replace("{default}", "main").replace("*", "x").replace("[!-]", "a")
for a in cat["actions"]:
    if (a.get("l2") or []) == ["L1"] or (a["r"] < 2 and not a.get("raises") and not a.get("denies")):
        continue
    for e in a["equivalents"].get("argv", []):
        words = [("bash scripts/" + e["script"]) if "script" in e else " ".join(fill(t) for t in e["cmd"])]
        words = [" ".join(fill(v) for v in e.get("env_any", [])[:1])] + words
        for k in ("all", "any", "args"):
            words += [fill(g) for g in e.get(k, [])[:1]] if k != "all" else [fill(g) for g in e.get(k, [])]
        print(" ".join(w for w in words if w))
PY
)
[ -z "$miss" ] && ok "every R2-R4 (or raisable) argv form in actions.json is a pre-filter candidate" || bad "pre-filter misses" "$miss"

# --- 2. the catalog's fixture table, through PG ----------------------------------------
section "the catalog's fixture table maps to the same ids through PG"
n_fx=0
while IFS=$'\t' read -r st label detail; do
  [ -n "$st" ] || continue
  n_fx=$((n_fx + 1))
  if [ "$st" = ok ]; then ok "pg matcher: $label"; else bad "pg matcher: $label" "$detail"; fi
done < <(python3 - "$ROOT/tests/test-permission-catalog.sh" "$HOOK" "$REPO" <<'PY'
import ast, json, re, subprocess, sys
src, hook, repo = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src, encoding="utf-8").read()
def table(name):
    m = re.search(r"^%s = (\[.*?^\])$" % name, text, re.S | re.M)
    return ast.literal_eval(m.group(1).replace("[UNCL]", "['UNCLASSIFIED']")) if m else []
fx, mfx = table("FIXTURES"), table("MCP_FIXTURES")
if len(fx) < 40 or len(mfx) < 5:
    print("FAIL\tthe fixture tables of tests/test-permission-catalog.sh\tnot found (%d, %d)" % (len(fx), len(mfx)))
def judge(label, got, uncl, want, avoid, fast):
    if want == ["UNCLASSIFIED"]:
        good = not got and uncl
    else:
        good = all(w in got for w in want) and not any(x in got for x in avoid) and not (uncl and not want)
    why = "got %s%s" % (sorted(got), " +UNCLASSIFIED" if uncl else "")
    if good and want and fast:
        good, why = False, "the fast path would have allowed it"
    print("%s\t%s -> %s\t%s" % ("ok" if good else "FAIL", label.replace("\t", " "), ", ".join(want) or "no id", why))
for cmd, want, avoid in fx:
    r = subprocess.run(["bash", hook, "--classify", cmd, repo], capture_output=True)
    try:
        out = json.loads(r.stdout)
    except ValueError:
        print("FAIL\t%s\tclassify printed no JSON (exit %d)" % (cmd, r.returncode)); continue
    judge(cmd, set(out["ids"]), out["unclassified"], want, avoid, out["fast_path_allows"])
for tool, args, want, avoid in mfx:
    r = subprocess.run(["bash", hook, "--classify-mcp", tool, json.dumps(args), repo], capture_output=True)
    try:
        out = json.loads(r.stdout)
    except ValueError:
        print("FAIL\tmcp %s\tclassify printed no JSON (exit %d)" % (tool, r.returncode)); continue
    judge("mcp %s %s" % (tool, json.dumps(args)), set(out["ids"]), out["unclassified"] or not out["ids"], want, avoid, False)
PY
)
[ "$n_fx" -ge 50 ] && ok "the fixture table ran ($n_fx rows)" || bad "the fixture table ran" "only $n_fx rows"

# --- 3. the equivalents, per host -----------------------------------------------------
section "merge, branch-delete and force-push equivalents: ask on Claude, deny on Codex and Cursor"
EQ=(
  'gh pr merge 5 --squash|pr.merge'
  'gh api -X PUT repos/me/app/pulls/5/merge|pr.merge'
  "gh api graphql -f query='mutation{mergePullRequest(input:{pullRequestId:\"x\"}){clientMutationId}}'|pr.merge"
  'curl -X PUT -H "Authorization: token $(gh auth token)" https://api.github.com/repos/me/app/pulls/5/merge|pr.merge'
  'git push origin :feat|branch.delete.remote'
  'git push origin --delete feat|branch.delete.remote'
  'git push --force origin feat|git.push.force'
  'git push --force-with-lease origin feat|git.push.force'
  'curl -X DELETE https://api.github.com/repos/me/app|repo.delete'
  'gh api -X DELETE repos/me/app|repo.delete'
)
for row in "${EQ[@]}"; do
  c="${row%|*}" id="${row##*|}"
  expect "claude asks: $c" claude "$(claude_bash "$c")" ask "$id"
  expect "codex denies: $c" codex "$(codex_bash "$c")" deny "$id"
  expect "cursor preToolUse denies: $c" cursor "$(cursor_pre Shell "$c")" deny "$id"
  expect "cursor beforeShellExecution denies: $c" cursor "$(cursor_shell "$c")" deny "$id"
done
# a push to the default branch is denied everywhere: protected_default_branch needs the API (unknown => applies)
for c in 'git push origin +HEAD:main' 'git push --force origin main' 'git push origin main' 'git push origin HEAD:refs/heads/master'; do
  expect "claude denies: $c" claude "$(claude_bash "$c")" deny "git.push.default"
  expect "codex denies: $c" codex "$(codex_bash "$c")" deny
done
# --admin is denied while a required check fails or is pending (safety invariant 2); that needs the API, so unknown applies
expect "claude denies: gh pr merge --admin" claude "$(claude_bash 'gh pr merge 5 --squash --admin')" deny "safety#2"
expect "cursor denies: gh pr merge --admin" cursor "$(cursor_shell 'gh pr merge 5 --squash --admin')" deny "pr.merge.admin"
expect "codex: an ask is delivered as a deny, saying why" codex "$(codex_bash 'gh pr merge 5')" deny "codex cannot carry a hook ask"
expect "codex: the deny names the out-of-session route" codex "$(codex_bash 'gh pr create --fill')" deny "scripts/plugin-config.sh"
expect "cursor: the deny says the ask cannot be carried" cursor "$(cursor_shell 'gh pr merge 5')" deny "cursor cannot carry a hook ask"
expect "gemini (env): an ask is delivered as a deny" gemini "$(claude_bash 'gh pr merge 5')" deny "gemini cannot carry a hook ask"
expect "claude: a plain own-branch push asks (R2 at supervised)" claude "$(claude_bash 'git push -u origin HEAD')" ask "git.push.branch"
expect "claude: UNCLASSIFIED gh is R4 and asks" claude "$(claude_bash 'gh secret set FOO -b x')" ask "UNCLASSIFIED"
expect "claude: a file-sourced GraphQL query is UNCLASSIFIED" claude "$(claude_bash 'gh api graphql -F query=@q.graphql')" ask "UNCLASSIFIED"
expect "claude: a GraphQL document in a variable is UNCLASSIFIED" claude "$(claude_bash 'gh api graphql -f query="$Q"')" ask "UNCLASSIFIED"
expect "claude: gh api with a variable path and a method is UNCLASSIFIED" claude "$(claude_bash 'gh api -X DELETE "$URL"')" ask "UNCLASSIFIED"
expect "claude: gh api with a variable path, GET, is a read" claude "$(claude_bash 'gh api "$URL"')" allow
expect "claude: gh pr view is a read" claude "$(claude_bash 'gh pr view 5 --json state')" allow
expect "claude: x=\$(gh pr merge ...) is seen inside the substitution" claude "$(claude_bash 'x=$(gh pr merge 5 --admin)')" deny "pr.merge.admin"
expect "claude: a substitution of an unknown gh call is UNCLASSIFIED" claude "$(claude_bash 'x=$(gh secret set FOO)')" ask "UNCLASSIFIED"
expect "claude: bash -lc is descended into" claude "$(claude_bash 'bash -lc "gh pr merge 5"')" ask "pr.merge"
expect "claude: quotes cannot hide the program" claude "$(claude_bash 'g"i"t push --force origin feat')" ask "git.push.force"
expect "claude: -uf is -u -f" claude "$(claude_bash 'git push -uf origin feat')" ask "git.push.force"
expect "claude: a commit message mentioning a push is a commit" claude "$(claude_bash 'git commit -m "then git push --force origin main"')" allow
expect "claude: --no-verify is R4" claude "$(claude_bash 'git commit --no-verify -m x')" ask "git.verify.skip"
expect "claude: a token variable in an unmapped command is UNCLASSIFIED (a D1 marker pattern)" claude "$(claude_bash 'echo "$GITHUB_TOKEN" | base64')" ask "UNCLASSIFIED"
expect "claude: the token command as text is UNCLASSIFIED" claude "$(claude_bash 'echo gh auth token')" ask "UNCLASSIFIED"
expect "claude: another *_TOKEN takes the slow path but is no marker" claude "$(claude_bash 'echo "$MY_TOKEN"')" allow

section "tty.drive and process.spawn.agent_host (R4): ask on Claude, deny on Codex and Cursor"
TTY=(
  'script -q /dev/null claude|tty.drive'
  "expect -c 'spawn claude; send y'|tty.drive"
  'unbuffer claude -p hi|tty.drive'
  'tmux send-keys -t 0 y Enter|tty.drive'
  'screen -S s -X stuff y|tty.drive'
  "osascript -e 'tell application \"System Events\" to keystroke \"y\"'|tty.drive"
  "osascript -e 'tell application \"Terminal\" to do script \"y\"'|tty.drive"
  'xdotool type y|tty.drive'
  "python3 -c 'import pty; pty.spawn([\"claude\"])'|tty.drive"
  "node -e \"require('node-pty').spawn('claude')\"|tty.drive"
  'claude -p hi|process.spawn.agent_host'
  'codex exec "fix it"|process.spawn.agent_host'
  'gemini -p hi|process.spawn.agent_host'
  'opencode run hi|process.spawn.agent_host'
  'cursor-agent -p hi|process.spawn.agent_host'
  'npx -y @anthropic-ai/claude-code -p hi|process.spawn.agent_host'
  'bunx @openai/codex exec x|process.spawn.agent_host'
  'node /opt/x/node_modules/@anthropic-ai/claude-code/cli.js -p hi|process.spawn.agent_host'
  'env FOO=1 claude -p hi|process.spawn.agent_host'
  'bash -c "claude -p hi"|process.spawn.agent_host'
  'x=$(claude -p hi)|process.spawn.agent_host'
)
for row in "${TTY[@]}"; do
  c="${row%|*}" id="${row##*|}"
  expect "claude asks: $c" claude "$(claude_bash "$c")" ask "$id"
  expect "codex denies: $c" codex "$(codex_bash "$c")" deny "$id"
  expect "cursor denies: $c" cursor "$(cursor_shell "$c")" deny "$id"
done

section "policy.edit forms (D5-D7): R4, and the out-of-session writers are denied outright"
POL=(
  'bash scripts/setup.sh --permission-level unattended --yes'
  'bash scripts/setup.sh --permission-level=standard'
  'SETUP_PERMISSION_LEVEL=standard bash scripts/setup.sh --yes'
  'bash scripts/plugin-config.sh standard'
  'bash scripts/plugin-config.sh pr-dev unattended'
  'bash scripts/plugin-config.sh pr.merge.auto allow'
  'bash scripts/plugin-config.sh reset all'
  'bash scripts/plugin-config.sh trust'
  '"$CLAUDE_PLUGIN_ROOT"/scripts/plugin-config.sh supervised'
)
for c in "${POL[@]}"; do
  expect "claude asks: $c" claude "$(claude_bash "$c")" ask "policy.edit"
  expect "codex denies: $c" codex "$(codex_bash "$c")" deny "policy.edit"
  expect "cursor denies: $c" cursor "$(cursor_shell "$c")" deny "policy.edit"
done
for c in 'bash scripts/plugin-config.sh confirm 0123456789abcdef' 'bash scripts/plugin-config.sh confirm 0123456789abcdef0123456789abcdef'; do
  expect "codex denies: $c" codex "$(codex_bash "$c")" deny "policy.edit"
  expect "cursor denies: $c" cursor "$(cursor_shell "$c")" deny "policy.edit"
done
expect "plugin-config.sh show is a read" claude "$(claude_bash 'bash scripts/plugin-config.sh show')" allow
expect "claude denies plugin-config.sh provision (D6)" claude "$(claude_bash 'bash scripts/plugin-config.sh provision --level standard')" deny "D6"
expect "claude denies claude plugin configure (D7)" claude "$(claude_bash 'claude plugin configure tamirs-superpowers --values-stdin')" deny "D7"
expect "claude denies gemini extensions config (D7)" claude "$(claude_bash 'gemini extensions config tamirs-superpowers TS_PERMISSION_LEVEL')" deny "D7"

# --- 4. fail closed --------------------------------------------------------------------
section "fail closed"
mk_tree() { # mk_tree <dir> — a plugin tree with the guard, its libs, the resolver and the catalog
  mkdir -p "$1/scripts/lib"
  cp -R "$ROOT/hooks" "$ROOT/core" "$1/"
  cp "$ROOT/scripts/resolve-permission.sh" "$1/scripts/"
  cp "$ROOT/scripts/lib/permission-common.sh" "$1/scripts/lib/"
}
mk_tree "$T/t-nores"; rm -f "$T/t-nores/scripts/resolve-permission.sh"
expect "no resolver: deny" claude "$(claude_bash 'gh pr create --fill')" deny "resolve-permission.sh is missing" "$T/t-nores/hooks/permission-guard.sh"
expect "no resolver, codex: deny" codex "$(codex_bash 'gh pr create --fill')" deny "resolver" "$T/t-nores/hooks/permission-guard.sh"
mk_tree "$T/t-garbage"; printf '#!/usr/bin/env bash\necho nonsense\n' > "$T/t-garbage/scripts/resolve-permission.sh"
expect "a resolver printing garbage: deny" claude "$(claude_bash 'gh pr create --fill')" deny "printed no JSON" "$T/t-garbage/hooks/permission-guard.sh"
mk_tree "$T/t-exit3"; printf '#!/usr/bin/env bash\necho %s\nexit 3\n' "'{\"verdict\":\"allow\",\"reason\":\"crash\"}'" > "$T/t-exit3/scripts/resolve-permission.sh"
expect "a resolver exiting 3 (even printing allow): deny" claude "$(claude_bash 'gh pr create --fill')" deny "exit 3" "$T/t-exit3/hooks/permission-guard.sh"
mk_tree "$T/t-cat"; printf '{"actions": [' > "$T/t-cat/core/permissions/actions.json"
expect "a corrupt catalog: deny" claude "$(claude_bash 'gh pr create --fill')" deny "catalog" "$T/t-cat/hooks/permission-guard.sh"
expect "a corrupt catalog, cursor: deny in Cursor's shape" cursor "$(cursor_shell 'gh pr create --fill')" deny "catalog" "$T/t-cat/hooks/permission-guard.sh"
expect "a corrupt catalog does not touch the fast path" claude "$(claude_bash 'ls')" allow "" "$T/t-cat/hooks/permission-guard.sh"
mkdir -p "$T/nopy" "$T/nojq"
for b in bash jq git sed cat mktemp dirname basename tr head env ps id dscl getent; do
  p="$(command -v "$b" 2>/dev/null)" || continue
  ln -sf "$p" "$T/nopy/$b"
  [ "$b" = jq ] || ln -sf "$p" "$T/nojq/$b"
done
ln -sf "$(command -v python3)" "$T/nojq/python3"
run_nopath() { OUT="$(printf '%s' "$2" | PATH="$1" "$(command -v bash)" "$HOOK" 2>/dev/null)"; RC=$?; }
run_nopath "$T/nopy" "$(claude_bash 'gh pr create --fill')"
judge "no python3: deny" deny "$(verdict claude)"
judge "no python3: the reason says so" yes "$(has "$(reason)" python3)"
run_nopath "$T/nojq" "$(claude_bash 'gh pr create --fill')"
judge "no jq: deny (literal JSON)" deny "$(verdict claude)"
run_nopath "$T/nojq" "$(cursor_shell 'gh pr create --fill')"
judge "no jq, Cursor payload: deny in Cursor's shape" deny "$(verdict cursor)"
run_nopath "$T/nojq" "$(claude_bash 'ls')"
judge "no jq: even ls is denied (the payload cannot be read)" deny "$(verdict claude)"
expect "a non-JSON payload: deny" claude 'this is not json' deny "not valid JSON"
expect "a NUL byte in the command: deny" claude '{"cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"ls\u0000git push --force origin main"}}' deny "NUL"
judge "a hook argument it does not know exits 2, never allows" 2 "$(bash "$HOOK" --bogus </dev/null >/dev/null 2>&1; echo $?)"

# --- 5. conditions and context -----------------------------------------------------------
section "conditions PG establishes, and context it refuses to guess"
judge "push -u origin HEAD: default_branch and tag_ref established false" \
  '["default_branch=false","tag_ref=false"]' "$(classify 'git push -u origin HEAD' | jq -c '[.resolver_calls[] | select(.id=="git.push.branch") | .conds[]] | sort')"
judge "push origin \$(git branch --show-current) reads as the current branch" \
  '["default_branch=false","tag_ref=false"]' "$(classify 'git push -u origin $(git branch --show-current)' | jq -c '[.resolver_calls[] | select(.id=="git.push.branch") | .conds[]] | sort')"
judge "push of a tag: tag_ref established true" '["tag_ref=true"]' "$(classify 'git push origin v1.0' | jq -c '[.resolver_calls[] | select(.id=="git.push.branch") | .conds[] | select(startswith("tag_ref"))]')"
expect "no refs/remotes/origin/HEAD: an own-branch push is denied, with the remedy" claude "$(claude_bash 'git push -u origin HEAD' "$NOHEAD")" deny "git remote set-head"
expect "a leading cd is followed (into the repo without origin/HEAD)" claude "$(claude_bash "cd $NOHEAD && git push -u origin HEAD")" deny "default_branch"
expect "a leading cd is followed (into the repo with origin/HEAD)" claude "$(claude_bash "cd $REPO && git push -u origin HEAD" "$NOHEAD")" ask "git.push.branch"
judge "a subshell cd is not followed" false "$(classify '(cd /tmp); git push -u origin HEAD' | jq -r .context_ok)"
judge "two cds are not followed" false "$(classify "cd $REPO && cd /tmp && git push" | jq -r .context_ok)"
judge "export changes the target: not followed" false "$(classify 'export GIT_DIR=/x; git push -u origin HEAD' | jq -r .context_ok)"
judge "GIT_DIR=… on the push: no condition established" '[]' "$(classify 'GIT_DIR=/x git push -u origin HEAD' | jq -c '[.resolver_calls[] | select(.id=="git.push.branch") | .conds[]]')"
judge "git -C <repo> is followed" '["default_branch=false","tag_ref=false"]' "$(classify "git -C $REPO push -u origin HEAD" "$NOHEAD" | jq -c '[.resolver_calls[] | select(.id=="git.push.branch") | .conds[]] | sort')"
expect "a clean tree: git checkout -- . is allowed" claude "$(claude_bash 'git checkout -- .')" allow
printf 'dirty\n' >> "$REPO/README"
expect "a dirty tree: git checkout -- . is denied (safety invariant 4)" claude "$(claude_bash 'git checkout -- .')" deny "safety#4"
expect "a dirty tree: git restore is denied" codex "$(codex_bash 'git restore README')" deny "safety#4"
git -C "$REPO" checkout -q -- README
git -C "$REPO" commit -q --allow-empty -m local
expect "reset --hard over an unpushed commit is R4" claude "$(claude_bash 'git reset --hard HEAD~1')" ask "R4"
git -C "$REPO" reset -q --hard refs/remotes/origin/feat
expect "reset --hard with nothing unpushed is R1" claude "$(claude_bash 'git reset --hard HEAD')" allow
expect "branch -D of a branch a remote holds is R1" claude "$(claude_bash 'git branch -D gone')" allow
git -C "$REPO" checkout -q local-only && git -C "$REPO" commit -q --allow-empty -m only-here && git -C "$REPO" checkout -q feat
expect "branch -D of commits no remote holds is raised to R3" claude "$(claude_bash 'git branch -D local-only')" ask "branch.delete.local"
git -C "$REPO" worktree add -q "$T/wt" -b wt-branch refs/remotes/origin/main 2>/dev/null
expect "worktree remove of a clean, pushed worktree is R1" claude "$(claude_bash "git worktree remove $T/wt")" allow
git -C "$T/wt" commit -q --allow-empty -m wt-local
expect "worktree remove of unpushed work is R4" claude "$(claude_bash "git worktree remove --force $T/wt")" ask "worktree.remove.force"

section "conditions PG reads from GitHub (fake gh), under one 3 s deadline"
now() { python3 -c 'import time; print(time.time())'; }
since() { python3 -c "import sys; print(int(float(sys.argv[2]) - float(sys.argv[1])))" "$1" "$(now)"; }
# gh pr merge --admin (D1, safety invariant 2): required checks, through gh pr checks --required
fake_gh_reset; checks '[{"bucket":"pass","name":"ci"},{"bucket":"skipping","name":"docs"}]'
expect "every required check passes: --admin asks on Claude (R4: the host prompt)" claude "$(claude_bash 'gh pr merge 5 --squash --admin')" ask "pr.merge.admin"
judge "  ... the prompt counts the checks" yes "$(has "$(reason)" "2 required, all passing")"
judge "  ... and names no check (names are PR-author text)" no "$(has "$(reason)" "docs")"
judge "  ... PG asked gh pr checks for that PR, required only" 1 "$(gh_calls 'pr checks 5 --required --json bucket')"
expect "  ... codex still denies (no ask route, D8)" codex "$(codex_bash 'gh pr merge 5 --squash --admin')" deny "pr.merge.admin"
expect "  ... cursor still denies" cursor "$(cursor_shell 'gh pr merge 5 --squash --admin')" deny "pr.merge.admin"
checks '[{"bucket":"pass"},{"bucket":"fail"}]'
expect "a failing required check: --admin is denied" claude "$(claude_bash 'gh pr merge 5 --admin')" deny "safety#2"
judge "  ... the reason counts it" yes "$(has "$(reason)" "1 failing")"
checks '[{"bucket":"pass"},{"bucket":"pending"}]' 8
expect "a pending required check (gh exit 8): denied" claude "$(claude_bash 'gh pr merge 5 --admin')" deny "1 pending"
checks '[{"bucket":"pass"},{"bucket":"cancel"}]'
expect "a cancelled required check: denied" claude "$(claude_bash 'gh pr merge 5 --admin')" deny "safety#2"
checks '[{"bucket":"pass"},{"bucket":"weird"}]'
expect "a state gh does not name: denied (unknown)" claude "$(claude_bash 'gh pr merge 5 --admin')" deny "safety#2"
checks '[]'
expect "an empty list: denied (unknown)" claude "$(claude_bash 'gh pr merge 5 --admin')" deny "safety#2"
checks 'not json'
expect "output that is not JSON: denied" claude "$(claude_bash 'gh pr merge 5 --admin')" deny "no JSON"
checks
expect "no required check reported (gh exits 1): denied, as one may not have started" claude "$(claude_bash 'gh pr merge 5 --admin')" deny "safety#2"
checks '[{"bucket":"pass"}]' 1
expect "a passing list with a non-zero exit: denied" claude "$(claude_bash 'gh pr merge 5 --admin')" deny "safety#2"
checks '[{"bucket":"pass"}]'; printf '6\n' > "$CHK.sleep"
t0="$(now)"
expect "a lookup that outlives the deadline: denied" claude "$(claude_bash 'gh pr merge 5 --admin')" deny "no answer within"
el="$(since "$t0")"
[ "$el" -lt 6 ] && ok "  ... and the guard answered in ${el}s, before gh would have (6 s)" || bad "the 3 s deadline held" "${el}s"
rm -f "$CHK.sleep"
fake_gh_reset; checks '[{"bucket":"pass"}]'
expect "-R owner/repo: the same repository is asked" claude "$(claude_bash 'gh pr merge 7 --admin -R me/app')" ask "pr.merge.admin"
judge "  ... with -R me/app" 1 "$(gh_calls 'pr checks 7 -R me/app --required')"
fake_gh_reset
expect "no selector: the current branch's PR is asked" claude "$(claude_bash 'gh pr merge --admin --squash')" ask "pr.merge.admin"
judge "  ... gh pr checks with no selector" 1 "$(gh_calls 'pr checks --required --json bucket')"
fake_gh_reset
expect "a PR URL is passed on" claude "$(claude_bash 'gh pr merge https://github.com/me/app/pull/9 --admin')" ask "pr.merge.admin"
judge "  ... as the URL" 1 "$(gh_calls 'pr checks https://github.com/me/app/pull/9 --required')"
fake_gh_reset
expect "GH_REPO=… retargets the merge: no lookup, denied" claude "$(claude_bash 'GH_REPO=me/other gh pr merge 5 --admin')" deny "safety#2"
expect "--hostname: no lookup, denied" claude "$(claude_bash 'gh pr merge 5 --admin --hostname ghe.example')" deny "safety#2"
expect "a cd chain PG does not follow: no lookup, denied" claude "$(claude_bash 'cd /tmp && cd / && gh pr merge 5 --admin')" deny "safety#2"
expect "two selectors: no lookup, denied" claude "$(claude_bash 'gh pr merge 5 6 --admin')" deny "safety#2"
expect "a selector with an expansion: no lookup, denied" claude "$(claude_bash 'gh pr merge "$PR" --admin')" deny "safety#2"
judge "none of those five asked gh" 0 "$(gh_calls 'pr checks')"
checks
# the default branch, when refs/remotes/<remote>/HEAD does not resolve: gh repo view of the push URL
fake_gh_use_fixtures "$FX/develop"; fake_gh_reset
expect "no origin/HEAD, GitHub says develop: an own-branch push asks (R2) instead of a deny" claude "$(claude_bash 'git push -u origin HEAD' "$NOHEAD")" ask "git.push.branch"
judge "  ... PG asked gh repo view for the remote's repository" 1 "$(gh_calls 'repo view github.com/me/other --json defaultBranchRef')"
judge "  ... default_branch and tag_ref established false" '["default_branch=false","tag_ref=false"]' \
  "$(classify 'git push -u origin HEAD' "$NOHEAD" | jq -c '[.resolver_calls[] | select(.id=="git.push.branch") | .conds[]] | sort')"
expect "  ... a push to develop is a default-branch push: denied" claude "$(claude_bash 'git push origin HEAD:develop' "$NOHEAD")" deny "git.push.default"
fake_gh_use_fixtures "$FX/feat-default"
expect "GitHub's answer can raise too (feat is the default there): denied" claude "$(claude_bash 'git push -u origin HEAD' "$NOHEAD")" deny "git.push.default"
fake_gh_use_fixtures "$FX/slow"
t0="$(now)"
expect "a default-branch lookup past the deadline: denied" claude "$(claude_bash 'git push -u origin HEAD' "$NOHEAD")" deny "default_branch"
el="$(since "$t0")"
[ "$el" -lt 6 ] && ok "  ... and the guard answered in ${el}s, before gh would have (6 s)" || bad "the 3 s deadline held" "${el}s"
fake_gh_use_fixtures "$FX/none"
expect "no answer from GitHub: denied, with the remedy" claude "$(claude_bash 'git push -u origin HEAD' "$NOHEAD")" deny "git remote set-head"
judge "  ... and the reason says GitHub was asked" yes "$(has "$(reason)" "could not be read from GitHub")"
fake_gh_use_fixtures "$FX/develop"; fake_gh_reset
expect "a repository whose origin/HEAD resolves asks GitHub nothing" claude "$(claude_bash 'git push -u origin HEAD')" ask "git.push.branch"
judge "  ... no gh call" 0 "$(gh_calls 'repo view')"
fake_gh_use_fixtures "$FX/none"
judge "the conditions lib: a usage error exits 2" 2 "$(bash "$ROOT/hooks/lib/permission-conditions.sh" bogus >/dev/null 2>&1; echo $?)"
judge "the conditions lib: no gh on PATH is unknown, never a pass" "unknown gh is not installed" \
  "$(PATH="$T/nopy" bash "$ROOT/hooks/lib/permission-conditions.sh" required-checks "$REPO" 5 - 2>/dev/null)"

# --- 6. levels, the call stamp, MCP ---------------------------------------------------------
section "levels through a real user file and lock"
CFG="$PH/.config/tamirs-superpowers"
set_level() {
  rm -rf "$PH/.config"
  [ "$1" = none ] && return 0
  mkdir -p "$CFG"
  chmod 700 "$PH/.config" "$CFG"
  printf '{"version": 1, "level": "%s"}\n' "$1" > "$CFG/permissions.json"
  chmod 600 "$CFG/permissions.json"
  printf '{"sha256": "%s", "by": "plugin-config", "at": "2026-11-04T00:00:00Z"}\n' \
    "$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$CFG/permissions.json")" > "$CFG/permissions.lock"
  chmod 600 "$CFG/permissions.lock"
}
set_level standard
judge "the resolver reads level standard from the user file" "standard user_file.level" \
  "$(bash "$ROOT/scripts/resolve-permission.sh" pr.create --json 2>/dev/null | jq -r '"\(.level) \(.level_source)"')"
expect "standard: an own-branch push is allowed" claude "$(claude_bash 'git push -u origin HEAD')" allow
expect "standard: gh pr create is allowed" claude "$(claude_bash 'gh pr create --fill')" allow
expect "standard, codex: gh pr create is allowed ({})" codex "$(codex_bash 'gh pr create --fill')" allow
expect "standard: gh pr merge still asks (R3)" claude "$(claude_bash 'gh pr merge 5 --squash')" ask "pr.merge"
expect "standard: auto-merge stays off (asks)" claude "$(claude_bash 'gh pr merge 5 --auto --squash')" ask "pr.merge.auto"
expect "standard: a push to main is still denied" claude "$(claude_bash 'git push origin main')" deny "git.push.default"
expect "standard: R4 still asks" claude "$(claude_bash 'claude -p hi')" ask "process.spawn.agent_host"
expect "standard, no origin/HEAD, GitHub silent: the push is still denied (unknown never holds)" claude "$(claude_bash 'git push -u origin HEAD' "$NOHEAD")" deny
fake_gh_use_fixtures "$FX/develop"
expect "standard, no origin/HEAD, GitHub names the default: the own-branch push is allowed" claude "$(claude_bash 'git push -u origin HEAD' "$NOHEAD")" allow
fake_gh_use_fixtures "$FX/none"
export TS_PERMISSION_LEVEL=supervised
expect "an env lowering is honoured (TS_PERMISSION_LEVEL=supervised)" claude "$(claude_bash 'gh pr create --fill')" ask
unset TS_PERMISSION_LEVEL
set_level none

section "the call stamp (D8)"
SEEN="$PH/.local/state/tamirs-superpowers/seen"
expect "a resolver call with --call is allowed" claude "$(claude_bash 'bash scripts/resolve-permission.sh pr.create --skill pr-dev --call abcdefgh12345678')" allow
judge "PG stamped it" yes "$(exists "$SEEN/abcdefgh12345678")"
judge "the stamp is 0600" 600 "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$SEEN/abcdefgh12345678" 2>/dev/null)"
judge "its dirs are 0700" "700 700" "$(python3 -c 'import os,sys; print(" ".join(oct(os.stat(p).st_mode & 0o777)[2:] for p in sys.argv[1:]))' "$SEEN/.." "$SEEN")"
judge "the resolver consumes it" consumed "$(bash "$ROOT/scripts/resolve-permission.sh" pr.create --call abcdefgh12345678 --json 2>/dev/null | jq -r '.level_sources[] | select(.source=="call_stamp") | .state')"
judge "and it is gone" no "$(exists "$SEEN/abcdefgh12345678")"
expect "a denied command gets no stamp" claude "$(claude_bash 'bash scripts/resolve-permission.sh x --call zzzzzzzz99999999 && git push origin main')" deny
judge "no stamp for the denied call" no "$(exists "$SEEN/zzzzzzzz99999999")"
expect "an invalid token writes nothing" claude "$(claude_bash 'bash scripts/resolve-permission.sh x --call ../../../escape')" allow
judge "nothing escaped the seen dir" no "$(exists "$PH/.local/escape")"

section "GitHub MCP tools"
expect "claude: merge_pull_request asks" claude "$(claude_mcp "${PFX}merge_pull_request" '{"owner":"me","repo":"app","pullNumber":5}')" ask "pr.merge"
expect "codex: merge_pull_request denies" codex "$(claude_mcp "${PFX}merge_pull_request" '{"owner":"me","repo":"app","pullNumber":5}' | jq -c '. + {turn_id:"t"}')" deny "pr.merge"
expect "claude: get_me is a read" claude "$(claude_mcp "${PFX}get_me" '{}')" allow
expect "claude: a workflow write is R4" claude "$(claude_mcp "${PFX}create_or_update_file" '{"owner":"me","repo":"app","branch":"x","path":".github/workflows/ci.yml","content":"x","message":"m"}')" ask "workflow.edit"
expect "claude: delete_repository is R4" claude "$(claude_mcp "${PFX}delete_repository" '{"owner":"me","repo":"app"}')" ask "repo.delete"
expect "claude: a tool of this server with no entry is UNCLASSIFIED" claude "$(claude_mcp "${PFX}dismiss_notification" '{}')" ask "UNCLASSIFIED"
expect "claude: another server's tool is not PG's" claude "$(claude_mcp 'mcp__other__merge_pull_request' '{}')" allow
judge "a README write on a non-default branch of origin: default_branch and the path established false" \
  '["default_branch=false","workflow_hook_or_policy_path=false"]' \
  "$(bash "$HOOK" --classify-mcp create_or_update_file '{"owner":"me","repo":"app","branch":"x","path":"README.md"}' "$REPO" | jq -c '[.resolver_calls[0].conds[]] | sort')"
expect "cursor: MCP:merge_pull_request is denied" cursor "$(cursor_mcp 'MCP:merge_pull_request' '{"owner":"me","repo":"app","pullNumber":5}')" deny "pr.merge"
expect "cursor: an MCP tool PG does not know is not PG's" cursor "$(cursor_mcp 'MCP:search_docs' '{}')" allow

# --- 7. the OpenCode dialect (D8: "R2: hook ask (A under --auto); R3/R4: deny") -----------------
section "OpenCode dialect: ask for R2 only, deny what must survive --auto"
oc_bash() { claude_bash "$@" | jq -c '. + {host:"opencode"}'; }
oc_mcp() { claude_mcp "$@" | jq -c '. + {host:"opencode"}'; }
expect "opencode: ls is allowed" claude "$(oc_bash 'ls -la')" allow
judge "opencode: the allow is {}" '{}' "$(run_pg claude "$(oc_bash 'git status')"; printf '%s' "$OUT")"
expect "opencode: gh pr create (R2) asks" claude "$(oc_bash 'gh pr create --fill')" ask "pr.create"
judge "  ... and says --auto approves it" yes "$(has "$(reason)" "opencode --auto")"
judge "  ... the route it names is the terminal one (no in-session raise on OpenCode)" yes "$(has "$(reason)" "outside the agent session")"
expect "opencode: an own-branch push (R2) asks" claude "$(oc_bash 'git push -u origin HEAD')" ask "git.push.branch"
expect "opencode: gh pr merge (R3) is a deny" claude "$(oc_bash 'gh pr merge 5 --squash')" deny "carries only an R2 ask"
expect "opencode: a force push (R3) is a deny" claude "$(oc_bash 'git push --force origin feat')" deny "git.push.force"
expect "opencode: claude -p (R4) is a deny" claude "$(oc_bash 'claude -p hi')" deny "process.spawn.agent_host"
expect "opencode: UNCLASSIFIED gh is a deny" claude "$(oc_bash 'gh secret set FOO -b x')" deny "UNCLASSIFIED"
expect "opencode: a policy.edit writer call is a deny" claude "$(oc_bash 'bash scripts/plugin-config.sh standard')" deny "policy.edit"
expect "opencode: R2 together with R3 in one command is a deny" claude "$(oc_bash 'gh pr create --fill && gh pr merge 5')" deny "pr.merge"
git -C "$REPO" checkout -q local-only && git -C "$REPO" commit -q --allow-empty -m oc-only-here && git -C "$REPO" checkout -q feat
expect "opencode: a branch -D raised to R3 is a deny" claude "$(oc_bash 'git branch -D local-only')" deny "branch.delete.local"
expect "opencode: MCP create_pull_request (R2) asks" claude "$(oc_mcp "${PFX}create_pull_request" '{"owner":"me","repo":"app","title":"t","head":"feat","base":"main"}')" ask "pr.create"
expect "opencode: MCP merge_pull_request (R3) is a deny" claude "$(oc_mcp "${PFX}merge_pull_request" '{"owner":"me","repo":"app","pullNumber":5}')" deny "pr.merge"
expect "opencode: an unknown tool of the server (UNCLASSIFIED) is a deny" claude "$(oc_mcp "${PFX}dismiss_notification" '{}')" deny "UNCLASSIFIED"
# the marker never loosens a deny-only host
expect "marker + CODEX_HOME: still Codex, the R2 ask is a deny" codex "$(oc_bash 'gh pr create --fill')" deny "codex cannot carry a hook ask"
expect "marker + turn_id: still Codex" claude "$(oc_bash 'gh pr create --fill' | jq -c '. + {turn_id:"t"}')" deny "codex"
expect "marker + GEMINI_* env: still Gemini" gemini "$(oc_bash 'gh pr create --fill')" deny "gemini cannot carry a hook ask"
expect "marker on a Cursor payload: still Cursor's deny" cursor "$(cursor_shell 'gh pr create --fill' | jq -c '. + {host:"opencode"}')" deny "cursor cannot carry"
expect "another host value is ignored (Claude asks R3)" claude "$(claude_bash 'gh pr merge 5' | jq -c '. + {host:"elsewhere"}')" ask "pr.merge"
set_level standard
expect "opencode, standard: gh pr create is allowed" claude "$(oc_bash 'gh pr create --fill')" allow
expect "opencode, standard: gh pr merge is still a deny" claude "$(oc_bash 'gh pr merge 5 --squash')" deny "pr.merge"
set_level none
SEEN="$PH/.local/state/tamirs-superpowers/seen"
expect "codex: an ask delivered as a deny" codex "$(codex_bash 'bash scripts/resolve-permission.sh pr.create --call cdxcdxcdx0000001 && gh pr create --fill')" deny
judge "  ... writes no call stamp (the command never runs)" no "$(exists "$SEEN/cdxcdxcdx0000001")"
expect "opencode: an R2 ask" claude "$(oc_bash 'bash scripts/resolve-permission.sh pr.create --call ocococoo00000001 && gh pr create --fill')" ask
judge "  ... is stamped (it may run once approved)" yes "$(exists "$SEEN/ocococoo00000001")"

# --- 8. the active skill (hooks/permission-intent.sh, D5/D8) ---------------------------------
section "the active skill: --skill from intent/<sid>.json; a raise only when user_typed"
STATE="$PH/.local/state/tamirs-superpowers"
INTENT="$STATE/intent/pg-1.json"
set_doc() { # set_doc '<user-file json>'
  rm -rf "$PH/.config"; mkdir -p "$CFG"; chmod 700 "$PH/.config" "$CFG"
  printf '%s\n' "$1" > "$CFG/permissions.json"; chmod 600 "$CFG/permissions.json"
  printf '{"sha256": "%s", "by": "plugin-config", "at": "2026-11-04T00:00:00Z"}\n' \
    "$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$CFG/permissions.json")" > "$CFG/permissions.lock"
  chmod 600 "$CFG/permissions.lock"
}
# The writer itself makes the context: a /pr-dev slash-command expansion, as Claude Code sends it.
intent_expand() { # intent_expand <command_name> [session] — runs hooks/permission-intent.sh
  jq -nc --arg n "$1" --arg s "${2:-pg-1}" --arg d "$REPO" \
    '{session_id:$s,cwd:$d,hook_event_name:"UserPromptExpansion",expansion_type:"slash_command",command_name:$n,command_args:"42"}' |
    bash "$ROOT/hooks/permission-intent.sh" >/dev/null 2>&1
}
intent_edit() { # intent_edit '<jq filter>' — rewrite the context in place, 0600
  jq -S "$1" "$INTENT" > "$INTENT.new" && chmod 600 "$INTENT.new" && mv "$INTENT.new" "$INTENT"
}
rm -rf "$STATE/intent"
intent_expand tamirs-superpowers:pr-dev
judge "permission-intent.sh wrote the context PG reads" "pr-dev null" "$(jq -r '"\(.skill) \(.user_typed)"' "$INTENT" 2>/dev/null)"
set_doc '{"version": 1, "level": "supervised", "skills": {"pr-dev": "standard"}}'
expect "a skill raise from an unpaired slash command does not apply (user_typed null): R2 asks" claude "$(claude_bash 'gh pr create --fill')" ask "pr.create"
judge "  ... the reason names the skill and why it only lowers" yes "$(has "$(reason)" "counts only where it is stricter")"
intent_edit '.user_typed = true'
expect "the same raise once user_typed: R2 is allowed (pr-dev at standard)" claude "$(claude_bash 'gh pr create --fill')" allow
expect "  ... R3 still asks" claude "$(claude_bash 'gh pr merge 5 --squash')" ask "pr.merge"
expect "  ... a call from another agent does not get the raise" claude "$(claude_bash 'gh pr create --fill' | jq -c '. + {agent_id:"sub-1"}')" ask "another agent"
expect "  ... nor another session (no context of its own)" claude "$(claude_bash 'gh pr create --fill' | jq -c '.session_id = "pg-2"')" ask "pr.create"
set_doc '{"version": 1, "level": "standard", "skills": {"pr-dev": "supervised"}}'
intent_edit '.user_typed = null'
expect "a skill lowering applies without provenance: R2 asks under /pr-dev" claude "$(claude_bash 'gh pr create --fill')" ask "pr.create"
expect "  ... and from another agent too" claude "$(claude_bash 'gh pr create --fill' | jq -c '. + {agent_id:"sub-1"}')" ask "pr.create"
expect "  ... without a context the global standard allows it" claude "$(claude_bash 'gh pr create --fill' | jq -c '.session_id = "pg-2"')" allow
# unusable contexts: the global level (standard here), never an error and never a deny of their own
intent_edit '.expires = "2020-01-01T00:00:00Z"'
expect "an expired context is ignored (global standard)" claude "$(claude_bash 'gh pr create --fill')" allow
intent_expand tamirs-superpowers:pr-dev
intent_edit '.session_id = "someone-else"'
expect "a context naming another session is ignored" claude "$(claude_bash 'gh pr create --fill')" allow
intent_expand tamirs-superpowers:pr-dev
chmod 644 "$INTENT"
expect "a group/world-readable context is ignored (unsafe)" claude "$(claude_bash 'gh pr create --fill')" allow
chmod 600 "$INTENT"
printf 'not json' > "$INTENT"; chmod 600 "$INTENT"
expect "a corrupt context is ignored (global level, no error)" claude "$(claude_bash 'gh pr create --fill')" allow
intent_expand tamirs-superpowers:pr-dev
intent_edit '.skill = "no-such-skill"'
expect "a context naming no shipped skill is ignored" claude "$(claude_bash 'gh pr create --fill')" allow
intent_expand tamirs-superpowers:pr-dev
expect "control: the valid context lowers again" claude "$(claude_bash 'gh pr create --fill')" ask "pr.create"
mkdir -p "$T/elsewhere" && chmod 700 "$T/elsewhere"
cp "$INTENT" "$T/elsewhere/pg-1.json" && chmod 600 "$T/elsewhere/pg-1.json"
rm -rf "$STATE/intent"
ln -s "$T/elsewhere" "$STATE/intent"
expect "the same context behind an intent dir that is a symlink is ignored" claude "$(claude_bash 'gh pr create --fill')" allow
rm -f "$STATE/intent"
set_level none
# what reaches the resolver: a stub that logs its arguments
mk_tree "$T/t-argv"
mkdir -p "$T/t-argv/skills/dev-workflow/pr-dev" && : > "$T/t-argv/skills/dev-workflow/pr-dev/SKILL.md"
cat > "$T/t-argv/scripts/resolve-permission.sh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/argv.log"
printf '%s\n' '{"verdict":"ask","r":2,"reason":"stub asks","effective_action":"pr.create"}'
SH
intent_expand tamirs-superpowers:pr-dev
intent_edit '.objective = "obj-7"'
rm -f "$T/argv.log"
expect "with a context (user_typed null) the stub is asked" claude "$(claude_bash 'gh pr create --fill')" ask "" "$T/t-argv/hooks/permission-guard.sh"
judge "  ... twice: with --skill pr-dev and without (the stricter answer kept)" "1 1" \
  "$(grep -c -- '--skill pr-dev' "$T/argv.log") $(grep -vc -- '--skill' "$T/argv.log")"
judge "  ... both with --objective obj-7 (tighten only)" 2 "$(grep -c -- '--objective obj-7' "$T/argv.log")"
intent_edit '.user_typed = true'
rm -f "$T/argv.log"
expect "with user_typed the stub is asked" claude "$(claude_bash 'gh pr create --fill')" ask "" "$T/t-argv/hooks/permission-guard.sh"
judge "  ... once, with --skill pr-dev" "1 1" "$(wc -l < "$T/argv.log" | tr -d ' ') $(grep -c -- '--skill pr-dev' "$T/argv.log")"
rm -rf "$STATE/intent"; rm -f "$T/argv.log"
expect "with no context the stub is asked" claude "$(claude_bash 'gh pr create --fill')" ask "" "$T/t-argv/hooks/permission-guard.sh"
judge "  ... once, with neither --skill nor --objective" "1 0" "$(wc -l < "$T/argv.log" | tr -d ' ') $(grep -c -e '--skill' -e '--objective' "$T/argv.log")"
rm -f "$T/argv.log"
expect "the fast path reads no context and runs no resolver" claude "$(claude_bash 'ls')" allow "" "$T/t-argv/hooks/permission-guard.sh"
judge "  ... nothing logged" no "$(exists "$T/argv.log")"

# --- 9. plugin-config.sh confirm <nonce> (D5) ------------------------------------------------
section "confirm <nonce>: the dialog names the request, PG stamps what it showed"
PEND="$STATE/pending"
ASKED="$STATE/asked"
mkdir -p "$PEND"; chmod 700 "$STATE" "$PEND"
mk_pending() { # mk_pending <nonce> <kind> [expires] [mode] — a record as the writers render it
  python3 - "$PEND/$1.json" "$1" "$2" "${3:-2099-01-01T00:00:00Z}" "${4:-600}" <<'PY'
import hashlib, json, os, sys
path, nonce, kind, exp, mode = sys.argv[1:6]
def render(d): return (json.dumps(d, indent=2, sort_keys=True, ensure_ascii=True) + "\n").encode("ascii")
if kind == "perms":
    rec = {"version": 1, "kind": "perms", "nonce": nonce, "skill": "pr-dev", "level": "standard",
           "target": {"arg": "42", "repo": "github.com/me/app"}, "session_id": "pg-1", "agent": "main",
           "host": "claude", "command_name": "tamirs-superpowers:pr-dev", "created": "2026-11-04T10:00:00Z", "expires": exp}
else:
    rec = {"version": 1, "kind": "config", "nonce": nonce, "created": "2026-11-04T10:00:00Z", "expires": exp,
           "op": "pr.merge.auto allow", "base_sha256": "absent", "doc": {"version": 1, "actions": {"pr.merge.auto": "allow"}},
           "rows": [{"action": "pr.merge.auto", "r": 3, "from": "ask", "to": "allow", "skills": [],
                     "context": "when its preconditions hold"}], "host": "claude"}
rec["body_sha256"] = hashlib.sha256(render(rec)).hexdigest()
if os.path.exists(path):
    os.unlink(path)
open(path, "wb").write(render(rec))
os.chmod(path, int(mode, 8))
PY
}
N1=11111111111111111111111111111111
N2=22222222222222222222222222222222
mk_pending "$N1" perms
expect "claude: confirm of a --perms= request asks" claude "$(claude_bash "bash scripts/plugin-config.sh confirm $N1")" ask "policy.edit"
r="$(reason)"
for w in "skill pr-dev" "--perms=standard" "github.com/me/app/42" "15 minutes" "never R4" "expires 2099-01-01T00:00:00Z"; do
  judge "  ... the dialog names '$w'" yes "$(has "$r" "$w")"
done
judge "  ... PG stamped asked/$N1.json" yes "$(exists "$ASKED/$N1.json")"
judge "  ... 0600 in a 0700 dir" "600 700" "$(python3 -c 'import os,sys; print(" ".join(oct(os.stat(p).st_mode & 0o777)[2:] for p in sys.argv[1:]))' "$ASKED/$N1.json" "$ASKED")"
judge "  ... with the sha256 of the bytes it showed" \
  "$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$PEND/$N1.json")" \
  "$(jq -r .file_sha256 "$ASKED/$N1.json")"
judge "  ... the record's own hash, the session and the expiry" "$(jq -r .body_sha256 "$PEND/$N1.json") pg-1 2099-01-01T00:00:00Z" \
  "$(jq -r '"\(.body_sha256) \(.session_id) \(.expires)"' "$ASKED/$N1.json")"
judge "  ... and left the pending record for the writer" yes "$(exists "$PEND/$N1.json")"
mk_pending "$N2" config
expect "claude: confirm of a config change asks and names its rows" claude "$(claude_bash "bash scripts/plugin-config.sh confirm $N2")" ask "pr.merge.auto (R3): ask -> allow for every skill when its preconditions hold"
judge "  ... and the op" yes "$(has "$(reason)" "pr.merge.auto allow")"
rm -rf "$ASKED"
expect "codex: confirm of a valid record is still a deny (no channel, D5)" codex "$(codex_bash "bash scripts/plugin-config.sh confirm $N1")" deny "policy.edit"
expect "opencode: likewise" claude "$(oc_bash "bash scripts/plugin-config.sh confirm $N1")" deny "policy.edit"
judge "  ... neither wrote a confirm stamp" no "$(exists "$ASKED/$N1.json")"
expect "a nonce with no record: a deny, nothing to approve" claude "$(claude_bash 'bash scripts/plugin-config.sh confirm 33333333333333333333333333333333')" deny "nothing for the user to approve"
expect "not a nonce: a deny" claude "$(claude_bash 'bash scripts/plugin-config.sh confirm 0123456789abcdef')" deny "not a nonce"
expect "confirm with no nonce: a deny" claude "$(claude_bash 'bash scripts/plugin-config.sh confirm')" deny "not a nonce"
mk_pending "$N1" perms 2020-01-01T00:00:00Z
expect "an expired request: a deny" claude "$(claude_bash "bash scripts/plugin-config.sh confirm $N1")" deny "expired"
mk_pending "$N1" perms
python3 - "$PEND/$N1.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["level"] = "unattended"
open(p, "w").write(json.dumps(d, indent=2, sort_keys=True) + "\n")
PY
expect "an altered record (its hash no longer matches): a deny" claude "$(claude_bash "bash scripts/plugin-config.sh confirm $N1")" deny "does not match its hash"
mk_pending "$N1" perms 2099-01-01T00:00:00Z 644
expect "a group/world-readable record: a deny (unsafe)" claude "$(claude_bash "bash scripts/plugin-config.sh confirm $N1")" deny "nothing for the user to approve"
judge "none of those denies was stamped" no "$(exists "$ASKED")"
mk_pending "$N1" perms
expect "confirm beside an R3 call: the dialog still names the request" claude "$(claude_bash "bash scripts/plugin-config.sh confirm $N1 && gh pr merge 5")" ask "skill pr-dev"
judge "classify lists the nonce" "[\"$N1\"]" "$(classify "bash scripts/plugin-config.sh confirm $N1" | jq -c .confirms)"
rm -rf "$PEND" "$ASKED"

# --- 10. libraries and wiring ---------------------------------------------------------------
section "hook_ask: an ask on Claude only"
HO="$ROOT/hooks/lib/hook-output.sh"
judge "claude: permissionDecision ask" ask "$(bash -c 'source "$1"; HOOK_PLATFORM=claude; hook_ask "why"' _ "$HO" | jq -r .hookSpecificOutput.permissionDecision)"
judge "claude: the reason is kept" why "$(bash -c 'source "$1"; HOOK_PLATFORM=claude; hook_ask "why"' _ "$HO" | jq -r .hookSpecificOutput.permissionDecisionReason)"
judge "codex: a deny" deny "$(bash -c 'source "$1"; HOOK_PLATFORM=codex; hook_ask "why"' _ "$HO" | jq -r .hookSpecificOutput.permissionDecision)"
judge "cursor: a deny in Cursor's shape" deny "$(bash -c 'source "$1"; HOOK_PLATFORM=cursor; hook_ask "why"' _ "$HO" | jq -r .permission)"
judge "gemini env: a deny" deny "$(GEMINI_PROJECT_DIR=/x bash -c 'source "$1"; HOOK_PLATFORM=claude; hook_ask "why"' _ "$HO" | jq -r .hookSpecificOutput.permissionDecision)"
judge "hook_deny is unchanged (claude)" deny "$(bash -c 'source "$1"; HOOK_PLATFORM=claude; hook_deny "why"' _ "$HO" | jq -r .hookSpecificOutput.permissionDecision)"
judge "hook_allow is unchanged (claude)" '{}' "$(bash -c 'source "$1"; HOOK_PLATFORM=claude; hook_allow' _ "$HO")"

section "the shared tokeniser"
CT="$ROOT/hooks/lib/command-tokens.sh"
seg() { bash -c 'source "$1"; "$2" "$3" | tr "\037\036" "|^"' _ "$CT" "$1" "$2" 2>/dev/null; }
judge "default mode: a quoted push is one argument" 'git|commit|-m|x; git push' "$(seg cmdtok_segments 'git commit -m "x; git push"')"
judge "default mode: \$( ) splits (agent-claim's contract)" "$(printf 'git|push|origin\ngit|branch|--show-current')" "$(seg cmdtok_effective_segments 'git push origin $(git branch --show-current)')"
judge "keep mode: the substitution stays in its word and is also a nested segment" \
  "$(printf '^gh|auth|token\ncurl|-H|t $(gh auth token)|https://api.github.com/x')" "$(seg cmdtok_argv_segments 'curl -H "t $(gh auth token)" https://api.github.com/x')"
judge "agent-claim still exposes the tokeniser under its names" yes \
  "$(bash -c 'source "$1"; type claim_shell_segments >/dev/null && type claim_effective_segments >/dev/null && [ "$_CLAIM_TOKSEP" = "$CMDTOK_SEP" ] && echo yes' _ "$ROOT/hooks/lib/agent-claim.sh")"

section "wiring"
judge "hooks.json: PG on Bash|Shell, onFailure block" 1 \
  "$(jq '[.hooks.PreToolUse[] | select(.matcher=="Bash|Shell") | .hooks[] | select(.command|test("permission-guard.sh")) | select(.onFailure=="block")] | length' "$ROOT/hooks/hooks.json")"
judge "hooks.json: PG on the GitHub MCP matcher, onFailure block" 1 \
  "$(jq --arg m "${PFX}.*" '[.hooks.PreToolUse[] | select(.matcher==$m) | .hooks[] | select(.command|test("permission-guard.sh")) | select(.onFailure=="block")] | length' "$ROOT/hooks/hooks.json")"
judge "the MCP matcher matches a tool of the server and not another" "yes no" \
  "$(python3 -c "import re,sys; m=sys.argv[1]; print(' '.join('yes' if re.fullmatch(m, t) else 'no' for t in (sys.argv[2]+'merge_pull_request', 'mcp__other__merge_pull_request')))" "${PFX}.*" "$PFX")"
judge "codex hooks.json carries PG on both matchers" 2 \
  "$(jq '[.hooks.PreToolUse[] | .hooks[] | select(.command|test("permission-guard.sh"))] | length' "$ROOT/platforms/codex/hooks.json")"
for ev in preToolUse beforeShellExecution; do
  judge "cursor $ev: PG, failClosed, no loop cap" 1 \
    "$(jq --arg e "$ev" '[.hooks[$e][] | select(.command|test("permission-guard.sh")) | select(.failClosed==true and has("loop_limit") and .loop_limit==null)] | length' "$ROOT/platforms/cursor/hooks.json")"
done
judge "hooks-classification.md names PG core-safety-invariant" yes \
  "$(grep -q 'permission-guard.sh.*core-safety-invariant' "$ROOT/docs/engineering/architecture/hooks-classification.md" && echo yes || echo no)"

harness_summary
