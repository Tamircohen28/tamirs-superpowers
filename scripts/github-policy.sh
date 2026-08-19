#!/usr/bin/env bash
# github-policy.sh — hold GitHub repositories to the canonical repository policy.
#
# USAGE
#   bash scripts/github-policy.sh [audit|plan|apply|verify] [flags]
#   make github-policy-plan / make github-policy
#
# VERBS
#   audit    read-only compliance report for ONE repository. Never writes, never
#            asks. This is the default, because the default behaviour of a tool
#            that can lock you out of your own repositories must be to look.
#   plan     render the desired rulesets, diff them against what is live, and
#            print the exact change. NEVER writes. Works on one repo or in bulk.
#   apply    plan, then show each diff and confirm it before mutating. Bulk
#            requires the verb AND a confirmation; `--yes` is the only way to
#            skip the prompt and it must be typed.
#   verify   post-mutation verification of ONE repository: re-read live state and
#            re-compare. Read-only. Exit 0 only when everything matches.
#
# SCOPE (plan / apply accept exactly one; audit / verify accept only --repo)
#   --repo <owner/name>  one repository. Defaults to this checkout's `origin`.
#   --all                every repository owned by the authenticated user.
#   --org <name>         every repository in one organization.
#
# FLAGS
#   --include <ERE>  keep only repos whose owner/name matches. Repeatable (OR).
#   --exclude <ERE>  drop repos whose owner/name matches. Repeatable, wins over
#                    --include.
#   --yes, -y        do not prompt; apply every non-blocked change. Explicit only.
#   --json           machine-readable report on stdout, humans on stderr.
#   --verbose, -v    detailed logging to stderr.
#   --help, -h       this text.
#
# ENV TWINS
#   GITHUB_POLICY_FILE=<path>   use a different canonical policy document
#   GITHUB_POLICY_YES=1         same as --yes
#
# EXAMPLES
#   bash scripts/github-policy.sh audit
#   bash scripts/github-policy.sh audit --repo Tamircohen28/tamirs-superpowers
#   bash scripts/github-policy.sh plan --all
#   bash scripts/github-policy.sh plan --org SentinelAIOrg --exclude 'sandbox$'
#   bash scripts/github-policy.sh apply --repo Tamircohen28/job-tracker-web
#   bash scripts/github-policy.sh apply --all --yes
#   bash scripts/github-policy.sh verify --repo Tamircohen28/tamirs-superpowers
#
# WHAT IT WILL NEVER DO
#   delete a ruleset · delete or rename a ruleset it did not render · weaken a
#   control that is already stronger than the policy · drop a required status
#   check · change a default branch · enable force pushes · allow the default
#   branch to be deleted · bypass or override an organization ruleset.
#   Any of those turns into a reported CONFLICT and the repository is left alone.
#
# EXIT CODES
#   0  compliant, or a plan was printed, or apply finished, or there was no
#      terminal to confirm on so the plan was printed instead
#   3  drift: something is absent, drifted, or blocked by a conflict
#   1  failure (bad flag, missing gh/jq, unreadable policy, API failure)
#
# STDIN IS NEVER READ. Prompts go to /dev/tty. A run with no terminal and no
# --yes prints the plan and exits 0 — it never mutates silently and never blocks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/setup-common.sh
. "${SCRIPT_DIR}/lib/setup-common.sh"
# shellcheck source=scripts/lib/github-common.sh
. "${SCRIPT_DIR}/lib/github-common.sh"

POLICY="${GITHUB_POLICY_FILE:-${POLICY_REPO_ROOT}/config/github/repository-policy.json}"

VERB=""
OPT_REPO=""
OPT_ALL=""
OPT_ORG=""
OPT_INCLUDE=""
OPT_EXCLUDE=""
OPT_JSON=""
SETUP_YES="${GITHUB_POLICY_YES:-}"
SETUP_VERBOSE="${SETUP_VERBOSE:-}"

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; }

# ---------------------------------------------------------------------------
# Argument parsing (rules/dev/user-facing-script-standards.md §1)
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    audit|plan|apply|verify)
      [ -z "$VERB" ] || setup_die "more than one verb given ('$VERB' then '$1')"
      VERB="$1" ;;
    --repo)      shift; [ $# -gt 0 ] || setup_die "--repo needs owner/name"; OPT_REPO="$1" ;;
    --repo=*)    OPT_REPO="${1#*=}" ;;
    --all)       OPT_ALL=1 ;;
    --org)       shift; [ $# -gt 0 ] || setup_die "--org needs a name"; OPT_ORG="$1" ;;
    --org=*)     OPT_ORG="${1#*=}" ;;
    --include)   shift; [ $# -gt 0 ] || setup_die "--include needs a pattern"; OPT_INCLUDE="$OPT_INCLUDE
$1" ;;
    --include=*) OPT_INCLUDE="$OPT_INCLUDE
${1#*=}" ;;
    --exclude)   shift; [ $# -gt 0 ] || setup_die "--exclude needs a pattern"; OPT_EXCLUDE="$OPT_EXCLUDE
$1" ;;
    --exclude=*) OPT_EXCLUDE="$OPT_EXCLUDE
${1#*=}" ;;
    --yes|-y)    SETUP_YES=1 ;;
    --dry-run)   VERB="plan" ;;
    --json)      OPT_JSON=1 ;;
    --verbose|-v) SETUP_VERBOSE=1 ;;
    --help|-h)   usage; exit 0 ;;
    --) shift; break ;;
    -*) setup_err "unknown flag: $1"; printf 'Try: bash scripts/github-policy.sh --help\n' >&2; exit 1 ;;
    *)  setup_err "unexpected argument: $1"; printf 'Try: bash scripts/github-policy.sh --help\n' >&2; exit 1 ;;
  esac
  shift
done

# The default verb is the read-only one, in every case. capture-config.sh:105-107
# rejects a terminal-sensitive default that writes; this script mutates live
# branch governance across an entire account, so it inherits the stricter rule
# rather than setup.sh's "a TTY means apply".
[ -n "$VERB" ] || VERB="audit"

# ---------------------------------------------------------------------------
# Scope validation — before any network call
# ---------------------------------------------------------------------------
SCOPE_N=0
[ -n "$OPT_REPO" ] && SCOPE_N=$((SCOPE_N + 1))
[ -n "$OPT_ALL" ]  && SCOPE_N=$((SCOPE_N + 1))
[ -n "$OPT_ORG" ]  && SCOPE_N=$((SCOPE_N + 1))
[ "$SCOPE_N" -le 1 ] || setup_die "give exactly one of --repo / --all / --org"

case "$VERB" in
  audit|verify)
    [ -z "$OPT_ALL" ] || setup_die "'$VERB' reports on one repository — use 'plan' for --all"
    [ -z "$OPT_ORG" ] || setup_die "'$VERB' reports on one repository — use 'plan' for --org"
    ;;
esac

BULK=""
[ -n "$OPT_ALL" ] || [ -n "$OPT_ORG" ] && BULK=1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/changes" "$WORK/repos"
CHANGE_N=0
REPO_N=0

# In --json mode stdout belongs to the JSON document alone (setup.sh:111).
out() { if [ -z "$OPT_JSON" ]; then printf '%s\n' "$*"; else printf '%s\n' "$*" >&2; fi; }
field() { cat "$1/$2" 2>/dev/null || printf ''; }
vlog() { [ -n "${SETUP_VERBOSE:-}" ] && printf '  %s%s%s\n' "$SETUP_C_DIM" "$*" "$SETUP_C_OFF" >&2; return 0; }

MARK_OK="${SETUP_C_GREEN}✓${SETUP_C_OFF}"
MARK_BAD="${SETUP_C_RED}✗${SETUP_C_OFF}"
MARK_WARN="${SETUP_C_YELLOW}⚠${SETUP_C_OFF}"

# ---------------------------------------------------------------------------
# Records (bash 3.2: a directory per record, a file per field — setup.sh:203-217)
# ---------------------------------------------------------------------------

# add_change <repo> <label> <status> <note> <destructive> <blocked> <reason>
#   status: ok | create | modify | conflict | error | skip
#   blocked: "" when the change is actionable, else the guard that stopped it
add_change() {
  local d; CHANGE_N=$((CHANGE_N + 1))
  d="$(printf '%s/changes/%04d' "$WORK" "$CHANGE_N")"
  mkdir -p "$d"
  printf '%s' "$1" >"$d/target";      printf '%s' "$2" >"$d/label"
  printf '%s' "$3" >"$d/status";      printf '%s' "$4" >"$d/note"
  printf '%s' "${5:-no}" >"$d/destructive"
  printf '%s' "${6:-}"   >"$d/blocked"
  printf '%s' "${7:-}"   >"$d/reason"
}

# add_repo <repo> <default-branch> <bucket> <note>
#   bucket: updated | already_compliant | skipped | conflict | failed | drifted
add_repo() {
  local d; REPO_N=$((REPO_N + 1))
  d="$(printf '%s/repos/%04d' "$WORK" "$REPO_N")"
  mkdir -p "$d"
  printf '%s' "$1" >"$d/repo";   printf '%s' "$2" >"$d/branch"
  printf '%s' "$3" >"$d/bucket"; printf '%s' "$4" >"$d/note"
}

count_bucket() {
  local want="$1" n=0 d
  for d in "$WORK"/repos/*; do
    [ -d "$d" ] || continue
    [ "$(field "$d" bucket)" = "$want" ] && n=$((n + 1))
  done
  printf '%s' "$n"
}

count_change_status() {
  local want="$1" n=0 d
  for d in "$WORK"/changes/*; do
    [ -d "$d" ] || continue
    [ "$(field "$d" status)" = "$want" ] && n=$((n + 1))
  done
  printf '%s' "$n"
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
[ -f "$POLICY" ] || setup_die "policy file not found: $POLICY"
jq empty "$POLICY" 2>/dev/null || setup_die "policy file is not valid JSON: $POLICY"

# `gh` is normally an optional feature dependency. Here the GitHub action IS the
# request (rules/dev/gh-cli-preference.md §1), so absence is a named failure.
if ! github_require "github-policy"; then
  setup_err "$(github_explain)"
  exit 1
fi

# ---------------------------------------------------------------------------
# Repository discovery
# ---------------------------------------------------------------------------

# local_repo — owner/name from this checkout's `origin`, or empty. Parsed from
# git, not asked of the API: it is a local fact and costs nothing.
local_repo() {
  local url
  url="$(git -C "$POLICY_REPO_ROOT" remote get-url origin 2>/dev/null)" || return 1
  case "$url" in
    git@github.com:*)      url="${url#git@github.com:}" ;;
    https://github.com/*)  url="${url#https://github.com/}" ;;
    ssh://git@github.com/*) url="${url#ssh://git@github.com/}" ;;
    *) return 1 ;;
  esac
  printf '%s' "${url%.git}"
}

# list_repos_paged <api-path-without-page> — TSV on stdout:
#   owner/name <TAB> fork <TAB> archived <TAB> default_branch <TAB> owner_type
# Paginated by hand rather than with `gh api --paginate`: github_api runs with
# --include, and --paginate would emit one header block per page while the
# splitter keeps only the last, silently discarding every page but the final one.
list_repos_paged() {
  local base="$1" page=1 body n sep
  while :; do
    case "$base" in *\?*) sep='&' ;; *) sep='?' ;; esac
    body="$(github_api GET "${base}${sep}per_page=100&page=${page}")" || return 1
    n="$(printf '%s' "$body" | jq 'length' 2>/dev/null)" || n=0
    [ "${n:-0}" -gt 0 ] || break
    printf '%s' "$body" | jq -r '.[] | [
        .full_name,
        (.fork // false | tostring),
        (.archived // false | tostring),
        (.default_branch // ""),
        (.owner.type // "User")
      ] | @tsv'
    [ "$n" -lt 100 ] && break
    page=$((page + 1))
    [ "$page" -gt 50 ] && { github_warn "stopping repository listing at 5000 repositories"; break; }
  done
}

# filters_pass <owner/repo> — --exclude wins over --include, because a pattern
# that says "never touch this one" must not be defeated by a broader --include.
filters_pass() {
  local name="$1" pat
  if [ -n "$(printf '%s' "$OPT_EXCLUDE" | tr -d '[:space:]')" ]; then
    while IFS= read -r pat; do
      [ -n "$pat" ] || continue
      printf '%s' "$name" | grep -Eq -- "$pat" && return 1
    done <<EOF
$OPT_EXCLUDE
EOF
  fi
  if [ -n "$(printf '%s' "$OPT_INCLUDE" | tr -d '[:space:]')" ]; then
    while IFS= read -r pat; do
      [ -n "$pat" ] || continue
      printf '%s' "$name" | grep -Eq -- "$pat" && return 0
    done <<EOF
$OPT_INCLUDE
EOF
    return 1
  fi
  return 0
}

build_repo_list() {
  local target rc
  : >"$WORK/repolist"
  if [ -n "$OPT_ALL" ]; then
    list_repos_paged "user/repos?affiliation=owner" >"$WORK/raw" || return 1
  elif [ -n "$OPT_ORG" ]; then
    list_repos_paged "orgs/${OPT_ORG}/repos?type=all" >"$WORK/raw" || return 1
  else
    target="$OPT_REPO"
    if [ -z "$target" ]; then
      rc=0; target="$(local_repo)" || rc=$?
      [ "$rc" = "0" ] && [ -n "$target" ] || {
        github_fail bad_response "no --repo given and this checkout has no github.com 'origin'"
        return 1
      }
      vlog "no --repo given; using this checkout's origin: $target"
    fi
    case "$target" in
      */*) : ;;
      *) github_fail bad_response "--repo must be owner/name, got '$target'"; return 1 ;;
    esac
    local view
    view="$(github_repo_view "$target")" || return 1
    printf '%s' "$view" | jq -r '[
        .full_name,
        (.fork // false | tostring),
        (.archived // false | tostring),
        (.default_branch // ""),
        (.owner.type // "User")
      ] | @tsv' >"$WORK/raw"
  fi

  local name fork arch branch otype
  while IFS="$(printf '\t')" read -r name fork arch branch otype; do
    [ -n "$name" ] || continue
    filters_pass "$name" || { vlog "filtered out: $name"; continue; }
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$fork" "$arch" "$branch" "$otype" >>"$WORK/repolist"
  done <"$WORK/raw"
}

# ---------------------------------------------------------------------------
# The weakening guard — the reason `apply` is safe to run
# ---------------------------------------------------------------------------
# policy_weakens <live-json-file> <desired-json-file>
# Prints one human reason per line for every way the desired state is a WEAKER
# control than what is already live, and returns 0 when it printed any. The
# canonical policy is a floor, never a ceiling: a repository that is already
# stricter than the policy is a repository this tool leaves alone.
policy_weakens() {
  jq -r -n --slurpfile live "$1" --slurpfile desired "$2" '
    def ctxs:
      ((.rules // []) | map(select(.type == "required_status_checks"))
       | map(.parameters.required_status_checks // []) | add // [])
      | map(.context) | unique;
    def rule($t): ((.rules // []) | map(select(.type == $t)) | first);
    def types:   ((.rules // []) | map(.type) | unique);
    def pr($k):  (rule("pull_request").parameters[$k]);

    ($live[0]) as $l | ($desired[0]) as $d |
    (($l | ctxs) - ($d | ctxs))   as $gone_ctx |
    (($l | types) - ($d | types)) as $gone_rules |
    [
      (if ($gone_ctx | length) > 0
       then "would remove required status check(s): " + ($gone_ctx | join(", ")) else empty end),

      (if ($gone_rules | length) > 0
       then "would remove protection rule(s) already in force: " + ($gone_rules | join(", ")) else empty end),

      (if (($l | rule("required_status_checks").parameters.strict_required_status_checks_policy) == true)
          and (($d | rule("required_status_checks").parameters.strict_required_status_checks_policy) != true)
       then "would turn OFF strict \"branch must be up to date\", which this repository currently enforces" else empty end),

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
# Organization rulesets — detect and report, never bypass
# ---------------------------------------------------------------------------
# org_conflicts <owner/repo> — one line per inherited organization ruleset that
# imposes something stricter than the canonical policy. An org ruleset is not a
# thing this tool may edit, weaken, or route around; the only correct behaviour
# is to say so and leave the repository alone.
org_conflicts() {
  local repo="$1" parents ids id detail
  parents="$(github_api GET "repos/${repo}/rulesets?includes_parents=true")" || return 1
  ids="$(printf '%s' "$parents" | jq -r '
    .[] | select(.target == "branch")
        | select((.source_type // "Repository") != "Repository")
        | select((.enforcement // "active") == "active")
        | .id')"
  for id in $ids; do
    detail="$(github_get_ruleset "$repo" "$id" 2>/dev/null)" || {
      printf 'organization ruleset %s is active on this repository and could not be read\n' "$id"
      continue
    }
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
        (if ((.rules // []) | map(.type) | index("required_signatures")) != null
         then "requires signed commits" else empty end),
        (if ((.rules // []) | map(.type) | index("required_deployments")) != null
         then "requires successful deployments" else empty end)
      ]
      | if length == 0 then empty
        else "organization ruleset \"" + ($o.name // "?") + "\" " + join("; ") end'
  done
}

# ---------------------------------------------------------------------------
# GitHub Actions concurrency
# ---------------------------------------------------------------------------
# Classification is DATA, read from the policy document. Nothing about which
# workflows may be cancelled is spelled anywhere in this script.
#
# workflow_class <name-subject> <content-file> -> cancellable | never_cancel | unclassified
# `never_cancel` wins a tie, per the policy's stated precedence: a test job
# wrongly serialized costs minutes, a deploy wrongly cancelled costs a
# half-written external state.
workflow_class() {
  local subject content="$2" hit
  subject="$(github_lower "$1")"

  hit="$(jq -r --arg s "$subject" '
    .actions.workflow_classification.classes.never_cancel.name_patterns[]
    | select($s | test(.)) ' "$POLICY" 2>/dev/null | head -1)"
  [ -n "$hit" ] && { printf 'never_cancel\n'; return 0; }

  local pat
  for pat in $(jq -r '.actions.workflow_classification.classes.never_cancel.content_signals[].pattern
                      | @base64' "$POLICY" 2>/dev/null); do
    pat="$(printf '%s' "$pat" | base64 --decode 2>/dev/null)"
    [ -n "$pat" ] || continue
    grep -Eq -- "$pat" "$content" 2>/dev/null && { printf 'never_cancel\n'; return 0; }
  done

  hit="$(jq -r --arg s "$subject" '
    .actions.workflow_classification.classes.cancellable.name_patterns[]
    | select($s | test(.)) ' "$POLICY" 2>/dev/null | head -1)"
  [ -n "$hit" ] && { printf 'cancellable\n'; return 0; }

  for pat in $(jq -r '.actions.workflow_classification.classes.cancellable.content_signals[].pattern
                      | @base64' "$POLICY" 2>/dev/null); do
    pat="$(printf '%s' "$pat" | base64 --decode 2>/dev/null)"
    [ -n "$pat" ] || continue
    grep -Eq -- "$pat" "$content" 2>/dev/null && { printf 'cancellable\n'; return 0; }
  done

  printf 'unclassified\n'
}

# fetch_workflows <owner/repo> <dest-dir> — populate dest-dir with one file per
# workflow. Prefers the local working tree when the target IS this checkout, so
# a workflow you have edited but not pushed is still audited; falls back to the
# contents API for every other repository. Read-only either way.
fetch_workflows() {
  local repo="$1" dest="$2" here listing path name raw
  mkdir -p "$dest"
  here="$(local_repo 2>/dev/null || true)"
  if [ "$here" = "$repo" ] && [ -d "$POLICY_REPO_ROOT/.github/workflows" ]; then
    for path in "$POLICY_REPO_ROOT"/.github/workflows/*.yml "$POLICY_REPO_ROOT"/.github/workflows/*.yaml; do
      [ -f "$path" ] || continue
      cp "$path" "$dest/$(basename "$path")"
    done
    printf 'local\n'
    return 0
  fi

  listing="$(github_api GET "repos/${repo}/contents/.github/workflows")" || {
    [ "$GITHUB_LAST_CLASS" = "not_found" ] && { GITHUB_LAST_CLASS=ok; printf 'none\n'; return 0; }
    return 1
  }
  for name in $(printf '%s' "$listing" | jq -r '.[] | select(.type == "file")
                | select(.name | test("\\.ya?ml$")) | .name'); do
    raw="$(github_api GET "repos/${repo}/contents/.github/workflows/${name}" \
             -H "Accept: application/vnd.github.raw")" || return 1
    printf '%s\n' "$raw" >"$dest/$name"
  done
  printf 'api\n'
}

# report_actions <owner/repo> — prints the `Actions:` block, and returns 1 when a
# cancellable workflow is missing the canonical concurrency block (a real gap) or
# a stateful one has cancellation switched on (a real hazard).
# It NEVER proposes adding concurrency to a never_cancel workflow, and a
# never_cancel workflow without cancellation is an informational line, not a
# failure — that is the correct configuration, not a missing one.
report_actions() {
  local repo="$1" dir="$WORK/wf/$REPO_N" src f base wname subject class has_conc cancels bad=0
  rc=0
  src="$(fetch_workflows "$repo" "$dir")" || rc=$?
  if [ "$rc" != "0" ]; then
    out "  $MARK_WARN workflows could not be read — $(github_explain)"
    return 0
  fi
  vlog "workflow source: $src"

  local any=no
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    any=yes
    base="$(basename "$f")"
    wname="$(sed -n 's/^name:[[:space:]]*//p' "$f" | head -1 | tr -d '"'"'")"
    subject="${base} ${wname}"
    class="$(workflow_class "$subject" "$f")"
    has_conc=no; grep -Eq '^concurrency:' "$f" && has_conc=yes
    cancels=no;  grep -Eq 'cancel-in-progress:[[:space:]]*true' "$f" && cancels=yes

    case "$class" in
      cancellable)
        if [ "$has_conc" = yes ] && [ "$cancels" = yes ]; then
          out "  $MARK_OK $base — superseded PR runs cancelled"
        else
          out "  $MARK_BAD $base — superseded PR runs are NOT cancelled; add the canonical concurrency block"
          add_change "$repo" "actions:$base" modify "missing concurrency block" no \
            "manual" "workflow files are edited by hand, never by this script"
          bad=1
        fi
        ;;
      never_cancel)
        if [ "$cancels" = yes ]; then
          out "  $MARK_BAD $base — cancel-in-progress is TRUE on a stateful workflow; remove it"
          add_change "$repo" "actions:$base" modify "cancellation enabled on a stateful workflow" no \
            "manual" "workflow files are edited by hand, never by this script"
          bad=1
        else
          out "  $MARK_WARN $base — cancellation intentionally not enabled"
        fi
        ;;
      *)
        out "  $MARK_WARN $base — unclassified; left untouched for a human decision"
        ;;
    esac
  done
  [ "$any" = yes ] || out "  ${SETUP_C_DIM}no workflows${SETUP_C_OFF}"
  return "$bad"
}

# ---------------------------------------------------------------------------
# Per-repository compliance
# ---------------------------------------------------------------------------
# Resolve the default branch from the API, never from a literal: this fleet is
# main x15 / master x4, so any hardcoded name is wrong on one of those sets.
resolve_branch() {
  local repo="$1" given="$2"
  if [ -n "$given" ]; then printf '%s' "$given"; return 0; fi
  github_default_branch "$repo"
}

# process_repo <repo> <fork> <archived> <default-branch> <owner-type>
# Reads live state, compares against canonical, records changes, and — only in
# `apply`, only after a confirmation, and only when nothing is blocked — writes.
# Sets R_BUCKET / R_NOTE. Never aborts the run: a repository's 403 is that
# repository's result, not the end of the sweep.
process_repo() {
  local repo="$1" fork="$2" arch="$3" branch="$4" otype="$5"
  local rc key name live desired diff conflicts weaken id status note
  R_BUCKET=""; R_NOTE=""; R_BRANCH=""

  if [ "$arch" = "true" ]; then R_BUCKET=skipped; R_NOTE="archived"; return 0; fi
  if [ "$fork" = "true" ]; then R_BUCKET=skipped; R_NOTE="fork"; return 0; fi

  rc=0; branch="$(resolve_branch "$repo" "$branch")" || rc=$?
  if [ "$rc" != "0" ] || [ -z "$branch" ]; then
    R_BUCKET=failed; R_NOTE="$(github_explain)"; return 0
  fi
  R_BRANCH="$branch"

  # Organization rulesets first: if something above this repository already
  # imposes more than the policy, the repository is a CONFLICT and is not
  # touched. There is no flag that overrides this.
  conflicts=""
  if [ "$otype" = "Organization" ]; then
    rc=0; conflicts="$(org_conflicts "$repo")" || rc=$?
    if [ "$rc" != "0" ]; then
      R_BUCKET=failed; R_NOTE="$(github_explain)"; return 0
    fi
  fi

  local n_absent=0 n_drift=0 n_ok=0 n_block=0 n_written=0
  : >"$WORK/rulesets.$REPO_N"

  for key in $(jq -r '.rulesets[].key' "$POLICY"); do
    name="$(jq -r --arg k "$key" '.rulesets[] | select(.key == $k) | .name' "$POLICY")"

    desired="$WORK/desired.$key"
    if ! github_render_payload_file "$POLICY" "$key" "$repo" "$desired"; then
      printf '%s\terror\t%s\n' "$name" "$(github_explain)" >>"$WORK/rulesets.$REPO_N"
      add_change "$repo" "$name" error "$(github_explain)" no "render" "$GITHUB_LAST_CLASS"
      R_BUCKET=failed; R_NOTE="$(github_explain)"; return 0
    fi

    rc=0
    live="$(github_get_ruleset_by_name "$repo" "$name")" || rc=$?
    if [ "$rc" = "1" ]; then
      printf '%s\terror\t%s\n' "$name" "$(github_explain)" >>"$WORK/rulesets.$REPO_N"
      add_change "$repo" "$name" error "$(github_explain)" no "api" "$GITHUB_LAST_CLASS"
      R_BUCKET=failed; R_NOTE="$(github_explain)"; return 0
    fi

    if [ "$rc" = "2" ]; then
      # Absent. Creating it can weaken nothing, but an org conflict still stops us.
      n_absent=$((n_absent + 1))
      printf '%s\tabsent\t\n' "$name" >>"$WORK/rulesets.$REPO_N"
      if [ -n "$conflicts" ]; then
        add_change "$repo" "$name" conflict "absent, but an organization ruleset is stricter" no \
          "org_policy" "$(printf '%s' "$conflicts" | head -1)"
        n_block=$((n_block + 1))
        continue
      fi
      add_change "$repo" "$name" create "ruleset does not exist yet" no "" ""
      if [ "$VERB" = apply ]; then
        if confirm_change "$repo" "$name" "create" "$desired" ""; then
          if github_create_ruleset "$repo" "$desired" >/dev/null; then
            n_written=$((n_written + 1))
            out "    $MARK_OK created"
          else
            out "    $MARK_BAD $(github_explain)"
            R_BUCKET=failed; R_NOTE="$(github_explain)"; return 0
          fi
        fi
      fi
      continue
    fi

    # Present. Normalize both sides and compare — the idempotence primitive.
    printf '%s' "$live" | github_ruleset_normalize >"$WORK/live.$key"
    if cmp -s "$desired" "$WORK/live.$key"; then
      n_ok=$((n_ok + 1))
      printf '%s\tup_to_date\t\n' "$name" >>"$WORK/rulesets.$REPO_N"
      add_change "$repo" "$name" ok "already up to date" no "" ""
      continue
    fi

    n_drift=$((n_drift + 1))
    printf '%s\tdrifted\t\n' "$name" >>"$WORK/rulesets.$REPO_N"
    diff="$WORK/diff.$key"
    diff -u "$WORK/live.$key" "$desired" 2>/dev/null | sed '1,2d' >"$diff" || true

    # The two blocking guards, in order: never weaken, never bypass an org.
    weaken="$(policy_weakens "$WORK/live.$key" "$desired")"
    if [ -n "$weaken" ]; then
      note="$(printf '%s' "$weaken" | tr '\n' ';' | sed 's/;$//')"
      add_change "$repo" "$name" conflict "$note" yes "weakens_existing_control" "$note"
      n_block=$((n_block + 1))
      continue
    fi
    if [ -n "$conflicts" ]; then
      add_change "$repo" "$name" conflict "$(printf '%s' "$conflicts" | head -1)" no \
        "org_policy" "$(printf '%s' "$conflicts" | tr '\n' ';' | sed 's/;$//')"
      n_block=$((n_block + 1))
      continue
    fi

    add_change "$repo" "$name" modify "drifts from policy" no "" ""
    if [ "$VERB" = apply ]; then
      if confirm_change "$repo" "$name" "update" "$desired" "$diff"; then
        id="$(github_ruleset_id "$repo" "$name")" || id=""
        if [ -z "$id" ]; then
          out "    $MARK_BAD could not resolve the ruleset id"
          R_BUCKET=failed; R_NOTE="could not resolve the ruleset id"; return 0
        fi
        # PUT the same bytes that were rendered, diffed and shown. Nothing is
        # re-rendered between the confirmation and the write.
        if github_update_ruleset "$repo" "$id" "$desired" >/dev/null; then
          n_written=$((n_written + 1))
          out "    $MARK_OK updated"
        else
          out "    $MARK_BAD $(github_explain)"
          R_BUCKET=failed; R_NOTE="$(github_explain)"; return 0
        fi
      fi
    fi
  done

  # Classic branch protection is legacy, reported, never the source of truth.
  rc=0
  github_classic_protection "$repo" "$branch" >/dev/null || rc=$?
  R_CLASSIC=absent
  if [ "$rc" = "0" ]; then
    R_CLASSIC=present
    add_change "$repo" "classic protection" ok "legacy classic branch protection is present — migrate to rulesets" no \
      "migration" "classic protection is read but never written by this tool"
  elif [ "$rc" != "2" ]; then
    R_CLASSIC=unknown
  fi

  if   [ "$n_block" -gt 0 ];   then R_BUCKET=conflict;          R_NOTE="$n_block ruleset(s) blocked"
  elif [ "$n_written" -gt 0 ]; then R_BUCKET=updated;           R_NOTE="$n_written ruleset(s) written"
  elif [ $((n_absent + n_drift)) -gt 0 ]; then
    if [ "$VERB" = apply ]; then R_BUCKET=skipped;              R_NOTE="declined at the prompt"
    else                         R_BUCKET=drifted;              R_NOTE="$n_absent absent, $n_drift drifted"; fi
  else                              R_BUCKET=already_compliant; R_NOTE="$n_ok ruleset(s) up to date"
  fi
  status=0
  return "$status"
}

# ---------------------------------------------------------------------------
# Confirmation — /dev/tty only, never stdin
# ---------------------------------------------------------------------------
# confirm_change <repo> <label> <action> <desired-file> <diff-file>
# Shows the EXACT payload or diff that is about to be sent, then asks. Returns 0
# to proceed, 1 to skip. `--yes` proceeds without asking; no terminal never
# proceeds — the caller has already guaranteed that case cannot reach here.
CONFIRM_ALL=""
confirm_change() {
  local repo="$1" label="$2" action="$3" desired="$4" diff="$5" ans
  out ""
  out "──────────────────────────────────────────────────────────────"
  out "$repo · $label · $action"
  out "──────────────────────────────────────────────────────────────"
  if [ -n "$diff" ] && [ -s "$diff" ]; then
    out "$(cat "$diff")"
  else
    out "$(sed 's/^/  + /' "$desired")"
  fi
  [ -n "$CONFIRM_ALL" ] && return 0
  [ -n "${SETUP_YES:-}" ] && return 0
  ans="$(setup_lower "$(setup_ask 'Apply to this repository? [y/N/a/q] ' n)")"
  case "$ans" in
    y|yes) return 0 ;;
    a|all) CONFIRM_ALL=1; return 0 ;;
    q|quit) QUIT=1; return 1 ;;
    *) return 1 ;;
  esac
}
QUIT=""

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------
print_single_report() {
  local repo="$1" branch="$2" line name st extra actions_bad=0
  out ""
  out "${SETUP_C_BOLD}GitHub Repository Standards${SETUP_C_OFF} — $repo"
  out ""
  out "Default branch: $branch"
  out ""
  out "Rulesets:"
  while IFS="$(printf '\t')" read -r name st extra; do
    [ -n "$name" ] || continue
    case "$st" in
      up_to_date) out "  $MARK_OK $name" ;;
      absent)     out "  $MARK_BAD $name — not present on this repository" ;;
      drifted)    out "  $MARK_BAD $name — drifts from policy" ;;
      error)      out "  $MARK_BAD $name — $extra" ;;
    esac
  done <"$WORK/rulesets.$REPO_N" 2>/dev/null || true

  # Anything blocked is louder than the line above, because a blocked change is
  # a decision the user has to make, not a task the tool will get to later.
  local d
  for d in "$WORK"/changes/*; do
    [ -d "$d" ] || continue
    [ "$(field "$d" target)" = "$repo" ] || continue
    [ "$(field "$d" status)" = conflict ] || continue
    out "  $MARK_WARN $(field "$d" label) — CONFLICT: $(field "$d" reason)"
  done

  out ""
  out "Legacy:"
  case "${R_CLASSIC:-absent}" in
    present) out "  $MARK_WARN classic branch protection is present on $branch — migrate it to rulesets" ;;
    unknown) out "  $MARK_WARN classic branch protection could not be read" ;;
    *)       out "  $MARK_OK no classic branch protection (rulesets are authoritative)" ;;
  esac

  out ""
  out "Actions:"
  report_actions "$repo" || actions_bad=1

  out ""
  if [ "$R_BUCKET" = already_compliant ] && [ "$actions_bad" = "0" ]; then
    out "Result: ${SETUP_C_GREEN}COMPLIANT${SETUP_C_OFF}"
    return 0
  fi
  if [ "$R_BUCKET" = conflict ]; then
    out "Result: ${SETUP_C_YELLOW}BLOCKED${SETUP_C_OFF} — $R_NOTE"
    return 3
  fi
  out "Result: ${SETUP_C_RED}NON-COMPLIANT${SETUP_C_OFF}"
  return 3
}

print_bulk_report() {
  local bucket d
  out ""
  out "${SETUP_C_BOLD}GitHub Repository Standards — $REPO_N repositories${SETUP_C_OFF}"
  for bucket in updated already_compliant skipped conflict failed drifted; do
    local n; n="$(count_bucket "$bucket")"
    [ "$n" -gt 0 ] || continue
    out ""
    case "$bucket" in
      updated)           out "UPDATED ($n)" ;;
      already_compliant) out "ALREADY COMPLIANT ($n)" ;;
      skipped)           out "SKIPPED ($n)" ;;
      conflict)          out "CONFLICT ($n)" ;;
      failed)            out "FAILED ($n)" ;;
      drifted)           out "WOULD UPDATE ($n)" ;;
    esac
    for d in "$WORK"/repos/*; do
      [ -d "$d" ] || continue
      [ "$(field "$d" bucket)" = "$bucket" ] || continue
      out "$(printf '  %-46s %s' "$(field "$d" repo)" "${SETUP_C_DIM}$(field "$d" note)${SETUP_C_OFF}")"
    done
  done
  out ""
}

print_json() {
  local d first=1
  printf '{"ok":true,"verb":"%s","policy_version":%s,"repositories":[' \
    "$VERB" "$(jq '.version' "$POLICY")"
  for d in "$WORK"/repos/*; do
    [ -d "$d" ] || continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    jq -nc --arg r "$(field "$d" repo)" --arg b "$(field "$d" branch)" \
           --arg k "$(field "$d" bucket)" --arg n "$(field "$d" note)" \
      '{repo:$r,default_branch:$b,bucket:$k,note:$n}' | tr -d '\n'
  done
  printf '],"changes":['
  first=1
  for d in "$WORK"/changes/*; do
    [ -d "$d" ] || continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    jq -nc --arg t "$(field "$d" target)" --arg l "$(field "$d" label)" \
           --arg s "$(field "$d" status)" --arg note "$(field "$d" note)" \
           --arg dz "$(field "$d" destructive)" --arg b "$(field "$d" blocked)" \
           --arg rsn "$(field "$d" reason)" \
      '{target:$t,label:$l,status:$s,note:$note,destructive:($dz=="yes"),blocked:$b,reason:$rsn}' \
      | tr -d '\n'
  done
  printf '],"summary":{"changes":%s,"up_to_date":%s,"skipped":%s,"conflicts":%s,"failed":%s}}\n' \
    "$(( $(count_change_status modify) + $(count_change_status create) ))" \
    "$(count_change_status ok)" \
    "$(count_bucket skipped)" \
    "$(count_bucket conflict)" \
    "$(count_bucket failed)"
}

# ---------------------------------------------------------------------------
main() {
  build_repo_list || { setup_err "$(github_explain)"; exit 1; }

  if [ ! -s "$WORK/repolist" ]; then
    out "No repositories matched. Nothing to do."
    [ -n "$OPT_JSON" ] && print_json
    exit 0
  fi

  local n_targets
  n_targets="$(wc -l <"$WORK/repolist" | tr -d ' ')"

  # BULK APPLY GATE. Two independent things must be true before a sweep can
  # mutate: the user typed `apply` (never the default), and either confirmed at a
  # terminal or typed --yes. With neither, the plan is printed and nothing moves.
  if [ "$VERB" = apply ] && [ -n "$BULK" ]; then
    if [ -z "${SETUP_YES:-}" ] && ! setup_can_prompt; then
      setup_note "no TTY — cannot confirm a bulk apply. Showing the plan instead; re-run with --yes to apply."
      VERB="plan"
    else
      out ""
      out "${SETUP_C_YELLOW}About to change live branch governance on up to $n_targets repositories.${SETUP_C_OFF}"
      out "Each repository is shown and confirmed separately before anything is written."
      if [ -z "${SETUP_YES:-}" ]; then
        local ans
        ans="$(setup_lower "$(setup_ask "Continue? [y/N] " n)")"
        case "$ans" in y|yes) : ;; *) out "Nothing was written."; exit 0 ;; esac
      fi
    fi
  fi

  # Single-repo apply obeys the same rule: no terminal and no --yes means plan.
  if [ "$VERB" = apply ] && [ -z "$BULK" ] && [ -z "${SETUP_YES:-}" ] && ! setup_can_prompt; then
    setup_note "no TTY — cannot confirm. Showing the plan instead; re-run with --yes to apply."
    VERB="plan"
  fi

  local name fork arch branch otype
  while IFS="$(printf '\t')" read -r name fork arch branch otype; do
    [ -n "$name" ] || continue
    [ -n "$QUIT" ] && break
    vlog "processing $name"
    R_BUCKET=""; R_NOTE=""; R_BRANCH=""; R_CLASSIC=absent
    process_repo "$name" "$fork" "$arch" "$branch" "$otype" || true
    add_repo "$name" "${R_BRANCH:-$branch}" "$R_BUCKET" "$R_NOTE"
    [ -n "$BULK" ] && [ -z "$OPT_JSON" ] && \
      out "$(printf '  %-46s %-18s %s' "$name" "$R_BUCKET" "${SETUP_C_DIM}$R_NOTE${SETUP_C_OFF}")"
  done <"$WORK/repolist"

  if [ -n "$OPT_JSON" ]; then
    print_json
    exit 0
  fi

  local rc=0
  if [ -n "$BULK" ]; then
    print_bulk_report
    if [ "$(count_bucket conflict)" -gt 0 ] || [ "$(count_bucket failed)" -gt 0 ] \
       || [ "$(count_bucket drifted)" -gt 0 ]; then rc=3; fi
    case "$VERB" in
      plan) out "Nothing has been written. Re-run with 'apply' to make these changes." ;;
    esac
  else
    print_single_report "$(field "$WORK/repos/0001" repo)" "$(field "$WORK/repos/0001" branch)" || rc=$?
    out ""
    case "$VERB" in
      audit)  out "  Remediate:  bash scripts/github-policy.sh plan --repo $(field "$WORK/repos/0001" repo)" ;;
      plan)   out "  Nothing has been written. Re-run with 'apply' to make these changes." ;;
      apply)  out "  Verify:     bash scripts/github-policy.sh verify --repo $(field "$WORK/repos/0001" repo)" ;;
    esac
  fi
  out ""
  exit "$rc"
}

main
