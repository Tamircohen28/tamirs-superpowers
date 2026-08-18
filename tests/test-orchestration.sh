#!/usr/bin/env bash
# test-orchestration.sh — fake-agent simulation of the orchestration contract.
#
# REFACTOR-SPEC §22.5. No model calls, no network, no gh, no writes outside a
# temp dir. Workers are scripted stubs (tests/lib/fake-agent.sh) that produce the
# artefacts a real worker produces — a branch, a commit, a handoff — on command,
# including on command badly.
#
# What is being pinned, in one line each:
#   parallel-workers        three independent workers, and NO worker opens a PR
#   dependencies            a dependent task is never dispatched or integrated early
#   failures                a failure/scope-escape/block leaves the objective intact
#   conflict                conflicts are resolved by the integrator, on objective/*
#   review-retry            reviewers are read-only; retry is bounded to one
#   resume                  a fresh process rebuilds everything from disk
#   delivery                one objective produces exactly ONE PR
#   sequential-equivalence  the no-subagent path reaches the same final state
#   no-worker-pr            the shipped SKILL.md files require what the sim proves
#
# Usage: bash tests/test-orchestration.sh [scenario-name]...

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"
# shellcheck source=tests/lib/fake-agent.sh
source "$REPO_ROOT/tests/lib/fake-agent.sh"

harness_require jq git

SCENARIOS=(
  parallel-workers
  dependencies
  failures
  conflict
  review-retry
  resume
  delivery
  sequential-equivalence
  no-worker-pr
)

if [ "$#" -gt 0 ]; then SCENARIOS=("$@"); fi

for s in "${SCENARIOS[@]}"; do
  f="$REPO_ROOT/tests/orchestration/scenario-$s.sh"
  if [ ! -f "$f" ]; then bad "scenario $s" "no such scenario file: $f"; continue; fi
  # shellcheck source=/dev/null
  source "$f"
done

harness_summary
