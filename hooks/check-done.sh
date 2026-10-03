#!/usr/bin/env bash
# Stop hook (ADVISORY — never blocks, always exit 0).
#
# Reminds the agent to verify a definition-of-done when uncommitted code changes
# are sitting in the tree.
#
# WHY THIS IS TIER-AWARE
#   The original message asked for one thing regardless of who was stopping:
#   lint + typecheck + tests + green CI. For a WORKER that demand is wrong, and
#   wrong in a way that costs real work — a worker's contract ends at
#   commit+handoff, it has no PR and therefore no CI to be green, so the only
#   way to satisfy the reminder was to run delivery validation the worker was
#   never supposed to run (or to ignore the hook, which trains everyone to
#   ignore it). Tier 3 evidence is the integrator's and CI's job.
#
#   Tiers (see core/policies/validation.md):
#     0  edit-time   cheap syntax / formatter on touched files
#     1  worker      tests + lint/typecheck relevant to the changed code
#     2  integration full lint/typecheck/unit suite + combined-diff review
#     3  delivery    independent CI, cross-platform/build/security, release
#
# TIER RESOLUTION (first hit wins)
#   1. SUPERPOWERS_VALIDATION_TIER — explicit, set by the orchestrator
#   2. the active task's .validation_tier in the objective state
#   3. inferred from the branch: worker/* -> 1, objective/* -> 2
#   4. no tier context at all -> today's behavior, unchanged
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/objective-common.sh
source "${SCRIPT_DIR}/lib/objective-common.sh"

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
changed=$(git -C "$root" status --porcelain 2>/dev/null \
  | grep -cE '\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|sh)$' || true)

[ "${changed:-0}" -gt 0 ] || exit 0

# --- resolve the tier -------------------------------------------------------

normalize_tier() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    0|edit|edit-time)      echo 0 ;;
    1|worker)              echo 1 ;;
    2|integration)         echo 2 ;;
    3|delivery|ci|release) echo 3 ;;
    *)                     echo "" ;;
  esac
}

tier="$(normalize_tier "${SUPERPOWERS_VALIDATION_TIER:-}")"

if [ -z "$tier" ]; then
  objective_id="$(active_objective_id "$root" 2>/dev/null || true)"
  task_id="${SUPERPOWERS_TASK_ID:-}"
  if [ -n "$objective_id" ] && [ -n "$task_id" ] && command -v jq >/dev/null 2>&1; then
    task_file="$(objective_state_dir "$root" "$objective_id")/tasks/${task_id}.json"
    [ -f "$task_file" ] && tier="$(normalize_tier "$(jq -r '.validation_tier // empty' "$task_file" 2>/dev/null)")"
  fi
fi

if [ -z "$tier" ]; then
  branch="$(git -C "$root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if is_worker_branch "$branch"; then
    tier=1
  elif is_objective_branch "$branch"; then
    tier=2
  fi
fi

# --- speak to that tier -----------------------------------------------------

repo="$(basename "$root")"

# --- does this repo have CI at all? ----------------------------------------
# Tier 3 used to demand "CI is green (gh run list / gh pr checks)" from every
# repo. A repo with no CI configuration can never satisfy that, so the agent
# either blocks on a gate that will never turn green or invents a result. CI
# presence is an observable fact — read it, and say which evidence is actually
# available here.
ci_system=""
if [ -d "$root/.github/workflows" ] \
   && find "$root/.github/workflows" \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | grep -q .; then
  ci_system="GitHub Actions"
elif [ -f "$root/.gitlab-ci.yml" ];        then ci_system="GitLab CI"
elif [ -d "$root/.circleci" ];             then ci_system="CircleCI"
elif [ -d "$root/.buildkite" ];            then ci_system="Buildkite"
elif [ -f "$root/azure-pipelines.yml" ];   then ci_system="Azure Pipelines"
elif [ -f "$root/Jenkinsfile" ];           then ci_system="Jenkins"
fi

# The CI clause of the tier-3 / default reminder, phrased from what was found.
if [ -z "$ci_system" ]; then
  ci_clause="This repo has NO CI configuration (no .github/workflows, .gitlab-ci.yml, .circleci/, .buildkite/, azure-pipelines.yml or Jenkinsfile) — local lint/typecheck/tests are the whole gate. Do not wait for, cite, or invent a CI result here."
elif [ "$ci_system" = "GitHub Actions" ]; then
  ci_clause="Also confirm CI is green — this repo uses GitHub Actions, so cite 'gh run list' / 'gh pr checks'."
else
  ci_clause="Also confirm CI is green — this repo uses ${ci_system}; cite its result from that system (gh commands do not apply)."
fi

case "$tier" in
  0)
    printf '⚠ DoD reminder (tier 0, edit-time): %s changed code file(s) in '"'"'%s'"'"'. Confirm the touched files parse and are formatted. Do not run the full suite here.\n' \
      "$changed" "$repo" >&2
    ;;
  1)
    printf '⚠ DoD reminder (tier 1, worker): %s changed code file(s) in '"'"'%s'"'"'. Before handoff, run the tests and lint/typecheck RELEVANT TO YOUR CHANGE and cite the output, then commit. You are NOT expected to run the full repo suite or to show green CI — tier 2 (integration) and tier 3 (delivery/CI) own that. Failing to be green at tier 3 is not a tier-1 failure. End at commit + handoff, not at a PR.\n' \
      "$changed" "$repo" >&2
    ;;
  2)
    printf '⚠ DoD reminder (tier 2, integration): %s changed code file(s) in '"'"'%s'"'"'. Before declaring the objective integrated, run the full lint/typecheck/unit suite over the COMBINED work and review the combined diff — cite the output. Tier 3 (independent CI, cross-platform/build/security) still has the final word.\n' \
      "$changed" "$repo" >&2
    ;;
  3)
    printf '⚠ DoD reminder (tier 3, delivery): %s changed code file(s) in '"'"'%s'"'"'. Before claiming done, confirm lint/typecheck/tests pass. %s Do not assert success without evidence.\n' \
      "$changed" "$repo" "$ci_clause" >&2
    ;;
  *)
    # No tier context — the pre-objective default, byte-for-byte in intent.
    printf '⚠ DoD reminder: %s changed code file(s) in '"'"'%s'"'"'. Before claiming done, confirm lint/typecheck/tests pass. %s Do not assert success without evidence.\n' \
      "$changed" "$repo" "$ci_clause" >&2
    ;;
esac

exit 0
