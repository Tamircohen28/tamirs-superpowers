#!/usr/bin/env bash
# test-standards-inventory-online.sh — the inventory's GitHub reads, on the fake gh.
#
# WHY THIS FILE EXISTS
#   standards-inventory.sh delegates two findings to CLI audits: Actions
#   concurrency to `github-policy.sh audit --json` and the canonical labels to
#   `github-labels.sh audit --json`. Both exit 3 when they find drift — and
#   drift is the finding. The inventory consumed the policy document only when
#   the command exited 0, so the moment the audit started exiting 3 on drift
#   (PR #374), a concurrency violation left `actions.checked=false`,
#   `violations=0`, and S4-14 was never scored: the control went silent exactly
#   when it had something to say. Every other suite runs the inventory with
#   CONTRACT_OFFLINE=1, where none of this code executes.
#
# WHAT IT HOLDS
#   * exit 3 is a successful read: a planted cancellable workflow with no
#     concurrency block surfaces as S4-14, and the missing canonical labels as
#     S3-05, while both audits demonstrably exit 3;
#   * any other exit code, or a `failed` bucket inside a 3, is UNREADABLE:
#     checked stays false and no gap is scored — and each such failure is
#     isolated to its own control, never bleeding into the other.
#
# HOW THE SUBJECT IS ROOTED
#   A hermetic git repo whose scripts/, config/, core/ and the _contract
#   scripts are SYMLINKS to the real tree, with `origin` set to the fixture
#   repository. The inventory derives every path from its own location, so it
#   finds the real, unmodified scripts; github-policy.sh sees the hermetic
#   root as "this checkout" and reads the planted workflow from it. `origin`
#   is rewritten by url.insteadOf to a local path so `git fetch` never leaves
#   the machine.
#
# bash 3.2. `set -uo pipefail`, not -e: the assertions are the control flow.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"
# shellcheck source=tests/lib/fake-gh.sh
source "$REPO_ROOT/tests/lib/fake-gh.sh"

harness_require git jq awk sed python3

TMP="$(harness_tmpdir)"
FIX="$TMP/fixtures"
ROOT="$TMP/root"
# The slug the `compliant` rulesets were transcribed from: the canonical policy
# carries a per-repository override for it (approving reviews, required
# contexts), so against this slug the rulesets read as already compliant and
# the audit's exit 3 comes from the planted Actions finding alone — the exact
# shape of the regression.
TARGET_REPO="Tamircohen28/tamirs-superpowers"
LABELS_FILE="$REPO_ROOT/config/github/labels.json"
REGISTRY="$REPO_ROOT/core/capabilities/platforms.json"

# ---------------------------------------------------------------------------
# Hermetic root
# ---------------------------------------------------------------------------
mkdir -p "$TMP/bin" "$TMP/home"
cp -R "$REPO_ROOT/tests/fixtures/github" "$FIX"
harness_new_repo "$ROOT" main
mkdir -p "$ROOT/scripts" "$ROOT/skills/repo/_contract/scripts" "$ROOT/.github/workflows"
for e in "$REPO_ROOT"/scripts/*; do ln -s "$e" "$ROOT/scripts/$(basename "$e")"; done
ln -s "$REPO_ROOT/config" "$ROOT/config"
ln -s "$REPO_ROOT/core"   "$ROOT/core"
for s in standards-inventory.sh score-standards-gaps.sh check-repo-hygiene.sh check-readme-branding.sh; do
  ln -s "$REPO_ROOT/skills/repo/_contract/scripts/$s" "$ROOT/skills/repo/_contract/scripts/$s"
done
ln -s "$REPO_ROOT/skills/repo/_contract/standards-contract.json" "$ROOT/skills/repo/_contract/standards-contract.json"
git -C "$ROOT" remote add origin "git@github.com:$TARGET_REPO.git"
# Keep `git fetch` on this machine. NOT url.insteadOf: that also rewrites what
# `git remote get-url` returns, and both the inventory and github-policy.sh
# derive owner/name from it. A no-op ssh command fails the fetch locally and
# leaves the URL exactly as GitHub would have it.
export GIT_SSH_COMMAND=false

# A cancellable PR-validation workflow with NO concurrency block: the one
# Actions finding the policy audit reports as a change (actions:ci.yml modify).
cat >"$ROOT/.github/workflows/ci.yml" <<'YAML'
name: CI
on:
  pull_request:
  push:
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: make validate
YAML
git -C "$ROOT" add .github && git -C "$ROOT" -c user.email=t@t -c user.name=t commit -qm 'ci: planted workflow'

fake_gh_install "$TMP/bin" "$TMP/gh.log" "$FIX/inventory-drift"
PATH="$TMP/bin:$PATH"
export PATH
export HOME="$TMP/home" GH_CONFIG_DIR="$TMP/home/gh" GH_TOKEN="" GITHUB_TOKEN="" NO_COLOR=1
unset CONTRACT_OFFLINE

INVENTORY="$ROOT/skills/repo/_contract/scripts/standards-inventory.sh"
SCORE="$ROOT/skills/repo/_contract/scripts/score-standards-gaps.sh"
INV="$TMP/inventory.json"
GAPS="$TMP/gaps.json"

# run_inventory — one inventory + scoring pass on the hermetic root.
run_inventory() {
  fake_gh_reset
  bash "$INVENTORY" "$ROOT" >"$INV" 2>"$TMP/inventory.err"
  bash "$SCORE" app-gold <"$INV" >"$GAPS" 2>/dev/null
}
inv()  { jq -r "$1" "$INV"; }
gap()  { jq -r --arg id "$1" '[.gaps[] | select(.id == $id)] | length' "$GAPS"; }
gapmsg() { jq -r --arg id "$1" '[.gaps[] | select(.id == $id) | .message] | join(" ")' "$GAPS"; }

N_PLATFORMS="$(jq '.platforms | length' "$REGISTRY")"
N_TAMIRS="$(jq '[.labels[] | select(.origin != "github-default")] | length' "$LABELS_FILE")"
EXPECT_MISSING=$((N_TAMIRS - 1 + N_PLATFORMS))

# ---------------------------------------------------------------------------
section "hermeticity"
judge "gh resolves to the temp shim" "$TMP/bin/gh" "$(command -v gh)"
judge "the inventory is reached through the hermetic root" yes "$([ -L "$INVENTORY" ] && echo yes || echo no)"

# ---------------------------------------------------------------------------
section "the precondition: both audits exit 3 on this repository"
rc=0; bash "$ROOT/scripts/github-policy.sh" audit --repo "$TARGET_REPO" --json >"$TMP/policy.json" 2>/dev/null || rc=$?
judge "github-policy.sh audit --json exits 3 (drift)"       3   "$rc"
judge "  because of the planted workflow"                   modify "$(jq -r '.changes[] | select(.label == "actions:ci.yml") | .status' "$TMP/policy.json")"
judge "  while the rulesets themselves are compliant"       already_compliant "$(jq -r '.repositories[0].bucket' "$TMP/policy.json")"
rc=0; bash "$ROOT/scripts/github-labels.sh" audit --repo "$TARGET_REPO" --json >"$TMP/labels.json" 2>/dev/null || rc=$?
judge "github-labels.sh audit --json exits 3 (drift)"       3   "$rc"
judge "  with the missing labels counted"                   "$EXPECT_MISSING" "$(jq '.repos[0].summary.create' "$TMP/labels.json")"

# ---------------------------------------------------------------------------
section "exit 3 is a successful read: the drift is the finding"
run_inventory
judge "the inventory parses"                                yes "$(jq empty "$INV" >/dev/null 2>&1 && echo yes || echo no)"
judge "governance was readable"                             true "$(inv '.branch_governance.readable')"
judge "  and the rulesets were read (safety active)"        true "$(inv '.branch_governance.rulesets.safety_active')"
judge "Actions concurrency was CHECKED despite the audit's exit 3" true "$(inv '.branch_governance.actions.checked')"
judge "  with the one violation counted"                    1   "$(inv '.branch_governance.actions.violations')"
judge "  and scored as S4-14"                               1   "$(gap S4-14)"
judge "labels were CHECKED despite the audit's exit 3"      true "$(inv '.github.labels.checked')"
judge "  with the missing count"                            "$EXPECT_MISSING" "$(inv '.github.labels.missing')"
judge "  naming them"                                       yes "$(has "$(inv '.github.labels.missing_names | join(",")')" "chore")"
judge "  and scored as S3-05"                               1   "$(gap S3-05)"
judge "  whose message names a missing label"               yes "$(has "$(gapmsg S3-05)" "chore")"
judge "  and the remedy"                                    yes "$(has "$(gapmsg S3-05)" "github-labels.sh apply")"
judge "the inventory itself ran both audits"                2   "$(awk -F'\t' '$3 == "repos/'"$TARGET_REPO"'/labels" || $3 == "repos/'"$TARGET_REPO"'/rulesets" { n[$3]=1 } END { c=0; for (k in n) c++; print c }' "$FAKE_GH_LOG")"

# ---------------------------------------------------------------------------
section "a failed read stays unknown, and only for its own control"
# Rulesets 500: the policy audit reports the repository as failed (exit 3 with
# a `failed` bucket). That is a read that did not happen — unchecked, no gap —
# and it must not touch the labels finding.
fake_gh_reset
fake_gh_error GET 'repos/*/*/rulesets' 500
bash "$INVENTORY" "$ROOT" >"$INV" 2>/dev/null; bash "$SCORE" app-gold <"$INV" >"$GAPS" 2>/dev/null
judge "rulesets 500: Actions is not checked"                false "$(inv '.branch_governance.actions.checked')"
judge "  violations read 0, not a guess"                    0   "$(inv '.branch_governance.actions.violations')"
judge "  and S4-14 is not scored"                           0   "$(gap S4-14)"
judge "  while labels are still checked"                    true "$(inv '.github.labels.checked')"
judge "  and S3-05 still scored"                            1   "$(gap S3-05)"

# Labels 403: the label audit exits 3 with a `failed` bucket — unchecked, no
# gap — and the Actions finding is unaffected.
fake_gh_reset
fake_gh_error GET 'repos/*/*/labels' 403
bash "$INVENTORY" "$ROOT" >"$INV" 2>/dev/null; bash "$SCORE" app-gold <"$INV" >"$GAPS" 2>/dev/null
judge "labels 403: labels are not checked"                  false "$(inv '.github.labels.checked')"
judge "  missing reads 0, not a guess"                      0   "$(inv '.github.labels.missing')"
judge "  and S3-05 is not scored"                           0   "$(gap S3-05)"
judge "  while Actions is still checked"                    true "$(inv '.branch_governance.actions.checked')"
judge "  and S4-14 still scored"                            1   "$(gap S4-14)"

# Exit 1 (no document at all): the label audit cannot even start.
fake_gh_reset
GITHUB_LABELS_FILE="$TMP/no-such-labels.json" bash "$INVENTORY" "$ROOT" >"$INV" 2>/dev/null
bash "$SCORE" app-gold <"$INV" >"$GAPS" 2>/dev/null
judge "label audit exit 1: labels are not checked"          false "$(inv '.github.labels.checked')"
judge "  and S3-05 is not scored"                           0   "$(gap S3-05)"
judge "  while S4-14 still is"                              1   "$(gap S4-14)"

# ---------------------------------------------------------------------------
section "offline, none of this runs"
fake_gh_reset
CONTRACT_OFFLINE=1 bash "$INVENTORY" "$ROOT" >"$INV" 2>/dev/null
judge "offline: governance unreadable"                      false "$(inv '.branch_governance.readable')"
judge "offline: Actions unchecked"                          false "$(inv '.branch_governance.actions.checked')"
judge "offline: labels unchecked"                           false "$(inv '.github.labels.checked')"
judge "offline: no gh call at all"                          0   "$(wc -l <"$FAKE_GH_LOG" | tr -d ' ')"

harness_summary
