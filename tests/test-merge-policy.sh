#!/usr/bin/env bash
# test-merge-policy.sh — resolve-merge-policy.sh decides auto-merge through the
# permission resolver, and only through it (ADR 004 item 3, D4).
#
# WHAT IS HELD
#   auto_merge is "enable" only when scripts/resolve-permission.sh answers allow
#   for pr.merge.auto AND the repository allows auto-merge. Everything else is
#   "skip": the default, TAMIRS_AUTO_MERGE=always (grants nothing), =never, an
#   objective's delivery.auto_merge true or false, a repository that disallows
#   auto-merge, and every way the resolver can fail (missing, non-zero exit,
#   unparseable output) -- fail closed.
#
# TWO RESOLVERS
#   Part A runs a COPY of resolve-merge-policy.sh inside a temp plugin tree whose
#   scripts/resolve-permission.sh is a stub. The script finds the resolver from
#   its own location, never from the environment, so the copy is the only way
#   to put an answer of our choosing in front of it -- and it is what proves the
#   mapping (allow/ask/deny/error -> enable/skip) and the call shape.
#
#   Part B runs the real script against the real resolver. The resolver reads
#   the passwd home, and its test override TAMIRS_PERMISSION_TEST_ROOT is
#   honoured under this suite (an allowlisted permission suite,
#   scripts/lib/permission-common.sh header), so Part B points it at an empty
#   0700 temp home and stops unless the resolver reports home_source test-root:
#   the "no configuration => skip" default is then asserted unconditionally, and
#   a user file in that home shows the real resolver's allow reaching "enable".
#
# Hermetic: temp fixtures, tests/lib/fake-gh.sh for every gh call, no network.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
# shellcheck source=tests/lib/fake-gh.sh
source "$ROOT/tests/lib/fake-gh.sh"

harness_require git jq python3

TMP="$(harness_tmpdir)"
export HOME="$TMP/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
unset GH_TOKEN GITHUB_TOKEN GH_REPO TAMIRS_AUTO_MERGE OBJECTIVES_ROOT \
  TS_PERMISSION_LEVEL CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL TAMIRS_PERMISSION_TEST_ROOT 2>/dev/null || true

REAL_MP="$ROOT/skills/dev-workflow/pr-dev/scripts/resolve-merge-policy.sh"
# Part B's passwd home: empty, 0700, outside every work tree (the resolver's test-root rules).
PH="$TMP/passwd-home"
mkdir -m 700 "$PH"

# --- fixtures -----------------------------------------------------------------
FX="$TMP/fx"
mkdir -p "$FX/_defaults" "$FX/default" "$FX/disallow" "$FX/unreadable" "$FX/pinned"
cat > "$FX/_defaults/repo-view.json" <<'J'
{"squashMergeAllowed":true,"mergeCommitAllowed":false,"rebaseMergeAllowed":false,"deleteBranchOnMerge":true,"viewerPermission":"WRITE","nameWithOwner":"acme/widget"}
J
printf '{"allow_auto_merge":true}\n'  > "$FX/_defaults/repo.json"
printf '{"allow_auto_merge":false}\n' > "$FX/disallow/repo.json"
printf '{"name":"widget"}\n'          > "$FX/unreadable/repo.json"
# Classic protection with one check pinned to an app (app_id > 0).
cat > "$FX/pinned/protection.json" <<'J'
{"required_status_checks":{"strict":false,"contexts":["ci"],"checks":[{"context":"ci","app_id":15368}]},"enforce_admins":{"enabled":true}}
J

BIN="$TMP/bin"
fake_gh_install "$BIN" "$TMP/gh.log" "$FX/default"
FAKE_GH_SHIM="$ROOT/tests/lib/fake-gh.sh"
# fake-gh.sh serves `gh api` and `gh repo`; `gh pr view` and the effective-rules
# endpoint are answered here, from env, and everything else goes to the shim.
# PRV_BASE unset = the PR's base cannot be read (the base-branch block is
# skipped); PRV_FILES unset = the file list cannot be read.
cat > "$BIN/gh" <<SHIM
#!/usr/bin/env bash
if [ "\${1:-}" = pr ] && [ "\${2:-}" = view ]; then
  case "\$*" in
    *baseRefName*)  [ -n "\${PRV_BASE:-}" ] && { printf '%s\n' "\$PRV_BASE"; exit 0; }; exit 1 ;;
    *headRefName*)  printf 'feature/x\n'; exit 0 ;;
    *changedFiles*) [ -n "\${PRV_FILES:-}" ] && { printf '%s\n' "\$PRV_FILES"; exit 0; }; exit 1 ;;
  esac
  exit 1
fi
case "\$*" in
  "api repos/acme/widget/rules/branches/"*) printf '%s\n' "\${PRV_RULES:-[]}"; exit 0 ;;
esac
exec bash "$FAKE_GH_SHIM" "\$@"
SHIM
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

scenario() { fake_gh_use_fixtures "$FX/$1"; }

# --- Part A plugin tree with a stub resolver ------------------------------------
PLUG="$TMP/plugin"
mkdir -p "$PLUG/skills/dev-workflow/pr-dev/scripts" "$PLUG/scripts"
cp "$REAL_MP" "$PLUG/skills/dev-workflow/pr-dev/scripts/resolve-merge-policy.sh"
STUB_MP="$PLUG/skills/dev-workflow/pr-dev/scripts/resolve-merge-policy.sh"
STUB_LOG="$TMP/stub.log"
export STUB_LOG
# The stub records its argv and TAMIRS_AUTO_MERGE, then answers per STUB_MODE:
# allow | ask | deny (exit 0), exit3 (a deny with exit 3), allow-exit1 (claims
# allow but exits 1), garbage (not JSON), noverdict ({}).
cat > "$PLUG/scripts/resolve-permission.sh" <<'STUB'
#!/usr/bin/env bash
{ printf 'ARGV %s\n' "$*"; printf 'ENV TAMIRS_AUTO_MERGE=%s\n' "${TAMIRS_AUTO_MERGE:-}"; } >> "$STUB_LOG"
mode="${STUB_MODE:-ask}"
case "$mode" in
  garbage)   printf 'not json at all\n'; exit 0 ;;
  noverdict) printf '{}\n'; exit 0 ;;
esac
rc=0; verdict="$mode"
case "$mode" in
  exit3) verdict=deny; rc=3 ;;
  allow-exit1) verdict=allow; rc=1 ;;
esac
STUB_VERDICT="$verdict" python3 -I -S -c '
import json, os
w = os.environ.get("STUB_WARN")
print(json.dumps({"action": "pr.merge.auto", "verdict": os.environ["STUB_VERDICT"],
  "decision": os.environ["STUB_VERDICT"],
  "decided_by": os.environ.get("STUB_BY", "stub rule"),
  "reason": os.environ.get("STUB_REASON", "stub reason"),
  "allow_with": {"once": None, "durable": ["/plugin-config pr.merge.auto allow"], "note": None},
  "warnings": [w] if w else []}))'
exit "$rc"
STUB
chmod +x "$PLUG/scripts/resolve-permission.sh"

REPO="$TMP/repo"
harness_new_repo "$REPO"

# mpa <env...> -- [args...] : run the Part A copy in $REPO; JSON on stdout.
mpa() {
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  [ "$#" -gt 0 ] || set -- 42
  : > "$STUB_LOG"
  ( cd "$REPO" && env ${envs[@]+"${envs[@]}"} bash "$STUB_MP" "$@" 2>/dev/null )
}
# mpb <env...> -- [args...] : the real script and the real resolver.
mpb() {
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  [ "$#" -gt 0 ] || set -- 42
  ( cd "$REPO" && env ${envs[@]+"${envs[@]}"} bash "$REAL_MP" "$@" 2>/dev/null )
}
f() { jq -r "$1" 2>/dev/null; }            # f <jq filter> on stdin
stub_argv() { sed -n 's/^ARGV //p' "$STUB_LOG"; }

# =============================================================================
section "A. the mapping: resolver verdict x repository capability"
# =============================================================================
scenario default

out="$(mpa STUB_MODE=ask)"
judge "default (resolver asks) => skip" skip "$(f .auto_merge <<<"$out")"
judge "  ... verdict is reported as ask" ask "$(f .auto_merge_verdict <<<"$out")"
judge "  ... the source says auto-merge is off unless configured" yes \
  "$(has "$(f .auto_merge_source <<<"$out")" "off unless configured")"
judge "  ... and names the setting that would turn it on" "/plugin-config pr.merge.auto allow" \
  "$(f .auto_merge_allow_with <<<"$out")"

out="$(mpa STUB_MODE=allow 'STUB_BY=user file actions["pr.merge.auto"] allow')"
judge "user config allow on pr.merge.auto + repo allows => enable" enable "$(f .auto_merge <<<"$out")"
judge "  ... the source quotes the resolver's decided_by (quotes survive as JSON)" yes \
  "$(has "$(f .auto_merge_source <<<"$out")" 'actions["pr.merge.auto"] allow')"

scenario disallow
out="$(mpa STUB_MODE=allow)"
judge "allow, but the repository disallows auto-merge => skip" skip "$(f .auto_merge <<<"$out")"
judge "  ... and says the repository overrode it" yes \
  "$(has "$(f .auto_merge_source <<<"$out")" "repository does not allow auto-merge")"
judge "  ... auto_merge_supported is false" false "$(f .auto_merge_supported <<<"$out")"

scenario unreadable
out="$(mpa STUB_MODE=allow)"
judge "allow, but the repository capability is unreadable => skip" skip "$(f .auto_merge <<<"$out")"
judge "  ... and says it could not be read" yes \
  "$(has "$(f .auto_merge_source <<<"$out")" "could not be read")"
scenario default

out="$(mpa STUB_MODE=deny STUB_BY="objective o1 delivery.auto_merge false")"
judge "resolver denies => skip" skip "$(f .auto_merge <<<"$out")"
judge "  ... with the deciding rule in the source" yes \
  "$(has "$(f .auto_merge_source <<<"$out")" "objective o1 delivery.auto_merge false")"

# =============================================================================
section "A. the legacy inputs no longer decide"
# =============================================================================
out="$(mpa TAMIRS_AUTO_MERGE=never STUB_MODE=allow)"
judge "TAMIRS_AUTO_MERGE=never => skip, even over an allow" skip "$(f .auto_merge <<<"$out")"
judge "  ... named as the explicit override" yes \
  "$(has "$(f .auto_merge_source <<<"$out")" "TAMIRS_AUTO_MERGE=never")"
judge "  ... and the resolver is never asked" 0 "$(stub_argv | grep -c . || true)"

out="$(mpa TAMIRS_AUTO_MERGE=always STUB_MODE=ask \
  "STUB_WARN=TAMIRS_AUTO_MERGE=always is ignored: run /plugin-config pr.merge.auto allow (D4 row 2)")"
judge "TAMIRS_AUTO_MERGE=always => skip (it grants nothing)" skip "$(f .auto_merge <<<"$out")"
judge "  ... the resolver's warning is surfaced" yes \
  "$(has "$(f '.warnings | join("|")' <<<"$out")" "TAMIRS_AUTO_MERGE=always is ignored")"
judge "  ... the source is the resolver, not the env var" no \
  "$(has "$(f .auto_merge_source <<<"$out")" "TAMIRS_AUTO_MERGE=always")"
judge "  ... and the env var reached the resolver (it decides, not this script)" yes \
  "$(has "$(cat "$STUB_LOG")" "TAMIRS_AUTO_MERGE=always")"

mkdir -p "$REPO/.dev-files/objectives/o1"
printf '{"delivery":{"auto_merge":true}}\n' > "$REPO/.dev-files/objectives/o1/objective.json"
out="$(mpa STUB_MODE=ask -- 42 o1)"
judge "objective delivery.auto_merge=true => skip (the resolver asked)" skip "$(f .auto_merge <<<"$out")"
judge "  ... objective_id is parsed from the second positional (was always empty)" o1 "$(f .objective_id <<<"$out")"
judge "  ... and handed to the resolver as --objective" yes "$(has "$(stub_argv)" "--objective o1")"
out="$(mpa STUB_MODE=ask -- --repo acme/widget 42 o1)"
judge "  ... also after --repo" yes "$(has "$(stub_argv)" "--objective o1")"

# =============================================================================
section "A. the call shape"
# =============================================================================
out="$(mpa STUB_MODE=ask -- --host claude 42)"
judge "action is pr.merge.auto" yes "$(has "$(stub_argv)" "--action pr.merge.auto")"
judge "target is owner/repo#N, not a bare number" yes "$(has "$(stub_argv)" "--target acme/widget#42")"
judge "skill is pr-dev" yes "$(has "$(stub_argv)" "--skill pr-dev")"
judge "--host is passed through" yes "$(has "$(stub_argv)" "--host claude")"
judge "--repo names the checkout" yes "$(has "$(stub_argv)" "--repo $(canon "$REPO")")"
out="$(mpa STUB_MODE=ask)"
judge "no --host given => none passed (a store may then only lower)" no1 \
  "$(has "$(stub_argv)" "--host")$(stub_argv | grep -c -- '--action pr.merge.auto')"
judge "the script performs no GitHub write" 0 "$(gh_mutations)"

# =============================================================================
section "A. the resolver failing is a skip (fail closed)"
# =============================================================================
out="$(mpa STUB_MODE=exit3)"
judge "resolver exits 3 => skip" skip "$(f .auto_merge <<<"$out")"
judge "  ... verdict error" error "$(f .auto_merge_verdict <<<"$out")"
judge "  ... source says fail closed" yes "$(has "$(f .auto_merge_source <<<"$out")" "fail closed")"

out="$(mpa STUB_MODE=allow-exit1)"
judge "resolver prints allow but exits 1 => skip" skip "$(f .auto_merge <<<"$out")"

out="$(mpa STUB_MODE=garbage)"
judge "resolver prints non-JSON => skip" skip "$(f .auto_merge <<<"$out")"
judge "  ... with a warning" yes "$(has "$(f '.warnings | join("|")' <<<"$out")" "no parseable verdict")"

out="$(mpa STUB_MODE=noverdict)"
judge "resolver prints JSON with no verdict => skip" skip "$(f .auto_merge <<<"$out")"

mv "$PLUG/scripts/resolve-permission.sh" "$PLUG/scripts/resolve-permission.sh.off"
out="$(mpa STUB_MODE=allow)"
judge "resolver missing => skip" skip "$(f .auto_merge <<<"$out")"
KEYS="admin_bypass_available auto_merge auto_merge_allow_with auto_merge_source auto_merge_supported auto_merge_verdict base_branch delete_branch delete_branch_source merge_method merge_method_source merge_queue objective_id pr protection_source required_checks requires_review strict_branch_update warnings"
judge "  ... and the output is still valid JSON with every field" "$KEYS" "$(f 'keys | join(" ")' <<<"$out")"
mv "$PLUG/scripts/resolve-permission.sh.off" "$PLUG/scripts/resolve-permission.sh"

# POSITIVE CONTROL for the three above: the same tree, a healthy allow, enables.
out="$(mpa STUB_MODE=allow)"
judge "control: the healthy stub still enables" enable "$(f .auto_merge <<<"$out")"

# =============================================================================
section "A. the unattended precondition is established from GitHub, not assumed"
# =============================================================================
scenario pinned
CLEAN='{"files":[{"path":"src/app.js"}],"changedFiles":1}'
WF='{"files":[{"path":"src/app.js"},{"path":".github/workflows/ci.yml"}],"changedFiles":2}'
CO='{"files":[{"path":".github/CODEOWNERS"}],"changedFiles":1}'
TRUNC='{"files":[{"path":"src/app.js"}],"changedFiles":150}'
COND="pinned_check_or_review_and_no_protected_paths"

out="$(mpa PRV_BASE=main "PRV_FILES=$CLEAN")"
judge "pinned check + clean diff => --cond $COND=true" yes "$(has "$(stub_argv)" "--cond $COND=true")"
out="$(mpa PRV_BASE=main "PRV_FILES=$WF")"
judge "a workflow file in the diff => =false" yes "$(has "$(stub_argv)" "--cond $COND=false")"
out="$(mpa PRV_BASE=main "PRV_FILES=$CO")"
judge "CODEOWNERS in the diff => =false" yes "$(has "$(stub_argv)" "--cond $COND=false")"
out="$(mpa PRV_BASE=main "PRV_FILES=$TRUNC")"
judge "a file list shorter than changedFiles => no --cond (unknown)" no1 \
  "$(has "$(stub_argv)" "--cond")$(stub_argv | grep -c -- '--action pr.merge.auto')"
out="$(mpa PRV_BASE=main)"
judge "an unreadable file list => no --cond" no1 \
  "$(has "$(stub_argv)" "--cond")$(stub_argv | grep -c -- '--action pr.merge.auto')"
scenario default
out="$(mpa PRV_BASE=main "PRV_FILES=$CLEAN")"
judge "no pinned check, no review, rules answered => =false" yes "$(has "$(stub_argv)" "--cond $COND=false")"
out="$(mpa PRV_BASE=main "PRV_FILES=$CLEAN" 'PRV_RULES=[{"type":"pull_request","ruleset_id":1,"parameters":{"required_approving_review_count":1}}]')"
judge "a required review (ruleset) + clean diff => =true" yes "$(has "$(stub_argv)" "--cond $COND=true")"
judge "  ... and the protection fields are unchanged by this (requires_review)" true "$(f .requires_review <<<"$out")"

# =============================================================================
section "B. the real resolver"
# =============================================================================
export TAMIRS_PERMISSION_TEST_ROOT="$PH"
hs="$(cd "$REPO" && bash "$ROOT/scripts/resolve-permission.sh" pr.merge.auto --json 2>/dev/null | jq -r '.home_source // empty')"
if [ "$hs" != test-root ]; then
  bad "the real resolver reads the temp passwd home under this suite" "home_source=$hs"
  printf 'FATAL: Part B would judge the real permission file\n'
  harness_summary
fi
ok "the real resolver reads the temp passwd home under this suite"
scenario default
rm -rf "$REPO/.dev-files"

out="$(mpb TAMIRS_AUTO_MERGE=never)"
judge "never => skip" skip "$(f .auto_merge <<<"$out")"

mkdir -p "$REPO/.dev-files/objectives/o1"
printf '{"delivery":{"auto_merge":false}}\n' > "$REPO/.dev-files/objectives/o1/objective.json"
out="$(mpb -- 42 o1)"
judge "objective delivery.auto_merge=false => skip" skip "$(f .auto_merge <<<"$out")"
judge "  ... denied, and the objective is named as the source" yes \
  "$(has "$(f .auto_merge_source <<<"$out")" "deny (objective")"

printf '{"delivery":{"auto_merge":true}}\n' > "$REPO/.dev-files/objectives/o1/objective.json"
out="$(mpb -- 42 o1)"
judge "objective delivery.auto_merge=true is reported as granting nothing" yes \
  "$(has "$(f '.warnings | join("|")' <<<"$out")" "grants nothing")"
judge "  ... and is not the source of the decision" no \
  "$(has "$(f .auto_merge_source <<<"$out")" "objective")"
judge "  ... (control: there is a source)" yes "$(has "$(f .auto_merge_source <<<"$out")" "resolve-permission pr.merge.auto")"
rm -rf "$REPO/.dev-files/objectives"

mkdir -p "$REPO/.dev-files"
printf '{"delivery":{"auto_merge":false}}\n' > "$REPO/.dev-files/policy.json"
out="$(mpb)"
judge "legacy .dev-files/policy.json false => skip (tighten-only)" skip "$(f .auto_merge <<<"$out")"
judge "  ... and the file is named" yes "$(has "$(f .auto_merge_source <<<"$out")" "policy.json delivery.auto_merge false")"
rm -f "$REPO/.dev-files/policy.json"

out="$(mpb TAMIRS_AUTO_MERGE=always)"
judge "always => the resolver's warning names the durable route" yes \
  "$(has "$(f '.warnings | join("|")' <<<"$out")" "/plugin-config pr.merge.auto allow")"
judge "  ... and always is not the source of the decision" no \
  "$(has "$(f .auto_merge_source <<<"$out")" "TAMIRS_AUTO_MERGE=always")"

# The default, and always-grants-nothing: the temp passwd home holds no configuration.
out="$(mpb)"
judge "no configuration anywhere => skip (auto-merge is off unless configured)" skip "$(f .auto_merge <<<"$out")"
judge "  ... the resolver asked" ask "$(f .auto_merge_verdict <<<"$out")"
out="$(mpb TAMIRS_AUTO_MERGE=always)"
judge "always, with no configuration => skip" skip "$(f .auto_merge <<<"$out")"

# A locked user file that allows pr.merge.auto (D2 standard row) reaches "enable" through the real resolver.
CFG="$PH/.config/tamirs-superpowers"
mkdir -p "$CFG"; chmod 700 "$PH/.config" "$CFG"
printf '{"version": 1, "level": "standard", "actions": {"pr.merge.auto": "allow"}}\n' > "$CFG/permissions.json"
chmod 600 "$CFG/permissions.json"
printf '{"sha256": "%s", "by": "plugin-config", "at": "2026-11-04T00:00:00Z"}\n' \
  "$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$CFG/permissions.json")" > "$CFG/permissions.lock"
chmod 600 "$CFG/permissions.lock"
out="$(mpb)"
judge "a user-file allow at standard => enable (real resolver, repository allows)" enable "$(f .auto_merge <<<"$out")"
judge "  ... the resolver allowed" allow "$(f .auto_merge_verdict <<<"$out")"
out="$(mpb TAMIRS_AUTO_MERGE=never)"
judge "  ... and never still tightens it to skip" skip "$(f .auto_merge <<<"$out")"
rm -rf "$PH/.config"

# The real script must find the real resolver from its own location: the
# source is the resolver's, never "not found".
out="$(mpb)"
judge "the in-tree script finds scripts/resolve-permission.sh" yes \
  "$(has "$(f .auto_merge_source <<<"$out")" "resolve-permission pr.merge.auto:")"

harness_summary
