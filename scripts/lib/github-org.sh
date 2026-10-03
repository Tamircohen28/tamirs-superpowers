#!/usr/bin/env bash
# github-org.sh — organization-level rulesets, classic-protection aggregation,
# and the derived approval count.
#
# WHY THIS FILE EXISTS
#   scripts/lib/github-common.sh speaks `repos/{owner}/{repo}/rulesets`. That is
#   the right abstraction for a personal account, where every repository is its
#   own island and the only way to hold nineteen of them to one policy is to
#   visit nineteen of them.
#
#   An organization is not that. `orgs/{org}/rulesets` carries
#   `conditions.repository_name` (or `repository_property`) targeting, so ONE
#   ruleset governs many repositories — including repositories that do not exist
#   yet. Changing the policy is then one write, not N, and a repo created
#   tomorrow is governed the moment it is created rather than the next time
#   somebody remembers to run a sweep. Copying a ruleset repo-by-repo across an
#   organization is not a smaller version of that; it is a different, worse
#   thing that drifts the moment anyone edits one copy.
#
#   So this file is not "github-common.sh but for orgs". It is the layer that
#   decides WHETHER org-level targeting is possible and preferable, and says
#   plainly why when it is not.
#
# SOURCING CONTRACT
#   Sourced, never executed, and only AFTER scripts/lib/github-common.sh — every
#   request here goes through `github_api`, and every classification is read
#   back through that library's file-backed accessors. Sourcing this alone gets
#   you undefined functions, not a fallback.
#
# PORTABILITY (rules/dev/user-facing-script-standards.md §3)
#   bash 3.2: no associative arrays, no `mapfile`, no `${var^^}`. No GNU-only
#   sed. Multi-record output is tab-separated lines, not arrays.
#
# STDIN (§4)
#   Nothing here reads stdin and nothing here prompts. Confirmation belongs to
#   the caller, which is the only layer that knows whether a human is present.
#
# WHAT THIS FILE WILL NEVER DO
#   delete an organization ruleset · edit one it did not render · weaken one
#   that is already stricter than canonical · translate a repository filter into
#   GitHub targeting patterns · treat a plan limitation as a permission problem.

# shellcheck shell=bash

# ---------------------------------------------------------------------------
# Org availability state
# ---------------------------------------------------------------------------
# Same subshell hazard github-common.sh documents for GITHUB_LAST_*: these get
# set inside `x="$(github_org_probe ...)"`, so the variable assignment dies with
# the subshell and only the file survives. Read them through the accessors.
#
#   GITHUB_ORG_AVAILABLE  yes | no
#   GITHUB_ORG_CLASS      ok | plan | permission | scope | org_policy
#                       | not_found | error
#   GITHUB_ORG_REASON     one human line, already phrased for a report
GITHUB_ORG_AVAILABLE=""
GITHUB_ORG_CLASS=""
GITHUB_ORG_REASON=""

_github_org_set() {
  GITHUB_ORG_AVAILABLE="$1"; GITHUB_ORG_CLASS="$2"; GITHUB_ORG_REASON="$3"
  local d; d="$(github_state_dir)"
  printf '%s' "$1" >"$d/org_available" 2>/dev/null
  printf '%s' "$2" >"$d/org_class"     2>/dev/null
  printf '%s' "$3" >"$d/org_reason"    2>/dev/null
  return 0
}

github_org_available() { cat "$GITHUB_STATE_DIR/org_available" 2>/dev/null || printf ''; }
github_org_class()     { cat "$GITHUB_STATE_DIR/org_class"     2>/dev/null || printf ''; }
github_org_reason()    { cat "$GITHUB_STATE_DIR/org_reason"    2>/dev/null || printf ''; }

# github_org_sync — repopulate the variables from the files, mirroring
# github_sync_state.
github_org_sync() {
  GITHUB_ORG_AVAILABLE="$(github_org_available)"
  GITHUB_ORG_CLASS="$(github_org_class)"
  GITHUB_ORG_REASON="$(github_org_reason)"
  return 0
}

# ---------------------------------------------------------------------------
# Probe
# ---------------------------------------------------------------------------
# github_org_probe <org>
#
#   0  organization rulesets are readable; the JSON array is on stdout
#   2  they are NOT available, for a reason that is not a bug and not an outage:
#      the org's plan, a missing scope, a permission, an org policy, or an org
#      this token cannot see. The caller degrades to per-repository policy and
#      says why. This is a DEGRADE, never a failure.
#   1  a real failure — no response, a 5xx, a body that is not an array.
#
# WHY PLAN-DETECTION IS A PROBE AND NOT A PLAN LOOKUP
#   `GET /orgs/{org}` returns `.plan.name`, and reading "free" would look like a
#   cleaner answer. It is not: the plan name is a billing fact, and whether this
#   token may read this org's rulesets right now depends additionally on the
#   token's scopes, the org's OAuth-app restrictions, SAML, and an IP allow
#   list. Asking the question we actually need answered — "can I read
#   orgs/X/rulesets" — answers all of them at once, in one call, and cannot be
#   wrong in the direction that matters. Measured 2026-08-19: ProductionMasterAI
#   (plan `team`) answers 200 with `[]`; SentinelAIOrg (plan `free`) answers 403
#   "Upgrade to GitHub Team to enable this feature."
#
# WHY THE MESSAGE IS INSPECTED BEFORE THE CLASS
#   github-common.sh classifies that 403 as `forbidden`, whose explanation is
#   "this token is not an admin of the repository" — which would send the user
#   to fix permissions they already have, for a wall that is billing. The 404
#   and 422 paths there already map "upgrade"/"not available" to `unsupported`;
#   the 403 path does not, and github-common.sh is not this file's to edit (see
#   session-files/requests/gh-org-rulesets.md). So the plan wording is tested
#   here, first, and only then the class.
github_org_probe() {
  local org="$1" out rc=0 low msg http

  [ -n "$org" ] || { _github_org_set no error "no organization name given"; return 1; }

  out="$(github_api GET "orgs/${org}/rulesets?per_page=100")" || rc=$?

  if [ "$rc" = "0" ]; then
    if ! printf '%s' "$out" | jq -e 'type == "array"' >/dev/null 2>&1; then
      _github_org_set no error "GET orgs/${org}/rulesets did not return a JSON array"
      github_fail bad_response "GET orgs/${org}/rulesets did not return a JSON array"
      return 1
    fi
    _github_org_set yes ok "organization rulesets are readable"
    printf '%s' "$out"
    return 0
  fi

  github_sync_state
  msg="$(github_last_error)"
  http="$(github_last_http)"
  low="$(github_lower "$msg")"

  # Plan first, on the wording, regardless of which status code carried it.
  case "$low" in
    *upgrade*|*"not available"*|*"enable this feature"*)
      _github_org_set no plan \
        "organization ruleset management is unavailable on this organization's plan; falling back to per-repository policy (HTTP ${http:-?}: ${msg})"
      return 2 ;;
  esac

  case "$(github_last_class)" in
    insufficient_scope)
      _github_org_set no scope \
        "reading organization rulesets needs the admin:org scope; falling back to per-repository policy (run: gh auth refresh -h github.com -s admin:org)"
      return 2 ;;
    forbidden)
      _github_org_set no permission \
        "this token is not an organization owner of ${org}; falling back to per-repository policy (HTTP ${http:-403}: ${msg})"
      return 2 ;;
    org_policy)
      _github_org_set no org_policy \
        "blocked by an organization or enterprise policy; falling back to per-repository policy (HTTP ${http:-403}: ${msg})"
      return 2 ;;
    unsupported)
      _github_org_set no plan \
        "organization ruleset management is unavailable on this organization's plan; falling back to per-repository policy (HTTP ${http:-?}: ${msg})"
      return 2 ;;
    not_found)
      _github_org_set no not_found \
        "organization ${org} does not exist or this token cannot see it; falling back to per-repository policy"
      return 2 ;;
    unauthenticated)
      _github_org_set no error "gh is not authenticated"
      return 1 ;;
  esac

  _github_org_set no error "$(github_explain)"
  return 1
}

# ---------------------------------------------------------------------------
# Reads — mirroring github-common.sh's repository-level shape
# ---------------------------------------------------------------------------

# github_org_list_rulesets <org> — JSON array on stdout. Same return codes as
# github_org_probe, because listing IS the probe: there is no cheaper question.
github_org_list_rulesets() { github_org_probe "$1"; }

# github_org_get_ruleset <org> <id> — full detail, with rules and bypass actors.
github_org_get_ruleset() {
  github_api_json GET "orgs/$1/rulesets/$2" 'type == "object" and has("rules")'
}

# github_org_ruleset_id <org> <name> — id by name, empty when absent.
github_org_ruleset_id() {
  local list rc=0
  list="$(github_org_list_rulesets "$1")" || rc=$?
  [ "$rc" = "0" ] || return "$rc"
  printf '%s' "$list" | jq -r --arg n "$2" '[.[] | select(.name == $n) | .id] | first // empty'
}

# github_org_get_ruleset_by_name <org> <name>
#   0 detail JSON on stdout · 2 absent · 1 failure · 3 org rulesets unavailable
# Absent and unavailable are different answers and a caller must branch on them:
# "the org has no such ruleset" is a plan to create, "the org cannot have
# rulesets" is a fallback to per-repository.
github_org_get_ruleset_by_name() {
  local id rc=0
  id="$(github_org_ruleset_id "$1" "$2")" || rc=$?
  [ "$rc" = "2" ] && return 3
  [ "$rc" = "0" ] || return 1
  if [ -z "$id" ]; then
    github_ok
    return 2
  fi
  github_org_get_ruleset "$1" "$id"
}

# ---------------------------------------------------------------------------
# Rendering an organization ruleset
# ---------------------------------------------------------------------------
# github_org_render_ruleset <policy-file> <ruleset-key> <org> [include-pattern...]
#
# The canonical ruleset, rendered once for the whole organization, with
# `conditions.repository_name` added so it targets many repositories from one
# definition. With no include pattern the target is `~ALL`.
#
# TWO THINGS DELIBERATELY DO NOT SURVIVE THE TRIP UP TO ORG LEVEL, AND BOTH ARE
# THE POINT OF THIS COMMENT:
#
#   1. Required status-check CONTEXTS. `required_checks.source` in the policy is
#      `per_repository` and `default_contexts` is empty, because a context is a
#      CI job NAME and a name that does not exist in a repository blocks every
#      pull request in it forever. Job names are not uniform across an org, so
#      there is no honest org-wide context list to assert. The renderer inherits
#      github_policy_render_ruleset's rule — a required_status_checks rule that
#      resolves to zero contexts is DROPPED, not sent gating on nothing — which
#      means the org copy of `Default Branch - PR & CI` carries linear history
#      and the pull-request rule but no check gate. That is not a bug and it is
#      not something to work around by inventing contexts: the per-repository
#      sweep is what supplies contexts, and org-level targeting does not replace
#      it for that one rule. Say so in the report rather than letting a reader
#      conclude the org ruleset covers everything.
#
#   2. Repository OVERRIDES. `repositories.<owner/repo>` in the policy is
#      per-repository by construction. The org render is deliberately given the
#      ORG name where the renderer expects `owner/repo`, so no override key can
#      match and the canonical defaults are what get rendered. Rendering one
#      repository's overrides into a ruleset that governs the whole org would
#      quietly impose one repo's exceptions on every other repo.
github_org_render_ruleset() {
  local policy="$1" key="$2" org="$3"
  shift 3

  local base include_json
  base="$(github_policy_render_ruleset "$policy" "$key" "$org")" || return 1

  if [ "$#" -eq 0 ]; then
    include_json='["~ALL"]'
  else
    include_json="$(printf '%s\n' "$@" | jq -R . | jq -s -c .)"
  fi

  printf '%s' "$base" | jq --argjson inc "$include_json" '
      .conditions = ((.conditions // {}) + {
        repository_name: { include: $inc, exclude: [], protected: false }
      })
    ' | github_ruleset_normalize
}

# github_org_render_payload_file <policy> <key> <org> <out-file> [include...]
github_org_render_payload_file() {
  local policy="$1" key="$2" org="$3" out="$4"
  shift 4
  local rendered
  rendered="$(github_org_render_ruleset "$policy" "$key" "$org" "$@")" || return 1
  printf '%s\n' "$rendered" >"$out"
}

# ---------------------------------------------------------------------------
# The weakening guard, org edition
# ---------------------------------------------------------------------------
# github_org_weakens <live-json-file> <desired-json-file>
#
# One human line per way the desired org ruleset is a WEAKER control than the
# one already live; returns 0 when it printed any. Same contract as
# `policy_weakens` in scripts/github-policy.sh, plus one dimension that only
# exists up here: REPOSITORY COVERAGE. Narrowing `conditions.repository_name`
# from `~ALL` to a list silently un-governs every repository that falls out of
# the list, and that is invisible in a rules diff — the rules are identical, the
# set of repositories they apply to is not.
#
# The rule dimensions below are the same jq as `policy_weakens`. That
# duplication is deliberate and temporary: this library must be sourceable and
# testable on its own, and scripts/lib/github-common.sh (where one shared copy
# belongs) is owned elsewhere in this change. Requested there — see
# session-files/requests/gh-org-rulesets.md. If you fix one of these, fix both.
github_org_weakens() {
  jq -r -n --slurpfile live "$1" --slurpfile desired "$2" '
    def ctxs:
      ((.rules // []) | map(select(.type == "required_status_checks"))
       | map(.parameters.required_status_checks // []) | add // [])
      | map(.context) | unique;
    def rule($t): ((.rules // []) | map(select(.type == $t)) | first);
    def types:   ((.rules // []) | map(.type) | unique);
    def pr($k):  (rule("pull_request").parameters[$k]);
    def cover:   (.conditions.repository_name.include // []);
    def excl:    (.conditions.repository_name.exclude // []);

    ($live[0]) as $l | ($desired[0]) as $d |
    (($l | ctxs) - ($d | ctxs))   as $gone_ctx |
    (($l | types) - ($d | types)) as $gone_rules |
    [
      (if (($l | cover) | index("~ALL")) != null and (($d | cover) | index("~ALL")) == null
       then "would narrow repository coverage from every repository in the organization to: "
            + (($d | cover) | join(", ")) else empty end),

      (if ((($d | excl) - ($l | excl)) | length) > 0
       then "would stop governing repositories matching: " + ((($d | excl) - ($l | excl)) | join(", ")) else empty end),

      (if ($gone_ctx | length) > 0
       then "would remove required status check(s): " + ($gone_ctx | join(", ")) else empty end),

      (if ($gone_rules | length) > 0
       then "would remove protection rule(s) already in force: " + ($gone_rules | join(", ")) else empty end),

      (if (($l | rule("required_status_checks").parameters.strict_required_status_checks_policy) == true)
          and (($d | rule("required_status_checks").parameters.strict_required_status_checks_policy) != true)
       then "would turn OFF strict \"branch must be up to date\", which this organization currently enforces" else empty end),

      (if (($l | pr("required_approving_review_count")) // 0) > (($d | pr("required_approving_review_count")) // 0)
       then "would lower required approving reviews from "
            + (($l | pr("required_approving_review_count")) | tostring) + " to "
            + ((($d | pr("required_approving_review_count")) // 0) | tostring) else empty end),

      (if (($l | pr("required_review_thread_resolution")) == true)
          and (($d | pr("required_review_thread_resolution")) != true)
       then "would stop requiring review threads to be resolved" else empty end),

      (if (($l | pr("require_code_owner_review")) == true) and (($d | pr("require_code_owner_review")) != true)
       then "would stop requiring a CODEOWNERS review" else empty end),

      (if (($l | pr("require_last_push_approval")) == true) and (($d | pr("require_last_push_approval")) != true)
       then "would stop requiring approval of the last push" else empty end),

      (if (($l | pr("dismiss_stale_reviews_on_push")) == true) and (($d | pr("dismiss_stale_reviews_on_push")) != true)
       then "would stop dismissing stale reviews on push" else empty end),

      (if ($l.enforcement == "active") and ($d.enforcement != "active")
       then "would drop enforcement from active to " + ($d.enforcement // "null") else empty end),

      (if (($l.conditions.ref_name.include // []) | index("~DEFAULT_BRANCH")) != null
          and (($d.conditions.ref_name.include // []) | index("~DEFAULT_BRANCH")) == null
       then "would stop targeting the default branch" else empty end)
    ] | .[]
  ' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Existing org policy that is STRICTER than canonical
# ---------------------------------------------------------------------------
# github_org_conflicts <org>
#
# One line per active organization ruleset that already imposes something
# canonical does not. Returns 0 always when the org could be read; the caller
# decides what a conflict means. An org ruleset stricter than the policy is
# never edited, never weakened and never routed around — it is reported and the
# organization is left alone. There is no flag that overrides this.
#
# Returns 3 when org rulesets are unavailable (nothing to conflict with).
github_org_conflicts() {
  local org="$1" list ids id detail rc=0
  list="$(github_org_list_rulesets "$org")" || rc=$?
  [ "$rc" = "2" ] && return 3
  [ "$rc" = "0" ] || return 1

  ids="$(printf '%s' "$list" | jq -r '
    .[] | select((.target // "branch") == "branch")
        | select((.enforcement // "active") == "active")
        | .id')"

  for id in $ids; do
    if ! detail="$(github_org_get_ruleset "$org" "$id")"; then
      printf 'organization ruleset %s is active and could not be read — %s\n' "$id" "$(github_explain)"
      continue
    fi
    printf '%s' "$detail" | jq -r '
      def rule($t): ((.rules // []) | map(select(.type == $t)) | first);
      . as $o |
      [
        (if (rule("required_status_checks").parameters.strict_required_status_checks_policy) == true
         then "requires strict \"branch must be up to date\"" else empty end),
        (if ((rule("pull_request").parameters.required_approving_review_count) // 0) > 0
         then "requires " + ((rule("pull_request").parameters.required_approving_review_count) | tostring)
              + " approving review(s)" else empty end),
        (if (rule("pull_request").parameters.require_code_owner_review) == true
         then "requires a CODEOWNERS review" else empty end),
        (if (rule("pull_request").parameters.require_last_push_approval) == true
         then "requires approval of the last push" else empty end),
        (if ((.rules // []) | map(.type) | index("required_signatures")) != null
         then "requires signed commits" else empty end),
        (if ((.rules // []) | map(.type) | index("required_deployments")) != null
         then "requires successful deployments" else empty end)
      ]
      | if length == 0 then empty
        else "organization ruleset \"" + ($o.name // "?") + "\" " + join("; ") end'
  done
  return 0
}

# ---------------------------------------------------------------------------
# Targeting decision
# ---------------------------------------------------------------------------
# github_org_targeting <org> <repo-count> <filters-active:yes|no>
#
# Prints tab-separated records and returns 0. This is the function that answers
# the question the whole file exists for.
#
#   mode<TAB>org | per_repo
#   reason<TAB><one human line>
#   covers<TAB><n>
#
# WHY A REPOSITORY FILTER FORCES per_repo
#   `--include` / `--exclude` are POSIX EREs matched against `owner/name`.
#   GitHub's `conditions.repository_name` patterns are fnmatch-style globs with
#   their own `~ALL` magic. `sandbox$` is a valid ERE and a valid literal glob
#   that matches nothing, so translating one into the other does not fail — it
#   silently changes WHICH repositories are governed, in the direction of
#   governing more of them than the operator asked for. There is no safe
#   automatic translation, so a filter means per-repository, and the reason is
#   printed rather than the behaviour being quietly different.
github_org_targeting() {
  local org="$1" n="${2:-0}" filters="${3:-no}"
  github_org_sync

  if [ "$(github_org_available)" != "yes" ]; then
    printf 'mode\tper_repo\n'
    printf 'reason\t%s\n' "$(github_org_reason)"
    printf 'covers\t%s\n' "$n"
    return 0
  fi

  if [ "$filters" = "yes" ]; then
    printf 'mode\tper_repo\n'
    printf 'reason\t%s\n' "a repository filter (--include/--exclude) is in effect. Those are POSIX EREs; GitHub's repository_name targeting takes globs, and translating between them would change which repositories are covered. Drop the filter to use one organization ruleset, or keep it and accept the per-repository sweep."
    printf 'covers\t%s\n' "$n"
    return 0
  fi

  printf 'mode\torg\n'
  printf 'reason\tone organization ruleset targeting repository_name ~ALL governs all %s repositories, and every repository created after it — change the policy once here instead of visiting %s repositories.\n' "$n" "$n"
  printf 'covers\t%s\n' "$n"
  return 0
}

# ---------------------------------------------------------------------------
# Writes — every one of these mutates governance for the whole organization
# ---------------------------------------------------------------------------
# The blast radius is larger than any repository-level write in this codebase:
# an org ruleset applies to repositories that do not exist yet. Nothing here
# prompts; the caller confirms, and scripts/github-policy.sh's LIVE-TARGET GATE
# applies to these exactly as it does to repository writes.

# github_org_create_ruleset <org> <payload-file>
github_org_create_ruleset() {
  github_api_json POST "orgs/$1/rulesets" 'has("id")' --input "$2"
}

# github_org_update_ruleset <org> <ruleset-id> <payload-file>
github_org_update_ruleset() {
  github_api_json PUT "orgs/$1/rulesets/$2" 'has("id")' --input "$3"
}

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
# github_org_verify <policy-file> <org>
#
# Read-only. One tab-separated record per canonical ruleset:
#   <key><TAB>up_to_date | absent | drifted | error
# Returns 0 when everything matches, 3 when anything is absent or drifted,
# 1 on a failure, 2 when org rulesets are unavailable on this organization.
github_org_verify() {
  local policy="$1" org="$2" key name rc worst=0 work
  work="$(mktemp -d)" || { github_fail unknown "could not create a temp dir"; return 1; }

  # `if ! cmd; then rc=$?` would record the INVERTED status (always 1), which is
  # exactly how "unavailable on this plan" would come to be reported as a
  # failure. Capture first, branch second.
  rc=0
  github_org_list_rulesets "$org" >"$work/list.json" || rc=$?
  if [ "$rc" != "0" ]; then
    rm -rf "$work"
    [ "$rc" = "2" ] && return 2
    return 1
  fi

  for key in $(jq -r '.rulesets[].key' "$policy"); do
    name="$(jq -r --arg k "$key" '.rulesets[] | select(.key == $k) | .name' "$policy")"
    if ! github_org_render_ruleset "$policy" "$key" "$org" >"$work/desired"; then
      printf '%s\terror\t%s\n' "$key" "$(github_explain)"
      worst=1
      continue
    fi
    local id
    id="$(jq -r --arg n "$name" '[.[] | select(.name == $n) | .id] | first // empty' "$work/list.json")"
    if [ -z "$id" ]; then
      printf '%s\tabsent\n' "$key"
      [ "$worst" -lt 3 ] && worst=3
      continue
    fi
    if ! github_org_get_ruleset "$org" "$id" | github_ruleset_normalize >"$work/live"; then
      printf '%s\terror\t%s\n' "$key" "$(github_explain)"
      worst=1
      continue
    fi
    # Bypass actors are organization-specific state, exactly as they are
    # repository-specific state at the repo level: who may merge around the
    # rules is a fact about the org's people, not a rule canonical can know.
    # Carry the live value across before comparing so a comparison never
    # proposes revoking somebody's key.
    jq --slurpfile live "$work/live" '.bypass_actors = (($live[0].bypass_actors) // [])' \
      "$work/desired" | github_ruleset_normalize >"$work/desired.patched"
    mv "$work/desired.patched" "$work/desired"

    if cmp -s "$work/desired" "$work/live"; then
      printf '%s\tup_to_date\n' "$key"
    else
      printf '%s\tdrifted\n' "$key"
      [ "$worst" -lt 3 ] && worst=3
    fi
  done

  rm -rf "$work"
  [ "$worst" = "1" ] && return 1
  return "$worst"
}

# ---------------------------------------------------------------------------
# Classic branch protection alongside rulesets — the migration hazard
# ---------------------------------------------------------------------------
# github_classic_aggregate <owner/repo> <branch>
#
# GitHub's "Convert to ruleset" button copies classic branch protection into a
# ruleset. It does NOT turn the classic protection off, and the two then apply
# AT THE SAME TIME: GitHub aggregates every rule that targets the branch and the
# STRICTER requirement wins. So a repository can pass a ruleset audit perfectly
# while a classic rule nobody has looked at in a year is the thing actually
# gating merges.
#
# The specific case worth shouting about: a classic rule with
# `required_status_checks.strict = true` — "require branches to be up to date
# before merging". `config/github/repository-policy.json` turns that OFF
# deliberately and at length, because with parallel workers and one integration
# PR it costs O(N^2) CI runs and the integration branch can never stay green
# long enough to land. A leftover classic `strict` silently defeats that
# decision, and it defeats it invisibly, because the ruleset says `false` and
# the ruleset is what everybody reads.
#
# Prints tab-separated records; returns 3 when there is at least one finding,
# 0 when there is none, 1 when the state could not be read.
#   classic<TAB>present|absent|unknown
#   rulesets<TAB><n>
#   strict_classic<TAB>true|false
#   finding<TAB><severity: critical|warn><TAB><line>
github_classic_aggregate() {
  local repo="$1" branch="$2" prot rc=0 list n strict approvals ctxs

  list="$(github_list_rulesets "$repo")" || return 1
  n="$(printf '%s' "$list" | jq '[.[] | select((.target // "branch") == "branch")] | length')"
  printf 'rulesets\t%s\n' "${n:-0}"

  prot="$(github_classic_protection "$repo" "$branch")" || rc=$?
  if [ "$rc" = "2" ]; then
    printf 'classic\tabsent\n'
    printf 'strict_classic\tfalse\n'
    return 0
  fi
  if [ "$rc" != "0" ]; then
    printf 'classic\tunknown\n'
    printf 'strict_classic\tfalse\n'
    printf 'finding\twarn\tclassic branch protection could not be read — %s\n' "$(github_explain)"
    return 3
  fi

  printf 'classic\tpresent\n'
  strict="$(printf '%s' "$prot" | jq -r '.required_status_checks.strict // false')"
  approvals="$(printf '%s' "$prot" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')"
  ctxs="$(printf '%s' "$prot" | jq -r '(.required_status_checks.contexts // []) | join(", ")')"
  printf 'strict_classic\t%s\n' "$strict"

  if [ "${n:-0}" -gt 0 ]; then
    printf 'finding\twarn\tclassic branch protection AND %s ruleset(s) both target %s. GitHub applies both and the stricter requirement wins, so the rulesets above are not the whole story.\n' "$n" "$branch"
  else
    printf 'finding\twarn\t%s is governed by classic branch protection only — no ruleset targets it. Migrate it to a ruleset; classic protection cannot be shared, versioned, or targeted at more than one branch pattern.\n' "$branch"
  fi

  if [ "$strict" = "true" ]; then
    printf 'finding\tcritical\ta classic rule still forces "branch must be up to date" (required_status_checks.strict = true) on %s. The canonical policy turns this OFF deliberately, and because GitHub aggregates classic protection with rulesets, this classic rule silently defeats strict_required_status_checks_policy: false — every merge invalidates every other open PR. This is the single most important line in this report.\n' "$branch"
  fi

  if [ "${approvals:-0}" -gt 0 ]; then
    printf 'finding\twarn\ta classic rule requires %s approving review(s) on %s. That requirement survives whatever the rulesets say, and on a solo repository it is only satisfiable with --admin.\n' "$approvals" "$branch"
  fi

  if [ -n "$ctxs" ]; then
    printf 'finding\twarn\tclassic required status checks on %s: %s. These gate merges in addition to any ruleset contexts.\n' "$branch" "$ctxs"
  fi

  return 3
}

# github_classic_migration_plan <owner/repo> <branch> — the ordered, manual
# migration. Printed, never executed: classic protection is READ by this
# codebase and never written, and a tool that deletes branch protection because
# it believes a ruleset has taken over is a tool that can un-protect a branch on
# a wrong belief. The confirmation belongs to a person looking at both.
github_classic_migration_plan() {
  local repo="$1" branch="$2"
  cat <<EOF
Migration path (manual, in this order — the order is the safety):

  1. Read both. Classic:
       gh api repos/${repo}/branches/${branch}/protection
     Rulesets:
       gh api repos/${repo}/rulesets?includes_parents=true

  2. Bring the ruleset up to canonical FIRST, while classic protection is still
     in force. The branch is over-protected for the duration, never under:
       bash scripts/github-policy.sh apply --repo ${repo}

  3. Confirm the ruleset alone carries everything you still want:
       bash scripts/github-policy.sh verify --repo ${repo}

  4. Only then remove the classic protection, by hand, on github.com, or:
       gh api -X DELETE repos/${repo}/branches/${branch}/protection
     This tool will not do step 4 for you at any verbosity or with any flag.

  Do NOT use github.com's "Convert to ruleset" button and stop there. It copies
  classic protection into a new ruleset and LEAVES CLASSIC ENABLED — which is
  how a repository ends up with two overlapping sets of rules where the stricter
  one silently wins.
EOF
}

# ---------------------------------------------------------------------------
# The derived approval count
# ---------------------------------------------------------------------------
# github_derive_review_count <bypass-present:yes|no> <collaborator-count>
#
#   count = 1 if (bypass_actor_present AND collaborators > 1) else 0
#
# WHY THIS IS DERIVED AND NOT STORED PER REPOSITORY
#   On a solo repository the owner authors every pull request, so a review
#   requirement is not strict — it is UNSATISFIABLE. GitHub will not let you
#   approve your own PR, so the only way a change ever lands is `--admin`, and
#   `--admin` does not skip only the review rule: it bypasses required status
#   checks, linear history and thread resolution AT THE SAME TIME. So requiring
#   one approval on a solo repo converts a green-CI gate into a bypass habit.
#   That is a net LOSS of safety, dressed as an increase.
#
#   The count is only meaningful BECAUSE a bypass actor exists. With a bypass
#   actor and more than one collaborator, the two read together as: anyone
#   else's change needs a review, the owner keeps an escape hatch on their own
#   repository. Without the bypass actor, raising the count to 1 is not
#   stricter, it is a lock on a door with no key.
#
#   Both inputs are facts in the API, so storing the answer per repository in
#   the policy file would be storing a stale copy of something readable. The
#   real gate on a solo repository is required_review_thread_resolution — a bot
#   review opens threads and the merge blocks until they are resolved, which one
#   human can genuinely satisfy without a bypass.
github_derive_review_count() {
  local bypass="${1:-no}" collabs="${2:-0}"
  case "$collabs" in ''|*[!0-9]*) collabs=0 ;; esac
  if [ "$bypass" = "yes" ] && [ "$collabs" -gt 1 ]; then
    printf '1\n'
  else
    printf '0\n'
  fi
}

# github_collaborator_count <owner/repo> — number of collaborators, on stdout.
#
# COSTS ONE EXTRA API CALL PER REPOSITORY, which is why nothing calls it
# eagerly. Across a 19-repository sweep that is 19 more requests for an answer
# that only changes the outcome when a bypass actor is present — and when one is
# not, the derived count is 0 regardless of how many collaborators there are.
# github_review_count_for below is the lazy wrapper; use that.
#
# Prints 0 and returns 2 when the count cannot be read. Unknown collaborators
# must resolve to the SAFE answer, and the safe answer is 0: an unsatisfiable
# review requirement conjured from a failed API call would push every merge onto
# `--admin`, which is the exact failure this derivation exists to avoid.
github_collaborator_count() {
  local repo="$1" out n
  if ! out="$(github_api GET "repos/${repo}/collaborators?per_page=100&affiliation=all")"; then
    printf '0\n'
    return 2
  fi
  n="$(printf '%s' "$out" | jq 'if type == "array" then length else 0 end' 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) printf '0\n'; return 2 ;; esac
  printf '%s\n' "$n"
  return 0
}

# github_review_count_for <owner/repo> <live-ruleset-json-file>
#
# The lazy derivation. Prints tab-separated records; always returns 0.
#   count<TAB><0|1>
#   bypass<TAB>yes|no
#   collaborators<TAB><n>|unknown
#   reason<TAB><one human line>
#
# The collaborator call is issued ONLY when a bypass actor is present, because
# that is the only branch where the answer can be anything but 0.
github_review_count_for() {
  local repo="$1" live="$2" bypass=no collabs rc=0

  if [ -f "$live" ] && jq -e '((.bypass_actors // []) | length) > 0' "$live" >/dev/null 2>&1; then
    bypass=yes
  fi

  if [ "$bypass" = "no" ]; then
    printf 'count\t0\n'
    printf 'bypass\tno\n'
    printf 'collaborators\tnot-queried\n'
    printf 'reason\tno bypass actor on this ruleset, so a review requirement would be unsatisfiable by the only person who can merge — 0 without querying collaborators, because the answer is 0 for any collaborator count.\n'
    return 0
  fi

  collabs="$(github_collaborator_count "$repo")" || rc=$?
  if [ "$rc" != "0" ]; then
    # These records are tab-separated LINES, and github_explain can carry a
    # multi-line body through from `gh`'s stderr. Embedding it raw would split
    # one record into several and truncate the reasoning at the first newline.
    local why; why="$(github_explain | tr '\n' ' ' | sed 's/  */ /g; s/ $//')"
    printf 'count\t0\n'
    printf 'bypass\tyes\n'
    printf 'collaborators\tunknown\n'
    printf 'reason\ta bypass actor is present but the collaborator count could not be read (%s). Deriving 0 — the safe direction, because an unsatisfiable review requirement forces every merge onto --admin, which bypasses status checks and linear history at the same time.\n' "$why"
    return 0
  fi

  printf 'count\t%s\n' "$(github_derive_review_count yes "$collabs")"
  printf 'bypass\tyes\n'
  printf 'collaborators\t%s\n' "$collabs"
  if [ "$collabs" -gt 1 ]; then
    printf 'reason\ta bypass actor is present and there are %s collaborators, so 1 approving review binds collaborators while the owner keeps the escape hatch.\n' "$collabs"
  else
    printf 'reason\ta bypass actor is present but there is only %s collaborator, so a review requirement would be unsatisfiable — the owner authors every pull request.\n' "$collabs"
  fi
  return 0
}
