#!/usr/bin/env bash
# resolve-merge-policy.sh — resolve the delivery/merge policy for one PR.
#
# Usage:
#   resolve-merge-policy.sh [--repo <owner/name>] [--host <h>] <PR_NUMBER> [objective_id]
#   resolve-merge-policy.sh -h | --help
#
# Auto-merge is a PERMISSION, not an invariant and not a default. Whether pr-dev
# may run `gh pr merge --auto` is the action `pr.merge.auto`, and the only place
# that decides it is scripts/resolve-permission.sh (ADR 004 D4,
# docs/engineering/decisions/004-permission-levels.md). This script asks it and
# keeps computing what only GitHub can answer: capability, protection, merge
# method, merge queue and the head-branch delete. auto_merge is "enable" only
# when BOTH hold:
#
#   - resolve-permission.sh --action pr.merge.auto --target <owner/repo#N> says
#     allow (exit 0, parseable JSON), and
#   - the repository reports allow_auto_merge: true.
#
# Everything else is "skip", and auto_merge_source names the rule that decided.
# The default -- no configuration anywhere -- is skip: auto-merge is OFF unless
# configured (core/policies/safety.md). The legacy inputs are the resolver's:
# TAMIRS_AUTO_MERGE=always grants nothing (a warning names the setting),
# =never denies (and is also honoured here, before the resolver runs); an
# objective's delivery.auto_merge=false denies and true grants nothing;
# .dev-files/policy.json is read tighten-only. A resolver that is missing,
# exits non-zero or prints something unparseable is a skip (fail closed, D4).
#
# --host names the agent host (claude | codex | cursor | gemini | opencode) and
# is passed to the resolver, which needs it before a host option store may set
# the level. Without it a store can only lower the level.
#
# The resolver is found from THIS file's own location (<plugin root>/scripts/),
# never from the environment, so the installed plugin cache resolves its own copy.
#
# Output: one JSON object on stdout. Always exits 0 — an unresolvable field
# becomes "unknown" so the caller degrades explicitly instead of guessing.
#
#   {
#     "pr": 42,
#     "objective_id": "auth-system" | null,
#     "auto_merge": "enable" | "skip",
#     "auto_merge_source": "<which rule decided>",
#     "auto_merge_verdict": "allow" | "ask" | "deny" | "error" | "not-asked",
#     "auto_merge_allow_with": "<durable setting that would allow it>" | null,
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
# THE UNATTENDED PRECONDITION
#   At the unattended level pr.merge.auto is allowed only while its catalog
#   precondition pinned_check_or_review_and_no_protected_paths holds (D1, SR
#   S-13). The protection read below is the only place that knows, so this
#   script establishes it and passes --cond ...=true|false; when a read failed
#   it passes nothing, and an unestablished precondition never holds.
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
  sed -n '2,59p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

# --repo <owner/name> pins the repository. Every `gh` call below otherwise
# resolves it from the CURRENT DIRECTORY, which is invisible and silently wrong
# when the cwd is not the repo you mean: the same PR number in a sibling
# checkout is a real, plausible-looking, completely unrelated pull request.
# `gh` honours GH_REPO for resolution, so exporting it once pins every call --
# including `gh api repos/{owner}/{repo}`.
PR=""
OBJECTIVE_ID=""
HOST_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      case "${2:-}" in
        */*) export GH_REPO="$2" ;;
        *) printf 'error: --repo expects <owner>/<name>, got %s\n' "${2:-}" >&2; exit 2 ;;
      esac
      shift 2 ;;
    --repo=*)
      case "${1#--repo=}" in
        */*) export GH_REPO="${1#--repo=}" ;;
        *) printf 'error: --repo expects <owner>/<name>, got %s\n' "${1#--repo=}" >&2; exit 2 ;;
      esac
      shift ;;
    --host) HOST_ARG="${2:-}"; shift 2 || shift ;;
    --host=*) HOST_ARG="${1#--host=}"; shift ;;
    # Positionals: <PR_NUMBER> then [objective_id]. The objective used to be
    # read as "${2:-}" AFTER this loop had shifted every argument away, so it
    # was always empty and an objective's delivery.auto_merge=false never
    # reached the decision.
    *)
      if [[ -z "$PR" ]]; then PR="$1"
      elif [[ -z "$OBJECTIVE_ID" ]]; then OBJECTIVE_ID="$1"
      fi
      shift ;;
  esac
done
if [[ -z "$PR" ]]; then
  echo "ERROR: missing <PR_NUMBER>" >&2
  usage 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# The permission resolver, from this file's own location: <root>/skills/
# dev-workflow/pr-dev/scripts/ -> <root>/scripts/. Never from an environment
# variable: an environment that can name the resolver can name a fake one that
# always says allow.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || SCRIPT_DIR=""
RESOLVER="${SCRIPT_DIR:+$SCRIPT_DIR/../../../../scripts/resolve-permission.sh}"

WARNINGS=()
warn() { WARNINGS+=("$1"); }

# jstr <text> — a JSON string literal (quotes, backslashes, control chars).
jstr() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  s="${s//$'\t'/ }"
  printf '"%s"' "$s"
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
VIEWER_PERM=""
MERGE_METHOD=squash
MERGE_METHOD_SOURCE="default: squash (repository merge methods not readable)"
DELETE_BRANCH=true
DELETE_BRANCH_SOURCE="default: delete the head branch after merge (head-branch protection not readable)"
# The unattended precondition's two halves (THE UNATTENDED PRECONDITION above):
# unknown | true | false. Unknown is passed to the resolver as nothing at all.
PINNED_OR_REVIEW=unknown
PROTECTED_PATHS=unknown
OWNER_REPO=""

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

    VIEWER_PERM="$(jq -r '.viewerPermission // ""' <<<"$REPO_JSON")"
  fi

  BASE="$(gh pr view "$PR" --json baseRefName --jq .baseRefName 2>/dev/null || true)"
  if [[ -n "$BASE" ]]; then
    BASE_BRANCH="\"$BASE\""
    # An explicit --repo wins; `gh repo view` is the cwd-inferred fallback.
    OWNER_REPO="${GH_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)}"
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
        # Pinned source: a classic check whose app_id names one app (-1 or
        # null is "any source", which anything that can post a status meets).
        C_PINNED="$(jq -r '[.required_status_checks.checks[]? | select((.app_id // -1) > 0)] | length' <<<"$PROT" 2>/dev/null || echo 0)"
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
        R_PINNED="$(jq -r '[.[]|select(.type=="required_status_checks")|.parameters.required_status_checks[]?|select((.integration_id // 0) > 0)] | length' <<<"$RULES" 2>/dev/null || echo 0)"
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

      # The first half of the precondition: >= 1 pinned required check or
      # >= 1 required approving review. Established only when the rules
      # endpoint ANSWERED (an error there leaves rulesets unknown).
      if [[ "${C_PINNED:-0}" -gt 0 || "${R_PINNED:-0}" -gt 0 || "$REQUIRES_REVIEW" == true ]]; then
        PINNED_OR_REVIEW=true
      elif [[ -n "$RULES" ]]; then
        PINNED_OR_REVIEW=false
      fi

      # --- admin bypass eligibility ---------------------------------------
      # viewerPermission alone is NOT proof of a bypass: a caller can hold
      # ADMIN/MAINTAIN on the repo while no bypass_actor for the rulesets
      # that actually apply to THIS branch covers that role at all — that
      # produces a false "yes, use --admin" signal. Derive it from what
      # actually grants the exemption instead of the caller's general
      # permission level.
      ADMIN=false
      if [[ "$SRC_RULES" == true ]]; then
        # `/rules/branches/<b>` (already fetched as $RULES) names which
        # rulesets apply here; only a per-ruleset GET exposes bypass_actors
        # — the list endpoint used elsewhere in this repo's docs does not.
        RSIDS="$(jq -r '[.[].ruleset_id] | unique | .[]' <<<"$RULES" 2>/dev/null)"
        while IFS= read -r rid; do
          [[ -z "$rid" ]] && continue
          RS="$(gh api "repos/$OWNER_REPO/rulesets/$rid" 2>/dev/null)" || continue
          # Built-in RepositoryRole actor_id: 1=read 2=triage 3=write
          # 4=maintain 5=admin. bypass_mode "always" is unconditional;
          # "pull_request" only waives required reviews on THIS pr's own
          # approval, not the rest of the ruleset, so it does not make
          # --admin (which bypasses everything) valid and is not counted.
          while IFS=$'	' read -r atype aid amode; do
            [[ "$atype" != "RepositoryRole" || "$amode" != "always" ]] && continue
            case "$aid" in
              5) [[ "$VIEWER_PERM" == "ADMIN" ]] && ADMIN=true ;;
              4) [[ "$VIEWER_PERM" == "ADMIN" || "$VIEWER_PERM" == "MAINTAIN" ]] && ADMIN=true ;;
            esac
          done < <(jq -r '.bypass_actors[]? | [.actor_type, .actor_id, .bypass_mode] | @tsv' <<<"$RS" 2>/dev/null)
        done <<<"$RSIDS"
      elif [[ "$SRC_CLASSIC" == true ]]; then
        # Classic protection exempts admins from the block UNLESS
        # enforce_admins is explicitly on — the opposite default from
        # rulesets, where a bypass must be explicitly granted.
        ENFORCE_ADMINS="$(jq -r '.enforce_admins.enabled // false' <<<"$PROT" 2>/dev/null || echo false)"
        if [[ "$ENFORCE_ADMINS" == "false" && "$VIEWER_PERM" == "ADMIN" ]]; then ADMIN=true; fi
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

    # The second half of the precondition: the PR touches nothing that
    # governs merging itself (.github/workflows/**, CODEOWNERS, the project
    # permission file). gh lists at most 100 files, so a PR whose changedFiles
    # exceeds what was listed stays unknown rather than read as clean.
    if FILES_JSON="$(gh pr view "$PR" --json files,changedFiles 2>/dev/null)" && command -v jq >/dev/null 2>&1; then
      case "$(jq -r '
          (.files // null) as $f | (.changedFiles // null) as $n
          | if ($f | type) != "array" or ($n | type) != "number" or ($f | length) < $n then "unknown"
            elif any($f[]; (.path // "") | test("^(\\.github/workflows/|\\.tamirs-superpowers/)|^(\\.github/|docs/)?CODEOWNERS$")) then "true"
            else "false" end' <<<"$FILES_JSON" 2>/dev/null || echo unknown)" in
        true) PROTECTED_PATHS=true ;;
        false) PROTECTED_PATHS=false ;;
      esac
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
# pr.merge.auto is decided by scripts/resolve-permission.sh alone (ADR 004 D4).
# What stays here is the one input only GitHub can answer -- whether the
# repository allows auto-merge at all -- and the explicit TAMIRS_AUTO_MERGE=never
# kill switch, honoured before the resolver even runs so it holds when the
# resolver is missing. There is no default that enables: the old step 5
# ("enable when the repository allows it") is deleted (D4 row 7).
AUTO_MERGE=skip
SOURCE=""
VERDICT=not-asked
ALLOW_WITH=""

# OWNER_REPO is set only inside the base-branch block; fill it when that block
# did not run (no gh, or the PR's base could not be read).
if [[ -z "$OWNER_REPO" ]]; then
  OWNER_REPO="${GH_REPO:-}"
  if [[ -z "$OWNER_REPO" ]] && command -v gh >/dev/null 2>&1; then
    OWNER_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  fi
fi

if [[ "${TAMIRS_AUTO_MERGE:-}" == never ]]; then
  SOURCE="TAMIRS_AUTO_MERGE=never (explicit override)"
else
  PRECOND=unknown
  if [[ "$PINNED_OR_REVIEW" == true && "$PROTECTED_PATHS" == false ]]; then
    PRECOND=true
  elif [[ "$PINNED_OR_REVIEW" == false || "$PROTECTED_PATHS" == true ]]; then
    PRECOND=false
  fi

  # A bare PR number would make the resolver infer the repository from origin;
  # owner/repo#N is what the trust rule compares against (D3, SR S-15).
  TARGET="$PR"
  case "$OWNER_REPO" in */*) TARGET="$OWNER_REPO#$PR" ;; esac
  RARGS=(--action pr.merge.auto --skill pr-dev --target "$TARGET" --repo "$REPO_ROOT" --json)
  [[ -n "$OBJECTIVE_ID" ]] && RARGS+=(--objective "$OBJECTIVE_ID")
  [[ -n "$HOST_ARG" ]] && RARGS+=(--host "$HOST_ARG")
  [[ "$PRECOND" != unknown ]] && RARGS+=(--cond "pinned_check_or_review_and_no_protected_paths=$PRECOND")

  if [[ -z "$RESOLVER" || ! -f "$RESOLVER" ]]; then
    VERDICT=error
    SOURCE="permission resolver not found (scripts/resolve-permission.sh beside this plugin's skills/) — auto-merge skipped (fail closed, ADR 004 D4)"
    warn "scripts/resolve-permission.sh is missing: pr.merge.auto cannot be resolved, so auto-merge is off"
  else
    RC=0
    ROUT="$(bash "$RESOLVER" "${RARGS[@]}" 2>/dev/null)" || RC=$?
    # One parse, by the interpreter the resolver itself requires. -I -S: no
    # module from the working directory or site-packages is ever imported.
    PARSED=""
    if command -v python3 >/dev/null 2>&1; then
      PARSED="$(printf '%s' "$ROUT" | python3 -I -S -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
    assert isinstance(d, dict)
except Exception:
    sys.exit(1)
def one(v):
    return " ".join(str(v).split()) if v is not None else ""
aw = d.get("allow_with") or d.get("setting_that_would_allow") or {}
durable = aw.get("durable") if isinstance(aw, dict) else None
print(one(d.get("verdict", d.get("decision"))))
print(one(d.get("decided_by")))
print(one(d.get("reason")))
print(one(durable[0]) if isinstance(durable, list) and durable else "")
for w in d.get("warnings") or []:
    print(one(w))
' 2>/dev/null)" || PARSED=""
    fi
    if ! command -v python3 >/dev/null 2>&1; then
      VERDICT=error
      SOURCE="python3 is not on PATH, so the permission resolver cannot run — auto-merge skipped (fail closed, ADR 004 D4)"
      warn "python3 is not on PATH — the permission resolver could not run, so .dev-files/policy.json and objective.json were NOT read; auto-merge is off"
    elif [[ -z "$PARSED" ]]; then
      VERDICT=error
      SOURCE="permission resolver output unreadable (exit $RC) — auto-merge skipped (fail closed, ADR 004 D4)"
      warn "scripts/resolve-permission.sh printed no parseable verdict for pr.merge.auto (exit $RC)"
    else
      R_VERDICT="" R_BY="" R_REASON="" n=0
      while IFS= read -r line; do
        n=$((n + 1))
        case "$n" in
          1) R_VERDICT="$line" ;;
          2) R_BY="$line" ;;
          3) R_REASON="$line" ;;
          4) ALLOW_WITH="$line" ;;
          *) [[ -n "$line" ]] && warn "resolve-permission: $line" ;;
        esac
      done <<<"$PARSED"
      if [[ "$RC" -ne 0 ]]; then
        VERDICT=error
        SOURCE="permission resolver failed (exit $RC: ${R_REASON:-no reason}) — auto-merge skipped (fail closed, ADR 004 D4)"
      else
        case "$R_VERDICT" in
          allow|ask|deny) VERDICT="$R_VERDICT" ;;
          *) VERDICT=error ;;
        esac
        case "$VERDICT" in
          allow)
            if [[ "$AUTO_MERGE_SUPPORTED" == true ]]; then
              AUTO_MERGE=enable
              SOURCE="resolve-permission pr.merge.auto: allow (${R_BY:-no rule named})"
            elif [[ "$AUTO_MERGE_SUPPORTED" == false ]]; then
              SOURCE="resolve-permission pr.merge.auto: allow (${R_BY:-no rule named}) — overridden: repository does not allow auto-merge"
            else
              SOURCE="resolve-permission pr.merge.auto: allow (${R_BY:-no rule named}) — overridden: whether the repository allows auto-merge could not be read"
            fi ;;
          ask)
            SOURCE="resolve-permission pr.merge.auto: ask (${R_BY:-no rule named}) — auto-merge is off unless configured${ALLOW_WITH:+; to turn it on: $ALLOW_WITH}" ;;
          deny)
            SOURCE="resolve-permission pr.merge.auto: deny (${R_BY:-no rule named}${R_REASON:+: $R_REASON})" ;;
          *)
            SOURCE="permission resolver returned no verdict — auto-merge skipped (fail closed, ADR 004 D4)" ;;
        esac
      fi
    fi
  fi
fi

OBJ_JSON=null
[[ -n "$OBJECTIVE_ID" ]] && OBJ_JSON="\"$OBJECTIVE_ID\""

WARNINGS_JSON="[]"
if ((${#WARNINGS[@]})); then
  WARNINGS_JSON="["
  for i in "${!WARNINGS[@]}"; do
    [[ $i -gt 0 ]] && WARNINGS_JSON+=","
    WARNINGS_JSON+="$(jstr "${WARNINGS[$i]}")"
  done
  WARNINGS_JSON+="]"
fi

cat <<EOF
{
  "pr": $PR,
  "objective_id": $OBJ_JSON,
  "auto_merge": "$AUTO_MERGE",
  "auto_merge_source": $(jstr "$SOURCE"),
  "auto_merge_verdict": "$VERDICT",
  "auto_merge_allow_with": $( [[ -n "$ALLOW_WITH" ]] && jstr "$ALLOW_WITH" || printf null ),
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
