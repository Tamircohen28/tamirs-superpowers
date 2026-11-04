#!/usr/bin/env bash
# test-resolve-permission.sh — the permission resolver (ADR 004 D2, D3, D4, D10;
# implementation item 2): scripts/resolve-permission.sh and
# scripts/lib/permission-common.sh.
#
# WHAT THIS SUITE HOLDS
#   A table: one case per D4 precedence row (7 default, 6 option store + user
#   level, 5 user keys, 4 project file and trust, 3 objective, 2 TAMIRS_AUTO_MERGE,
#   1 --perms= tickets, one case per D5 rule, 0 invariants), the D9 host floor
#   (a cached, deadline-bound probe; below => supervised, unknown => a warning) and
#   per failure mode
#   (missing or corrupt catalog and schema, no python3, a missing library, a
#   corrupt user file, wrong
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
section "row 3: objective delivery.auto_merge; row 2: TAMIRS_AUTO_MERGE"

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


# ------------------------------------------------------------------ row 1
section "row 1: --perms= tickets (D4 row 1, D5; SR S-05, S-09, S-11)"

# ticket <home> <kind> <level> [<json overrides>] [<ttl s>] [<created offset s>] — a ticket as the
# writers render it (scripts/plugin-config.sh header): session s-1, agent main, host claude, skill
# pr-dev, target {arg 42, repo github.com/you/app}, created now, 15 min (raise) or 24 h (lower).
# 0600 in a 0700 dir; prints its id.
ticket() {
  local h="$1" d over="${4:-}"
  [ -n "$over" ] || over='{}'
  d="$h/.local/state/tamirs-superpowers/tickets"
  mkdir -p "$d"
  chmod 700 "$h/.local" "$h/.local/state" "$h/.local/state/tamirs-superpowers" "$d"
  python3 - "$d" "$2" "$3" "$over" "${5:-}" "${6:-0}" <<'PY'
import json, os, sys, time
d, kind, level, over, ttl, off = sys.argv[1:7]
t = int(time.time()) + int(off)
ttl = int(ttl) if ttl else (900 if kind == "raise" else 86400)
tid = os.urandom(16).hex()
u = lambda x: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(x))
tk = {"version": 1, "kind": kind, "id": tid, "skill": "pr-dev", "level": level,
      "target": {"arg": "42", "repo": "github.com/you/app"}, "session_id": "s-1", "agent": "main",
      "host": "claude", "created": u(t), "expires": u(t + ttl), "source": "plugin-config confirm (test)"}
tk.update(json.loads(over))
p = os.path.join(d, tid + ".json")
with open(p, "w") as f:
    f.write(json.dumps(tk, indent=2, sort_keys=True) + "\n")
os.chmod(p, 0o600)
print(tid)
PY
}
tdir() { printf '%s/.local/state/tamirs-superpowers/tickets' "$1"; }
S1=(--host claude --session s-1 --agent main --skill pr-dev)
TREPO="$TMP/app-t"; new_repo "$TREPO"

H="$(new_home)"; TK="$(ticket "$H" raise standard)"
run "$H" pr.comment "${S1[@]}" --target you/app#42
expect "a raise ticket on its skill and target: R2 allowed" allow .ticket "$TK" .level supervised
judge "  ... decided_by names the ticket" yes "$(has "$(jf .decided_by)" "ticket $TK")"
judge "  ... level_sources lists it" "$TK" "$(jf '[.level_sources[] | select(.source=="tickets")][0].raise[0]')"
run "$H" pr.comment --host claude --skill pr-dev --target you/app#42
expect "no --session: tickets are not read" ask .ticket null
run "$H" pr.comment --host claude --session s-2 --agent main --skill pr-dev --target you/app#42
expect "another session: not this call's ticket" ask
run "$H" pr.comment --host claude --session s-1 --skill pr-dev --target you/app#42
expect "--session without --agent is the main thread (the partial S-11 disposition)" allow .agent main
run "$H" pr.comment --host claude --session s-1 --agent sub-1 --skill pr-dev --target you/app#42
expect "an observed subagent id: the main-thread ticket does not reach it (S-11)" ask
warned "subagent" "bound to agent main"
run "$H" pr.comment --host claude --session s-1 --agent main --skill start-dev --target you/app#42
expect "another skill: one skill per ticket" ask
run "$H" pr.comment --host claude --session s-1 --agent main --target you/app#42
expect "no skill on the call: no raise" ask
run "$H" pr.comment --host gemini --session s-1 --agent main --skill pr-dev --target you/app#42
expect "a ticket bound to claude, a call on gemini" ask
warned "host" "bound to host claude"

# the target: actions.json target_kinds equality, an unresolvable field never matches
run "$H" pr.comment "${S1[@]}" --target you/app#43
expect "pr kind: another PR number" ask
run "$H" pr.comment "${S1[@]}" --target other/app#42
expect "pr kind: the same number in another repo" ask
run "$H" pr.comment "${S1[@]}"
expect "pr kind: no --target, nothing to match" ask
run "$H" pr.comment "${S1[@]}" --target https://github.com/you/app/pull/42
expect "pr kind: the PR URL" allow
run "$H" pr.comment "${S1[@]}" --target github.com/you/app#42
expect "pr kind: host/owner/repo#n" allow
run "$H" pr.comment "${S1[@]}" --repo "$TREPO" --target 42
expect "pr kind: a bare number in a checkout whose origin is you/app" allow
GH_REPO=other/app run "$H" pr.comment "${S1[@]}" --repo "$TREPO" --target 42
expect "pr kind: a bare number while GH_REPO names another repo (gh acts there)" ask
run "$H" pr.comment "${S1[@]}" --repo "$NOWHERE" --target 42
expect "pr kind: a bare number with no checkout origin is unresolvable" ask
run "$H" issue.comment "${S1[@]}" --target you/app#42
expect "issue kind: the ticket's number in its repo" allow
run "$H" issue.create "${S1[@]}" --target you/app
expect "repo kind: the ticket's repository" allow
run "$H" issue.create "${S1[@]}" --repo "$TREPO" --target .
expect "repo kind: '.' in the ticket's checkout" allow
run "$H" issue.create "${S1[@]}" --target other/app
expect "repo kind: another repository" ask
run "$H" git.push.branch "${S1[@]}" --target you/app --cond default_branch=false --cond tag_ref=false
expect "branch kind: a ticket names no branch, so it never matches" ask
H2="$(new_home)"; ticket "$H2" raise standard '{"target": {"arg": "add-login", "repo": "github.com/you/app"}}' >/dev/null
run "$H2" issue.create "${S1[@]}" --target you/app
expect "an argument that names no target leaves the repository (repo kind matches)" allow
run "$H2" pr.comment "${S1[@]}" --target you/app#42
expect "  ... and no number (pr kind does not)" ask
H2="$(new_home)"; ticket "$H2" raise standard '{"target": {"arg": "42", "repo": null}}' >/dev/null
run "$H2" pr.comment "${S1[@]}" --target you/app#42
expect "a ticket with no resolvable repository matches nothing" ask

# R2/R3 only; R3 needs the unattended ceiling and its precondition; never R4 or UNCLASSIFIED
run "$H" pr.close "${S1[@]}" --target you/app#42 --cond own_pr_or_closes_ref_of_merged_pr=true
expect "R3 under a standard ticket: the standard ceiling asks" ask
H3="$(new_home)"; TK3="$(ticket "$H3" raise unattended)"
run "$H3" pr.close "${S1[@]}" --target you/app#42 --cond own_pr_or_closes_ref_of_merged_pr=true
expect "R3 under an unattended ticket, precondition holds" allow .ticket "$TK3"
run "$H3" pr.close "${S1[@]}" --target you/app#42
expect "R3 under an unattended ticket, precondition unknown" ask
run "$H3" pr.merge "${S1[@]}" --target you/app#42
expect "R3 never_auto: no ticket makes it automatic" ask .never_auto true
run "$H3" pr.merge.admin "${S1[@]}" --target you/app#42 --cond required_check_failing_or_pending=false
expect "R4: no ticket satisfies it (S-05)" ask .r 4 .ticket null
run "$H3" repo.create "${S1[@]}" --target you/app
expect "R4 repo kind: still the host prompt" ask .r 4
run "$H3" made.up.action "${S1[@]}" --target you/app#42
expect "UNCLASSIFIED: never" ask .unclassified true
run "$H3" pr.thread.resolve "${S1[@]}" --target you/app#42
expect "a step context raised (another's thread unknown: R3) gets no ticket" ask .r 3
run "$H" pr.thread.resolve "${S1[@]}" --target you/app#42 --cond others_thread=false
expect "  ... the same step, not raised, gets it" allow .r 2

# any deny is final; a ticket outranks rows 2-7's asks, not their denies
H4="$(new_home)"; user_file "$H4" '{"version": 1, "actions": {"pr.comment": "deny"}}'; ticket "$H4" raise unattended >/dev/null
run "$H4" pr.comment "${S1[@]}" --target you/app#42
expect "a user deny stands over a ticket" deny
H4="$(new_home)"; user_file "$H4" '{"version": 1, "actions": {"pr.comment": "ask"}}'; ticket "$H4" raise standard >/dev/null
run "$H4" pr.comment "${S1[@]}" --target you/app#42
expect "a user ask (row 5) is lifted by the confirmed ticket (row 1)" allow
TREPO2="$TMP/app-t2"; new_repo "$TREPO2"; project_file "$TREPO2" '{"version": 1, "actions": {"pr.comment": "deny"}}'
run "$H4" pr.comment "${S1[@]}" --repo "$TREPO2" --target 42
expect "a project deny stands over a ticket" deny
TAMIRS_AUTO_MERGE=never run "$H3" pr.merge.auto "${S1[@]}" --target you/app#42 \
  --cond pinned_check_or_review_and_no_protected_paths=true
expect "TAMIRS_AUTO_MERGE=never stands over a ticket" deny
run "$H3" pr.merge.auto "${S1[@]}" --target you/app#42 --cond pinned_check_or_review_and_no_protected_paths=true
expect "pr.merge.auto under an unattended ticket, precondition holds" allow
run "$H" pr.merge.auto "${S1[@]}" --target you/app#42 --cond pinned_check_or_review_and_no_protected_paths=true
expect "pr.merge.auto under a standard ticket: standard keeps it off" ask
run "$H" pr.comment "${S1[@]}" --target you/app#42 --headless
expect "headless: the ticket's allow needs no human" allow
run "$H" pr.comment "${S1[@]}" --target you/app#43 --headless
expect "headless without a matching ticket: ask -> deny" deny
run "$H" pr.comment "${S1[@]}" --target you/app#42 --call nostamp001
expect "the call stamp (D8) is not lifted by a ticket" ask

# the raise ticket's own checks: expiry, lifetime, shape, file and dir safety
H5="$(new_home)"; ticket "$H5" raise standard '{}' 900 -1000 >/dev/null
run "$H5" pr.comment "${S1[@]}" --target you/app#42
expect "an expired raise ticket" ask
warned "expired" "expired at"
H5="$(new_home)"; ticket "$H5" raise standard '{}' 3600 >/dev/null
run "$H5" pr.comment "${S1[@]}" --target you/app#42
expect "a raise ticket that lives an hour" ask
warned "an hour" "at most 15 minutes"
H5="$(new_home)"; ticket "$H5" raise standard '{}' 900 3600 >/dev/null
run "$H5" pr.comment "${S1[@]}" --target you/app#42
expect "a raise ticket created in the future" ask
warned "future" "at most 15 minutes"
H5="$(new_home)"; ticket "$H5" raise standard '{"skill": null}' >/dev/null
run "$H5" pr.comment "${S1[@]}" --target you/app#42
expect "a raise ticket with no skill" ask
warned "no skill" "names no skill"
H5="$(new_home)"; TK5="$(ticket "$H5" raise standard)"; chmod 644 "$(tdir "$H5")/$TK5.json"
run "$H5" pr.comment "${S1[@]}" --target you/app#42
expect "a group/world-readable raise ticket" ask
warned "0644 raise" "only a lowering would count"
H5="$(new_home)"; ticket "$H5" raise standard >/dev/null; chmod 755 "$(tdir "$H5")"
run "$H5" pr.comment "${S1[@]}" --target you/app#42
expect "a raise ticket in a 0755 tickets dir" ask
warned "0755 dir" "is unsafe"
H5="$(new_home)"; mkdir -p "$TMP/elsewhere-$$"; chmod 700 "$TMP/elsewhere-$$"
TK5="$(ticket "$H5" raise standard)"; mv "$(tdir "$H5")/$TK5.json" "$TMP/elsewhere-$$/"
rmdir "$(tdir "$H5")"; ln -s "$TMP/elsewhere-$$" "$(tdir "$H5")"
run "$H5" pr.comment "${S1[@]}" --target you/app#42
expect "a raise ticket behind a symlinked tickets dir" ask
warned "symlinked dir" "symbolic link"
H5="$(new_home)"; TK5="$(ticket "$H5" raise standard)"; mv "$(tdir "$H5")/$TK5.json" "$(tdir "$H5")/0123456789abcdef0123456789abcdef.json"
run "$H5" pr.comment "${S1[@]}" --target you/app#42
expect "a ticket whose id is not its file name" ask
warned "renamed" "its id is not its file name"
H5="$(new_home)"; ticket "$H5" raise standard >/dev/null
printf 'not json\n' > "$(tdir "$H5")/ffffffffffffffffffffffffffffffff.json"; chmod 600 "$(tdir "$H5")/ffffffffffffffffffffffffffffffff.json"
printf '{"skill": "pr-dev", "level": "unattended"}\n' > "$(tdir "$H5")/t.json"; chmod 600 "$(tdir "$H5")/t.json"
run "$H5" pr.comment "${S1[@]}" --target you/app#42
expect "corrupt and misnamed files are ignored; the valid ticket beside them still applies" allow
warned "corrupt" "corrupt"
warned "misnamed" "not a ticket file name"
H5="$(new_home)"; mkdir -p "$(tdir "$H5")"; chmod -R 700 "$H5/.local"
printf '{"skill": "pr-dev", "level": "unattended"}\n' > "$(tdir "$H5")/t.json"
run "$H5" pr.comment "${S1[@]}" --target you/app#42
expect "a ticket-shaped file the writers never made raises nothing, and is no error" ask .level supervised

# lowering tickets: no provenance, every agent and target of the session, beat a raise (SR S-09)
H6="$(new_home)"; user_file "$H6" '{"version": 1, "level": "standard", "actions": {"pr.review_request": "allow"}}'
TL="$(ticket "$H6" lower supervised '{"skill": null, "target": {"arg": null, "repo": null}}')"
run "$H6" pr.create --host claude --session s-1 --agent main
expect "a session-wide lowering: R2 asks again" ask .level supervised .ticket "$TL"
judge "  ... level_source names it" yes "$(has "$(jf .level_source)" "lowering ticket $TL")"
judge "  ... the setting note says why" yes "$(has "$(jf .setting_that_would_allow.note)" "lowering --perms= ticket")"
run "$H6" pr.create --host claude --session s-1 --agent sub-1 --target other/app#9
expect "  ... from another agent and on another target too" ask
run "$H6" pr.review_request --host claude --session s-1 --agent main --target you/app#42
expect "  ... and over a user allow (row 1 above row 5)" ask
run "$H6" pr.create --host claude --session s-2 --agent main
expect "  ... not in another session" allow
run "$H6" --level --host claude --session s-1
judge "--level with --session reports the lowering" supervised "$(jf .level)"
judge "  ... and lists it" "$TL null supervised s-1" "$(jf '.lowering_tickets[0] | "\(.id) \(.skill) \(.level) \(.session_id)"')"
OUT="$(cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$H6" bash "$RESOLVE" --level --host claude --session s-1 --explain 2>/dev/null)"
judge "  ... in text too" yes "$(has "$OUT" "lowering ticket $TL: the whole session at supervised, session s-1")"
run "$H6" --level --host claude --session s-2
judge "  ... another session lists none" 0 "$(jf '.lowering_tickets | length')"
H6="$(new_home)"; user_file "$H6" '{"version": 1, "level": "standard"}'; ticket "$H6" lower supervised >/dev/null
run "$H6" pr.create --host claude --session s-1 --agent main --skill pr-dev
expect "a lowering for pr-dev applies under pr-dev" ask
run "$H6" pr.create --host claude --session s-1 --agent main --skill start-dev
expect "  ... not under another skill" allow
run "$H6" pr.create --host claude --session s-1 --agent main
expect "  ... nor with no skill" allow
ticket "$H6" raise unattended >/dev/null
run "$H6" pr.comment "${S1[@]}" --target you/app#42
expect "a lowering beats a raise for the same skill" ask
H6="$(new_home)"; user_file "$H6" '{"version": 1, "level": "standard"}'
TL="$(ticket "$H6" lower supervised '{"skill": null}')"; chmod 644 "$(tdir "$H6")/$TL.json"
run "$H6" pr.create --host claude --session s-1 --agent main
expect "an unsafe lowering ticket still lowers (tighten-only, D10.2)" ask
H6="$(new_home)"; user_file "$H6" '{"version": 1, "level": "standard"}'; ticket "$H6" lower supervised '{"skill": null}' 86400 -90000 >/dev/null
run "$H6" pr.create --host claude --session s-1 --agent main
expect "an expired lowering ticket no longer lowers" allow
H6="$(new_home)"; user_file "$H6" '{"version": 1, "level": "unattended", "actions": {"pr.merge.auto": "allow"}}'
ticket "$H6" lower standard '{"skill": null}' >/dev/null
run "$H6" pr.merge.auto --host claude --session s-1 --agent main --target you/app#42
expect "a lowering to standard keeps the configured pr.merge.auto allow (D2 row)" allow
ticket "$H6" lower supervised '{"skill": null}' >/dev/null
run "$H6" pr.merge.auto --host claude --session s-1 --agent main --target you/app#42
expect "  ... a lowering to supervised does not" ask

run "$H" pr.comment --host claude --agent main --skill pr-dev
judge "usage: --agent without --session exits 2" 2 "$RC"
judge "usage: ... and denies" deny "$(jf .verdict)"
run "$H" pr.comment --host claude --session "$(printf 'a\tb')" --skill pr-dev
judge "usage: a control character in --session exits 2" 2 "$RC"
run "$H" pr.comment "${S1[@]}" --target you/app#42 --explain
judge "--explain traces the ticket" yes "$(has "$OUT" "ticket $TK")"

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

# ------------------------------------------------------------------ D9 host floor
section "D9: a host below permissions_min runs every level above supervised as supervised"

HV="$TMP/hv-bin"; mkdir -p "$HV"
fake_host() { # fake_host <bin> <--version line> [sleep s] — a host CLI that logs each probe
  { printf '#!/bin/sh\n'; printf 'echo %s >> "%s/probes"\n' "$1" "$TMP"
    [ -n "${3:-}" ] && printf 'sleep %s\n' "$3"
    printf 'echo "%s"\n' "$2"; } > "$HV/$1"
  chmod +x "$HV/$1"
}
nprobes() { [ -f "$TMP/probes" ] && grep -c "^$1\$" "$TMP/probes" || echo 0; }
hvrun() { # hvrun <home> <override> <resolver args...>
  local h="$1" v="$2"; shift 2
  OUT="$(cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$h" TAMIRS_PERMISSION_TEST_HOST_VERSION="$v" PATH="$HV:$PATH" bash "$RESOLVE" "$@" 2>/dev/null)"
  RC=$?
}
floor() { jf '[.level_sources[] | select(.source == "host_floor")][0] | "\(.state) \(.version) \(.floor)"'; }

H="$(new_home)"; user_file "$H" '{"version": 1, "level": "standard"}'
run "$H" pr.create --host claude
expect "under the test root with no override the floor is not probed" allow
judge "  ... and is not reported" "" "$(jf '[.level_sources[] | select(.source == "host_floor")] | .[0].state // ""')"
for row in "claude|2.1.316 (Claude Code)|2.1.316|2.1.317" "codex|codex-cli 0.165.9|0.165.9|0.166.0" \
           "cursor|2026.10.21-abc|2026.10.21|2026.10.22" "gemini|0.65.0|0.65.0|0.66.0" "opencode|opencode v2.2.4|2.2.4|2.2.5"; do
  IFS='|' read -r host line have fv <<<"$row"
  hvrun "$H" "$line" pr.create --host "$host"
  expect "$host '$line' (< $fv): R2 at standard asks" ask .level supervised
  judge "  ... reported below its floor" "below $have $fv" "$(floor)"
  judge "  ... decided_by names D9" yes "$(has "$(jf .decided_by)" "host floor (D9)")"
done
hvrun "$H" "2.1.317 (Claude Code)" pr.create --host claude
expect "claude at the floor: standard holds" allow .level standard
judge "  ... reported as meeting it" "meets 2.1.317 2.1.317" "$(floor)"
hvrun "$H" "2.1.300" pr.create --host claude
judge "  ... the setting note says no level setting lifts it" yes "$(has "$(jf .setting_that_would_allow.note)" "every level above supervised runs as supervised")"
warned "below the floor" "below the permission-levels floor 2.1.317"
hvrun "$H" "not a version" pr.create --host claude
expect "an unreadable version: no clamp" allow .level standard
warned "unreadable version" "is not checked (ADR 004 D9: a warning only)"
hvrun "$H" "2.1.300" pr.create
expect "no --host: no host to check, no clamp" allow
hvrun "$H" "2.1.300" --level --host claude
judge "--level clamps too" "supervised yes" "$(jf .level) $(has "$(jf .level_source)" "host floor (D9)")"
hvrun "$H" "2.1.300" pr.merge --host claude
expect "an answer supervised already gives (R3 asks) is unchanged" ask
hvrun "$H" "2.1.300" git.commit --host claude
expect "R1 stays allowed below the floor (supervised allows it)" allow
H2="$(new_home)"; user_file "$H2" '{"version": 1, "level": "standard", "actions": {"pr.create": "allow"}}'
hvrun "$H2" "2.1.300" pr.create --host claude
expect "a user action allow is clamped as well (the host's own gates are unproven below the floor)" ask
H2="$(new_home)"; user_file "$H2" '{"version": 1, "level": "standard", "actions": {"pr.create": "deny"}}'
hvrun "$H2" "2.1.300" pr.create --host claude
expect "a deny stays a deny" deny

# the real probe: once per session, cached, deadline-bound; never at supervised
: > "$TMP/probes"
fake_host claude "2.1.300 (Claude Code)"
hvrun "$H" probe pr.create --host claude --session hv-1 --agent main
expect "probe: the CLI on PATH below the floor" ask
judge "  ... probed once" 1 "$(nprobes claude)"
hvrun "$H" probe pr.create --host claude --session hv-1 --agent main
judge "  ... the same session reuses the cache" 1 "$(nprobes claude)"
CF="$(ls "$H/.local/state/tamirs-superpowers/hostver/"claude.*.json 2>/dev/null | head -1)"
judge "  ... a 0600 cache in a 0700 dir" "600 700" "$(python3 -c 'import os,stat,sys; print("%o %o" % (stat.S_IMODE(os.stat(sys.argv[1]).st_mode), stat.S_IMODE(os.stat(os.path.dirname(sys.argv[1])).st_mode)))' "$CF" 2>/dev/null)"
hvrun "$H" probe pr.create --host claude --session hv-2 --agent main
judge "  ... a new session probes again" 2 "$(nprobes claude)"
sleep 1; fake_host claude "2.1.318 (Claude Code)"; printf '# padding\n' >> "$HV/claude"
hvrun "$H" probe pr.create --host claude --session hv-1 --agent main
expect "  ... a replaced binary (an upgrade) is probed again, cache or not" allow
judge "  ... (probe count)" 3 "$(nprobes claude)"
python3 -c 'import json, sys; p = sys.argv[1]; d = json.load(open(p)); d["at"] -= 3600; open(p, "w").write(json.dumps(d))' "$CF"
hvrun "$H" probe pr.create --host claude --session hv-1 --agent main
judge "  ... a cache older than its 10-minute TTL is probed again" 4 "$(nprobes claude)"
H3="$(new_home)"
hvrun "$H3" probe pr.create --host claude --session hv-1 --agent main
expect "at supervised (no user file) the answer is supervised's" ask
judge "  ... so nothing is probed" 4 "$(nprobes claude)"
fake_host codex "codex-cli 0.170.0" 9
t0="$(python3 -c 'import time; print(time.time())')"
hvrun "$H" probe pr.create --host codex --session hv-1 --agent main
t1="$(python3 -c 'import time; print(time.time())')"
expect "a CLI that hangs on --version: unknown, no clamp" allow
warned "probe deadline" "timed out after 3 s"
judge "  ... killed at the 3 s deadline" yes "$(python3 -c "print('yes' if $t1 - $t0 < 6 else 'no')")"
t0="$(python3 -c 'import time; print(time.time())')"
hvrun "$H" probe pr.create --host codex --session hv-1 --agent main
t1="$(python3 -c 'import time; print(time.time())')"
judge "  ... and the unknown is cached, so the next call does not wait again" yes "$(python3 -c "print('yes' if $t1 - $t0 < 2 else 'no')")"
OUT="$(cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$H" TAMIRS_PERMISSION_TEST_HOST_VERSION=probe PATH="$TMP/no-such-dir:/usr/bin:/bin" bash "$RESOLVE" pr.create --host opencode 2>/dev/null)"; RC=$?
expect "no host CLI on PATH: unknown, no clamp" allow
warned "no binary" "opencode is not on PATH"

# ------------------------------------------------------------------ headless, unknown, alias
section "headless ask -> deny; unknown ids; aliases (D1, D2)"

H="$(new_home)"
run "$H" pr.create --host claude --skill pr-dev --headless
expect "headless R2 ask -> deny" deny .headless_ask_to_deny true '.setting_that_would_allow.durable[0]' "/plugin-config standard" \
  '.setting_that_would_allow.durable[1]' "/plugin-config pr-dev standard" \
  '.setting_that_would_allow.once' null .allow_with.once null
judge "  ... no --perms= raise on Claude Code: it sends no prompt origin (M3)" yes \
  "$(has "$(jf .setting_that_would_allow.note)" "it does not send prompt origin")"
run "$H" pr.create --host gemini --headless
expect "  ... nor on Gemini CLI (its prompt hook only lowers)" deny '.setting_that_would_allow.once' null
judge "  ... which the note says" yes "$(has "$(jf .setting_that_would_allow.note)" "only lowers")"
run "$H" pr.create --headless
expect "  ... nor with no --host" deny '.setting_that_would_allow.once' null
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

# A permission suite NAMED in an ancestor's arguments is not a suite being run (think
# `claude -p "run tests/test-permission-guard.sh"`): an orphan whose own argument list
# carries the path of every allowlisted suite still gets the real passwd home.
D2="$TMP/detached-named"; mkdir -p "$D2"
( exec /bin/sh -c 'sleep 1; cd "$4"; TAMIRS_PERMISSION_TEST_ROOT="$1" bash "$2" --level --host codex > "$3/out" 2>/dev/null; echo $? > "$3/rc"' \
    sh "$H" "$RESOLVE" "$D2" "$NOWHERE" "$ROOT/tests/test-resolve-permission.sh" "$ROOT/tests/test-permission-guard.sh" \
    "$ROOT/tests/test-setup-permission-level.sh" "$ROOT/tests/test-merge-policy.sh" >/dev/null 2>&1 & )
n=0
while [ ! -s "$D2/rc" ] && [ "$n" -lt 150 ]; do sleep 0.1; n=$((n + 1)); done
if [ -s "$D2/rc" ]; then
  OUT="$(cat "$D2/out")"
  judge "a suite named, not run, by an ancestor: real passwd home" passwd "$(jf .home_source)"
  judge "  ... and the warning lists the suites that count" yes "$(has "$(jf '.warnings | join(" ")')" "test-merge-policy.sh")"
else
  bad "orphaned process naming the suites" "no answer within 15s"
fi

harness_summary
