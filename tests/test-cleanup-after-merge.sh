#!/usr/bin/env bash
# test-cleanup-after-merge.sh — pr-dev's cleanup-after-merge.sh deletes a PR's
# branch, worktree and remote branch only when GitHub shows it is safe (audit
# finding D-1).
#
# WHAT IS HELD
#   - Nothing is deleted unless the PR is MERGED, its head is neither the base
#     nor the default branch, and it is not cross-repository; an unreadable
#     answer counts as a failed check.
#   - The remote branch is kept when GitHub reports it protected (branch flag or
#     a ruleset deletion rule), when that cannot be read, and when its tip holds
#     commits the PR did not merge.
#   - A worktree with uncommitted changes is never force-removed.
#   - A local branch with commits no remote ref or merged PR holds is kept.
#
# HOW
#   Every gh call goes to tests/lib/fake-gh.sh, wrapped here for the calls it does not model (pr view,
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

CAM="$ROOT/skills/dev-workflow/pr-dev/scripts/cleanup-after-merge.sh"

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
  # --repo other/thing: a DIFFERENT repository from the clone (acme/widget). Real
  # gh only reaches it from \`repo view\` with the slug passed positionally.
  "repo view other/thing"*)
     printf '{"defaultBranchRef":{"name":"main"},"nameWithOwner":"other/thing"}\n' > "\$GHS/other-repo.json"
     serve "\$GHS/other-repo.json" "\$q" ;;
  "api repos/other/thing/git/ref/heads/"*)  b="\${2#repos/other/thing/git/ref/heads/}"
     [ -f "\$GHS/oref-\$b.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
     serve "\$GHS/oref-\$b.json" "\$q" ;;
  "api repos/other/thing/branches/"*)       b="\${2#repos/other/thing/branches/}"; serve "\$GHS/obranch-\$b.json" "\$q" ;;
  "api repos/other/thing/rules/branches/"*) printf '[]\n' > "\$GHS/orules.json"; serve "\$GHS/orules.json" "\$q" ;;
  "api -X DELETE repos/other/thing/git/refs/heads/"*) exit 0 ;;
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
}
# pr_json <state> <head> <base> <cross>
pr_json() {
  printf '{"state":"%s","headRefName":"%s","headRefOid":"%s","baseRefName":"%s","isCrossRepository":%s}\n' \
    "$1" "$2" "$HEAD_OID" "$3" "$4" > "$GHS/pr.json"
}
# run — the script from the clone; output in OUT, exit in RC.
run() {
  RC=0
  OUT="$(cd "$CL" && bash "$CAM" 42 2>&1)" || RC=$?
}
remote_has() { git -C "$ORIGIN" show-ref --verify --quiet "refs/heads/$1" && echo yes || echo no; }
local_has()  { git -C "$CL" show-ref --verify --quiet "refs/heads/$1" && echo yes || echo no; }
out_has() { has "$OUT" "$1"; }

# =============================================================================
section "a merged PR is cleaned up"
# =============================================================================
new_world
run
judge "exit 0" 0 "$RC"
judge "remote branch deleted" no "$(remote_has feature)"
judge "local branch deleted" no "$(local_has feature)"
judge "worktree removed" no "$(exists "$WT")"
judge "no skipped: list" no "$(out_has "skipped:")"

# =============================================================================
section "D-1: the PR must be MERGED, own-repo, and not the base/default branch"
# =============================================================================
new_world
pr_json OPEN feature main false
run
judge "OPEN PR => remote branch kept" yes "$(remote_has feature)"
judge "  ... local branch kept" yes "$(local_has feature)"
judge "  ... worktree kept" yes "$(exists "$WT")"
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

# =============================================================================
section "--repo naming ANOTHER repository: only GitHub-side cleanup, via the API"
# =============================================================================
# Every local step acts on the CHECKOUT's origin. Run from acme/widget with
# --repo other/thing, the old script deleted acme/widget's merged 'feature'
# branch (remote, local and worktree) because the names matched. This world is
# built so that would happen again: its own 'feature' is merged and same-named.
run_pinned() {
  RC=0
  OUT="$(cd "$CL" && bash "$CAM" --repo other/thing 42 2>&1)" || RC=$?
}
api_deleted() { grep -q "api -X DELETE repos/other/thing/git/refs/heads/$1" "$GHS/calls.log" 2>/dev/null && echo yes || echo no; }

new_world
printf '{"object":{"sha":"%s"}}\n' "$HEAD_OID" > "$GHS/oref-feature.json"
printf '{"name":"feature","protected":false}\n' > "$GHS/obranch-feature.json"
run_pinned
judge "the pinned repo's merged branch is deleted through the API" yes "$(api_deleted feature)"
judge "  ... this checkout's origin branch is untouched" yes "$(remote_has feature)"
judge "  ... this checkout's local branch is untouched" yes "$(local_has feature)"
judge "  ... this checkout's worktree is untouched" yes "$(exists "$WT")"
judge "  ... says local cleanup was skipped, and why" yes "$(out_has "not other/thing — local cleanup")"
judge "  ... exit 0" 0 "$RC"

new_world
printf '{"object":{"sha":"%s"}}\n' "0123456789abcdef0123456789abcdef01234567" > "$GHS/oref-feature.json"
printf '{"name":"feature","protected":false}\n' > "$GHS/obranch-feature.json"
run_pinned
judge "remote tip is not the PR head => kept, not deleted" no "$(api_deleted feature)"
judge "  ... exit 3, naming why" "3 yes" "$RC $(out_has "is not the merged PR head")"

new_world
printf '{"object":{"sha":"%s"}}\n' "$HEAD_OID" > "$GHS/oref-feature.json"
printf '{"name":"feature","protected":true}\n' > "$GHS/obranch-feature.json"
run_pinned
judge "protected remote branch => kept" no "$(api_deleted feature)"
judge "  ... exit 3" 3 "$RC"

new_world
printf '{"name":"feature","protected":false}\n' > "$GHS/obranch-feature.json"
run_pinned
judge "remote branch already gone (404) => nothing to delete, exit 0" "no 0" "$(api_deleted feature) $RC"
judge "  ... and says so" yes "$(out_has "is already gone")"

new_world
pr_json OPEN feature main false
printf '{"object":{"sha":"%s"}}\n' "$HEAD_OID" > "$GHS/oref-feature.json"
run_pinned
judge "unmerged PR with --repo => nothing deleted anywhere" "no yes yes" "$(api_deleted feature) $(remote_has feature) $(local_has feature)"
judge "  ... exit 3" 3 "$RC"

harness_summary
