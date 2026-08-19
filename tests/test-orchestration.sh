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

# The other `gh` double (tests/lib/fake-gh.sh) defines the same two names over
# different state. fake-agent.sh aborts if fake-gh loaded first; this catches the
# reverse order, where fake-gh would have quietly replaced these bindings. An
# unmeasured "no PR was created" is worse than a failing one.
if ! declare -f gh_calls 2>/dev/null | grep -q 'SIM_GHLOG'; then
  echo "FATAL: gh_calls is not the fake-agent binding — another gh double is loaded" >&2
  exit 1
fi
if ! declare -f fake_gh_install 2>/dev/null | grep -q 'GHSHIM\|bindir'; then
  echo "FATAL: fake_gh_install is not the fake-agent binding — another gh double is loaded" >&2
  exit 1
fi

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
