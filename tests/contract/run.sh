#!/usr/bin/env bash
# run.sh — platform contract suites (REFACTOR-SPEC §22.4).
#
# One suite per target. The schema/contract half always runs; the vendor-CLI half
# skips with a named reason when the CLI is absent, so the same file serves both
# the always-on CI job and the nightly platform job.
#
# Usage:
#   bash tests/contract/run.sh                 # every platform
#   bash tests/contract/run.sh claude gemini   # a subset (one CI job per target)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"
# shellcheck source=tests/contract/_common.sh
source "$REPO_ROOT/tests/contract/_common.sh"

harness_require jq git

PLATFORMS=(claude cursor codex gemini opencode)
[ "$#" -gt 0 ] && PLATFORMS=("$@")

for p in "${PLATFORMS[@]}"; do
  f="$REPO_ROOT/tests/contract/$p.sh"
  if [ ! -f "$f" ]; then bad "platform $p" "no contract suite at $f"; continue; fi
  # shellcheck source=/dev/null
  source "$f"
done

harness_summary
