#!/usr/bin/env bash
# test-standards-inventory-paths.sh — the inventory must judge a repo by what the
# platform honours, not by the one path it happened to probe.
#
# WHY THIS FILE EXISTS
#   `standards-inventory.sh` probed a single path for two controls the platform
#   reads from several. `#129` fixed that — root, `.github/` and `docs/` for
#   CODEOWNERS; the `.md`/`.txt`/`LICENCE`/`COPYING` spellings for the licence —
#   but shipped no test, so nothing stops the next edit from narrowing the search
#   again, and nothing proves the widened one did not go too far.
#
#   The defect it fixed is the mirror image of the usual one in this repo. The
#   familiar form is a check that PASSES because it could not verify. This one
#   ASSERTED A GAP from an incomplete read — S4-01 "CODEOWNERS missing" against a
#   repo whose `.github/CODEOWNERS` was present and working. That is the more
#   corrosive of the two, because the only way to make it go quiet is to degrade
#   a repo that was already correct.
#
#   So every case here is asserted in BOTH directions. Each location that must be
#   recognised is paired with a repo that genuinely has none, so a regression to
#   an unconditional `true` fails. Each widened search is paired with a location
#   the platform does NOT honour, so "probe everywhere" fails too. And the two
#   controls that are legitimately root-only are asserted to have stayed that way.
#
# Usage: bash tests/test-standards-inventory-paths.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require jq
INVENTORY="$REPO_ROOT/skills/repo/_contract/scripts/standards-inventory.sh"
SCORE="$REPO_ROOT/skills/repo/_contract/scripts/score-standards-gaps.sh"

TMP="$(harness_tmpdir)"

# repo <name> <relative-file>... — a bare repo root holding exactly those files.
repo() {
  local d="$TMP/$1"; shift
  mkdir -p "$d"
  local rel
  for rel in "$@"; do
    mkdir -p "$d/$(dirname "$rel")"
    printf '* @TamirCohen28\n' > "$d/$rel"
  done
  printf '%s\n' "$d"
}

# fact <dir> <jq-path> — one field of the inventory, read offline.
fact() { CONTRACT_OFFLINE=1 bash "$INVENTORY" "$1" | jq -r "$2"; }

# fires <dir> <gap-id> — does the scorer raise this gap against the repo?
fires() {
  local out
  out="$(CONTRACT_OFFLINE=1 bash "$INVENTORY" "$1" | bash "$SCORE" 2>/dev/null)"
  has "$out" "$2"
}

section "CODEOWNERS — every location GitHub honours"

judge "root CODEOWNERS is seen" true \
  "$(fact "$(repo co-root CODEOWNERS)" '.root_files.codeowners')"
judge ".github/CODEOWNERS is seen" true \
  "$(fact "$(repo co-github .github/CODEOWNERS)" '.root_files.codeowners')"
judge "docs/CODEOWNERS is seen" true \
  "$(fact "$(repo co-docs docs/CODEOWNERS)" '.root_files.codeowners')"

# The negative control. Without this, `codeowners=true` unconditionally would pass
# all three assertions above.
judge "no CODEOWNERS anywhere is still false" false \
  "$(fact "$(repo co-none README.md)" '.root_files.codeowners')"

# A location GitHub does NOT honour must not be accepted either — the search is
# widened to the platform's rule, not to "anywhere in the tree".
judge "src/CODEOWNERS is not a CODEOWNERS" false \
  "$(fact "$(repo co-bogus src/CODEOWNERS)" '.root_files.codeowners')"

section "S4-01 follows the inventory, in both directions"

judge "S4-01 stays quiet for .github/CODEOWNERS" no \
  "$(fires "$(repo s4-github .github/CODEOWNERS)" 'S4-01')"
judge "S4-01 stays quiet for root CODEOWNERS" no \
  "$(fires "$(repo s4-root CODEOWNERS)" 'S4-01')"
judge "S4-01 still fires when there is none" yes \
  "$(fires "$(repo s4-none README.md)" 'S4-01')"

section "LICENSE — the same defect, same shape"

judge "LICENSE is seen" true \
  "$(fact "$(repo lic-plain LICENSE)" '.root_files.license')"
judge "LICENSE.md is seen" true \
  "$(fact "$(repo lic-md LICENSE.md)" '.root_files.license')"
judge "LICENSE.txt is seen" true \
  "$(fact "$(repo lic-txt LICENSE.txt)" '.root_files.license')"
judge "COPYING is seen" true \
  "$(fact "$(repo lic-copying COPYING)" '.root_files.license')"
judge "LICENCE (British spelling) is seen" true \
  "$(fact "$(repo lic-brit LICENCE)" '.root_files.license')"
judge "LICENCE.md is seen" true \
  "$(fact "$(repo lic-brit-md LICENCE.md)" '.root_files.license')"
judge "COPYING.md is seen" true \
  "$(fact "$(repo lic-copying-md COPYING.md)" '.root_files.license')"
judge "docs/LICENSE is NOT a repo licence" false \
  "$(fact "$(repo lic-nested docs/LICENSE)" '.root_files.license')"
judge "no licence at all is still false" false \
  "$(fact "$(repo lic-none README.md)" '.root_files.license')"

section "root-only conventions stay root-only"

# CLAUDE.md and AGENTS.md are per-directory instruction files by design; only the
# root one is the repository's own. Widening these would be wrong, not generous.
judge "docs/CLAUDE.md does not count as the repo's CLAUDE.md" false \
  "$(fact "$(repo cl-nested docs/CLAUDE.md)" '.root_files.claude_md')"
judge "root CLAUDE.md does" true \
  "$(fact "$(repo cl-root CLAUDE.md)" '.root_files.claude_md')"

section "the live repo is self-consistent"

judge "this repo reports its own CODEOWNERS" true \
  "$(fact "$REPO_ROOT" '.root_files.codeowners')"
judge "this repo reports its own LICENSE" true \
  "$(fact "$REPO_ROOT" '.root_files.license')"

harness_summary
