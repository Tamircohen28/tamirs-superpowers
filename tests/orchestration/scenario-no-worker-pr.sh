#!/usr/bin/env bash
# Scenario: the shipped skills say what the simulation proves.
#
# The simulation shows that a worker CAN finish without a PR. This file asserts
# that the shipped instructions REQUIRE it — because the workers in production are
# language models reading these files, and a simulation that passes against a
# SKILL.md telling the worker to open a PR would be measuring the harness rather
# than the product.
#
# Static, fast, and hermetic: it only reads files already in the repo.
# shellcheck shell=bash

# Fragment, not an entrypoint: sourced by tests/test-orchestration.sh. Run standalone it would die on
# the first helper call with an opaque 127, so say what to run instead.
if ! declare -f judge >/dev/null 2>&1; then
  printf 'This file is a test fragment, not an entrypoint.\nRun: bash tests/test-orchestration.sh\n' >&2
  exit 2
fi

section "shipped worker instructions forbid delivery"

WD="$REPO_ROOT/skills/dev-workflow/worker-dev/SKILL.md"
OD="$REPO_ROOT/skills/dev-workflow/orchestrate-dev/SKILL.md"
DD="$REPO_ROOT/skills/dev-workflow/deliver-dev/SKILL.md"

for f in "$WD" "$OD" "$DD"; do
  judge "$(basename "$(dirname "$f")")/SKILL.md exists" yes "$(exists "$f")"
done

wd="$(cat "$WD" 2>/dev/null)"
judge "worker-dev states it must not create a PR" yes "$(has "$wd" "gh pr create")"
judge "worker-dev routes PR creation to deliver-dev" yes "$(has "$wd" "deliver-dev")"
judge "worker-dev forbids auto-merge" yes "$(has "$wd" "auto-merge")"
judge "worker-dev ends at commit + handoff" yes "$(has "$wd" "handoff")"

# The only skill allowed to run `gh pr create` unconditionally is deliver-dev.
# start-dev is the compatibility facade and mentions it while delegating, so the
# assertion is on which skill OWNS the call, stated by deliver-dev itself.
judge "deliver-dev owns the single PR creation" yes "$(has "$(cat "$DD" 2>/dev/null)" "gh pr create")"
judge "orchestrate-dev delegates delivery rather than opening the PR itself" yes \
  "$(has "$(cat "$OD" 2>/dev/null)" "deliver-dev")"
judge "orchestrate-dev integrates onto ONE branch" yes "$(has "$(cat "$OD" 2>/dev/null)" "ONE branch")"

# No helper script a worker runs may reach GitHub's PR API.
worker_scripts="$REPO_ROOT/skills/dev-workflow/_shared/scripts"
offenders="$(grep -l 'gh pr create' "$worker_scripts"/*.sh 2>/dev/null || true)"
judge "no shared worker script calls 'gh pr create'" "" "$offenders"

merge_offenders="$(grep -l 'gh pr merge' "$worker_scripts"/objective-state.sh "$worker_scripts"/handoff.sh 2>/dev/null || true)"
judge "neither state script calls 'gh pr merge'" "" "$merge_offenders"
