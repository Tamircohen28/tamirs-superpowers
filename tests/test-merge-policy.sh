#!/usr/bin/env bash
# test-merge-policy.sh — resolve-merge-policy.sh's auto-merge decision follows
# its documented precedence, highest first:
#
#   1. TAMIRS_AUTO_MERGE=always|never          (explicit user/session override)
#   2. the objective's delivery.auto_merge     (second positional argument)
#   3. .dev-files/policy.json delivery.auto_merge
#   4. repository capability: a repository that disallows auto-merge wins over
#      any request to enable it
#   5. default: enable when the repository allows auto-merge
#
# Merge method, head-branch delete, rulesets and --repo are held by
# tests/test-shape.sh; this suite holds only the auto-merge decision.
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
unset GH_TOKEN GITHUB_TOKEN GH_REPO TAMIRS_AUTO_MERGE OBJECTIVES_ROOT 2>/dev/null || true

MP="$ROOT/skills/dev-workflow/pr-dev/scripts/resolve-merge-policy.sh"

# --- fixtures -----------------------------------------------------------------
FX="$TMP/fx"
mkdir -p "$FX/_defaults" "$FX/default" "$FX/disallow" "$FX/unreadable"
cat > "$FX/_defaults/repo-view.json" <<'J'
{"squashMergeAllowed":true,"mergeCommitAllowed":false,"rebaseMergeAllowed":false,"deleteBranchOnMerge":true,"viewerPermission":"WRITE","nameWithOwner":"acme/widget"}
J
printf '{"allow_auto_merge":true}\n'  > "$FX/_defaults/repo.json"
printf '{"allow_auto_merge":false}\n' > "$FX/disallow/repo.json"
printf '{"name":"widget"}\n'          > "$FX/unreadable/repo.json"

BIN="$TMP/bin"
fake_gh_install "$BIN" "$TMP/gh.log" "$FX/default"
FAKE_GH_SHIM="$ROOT/tests/lib/fake-gh.sh"
# `gh pr view` cannot read the PR's base, so the protection block is skipped;
# everything else goes to the shim.
cat > "$BIN/gh" <<SHIM
#!/usr/bin/env bash
if [ "\${1:-}" = pr ] && [ "\${2:-}" = view ]; then exit 1; fi
exec bash "$FAKE_GH_SHIM" "\$@"
SHIM
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

scenario() { fake_gh_use_fixtures "$FX/$1"; }

REPO="$TMP/repo"
harness_new_repo "$REPO"

# mp <env...> -- [args...] : run the script in $REPO; JSON on stdout.
mp() {
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  [ "$#" -gt 0 ] || set -- 42
  ( cd "$REPO" && env ${envs[@]+"${envs[@]}"} bash "$MP" "$@" 2>/dev/null )
}
f() { jq -r "$1" 2>/dev/null; }            # f <jq filter> on stdin
set_policy()    { mkdir -p "$REPO/.dev-files"; printf '{"delivery":{"auto_merge":%s}}\n' "$1" > "$REPO/.dev-files/policy.json"; }
set_objective() { mkdir -p "$REPO/.dev-files/objectives/o1"; printf '{"delivery":{"auto_merge":%s}}\n' "$1" > "$REPO/.dev-files/objectives/o1/objective.json"; }
reset_files()   { rm -rf "$REPO/.dev-files"; }

# =============================================================================
section "5/4. the default and the repository capability"
# =============================================================================
scenario default
out="$(mp)"
judge "nothing configured, repository allows auto-merge => enable" enable "$(f .auto_merge <<<"$out")"
judge "  ... the source names the default" yes \
  "$(has "$(f .auto_merge_source <<<"$out")" "default: enable when the repository allows auto-merge")"
judge "  ... auto_merge_supported is true" true "$(f .auto_merge_supported <<<"$out")"
judge "  ... the output is one valid JSON object" object "$(f type <<<"$out")"

scenario disallow
out="$(mp)"
judge "repository disallows auto-merge => skip" skip "$(f .auto_merge <<<"$out")"
judge "  ... and says so" yes "$(has "$(f .auto_merge_source <<<"$out")" "repository does not allow auto-merge")"
judge "  ... auto_merge_supported is false" false "$(f .auto_merge_supported <<<"$out")"

scenario unreadable
out="$(mp)"
judge "repository capability unreadable => auto_merge_supported null" null "$(f .auto_merge_supported <<<"$out")"
scenario default

# =============================================================================
section "3. .dev-files/policy.json"
# =============================================================================
reset_files; set_policy false
out="$(mp)"
judge "policy.json auto_merge=false => skip" skip "$(f .auto_merge <<<"$out")"
judge "  ... named as the source" yes "$(has "$(f .auto_merge_source <<<"$out")" ".dev-files/policy.json delivery.auto_merge=false")"

reset_files; set_policy true
scenario disallow
out="$(mp)"
judge "policy.json auto_merge=true on a repository that disallows it => skip" skip "$(f .auto_merge <<<"$out")"
judge "  ... the source says the repository overrode it" yes \
  "$(has "$(f .auto_merge_source <<<"$out")" "overridden: repository does not allow auto-merge")"
scenario default

# =============================================================================
section "2. the objective"
# =============================================================================
reset_files; set_objective false
out="$(mp -- 42 o1)"
judge "objective delivery.auto_merge=false => skip" skip "$(f .auto_merge <<<"$out")"
judge "  ... objective_id is parsed from the second positional (was always empty)" o1 "$(f .objective_id <<<"$out")"
judge "  ... and the objective is named as the source" yes \
  "$(has "$(f .auto_merge_source <<<"$out")" "objective o1 delivery.auto_merge=false")"
out="$(mp -- --repo acme/widget 42 o1)"
judge "  ... also after --repo" "skip o1" "$(f '.auto_merge + " " + .objective_id' <<<"$out")"

reset_files; set_policy false; set_objective true
out="$(mp -- 42 o1)"
judge "objective true outranks policy.json false => enable" enable "$(f .auto_merge <<<"$out")"

out="$(mp)"
judge "without the objective argument, policy.json decides => skip" skip "$(f .auto_merge <<<"$out")"

# =============================================================================
section "1. TAMIRS_AUTO_MERGE"
# =============================================================================
reset_files; set_objective true
out="$(mp TAMIRS_AUTO_MERGE=never -- 42 o1)"
judge "TAMIRS_AUTO_MERGE=never outranks objective true => skip" skip "$(f .auto_merge <<<"$out")"
judge "  ... named as the explicit override" yes "$(has "$(f .auto_merge_source <<<"$out")" "TAMIRS_AUTO_MERGE=never")"

reset_files; set_objective false
out="$(mp TAMIRS_AUTO_MERGE=always -- 42 o1)"
judge "TAMIRS_AUTO_MERGE=always outranks objective false => enable" enable "$(f .auto_merge <<<"$out")"

scenario disallow
out="$(mp TAMIRS_AUTO_MERGE=always)"
judge "TAMIRS_AUTO_MERGE=always on a repository that disallows it => skip" skip "$(f .auto_merge <<<"$out")"
judge "  ... the source keeps the request and names the override" yes \
  "$(has "$(f .auto_merge_source <<<"$out")" "TAMIRS_AUTO_MERGE=always (explicit override) — overridden: repository does not allow auto-merge")"
scenario default
reset_files

harness_summary
