#!/usr/bin/env bash
# resolve-merge-policy.sh — resolve the delivery/merge policy for one PR.
#
# Usage:
#   resolve-merge-policy.sh <PR_NUMBER> [objective_id]
#   resolve-merge-policy.sh -h | --help
#
# Auto-merge is a POLICY, not an invariant. This script answers "what is this
# repository and this user actually asking for?" so pr-dev never forces a merge
# mode against configuration. Precedence, highest first:
#
#   1. TAMIRS_AUTO_MERGE=always|never          (explicit user/session override)
#   2. .dev-files/objectives/<id>/objective.json  -> .delivery.auto_merge
#   3. .dev-files/policy.json                  -> .delivery.auto_merge
#   4. repository capability: allowAutoMerge / merge queue
#   5. documented default: enable auto-merge when the repository allows it
#
# Output: one JSON object on stdout. Always exits 0 — an unresolvable field
# becomes "unknown" so the caller degrades explicitly instead of guessing.
#
#   {
#     "pr": 42,
#     "objective_id": "auth-system" | null,
#     "auto_merge": "enable" | "skip",
#     "auto_merge_source": "<which rule decided>",
#     "auto_merge_supported": true | false | null,
#     "merge_queue": true | false | null,
#     "merge_method": "squash" | "merge" | "rebase",
#     "delete_branch": true | false,
#     "base_branch": "main" | null,
#     "requires_review": true | false | null,
#     "required_checks": [ "..." ] | null,
#     "strict_branch_update": true | false | null,
#     "admin_bypass_available": true | false | null
#   }
#
# strict_branch_update mirrors branch protection's "Require branches to be up
# to date before merging". true = strict: the head must be rebased/updated onto
# the base before merge. false = loose: a behind-but-mergeable branch is fine
# and must NOT be churned with pointless base merges.
set -euo pipefail

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

PR="${1:-}"
OBJECTIVE_ID="${2:-}"
if [[ -z "$PR" ]]; then
  echo "ERROR: missing <PR_NUMBER>" >&2
  usage 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

json_get() { # json_get <file> <jq-filter>
  # NOTE: deliberately not using jq's `//` — it treats `false` as absent, which
  # is exactly the value a "do not auto-merge" policy needs to express.
  [[ -f "$1" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local v
  v="$(jq -r "$2" "$1" 2>/dev/null || true)"
  [[ -n "$v" && "$v" != "null" ]] || return 1
  printf '%s' "$v"
}

# --- repository capabilities -------------------------------------------------
AUTO_MERGE_SUPPORTED=null
MERGE_QUEUE=null
BASE_BRANCH=null
REQUIRES_REVIEW=null
REQUIRED_CHECKS=null
STRICT=null
ADMIN=null
MERGE_METHOD=squash
# pr-dev always passes --delete-branch itself; the repo setting only decides
# whether GitHub would have done it anyway.
DELETE_BRANCH=true

if command -v gh >/dev/null 2>&1; then
  # allow_auto_merge is REST-only — `gh repo view --json` has no such field.
  REPO_JSON="$(gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed,deleteBranchOnMerge,viewerPermission 2>/dev/null || echo '{}')"
  REST_JSON="$(gh api 'repos/{owner}/{repo}' 2>/dev/null || echo '{}')"
  if command -v jq >/dev/null 2>&1; then
    case "$(jq -r '.allow_auto_merge' <<<"$REST_JSON" 2>/dev/null || echo null)" in
      true) AUTO_MERGE_SUPPORTED=true ;;
      false) AUTO_MERGE_SUPPORTED=false ;;
    esac
    [[ "$(jq -r '.squashMergeAllowed // "true"' <<<"$REPO_JSON")" == "false" ]] && MERGE_METHOD=merge
    case "$(jq -r '.viewerPermission // ""' <<<"$REPO_JSON")" in
      ADMIN|MAINTAIN) ADMIN=true ;;
      "") ADMIN=null ;;
      *) ADMIN=false ;;
    esac
  fi

  BASE="$(gh pr view "$PR" --json baseRefName --jq .baseRefName 2>/dev/null || true)"
  if [[ -n "$BASE" ]]; then
    BASE_BRANCH="\"$BASE\""
    OWNER_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
    if [[ -n "$OWNER_REPO" ]] && command -v jq >/dev/null 2>&1; then
      PROT="$(gh api "repos/$OWNER_REPO/branches/$BASE/protection" 2>/dev/null || echo '')"
      if [[ -n "$PROT" ]]; then
        case "$(jq -r '.required_status_checks.strict // "null"' <<<"$PROT")" in
          true) STRICT=true ;;
          false) STRICT=false ;;
        esac
        if jq -e '.required_pull_request_reviews' >/dev/null 2>&1 <<<"$PROT"; then
          REQUIRES_REVIEW=true
        else
          REQUIRES_REVIEW=false
        fi
        CHECKS="$(jq -c '.required_status_checks.contexts // []' <<<"$PROT" 2>/dev/null || true)"
        [[ -n "$CHECKS" ]] && REQUIRED_CHECKS="$CHECKS"
      fi
    fi
    # Merge queue presence: reported on the PR when the base has one configured.
    MQ="$(gh api graphql -f query="query{repository(owner:\"${OWNER_REPO%%/*}\",name:\"${OWNER_REPO##*/}\"){mergeQueue(branch:\"$BASE\"){id}}}" 2>/dev/null || true)"
    if [[ -n "$MQ" ]] && command -v jq >/dev/null 2>&1; then
      if [[ "$(jq -r '.data.repository.mergeQueue.id // "null"' <<<"$MQ")" == "null" ]]; then
        MERGE_QUEUE=false
      else
        MERGE_QUEUE=true
      fi
    fi
  fi
fi

# --- auto-merge decision -----------------------------------------------------
AUTO_MERGE=enable
SOURCE="default: enable when the repository allows auto-merge"

if [[ "$AUTO_MERGE_SUPPORTED" == "false" ]]; then
  AUTO_MERGE=skip
  SOURCE="repository does not allow auto-merge"
fi

POLICY_FILE="$REPO_ROOT/.dev-files/policy.json"
if v="$(json_get "$POLICY_FILE" '.delivery.auto_merge')"; then
  case "$v" in
    true) AUTO_MERGE=enable; SOURCE=".dev-files/policy.json delivery.auto_merge=true" ;;
    false) AUTO_MERGE=skip; SOURCE=".dev-files/policy.json delivery.auto_merge=false" ;;
  esac
fi

if [[ -n "$OBJECTIVE_ID" ]]; then
  OBJ_FILE="$REPO_ROOT/.dev-files/objectives/$OBJECTIVE_ID/objective.json"
  if v="$(json_get "$OBJ_FILE" '.delivery.auto_merge')"; then
    case "$v" in
      true) AUTO_MERGE=enable; SOURCE="objective $OBJECTIVE_ID delivery.auto_merge=true" ;;
      false) AUTO_MERGE=skip; SOURCE="objective $OBJECTIVE_ID delivery.auto_merge=false" ;;
    esac
  fi
fi

case "${TAMIRS_AUTO_MERGE:-}" in
  always) AUTO_MERGE=enable; SOURCE="TAMIRS_AUTO_MERGE=always (explicit override)" ;;
  never)  AUTO_MERGE=skip;   SOURCE="TAMIRS_AUTO_MERGE=never (explicit override)" ;;
esac

# A repository that forbids auto-merge wins over any request to enable it:
# asking for something the platform refuses is not a policy, it is an error.
if [[ "$AUTO_MERGE_SUPPORTED" == "false" && "$AUTO_MERGE" == "enable" ]]; then
  AUTO_MERGE=skip
  SOURCE="$SOURCE — overridden: repository does not allow auto-merge"
fi

OBJ_JSON=null
[[ -n "$OBJECTIVE_ID" ]] && OBJ_JSON="\"$OBJECTIVE_ID\""

cat <<EOF
{
  "pr": $PR,
  "objective_id": $OBJ_JSON,
  "auto_merge": "$AUTO_MERGE",
  "auto_merge_source": "$SOURCE",
  "auto_merge_supported": $AUTO_MERGE_SUPPORTED,
  "merge_queue": $MERGE_QUEUE,
  "merge_method": "$MERGE_METHOD",
  "delete_branch": $DELETE_BRANCH,
  "base_branch": $BASE_BRANCH,
  "requires_review": $REQUIRES_REVIEW,
  "required_checks": ${REQUIRED_CHECKS:-null},
  "strict_branch_update": $STRICT,
  "admin_bypass_available": $ADMIN
}
EOF
