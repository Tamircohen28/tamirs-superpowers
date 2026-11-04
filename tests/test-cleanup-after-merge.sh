#!/usr/bin/env bash
# test-cleanup-after-merge.sh — pr-dev's cleanup-after-merge.sh deletes a PR's
# branch, worktree and remote branch only when GitHub shows it is safe, and only
# through the permission resolver (ADR 004 D1/D4, audit finding D-1).
#
# WHAT IS HELD
#   - Nothing is deleted unless the PR is MERGED, its head is neither the base
#     nor the default branch, and it is not cross-repository; an unreadable
#     answer counts as a failed check.
#   - The remote branch is kept when GitHub reports it protected (branch flag or
#     a ruleset deletion rule), when that cannot be read, and when its tip holds
#     commits the PR did not merge.
#   - branch.delete.remote goes through the resolver: allow deletes; ask with no
#     terminal, deny, a missing resolver, a failing or unreadable resolver all
#     keep it and print the setting that would allow it (exit 3).
#   - A worktree with uncommitted changes is never force-removed.
#   - A local branch with commits no remote ref or merged PR holds is kept.
#
# HOW
#   The script runs as a COPY inside a temp plugin tree whose
#   scripts/resolve-permission.sh is a stub (the script finds the resolver from
#   its own path, never from the environment). Every gh call goes to
#   tests/lib/fake-gh.sh, wrapped here for the calls it does not model (pr view,
#   the branch and rules endpoints). Real git: a bare origin and a clone per
#   scenario, all under a temp dir. No network.
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
unset GH_TOKEN GITHUB_TOKEN GH_REPO 2>/dev/null || true

# --- plugin tree with a stub resolver -------------------------------------------
PLUG="$TMP/plugin"
mkdir -p "$PLUG/skills/dev-workflow/pr-dev/scripts" "$PLUG/skills/dev-workflow/_shared/scripts" "$PLUG/scripts"
cp "$ROOT/skills/dev-workflow/pr-dev/scripts/cleanup-after-merge.sh" "$PLUG/skills/dev-workflow/pr-dev/scripts/"
cp "$ROOT/skills/dev-workflow/_shared/scripts/default-branch.sh" "$PLUG/skills/dev-workflow/_shared/scripts/"
CAM="$PLUG/skills/dev-workflow/pr-dev/scripts/cleanup-after-merge.sh"
STUB="$PLUG/scripts/resolve-permission.sh"
STUB_LOG="$TMP/stub.log"
export STUB_LOG
# STUB_MODES="action=mode,..." (default STUB_DEFAULT, else allow). Modes: allow |
# ask | deny (exit 0), exit3 (deny, exit 3), garbage (not JSON, exit 0).
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
printf 'ARGV %s\n' "$*" >> "$STUB_LOG"
action="" prev=""
for a in "$@"; do [ "$prev" = --action ] && action="$a"; prev="$a"; done
mode="${STUB_DEFAULT:-allow}"
IFS=, read -r -a pairs <<<"${STUB_MODES:-}"
for p in ${pairs[@]+"${pairs[@]}"}; do [ "${p%%=*}" = "$action" ] && mode="${p#*=}"; done
case "$mode" in
  garbage) echo "not json"; exit 0 ;;
  exit3) printf '{"verdict":"deny","reason":"resolver error"}\n'; exit 3 ;;
esac
printf '{"action":"%s","verdict":"%s","reason":"stub %s for %s","setting_that_would_allow":{"once":null,"durable":["/plugin-config %s allow"],"note":null}}\n' \
  "$action" "$mode" "$mode" "$action" "$action"
STUBEOF
chmod +x "$STUB"

# --- gh: fake-gh.sh plus the calls it does not model ------------------------------
FX="$TMP/fx"; mkdir -p "$FX/_defaults" "$FX/s"
printf '{"defaultBranchRef":{"name":"main"},"nameWithOwner":"acme/widget"}\n' > "$FX/_defaults/repo-view.json"
BIN="$TMP/bin"
fake_gh_install "$BIN" "$TMP/gh.log" "$FX/s"
GHS="$TMP/ghstate"; mkdir -p "$GHS"; export GHS
cat > "$BIN/gh" <<SHIM
#!/usr/bin/env bash
# serve <file> <jq>: a missing file or one reading ERR is a failed call.
serve() { [ -f "\$1" ] && [ "\$(cat "\$1")" != ERR ] || exit 1; if [ -n "\$2" ]; then jq -r "\$2" < "\$1"; else cat "\$1"; fi; exit 0; }
q=""; prev=""
for a in "\$@"; do case "\$prev" in --jq|-q) q="\$a" ;; esac; prev="\$a"; done
printf '%s\n' "\$*" >> "\$GHS/calls.log"
case "\$1 \${2:-}" in
  "pr view") serve "\$GHS/pr.json" "\$q" ;;
esac
case "\$*" in
  "api repos/acme/widget/branches/"*)       b="\${2#repos/acme/widget/branches/}"; serve "\$GHS/branch-\$b.json" "\$q" ;;
  "api repos/acme/widget/rules/branches/"*) b="\${2#repos/acme/widget/rules/branches/}"
     [ -f "\$GHS/rules-\$b.json" ] || { printf '[]\n' > "\$GHS/rules-\$b.json"; }
     serve "\$GHS/rules-\$b.json" "\$q" ;;
esac
exec bash "$ROOT/tests/lib/fake-gh.sh" "\$@"
SHIM
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

# --- one world per scenario: origin + clone + a pushed, "merged" feature branch ----
N=0
new_world() {
  N=$((N + 1))
  W="$TMP/w$N"; ORIGIN="$W/origin.git"; CL="$W/clone"; WT="$W/wt"
  mkdir -p "$W"
  git init -q --bare -b main "$ORIGIN"
  harness_new_repo "$CL"
  git -C "$CL" remote add origin "$ORIGIN"
  git -C "$CL" push -q origin main
  git -C "$CL" remote set-head origin main >/dev/null
  git -C "$CL" checkout -q -b feature
  git -C "$CL" commit -q --allow-empty -m "feature work"
  git -C "$CL" push -q -u origin feature 2>/dev/null
  HEAD_OID="$(git -C "$CL" rev-parse feature)"
  git -C "$CL" checkout -q main
  # The squash merge GitHub made on main.
  git -C "$CL" commit -q --allow-empty -m "feature work (#42)"
  git -C "$CL" push -q origin main
  git -C "$CL" worktree add -q "$WT" feature
  rm -f "$GHS"/*.json "$GHS/calls.log"
  pr_json MERGED feature main false
  printf '{"name":"feature","protected":false}\n' > "$GHS/branch-feature.json"
  : > "$STUB_LOG"
}
# pr_json <state> <head> <base> <cross>
pr_json() {
  printf '{"state":"%s","headRefName":"%s","headRefOid":"%s","baseRefName":"%s","isCrossRepository":%s}\n' \
    "$1" "$2" "$HEAD_OID" "$3" "$4" > "$GHS/pr.json"
}
# run [env...] — the copied script from the clone; output in OUT, exit in RC.
run() {
  RC=0
  OUT="$(cd "$CL" && env "$@" bash "$CAM" 42 2>&1)" || RC=$?
}
remote_has() { git -C "$ORIGIN" show-ref --verify --quiet "refs/heads/$1" && echo yes || echo no; }
local_has()  { git -C "$CL" show-ref --verify --quiet "refs/heads/$1" && echo yes || echo no; }
asked() { grep -c -- "--action $1" "$STUB_LOG" 2>/dev/null || true; }
out_has() { has "$OUT" "$1"; }

# =============================================================================
section "allow: a merged PR is cleaned up, through the resolver"
# =============================================================================
new_world
run
judge "exit 0" 0 "$RC"
judge "remote branch deleted" no "$(remote_has feature)"
judge "local branch deleted" no "$(local_has feature)"
judge "worktree removed" no "$(exists "$WT")"
judge "branch.delete.remote was asked once" 1 "$(asked branch.delete.remote)"
judge "  ... with the PR as owner/repo#N" yes "$(has "$(cat "$STUB_LOG")" "--target acme/widget#42")"
judge "  ... and the established precondition" yes "$(has "$(cat "$STUB_LOG")" "--cond pr_merged_not_default_not_cross_repo=true")"
judge "  ... unmerged_commits established false" yes "$(has "$(cat "$STUB_LOG")" "--cond unmerged_commits=false")"
judge "  ... headless, because no terminal is attached" yes "$(has "$(grep -- '--action branch.delete.remote' "$STUB_LOG")" "--headless")"
judge "branch.delete.local was asked" 1 "$(asked branch.delete.local)"
judge "worktree.remove was asked with discards_work=false" yes \
  "$(has "$(grep -- '--action worktree.remove' "$STUB_LOG")" "--cond discards_work=false")"

judge "  ... and no --host when none was given" no "$(has "$(cat "$STUB_LOG")" "--host")"

new_world
OUT="$(cd "$CL" && bash "$CAM" --host claude 42 2>&1)"
judge "--host claude reaches the resolver" yes "$(has "$(cat "$STUB_LOG")" "--host claude")"

# =============================================================================
section "the resolver decides branch.delete.remote"
# =============================================================================
new_world
run STUB_MODES=branch.delete.remote=ask
judge "ask, no terminal => remote branch kept" yes "$(remote_has feature)"
judge "  ... exit 3" 3 "$RC"
judge "  ... says it needs confirmation" yes "$(out_has "needs confirmation and no terminal is attached")"
judge "  ... names the setting that would allow it" yes "$(out_has "allow with: /plugin-config branch.delete.remote allow")"
judge "  ... the R1 local cleanup still ran" no "$(local_has feature)"

new_world
run STUB_MODES=branch.delete.remote=deny
judge "deny => remote branch kept" yes "$(remote_has feature)"
judge "  ... exit 3" 3 "$RC"
judge "  ... reports the reason and the setting" yes "$(out_has "blocked: stub deny for branch.delete.remote — allow with: /plugin-config branch.delete.remote allow")"

new_world
run STUB_MODES=branch.delete.remote=exit3
judge "resolver exits non-zero => kept" yes "$(remote_has feature)"
judge "  ... fail closed" yes "$(out_has "the permission resolver failed (exit 3")"

new_world
run STUB_MODES=branch.delete.remote=garbage
judge "unparseable resolver output => kept" yes "$(remote_has feature)"
judge "  ... exit 3" 3 "$RC"

new_world
mv "$STUB" "$STUB.off"
run
mv "$STUB.off" "$STUB"
judge "resolver missing => remote branch kept" yes "$(remote_has feature)"
judge "  ... local branch kept" yes "$(local_has feature)"
judge "  ... worktree kept" yes "$(exists "$WT")"
judge "  ... says the resolver is missing" yes "$(out_has "permission resolver (scripts/resolve-permission.sh) is missing")"
judge "  ... exit 3" 3 "$RC"

new_world
run STUB_MODES=branch.delete.local=deny,worktree.remove=deny
judge "deny on the R1 steps => local branch kept" yes "$(local_has feature)"
judge "  ... worktree kept" yes "$(exists "$WT")"

# =============================================================================
section "D-1: the PR must be MERGED, own-repo, and not the base/default branch"
# =============================================================================
new_world
pr_json OPEN feature main false
run
judge "OPEN PR => remote branch kept" yes "$(remote_has feature)"
judge "  ... local branch kept" yes "$(local_has feature)"
judge "  ... worktree kept" yes "$(exists "$WT")"
judge "  ... the resolver is never asked" 0 "$(grep -c . "$STUB_LOG" || true)"
judge "  ... exit 3, naming why" "3 yes" "$RC $(out_has "is OPEN, not MERGED")"

new_world
pr_json CLOSED feature main false
run
judge "CLOSED (unmerged) PR => nothing deleted" "yes yes" "$(remote_has feature) $(local_has feature)"

new_world
pr_json MERGED feature main true
run
judge "cross-repository PR => nothing deleted" "yes yes yes" "$(remote_has feature) $(local_has feature) $(exists "$WT")"
judge "  ... says it is cross-repository" yes "$(out_has "cross-repository")"

new_world
printf '{"state":"MERGED","headRefName":"feature","headRefOid":"%s","baseRefName":"main"}\n' "$HEAD_OID" > "$GHS/pr.json"
run
judge "isCrossRepository unreadable => nothing deleted" "yes yes" "$(remote_has feature) $(local_has feature)"

new_world
pr_json MERGED feature feature false
run
judge "head == base => nothing deleted" "yes yes" "$(remote_has feature) $(local_has feature)"

new_world
pr_json MERGED main release false
run
judge "head == the default branch => main kept on origin" yes "$(remote_has main)"
judge "  ... exit 3" 3 "$RC"

new_world
printf 'ERR' > "$GHS/pr.json"
run
judge "PR unreadable => nothing deleted" "yes yes yes" "$(remote_has feature) $(local_has feature) $(exists "$WT")"
judge "  ... exit 1" 1 "$RC"

# =============================================================================
section "protection is GitHub's answer, and the remote tip must be the merged head"
# =============================================================================
new_world
printf '{"name":"feature","protected":true}\n' > "$GHS/branch-feature.json"
run
judge "protected flag => remote branch kept" yes "$(remote_has feature)"
judge "  ... the resolver is not asked to delete it" 0 "$(asked branch.delete.remote)"
judge "  ... exit 3" 3 "$RC"

new_world
printf '[{"type":"deletion"}]\n' > "$GHS/rules-feature.json"
run
judge "ruleset deletion rule => remote branch kept" yes "$(remote_has feature)"

new_world
printf 'ERR' > "$GHS/branch-feature.json"
run
judge "protection flag unreadable => remote branch kept" yes "$(remote_has feature)"
judge "  ... says it could not be read" yes "$(out_has "could not be read")"

new_world
printf 'ERR' > "$GHS/rules-feature.json"
run
judge "rules unreadable => remote branch kept" yes "$(remote_has feature)"

new_world
# Someone pushed to the branch after the merge.
git -C "$WT" commit -q --allow-empty -m "late commit"
git -C "$WT" push -q origin feature 2>/dev/null
run
judge "remote tip beyond the merged head => remote branch kept" yes "$(remote_has feature)"
judge "  ... says the PR did not merge those commits" yes "$(out_has "did not merge")"

# =============================================================================
section "uncommitted and unpushed work is never discarded"
# =============================================================================
new_world
printf 'wip\n' > "$WT/notes.txt"
run
judge "dirty worktree => kept" yes "$(exists "$WT")"
judge "  ... with its file" yes "$(exists "$WT/notes.txt")"
judge "  ... reports uncommitted changes" yes "$(out_has "uncommitted changes")"
judge "  ... the local branch it holds is kept" yes "$(local_has feature)"
judge "  ... exit 3" 3 "$RC"

new_world
git -C "$WT" commit -q --allow-empty -m "local only"
run
judge "local commits no remote holds => local branch kept" yes "$(local_has feature)"
judge "  ... reports it" yes "$(out_has "holds commits no remote ref and no merged PR contains")"

harness_summary
