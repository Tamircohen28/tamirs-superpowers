#!/usr/bin/env bash
# test-plugin-config.sh — the D6 writer, the D5 intent hook and the D8 GitHub MCP
# flags (ADR 004 items 6, 8; D3, D5, D6, D8, D10).
#
# WHAT IS PINNED
#   * scripts/plugin-config.sh: set / show / reset round-trip on a temp passwd
#     home; the lock it writes verifies in scripts/resolve-permission.sh;
#     anti-escalation (a widening inside an agent session is only recorded
#     pending; `confirm` applies it once, on a host with a channel, and is refused
#     where there is none; on Claude only with the guard's single-use confirm
#     stamp asked/<nonce>.json, written by the real hooks/permission-guard.sh, for
#     these bytes, this nonce, session and host, and fresh); R4 allow is never
#     stored; trust widens pr.merge.auto for its own remote only; provision is
#     refused inside a session and marks its lock by: provision; nothing is
#     written when the test root is refused.
#   * hooks/permission-intent.sh, from crafted Claude payloads: a user-typed
#     slash command with a raising --perms= records a PENDING request (never a
#     ticket); a non-user or missing `source` records none, and a missing one (all
#     Claude Code sends, measured M3) says why and names /plugin-config; a
#     lowering becomes a lowering ticket at once; confirm turns a pending request
#     into a ticket; EVERY slash command pairs with its submit half (on the shared
#     prompt_id when the host sends one, M2), which marks its context
#     host_recorded, and user_typed only for source user (never for another
#     command or a prompt that does not start with it); a PreToolUse on the Skill
#     tool records that skill host_recorded for the calling agent, a subagent in
#     its own file (M5).
#   * ticket hygiene (D5): show lists the active lowering tickets, every writer
#     run prunes expired tickets, and confirming a raise says an active lowering
#     of the session still wins.
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
GUARD="$REPO_ROOT/hooks/permission-guard.sh"
# ask_pg <root> <nonce> [session] — run the real permission guard on the Claude Bash call
# `bash plugin-config.sh confirm <nonce>`; it writes the confirm stamp asked/<nonce>.json
# before it returns ask (the D5 dialog). Prints the guard's decision.
ask_pg() {
  jq -nc --arg c "bash $PC confirm $2" --arg d "$NOWHERE" --arg s "${3:-pg-s}" \
    '{session_id:$s,transcript_path:"/t",cwd:$d,hook_event_name:"PreToolUse",permission_mode:"default",tool_name:"Bash",tool_use_id:"call-1",tool_input:{command:$c,description:"confirm"}}' |
    (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$1" bash "$GUARD" 2>/dev/null) |
    jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null
}
stampf() { printf '%s/asked/%s.json' "$(sdir "$1")" "$2"; }

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
PEND="$(sdir "$R2")/pending/$NONCE.json"
out="$(pc "$R2" claude confirm "$NONCE")"; rc=$?
judge "confirm under the Claude CLI with no guard stamp is refused (3)" 3 "$rc"
judge "it says there is no confirm stamp and that the CLI is no proof alone" "yes yes" \
  "$(has "$out" 'there is no confirm stamp') $(has "$out" 'not proof on its own')"
judge "the file is unchanged" "$before" "$(sum "$(pfile "$R2")")"
judge "the request is kept (the terminal route still works)" yes "$(exists "$PEND")"
judge "the guard asks on this confirm (the D5 dialog)" ask "$(ask_pg "$R2" "$NONCE")"
judge "and stamps asked/<nonce>.json" yes "$(exists "$(stampf "$R2" "$NONCE")")"
cp "$PEND" "$R2/pend.saved"
out="$(pc "$R2" claude confirm "$NONCE")"; rc=$?
judge "confirm with the guard's stamp exits 0" 0 "$rc"
judge "it applied the raise" unattended "$(jq -r .level "$(pfile "$R2")")"
judge "the resolver reads it verified" "unattended verified" "$(level_of "$R2" | jq -r '[.level, (.level_sources[] | select(.source == "user_file") | .state)] | join(" ")')"
judge "the stamp is consumed" no "$(exists "$(stampf "$R2" "$NONCE")")"
out="$(pc "$R2" claude confirm "$NONCE")"; rc=$?
judge "a nonce is single-use" 1 "$rc"
cp "$R2/pend.saved" "$PEND"; chmod 600 "$PEND"
out="$(pc "$R2" claude confirm "$NONCE")"; rc=$?
judge "replaying the confirm (the same record put back) is refused: the stamp is single-use" "3 yes" \
  "$rc $(has "$out" 'there is no confirm stamp')"
rm -f "$PEND"

# A stamp for another nonce, or for other bytes under this nonce, proves nothing.
pc "$R2" none supervised >/dev/null
before="$(sum "$(pfile "$R2")")"
NA="$(pcj "$R2" claude standard | jq -r .nonce)"
NB="$(pcj "$R2" claude unattended | jq -r .nonce)"
judge "the guard asks on confirm A" ask "$(ask_pg "$R2" "$NA")"
mv "$(stampf "$R2" "$NA")" "$(stampf "$R2" "$NB")"
out="$(pc "$R2" claude confirm "$NB")"; rc=$?
judge "A's stamp under B's name is refused (3)" "3 yes" "$rc $(has "$out" 'the confirm stamp is for another request')"
judge "the stamp was consumed by the refusal" no "$(exists "$(stampf "$R2" "$NB")")"
out="$(pc "$R2" claude confirm "$NA")"; rc=$?
judge "and A itself now has no stamp (3)" "3 yes" "$rc $(has "$out" 'there is no confirm stamp')"
judge "the guard asks on confirm B" ask "$(ask_pg "$R2" "$NB")"
PB="$(sdir "$R2")/pending/$NB.json"
python3 -I -S - "$PB" <<'PY2'
import hashlib, json, sys
p = sys.argv[1]
def render(d): return (json.dumps(d, indent=2, sort_keys=True, ensure_ascii=True) + "\n").encode("ascii")
d = json.load(open(p)); d.pop("body_sha256")
d["doc"]["actions"] = {"pr.merge": "allow"}; d["op"] = "pr.merge allow"
d["body_sha256"] = hashlib.sha256(render(d)).hexdigest()
open(p, "wb").write(render(d))
PY2
out="$(pc "$R2" claude confirm "$NB")"; rc=$?
judge "a re-hashed record with another change than the dialog showed is refused (3)" "3 yes" \
  "$rc $(has "$out" 'names other bytes than this pending record')"
judge "nothing was written" "$before" "$(sum "$(pfile "$R2")")"
judge "a stamp naming another host is refused" "3 yes" "$(
  ask_pg "$R2" "$NA" >/dev/null
  python3 -I -S -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["host"]="gemini"; open(p,"w").write(json.dumps(d))' "$(stampf "$R2" "$NA")"
  out="$(pc "$R2" claude confirm "$NA")"; printf '%s %s' "$?" "$(has "$out" 'not claude')")"
judge "a stale stamp (asked over 15 minutes ago) is refused" "3 yes" "$(
  ask_pg "$R2" "$NA" >/dev/null
  python3 -I -S -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["at"]="2026-01-01T00:00:00Z"; open(p,"w").write(json.dumps(d))' "$(stampf "$R2" "$NA")"
  out="$(pc "$R2" claude confirm "$NA")"; printf '%s %s' "$?" "$(has "$out" 'is stale')")"
judge "a stamp the user's other processes could rewrite (0644) is refused" "3 yes" "$(
  ask_pg "$R2" "$NA" >/dev/null; chmod 644 "$(stampf "$R2" "$NA")"
  out="$(pc "$R2" claude confirm "$NA")"; printf '%s %s' "$?" "$(has "$out" 'the confirm stamp is unsafe')")"
judge "after all of that, A still applies with a fresh stamp" "ask 0 standard" "$(
  a="$(ask_pg "$R2" "$NA")"; pc "$R2" claude confirm "$NA" >/dev/null; printf '%s %s %s' "$a" "$?" "$(jq -r .level "$(pfile "$R2")")")"

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
out="$(expn '42 --perms=standard' s3 | hook)"
judge "a missing source: no request" 1 "$(npend)"
judge "  ... and the model is told why: Claude Code sends no prompt origin" yes \
  "$(has "$out" 'Claude Code does not send prompt origin; use /plugin-config to set a durable per-skill level')"
judge "  ... naming the durable route for this skill and level" yes "$(has "$out" '/plugin-config pr-dev standard')"
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
judge "and writes no half (it is no slash command)" no "$(exists "$(sdir "$R6")/intent/s10.submit.json")"

# Every user-typed slash command marks its context user_typed, --perms= or not (D8: a per-skill raise
# from the user file applies only to a user-typed command).
ut() { jq -r .user_typed "$(sdir "$R6")/intent/$1.json" 2>/dev/null; }
np0="$(npend)"; nt0="$(ntick)"
out="$(expn '42' u1 | hook)"
judge "a plain /skill expansion is silent" "" "$out"
judge "  ... its context waits for the submit half (user_typed null)" null "$(ut u1)"
out="$(subm '/tamirs-superpowers:pr-dev 42' user u1 | hook)"
judge "  ... a user-typed submit with no --perms= pairs: user_typed true" true "$(ut u1)"
judge "  ... silently" "" "$out"
judge "  ... and records no request and no ticket" "$np0 $nt0" "$(npend) $(ntick)"
judge "  ... both halves are gone" "no no" "$(exists "$(sdir "$R6")/intent/u1.expansion.json") $(exists "$(sdir "$R6")/intent/u1.submit.json")"
subm '/pr-dev 7' user u2 | hook >/dev/null
judge "the submit half is written for every slash prompt" yes "$(exists "$(sdir "$R6")/intent/u2.submit.json")"
expn '7' u2 | hook >/dev/null
judge "submit first, then expansion, and the short /pr-dev form: user_typed true" true "$(ut u2)"
subm '/pr-dev 7' sdk u3 | hook >/dev/null; expn '7' u3 | hook >/dev/null
judge "source sdk: user_typed false (nothing that can raise)" false "$(ut u3)"
subm '/pr-dev 7' "" u4 | hook >/dev/null; expn '7' u4 | hook >/dev/null
judge "a missing source: user_typed false" false "$(ut u4)"
subm '/tamirs-superpowers:start-dev 7' user u5 | hook >/dev/null; expn '7' u5 | hook >/dev/null
judge "a user submit naming another command does not pair: user_typed null" null "$(ut u5)"
subm 'run /pr-dev 7 for me' user u6 | hook >/dev/null; expn '7' u6 | hook >/dev/null
judge "a prompt that does not start with the command does not pair" null "$(ut u6)"
expn '7' u7 | hook >/dev/null
printf '{"hook_event_name":"UserPromptSubmit","session_id":"u7","cwd":"/","source":"user","prompt":"\\n  /pr-dev 7"}' | hook >/dev/null
judge "leading blank lines before the command still pair" true "$(ut u7)"
expn '42 --perms=unattended' u8 | hook >/dev/null
subm '/tamirs-superpowers:pr-dev 42' user u8 | hook >/dev/null
judge "a --perms= raise whose submit carries none does not pair (no request)" "$np0 null" "$(npend) $(ut u8)"

# host_recorded (D8, M2/M3): pairing proves the host expanded this command for this prompt, whatever `source` says,
# so the user's own per-skill level may widen on it; user_typed stays false while Claude Code sends no source.
hr() { jq -r '"\(.host_recorded) \(.user_typed) \(.recorded_by)"' "$(sdir "$R6")/intent/$1.json" 2>/dev/null; }
judge "a paired user submit: host_recorded true" "true true UserPromptExpansion" "$(hr u1)"
judge "a paired submit with no source: host_recorded true, user_typed false" "true false UserPromptExpansion" "$(hr u4)"
judge "an expansion that never paired: host_recorded false" "false null UserPromptExpansion" "$(hr u5)"
subm_pid() { jq -nc --arg p "$1" --arg s "$2" --arg i "$3" '{hook_event_name:"UserPromptSubmit",session_id:$s,prompt_id:$i,cwd:"/",prompt:$p}'; }
expn_pid() { jq -nc --arg a "$1" --arg s "$2" --arg i "$3" \
  '{hook_event_name:"UserPromptExpansion",session_id:$s,prompt_id:$i,cwd:"/",expansion_type:"slash_command",command_name:"tamirs-superpowers:pr-dev",command_args:$a,command_source:"plugin",prompt:("/tamirs-superpowers:pr-dev " + $a)}'; }
subm_pid '/tamirs-superpowers:pr-dev 42' m1 p-1 | hook >/dev/null; expn_pid '42' m1 p-1 | hook >/dev/null
judge "M2 as measured (submit first, the same prompt_id, no source): host_recorded" "true false UserPromptExpansion" "$(hr m1)"
judge "  ... the context keeps the prompt_id" p-1 "$(jq -r .prompt_id "$(sdir "$R6")/intent/m1.json" 2>/dev/null)"
subm_pid '/tamirs-superpowers:pr-dev 42' m2 p-1 | hook >/dev/null; expn_pid '42' m2 p-2 | hook >/dev/null
judge "another prompt_id does not pair, even inside the 60 s window" "false null UserPromptExpansion" "$(hr m2)"
subm '/tamirs-superpowers:pr-dev 42' "" m3 | hook >/dev/null; expn_pid '42' m3 p-3 | hook >/dev/null
judge "a prompt_id on one half only does not pair" "false null UserPromptExpansion" "$(hr m3)"

# The host's own Skill call (PreToolUse, matcher Skill in hooks/hooks.json): the skill is active for that agent.
skillc() { jq -nc --arg n "$1" --arg s "$2" --arg ag "${3:-}" \
  '{hook_event_name:"PreToolUse",session_id:$s,cwd:"/",tool_name:"Skill",tool_input:{skill:$n,args:"42"}} + (if $ag == "" then {} else {agent_id:$ag,agent_type:"general-purpose"} end)'; }
out="$(skillc tamirs-superpowers:pr-dev k1 | hook)"
judge "a Skill call is silent (it never answers the tool call)" "" "$out"
judge "  ... and records the skill host_recorded for the main thread" "pr-dev main true null PreToolUse:Skill" \
  "$(jq -r '"\(.skill) \(.agent) \(.host_recorded) \(.user_typed) \(.recorded_by)"' "$(sdir "$R6")/intent/k1.json" 2>/dev/null)"
skillc worker-dev k1 af490d90651b7315a | hook >/dev/null
judge "a subagent's Skill call gets its own file (M5 agent_id)" "worker-dev af490d90651b7315a true" \
  "$(jq -r '"\(.skill) \(.agent) \(.host_recorded)"' "$(sdir "$R6")/intent/k1.agent-af490d90651b7315a.json" 2>/dev/null)"
judge "  ... and leaves the main thread's context alone" "pr-dev main" "$(jq -r '"\(.skill) \(.agent)"' "$(sdir "$R6")/intent/k1.json" 2>/dev/null)"
skillc engineering:code-review k1 | hook >/dev/null
judge "another plugin's skill replaces the main context with no skill of ours" "null true" \
  "$(jq -r '"\(.skill) \(.host_recorded)"' "$(sdir "$R6")/intent/k1.json" 2>/dev/null)"
np1="$(npend)"; nt1="$(ntick)"
skillc tamirs-superpowers:pr-dev k2 | jq -c '.tool_input.args = "42 --perms=supervised"' | hook >/dev/null
judge "a Skill call's args are never read for --perms= (model text, D5)" "$np1 $nt1" "$(npend) $(ntick)"
skillc tamirs-superpowers:pr-dev k3 | CODEX_HOME="$NOWHERE" hook >/dev/null
judge "Codex: a Skill-shaped PreToolUse records nothing" no "$(exists "$(sdir "$R6")/intent/k3.json")"
printf '{"hook_event_name":"PreToolUse","session_id":"k4","cwd":"/","tool_name":"Edit","tool_input":{"file_path":"/x"}}' | hook >/dev/null
judge "another tool's PreToolUse records nothing" no "$(exists "$(sdir "$R6")/intent/k4.json")"

NONCE="$(jq -r .nonce "$REC")"
judge "the guard asks on the confirm made from another session" ask "$(ask_pg "$R6" "$NONCE" s-other)"
out="$(pc "$R6" claude confirm "$NONCE")"; rc=$?
judge "a stamp from another session than the request is refused (3)" "3 yes" "$rc $(has "$out" 'from another session')"
judge "the guard asks on the confirm, naming the request" ask "$(ask_pg "$R6" "$NONCE" s1)"
out="$(pc "$R6" claude confirm "$NONCE")"; rc=$?
judge "confirm turns the request into a ticket" 0 "$rc"
judge "a raise ticket for pr-dev at unattended, bound to its session" "raise pr-dev unattended s1 main" \
  "$(jq -r 'select(.kind == "raise") | "\(.kind) \(.skill) \(.level) \(.session_id) \(.agent)"' "$(sdir "$R6")"/tickets/*.json)"
judge "it expires 15 minutes after it was made" 900 \
  "$(jq -r 'select(.kind == "raise") | [.created, .expires] | map(strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) | .[1] - .[0]' "$(sdir "$R6")"/tickets/*.json)"
judge "the request is consumed" no "$(exists "$REC")"

# ---------------------------------------------------------------------------
section "ticket hygiene: show lists lowerings, writers prune expired tickets, a lowering beats a confirmed raise"

R8="$(new_root)"
hook8() { (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$R8" bash "$HOOK"); }
pc "$R8" none standard >/dev/null
expn '7 --perms=supervised' h1 | hook8 >/dev/null
LOWF="$(find "$(sdir "$R8")/tickets" -name '*.json' | head -1)"; LOW="$(basename "$LOWF" .json)"
js="$(pcj "$R8" none show)"
judge "show --json lists the active lowering ticket" "$LOW pr-dev supervised h1" \
  "$(printf '%s' "$js" | jq -r '.lowering_tickets[0] | "\(.id) \(.skill) \(.level) \(.session_id)"')"
judge "show says so in text" yes "$(has "$(pc "$R8" none show)" "lowering ticket $LOW: pr-dev at supervised, session h1")"
judge "--level --session lists the session's lowering tickets" "$LOW" \
  "$( (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$R8" bash "$RESOLVE" --level --json --session h1) | jq -r '.lowering_tickets[0].id')"
judge "  ... and not another session's" 0 \
  "$( (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$R8" bash "$RESOLVE" --level --json --session h2) | jq -r '.lowering_tickets | length')"
# an expired ticket: the resolver ignores it, the next writer run deletes it
OLDT="$(sdir "$R8")/tickets/0123456789abcdef0123456789abcdef.json"
jq -n '{version:1,kind:"lower",id:"0123456789abcdef0123456789abcdef",skill:null,level:"supervised",target:{arg:null,repo:null},session_id:"h1",agent:"main",host:"claude",created:"2026-01-01T00:00:00Z",expires:"2026-01-02T00:00:00Z",source:"test"}' > "$OLDT"
chmod 600 "$OLDT"
judge "an expired ticket is not listed" 1 "$(pcj "$R8" none show | jq -r '.lowering_tickets | length')"
judge "  ... and the writer run that listed it deleted it" no "$(exists "$OLDT")"
judge "the active one is kept" yes "$(exists "$LOWF")"
# a confirmed raise for the same skill and session: the lowering still wins (D4 row 1, lower always)
subm '/tamirs-superpowers:pr-dev 42 --perms=unattended' user h1 | hook8 >/dev/null
expn '42 --perms=unattended' h1 | hook8 >/dev/null
N8="$(jq -r .nonce "$(find "$(sdir "$R8")/pending" -name '*.json' | head -1)" 2>/dev/null)"
judge "the guard asks on the confirm" ask "$(ask_pg "$R8" "$N8" h1)"
out="$(pc "$R8" claude confirm "$N8")"; rc=$?
judge "confirm writes the raise ticket" 0 "$rc"
judge "  ... and says the session's lowering still wins" yes "$(has "$out" "lowering ticket $LOW (pr-dev at supervised")"
judge "  ... which it does not retire" yes "$(exists "$LOWF")"
judge "the resolver agrees: pr-dev runs at supervised in that session" supervised \
  "$( (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$R8" bash "$RESOLVE" --level --json --session h1 --agent main --skill pr-dev) | jq -r .level)"

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
