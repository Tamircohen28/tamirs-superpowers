#!/usr/bin/env bash
# test-cleanup-gates.sh — the cleanup skill's cleanup.sh --yes deletes only what
# GitHub shows safe (audit finding D-6).
#
# WHAT IS HELD
#   - Dry-run (no --yes) deletes nothing.
#   - Protection is GitHub's answer (the branch `protected` flag, a ruleset
#     deletion rule), never a name; unreadable protection keeps the branch.
#   - A branch at the default branch's tip is kept; so is one with an open PR
#     or whose PRs cannot be listed.
#   - A clean worktree is kept when its commits are on no remote ref (also
#     when origin/<branch> does not exist), when an agent holds a live claim on
#     its branch, or when an unfinished objective task owns it.
#
# HOW
#   gh is tests/lib/fake-gh.sh, wrapped here for pr list and the branch and
#   rules endpoints. Real git under a temp dir.
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
export AGENT_CLAIM_DIR="$TMP/claims"
unset GH_TOKEN GITHUB_TOKEN GH_REPO OBJECTIVES_ROOT AGENT_CLAIM_STALE_SECONDS 2>/dev/null || true

CS="$ROOT/skills/repo/cleanup/scripts/cleanup.sh"

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
q="" head="" state="" prev=""
for a in "\$@"; do
  case "\$prev" in --jq|-q) q="\$a" ;; --head) head="\$a" ;; --state) state="\$a" ;; esac
  prev="\$a"
done
case "\$1 \${2:-}" in
  "pr list") f="\$GHS/prs-\$state-\$head.json"; [ -f "\$f" ] || printf '[]\n' > "\$f"; serve "\$f" "\$q" ;;
esac
case "\$*" in
  "api repos/acme/widget/branches/"*)       b="\${2#repos/acme/widget/branches/}"; serve "\$GHS/branch-\$b.json" "\$q" ;;
  "api repos/acme/widget/rules/branches/"*) b="\${2#repos/acme/widget/rules/branches/}"
     [ -f "\$GHS/rules-\$b.json" ] || printf '[]\n' > "\$GHS/rules-\$b.json"
     serve "\$GHS/rules-\$b.json" "\$q" ;;
esac
exec bash "$ROOT/tests/lib/fake-gh.sh" "\$@"
SHIM
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

# --- the world ---------------------------------------------------------------------
# origin branches, all merged into main except `fresh`, which sits at main's tip:
#   merged1 (a merged same-repo PR), forked (its merged PR is cross-repo), prot
#   (protected flag), ruled (ruleset deletion rule), unk (protection unreadable),
#   openpr (an open PR), listfail (PR list fails)
# auxiliary worktrees, all clean:
#   wgone   no origin branch, no commits of its own         -> removable
#   wlocal  no origin branch, one local-only commit         -> kept (unpushed)
#   wclaim  a live agent claim on its branch                -> kept
#   wstale  a stale claim (old heartbeat)                   -> removable
#   wtask   an objective task running in it                 -> kept
#   wdone   its objective task completed                    -> removable
N=0
REMOTE_BRANCHES="merged1 forked prot ruled unk openpr listfail"
new_world() {
  N=$((N + 1))
  W="$TMP/w$N"; ORIGIN="$W/origin.git"; CL="$W/clone"; WTS="$W/wts"
  mkdir -p "$W" "$WTS"
  git init -q --bare -b main "$ORIGIN"
  harness_new_repo "$CL"
  git -C "$CL" remote add origin "$ORIGIN"
  git -C "$CL" push -q origin main
  git -C "$CL" remote set-head origin main >/dev/null
  printf '.dev-files/\n' >> "$CL/.git/info/exclude"
  local b
  for b in $REMOTE_BRANCHES; do
    git -C "$CL" checkout -q -b "$b" main
    git -C "$CL" commit -q --allow-empty -m "work on $b"
    git -C "$CL" push -q origin "$b" 2>/dev/null
    git -C "$CL" checkout -q main
    git -C "$CL" merge -q --no-ff --no-edit "$b"
  done
  git -C "$CL" push -q origin main
  git -C "$CL" branch -q fresh main
  git -C "$CL" push -q origin fresh 2>/dev/null
  git -C "$CL" fetch -q origin
  for b in wgone wlocal wclaim wstale wtask wdone; do
    git -C "$CL" worktree add -q -b "$b" "$WTS/$b" main
  done
  git -C "$WTS/wlocal" commit -q --allow-empty -m "local only"

  rm -f "$GHS"/*.json
  for b in $REMOTE_BRANCHES fresh; do printf '{"name":"%s","protected":false}\n' "$b" > "$GHS/branch-$b.json"; done
  printf '{"name":"prot","protected":true}\n' > "$GHS/branch-prot.json"
  printf '[{"type":"deletion"}]\n' > "$GHS/rules-ruled.json"
  printf 'ERR' > "$GHS/branch-unk.json"
  printf '[{"number":9}]\n' > "$GHS/prs-open-openpr.json"
  printf 'ERR' > "$GHS/prs-open-listfail.json"
  printf '[{"number":7,"isCrossRepository":false,"baseRefName":"main"}]\n' > "$GHS/prs-merged-merged1.json"
  printf '[{"number":8,"isCrossRepository":true,"baseRefName":"main"}]\n' > "$GHS/prs-merged-forked.json"

  rm -rf "$AGENT_CLAIM_DIR"; mkdir -p "$AGENT_CLAIM_DIR"
  local now; now="$(date +%s)"
  printf '{"schema":"agent-work-claim/1","resource":"git:acme/widget@wclaim","agent_id":"other","tool":"codex","host":"%s","pid":%s,"heartbeat_at":%s}\n' \
    "$(hostname)" "$$" "$now" > "$AGENT_CLAIM_DIR/git_acme_widget_wclaim.json"
  printf '{"schema":"agent-work-claim/1","resource":"git:acme/widget@wstale","agent_id":"other","tool":"codex","host":"elsewhere","pid":1,"heartbeat_at":%s}\n' \
    "$((now - 5000))" > "$AGENT_CLAIM_DIR/git_acme_widget_wstale.json"

  local od="$CL/.dev-files/objectives/obj1"
  mkdir -p "$od/tasks"
  printf '{"id":"obj1","status":"active","integration_branch":"objective/obj1","base_branch":"main","tasks":["task-001","task-002"]}\n' > "$od/objective.json"
  printf '{"id":"task-001","status":"running","branch":"wtask","worktree":"%s"}\n' "$WTS/wtask" > "$od/tasks/task-001.json"
  printf '{"id":"task-002","status":"completed","branch":"wdone","worktree":"%s"}\n' "$WTS/wdone" > "$od/tasks/task-002.json"
}
# run [env...] -- [args...] — the copied script on the clone; OUT and RC.
run() {
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  RC=0
  OUT="$(cd "$CL" && env ${envs[@]+"${envs[@]}"} bash "$CS" "$@" 2>&1)" || RC=$?
}
remote_has() { git -C "$ORIGIN" show-ref --verify --quiet "refs/heads/$1" && echo yes || echo no; }
out_has() { has "$OUT" "$1"; }

# =============================================================================
section "dry-run deletes nothing"
# =============================================================================
new_world
run -- .
judge "dry-run exit 0" 0 "$RC"
judge "merged1 still on origin" yes "$(remote_has merged1)"
judge "worktree wgone still there" yes "$(exists "$WTS/wgone")"
judge "the plan names the deletion --yes would make" yes "$(out_has "would delete merged branch: merged1")"

# =============================================================================
section "--yes: only what GitHub shows safe is deleted"
# =============================================================================
new_world
run -- --yes .
judge "exit 0" 0 "$RC"
judge "merged1 (merged, unprotected) deleted" no "$(remote_has merged1)"
judge "forked (merged into main, cross-repo PR) deleted" no "$(remote_has forked)"
judge "fresh (at the default tip) kept" yes "$(remote_has fresh)"
judge "  ... named as at the tip" yes "$(out_has "keep (at the main tip — no commits of its own): fresh")"
judge "prot (protected flag) kept" yes "$(remote_has prot)"
judge "ruled (ruleset deletion rule) kept" yes "$(remote_has ruled)"
judge "unk (protection unreadable) kept" yes "$(remote_has unk)"
judge "openpr (open PR) kept" yes "$(remote_has openpr)"
judge "listfail (PR list failed) kept" yes "$(remote_has listfail)"

judge "wgone (no origin branch, nothing unpushed) removed" no "$(exists "$WTS/wgone")"
judge "wlocal (local-only commit, no origin branch) kept" yes "$(exists "$WTS/wlocal")"
judge "  ... as unpushed" yesyes "$(out_has "keep (unpushed commits: 1): ")$(out_has "/wts/wlocal")"
judge "wclaim (live claim) kept" yes "$(exists "$WTS/wclaim")"
judge "  ... as in flight" yes "$(out_has "live agent claim on git:acme/widget@wclaim")"
judge "wstale (stale claim) removed" no "$(exists "$WTS/wstale")"
judge "wtask (running objective task) kept" yes "$(exists "$WTS/wtask")"
judge "  ... named by its task" yes "$(out_has "objective obj1 task-001 is running")"
judge "wdone (completed task) removed" no "$(exists "$WTS/wdone")"

new_world
printf 'not json' > "$AGENT_CLAIM_DIR/git_acme_widget_wgone.json"
run -- --yes --local-only .
judge "an unreadable claim for its branch keeps the worktree" yes "$(exists "$WTS/wgone")"

harness_summary
