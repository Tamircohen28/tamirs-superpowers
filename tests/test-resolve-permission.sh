#!/usr/bin/env bash
# test-resolve-permission.sh — the permission resolver (ADR 004 D2, D3, D4, D10;
# implementation item 2): scripts/resolve-permission.sh and
# scripts/lib/permission-common.sh.
#
# WHAT THIS SUITE HOLDS
#   A table: one case per D4 precedence row (7 default, 6 option store + user
#   level, 5 user keys, 4 project file and trust, 3 objective, 2 TAMIRS_AUTO_MERGE,
#   1 tickets not read, 0 invariants) and per failure mode (missing or corrupt
#   catalog and schema, no python3, a missing library, a corrupt user file, wrong
#   owner or mode, lock mismatch or absence, an untrusted widening project file,
#   a trusted one and every way trust breaks, env tightening and attempted
#   widening, headless ask -> deny, the never_auto clamp, an R4 allow attempt, an
#   unknown id), plus the library functions and the test-override guard.
#
# HOW THE FAKE PASSWD HOME WORKS
#   Every case gets a fresh home under a harness temp dir, named by
#   TAMIRS_PERMISSION_TEST_ROOT. The resolver honours it only because this very
#   file is a process ancestor (and the dir is 0700, under a temp root, outside a
#   git work tree); the guard section proves that a process outside this suite
#   with the same variable gets the real passwd home instead. Cases run from a
#   non-repo temp dir, so no checkout's project file leaks in.
#
# Hermetic: writes only under mktemp; no network, no gh, no git remote calls.
# The guard case reads (never writes) the real user file path, if one exists.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"

harness_require python3 jq git

unset TAMIRS_AUTO_MERGE TS_PERMISSION_LEVEL CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL OBJECTIVES_ROOT \
  GH_REPO GH_HOST TAMIRS_PERMISSION_TEST_ROOT

TMP="$(harness_tmpdir)"
# The override is honoured only under a system temp root (the guard's rule 2), so
# a TMPDIR pointing elsewhere (a CI workspace, say) would make every case read the
# real home. Fall back to /tmp then.
case "$(canon "$TMP")" in
  /tmp/*|/private/tmp/*|/var/tmp/*|/private/var/tmp/*|/var/folders/*|/private/var/folders/*) ;;
  *) TMP="$(TMPDIR=/tmp harness_tmpdir)" ;;
esac
RESOLVE="$ROOT/scripts/resolve-permission.sh"
NOWHERE="$TMP/nowhere"
mkdir -p "$NOWHERE"

# ------------------------------------------------------------------ fixtures

sha() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

# new_home — a fresh fake passwd home with a private config dir; prints its path.
new_home() {
  local h
  h="$(mktemp -d "$TMP/home.XXXXXX")"
  chmod 700 "$h"
  mkdir -p "$h/.config/tamirs-superpowers"
  chmod 700 "$h/.config/tamirs-superpowers"
  printf '%s' "$h"
}

cfgdir() { printf '%s/.config/tamirs-superpowers' "$1"; }

# lock <home> <sha256> — what the D6 writer leaves beside the user file.
lock() {
  printf '{"sha256": "%s", "by": "plugin-config", "at": "2026-11-04T00:00:00Z"}\n' "$2" > "$(cfgdir "$1")/permissions.lock"
  chmod 600 "$(cfgdir "$1")/permissions.lock"
}

# user_file <home> <json> [locked|unlocked|badlock]
user_file() {
  local f
  f="$(cfgdir "$1")/permissions.json"
  printf '%s\n' "$2" > "$f"
  chmod 600 "$f"
  case "${3:-locked}" in
    locked) lock "$1" "$(sha "$f")" ;;
    badlock) lock "$1" "$(printf '0%.0s' $(seq 1 64))" ;;
    unlocked) rm -f "$(cfgdir "$1")/permissions.lock" ;;
  esac
}

claude_store() {
  mkdir -p "$1/.claude"
  printf '{"pluginConfigs": {"tamirs-superpowers@tamirs-marketplace": {"options": {"permission_level": "%s"}}}}\n' \
    "$2" > "$1/.claude/settings.json"
  chmod 644 "$1/.claude/settings.json"
}

gemini_store() {
  mkdir -p "$1/.gemini/extensions/tamirs-superpowers"
  printf '# set by gemini extensions config\nTS_PERMISSION_LEVEL="%s"\n' "$2" > "$1/.gemini/extensions/tamirs-superpowers/.env"
}

# new_repo <dir> — a git checkout whose origin is github.com/you/app.
new_repo() {
  harness_new_repo "$1"
  git -C "$1" remote add origin git@github.com:you/app.git
}

project_file() {
  mkdir -p "$1/.tamirs-superpowers"
  printf '%s\n' "$2" > "$1/.tamirs-superpowers/permissions.json"
}

# trust_json <repo> [remote] — a trust entry for the repo's current project file.
trust_json() {
  printf '{"repo": "%s", "remote": "%s", "file": ".tamirs-superpowers/permissions.json", "sha256": "%s", "widens": ["pr.merge.auto"], "at": "2026-11-04T00:00:00Z"}' \
    "$(canon "$1")" "${2:-github.com/you/app}" "$(sha "$1/.tamirs-superpowers/permissions.json")"
}

# ------------------------------------------------------------------ runner

OUT=""
RC=0
# run <home> <resolver args...> — env prefixes on the call reach the resolver.
run() {
  local h="$1"
  shift
  OUT="$(cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$h" bash "$RESOLVE" "$@" 2>/dev/null)"
  RC=$?
}

jf() { printf '%s' "$OUT" | jq -r "$1" 2>/dev/null || echo "<unparsed>"; }

# expect <name> <verdict> [<jq-expr> <expected>]... — the verdict, exit 0, and
# any further fields.
expect() {
  local name="$1" want="$2"
  shift 2
  judge "$name: exit" 0 "$RC"
  judge "$name: verdict" "$want" "$(jf .verdict)"
  while [ $# -ge 2 ]; do
    judge "$name: $1" "$2" "$(jf "$1")"
    shift 2
  done
}

# warned <name> <substring>
warned() { judge "$1: warns '$2'" yes "$(has "$(jf '.warnings | join("\n")')" "$2")"; }

# ------------------------------------------------------------------ row 7 and D2 ceilings
section "row 7: no source means supervised; D2 ceilings per R"

H="$(new_home)"
run "$H" pr.create --host codex
expect "no sources, R2" ask .level supervised .level_source default .r 2 .decision ask
run "$H" repo.read --host codex
expect "no sources, R0" allow
run "$H" git.commit --host codex
expect "no sources, R1" allow

H="$(new_home)"; user_file "$H" '{"version": 1, "level": "standard"}'
run "$H" pr.create --host codex
expect "standard, R2" allow .level standard
run "$H" branch.delete.remote --host codex --cond pr_merged_not_default_not_cross_repo=true \
  --cond unmerged_commits=false --cond tag_ref=false
expect "standard, R3" ask

H="$(new_home)"; user_file "$H" '{"version": 1, "level": "unattended"}'
run "$H" branch.delete.remote --host codex --cond pr_merged_not_default_not_cross_repo=true \
  --cond unmerged_commits=false --cond tag_ref=false
expect "unattended, R3 precondition holds" allow .precondition.state holds
run "$H" pr.close --host codex
expect "unattended, R3 precondition unknown" ask .precondition.state unknown .precondition.name own_pr_or_closes_ref_of_merged_pr
run "$H" pr.merge --host codex
expect "unattended, R3 never_auto" ask .never_auto true
run "$H" repo.create --host codex
expect "unattended, R4: the ceiling asks" ask .r 4 .decided_by "level unattended ceiling for R4"

# ------------------------------------------------------------------ row 6
section "row 6: the lower of the option store and the user file level (D3)"

H="$(new_home)"; claude_store "$H" unattended
run "$H" pr.create --host claude
expect "store unattended, no user file (D3 worked example)" allow .level unattended .level_source option_store:claude
user_file "$H" '{"version": 1, "level": "standard"}'
run "$H" branch.delete.remote --host claude --cond pr_merged_not_default_not_cross_repo=true \
  --cond unmerged_commits=false --cond tag_ref=false
expect "store unattended + file standard" ask .level standard .level_source user_file.level

H="$(new_home)"; user_file "$H" '{"version": 1, "level": "unattended"}'; claude_store "$H" unattended
run "$H" pr.create --host codex
expect "no store on codex, file unattended" allow .level unattended

H="$(new_home)"; claude_store "$H" yolo
run "$H" pr.create --host claude
expect "store value not a level" ask .level supervised
warned "store value not a level" "is not a level"

H="$(new_home)"; gemini_store "$H" standard
run "$H" pr.create --host gemini
expect "gemini .env standard" allow .level standard .level_source option_store:gemini
run "$H" pr.create --host claude
expect "the gemini store is not read on claude" ask .level supervised

H="$(new_home)"; claude_store "$H" unattended
run "$H" pr.create
expect "no --host: a store only lowers" ask .level supervised
user_file "$H" '{"version": 1, "level": "unattended"}'; claude_store "$H" standard
run "$H" branch.delete.remote --cond pr_merged_not_default_not_cross_repo=true \
  --cond unmerged_commits=false --cond tag_ref=false
expect "no --host: store standard lowers file unattended" ask .level standard

section "row 6: env only tightens (D3, SR S-04)"

H="$(new_home)"; claude_store "$H" unattended
CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL=standard run "$H" branch.delete.remote --host claude \
  --cond pr_merged_not_default_not_cross_repo=true --cond unmerged_commits=false --cond tag_ref=false
expect "env CLAUDE_PLUGIN_OPTION tightens" ask .level standard .level_source env:CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL
TS_PERMISSION_LEVEL=supervised run "$H" pr.create --host claude
expect "env TS_PERMISSION_LEVEL tightens" ask .level supervised
TS_PERMISSION_LEVEL=yolo run "$H" pr.create --host claude
expect "env invalid value reads as supervised" ask .level supervised
warned "env invalid value" "env only tightens"

H="$(new_home)"
CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL=unattended run "$H" pr.create --host claude
expect "env attempted widen (claude)" ask .level supervised
TS_PERMISSION_LEVEL=unattended run "$H" pr.create --host gemini
expect "env attempted widen (gemini)" ask .level supervised

# ------------------------------------------------------------------ row 5
section "row 5: user file skill_actions > actions > skills > groups; deny is final"

H="$(new_home)"; user_file "$H" '{"version": 1, "actions": {"pr.create": "allow"}}'
run "$H" pr.create --host codex
expect "actions allow widens supervised" allow .decided_by 'user.actions[pr.create]'

H="$(new_home)"; user_file "$H" '{"version": 1, "level": "unattended", "actions": {"pr.create": "ask"}}'
run "$H" pr.create --host codex
expect "actions ask tightens unattended" ask

H="$(new_home)"; user_file "$H" '{"version": 1, "actions": {"pr.create": "ask"}, "skill_actions": {"pr-dev": {"pr.create": "allow"}}}'
run "$H" pr.create --host codex --skill pr-dev
expect "skill_actions beats actions" allow .decided_by 'user.skill_actions[pr-dev][pr.create]'
run "$H" pr.create --host codex --skill plan-dev
expect "skill_actions is per skill" ask

H="$(new_home)"; user_file "$H" '{"version": 1, "actions": {"pr.create": "deny"}, "skill_actions": {"pr-dev": {"pr.create": "allow"}}}'
run "$H" pr.create --host codex --skill pr-dev
expect "a deny anywhere is final" deny .deny_wins_from 'user.actions[pr.create]'

H="$(new_home)"; user_file "$H" '{"version": 1, "level": "standard", "skills": {"pr-dev": "unattended"}}'
run "$H" pr.close --host codex --skill pr-dev --cond own_pr_or_closes_ref_of_merged_pr=true
expect "skills raises one skill (D3 example)" allow .level unattended .level_source 'user.skills[pr-dev]'
run "$H" pr.close --host codex --skill plan-dev --cond own_pr_or_closes_ref_of_merged_pr=true
expect "skills leaves other skills" ask .level standard

H="$(new_home)"; user_file "$H" '{"version": 1, "level": "standard", "groups": {"dev-workflow": {"level": "unattended", "skills": ["pr-dev"]}}}'
run "$H" pr.close --host codex --skill pr-dev --cond own_pr_or_closes_ref_of_merged_pr=true
expect "group raises a snapshot member" allow .level unattended
run "$H" pr.close --host codex --skill deliver-dev --cond own_pr_or_closes_ref_of_merged_pr=true
expect "group raise skips a member missing from the snapshot" ask .level standard

H="$(new_home)"; user_file "$H" '{"version": 1, "level": "standard", "groups": {"dev-workflow": {"level": "supervised", "skills": []}}}'
run "$H" pr.create --host codex --skill deliver-dev
expect "group lowering reaches every category member" ask .level supervised
run "$H" pr.create --host codex --skill cleanup
expect "group lowering stays in its category" allow .level standard

section "never_auto clamp, R4 allow attempt (D1, D2, D3)"

H="$(new_home)"; user_file "$H" '{"version": 1, "level": "unattended", "actions": {"pr.merge": "allow", "repo.settings.merge": "allow"}}'
run "$H" pr.merge --host codex
expect "actions allow on a never_auto id is clamped to ask" ask .never_auto true \
  .decided_by "pr.merge is never automatic (D1 'none'; D2 R3 row)"
run "$H" repo.settings.merge --host codex
expect "never_auto clamp (repo.settings.merge)" ask

H="$(new_home)"; claude_store "$H" unattended
user_file "$H" '{"version": 1, "level": "unattended", "actions": {"repo.create": "allow"}}'
run "$H" repo.create --host claude
expect "R4 allow in the user file: schema-invalid, supervised" ask .level supervised
warned "R4 allow attempt" "is invalid"
run "$H" pr.create --host claude
expect "an invalid user file also drops the store raise" ask .level supervised

# ------------------------------------------------------------------ user-file failure modes
section "user file failure modes (D3, D10.2, SR S-04)"

H="$(new_home)"; claude_store "$H" unattended
printf '{"version": 1, "level": ' > "$(cfgdir "$H")/permissions.json"; chmod 600 "$(cfgdir "$H")/permissions.json"
run "$H" pr.create --host claude
expect "corrupt user file: supervised" ask .level supervised '.level_sources[] | select(.source=="user_file") | .state' invalid
warned "corrupt user file" "overrides ignored"

TIGHT='{"version": 1, "level": "unattended", "skills": {"pr-dev": "unattended"}, "actions": {"pr.comment": "deny", "pr.create": "allow"}}'
H="$(new_home)"; user_file "$H" "$TIGHT" badlock
run "$H" pr.create --host codex --skill pr-dev
expect "lock mismatch: widening dropped" ask .level supervised '.level_sources[] | select(.source=="user_file") | .lock' mismatch
run "$H" pr.comment --host codex
expect "lock mismatch: tightening kept" deny
warned "lock mismatch" "does not match its lock"

H="$(new_home)"; user_file "$H" "$TIGHT" unlocked
run "$H" pr.create --host codex
expect "no lock: widening dropped" ask '.level_sources[] | select(.source=="user_file") | .lock' absent
run "$H" pr.comment --host codex
expect "no lock: tightening kept" deny

H="$(new_home)"; user_file "$H" "$TIGHT"; chmod 644 "$(cfgdir "$H")/permissions.lock"
run "$H" pr.create --host codex
expect "lock mode 0644: unsafe lock" ask '.level_sources[] | select(.source=="user_file") | .lock' unsafe

H="$(new_home)"; user_file "$H" "$TIGHT"; chmod 644 "$(cfgdir "$H")/permissions.json"
run "$H" pr.create --host codex
expect "user file mode 0644: tighten-only" ask '.level_sources[] | select(.source=="user_file") | .state' tighten-only
run "$H" pr.comment --host codex
expect "user file mode 0644: deny kept" deny
warned "user file mode 0644" "owner/mode checks"

H="$(new_home)"; user_file "$H" "$TIGHT"; chmod 755 "$(cfgdir "$H")"
run "$H" pr.create --host codex
expect "config dir mode 0755: tighten-only" ask '.level_sources[] | select(.source=="user_file") | .state' tighten-only

H="$(new_home)"; user_file "$H" "$TIGHT"; chmod 775 "$H/.config"
run "$H" pr.create --host codex
expect "group-writable parent: tighten-only" ask '.level_sources[] | select(.source=="user_file") | .state' tighten-only

H="$(new_home)"; claude_store "$H" unattended; user_file "$H" '{"version": 1, "level": "standard", "actions": {"pr.comment": "deny"}}'
chmod 644 "$(cfgdir "$H")/permissions.json"
run "$H" pr.create --host claude
expect "tighten-only keeps a lower level against the store" allow .level standard
run "$H" branch.delete.remote --host claude --cond pr_merged_not_default_not_cross_repo=true \
  --cond unmerged_commits=false --cond tag_ref=false
expect "tighten-only level standard still caps R3" ask

H="$(new_home)"; WT="$TMP/dotfiles"; new_repo "$WT"
printf '%s\n' "$TIGHT" > "$WT/permissions.json"; chmod 600 "$WT/permissions.json"
ln -s "$WT/permissions.json" "$(cfgdir "$H")/permissions.json"; lock "$H" "$(sha "$WT/permissions.json")"
run "$H" pr.create --host codex
expect "user file realpath inside a git work tree: tighten-only" ask \
  '.level_sources[] | select(.source=="user_file") | .state' tighten-only
warned "user file in a work tree" "inside the git work tree"

H="$(new_home)"; ln -s /etc/hosts "$(cfgdir "$H")/permissions.json"
run "$H" pr.create --host codex
expect "foreign-owned (root) file that is not JSON: invalid" ask .level supervised

# ------------------------------------------------------------------ row 4
section "row 4: the project file tightens; widens only pr.merge.auto when trusted (D3, SR S-15)"

REPO="$TMP/app"; new_repo "$REPO"
project_file "$REPO" '{"version": 1, "actions": {"pr.merge.auto": "allow"}}'

H="$(new_home)"; user_file "$H" '{"version": 1, "level": "standard"}'
run "$H" pr.merge.auto --host codex --repo "$REPO" --target 42
expect "untrusted project allow is ignored" ask
warned "untrusted project allow" "allow is ignored"

H="$(new_home)"; user_file "$H" "{\"version\": 1, \"level\": \"standard\", \"trust\": [$(trust_json "$REPO")]}"
run "$H" pr.merge.auto --host codex --repo "$REPO" --target 42
expect "trusted project allow widens pr.merge.auto" allow '.level_sources[] | select(.source=="project_file") | .trusted' true
run "$H" pr.merge.auto --host codex --repo "$REPO" --target you/app#42
expect "trusted, target owner/repo#n" allow
run "$H" pr.merge.auto --host codex --repo "$REPO" --target https://github.com/you/app/pull/42
expect "trusted, target PR URL" allow
run "$H" pr.merge.auto --host codex --repo "$REPO" --target other/app#7
expect "trusted, but the target is another repo" ask
warned "target is another repo" "is not the trusted remote"
run "$H" pr.merge.auto --host codex --repo "$REPO"
expect "trusted, but no target" ask
GH_REPO=evil/app run "$H" pr.merge.auto --host codex --repo "$REPO" --target 42
expect "trusted, but GH_REPO points the PR number elsewhere" ask
run "$H" pr.merge.auto --host codex --repo "$REPO" --target 42 --headless
expect "trusted allow holds headless" allow
run "$H" pr.merge.auto --host codex --repo "$REPO" --target 42 --objective nope
expect "missing objective contributes nothing" allow
warned "missing objective" "has no readable objective.json"

LINKED="$TMP/app-linked"
git -C "$REPO" add -A >/dev/null 2>&1 && git -C "$REPO" commit -qm "project file" >/dev/null 2>&1
git -C "$REPO" worktree add -q "$LINKED" -b linked >/dev/null 2>&1
run "$H" pr.merge.auto --host codex --repo "$LINKED" --target 42
expect "trust is shared by a linked worktree (repo realpath)" allow

user_file "$H" "{\"version\": 1, \"level\": \"standard\", \"trust\": [$(trust_json "$REPO")]}" badlock
run "$H" pr.merge.auto --host codex --repo "$REPO" --target 42
expect "trusted, but the user file lock mismatches" ask

H="$(new_home)"; user_file "$H" "{\"version\": 1, \"level\": \"standard\", \"trust\": [$(trust_json "$REPO" github.com/you/other)]}"
run "$H" pr.merge.auto --host codex --repo "$REPO" --target 42
expect "trust entry remote is not the origin" ask

H="$(new_home)"; user_file "$H" "{\"version\": 1, \"level\": \"standard\", \"trust\": [$(trust_json "$REPO")]}"
project_file "$REPO" '{"version": 1, "actions": {"pr.merge.auto": "allow"}, "level": "standard"}'
run "$H" pr.merge.auto --host codex --repo "$REPO" --target 42
expect "the project file changed after trust" ask
warned "project file changed" "changed since it was trusted"

REPO2="$TMP/app2"; new_repo "$REPO2"
H="$(new_home)"; user_file "$H" '{"version": 1, "level": "standard", "actions": {"pr.create": "allow"}}'
project_file "$REPO2" '{"version": 1, "level": "supervised"}'
run "$H" pr.create --host codex --repo "$REPO2"
expect "project level tightens a user allow" ask .level supervised
project_file "$REPO2" '{"version": 1, "actions": {"pr.create": "deny"}}'
run "$H" pr.create --host codex --repo "$REPO2"
expect "project deny" deny .deny_wins_from 'project.actions[pr.create]'
project_file "$REPO2" '{"version": 1, "skills": {"pr-dev": "supervised"}}'
H="$(new_home)"; user_file "$H" '{"version": 1, "level": "standard"}'
run "$H" pr.create --host codex --repo "$REPO2" --skill pr-dev
expect "project skills tightens one skill" ask
run "$H" pr.create --host codex --repo "$REPO2" --skill plan-dev
expect "project skills leaves other skills" allow
project_file "$REPO2" '{"version": 1, "level": "unattended", "skills": {"pr-dev": "unattended"}}'
run "$H" pr.close --host codex --repo "$REPO2" --skill pr-dev --cond own_pr_or_closes_ref_of_merged_pr=true
expect "project level cannot widen" ask .level standard
project_file "$REPO2" '{"version": 1, "actions": {"release.create": "allow"}}'
run "$H" pr.create --host codex --repo "$REPO2"
expect "invalid project file (R4 allow): supervised" ask .level supervised
warned "invalid project file" "project file"

H="$(new_home)"; user_file "$H" '{"version": 1, "level": "unattended", "actions": {"pr.merge.auto": "allow"}}'
project_file "$REPO2" '{"version": 1, "level": "standard"}'
run "$H" pr.merge.auto --host codex --repo "$REPO2" --target 42
expect "project standard keeps a user pr.merge.auto allow (D2 row)" allow
project_file "$REPO2" '{"version": 1, "level": "supervised"}'
run "$H" pr.merge.auto --host codex --repo "$REPO2" --target 42
expect "project supervised clamps the user pr.merge.auto allow" ask

section "row 4 legacy: .dev-files/policy.json is tighten-only"

REPO3="$TMP/app3"; new_repo "$REPO3"; mkdir -p "$REPO3/.dev-files"
H="$(new_home)"; user_file "$H" '{"version": 1, "actions": {"pr.merge.auto": "allow"}}'
printf '{"delivery": {"auto_merge": false}}\n' > "$REPO3/.dev-files/policy.json"
run "$H" pr.merge.auto --host codex --repo "$REPO3" --target 42
expect "policy.json auto_merge false denies" deny
H="$(new_home)"; user_file "$H" '{"version": 1, "level": "standard"}'
printf '{"delivery": {"auto_merge": true}}\n' > "$REPO3/.dev-files/policy.json"
run "$H" pr.merge.auto --host codex --repo "$REPO3" --target 42
expect "policy.json auto_merge true grants nothing" ask
warned "policy.json true" "grants nothing"

# ------------------------------------------------------------------ rows 3, 2, 1
section "row 3: objective delivery.auto_merge; row 2: TAMIRS_AUTO_MERGE; row 1: no ticket read"

REPO4="$TMP/app4"; new_repo "$REPO4"; mkdir -p "$REPO4/.dev-files/objectives/obj1"
H="$(new_home)"; user_file "$H" '{"version": 1, "actions": {"pr.merge.auto": "allow"}}'
printf '{"delivery": {"auto_merge": false}}\n' > "$REPO4/.dev-files/objectives/obj1/objective.json"
run "$H" pr.merge.auto --host codex --repo "$REPO4" --objective obj1
expect "objective auto_merge false denies" deny
printf '{"delivery": {"auto_merge": true}}\n' > "$REPO4/.dev-files/objectives/obj1/objective.json"
H="$(new_home)"; user_file "$H" '{"version": 1, "level": "standard"}'
run "$H" pr.merge.auto --host codex --repo "$REPO4" --objective obj1
expect "objective auto_merge true grants nothing" ask
warned "objective true" "grants nothing"
OBJR="$TMP/objroot"; mkdir -p "$OBJR/obj2"; printf '{"delivery": {"auto_merge": false}}\n' > "$OBJR/obj2/objective.json"
H="$(new_home)"; user_file "$H" '{"version": 1, "actions": {"pr.merge.auto": "allow"}}'
OBJECTIVES_ROOT="$OBJR" run "$H" pr.merge.auto --host codex --repo "$REPO4" --objective obj2
expect "objective under OBJECTIVES_ROOT denies" deny

TAMIRS_AUTO_MERGE=never run "$H" pr.merge.auto --host codex --target 42
expect "TAMIRS_AUTO_MERGE=never denies" deny .deny_wins_from "env TAMIRS_AUTO_MERGE=never (D4 row 2)"
H="$(new_home)"; user_file "$H" '{"version": 1, "level": "standard"}'
TAMIRS_AUTO_MERGE=always run "$H" pr.merge.auto --host codex --target 42
expect "TAMIRS_AUTO_MERGE=always grants nothing" ask
warned "TAMIRS_AUTO_MERGE=always" "/plugin-config pr.merge.auto allow"

H="$(new_home)"; mkdir -p "$H/.local/state/tamirs-superpowers/tickets"; chmod -R 700 "$H/.local"
printf '{"skill": "pr-dev", "level": "unattended"}\n' > "$H/.local/state/tamirs-superpowers/tickets/t.json"
run "$H" pr.create --host claude --skill pr-dev
expect "a ticket-shaped file raises nothing (row 1 is not read)" ask .level supervised

# ------------------------------------------------------------------ row 0
section "row 0: invariants, context raises, R4 never automatic"

H="$(new_home)"; user_file "$H" '{"version": 1, "level": "unattended", "actions": {"branch.delete.local": "allow"}}'
run "$H" git.push.default --host codex
expect "protected default branch not established false: deny" deny .deny_wins_from \
  "safety invariant safety#5: protected_default_branch not established false"
run "$H" git.push.default --host codex --cond protected_default_branch=false
expect "unprotected default branch: never automatic" ask
run "$H" work.discard --host codex
expect "work.discard over unknown uncommitted changes: deny" deny
run "$H" pr.merge.admin --host codex --cond required_check_failing_or_pending=false
expect "pr.merge.admin with checks green: R4 ask" ask .r 4
run "$H" pr.merge.admin --host codex
expect "pr.merge.admin with checks unknown: deny" deny
run "$H" git.push.branch --host codex --cond default_branch=false --cond tag_ref=false
expect "git.push.branch, conditions established" allow .effective_action git.push.branch
run "$H" git.push.branch --host codex --cond default_branch=true --cond tag_ref=false --cond protected_default_branch=false
expect "git.push.branch to the default branch becomes git.push.default" ask .effective_action git.push.default
run "$H" git.push.branch --host codex
expect "git.push.branch, nothing established: strictest of every id it may become" deny
run "$H" branch.delete.local --host codex --cond unmerged_no_remote_copy=false
expect "branch.delete.local, merged" allow .r 1
run "$H" branch.delete.local --host codex
expect "branch.delete.local raised to R3: the user allow does not carry" ask .r 3 '.raised_by[0].to' R3

# ------------------------------------------------------------------ headless, unknown, alias
section "headless ask -> deny; unknown ids; aliases (D1, D2)"

H="$(new_home)"
run "$H" pr.create --host claude --skill pr-dev --headless
expect "headless R2 ask -> deny" deny .headless_ask_to_deny true '.setting_that_would_allow.durable[0]' "/plugin-config standard" \
  '.setting_that_would_allow.once' "--perms=standard" .allow_with.once "--perms=standard"
run "$H" pr.create --host opencode --headless
expect "headless on a host with no channel" deny '.setting_that_would_allow.once' null
run "$H" repo.create --host claude --headless
expect "headless R4" deny .headless_ask_to_deny true
judge "headless R4: no setting allows it" yes "$(has "$(jf .setting_that_would_allow.note)" "no setting allows it automatically")"
run "$H" repo.read --host claude --headless
expect "headless allow stays allow" allow .headless_ask_to_deny false .setting_that_would_allow null

H="$(new_home)"; user_file "$H" '{"version": 1, "level": "unattended"}'
run "$H" made.up.action --host codex
expect "unknown id: UNCLASSIFIED R4, never allow" ask .r 4 .unclassified true
warned "unknown id" "UNCLASSIFIED"
run "$H" made.up.action --host codex --headless
expect "unknown id headless" deny
run "$H" pr.auto_merge.enable --host codex --cond pinned_check_or_review_and_no_protected_paths=true
expect "alias folds into the canonical id" allow .action pr.merge.auto .requested pr.auto_merge.enable

# ------------------------------------------------------------------ call stamp
section "call stamp (D8): no stamp from the guard means supervised"

H="$(new_home)"; user_file "$H" '{"version": 1, "level": "standard", "actions": {"pr.comment": "allow"}}'
run "$H" pr.create --host codex --call stamp0001
expect "missing stamp" ask .level supervised
run "$H" pr.comment --host codex --call stamp0001
expect "missing stamp clamps a user allow too" ask
mkdir -p "$H/.local/state/tamirs-superpowers/seen"; chmod 700 "$H/.local" "$H/.local/state" \
  "$H/.local/state/tamirs-superpowers" "$H/.local/state/tamirs-superpowers/seen"
: > "$H/.local/state/tamirs-superpowers/seen/stamp0002"
run "$H" pr.create --host codex --call stamp0002
expect "stamp present" allow .level standard
judge "stamp is consumed" no "$(exists "$H/.local/state/tamirs-superpowers/seen/stamp0002")"
run "$H" pr.create --host codex --call stamp0002
expect "a consumed stamp does not count twice" ask

# ------------------------------------------------------------------ output modes, usage errors
section "--level, --explain, usage errors"

H="$(new_home)"; user_file "$H" '{"version": 1, "level": "standard", "skills": {"pr-dev": "unattended"}}'
run "$H" --level --host codex --skill pr-dev
judge "--level: exit" 0 "$RC"
judge "--level: level" unattended "$(jf .level)"
judge "--level: source" 'user.skills[pr-dev]' "$(jf .level_source)"
run "$H" pr.create --host codex --explain
judge "--explain: exit" 0 "$RC"
judge "--explain: names the verdict" yes "$(has "$OUT" "verdict: allow")"
judge "--explain: carries the trace" yes "$(has "$OUT" "trace view user_file")"
run "$H" pr.create --host codex --explain --json
judge "--explain --json: trace array" true "$(jf '.trace | length > 0')"
run "$H" --action pr.create --host codex
judge "--action form" allow "$(jf .verdict)"

run "$H" pr.create --host bogus
judge "usage: bad --host exits 2" 2 "$RC"
judge "usage: bad --host denies" deny "$(jf .verdict)"
run "$H" pr.create --cond no_such_condition=true
judge "usage: unknown --cond exits 2" 2 "$RC"
judge "usage: unknown --cond denies" deny "$(jf .verdict)"
run "$H" --host codex
judge "usage: no action exits 2" 2 "$RC"
run "$H" 'pr create' --host codex
judge "usage: malformed id denies" deny "$(jf .verdict)"
OUT="$(bash "$RESOLVE" --help)"; RC=$?
judge "--help exits 0" 0 "$RC"
judge "--help prints the usage" yes "$(has "$OUT" "resolve-permission.sh <action-id> [options]")"

# ------------------------------------------------------------------ engine failure modes
section "failure is a deny with exit 3 (D4, SR S-12)"

# tree <name> — a copy of the resolver, its library, catalog and schema.
tree() {
  local t="$TMP/tree-$1"
  mkdir -p "$t/scripts/lib" "$t/core/permissions" "$t/core/schemas"
  cp "$ROOT/scripts/resolve-permission.sh" "$t/scripts/"
  cp "$ROOT/scripts/lib/permission-common.sh" "$t/scripts/lib/"
  cp "$ROOT/core/permissions/actions.json" "$t/core/permissions/"
  cp "$ROOT/core/schemas/permissions.schema.json" "$t/core/schemas/"
  printf '%s' "$t"
}

# run_tree <tree> <args...>
run_tree() {
  local t="$1"
  shift
  OUT="$(cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$H" bash "$t/scripts/resolve-permission.sh" "$@" 2>/dev/null)"
  RC=$?
}

H="$(new_home)"
T="$(tree ok)"; run_tree "$T" repo.read --host codex
judge "a copied tree resolves" allow "$(jf .verdict)"
T="$(tree nocat)"; rm "$T/core/permissions/actions.json"; run_tree "$T" repo.read --host codex
judge "missing catalog: exit 3" 3 "$RC"
judge "missing catalog: deny" deny "$(jf .verdict)"
judge "missing catalog: says so" yes "$(has "$(jf .error)" "action catalog unreadable")"
T="$(tree badcat)"; printf '{"actions": ' > "$T/core/permissions/actions.json"; run_tree "$T" repo.read --host codex
judge "corrupt catalog: exit 3" 3 "$RC"
judge "corrupt catalog: deny" deny "$(jf .verdict)"
T="$(tree shapecat)"; printf '{"actions": 5}\n' > "$T/core/permissions/actions.json"; run_tree "$T" repo.read --host codex
judge "malformed catalog: exit 3" 3 "$RC"
judge "malformed catalog: deny" deny "$(jf .verdict)"
T="$(tree noschema)"; rm "$T/core/schemas/permissions.schema.json"; run_tree "$T" repo.read --host codex
judge "missing schema: exit 3" 3 "$RC"
judge "missing schema: deny" deny "$(jf .verdict)"
T="$(tree nolib)"; rm "$T/scripts/lib/permission-common.sh"; run_tree "$T" repo.read --host codex
judge "missing library: exit 3" 3 "$RC"
judge "missing library: deny" deny "$(jf .verdict)"
OUT="$(cd "$NOWHERE" && PATH=/nonexistent /bin/bash "$RESOLVE" repo.read --host codex 2>/dev/null)"; RC=$?
judge "no python3: exit 3" 3 "$RC"
judge "no python3: deny" deny "$(jf .verdict)"
judge "no python3: names the action" repo.read "$(jf .action)"
judge "no python3: says so" yes "$(has "$(jf .error)" "python3 is not available")"

# ------------------------------------------------------------------ library functions
section "library functions"

# Linux caps ONE argv string at 128 KiB (MAX_ARG_STRLEN) and the engine is passed
# to python3 -c as one: past that, every call there would fail, i.e. deny.
ENGINE_BYTES="$(bash -c '. "$1"; printf "%s" "${#_PERM_ENGINE}"' lib "$ROOT/scripts/lib/permission-common.sh")"
judge "the engine fits one Linux argv string (< 120 KiB, now $ENGINE_BYTES bytes)" yes \
  "$([ "${ENGINE_BYTES:-0}" -gt 1000 ] && [ "$ENGINE_BYTES" -lt 122880 ] && echo yes || echo no)"

H="$(new_home)"
LIB="$ROOT/scripts/lib/permission-common.sh"
lib() { (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$H" bash -c '. "$1"; shift; "$@"' lib "$LIB" "$@" 2>/dev/null); }

judge "perm_passwd_home honours the guarded test root" "$(canon "$H")" "$(lib perm_passwd_home)"
judge "perm_user_config_dir" "$(canon "$H")/.config/tamirs-superpowers" "$(lib perm_user_config_dir)"
judge "perm_state_dir" "$(canon "$H")/.local/state/tamirs-superpowers" "$(lib perm_state_dir)"
judge "perm_dirs home_source" test-root "$(lib perm_dirs | jq -r .home_source)"
REAL_HOME="$(python3 -c 'import os,pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
judge "perm_passwd_home without python3 falls back to getent/dscl" "$REAL_HOME" \
  "$(cd "$NOWHERE" && PATH=/nonexistent /bin/bash -c '. "$1"; perm_passwd_home' lib "$LIB" 2>/dev/null)"
judge "perm_normalize_remote scp form" github.com/you/app "$(lib perm_normalize_remote git@github.com:You/App.git)"
judge "perm_normalize_remote https with userinfo" github.com/you/app "$(lib perm_normalize_remote https://x:tok@github.com/you/app)"
judge "perm_normalize_remote ssh default port" github.com/you/app "$(lib perm_normalize_remote ssh://git@github.com:22/you/app.git)"
judge "perm_normalize_remote keeps another port" ghe.example.com:8443/o/r "$(lib perm_normalize_remote https://ghe.example.com:8443/o/r)"
judge "perm_repo_key of a linked worktree is the main tree" "$(canon "$REPO")" "$(lib perm_repo_key "$LINKED")"
judge "perm_map_verdict R2 standard" allow "$(lib perm_map_verdict pr.create standard)"
judge "perm_map_verdict R3 unattended, precondition unknown" ask "$(lib perm_map_verdict pr.close unattended)"
judge "perm_map_verdict R3 unattended, precondition holds" allow \
  "$(lib perm_map_verdict pr.close unattended --cond own_pr_or_closes_ref_of_merged_pr=true)"
judge "perm_map_verdict R4" ask "$(lib perm_map_verdict repo.delete unattended)"
judge "perm_map_verdict unknown id" ask "$(lib perm_map_verdict made.up unattended)"
F="$TMP/hashme"; printf 'abc' > "$F"
judge "perm_sha256" ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad "$(lib perm_sha256 "$F")"
judge "perm_check_file: a root-owned file is unsafe" yes \
  "$(has "$(lib perm_check_file /etc/hosts private | jq -r '.problems | join(" ")')" "owned by uid 0")"
user_file "$H" '{"version": 1, "level": "standard"}'
judge "perm_check_file: the user file is ok" ok "$(lib perm_check_file "$(cfgdir "$H")/permissions.json" private | jq -r .state)"
judge "perm_lock_check: match" match "$(lib perm_lock_check)"
judge "perm_load_user_file: verified" verified "$(lib perm_load_user_file | jq -r .state)"
claude_store "$H" standard
judge "perm_option_store_level claude" standard "$(lib perm_option_store_level claude | jq -r .level)"
judge "perm_load_project_file" valid "$(lib perm_load_project_file "$REPO" | jq -r .state)"
judge "perm_trust_check: untrusted" false "$(lib perm_trust_check "$REPO" 42 | jq -r .trusted)"
OUT="$(cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$H" bash -c '. "$1"; set -e; out="$(perm_resolve pr.create --host codex)"; printf "%s" "$out"' lib "$LIB" 2>/dev/null)"
judge "perm_resolve under the caller's set -e" allow "$(jf .verdict)"

# ------------------------------------------------------------------ the test-override guard
section "the test override is refused outside its guard"

H="$(new_home)"
chmod 755 "$H"
judge "override refused: mode 0755" passwd "$(lib perm_dirs | jq -r .home_source)"
judge "override refused: says why" yes "$(has "$(lib perm_dirs | jq -r '.warnings | join(" ")')" "not 0700")"
chmod 700 "$H"
GH_HOME="$TMP/repo-home"; new_repo "$GH_HOME"; chmod 700 "$GH_HOME"
judge "override refused: inside a git work tree" passwd \
  "$( (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$GH_HOME" bash -c '. "$1"; perm_dirs' lib "$LIB" 2>/dev/null) | jq -r .home_source)"
judge "override refused: relative path" passwd \
  "$( (cd "$TMP" && TAMIRS_PERMISSION_TEST_ROOT="${H##*/}" bash -c '. "$1"; perm_dirs' lib "$LIB" 2>/dev/null) | jq -r .home_source)"

# The decisive rule: not under this suite. Orphan a process (its parent exits at
# once, so it is reparented away from this script), give it the same variable,
# and it must get the real passwd home.
D="$TMP/detached"; mkdir -p "$D"
user_file "$H" '{"version": 1, "level": "unattended"}'
( exec /bin/sh -c 'sleep 1; cd "$4"; TAMIRS_PERMISSION_TEST_ROOT="$1" bash "$2" --level --host codex > "$3/out" 2>/dev/null; echo $? > "$3/rc"' \
    sh "$H" "$RESOLVE" "$D" "$NOWHERE" >/dev/null 2>&1 & )
n=0
while [ ! -s "$D/rc" ] && [ "$n" -lt 150 ]; do sleep 0.1; n=$((n + 1)); done
if [ -s "$D/rc" ]; then
  OUT="$(cat "$D/out")"
  judge "orphaned process: exit 0" 0 "$(cat "$D/rc")"
  judge "orphaned process: real passwd home" passwd "$(jf .home_source)"
  judge "orphaned process: warns why" yes "$(has "$(jf '.warnings | join(" ")')" "not running under")"
  judge "orphaned process: reads the real user file path" "$REAL_HOME/.config/tamirs-superpowers/permissions.json" \
    "$(jf '.level_sources[] | select(.source=="user_file") | .path')"
else
  bad "orphaned process" "no answer within 15s"
fi

harness_summary
