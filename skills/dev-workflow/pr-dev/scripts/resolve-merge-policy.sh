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
#     "merge_method_source": "<which rule decided>",
#     "delete_branch": true | false,
#     "delete_branch_source": "<which rule decided>",
#     "warnings": [ "..." ],
#     "base_branch": "<the PR's base branch>" | null,
#     "requires_review": true | false | null,
#     "required_checks": [ "..." ] | null,
#     "strict_branch_update": true | false | null,
#     "protection_source": "classic" | "rulesets" | "classic+rulesets" | "none" | null,
#     "admin_bypass_available": true | false | null
#   }
#
# strict_branch_update mirrors branch protection's "Require branches to be up
# to date before merging". true = strict: the head must be rebased/updated onto
# the base before merge. false = loose: a behind-but-mergeable branch is fine
# and must NOT be churned with pointless base merges.
#
# PROTECTION IS READ FROM TWO PLACES, NOT ONE
#   GitHub has two independent protection systems: classic branch protection
#   (`/repos/{o}/{r}/branches/{b}/protection`) and rulesets
#   (`/repos/{o}/{r}/rulesets`, whose *effective* result for one branch is
#   `/repos/{o}/{r}/rules/branches/{b}`). A repository can use either, both, or
#   neither, and they do not shadow each other -- the effective protection is
#   the UNION.
#
#   This script used to read only the classic endpoint. On a ruleset-governed
#   repository that endpoint returns 404 "Branch not protected", and the script
#   reported `required_checks: []`, `requires_review: false`,
#   `strict_branch_update: null` for a branch that in fact required nine status
#   checks and a pull request. Every downstream decision then ran on that: the
#   readiness gate had no required checks to wait for, and the loose/strict
#   branch-freshness rule silently took the loose path.
#
#   The head-branch read was the same bug with a worse consequence: a
#   ruleset-protected head read as unprotected, so `delete_branch` came back
#   true and pr-dev would delete a governed branch after merge -- not
#   recoverable from the PR.
#
#   Observed on this repository 2026-08-31: PR & CI + Safety rulesets active on
#   ~DEFAULT_BRANCH, classic protection absent. Fixed by reading both and
#   unioning; `protection_source` records which sources actually answered so a
#   wrong reading is visible rather than inferred.
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

WARNINGS=()
warn() { WARNINGS+=("$1"); }

# A JSON reader is a hard prerequisite for honouring any policy file. Without
# one, the defaults below are still emitted — but the caller is told that the
# policy files were never opened, instead of being handed a default dressed up
# as a decision. (json_get itself runs inside a command substitution, so it
# cannot record this: the check belongs here, once.)
if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  warn "neither jq nor python3 is on PATH — .dev-files/policy.json and objective.json were NOT read; every field below is a default, not a resolved policy"
fi

# json_get <file> <dotted.path>
#
# NOTE: deliberately not using jq's `//` — it treats `false` as absent, which is
# exactly the value a "do not auto-merge" policy needs to express.
#
# Without jq this used to return 1, which is indistinguishable from "the key is
# absent" — so on a machine with no jq the policy file was silently discarded
# and the built-in default won while the caller was told the file had been
# honoured. It now falls back to python3, and if neither exists it says so in
# `warnings` rather than pretending the file was read.
json_get() {
  local file="$1" path="$2" v=""
  [[ -f "$file" ]] || return 1
  if command -v jq >/dev/null 2>&1; then
    v="$(jq -r ".$path" "$file" 2>/dev/null || true)"
  elif command -v python3 >/dev/null 2>&1; then
    v="$(JSON_PATH="$path" python3 -c '
import json, os, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for k in os.environ["JSON_PATH"].split("."):
    if not isinstance(d, dict) or k not in d:
        sys.exit(0)
    d = d[k]
print("null" if d is None else ("true" if d is True else ("false" if d is False else d)))
' "$file" 2>/dev/null || true)"
  else
    return 1
  fi
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
PROTECTION_SOURCE=null
ADMIN=null
MERGE_METHOD=squash
MERGE_METHOD_SOURCE="default: squash (repository merge methods not readable)"
DELETE_BRANCH=true
DELETE_BRANCH_SOURCE="default: delete the head branch after merge (head-branch protection not readable)"

if command -v gh >/dev/null 2>&1; then
  # allow_auto_merge is REST-only — `gh repo view --json` has no such field.
  REPO_JSON="$(gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed,deleteBranchOnMerge,viewerPermission 2>/dev/null || echo '{}')"
  REST_JSON="$(gh api 'repos/{owner}/{repo}' 2>/dev/null || echo '{}')"
  if command -v jq >/dev/null 2>&1; then
    case "$(jq -r '.allow_auto_merge' <<<"$REST_JSON" 2>/dev/null || echo null)" in
      true) AUTO_MERGE_SUPPORTED=true ;;
      false) AUTO_MERGE_SUPPORTED=false ;;
    esac
    # Merge method: the first method the repository actually ALLOWS. All three
    # flags were already fetched two lines above and only squashMergeAllowed was
    # consulted — so a repo that permits merge and rebase but not squash landed
    # on `merge` by luck, and a rebase-only repo was handed a method it forbids.
    # `// "unknown"` cannot be used here: jq's alternative operator treats
    # `false` as absent, and `false` is precisely the value that matters — the
    # same trap json_get above documents. Test for the key instead.
    flag_of() { jq -r --arg k "$1" 'if has($k) and .[$k] != null then .[$k] else "unknown" end' <<<"$REPO_JSON"; }
    SQ="$(flag_of squashMergeAllowed)"
    MC="$(flag_of mergeCommitAllowed)"
    RB="$(flag_of rebaseMergeAllowed)"
    if [[ "$SQ" == true ]]; then
      MERGE_METHOD=squash;  MERGE_METHOD_SOURCE="repository allows squash"
    elif [[ "$MC" == true ]]; then
      MERGE_METHOD=merge;   MERGE_METHOD_SOURCE="repository forbids squash; allows merge commits"
    elif [[ "$RB" == true ]]; then
      MERGE_METHOD=rebase;  MERGE_METHOD_SOURCE="repository forbids squash and merge commits; allows rebase"
    elif [[ "$SQ" == false && "$MC" == false && "$RB" == false ]]; then
      MERGE_METHOD_SOURCE="repository reports NO merge method allowed — squash retained as a placeholder; GitHub will refuse the merge"
      warn "repository allows none of squash/merge/rebase — the merge cannot succeed until one is enabled"
    fi

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
      # --- classic branch protection -------------------------------------
      # `gh api` prints the error BODY to stdout on a 404 and still exits
      # non-zero, so `|| echo ''` leaves PROT holding {"message":"Branch not
      # protected"} -- non-empty, and indistinguishable from success by
      # emptiness alone. That is the same "absence read as an answer" mistake
      # this whole fix is about, so key on the EXIT STATUS.
      if PROT="$(gh api "repos/$OWNER_REPO/branches/$BASE/protection" 2>/dev/null)"; then :; else PROT=""; fi
      SRC_CLASSIC=false
      if [[ -n "$PROT" ]] && jq -e '.required_status_checks? // .required_pull_request_reviews? // empty' >/dev/null 2>&1 <<<"$PROT"; then
        SRC_CLASSIC=true
        # NOT `.strict // "null"`. jq's alternative operator treats **false**
        # as empty, so `false // "null"` yields "null" -- meaning a classic
        # repository with strict explicitly OFF reported
        # `strict_branch_update: null` rather than `false`, and pr-dev then
        # took the "unknown -> treat as loose" path by accident instead of by
        # reading the setting. Same answer here, wrong reason, and it would
        # have been the opposite answer had the default been strict.
        case "$(jq -r '(.required_status_checks.strict) as $v | if $v == true then "true" elif $v == false then "false" else "null" end' <<<"$PROT")" in
          true) STRICT=true ;;
          false) STRICT=false ;;
        esac
        # An approval count of 0 means "a PR is required", not "a review is
        # required" -- treating the block's mere presence as requires_review
        # makes pr-dev wait for an approval that nothing will ever demand.
        CLASSIC_APPROVALS="$(jq -r '.required_pull_request_reviews.required_approving_review_count // 0' <<<"$PROT" 2>/dev/null || echo 0)"
        if [[ "${CLASSIC_APPROVALS:-0}" -gt 0 ]]; then REQUIRES_REVIEW=true; else REQUIRES_REVIEW=false; fi
        CHECKS="$(jq -c '.required_status_checks.contexts // []' <<<"$PROT" 2>/dev/null || true)"
        [[ -n "$CHECKS" ]] && REQUIRED_CHECKS="$CHECKS"
      fi

      # --- rulesets (the effective rules for this one branch) --------------
      # `/rules/branches/<b>` is the resolved union of every ruleset that
      # matches the branch, so no ruleset conditions have to be evaluated here.
      # An empty array is a real answer ("no rules apply"), distinct from a
      # failed call -- so an API error must NOT be read as "unprotected".
      if RULES="$(gh api "repos/$OWNER_REPO/rules/branches/$BASE" 2>/dev/null)"; then :; else RULES=""; fi
      SRC_RULES=false
      # A successful call returning [] means "no rules apply" -- a real answer,
      # but not a source of protection. Counting it would label a purely
      # classic repo "classic+rulesets" and imply rules that do not exist.
      if [[ -n "$RULES" ]] && jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$RULES"; then
        SRC_RULES=true

        R_STRICT="$(jq -r 'map(select(.type=="required_status_checks"))|map(.parameters.strict_required_status_checks_policy // false)|any' <<<"$RULES" 2>/dev/null || echo false)"
        # Union semantics: strict from EITHER source means strict.
        if [[ "$R_STRICT" == "true" ]]; then
          STRICT=true
        elif [[ "$STRICT" == "null" ]] && jq -e 'map(select(.type=="required_status_checks"))|length > 0' >/dev/null 2>&1 <<<"$RULES"; then
          STRICT=false
        fi

        R_APPROVALS="$(jq -r '[.[]|select(.type=="pull_request")|.parameters.required_approving_review_count // 0]|max // 0' <<<"$RULES" 2>/dev/null || echo 0)"
        if [[ "${R_APPROVALS:-0}" -gt 0 ]]; then
          REQUIRES_REVIEW=true
        elif [[ "$REQUIRES_REVIEW" == "null" ]] && jq -e 'map(select(.type=="pull_request"))|length > 0' >/dev/null 2>&1 <<<"$RULES"; then
          REQUIRES_REVIEW=false
        fi

        R_CHECKS="$(jq -c '[.[]|select(.type=="required_status_checks")|.parameters.required_status_checks[]?|.context]' <<<"$RULES" 2>/dev/null || echo '[]')"
        if [[ -n "$R_CHECKS" && "$R_CHECKS" != "[]" ]]; then
          if [[ "$REQUIRED_CHECKS" == "null" ]]; then
            REQUIRED_CHECKS="$R_CHECKS"
          else
            REQUIRED_CHECKS="$(jq -cn --argjson a "$REQUIRED_CHECKS" --argjson b "$R_CHECKS" '$a + $b | unique')"
          fi
        elif [[ "$REQUIRED_CHECKS" == "null" ]]; then
          REQUIRED_CHECKS='[]'
        fi
      fi

      if   [[ "$SRC_CLASSIC" == true && "$SRC_RULES" == true ]]; then PROTECTION_SOURCE='"classic+rulesets"'
      elif [[ "$SRC_CLASSIC" == true ]]; then PROTECTION_SOURCE='"classic"'
      elif [[ "$SRC_RULES"   == true ]]; then PROTECTION_SOURCE='"rulesets"'
      else PROTECTION_SOURCE='"none"'
      fi
    fi
    # Delete-branch: NOT unconditionally true. "Always delete the remote branch"
    # is right for a throwaway feature branch and wrong for a governed head (a
    # release branch, a shared integration branch) — and deleting one is not
    # recoverable from the PR. Protection on the head branch is the fact to read.
    HEAD_REF="$(gh pr view "$PR" --json headRefName --jq .headRefName 2>/dev/null || true)"
    if [[ -n "$HEAD_REF" && -n "$OWNER_REPO" ]]; then
      # Both protection systems again, and here the classic-only read was
      # actively dangerous: a ruleset-protected head answered 404 and became
      # "unprotected — safe to delete", so pr-dev would delete a governed
      # branch after merge. Deleting is not recoverable from the PR.
      #
      # The classic endpoint returning non-zero is treated as "no classic
      # protection", which is what it means in practice (404 "Branch not
      # protected"). Escalating every non-zero to "unknown" was tried and is
      # wrong: it would fire the fail-closed path on essentially every
      # repository and stop deleting ordinary feature branches. The rules
      # endpoint is the one that must answer — an ARRAY (even empty) is a real
      # statement about ruleset protection, an error is not, and only that
      # error keeps the branch.
      HEAD_CLASSIC_PROTECTED=false
      gh api "repos/$OWNER_REPO/branches/$HEAD_REF/protection" >/dev/null 2>&1 && HEAD_CLASSIC_PROTECTED=true

      if HEAD_RULES_JSON="$(gh api "repos/$OWNER_REPO/rules/branches/$HEAD_REF" 2>/dev/null)"; then :; else HEAD_RULES_JSON=""; fi
      HEAD_RULES=unknown
      if [[ -n "$HEAD_RULES_JSON" ]] && jq -e 'type == "array"' >/dev/null 2>&1 <<<"$HEAD_RULES_JSON"; then
        if jq -e 'length > 0' >/dev/null 2>&1 <<<"$HEAD_RULES_JSON"; then
          HEAD_RULES=protected
        else
          HEAD_RULES=unprotected
        fi
      fi

      if [[ "$HEAD_CLASSIC_PROTECTED" == true || "$HEAD_RULES" == protected ]]; then
        DELETE_BRANCH=false
        if [[ "$HEAD_CLASSIC_PROTECTED" == true ]]; then
          DELETE_BRANCH_SOURCE="head branch $HEAD_REF is protected (classic branch protection) — not deleting it"
        else
          DELETE_BRANCH_SOURCE="head branch $HEAD_REF is protected (a ruleset applies to it) — not deleting it"
        fi
      elif [[ "$HEAD_RULES" == unprotected ]]; then
        DELETE_BRANCH=true
        DELETE_BRANCH_SOURCE="head branch $HEAD_REF is unprotected in both classic protection and rulesets — safe to delete after merge"
      else
        DELETE_BRANCH=false
        DELETE_BRANCH_SOURCE="head branch $HEAD_REF ruleset protection could not be read — keeping the branch rather than risking an unrecoverable delete"
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
if v="$(json_get "$POLICY_FILE" 'delivery.auto_merge')"; then
  case "$v" in
    true) AUTO_MERGE=enable; SOURCE=".dev-files/policy.json delivery.auto_merge=true" ;;
    false) AUTO_MERGE=skip; SOURCE=".dev-files/policy.json delivery.auto_merge=false" ;;
  esac
fi

if [[ -n "$OBJECTIVE_ID" ]]; then
  OBJ_FILE="$REPO_ROOT/.dev-files/objectives/$OBJECTIVE_ID/objective.json"
  if v="$(json_get "$OBJ_FILE" 'delivery.auto_merge')"; then
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

WARNINGS_JSON="[]"
if ((${#WARNINGS[@]})); then
  WARNINGS_JSON="["
  for i in "${!WARNINGS[@]}"; do
    [[ $i -gt 0 ]] && WARNINGS_JSON+=","
    WARNINGS_JSON+="\"${WARNINGS[$i]//\"/\\\"}\""
  done
  WARNINGS_JSON+="]"
fi

cat <<EOF
{
  "pr": $PR,
  "objective_id": $OBJ_JSON,
  "auto_merge": "$AUTO_MERGE",
  "auto_merge_source": "$SOURCE",
  "auto_merge_supported": $AUTO_MERGE_SUPPORTED,
  "merge_queue": $MERGE_QUEUE,
  "merge_method": "$MERGE_METHOD",
  "merge_method_source": "$MERGE_METHOD_SOURCE",
  "delete_branch": $DELETE_BRANCH,
  "delete_branch_source": "$DELETE_BRANCH_SOURCE",
  "warnings": $WARNINGS_JSON,
  "base_branch": $BASE_BRANCH,
  "requires_review": $REQUIRES_REVIEW,
  "required_checks": ${REQUIRED_CHECKS:-null},
  "strict_branch_update": $STRICT,
  "protection_source": $PROTECTION_SOURCE,
  "admin_bypass_available": $ADMIN
}
EOF
