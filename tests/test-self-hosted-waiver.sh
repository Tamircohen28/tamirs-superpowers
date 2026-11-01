#!/usr/bin/env bash
# test-self-hosted-waiver.sh — a deliberate self-hosted runner can be waived on its
# own line, and nothing else can.
#
# WHY THIS FILE EXISTS
#   S6-04 (check-repo-hygiene.sh) and ip-scan.sh flagged every self-hosted runner,
#   with no way to record that a repo chose one on purpose — a private repo whose
#   GitHub-hosted minutes are billing-blocked, running CI on its owner's machine
#   behind a trust gate. The gate could then never reach P1 = 0, and a gate that is
#   permanently red hides the next real P1. The waiver is the `action-pin-ok:`
#   shape: `# self-hosted-ok: <reason>` in the comment part of that line.
#
#   Every case is asserted in both directions, so a fix that simply ignores
#   self-hosted runners fails here: an unwaived line must still fire, a waiver
#   without a reason waives nothing, the token outside a comment waives nothing,
#   and on ip-scan the waiver must not reach the credential pattern.
#
#   The runner line is assembled at run time. This repo's own PR checklist runs
#   ip-scan.sh over the tree, and a literal fixture line would be a hit.
#
# Usage: bash tests/test-self-hosted-waiver.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require jq
HYGIENE="$REPO_ROOT/skills/repo/_contract/scripts/check-repo-hygiene.sh"
IPSCAN="$REPO_ROOT/skills/repo/_contract/scripts/ip-scan.sh"
INVENTORY="$REPO_ROOT/skills/repo/_contract/scripts/standards-inventory.sh"
SCORE="$REPO_ROOT/skills/repo/_contract/scripts/score-standards-gaps.sh"

TMP="$(harness_tmpdir)"
RUNNER="runs-on: [self""-hosted, macOS, ARM64, my-repo]"

# repo <name> <workflow-line>... — a repo whose one workflow has these job lines.
repo() {
  local d="$TMP/$1"; shift
  mkdir -p "$d/.github/workflows"
  {
    printf 'name: CI\non: push\njobs:\n'
    local i=0 l
    for l in "$@"; do i=$((i + 1)); printf '  j%s:\n    %s\n    steps:\n      - run: "true"\n' "$i" "$l"; done
  } > "$d/.github/workflows/ci.yml"
  printf '%s\n' "$d"
}

hyg() { bash "$HYGIENE" "$1" | jq -r "$2"; }
fires() {
  local out
  out="$(CONTRACT_OFFLINE=1 bash "$INVENTORY" "$1" | bash "$SCORE" 2>/dev/null)"
  has "$out" "$2"
}
scan_clean() { has "$(bash "$IPSCAN" "$1" 2>&1)" "RESULT: CLEAN"; }

section "check-repo-hygiene.sh / S6-04"

d="$(repo plain "$RUNNER")"
judge "unwaived runner is flagged" true "$(hyg "$d" '.hygiene.self_hosted_ci')"
judge "S6-04 fires for an unwaived runner" yes "$(fires "$d" 'S6-04')"

d="$(repo waived "$RUNNER  # self-hosted-ok: hosted minutes are billing-blocked")"
judge "waived runner is not flagged" false "$(hyg "$d" '.hygiene.self_hosted_ci')"
judge "waived runner is counted, not hidden" 1 "$(hyg "$d" '.hygiene.self_hosted_waived')"
judge "S6-04 stays quiet when every runner is waived" no "$(fires "$d" 'S6-04')"

d="$(repo mixed "$RUNNER  # self-hosted-ok: billing" "$RUNNER")"
judge "one unwaived line among waived ones still flags" true "$(hyg "$d" '.hygiene.self_hosted_ci')"
judge "the waived one is still counted" 1 "$(hyg "$d" '.hygiene.self_hosted_waived')"

d="$(repo noreason "$RUNNER  # self-hosted-ok:")"
judge "a waiver with no reason waives nothing" true "$(hyg "$d" '.hygiene.self_hosted_ci')"

d="$(repo nocomment "runs-on: [self""-hosted, self-hosted-ok: x]")"
judge "the token outside a comment waives nothing" true "$(hyg "$d" '.hygiene.self_hosted_ci')"

d="$(repo quoted "runs-on: [self""-hosted, \"# self-hosted-ok: label\"]")"
judge "a quoted label holding the token waives nothing" true "$(hyg "$d" '.hygiene.self_hosted_ci')"
d="$(repo quoted-single "runs-on: [self""-hosted, '# self-hosted-ok: label']")"
judge "same with single quotes" true "$(hyg "$d" '.hygiene.self_hosted_ci')"
d="$(repo quoted-then-real "runs-on: [self""-hosted, \"a#b\"]  # self-hosted-ok: billing")"
judge "a real comment after a quoted hash still waives" false "$(hyg "$d" '.hygiene.self_hosted_ci')"

d="$(repo hosted "runs-on: ubuntu-latest")"
judge "a hosted runner is not flagged" false "$(hyg "$d" '.hygiene.self_hosted_ci')"
judge "and nothing is counted as waived" 0 "$(hyg "$d" '.hygiene.self_hosted_waived')"

section "ip-scan.sh"

judge "unwaived runner is a hit" no "$(scan_clean "$(repo s-plain "$RUNNER")")"
judge "waived runner is clean" yes "$(scan_clean "$(repo s-waived "$RUNNER  # self-hosted-ok: billing")")"
judge "a waiver with no reason is still a hit" no "$(scan_clean "$(repo s-noreason "$RUNNER  # self-hosted-ok:")")"
judge "a quoted label holding the token is still a hit" no \
  "$(scan_clean "$(repo s-quoted "runs-on: [self""-hosted, \"# self-hosted-ok: label\"]")")"
out="$(bash "$IPSCAN" "$(repo s-count "$RUNNER  # self-hosted-ok: billing")" 2>&1)"
judge "the scan reports what it waived" yes "$(has "$out" "Waived: 1 self-hosted")"

d="$TMP/s-cred"; mkdir -p "$d"
printf '%s = "%s"  # self-hosted-ok: not a runner\n' 'API''_KEY' 'abcdefghijklmnop' > "$d/config.py"
judge "the waiver never reaches the credential pattern" no "$(scan_clean "$d")"

harness_summary
