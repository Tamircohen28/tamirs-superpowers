#!/usr/bin/env bash
# test-plugin-config.sh — the D6 writer, the D5 intent hook and the D8 GitHub MCP
# flags (ADR 004 items 6, 8; D3, D5, D6, D8, D10).
#
# WHAT IS PINNED
#   * scripts/plugin-config.sh: set / show / reset round-trip on a temp passwd
#     home; the lock it writes verifies in scripts/resolve-permission.sh;
#     anti-escalation (a widening inside an agent session is only recorded
#     pending; `confirm` applies it once, on a host with a channel, and is refused
#     where there is none); R4 allow is never stored; trust widens pr.merge.auto
#     for its own remote only; provision is refused inside a session and marks
#     its lock by: provision; nothing is written when the test root is refused.
#   * hooks/permission-intent.sh, from crafted Claude payloads: a user-typed
#     slash command with a raising --perms= records a PENDING request (never a
#     ticket); a non-user or missing `source` records none; a lowering becomes a
#     lowering ticket at once; confirm turns a pending request into a ticket.
#   * scripts/github-mcp.sh --print-flags: the D8 flags per level (the server is
#     never started).
#
# NOTHING TOUCHES THE REAL HOME
#   Every run points TAMIRS_PERMISSION_TEST_ROOT at a temp root. The permission
#   library honours it only while an ancestor shell runs one of its named
#   permission suites (scripts/lib/permission-common.sh, TEST_SCRIPTS), which
#   must include this file's name; the suite aborts before any write otherwise.
#   The writer finds the agent session from its process ancestry, so the suite
#   pins TAMIRS_PERMISSION_TEST_SESSION, which the writer honours only under the
#   test root. A witness on the real config and state dirs is compared at the end.
#
# Usage: bash tests/test-plugin-config.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require jq python3 git
PC="$REPO_ROOT/scripts/plugin-config.sh"
RESOLVE="$REPO_ROOT/scripts/resolve-permission.sh"
HOOK="$REPO_ROOT/hooks/permission-intent.sh"
MCP="$REPO_ROOT/scripts/github-mcp.sh"

unset CODEX_HOME GEMINI_SESSION_ID GEMINI_PROJECT_DIR TS_PERMISSION_LEVEL CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL \
  TAMIRS_AUTO_MERGE GH_REPO GH_HOST CLAUDE_PLUGIN_DATA SUPERPOWERS_OBJECTIVE_ID OBJECTIVES_ROOT
export NO_COLOR=1 TAMIRS_PERMISSION_TEST_SESSION=none

REAL_HOME="$(python3 -I -S -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
witness() { ls -lAR "$REAL_HOME/.config/tamirs-superpowers" "$REAL_HOME/.local/state/tamirs-superpowers" 2>/dev/null | shasum | awk '{print $1}'; }
REAL_BEFORE="$(witness)"

NOWHERE="$(harness_tmpdir)"
new_root() { local r; r="$(harness_tmpdir)"; chmod 700 "$r"; printf '%s' "$r"; }
# pc <root> <session> <args...> — the writer from a directory with no repository.
pc() { local root="$1" s="$2"; shift 2; (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$root" TAMIRS_PERMISSION_TEST_SESSION="$s" bash "$PC" "$@" 2>&1); }
pcj() { pc "$@" --json; }
pfile() { printf '%s/.config/tamirs-superpowers/permissions.json' "$1"; }
plock() { printf '%s/.config/tamirs-superpowers/permissions.lock' "$1"; }
sdir() { printf '%s/.local/state/tamirs-superpowers' "$1"; }
sum() { [ -f "$1" ] && shasum "$1" | awk '{print $1}' || printf 'MISSING'; }
mode_of() { python3 -I -S -c 'import os, stat, sys; print("%o" % stat.S_IMODE(os.stat(sys.argv[1]).st_mode))' "$1" 2>/dev/null || printf 'MISSING'; }
level_of() { (cd "${3:-$NOWHERE}" && TAMIRS_PERMISSION_TEST_ROOT="$1" bash "$RESOLVE" --level --json ${2:+--skill "$2"} 2>/dev/null); }
verdict_of() { local root="$1"; shift; (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$root" bash "$RESOLVE" "$@" 2>/dev/null | jq -r .verdict); }
ufstate() { level_of "$1" | jq -r '.level_sources[] | select(.source == "user_file") | .state'; }

# ---------------------------------------------------------------------------
section "the test root is honoured (precondition for every write below)"

ROOT="$(new_root)"
src="$(cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$ROOT" bash -c '. "$1"; perm_dirs' x "$REPO_ROOT/scripts/lib/permission-common.sh" 2>/dev/null | jq -r '.home_source')"
if [ "$src" != test-root ]; then
  bad "the permission library honours TAMIRS_PERMISSION_TEST_ROOT under this suite" \
    "home_source=$src: add test-plugin-config.sh to TEST_SCRIPTS in scripts/lib/permission-common.sh"
  printf 'FATAL: refusing to run write cases: they would target the real home\n'
  harness_summary
fi
ok "the permission library honours TAMIRS_PERMISSION_TEST_ROOT under this suite"

LOOSE="$(new_root)"; chmod 755 "$LOOSE"
out="$(pc "$LOOSE" none standard)"; rc=$?
judge "a refused test root (0755): the writer exits 1" 1 "$rc"
judge "and says it will not write the real home" yes "$(has "$out" 'refusing to write there')"
judge "and nothing lands in the loose root" no "$(exists "$(pfile "$LOOSE")")"

# ---------------------------------------------------------------------------
section "set / show / reset round-trip; the lock verifies in the resolver"

out="$(pc "$ROOT" none standard)"; rc=$?
judge "set standard (outside any session) exits 0" 0 "$rc"
judge "it lists what it widened" yes "$(has "$out" 'widened: pr.create (R2): ask -> allow')"
judge "the file is 0600" 600 "$(mode_of "$(pfile "$ROOT")")"
judge "its dir is 0700" 700 "$(mode_of "$ROOT/.config/tamirs-superpowers")"
judge "the lock is 0600" 600 "$(mode_of "$(plock "$ROOT")")"
judge "deterministic bytes: sorted keys, 2-space indent" '{
  "level": "standard",
  "version": 1
}' "$(cat "$(pfile "$ROOT")")"
judge "the lock hashes the exact bytes" "$(shasum -a 256 "$(pfile "$ROOT")" | awk '{print $1}')" "$(jq -r .sha256 "$(plock "$ROOT")")"
judge "the lock is by plugin-config" plugin-config "$(jq -r .by "$(plock "$ROOT")")"
judge "the resolver reads standard from the user file" "standard user_file.level" "$(level_of "$ROOT" | jq -r '"\(.level) \(.level_source)"')"
judge "and reads it as verified" verified "$(ufstate "$ROOT")"

pc "$ROOT" none pr-dev unattended >/dev/null
pc "$ROOT" none dev-workflow supervised >/dev/null
pc "$ROOT" none pr.merge.auto allow >/dev/null
pc "$ROOT" none pkg.install.network pr-dev deny >/dev/null
judge "per-skill, per-group, action and skill_action entries land" \
  '{"actions":{"pr.merge.auto":"allow"},"groups":{"dev-workflow":{"level":"supervised"}},"level":"standard","skill_actions":{"pr-dev":{"pkg.install.network":"deny"}},"skills":{"pr-dev":"unattended"},"version":1}' \
  "$(jq -c -S '.groups[].skills = null | del(.groups[].skills)' "$(pfile "$ROOT")")"
judge "a group carries the category's skill snapshot" yes \
  "$(jq -r '.groups["dev-workflow"].skills | index("pr-dev") != null' "$(pfile "$ROOT")" | sed 's/true/yes/')"
judge "skills.pr-dev beats its group: the resolver gives pr-dev unattended" unattended "$(level_of "$ROOT" pr-dev | jq -r .level)"
judge "the resolver still reads it verified after four writes" verified "$(ufstate "$ROOT")"
judge "the previous bytes are kept as permissions.json.bak" yes "$(exists "$(pfile "$ROOT").bak")"

js="$(pcj "$ROOT" none show)"
judge "show --json: the user file state" verified "$(printf '%s' "$js" | jq -r .user_file.state)"
judge "show --json: the lock author" plugin-config "$(printf '%s' "$js" | jq -r .user_file.lock_by)"
judge "show --json: the effective level and its source" "standard user_file.level" "$(printf '%s' "$js" | jq -r '"\(.level.level) \(.level.level_source)"')"
out="$(pc "$ROOT" none show)"
judge "show lists each entry" yes "$(has "$out" 'skills.pr-dev = unattended')"
judge "show prints the hash" yes "$(has "$out" "sha256   $(jq -r .sha256 "$(plock "$ROOT")")")"
judge "show <action> asks the resolver" yes "$(has "$(pc "$ROOT" none show pr.create)" 'action pr.create (R2): allow')"

before="$(sum "$(pfile "$ROOT")")"
out="$(pc "$ROOT" none standard)"
judge "setting what is already there writes nothing" "$before" "$(sum "$(pfile "$ROOT")")"
judge "and says so" yes "$(has "$out" 'nothing to do')"

pc "$ROOT" none reset pr-dev >/dev/null
judge "reset <skill> drops skills.<s> and skill_actions.<s>" "null null" "$(jq -r '"\(.skills["pr-dev"]) \(.skill_actions)"' "$(pfile "$ROOT")")"
pc "$ROOT" none reset pr.merge.auto >/dev/null
judge "reset <action> drops it" null "$(jq -r '.actions' "$(pfile "$ROOT")")"
pc "$ROOT" none reset all >/dev/null
judge "reset all leaves only the version" '{"version":1}' "$(jq -c . "$(pfile "$ROOT")")"
judge "and the resolver answers supervised from the default" "supervised default" "$(level_of "$ROOT" | jq -r '"\(.level) \(.level_source)"')"

out="$(pc "$ROOT" none nonsense standard)"; rc=$?
judge "an unknown target is a usage error (2)" 2 "$rc"
out="$(pc "$ROOT" none pr-dev bogus)"; rc=$?
judge "a skill takes a level only (2)" 2 "$rc"

# ---------------------------------------------------------------------------
section "anti-escalation: a widening in a session is only recorded (D5, D6)"

R2="$(new_root)"
pc "$R2" none standard >/dev/null
before="$(sum "$(pfile "$R2")")"
js="$(pcj "$R2" claude unattended)"; rc="$(printf '%s' "$js" | jq -r .exit)"
judge "a raise inside a Claude session exits 4 (pending)" 4 "$rc"
judge "the file is unchanged" "$before" "$(sum "$(pfile "$R2")")"
judge "the result names its widened rows" yes "$(printf '%s' "$js" | jq -r '[.rows[].action] | index("pr.merge.auto") != null' | sed 's/true/yes/')"
NONCE="$(printf '%s' "$js" | jq -r .nonce)"
judge "the nonce is 128 bits of hex" yes "$(printf '%s' "$NONCE" | grep -qE '^[0-9a-f]{32}$' && echo yes || echo no)"
PEND="$(sdir "$R2")/pending/$NONCE.json"
judge "the pending record is 0600" 600 "$(mode_of "$PEND")"
judge "it records the base file's hash" "$(shasum -a 256 "$(pfile "$R2")" | awk '{print $1}')" "$(jq -r .base_sha256 "$PEND")"
judge "and prints the confirm command" yes "$(has "$(printf '%s' "$js" | jq -r '.messages | join(" ")')" "plugin-config.sh confirm $NONCE")"

out="$(pc "$R2" codex confirm "$NONCE")"; rc=$?
judge "confirm inside a Codex session is refused (3)" 3 "$rc"
judge "it says the raise path is disabled and names the terminal route" yes "$(has "$out" 'confirm is disabled in this session')"
judge "a refused confirm does not consume the request" yes "$(exists "$PEND")"
for s in cursor opencode nested claude-desktop; do
  pc "$R2" "$s" confirm "$NONCE" >/dev/null; rc=$?
  judge "confirm in a $s session is refused (3)" 3 "$rc"
done

cp "$PEND" "$R2/saved"
python3 -I -S -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["doc"]["level"]="unattended"; d["doc"]["actions"]={"pr.merge":"allow"}; open(p,"w").write(json.dumps(d, indent=2, sort_keys=True)+"\n")' "$PEND"
out="$(pc "$R2" claude confirm "$NONCE")"; rc=$?
judge "an altered pending record is refused" 1 "$rc"
judge "because its hash no longer matches" yes "$(has "$out" 'does not match its nonce or its hash')"
judge "the file is still unchanged" "$before" "$(sum "$(pfile "$R2")")"

NONCE="$(pcj "$R2" claude unattended | jq -r .nonce)"
out="$(pc "$R2" claude confirm "$NONCE")"; rc=$?
judge "confirm in a Claude session (the PG dialog is the proof) exits 0" 0 "$rc"
judge "it applied the raise" unattended "$(jq -r .level "$(pfile "$R2")")"
judge "the resolver reads it verified" "unattended verified" "$(level_of "$R2" | jq -r '[.level, (.level_sources[] | select(.source == "user_file") | .state)] | join(" ")')"
out="$(pc "$R2" claude confirm "$NONCE")"; rc=$?
judge "a nonce is single-use" 1 "$rc"

out="$(pc "$R2" codex supervised)"; rc=$?
judge "a lowering is written at once, even with no channel" "0 supervised" "$rc $(jq -r .level "$(pfile "$R2")")"
NONCE="$(pcj "$R2" codex standard | jq -r .nonce)"
judge "a raise in a Codex session is recorded pending too" yes "$(exists "$(sdir "$R2")/pending/$NONCE.json")"
judge "and says to confirm it in the user's own terminal" yes "$(has "$(pc "$R2" codex standard)" 'outside any agent session')"
out="$(pc "$R2" none confirm "$NONCE")"; rc=$?
judge "the same nonce confirmed outside any session applies it" "0 standard" "$rc $(jq -r .level "$(pfile "$R2")")"

# A hand edit behind the lock is tighten-only; re-locking it is a widening.
python3 -I -S -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["level"]="unattended"; open(p,"w").write(json.dumps(d))' "$(pfile "$R2")"
judge "a hand edit reads tighten-only" tighten-only "$(ufstate "$R2")"
js="$(pcj "$R2" claude pr.create ask)"
judge "re-locking it inside a session counts as widening (D10.2)" pending "$(printf '%s' "$js" | jq -r .result)"

# ---------------------------------------------------------------------------
section "R4 allow is never stored; deny always is"

R3="$(new_root)"
out="$(pc "$R3" none pr.merge.admin allow)"; rc=$?
judge "R4 allow is refused (3)" 3 "$rc"
judge "no file was written" no "$(exists "$(pfile "$R3")")"
out="$(pc "$R3" claude pr.merge.admin deny)"; rc=$?
judge "R4 deny is a tightening: written at once in a session" "0 deny" "$rc $(jq -r '.actions["pr.merge.admin"]' "$(pfile "$R3")")"
judge "the resolver honours it" deny "$(verdict_of "$R3" pr.merge.admin)"
js="$(pcj "$R3" claude reset pr.merge.admin)"
judge "dropping a deny inside a session is a widening (pending)" pending "$(printf '%s' "$js" | jq -r .result)"

# ---------------------------------------------------------------------------
section "trust: the project file may widen pr.merge.auto, for its own remote only (D3)"

R4="$(new_root)"
REPO="$(harness_tmpdir)/app"; harness_new_repo "$REPO"
git -C "$REPO" remote add origin https://github.com/you/app.git
mkdir -p "$REPO/.tamirs-superpowers"
printf '{"version": 1, "actions": {"pr.merge.auto": "allow"}}\n' > "$REPO/.tamirs-superpowers/permissions.json"
pc "$R4" none standard >/dev/null
rv() { (cd "$REPO" && TAMIRS_PERMISSION_TEST_ROOT="$R4" bash "$RESOLVE" "$@" 2>/dev/null); }
judge "before trust: pr.merge.auto at standard asks" ask "$(rv pr.merge.auto --target you/app#1 | jq -r .verdict)"
js="$(cd "$REPO" && TAMIRS_PERMISSION_TEST_ROOT="$R4" TAMIRS_PERMISSION_TEST_SESSION=claude bash "$PC" trust --json 2>&1)"
judge "trust inside a session is always pending" pending "$(printf '%s' "$js" | jq -r .result)"
out="$(cd "$REPO" && TAMIRS_PERMISSION_TEST_ROOT="$R4" TAMIRS_PERMISSION_TEST_SESSION=none bash "$PC" trust 2>&1)"; rc=$?
judge "trust outside a session exits 0" 0 "$rc"
judge "the entry binds repo, remote, hash and widens only pr.merge.auto" \
  "$(canon "$REPO")|github.com/you/app|$(shasum -a 256 "$REPO/.tamirs-superpowers/permissions.json" | awk '{print $1}')|[\"pr.merge.auto\"]" \
  "$(jq -r '.trust[0] | "\(.repo)|\(.remote)|\(.sha256)|\(.widens | tojson)"' "$(pfile "$R4")")"
judge "the resolver accepts it: pr.merge.auto on its own remote is allowed" allow "$(rv pr.merge.auto --target you/app#1 | jq -r .verdict)"
judge "the trust check says trusted" true "$(cd "$REPO" && TAMIRS_PERMISSION_TEST_ROOT="$R4" bash -c '. "$1"; perm_trust_check "$2" you/app#1' x "$REPO_ROOT/scripts/lib/permission-common.sh" "$REPO" | jq -r .trusted)"
judge "another remote gets nothing from it" ask "$(rv pr.merge.auto --target you/other#1 | jq -r .verdict)"
judge "nor does any other action (pr.merge stays ask)" ask "$(rv pr.merge --target you/app#1 | jq -r .verdict)"
printf '{"version": 1, "actions": {"pr.merge.auto": "allow"}, "level": "standard"}\n' > "$REPO/.tamirs-superpowers/permissions.json"
judge "a changed project file loses the trust" ask "$(rv pr.merge.auto --target you/app#1 | jq -r .verdict)"
printf '{"version": 1, "level": "supervised"}\n' > "$REPO/.tamirs-superpowers/permissions.json"
out="$(cd "$REPO" && TAMIRS_PERMISSION_TEST_ROOT="$R4" bash "$PC" trust 2>&1)"; rc=$?
judge "a project file that allows nothing has nothing to trust" "1 yes" "$rc $(has "$out" 'nothing to trust')"

# ---------------------------------------------------------------------------
section "provision: CI only, before the agent (D6, SR S-18)"

R5="$(new_root)"
out="$(pc "$R5" claude provision --level standard)"; rc=$?
judge "provision inside an agent session is refused (3)" 3 "$rc"
judge "and writes nothing" no "$(exists "$(pfile "$R5")")"
out="$(pc "$R5" none provision --level unattended)"; rc=$?
judge "provision outside any session exits 0" 0 "$rc"
judge "its lock is by: provision" provision "$(jq -r .by "$(plock "$R5")")"
judge "the resolver reads it verified" "unattended verified" "$(level_of "$R5" | jq -r '[.level, (.level_sources[] | select(.source == "user_file") | .state)] | join(" ")')"
judge "show marks a provisioned lock" yes "$(has "$(pc "$R5" none show)" 'written by CI provision')"
printf '{"version": 1, "level": "standard", "actions": {"pr.merge.auto": "deny"}}\n' > "$R5/spec.json"
pc "$R5" none provision --file "$R5/spec.json" >/dev/null
judge "provision --file writes the given document" deny "$(jq -r '.actions["pr.merge.auto"]' "$(pfile "$R5")")"
printf '{"version": 1, "actions": {"policy.edit": "allow"}}\n' > "$R5/bad.json"
out="$(pc "$R5" none provision --file "$R5/bad.json")"; rc=$?
judge "a document the schema rejects is never written" "1 deny" "$rc $(jq -r '.actions["pr.merge.auto"]' "$(pfile "$R5")")"

# ---------------------------------------------------------------------------
section "the intent hook records requests, never grants (D5)"

R6="$(new_root)"
hook() { (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$R6" bash "$HOOK"); }
expn() { jq -nc --arg a "$1" --arg s "$2" --arg c "${3:-tamirs-superpowers:pr-dev}" \
  '{hook_event_name:"UserPromptExpansion",session_id:$s,cwd:"/",expansion_type:"slash_command",command_name:$c,command_args:$a,prompt:("/" + $c + " " + $a)}'; }
subm() { jq -nc --arg p "$1" --arg src "$2" --arg s "$3" \
  '{hook_event_name:"UserPromptSubmit",session_id:$s,cwd:"/",prompt:$p} + (if $src == "" then {} else {source:$src} end)'; }
npend() { find "$(sdir "$R6")/pending" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }
ntick() { find "$(sdir "$R6")/tickets" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

out="$(expn '42 --perms=unattended' s1 | hook)"
judge "an expansion alone records no request (it waits for its submit half)" "0" "$(npend)"
ctx="$(sdir "$R6")/intent/s1.json"
judge "it writes the active-skill context" "pr-dev unattended 42" "$(jq -r '"\(.skill) \(.perms) \(.target.arg)"' "$ctx" 2>/dev/null)"
out="$(subm '/tamirs-superpowers:pr-dev 42 --perms=unattended' user s1 | hook)"
judge "a user-typed submit pairs: one pending request" 1 "$(npend)"
judge "and no ticket (a request is never a grant)" 0 "$(ntick)"
judge "the model is told it is a request and how to confirm" yes "$(has "$(printf '%s' "$out" | jq -r .hookSpecificOutput.additionalContext)" 'This is a REQUEST, not a grant')"
judge "the hook answers in the UserPromptSubmit dialect" UserPromptSubmit "$(printf '%s' "$out" | jq -r .hookSpecificOutput.hookEventName)"
REC="$(find "$(sdir "$R6")/pending" -name '*.json' | head -1)"
judge "the record carries skill, level, target, session and agent" "perms pr-dev unattended 42 s1 main" \
  "$(jq -r '"\(.kind) \(.skill) \(.level) \(.target.arg) \(.session_id) \(.agent)"' "$REC")"
judge "the context is marked user-typed" true "$(jq -r .user_typed "$ctx")"

subm '/pr-dev 42 --perms=standard' sdk s2 | hook >/dev/null
out="$(expn '42 --perms=standard' s2 | hook)"
judge "source sdk: no request" 1 "$(npend)"
judge "and the model is told why" yes "$(has "$out" 'not typed by the user (source sdk)')"
subm '/pr-dev 42 --perms=standard' "" s3 | hook >/dev/null
expn '42 --perms=standard' s3 | hook >/dev/null
judge "a missing source: no request" 1 "$(npend)"
expn $'42\n--perms=unattended' s4 | hook >/dev/null
subm $'/pr-dev 42\n--perms=unattended' user s4 | hook >/dev/null
judge "--perms= off the first line is ignored" 1 "$(npend)"
out="$(expn '42 --perms=bypass' s5 | hook)"
judge "a value that is not a level is ignored with a note" yes "$(has "$out" 'is not a level')"
out="$(subm 'please run with --perms=standard' user s6 | hook)"
judge "a plain prompt with no expansion records nothing" "1 ''" "$(npend) '$out'"

# A lowering needs no provenance (SR S-09): written at once, as a lowering ticket.
pc "$R6" none standard >/dev/null
out="$(expn '7 --perms=supervised' s7 | hook)"
judge "a lowering becomes a ticket at once" 1 "$(ntick)"
TK="$(find "$(sdir "$R6")/tickets" -name '*.json' | head -1)"
judge "a lowering ticket for that skill and session" "lower pr-dev supervised s7" "$(jq -r '"\(.kind) \(.skill) \(.level) \(.session_id)"' "$TK")"
judge "the model is told it lowers" yes "$(has "$out" 'lowers pr-dev from standard to supervised')"

out="$(subm '$pr-dev --perms=unattended' "" s8 | CODEX_HOME="$NOWHERE" hook)"
judge "Codex: a raise is refused with the out-of-session route" yes "$(has "$out" 'codex has no host-attested channel')"
subm '$pr-dev --perms=supervised' "" s9 | CODEX_HOME="$NOWHERE" hook >/dev/null
judge "Codex: a lowering is a session-wide ticket" "lower null" \
  "$(jq -r 'select(.session_id == "s9") | "\(.kind) \(.skill)"' "$(sdir "$R6")"/tickets/*.json)"

out="$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"s10","prompt":"hello"}' | hook)"
judge "an ordinary prompt is silent" "" "$out"

NONCE="$(jq -r .nonce "$REC")"
out="$(pc "$R6" claude confirm "$NONCE")"; rc=$?
judge "confirm turns the request into a ticket" 0 "$rc"
judge "a raise ticket for pr-dev at unattended, bound to its session" "raise pr-dev unattended s1 main" \
  "$(jq -r 'select(.kind == "raise") | "\(.kind) \(.skill) \(.level) \(.session_id) \(.agent)"' "$(sdir "$R6")"/tickets/*.json)"
judge "it expires 15 minutes after it was made" 900 \
  "$(jq -r 'select(.kind == "raise") | [.created, .expires] | map(strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) | .[1] - .[0]' "$(sdir "$R6")"/tickets/*.json)"
judge "the request is consumed" no "$(exists "$REC")"

# ---------------------------------------------------------------------------
section "github-mcp.sh applies the D8 flags per level (never starts the server)"

R7="$(new_root)"
flags() { (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$R7" bash "$MCP" --print-flags "$@" 2>/dev/null | jq -r '"\(.level) \(.flags | join(" "))"'); }
EXCL="merge_pull_request,delete_repository,create_repository,fork_repository,create_or_update_file,push_files,delete_file,issue_write,update_pull_request,pull_request_review_write"
judge "no user file: supervised, --read-only" "supervised --read-only" "$(flags)"
pc "$R7" none standard >/dev/null
judge "standard: merge and R4 tools excluded" "standard --exclude-tools $EXCL" "$(flags)"
pc "$R7" none unattended >/dev/null
judge "unattended: the same exclusions" "unattended --exclude-tools $EXCL" "$(flags --host codex)"
judge "merge_pull_request is excluded at every level above supervised" yes "$(has "$(flags)" merge_pull_request)"
judge "an env level only lowers" "supervised --read-only" "$(TS_PERMISSION_LEVEL=supervised flags)"
judge "a bad --host is a usage error" 2 "$(bash "$MCP" --print-flags --host nope >/dev/null 2>&1; echo $?)"
judge "without a token it refuses to start" 1 "$(cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$R7" env -u GITHUB_PERSONAL_ACCESS_TOKEN bash "$MCP" >/dev/null 2>&1; echo $?)"

# ---------------------------------------------------------------------------
section "the real config and state dirs were never touched"

judge "real-home witness unchanged" "$REAL_BEFORE" "$(witness)"

harness_summary
