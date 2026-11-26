#!/usr/bin/env bash
# github-labels.sh — hold GitHub repositories to the canonical label set.
#
# USAGE
#   bash scripts/github-labels.sh [audit|plan|apply] [flags]
#   make github-labels-plan / make github-labels
#
# VERBS
#   audit    read-only report for ONE repository: which canonical labels are
#            missing, which drift (colour or description), which live labels
#            the set does not know. Never writes, never asks. The default.
#   plan     the same comparison, on one repository or in bulk, printed as the
#            exact change `apply` would make. NEVER writes.
#   apply    plan, then show each repository's changes and confirm before
#            writing.
#            Creates missing labels and updates drifted ones. It never deletes
#            unless --prune is typed.
#
# SCOPE (plan / apply accept exactly one; audit accepts only --repo)
#   --repo <owner/name>  one repository. Defaults to this checkout's `origin`.
#   --all                every repository owned by the authenticated user.
#   --org <name>         every repository in one organization.
#
# FLAGS
#   --prune          also DELETE live labels the canonical set does not name.
#                    Off by default and never implied by --yes: a label the set
#                    does not know may be one a human made on purpose, and a
#                    deleted label is stripped from every issue that carried it.
#   --yes, -y        do not prompt; apply every change. Explicit only.
#   --json           machine-readable report on stdout, humans on stderr.
#   --verbose, -v    detailed logging to stderr.
#   --help, -h       this text.
#
# WHAT IS COMPARED
#   The desired set is config/github/labels.json plus one agent:<platform>
#   label per key of core/capabilities/platforms.json (never a hardcoded
#   platform list). A label matches by name, case-insensitively, as GitHub
#   does; colour is compared case-insensitively; description byte for byte.
#
# ENV TWINS
#   GITHUB_LABELS_FILE=<path>      a different canonical label set
#   GITHUB_PLATFORMS_FILE=<path>   a different capability registry
#   GITHUB_LABELS_YES=1            same as --yes
#
# EXAMPLES
#   bash scripts/github-labels.sh audit --repo Tamircohen28/tamirs-superpowers
#   bash scripts/github-labels.sh plan --all
#   bash scripts/github-labels.sh apply --repo Tamircohen28/job-tracker-web
#   bash scripts/github-labels.sh apply --repo Tamircohen28/job-tracker-web --prune
#   bash scripts/github-labels.sh plan --org SentinelAIOrg --json
#
# EXIT CODES
#   0  compliant, or a plan was printed, or apply finished, or there was no
#      terminal to confirm on so the plan was printed instead
#   3  drift: a label is missing or differs; or a write failed
#   1  failure (bad flag, missing gh/jq, unreadable label set, API failure)
#
# STDIN IS NEVER READ. Prompts go to /dev/tty. A run with no terminal and no
# --yes prints the plan and exits 0 — it never mutates silently and never blocks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABELS_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/setup-common.sh
. "${SCRIPT_DIR}/lib/setup-common.sh"
# shellcheck source=scripts/lib/github-common.sh
. "${SCRIPT_DIR}/lib/github-common.sh"

LABELS="${GITHUB_LABELS_FILE:-${LABELS_REPO_ROOT}/config/github/labels.json}"
REGISTRY="${GITHUB_PLATFORMS_FILE:-${LABELS_REPO_ROOT}/core/capabilities/platforms.json}"

VERB=""
OPT_REPO=""
OPT_ALL=""
OPT_ORG=""
OPT_JSON=""
OPT_PRUNE=""
SETUP_YES="${GITHUB_LABELS_YES:-}"
SETUP_VERBOSE="${SETUP_VERBOSE:-}"

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; }

# ---------------------------------------------------------------------------
# Argument parsing (rules/dev/user-facing-script-standards.md §1)
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    audit|plan|apply)
      [ -z "$VERB" ] || setup_die "more than one verb given ('$VERB' then '$1')"
      VERB="$1" ;;
    --repo)      shift; [ $# -gt 0 ] || setup_die "--repo needs owner/name"; OPT_REPO="$1" ;;
    --repo=*)    OPT_REPO="${1#*=}" ;;
    --all)       OPT_ALL=1 ;;
    --org)       shift; [ $# -gt 0 ] || setup_die "--org needs a name"; OPT_ORG="$1" ;;
    --org=*)     OPT_ORG="${1#*=}" ;;
    --prune)     OPT_PRUNE=1 ;;
    --yes|-y)    SETUP_YES=1 ;;
    --dry-run)   VERB="plan" ;;
    --json)      OPT_JSON=1 ;;
    --verbose|-v) SETUP_VERBOSE=1 ;;
    --help|-h)   usage; exit 0 ;;
    --) shift; break ;;
    -*) setup_err "unknown flag: $1"; printf 'Try: bash scripts/github-labels.sh --help\n' >&2; exit 1 ;;
    *)  setup_err "unexpected argument: $1"; printf 'Try: bash scripts/github-labels.sh --help\n' >&2; exit 1 ;;
  esac
  shift
done

# The default verb is the read-only one, as in github-policy.sh.
[ -n "$VERB" ] || VERB="audit"

SCOPE_N=0
[ -n "$OPT_REPO" ] && SCOPE_N=$((SCOPE_N + 1))
[ -n "$OPT_ALL" ]  && SCOPE_N=$((SCOPE_N + 1))
[ -n "$OPT_ORG" ]  && SCOPE_N=$((SCOPE_N + 1))
[ "$SCOPE_N" -le 1 ] || setup_die "give exactly one of --repo / --all / --org"

if [ "$VERB" = audit ]; then
  [ -z "$OPT_ALL" ] || setup_die "'audit' reports on one repository — use 'plan' for --all"
  [ -z "$OPT_ORG" ] || setup_die "'audit' reports on one repository — use 'plan' for --org"
fi
[ -z "$OPT_PRUNE" ] || [ "$VERB" = apply ] || setup_note "--prune only matters to 'apply'; extras are reported either way"

BULK=""
[ -n "$OPT_ALL" ] || [ -n "$OPT_ORG" ] && BULK=1
# Set when `apply` degrades to `plan` for want of a terminal or an allow. That
# run is a SUCCESS — it did what the stdin contract promises — so it must not
# also report drift as a failing exit status.
DEGRADED=""

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/repos"
REPO_N=0

out() { if [ -z "$OPT_JSON" ]; then printf '%s\n' "$*"; else printf '%s\n' "$*" >&2; fi; }
field() { cat "$1/$2" 2>/dev/null || printf ''; }
vlog() { [ -n "${SETUP_VERBOSE:-}" ] && printf '  %s%s%s\n' "$SETUP_C_DIM" "$*" "$SETUP_C_OFF" >&2; return 0; }

MARK_OK="${SETUP_C_GREEN}✓${SETUP_C_OFF}"
MARK_ADD="${SETUP_C_GREEN}+${SETUP_C_OFF}"
MARK_MOD="${SETUP_C_YELLOW}~${SETUP_C_OFF}"
MARK_DEL="${SETUP_C_RED}-${SETUP_C_OFF}"
MARK_BAD="${SETUP_C_RED}✗${SETUP_C_OFF}"

# api_call <METHOD> <out-file> <path> [gh args...] — the lib's one request
# primitive with stdout redirected in THIS shell, so the error class survives
# (the subshell contract at the top of github-common.sh).
api_call() {
  local method="$1" f="$2" path="$3"
  shift 3
  github_api "$method" "$path" "$@" >"$f"
}
api_json() {
  local f="$1" path="$2"
  shift 2
  api_call GET "$f" "$path" "$@" || return 1
  jq empty "$f" >/dev/null 2>&1 || { github_fail bad_response "GET $path did not return JSON"; return 1; }
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
[ -f "$LABELS" ]   || setup_die "label set not found: $LABELS"
jq empty "$LABELS" 2>/dev/null || setup_die "label set is not valid JSON: $LABELS"
[ -f "$REGISTRY" ] || setup_die "capability registry not found: $REGISTRY"
jq -e '.platforms | type == "object" and length > 0' "$REGISTRY" >/dev/null 2>&1 \
  || setup_die "capability registry has no platforms object: $REGISTRY"

if ! github_require "github-labels"; then
  setup_err "$(github_explain)"
  exit 1
fi

LABELS_VERSION="$(jq -r '.version // "unversioned"' "$LABELS")"

# ---------------------------------------------------------------------------
# The desired set — the label file plus one agent:<platform> per registry key
# ---------------------------------------------------------------------------
# Rendered ONCE, before any repository is read: the same bytes are compared on
# every repository and sent on every write. Colours are lowercased here so the
# comparison is never a case question.
render_desired() {
  jq -n --slurpfile l "$LABELS" --slurpfile p "$REGISTRY" '
    $l[0] as $L | $p[0] as $P
    | ($L.agent_labels) as $A
    | ($L.labels | map({ name: .name, color: (.color | ascii_downcase), description: (.description // "") }))
      + ($P.platforms | to_entries | map(
          .key as $k | (.value.display_name // $k) as $dn
          | {
              name: ($A.prefix + $k),
              color: ($A.color | ascii_downcase),
              description: ($A.description_template | split("{display_name}") | join($dn))
            }))
    | sort_by(.name | ascii_downcase)
  ' >"$WORK/desired.json" 2>/dev/null \
    || setup_die "could not render the desired label set from $LABELS and $REGISTRY"
  jq -e 'type == "array" and length > 0' "$WORK/desired.json" >/dev/null 2>&1 \
    || setup_die "the rendered label set is empty"
}

# ---------------------------------------------------------------------------
# Repository discovery (as github-policy.sh, minus the filters)
# ---------------------------------------------------------------------------
local_repo() {
  local url
  url="$(git -C "$LABELS_REPO_ROOT" remote get-url origin 2>/dev/null)" || return 1
  case "$url" in
    git@github.com:*)       url="${url#git@github.com:}" ;;
    https://github.com/*)   url="${url#https://github.com/}" ;;
    ssh://git@github.com/*) url="${url#ssh://git@github.com/}" ;;
    *) return 1 ;;
  esac
  printf '%s' "${url%.git}"
}

# list_repos_paged <api-path> — TSV: owner/name <TAB> archived
list_repos_paged() {
  local base="$1" page=1 n sep
  while :; do
    case "$base" in *\?*) sep='&' ;; *) sep='?' ;; esac
    api_json "$WORK/page.json" "${base}${sep}per_page=100&page=${page}" || return 1
    n="$(jq 'length' "$WORK/page.json" 2>/dev/null)" || n=0
    [ "${n:-0}" -gt 0 ] || break
    jq -r '.[] | [.full_name, (.archived // false | tostring)] | @tsv' "$WORK/page.json"
    [ "$n" -lt 100 ] && break
    page=$((page + 1))
    [ "$page" -gt 50 ] && { github_warn "stopping repository listing at 5000 repositories"; break; }
  done
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
    jq -e 'has("full_name")' "$WORK/view.json" >/dev/null 2>&1 || {
      github_fail bad_response "repos/$target returned a body with no full_name"; return 1; }
    jq -r '[.full_name, (.archived // false | tostring)] | @tsv' "$WORK/view.json" >"$WORK/raw"
  fi
  local name arch
  while IFS="$(printf '\t')" read -r name arch; do
    [ -n "$name" ] || continue
    printf '%s\t%s\n' "$name" "$arch" >>"$WORK/repolist"
  done <"$WORK/raw"
}

# ---------------------------------------------------------------------------
# Comparison — one repository, pure jq over two arrays
# ---------------------------------------------------------------------------
# diff_labels <live.json> <changes.json>
# Each change: {name, status, live, desired}
#   status: ok | create | update | extra | delete
# `extra` is a live label the set does not name; it becomes `delete` only when
# --prune was typed, and never otherwise.
diff_labels() {
  local prune=false
  [ -n "$OPT_PRUNE" ] && prune=true
  jq -n --slurpfile d "$WORK/desired.json" --slurpfile l "$1" --argjson prune "$prune" '
    ($d[0]) as $want
    | ($l[0] | map({ name: .name, color: ((.color // "") | ascii_downcase), description: (.description // "") })) as $have
    | ($have | map({ key: (.name | ascii_downcase), value: . }) | from_entries) as $byname
    | ($want | map(
        . as $w
        | ($byname[$w.name | ascii_downcase]) as $live
        | if $live == null then { name: $w.name, status: "create", live: null, desired: $w }
          elif ($live.name == $w.name and $live.color == $w.color and $live.description == $w.description)
            then { name: $w.name, status: "ok", live: $live, desired: $w }
          else { name: $w.name, status: "update", live: $live, desired: $w }
          end))
      + ($have
         | map(select((.name | ascii_downcase) as $n | ($want | map(.name | ascii_downcase) | index($n)) == null))
         | map({ name: .name, status: (if $prune then "delete" else "extra" end), live: ., desired: null }))
    | sort_by(.name | ascii_downcase)
  ' >"$2"
}

count_status() { jq -r --arg s "$1" 'map(select(.status == $s)) | length' "$2"; }

# write_summary <changes.json> <out-file> [failed]
write_summary() {
  jq -c --argjson failed "${3:-0}" '{
    ok:     (map(select(.status == "ok"))      | length),
    create: (map(select(.status == "create"))  | length),
    update: (map(select(.status == "update"))  | length),
    extra:  (map(select(.status == "extra"))   | length),
    delete: (map(select(.status == "delete"))  | length),
    failed: $failed
  }' "$1" >"$2"
}

# ---------------------------------------------------------------------------
# Confirmation (apply only)
# ---------------------------------------------------------------------------
CONFIRM_ALL=""
QUIT=""
confirm_repo() {
  local repo="$1" changes="$2" ans
  out ""
  out "──────────────────────────────────────────────────────────────"
  out "$repo · labels"
  out "──────────────────────────────────────────────────────────────"
  print_changes "$changes"
  [ -n "$CONFIRM_ALL" ] && return 0
  [ -n "${SETUP_YES:-}" ] && return 0
  # Into a variable, never `$(setup_ask ...)`: inside a command substitution
  # stdout is the capture pipe, so the prompt would decide "no terminal" and
  # hand back the default without ever asking (setup-common.sh, setup_ask_into).
  setup_ask_into ans 'Apply to this repository? [y/N/a/q] ' n
  ans="$(setup_lower "$ans")"
  case "$ans" in
    y|yes) return 0 ;;
    a|all) CONFIRM_ALL=1; return 0 ;;
    q|quit) QUIT=1; return 1 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
print_changes() {
  local changes="$1" line name status lcolor ldesc dcolor ddesc
  # Fields are joined on the unit separator, not a tab: tab is IFS whitespace
  # to `read`, so two adjacent empty fields (a create has no live colour or
  # description) would collapse and shift every column after them.
  while IFS="$(printf '\037')" read -r name status lcolor ldesc dcolor ddesc; do
    [ -n "$name" ] || continue
    case "$status" in
      ok)     out "  $MARK_OK $name" ;;
      create) out "  $MARK_ADD $(printf '%-28s' "$name") create   #$dcolor  \"$ddesc\"" ;;
      update)
        line=""
        [ "$lcolor" != "$dcolor" ] && line="colour #$lcolor → #$dcolor"
        [ "$ldesc" != "$ddesc" ] && line="${line:+$line; }description \"$ldesc\" → \"$ddesc\""
        [ -z "$line" ] && line="rename → $name"
        out "  $MARK_MOD $(printf '%-28s' "$name") update   $line" ;;
      extra)  out "  · $(printf '%-28s' "$name") extra    not in the canonical set; left alone (--prune deletes it)" ;;
      delete) out "  $MARK_DEL $(printf '%-28s' "$name") delete   not in the canonical set (--prune)" ;;
      failed) out "  $MARK_BAD $(printf '%-28s' "$name") failed   $ldesc" ;;
    esac
  done < <(jq -r '.[] | [
      .name, .status,
      (.live.color // ""), (.live.description // ""),
      (.desired.color // ""), (.desired.description // "")
    ] | join("\u001f")' "$changes")
}

print_repo_report() {
  local d="$1" repo bucket note s
  repo="$(field "$d" repo)"; bucket="$(field "$d" bucket)"; note="$(field "$d" note)"
  out ""
  out "${SETUP_C_BOLD}$repo${SETUP_C_OFF} · labels $LABELS_VERSION · $bucket${note:+ — $note}"
  [ -f "$d/changes.json" ] || return 0
  print_changes "$d/changes.json"
  s="$(cat "$d/summary.json")"
  out ""
  out "  $(jq -r '"\(.ok) ok · \(.create) to create · \(.update) to update · \(.extra) extra · \(.delete) to delete\(if .failed > 0 then " · \(.failed) FAILED" else "" end)"' <<<"$s")"
}

print_bulk_report() {
  local d repo bucket s
  out ""
  out "${SETUP_C_BOLD}Labels $LABELS_VERSION · $REPO_N repositories${SETUP_C_OFF}"
  for d in "$WORK"/repos/*; do
    [ -d "$d" ] || continue
    repo="$(field "$d" repo)"; bucket="$(field "$d" bucket)"
    if [ -f "$d/summary.json" ]; then
      s="$(jq -r '"\(.create) create · \(.update) update · \(.extra + .delete) extra"' "$d/summary.json")"
    else
      s="$(field "$d" note)"
    fi
    out "  $(printf '%-46s %-18s' "$repo" "$bucket") $SETUP_C_DIM$s$SETUP_C_OFF"
  done
}

print_json() {
  local d first=1
  {
    printf '{"verb":%s,"labels_file":%s,"labels_version":%s,"prune":%s,"degraded":%s,"repos":[' \
      "$(jq -Rn --arg v "$VERB" '$v')" "$(jq -Rn --arg v "$LABELS" '$v')" \
      "$(jq -Rn --arg v "$LABELS_VERSION" '$v')" \
      "$([ -n "$OPT_PRUNE" ] && printf true || printf false)" \
      "$([ -n "$DEGRADED" ] && printf true || printf false)"
    for d in "$WORK"/repos/*; do
      [ -d "$d" ] || continue
      [ -n "$first" ] || printf ','
      first=""
      jq -nc \
        --arg repo "$(field "$d" repo)" --arg bucket "$(field "$d" bucket)" \
        --arg note "$(field "$d" note)" \
        --slurpfile changes "$( [ -f "$d/changes.json" ] && printf '%s' "$d/changes.json" || printf '%s' "$WORK/empty.json")" \
        --slurpfile summary "$( [ -f "$d/summary.json" ] && printf '%s' "$d/summary.json" || printf '%s' "$WORK/empty-summary.json")" \
        '{repo: $repo, bucket: $bucket, note: $note, changes: $changes[0], summary: $summary[0]}'
    done
    printf ']}'
  } | jq '. + {summary: (
        [.repos[].summary] | {
          ok: (map(.ok) | add // 0), create: (map(.create) | add // 0), update: (map(.update) | add // 0),
          extra: (map(.extra) | add // 0), delete: (map(.delete) | add // 0), failed: (map(.failed) | add // 0)
        }),
        buckets: ([.repos[].bucket] | group_by(.) | map({key: .[0], value: length}) | from_entries)
      }'
}

# ---------------------------------------------------------------------------
# One repository
# ---------------------------------------------------------------------------
# process_repo <owner/name> <archived> — fills $WORK/repos/NNNN/{repo,bucket,
# note,changes.json,summary.json}. Buckets: compliant | drifted | updated |
# skipped | failed. Never returns non-zero: a failure is a bucket, not an abort,
# so one repository cannot stop a sweep.
process_repo() {
  local repo="$1" archived="$2" d failed=0 name status lname
  REPO_N=$((REPO_N + 1))
  d="$(printf '%s/repos/%04d' "$WORK" "$REPO_N")"
  mkdir -p "$d"
  printf '%s' "$repo" >"$d/repo"
  printf '' >"$d/note"

  if [ "$archived" = "true" ]; then
    printf 'skipped' >"$d/bucket"; printf 'archived — labels on an archived repository are read-only' >"$d/note"
    return 0
  fi

  if ! api_call GET "$d/live.raw" "repos/$repo/labels?per_page=100" ; then
    printf 'failed' >"$d/bucket"; printf '%s' "$(github_explain)" >"$d/note"
    return 0
  fi
  # Pages beyond the first: the library's own pager, for the rare repo with
  # more than 100 labels; the first page above keeps the error class readable.
  if [ "$(jq 'length' "$d/live.raw" 2>/dev/null || echo 0)" -ge 100 ]; then
    if ! github_list_labels "$repo" >"$d/live.raw"; then
      printf 'failed' >"$d/bucket"; printf '%s' "$(github_explain)" >"$d/note"
      return 0
    fi
  fi
  jq -e 'type == "array"' "$d/live.raw" >/dev/null 2>&1 || {
    printf 'failed' >"$d/bucket"; printf 'repos/%s/labels did not return an array' "$repo" >"$d/note"
    return 0
  }

  diff_labels "$d/live.raw" "$d/changes.json"
  write_summary "$d/changes.json" "$d/summary.json"

  local n_create n_update n_delete
  n_create="$(count_status create "$d/changes.json")"
  n_update="$(count_status update "$d/changes.json")"
  n_delete="$(count_status delete "$d/changes.json")"

  if [ "$n_create" = 0 ] && [ "$n_update" = 0 ] && [ "$n_delete" = 0 ]; then
    printf 'compliant' >"$d/bucket"
    return 0
  fi
  if [ "$VERB" != apply ]; then
    printf 'drifted' >"$d/bucket"
    return 0
  fi

  # apply — confirm, then write each change in this shell so the class survives.
  if ! confirm_repo "$repo" "$d/changes.json"; then
    printf 'skipped' >"$d/bucket"; printf 'not confirmed' >"$d/note"
    return 0
  fi
  cp "$d/changes.json" "$d/applied.json"
  while IFS="$(printf '\t')" read -r name status lname; do
    [ -n "$name" ] || continue
    case "$status" in
      create)
        jq -c --arg n "$name" '.[] | select(.name == $n) | .desired | {name, color, description}' "$d/changes.json" >"$d/payload.json"
        if github_create_label "$repo" "$d/payload.json" >/dev/null; then
          vlog "created $name"
        else
          failed=$((failed + 1)); mark_failed "$d/applied.json" "$name" "$(github_explain)"
        fi ;;
      update)
        # The path names the label as it is live; a differing case is a rename
        # and travels in the body as new_name.
        jq -c --arg n "$name" '.[] | select(.name == $n)
          | (.desired | {color, description}) + (if .live.name != .name then {new_name: .name} else {} end)' \
          "$d/changes.json" >"$d/payload.json"
        if github_update_label "$repo" "$lname" "$d/payload.json" >/dev/null; then
          vlog "updated $name"
        else
          failed=$((failed + 1)); mark_failed "$d/applied.json" "$name" "$(github_explain)"
        fi ;;
      delete)
        if github_delete_label "$repo" "$lname"; then
          vlog "deleted $name"
        else
          failed=$((failed + 1)); mark_failed "$d/applied.json" "$name" "$(github_explain)"
        fi ;;
    esac
  done < <(jq -r '.[] | select(.status == "create" or .status == "update" or .status == "delete")
                  | [.name, .status, (.live.name // "")] | @tsv' "$d/changes.json")
  mv "$d/applied.json" "$d/changes.json"
  write_summary "$d/changes.json" "$d/summary.json" "$failed"
  if [ "$failed" -gt 0 ]; then
    printf 'failed' >"$d/bucket"; printf '%s write(s) failed' "$failed" >"$d/note"
  else
    printf 'updated' >"$d/bucket"
  fi
  return 0
}

# mark_failed <changes.json> <name> <reason> — a write that failed keeps its
# row, re-labelled, so the report and the JSON say which one and why.
mark_failed() {
  local f="$1" tmp
  tmp="$(mktemp)"
  jq --arg n "$2" --arg why "$3" 'map(if .name == $n then .status = "failed" | .live = ((.live // {}) + {description: $why}) else . end)' "$f" >"$tmp"
  mv "$tmp" "$f"
}

# ---------------------------------------------------------------------------
main() {
  render_desired
  printf '[]' >"$WORK/empty.json"
  printf '{"ok":0,"create":0,"update":0,"extra":0,"delete":0,"failed":0}' >"$WORK/empty-summary.json"

  build_repo_list || { setup_err "$(github_explain)"; exit 1; }
  if [ ! -s "$WORK/repolist" ]; then
    out "No repositories matched. Nothing to do."
    [ -n "$OPT_JSON" ] && print_json
    exit 0
  fi
  local n_targets
  n_targets="$(wc -l <"$WORK/repolist" | tr -d ' ')"

  if [ "$VERB" = apply ] && [ -n "$BULK" ]; then
    if [ -z "${SETUP_YES:-}" ] && ! setup_can_prompt; then
      setup_note "no TTY — cannot confirm a bulk apply. Showing the plan instead; re-run with --yes to apply."
      VERB="plan"; DEGRADED=1
    else
      out ""
      out "${SETUP_C_YELLOW}About to change labels on up to $n_targets repositories${OPT_PRUNE:+, deleting any the set does not name}.${SETUP_C_OFF}"
      out "Each repository is shown and confirmed separately before anything is written."
      if [ -z "${SETUP_YES:-}" ]; then
        local ans
        setup_ask_into ans "Continue? [y/N] " n
        ans="$(setup_lower "$ans")"
        case "$ans" in y|yes) : ;; *) out "Nothing was written."; exit 0 ;; esac
      fi
    fi
  fi
  if [ "$VERB" = apply ] && [ -z "$BULK" ] && [ -z "${SETUP_YES:-}" ] && ! setup_can_prompt; then
    setup_note "no TTY — cannot confirm. Showing the plan instead; re-run with --yes to apply."
    VERB="plan"; DEGRADED=1
  fi

  local name arch
  while IFS="$(printf '\t')" read -r name arch; do
    [ -n "$name" ] || continue
    [ -n "$QUIT" ] && break
    vlog "processing $name"
    process_repo "$name" "$arch"
    [ -n "$BULK" ] && printf '  %-46s %s\n' "$name" "$(field "$(printf '%s/repos/%04d' "$WORK" "$REPO_N")" bucket)" >&2
  done <"$WORK/repolist"

  # The exit code is decided from the findings BEFORE either renderer runs, so
  # `--json` and the human report can never disagree about it. An early
  # `exit 0` on the JSON path once let a failed label read (bucket "failed")
  # exit 0 while the same audit without --json exited 3.
  local rc; rc="$(exit_status)"

  if [ -n "$OPT_JSON" ]; then
    print_json
    exit "$rc"
  fi

  if [ -n "$BULK" ]; then
    print_bulk_report
  else
    print_repo_report "$WORK/repos/0001"
  fi
  out ""
  case "$VERB" in
    audit) out "  Remediate:  bash scripts/github-labels.sh plan --repo $(field "$WORK/repos/0001" repo)" ;;
    plan)  out "  Nothing has been written. Re-run with 'apply' to make these changes." ;;
    apply) out "  Verify:     bash scripts/github-labels.sh audit --repo $(field "$WORK/repos/0001" repo)" ;;
  esac
  out ""
  exit "$rc"
}

# exit_status — 3 when any repository drifted or failed, else 0; a degraded
# run (apply that printed the plan for want of a terminal) is 0.
# The one place the code is decided; both renderers read it.
exit_status() {
  local rc=0 d
  for d in "$WORK"/repos/*; do
    [ -d "$d" ] || continue
    case "$(field "$d" bucket)" in drifted|failed) rc=3 ;; esac
  done
  [ -n "$DEGRADED" ] && rc=0
  printf '%s' "$rc"
}

main
