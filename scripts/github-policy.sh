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
#   --allow-weakening
#                    permit a change that makes a repository LESS protected than
#                    it is today. Off by default and never implied by --yes: the
#                    tool's whole reason for existing is that it does not quietly
#                    reduce a control someone deliberately turned on. Each such
#                    change is still shown, marked, and confirmed individually.
#   --json           machine-readable report on stdout, humans on stderr.
#   --verbose, -v    detailed logging to stderr.
#   --help, -h       this text.
#
# ENV TWINS
#   GITHUB_POLICY_FILE=<path>   use a different canonical policy document
#   GITHUB_POLICY_YES=1         same as --yes
#   GITHUB_POLICY_ALLOW_LIVE=1  authorise unattended writes (no TTY). Required in
#                               addition to --yes; see the LIVE-TARGET GATE below.
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
OPT_ALLOW_WEAKEN=""
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
    --allow-weakening) OPT_ALLOW_WEAKEN=1 ;;
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
# Set when `apply` degrades to `plan` for want of a terminal. That run is a
# SUCCESS — it did exactly what the stdin contract promises — so it must not
# also report drift as a failing exit status, or every non-interactive caller
# learns to ignore this script's exit code.
DEGRADED=""
[ -n "$OPT_ALL" ] || [ -n "$OPT_ORG" ] && BULK=1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/changes" "$WORK/repos"
CHANGE_N=0
REPO_N=0
RIDX=0

# In --json mode stdout belongs to the JSON document alone (setup.sh:111).
out() { if [ -z "$OPT_JSON" ]; then printf '%s\n' "$*"; else printf '%s\n' "$*" >&2; fi; }
field() { cat "$1/$2" 2>/dev/null || printf ''; }
# aout — the Actions block writes to stdout unconditionally so the caller can
# capture it once and replay it into either renderer. Emitting it only on the
# human path is how `--json` would come to under-report a real finding.
aout() { printf '%s\n' "$*"; }
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
# Class-preserving requests
# ---------------------------------------------------------------------------
# github_api records WHY a call failed in shell variables, and a variable set
# inside `$( )` dies with the subshell — the exact hazard github-common.sh
# documents for github_scopes. So `x="$(github_api ...)"` always leaves
# GITHUB_LAST_CLASS holding whatever the PREVIOUS call left there, and a 403 on
# repo B gets reported with repo A's reason. Every read and write below is
# therefore issued through the lib's one request primitive with stdout REDIRECTED
# TO A FILE, in this shell, so the classification survives to be printed.
# (Requested of the lib owner in session-files/requests/gh-policy-cli.md.)

# api_call <METHOD> <out-file> <path> [gh args...]
api_call() {
  local method="$1" f="$2" path="$3"
  shift 3
  github_api "$method" "$path" "$@" >"$f"
}

# api_json <out-file> <path> [gh args...] — as api_call GET, plus the guard that
# a 2xx whose body is not JSON is `bad_response`, never silently "empty".
api_json() {
  local f="$1" path="$2"
  shift 2
  api_call GET "$f" "$path" "$@" || return 1
  jq empty "$f" >/dev/null 2>&1 || { github_fail bad_response "GET $path did not return JSON"; return 1; }
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
    api_json "$WORK/page.json" "${base}${sep}per_page=100&page=${page}" || return 1
    n="$(jq 'length' "$WORK/page.json" 2>/dev/null)" || n=0
    [ "${n:-0}" -gt 0 ] || break
    jq -r '.[] | [
        .full_name,
        (.fork // false | tostring),
        (.archived // false | tostring),
        (.default_branch // ""),
        (.owner.type // "User")
      ] | @tsv' "$WORK/page.json"
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
    api_json "$WORK/view.json" "repos/$target" || return 1
    jq -e 'has("default_branch")' "$WORK/view.json" >/dev/null 2>&1 || {
      github_fail bad_response "repos/$target returned a body with no default_branch"; return 1; }
    jq -r '[
        .full_name,
        (.fork // false | tostring),
        (.archived // false | tostring),
        (.default_branch // ""),
        (.owner.type // "User")
      ] | @tsv' "$WORK/view.json" >"$WORK/raw"
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
  local repo="$1" ids id
  api_json "$WORK/parents.json" "repos/${repo}/rulesets?includes_parents=true" || return 1
  ids="$(jq -r '
    .[] | select(.target == "branch")
        | select((.source_type // "Repository") != "Repository")
        | select((.enforcement // "active") == "active")
        | .id' "$WORK/parents.json")"
  for id in $ids; do
    if ! api_json "$WORK/parent.$id.json" "repos/${repo}/rulesets/${id}"; then
      printf 'organization ruleset %s is active on this repository and could not be read\n' "$id"
      continue
    fi
    jq -r '
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
        else "organization ruleset \"" + ($o.name // "?") + "\" " + join("; ") end' "$WORK/parent.$id.json"
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
#
# Matching runs inside jq, on both the name and the file body, because the policy
# states its patterns are "compatible with jq test()". Handing them to `grep -E`
# instead would silently mean something else: BSD grep has no `\s`, so
# `^\s*pull_request:` would become "an optional literal s", and a whole class of
# workflows would be misclassified on macOS and correctly classified on Linux.
# One engine, the one the data was written for.
workflow_class() {
  local subject="$1" content="$2" hit
  hit="$(jq -r -n --arg s "$(github_lower "$subject")" --rawfile c "$content" --slurpfile p "$POLICY" '
    ($p[0].actions.workflow_classification.classes) as $classes |
    def matches($cls):
      (($classes[$cls].name_patterns    // []) | any(. as $pat | $s | test($pat)))
      or
      (($classes[$cls].content_signals  // []) | any(.pattern as $pat | $c | test($pat; "i")));
    if matches("never_cancel") then "never_cancel"
    elif matches("cancellable") then "cancellable"
    else "unclassified" end
  ' 2>/dev/null)"
  [ -n "$hit" ] || hit="unclassified"
  printf '%s\n' "$hit"
}

# workflow_cancels <file> -> always | on_pr | no
# `cancel-in-progress: true` is the canonical form. An expression form —
# `${{ github.event_name == 'pull_request' }}` — is not a missing block, it is a
# sharper version of the same rule: cancel superseded PR runs, never cancel a
# push. Reporting that as a gap would push the user to REPLACE a better
# configuration with the policy's simpler one.
workflow_cancels() {
  grep -Eq '^concurrency:' "$1" || { printf 'no\n'; return 0; }
  grep -Eq 'cancel-in-progress:[[:space:]]*true[[:space:]]*$' "$1" && { printf 'always\n'; return 0; }
  grep -Eq 'cancel-in-progress:[[:space:]]*\$\{\{' "$1" && { printf 'on_pr\n'; return 0; }
  printf 'no\n'
}

# fetch_workflows <owner/repo> <dest-dir> — populate dest-dir with one file per
# workflow. Prefers the local working tree when the target IS this checkout, so
# a workflow you have edited but not pushed is still audited; falls back to the
# contents API for every other repository. Read-only either way.
fetch_workflows() {
  local repo="$1" dest="$2" here path name
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

  # A repository with no workflows directory is a 404 and is a normal, healthy
  # answer — not a failure to report.
  if ! api_json "$WORK/wflist.json" "repos/${repo}/contents/.github/workflows"; then
    [ "$GITHUB_LAST_CLASS" = "not_found" ] && { GITHUB_LAST_CLASS=ok; printf 'none\n'; return 0; }
    return 1
  fi
  for name in $(jq -r '.[] | select(.type == "file")
                | select(.name | test("\\.ya?ml$")) | .name' "$WORK/wflist.json"); do
    api_call GET "$dest/$name" "repos/${repo}/contents/.github/workflows/${name}" \
      -H "Accept: application/vnd.github.raw" || return 1
  done
  printf 'api\n'
}

# report_actions <owner/repo> — prints the `Actions:` block, and returns 1 when a
# cancellable workflow is missing the canonical concurrency block (a real gap) or
# a stateful one has cancellation switched on (a real hazard).
# It NEVER proposes adding concurrency to a never_cancel workflow, and a
# never_cancel workflow without cancellation is an informational line, not a
# failure — that is the correct configuration, not a missing one.
# It writes its block to STDOUT, unconditionally, so the caller can capture it
# once and replay it into either renderer. Running it only on the human path is
# how `--json` would come to under-report a real finding.
report_actions() {
  local repo="$1" dir="$WORK/wf/$RIDX" src f base wname subject class cancels bad=0 rc
  rc=0
  src="$(fetch_workflows "$repo" "$dir")" || rc=$?
  if [ "$rc" != "0" ]; then
    aout "  $MARK_WARN workflows could not be read — $(github_explain)"
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
    cancels="$(workflow_cancels "$f")"

    case "$class" in
      cancellable)
        if [ "$cancels" = always ]; then
          aout "  $MARK_OK $base — superseded PR runs cancelled"
        elif [ "$cancels" = on_pr ]; then
          aout "  $MARK_OK $base — superseded PR runs cancelled (pull_request only)"
        else
          aout "  $MARK_BAD $base — superseded PR runs are NOT cancelled; add the canonical concurrency block"
          add_change "$repo" "actions:$base" modify "missing concurrency block" no \
            "manual" "workflow files are edited by hand, never by this script"
          bad=1
        fi
        ;;
      never_cancel)
        if [ "$cancels" = always ]; then
          aout "  $MARK_BAD $base — cancel-in-progress is TRUE on a stateful workflow; remove it"
          add_change "$repo" "actions:$base" modify "cancellation enabled on a stateful workflow" no \
            "manual" "workflow files are edited by hand, never by this script"
          bad=1
        else
          aout "  $MARK_WARN $base — cancellation intentionally not enabled"
        fi
        ;;
      *)
        aout "  $MARK_WARN $base — unclassified; left untouched for a human decision"
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
  api_json "$WORK/branch.json" "repos/$repo" || return 1
  jq -r '.default_branch // empty' "$WORK/branch.json"
}

# process_repo <repo> <fork> <archived> <default-branch> <owner-type>
# Reads live state, compares against canonical, records changes, and — only in
# `apply`, only after a confirmation, and only when nothing is blocked — writes.
# Sets R_BUCKET / R_NOTE. Never aborts the run: a repository's 403 is that
# repository's result, not the end of the sweep.
process_repo() {
  local repo="$1" fork="$2" arch="$3" branch="$4" otype="$5"
  local rc key name desired diff conflicts weaken id status note line
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
    # An inherited ruleset stricter than the policy is reported WHETHER OR NOT
    # this repository's own rulesets drift. A repo that is compliant underneath a
    # stricter org rule is still governed by something this tool does not own,
    # and silently reporting it as plain ALREADY COMPLIANT would hide that.
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      add_change "$repo" "organization ruleset" conflict "$line" no "org_policy" "$line"
    done <<EOF
$conflicts
EOF
  fi

  local n_absent=0 n_drift=0 n_ok=0 n_block=0 n_written=0
  : >"$WORK/rulesets.$RIDX"
  : >"$WORK/plan.$RIDX"
  : >"$WORK/bypass.$RIDX"

  for key in $(jq -r '.rulesets[].key' "$POLICY"); do
    name="$(jq -r --arg k "$key" '.rulesets[] | select(.key == $k) | .name' "$POLICY")"

    desired="$WORK/desired.$key"
    if ! github_render_payload_file "$POLICY" "$key" "$repo" "$desired"; then
      printf '%s\terror\t%s\n' "$name" "$(github_explain)" >>"$WORK/rulesets.$RIDX"
      add_change "$repo" "$name" error "$(github_explain)" no "render" "$GITHUB_LAST_CLASS"
      R_BUCKET=failed; R_NOTE="$(github_explain)"; return 0
    fi

    if ! api_json "$WORK/rslist.json" "repos/$repo/rulesets?includes_parents=false"; then
      printf '%s\terror\t%s\n' "$name" "$(github_explain)" >>"$WORK/rulesets.$RIDX"
      add_change "$repo" "$name" error "$(github_explain)" no "api" "$GITHUB_LAST_CLASS"
      R_BUCKET=failed; R_NOTE="$(github_explain)"; return 0
    fi
    # Match by NAME. The id is read from the same listing rather than fetched
    # again later, so the ruleset that gets written is provably the one that was
    # diffed — an id re-resolved after the confirmation could name a ruleset that
    # changed underneath us.
    id="$(jq -r --arg n "$name" '[.[] | select(.name == $n) | .id] | first // empty' "$WORK/rslist.json")"
    rc=0
    if [ -n "$id" ]; then
      api_json "$WORK/live.raw.$key" "repos/$repo/rulesets/$id" || rc=1
    else
      rc=2
    fi
    if [ "$rc" = "1" ]; then
      printf '%s\terror\t%s\n' "$name" "$(github_explain)" >>"$WORK/rulesets.$RIDX"
      add_change "$repo" "$name" error "$(github_explain)" no "api" "$GITHUB_LAST_CLASS"
      R_BUCKET=failed; R_NOTE="$(github_explain)"; return 0
    fi

    if [ "$rc" = "2" ]; then
      # Absent. Creating it can weaken nothing, but an org conflict still stops us.
      n_absent=$((n_absent + 1))
      printf '%s\tabsent\t\n' "$name" >>"$WORK/rulesets.$RIDX"
      if [ -n "$conflicts" ]; then n_block=$((n_block + 1)); continue; fi
      add_change "$repo" "$name" create "ruleset does not exist yet" no "" ""
      { printf '%s — create\n' "$name"; sed 's/^/  + /' "$desired"; } >>"$WORK/plan.$RIDX"
      if [ "$VERB" = apply ]; then
        if confirm_change "$repo" "$name" "create" "$desired" ""; then
          if api_call POST "$WORK/created.json" "repos/$repo/rulesets" --input "$desired" >/dev/null; then
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
    github_ruleset_normalize <"$WORK/live.raw.$key" >"$WORK/live.$key"

    # BYPASS ACTORS ARE PRESERVED, NEVER ASSERTED — carry the live value into the
    # desired payload before anything compares or writes.
    #
    # A bypass actor is repository-specific state, exactly like required status
    # check contexts: who is allowed to merge around the rules is a fact about a
    # repository's people, not a rule the policy can know. Asserting `[]` would
    # strip it, and on a solo-contributor account the admin bypass is the merge
    # path — `--admin` is the documented and habitual way changes land here. So
    # asserting the canonical empty list would revoke the author's ability to
    # merge into their own default branch. That is "a policy tool can lock the
    # author out" arriving from the one direction nobody watches, because it wears
    # the costume of a STRENGTHENING: the diff looks like tightening a control
    # while it actually removes the operator's only key.
    #
    # ACCEPTED TRADE-OFF, stated rather than hidden: a repository carrying an
    # over-broad bypass — say Everyone — will never be corrected by this tool. The
    # user chose that deliberately over the risk of lockout. It is surfaced as an
    # informational line so it is at least visible, and it never fails compliance.
    #
    # A ruleset being CREATED gets no bypass actors at all (the policy's `[]`
    # stands): there is no live value to preserve, and inventing one would be
    # granting an exemption nobody asked for.
    jq --slurpfile live "$WORK/live.raw.$key" \
       '.bypass_actors = (($live[0].bypass_actors) // [])' "$desired" \
      | github_ruleset_normalize >"$WORK/desired.patched.$key"
    mv "$WORK/desired.patched.$key" "$desired"

    jq -r --arg n "$name" '
      (.bypass_actors // [])
      | if length == 0 then empty
        else "\($n)\t\(length)\t" + ([.[] | "\(.actor_type // "?") \(.actor_id // "?") (\(.bypass_mode // "?"))"] | join(", "))
        end' "$WORK/live.raw.$key" >>"$WORK/bypass.$RIDX"

    if cmp -s "$desired" "$WORK/live.$key"; then
      n_ok=$((n_ok + 1))
      printf '%s\tup_to_date\t\n' "$name" >>"$WORK/rulesets.$RIDX"
      add_change "$repo" "$name" ok "already up to date" no "" ""
      continue
    fi

    n_drift=$((n_drift + 1))
    printf '%s\tdrifted\t\n' "$name" >>"$WORK/rulesets.$RIDX"
    diff="$WORK/diff.$key"
    diff -u "$WORK/live.$key" "$desired" 2>/dev/null | sed '1,2d' >"$diff" || true

    # The two blocking guards, in order: never weaken, never bypass an org.
    weaken="$(policy_weakens "$WORK/live.$key" "$desired")"
    note=""
    if [ -n "$weaken" ]; then
      note="$(printf '%s' "$weaken" | tr '\n' ';' | sed 's/;$//')"
      if [ -z "$OPT_ALLOW_WEAKEN" ]; then
        add_change "$repo" "$name" conflict "$note" yes "weakens_existing_control" "$note"
        n_block=$((n_block + 1))
        continue
      fi
      # Opted in explicitly. It is still shown, still marked destructive, and
      # still confirmed one repository at a time — the flag buys permission to
      # ask, not permission to skip asking.
      { printf 'WEAKENING (allowed by --allow-weakening): %s\n' "$note"; } >>"$WORK/plan.$RIDX"
    fi
    if [ -n "$conflicts" ]; then n_block=$((n_block + 1)); continue; fi

    if [ -n "$note" ]; then
      add_change "$repo" "$name" modify "weakens an existing control: $note" yes "" ""
    else
      add_change "$repo" "$name" modify "drifts from policy" no "" ""
    fi
    { printf '%s — update (live -> desired)\n' "$name"; sed 's/^/  /' "$diff"; } >>"$WORK/plan.$RIDX"
    if [ "$VERB" = apply ]; then
      WEAKEN_NOTE="$note"
      if confirm_change "$repo" "$name" "update" "$desired" "$diff"; then
        # PUT the same bytes that were rendered, diffed and shown. Nothing is
        # re-rendered and no id is re-resolved between the confirmation and the
        # write.
        WEAKEN_NOTE=""
        if api_call PUT "$WORK/updated.json" "repos/$repo/rulesets/$id" --input "$desired" >/dev/null; then
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
  R_CLASSIC=absent
  if api_json "$WORK/classic.json" "repos/$repo/branches/$branch/protection"; then
    R_CLASSIC=present
    add_change "$repo" "classic protection" ok "legacy classic branch protection is present — migrate to rulesets" no \
      "migration" "classic protection is read but never written by this tool"
  elif [ "$GITHUB_LAST_CLASS" != "not_found" ]; then
    R_CLASSIC=unknown
  fi

  if   [ -n "$conflicts" ];    then R_BUCKET=conflict;          R_NOTE="$(printf '%s' "$conflicts" | head -1)"
  elif [ "$n_block" -gt 0 ];   then R_BUCKET=conflict;          R_NOTE="$n_block ruleset(s) blocked"
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
WEAKEN_NOTE=""
confirm_change() {
  local repo="$1" label="$2" action="$3" desired="$4" diff="$5" ans
  out ""
  out "──────────────────────────────────────────────────────────────"
  out "$repo · $label · $action"
  out "──────────────────────────────────────────────────────────────"
  if [ -n "${WEAKEN_NOTE:-}" ]; then
    out "${SETUP_C_YELLOW}This makes the repository LESS protected than it is today:${SETUP_C_OFF}"
    out "  $WEAKEN_NOTE"
    out ""
  fi
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
  local repo="$1" branch="$2" line name st extra bname bn bwho
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
  done <"$WORK/rulesets.$RIDX" 2>/dev/null || true

  # Anything blocked is louder than the line above, because a blocked change is
  # a decision the user has to make, not a task the tool will get to later.
  local d
  for d in "$WORK"/changes/*; do
    [ -d "$d" ] || continue
    [ "$(field "$d" target)" = "$repo" ] || continue
    [ "$(field "$d" status)" = conflict ] || continue
    out "  $MARK_WARN $(field "$d" label) — CONFLICT: $(field "$d" reason)"
  done

  # `audit` answers "is this repository compliant"; the remediation diff belongs
  # to the verbs whose job is the change.
  if { [ "$VERB" = plan ] || [ "$VERB" = verify ]; } && [ -s "$WORK/plan.$RIDX" ]; then
    out ""
    out "Planned change:"
    while IFS= read -r line; do out "  $line"; done <"$WORK/plan.$RIDX"
  fi

  if [ -s "$WORK/bypass.$RIDX" ]; then
    out ""
    out "Bypass actors (preserved, not asserted by policy):"
    while IFS="$(printf '\t')" read -r bname bn bwho; do
      [ -n "$bname" ] || continue
      out "  $MARK_WARN $bname — $bn preserved: $bwho"
    done <"$WORK/bypass.$RIDX"
  fi

  out ""
  out "Legacy:"
  case "${R_CLASSIC:-absent}" in
    present) out "  $MARK_WARN classic branch protection is present on $branch — migrate it to rulesets" ;;
    unknown) out "  $MARK_WARN classic branch protection could not be read" ;;
    *)       out "  $MARK_OK no classic branch protection (rulesets are authoritative)" ;;
  esac

  out ""
  out "Actions:"
  while IFS= read -r line; do out "$line"; done <"$WORK/actions.out"

  out ""
  if [ "$R_BUCKET" = already_compliant ] && [ "$ACTIONS_BAD" = "0" ]; then
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
      VERB="plan"; DEGRADED=1
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
    VERB="plan"; DEGRADED=1
  fi

  # LIVE-TARGET GATE.
  #
  # --yes exists so a human can skip per-change prompts. It was never meant to be
  # the whole authorisation for writing to somebody's real repositories, and on
  # 2026-08-19 that gap was exercised for real: a non-interactive run with --yes
  # reverted a deliberate setting on the author's own repo, silently, because
  # nothing distinguished "confirmed by a person" from "no person present".
  #
  # So: without a terminal, --yes alone is not enough. A genuinely unattended
  # caller (CI, a scripted sweep) must ALSO set GITHUB_POLICY_ALLOW_LIVE=1, which
  # is impossible to supply by accident and trivial to grep for in a review.
  # A TTY session is unaffected — a human at a prompt has already authorised it.
  if [ "$VERB" = apply ] && ! setup_can_prompt && [ -z "${GITHUB_POLICY_ALLOW_LIVE:-}" ]; then
    setup_note "refusing to write without a terminal: --yes confirms individual changes, it does not authorise unattended mutation of live repositories."
    setup_note "set GITHUB_POLICY_ALLOW_LIVE=1 to allow this deliberately. Showing the plan instead."
    VERB="plan"; DEGRADED=1
  fi

  local name fork arch branch otype
  while IFS="$(printf '\t')" read -r name fork arch branch otype; do
    [ -n "$name" ] || continue
    [ -n "$QUIT" ] && break
    vlog "processing $name"
    RIDX=$((RIDX + 1))
    R_BUCKET=""; R_NOTE=""; R_BRANCH=""; R_CLASSIC=absent
    process_repo "$name" "$fork" "$arch" "$branch" "$otype" || true
    add_repo "$name" "${R_BRANCH:-$branch}" "$R_BUCKET" "$R_NOTE"
    # Live progress goes to stderr, never stdout: a 19-repository sweep takes
    # half a minute and silence reads as a hang, but the report on stdout must
    # not carry the same rows twice when it is piped into a file.
    [ -n "$BULK" ] && printf '  %-46s %-18s %s%s%s\n' \
      "$name" "$R_BUCKET" "$SETUP_C_DIM" "$R_NOTE" "$SETUP_C_OFF" >&2
  done <"$WORK/repolist"

  # Single-repository scope always analyses Actions concurrency, in every output
  # mode, before either renderer runs. Bulk scope does not: it would be one
  # contents-API call per workflow per repository, and the bulk report is about
  # branch governance. `audit`/`verify` on one repo is where that answer belongs.
  ACTIONS_BAD=0
  if [ -z "$BULK" ] && [ "$REPO_N" -gt 0 ]; then
    report_actions "$(field "$WORK/repos/0001" repo)" >"$WORK/actions.out" || ACTIONS_BAD=1
  fi

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
      verify) out "  Remediate:  bash scripts/github-policy.sh apply --repo $(field "$WORK/repos/0001" repo)" ;;
    esac
  fi
  [ -n "$DEGRADED" ] && rc=0
  out ""
  exit "$rc"
}

main
