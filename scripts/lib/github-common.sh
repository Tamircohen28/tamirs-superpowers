#!/usr/bin/env bash
# github-common.sh — the single GitHub abstraction for repository governance.
#
# Sourced, never executed. Every read and write of branch governance (rulesets,
# classic branch protection, required status checks, default branch) goes through
# here. Before this file the same `gh api` calls were spelled four different ways
# in four scripts, two of them against classic `branches/*/protection`, which 404s
# on a repository that is correctly protected by rulesets — so the scattered code
# reported a governed repo as unprotected. One abstraction, one answer.
#
# PORTABILITY CONTRACT (rules/dev/user-facing-script-standards.md §3)
#   bash 3.2: no associative arrays, no `mapfile`, no `${var^^}`, no `declare -A`.
#   No `timeout(1)`. No GNU-only `sed -i`. Multi-record iteration uses the
#   file-per-record idiom (a directory per record, a file per field).
#
# STDIN CONTRACT (§4)
#   Nothing here reads stdin, and nothing here prompts. `gh` is invoked with
#   stdin redirected from /dev/null so an inherited descriptor can never block a
#   governance read inside a hook or a CI job.
#
# TRANSPORT (rules/dev/gh-cli-preference.md)
#   `gh api` only — never GitHub MCP, never browser automation. `gh` is normally
#   an optional feature dependency, but for this feature the GitHub action IS the
#   request, so a missing or unauthenticated `gh` is a hard, reportable failure
#   with a named class, never a silent skip.

# shellcheck shell=bash

# ---------------------------------------------------------------------------
# Error classification
# ---------------------------------------------------------------------------
# Every call sets these. They are the whole point of the wrapper: a caller must
# be able to tell "this repository has no rulesets" from "your token cannot see
# them", because the first is a plan to apply and the second is a stop.
#
#   ok                 request succeeded
#   no_cli             gh is not installed
#   unauthenticated    no credential, or the credential was rejected (401)
#   insufficient_scope 403 and the token is missing an OAuth scope
#   forbidden          403 and the actor simply lacks permission on this repo
#   org_policy         403/451 raised by an organization or enterprise policy
#   rate_limited       403/429 rate or abuse limit; GITHUB_LAST_RETRY_AFTER set
#   not_found          404 — absent resource, or a resource hidden by permission
#   conflict           409 — the resource changed under us; re-read and retry
#   invalid_request    422 — GitHub rejected the payload we built; our bug
#   unsupported        404/422 for a feature this plan or repo type does not have
#   bad_response       2xx whose body is not the JSON shape we require
#   network            the request never reached GitHub
#   unknown            an HTTP failure none of the above explains
#
# SUBSHELL CONTRACT — read this before using the variables directly.
#   Almost every caller writes `out="$(github_list_rulesets "$r")" || ...`, and
#   a command substitution runs in a SUBSHELL: any variable the callee assigned
#   dies with it, so `$GITHUB_LAST_CLASS` in the parent reads empty and every
#   `[ "$GITHUB_LAST_CLASS" = "not_found" ]` test silently falls through. That
#   bug turned "this repository has no classic protection" — the normal, healthy
#   state — into a hard error, which is the exact failure mode this library was
#   written to eliminate. So the state is ALSO written to files under a
#   per-invocation state dir, and the accessors below read those files.
#
#   `github_last_class` and friends are correct everywhere, always.
#   The GITHUB_LAST_* variables are correct only in the shell that made the
#   call; after a command substitution, call `github_sync_state` to refresh them.
#   When in doubt use the accessor.
GITHUB_LAST_CLASS=""
GITHUB_LAST_HTTP=""
GITHUB_LAST_ERROR=""
GITHUB_LAST_RETRY_AFTER=""
GITHUB_LAST_BODY=""
GITHUB_CLI_SCOPES=""

# `$$` is the PID of the shell that sourced this file and stays stable inside
# command substitutions (unlike $BASHPID), which is precisely the property that
# makes it usable as the handle shared across the subshell boundary.
GITHUB_STATE_DIR="${TMPDIR:-/tmp}/github-common-$$"

github_state_dir() {
  [ -d "$GITHUB_STATE_DIR" ] || mkdir -p "$GITHUB_STATE_DIR" 2>/dev/null
  printf '%s' "$GITHUB_STATE_DIR"
}

# github_state_cleanup — entrypoints should trap this on EXIT.
github_state_cleanup() { [ -n "$GITHUB_STATE_DIR" ] && rm -rf "$GITHUB_STATE_DIR"; return 0; }

# github_set_state <class> <http> <error> <retry_after> — the single writer.
github_set_state() {
  GITHUB_LAST_CLASS="$1"; GITHUB_LAST_HTTP="$2"
  GITHUB_LAST_ERROR="$3"; GITHUB_LAST_RETRY_AFTER="$4"
  local d; d="$(github_state_dir)"
  printf '%s' "$1" >"$d/class"       2>/dev/null
  printf '%s' "$2" >"$d/http"        2>/dev/null
  printf '%s' "$3" >"$d/error"       2>/dev/null
  printf '%s' "$4" >"$d/retry_after" 2>/dev/null
  return 0
}

github_last_class()       { cat "$GITHUB_STATE_DIR/class"       2>/dev/null || printf ''; }
github_last_http()        { cat "$GITHUB_STATE_DIR/http"        2>/dev/null || printf ''; }
github_last_error()       { cat "$GITHUB_STATE_DIR/error"       2>/dev/null || printf ''; }
github_last_retry_after() { cat "$GITHUB_STATE_DIR/retry_after" 2>/dev/null || printf ''; }

# github_sync_state — repopulate the GITHUB_LAST_* variables from the state
# files. Call this after any `$( )` invocation of a github_* function whose
# failure cause you intend to read from the variables.
github_sync_state() {
  GITHUB_LAST_CLASS="$(github_last_class)"
  GITHUB_LAST_HTTP="$(github_last_http)"
  GITHUB_LAST_ERROR="$(github_last_error)"
  GITHUB_LAST_RETRY_AFTER="$(github_last_retry_after)"
  return 0
}

# github_ok — record success.
github_ok() { github_set_state ok "" "" ""; return 0; }

github_say()  { printf '%s\n' "$*" >&2; }
github_warn() { printf 'warning: %s\n' "$*" >&2; }
github_err()  { printf 'error: %s\n' "$*" >&2; }

# github_lower <string> — bash 3.2 has no ${var,,}.
github_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# github_reset_error — clear the last-call state. Called at the top of every
# entry point so a caller never reads a stale class from two calls ago.
github_reset_error() {
  GITHUB_LAST_BODY=""
  github_set_state "" "" "" ""
}

# github_fail <class> <message> — record and return 1.
github_fail() {
  github_set_state "$1" "$GITHUB_LAST_HTTP" "$2" "$GITHUB_LAST_RETRY_AFTER"
  return 1
}

# github_explain — one human line describing the last failure, with the remedy.
# Printing the class alone would be useless to the person who has to fix it.
github_explain() {
  github_sync_state
  case "$GITHUB_LAST_CLASS" in
    ok|"")             printf 'ok\n' ;;
    no_cli)            printf 'gh is not installed — this operation is a GitHub action and has no local substitute. Install it: brew install gh\n' ;;
    unauthenticated)   printf 'gh is not authenticated (HTTP %s) — run: gh auth login\n' "${GITHUB_LAST_HTTP:-401}" ;;
    insufficient_scope) printf 'token is missing an OAuth scope (HTTP 403). Have: [%s]. Run: gh auth refresh -h github.com -s repo -s admin:org\n' "$GITHUB_CLI_SCOPES" ;;
    forbidden)         printf 'permission denied (HTTP 403) — this token is not an admin of the repository. %s\n' "$GITHUB_LAST_ERROR" ;;
    org_policy)        printf 'blocked by an organization or enterprise policy (HTTP %s) — %s\n' "${GITHUB_LAST_HTTP:-403}" "$GITHUB_LAST_ERROR" ;;
    rate_limited)      printf 'GitHub rate limit hit (HTTP %s) — retry after %s seconds\n' "${GITHUB_LAST_HTTP:-403}" "${GITHUB_LAST_RETRY_AFTER:-60}" ;;
    not_found)         printf 'not found (HTTP 404) — the repository or resource does not exist, or this token cannot see it\n' ;;
    conflict)          printf 'conflict (HTTP 409) — the ruleset changed on GitHub since it was read. Re-run plan and diff again before applying; do not retry blindly. %s\n' "$GITHUB_LAST_ERROR" ;;
    invalid_request)   printf 'GitHub rejected the payload (HTTP 422) — %s. This is a bug in the rendered ruleset, not in your permissions.\n' "$GITHUB_LAST_ERROR" ;;
    unsupported)       printf 'unsupported on this repository or plan (HTTP %s) — %s\n' "${GITHUB_LAST_HTTP:-422}" "$GITHUB_LAST_ERROR" ;;
    bad_response)      printf 'unexpected API response shape — %s\n' "$GITHUB_LAST_ERROR" ;;
    network)           printf 'could not reach GitHub — %s\n' "$GITHUB_LAST_ERROR" ;;
    *)                 printf 'unexpected failure (HTTP %s) — %s\n' "${GITHUB_LAST_HTTP:-?}" "$GITHUB_LAST_ERROR" ;;
  esac
}

# ---------------------------------------------------------------------------
# Availability probe — exported so scripts/doctor.sh need not re-implement it
# ---------------------------------------------------------------------------

github_have() { command -v gh >/dev/null 2>&1; }
github_have_jq() { command -v jq >/dev/null 2>&1; }

# github_cli_version — prints the gh semver, or nothing.
github_cli_version() {
  github_have || return 1
  gh --version 2>/dev/null | head -1 | awk '{print $3}'
}

# github_probe — prints one of: missing | unauthenticated | ready
# Side effect: sets GITHUB_CLI_SCOPES when authenticated. This is the canonical
# availability answer; doctor.sh, the entrypoint and the tests all use it rather
# than each writing their own `command -v gh && gh auth status` pair.
github_probe() {
  if ! github_have; then printf 'missing\n'; return 1; fi
  local status
  if ! status="$(gh auth status </dev/null 2>&1)"; then
    printf 'unauthenticated\n'; return 1
  fi
  GITHUB_CLI_SCOPES="$(printf '%s\n' "$status" \
    | sed -n "s/.*Token scopes: //p" | tr -d "'" | tr -s ', ' ' ' | head -1)"
  printf 'ready\n'
  return 0
}

# github_scopes — the token's OAuth scopes, space separated, on stdout.
# Present because github_probe is normally called as `$(github_probe)`, and a
# variable set inside a command substitution dies with the subshell. Anything
# that needs the scope list reads it from here rather than from the side effect.
github_scopes() {
  github_probe >/dev/null 2>&1 || true
  printf '%s' "$GITHUB_CLI_SCOPES"
}

# github_require [<context>] — hard-fail helper for the one exception in
# gh-cli-preference.md §1: when the GitHub action IS the request, absence is a
# reportable failure, not a skip.
github_require() {
  local ctx="${1:-github repository policy}"
  github_reset_error
  github_have_jq || { github_fail bad_response "jq is required by $ctx"; return 1; }
  case "$(github_probe)" in
    missing)          github_fail no_cli "gh is required by $ctx"; return 1 ;;
    unauthenticated)  github_fail unauthenticated "gh is not authenticated; $ctx cannot proceed"; return 1 ;;
  esac
  github_ok
  return 0
}

# github_has_scope <scope> — membership test over the probed scope list, using
# the bash 3.2 substring idiom rather than an array.
github_has_scope() {
  [ -n "$GITHUB_CLI_SCOPES" ] || github_probe >/dev/null 2>&1
  case " $GITHUB_CLI_SCOPES " in
    *" $1 "*) return 0 ;;
    *)        return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# The one request primitive
# ---------------------------------------------------------------------------
# github_api <METHOD> <path> [extra gh api args...]
#
# Prints the response body on stdout. Returns 0 on 2xx, 1 otherwise with
# GITHUB_LAST_CLASS set. Runs with `--include` so the status line and the
# Retry-After / X-OAuth-Scopes headers are available for classification —
# guessing a 403's meaning from its prose is how a rate limit gets reported as a
# permissions problem.
github_api() {
  github_reset_error
  if ! github_have; then
    github_fail no_cli "gh is not installed"
    return 1
  fi

  local method="$1" path="$2"
  shift 2

  local work raw rc
  work="$(mktemp -d)" || { github_fail unknown "could not create a temp dir"; return 1; }

  set -- --include --method "$method" "$path" "$@"
  rc=0
  gh api "$@" </dev/null >"$work/raw" 2>"$work/err" || rc=$?
  raw="$work/raw"

  # Split the last header block from the body. `--include` emits one block per
  # response, so a redirect yields two; the last one is the response we got.
  awk -v hf="$work/hdr" -v bf="$work/body" '
    { line = $0; sub(/\r$/, "", line) }
    line ~ /^HTTP\/[0-9.]+ [0-9][0-9][0-9]/ { inhdr = 1; hdrs = line "\n"; body = ""; next }
    inhdr && line == ""  { inhdr = 0; next }
    inhdr                { hdrs = hdrs line "\n"; next }
                         { body = body line "\n" }
    END { printf "%s", hdrs > hf; printf "%s", body > bf }
  ' "$raw"

  local hdr="$work/hdr" body="$work/body"
  [ -f "$hdr" ]  || : >"$hdr"
  [ -f "$body" ] || : >"$body"

  GITHUB_LAST_HTTP="$(head -1 "$hdr" | awk '{print $2}')"
  GITHUB_LAST_RETRY_AFTER="$(sed -n 's/^[Rr]etry-[Aa]fter: *//p' "$hdr" | tr -d ' \r' | head -1)"
  github_set_state "" "$GITHUB_LAST_HTTP" "" "$GITHUB_LAST_RETRY_AFTER"
  local scopes remaining stderr_txt
  scopes="$(sed -n 's/^[Xx]-[Oo][Aa]uth-[Ss]copes: *//p' "$hdr" | tr -d '\r' | head -1)"
  [ -n "$scopes" ] && GITHUB_CLI_SCOPES="$(printf '%s' "$scopes" | tr -s ', ' ' ')"
  remaining="$(sed -n 's/^[Xx]-[Rr]ate[Ll]imit-[Rr]emaining: *//p' "$hdr" | tr -d ' \r' | head -1)"
  stderr_txt="$(tr -d '\r' <"$work/err" | head -5)"
  GITHUB_LAST_BODY="$(cat "$body")"

  # No status line at all means the request never reached GitHub.
  if [ -z "$GITHUB_LAST_HTTP" ]; then
    rm -rf "$work"
    github_fail network "${stderr_txt:-gh produced no HTTP response}"
    return 1
  fi

  local msg
  msg="$(printf '%s' "$GITHUB_LAST_BODY" | jq -r '.message // empty' 2>/dev/null)"
  [ -n "$msg" ] || msg="$stderr_txt"

  case "$GITHUB_LAST_HTTP" in
    2*)
      rm -rf "$work"
      github_ok
      printf '%s' "$GITHUB_LAST_BODY"
      return 0
      ;;
    401)
      rm -rf "$work"; github_fail unauthenticated "$msg"; return 1 ;;
    429)
      rm -rf "$work"
      [ -n "$GITHUB_LAST_RETRY_AFTER" ] || GITHUB_LAST_RETRY_AFTER=60
      github_fail rate_limited "$msg"; return 1 ;;
    403)
      rm -rf "$work"
      local low; low="$(github_lower "$msg")"
      case "$low" in
        *"rate limit"*|*"abuse"*|*"secondary rate"*)
          [ -n "$GITHUB_LAST_RETRY_AFTER" ] || GITHUB_LAST_RETRY_AFTER=60
          github_fail rate_limited "$msg"; return 1 ;;
      esac
      if [ "$remaining" = "0" ]; then
        [ -n "$GITHUB_LAST_RETRY_AFTER" ] || GITHUB_LAST_RETRY_AFTER=60
        github_fail rate_limited "$msg"; return 1
      fi
      case "$low" in
        *"saml"*|*"sso"*|*"organization has enabled"*|*"enterprise"*|*"ip allow"*|*"policy"*)
          github_fail org_policy "$msg"; return 1 ;;
        *"scope"*|*"oauth"*|*"not accessible by"*|*"fine-grained"*)
          github_fail insufficient_scope "$msg"; return 1 ;;
      esac
      github_fail forbidden "$msg"; return 1 ;;
    404)
      rm -rf "$work"
      local low404; low404="$(github_lower "$msg")"
      case "$low404" in
        *"upgrade"*|*"not available"*)
          github_fail unsupported "$msg"; return 1 ;;
      esac
      github_fail not_found "$msg"; return 1 ;;
    409)
      # A ruleset changed between the read that produced our diff and this write.
      # Distinct from every other class because the correct response is to
      # re-read and re-diff, never to retry the same payload.
      rm -rf "$work"; github_fail conflict "$msg"; return 1 ;;
    422)
      rm -rf "$work"
      local low422 fields; low422="$(github_lower "$msg")"
      case "$low422" in
        *"upgrade"*|*"not available"*|*"plan"*|*"organization"*)
          github_fail unsupported "$msg"; return 1 ;;
      esac
      # Surface the per-field errors: "Validation Failed" alone tells the
      # operator nothing about which rule GitHub objected to.
      fields="$(printf '%s' "$GITHUB_LAST_BODY" \
        | jq -r '[(.errors // [])[] | "\(.resource // "?").\(.field // "?") \(.code // "")"] | join("; ")' 2>/dev/null)"
      [ -n "$fields" ] && msg="$msg ($fields)"
      github_fail invalid_request "$msg"; return 1 ;;
    451)
      rm -rf "$work"; github_fail org_policy "$msg"; return 1 ;;
    5*)
      rm -rf "$work"; github_fail network "GitHub returned $GITHUB_LAST_HTTP — $msg"; return 1 ;;
    *)
      rm -rf "$work"; github_fail unknown "$msg"; return 1 ;;
  esac
}

# github_api_json <METHOD> <path> <jq-guard> [extra args...]
# As github_api, but asserts the body matches a jq boolean guard. A 200 whose
# body is not the shape we expected is `bad_response`, not success — silently
# treating `null` as "no rulesets" would report a governed repo as unprotected.
github_api_json() {
  local method="$1" path="$2" guard="$3"
  shift 3
  local out
  out="$(github_api "$method" "$path" "$@")" || return 1
  if ! printf '%s' "$out" | jq -e "$guard" >/dev/null 2>&1; then
    github_fail bad_response "$method $path returned a body that fails the guard: $guard"
    return 1
  fi
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------

# github_default_branch <owner/repo> — the default branch name, from the API.
# Never guessed from a literal: the governed fleet mixes both spellings.
github_default_branch() {
  local out
  out="$(github_api_json GET "repos/$1" '.default_branch | type == "string" and length > 0')" || return 1
  printf '%s' "$out" | jq -r '.default_branch'
}

# github_repo_view <owner/repo> — the repository object (merge settings live here).
github_repo_view() { github_api_json GET "repos/$1" 'type == "object" and has("default_branch")'; }

# github_list_rulesets <owner/repo> — JSON array of {id, name, target, enforcement}.
# Empty array is a legitimate answer and must not be confused with a failure.
github_list_rulesets() {
  github_api_json GET "repos/$1/rulesets?includes_parents=false" 'type == "array"'
}

# github_ruleset_id <owner/repo> <name> — id of a ruleset by name, empty if absent.
github_ruleset_id() {
  local list
  list="$(github_list_rulesets "$1")" || return 1
  printf '%s' "$list" | jq -r --arg n "$2" '[.[] | select(.name == $n) | .id] | first // empty'
}

# github_get_ruleset <owner/repo> <id> — full detail, including rules and bypass actors.
github_get_ruleset() {
  github_api_json GET "repos/$1/rulesets/$2" 'type == "object" and has("rules")'
}

# github_get_ruleset_by_name <owner/repo> <name>
# Returns 0 with the detail JSON, or 2 (not 1) when the ruleset simply does not
# exist. Absent and failed are different answers and the caller must be able to
# branch on them.
github_get_ruleset_by_name() {
  local id
  id="$(github_ruleset_id "$1" "$2")" || return 1
  if [ -z "$id" ]; then
    github_ok
    return 2
  fi
  github_get_ruleset "$1" "$id"
}

# github_classic_protection <owner/repo> <branch>
# Legacy branch protection. Returns 0 with JSON when present, 2 when absent
# (the common, healthy case on a rulesets-governed repo — a 404 here is NOT an
# error), 1 on a real failure.
github_classic_protection() {
  local out
  if out="$(github_api GET "repos/$1/branches/$2/protection")"; then
    printf '%s' "$out"
    return 0
  fi
  # ACCESSOR, not the variable: github_api ran inside the `$( )` above, so the
  # variable it set is already gone. Reading it here is the bug this library
  # exists to prevent — an absent classic protection would read as a failure.
  if [ "$(github_last_class)" = "not_found" ]; then
    github_ok
    return 2
  fi
  return 1
}

# github_effective_required_checks <owner/repo>
# The answer to "what actually gates a merge here", across both mechanisms.
# Prints tab-separated records on stdout:
#   source<TAB>rulesets|classic|none
#   strict<TAB>true|false
#   context<TAB><name>            (zero or more)
github_effective_required_checks() {
  local repo="$1" list ids d strict rc

  list="$(github_list_rulesets "$repo")" || return 1
  ids="$(printf '%s' "$list" | jq -r '.[] | select(.target == "branch") | .id')"

  local found=no
  local work; work="$(mktemp -d)" || { github_fail unknown "could not create a temp dir"; return 1; }
  : >"$work/contexts"
  : >"$work/strict"

  for id in $ids; do
    d="$(github_get_ruleset "$repo" "$id")" || { rm -rf "$work"; return 1; }
    printf '%s' "$d" | jq -r '
      (.rules // [])[] | select(.type == "required_status_checks")
      | (.parameters.required_status_checks // [])[] | .context
    ' >>"$work/contexts"
    printf '%s' "$d" | jq -r '
      (.rules // [])[] | select(.type == "required_status_checks")
      | (.parameters.strict_required_status_checks_policy // false) | tostring
    ' >>"$work/strict"
  done

  if [ -s "$work/strict" ]; then
    found=yes
    printf 'source\trulesets\n'
    # Any ruleset demanding strict makes the merge gate strict.
    if grep -qx 'true' "$work/strict"; then strict=true; else strict=false; fi
    printf 'strict\t%s\n' "$strict"
    sort -u "$work/contexts" | while IFS= read -r c; do
      [ -n "$c" ] && printf 'context\t%s\n' "$c"
    done
  fi
  rm -rf "$work"

  if [ "$found" = "yes" ]; then
    github_ok
    return 0
  fi

  # No ruleset-based checks — fall back to classic protection before concluding
  # "unprotected". This is the exact bug the old scattered code had, inverted.
  local branch prot
  branch="$(github_default_branch "$repo")" || return 1
  rc=0
  prot="$(github_classic_protection "$repo" "$branch")" || rc=$?
  if [ "$rc" = "0" ]; then
    printf 'source\tclassic\n'
    printf 'strict\t%s\n' "$(printf '%s' "$prot" | jq -r '.required_status_checks.strict // false')"
    printf '%s' "$prot" | jq -r '(.required_status_checks.contexts // [])[] | "context\t" + .'
    github_ok
    return 0
  elif [ "$rc" = "2" ]; then
    printf 'source\tnone\n'
    printf 'strict\tfalse\n'
    github_ok
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Rendering and the idempotence primitive
# ---------------------------------------------------------------------------

# github_json_normalize — stdin JSON, canonical sorted 2-space rendering on
# stdout. Both sides of every comparison go through this, so "is it already up
# to date" is a content question and never a key-order or whitespace question.
github_json_normalize() { jq -S --indent 2 '.'; }

# github_ruleset_normalize — stdin: either a live ruleset detail or a rendered
# desired payload. stdout: the comparable subset, canonically ordered.
#
# Server-owned fields (id, timestamps, _links, source, current_user_can_bypass)
# are dropped because they can never match by construction. bypass_actors is
# deliberately KEPT and defaulted to []: an actor added on github.com is real
# drift, and dropping the field would hide the one change that silently defeats
# a ruleset. Rules are sorted by type and reduced to {type, parameters} so a
# future server-side annotation on a rule does not read as a diff.
github_ruleset_normalize() {
  jq -S --indent 2 '
    {
      name:          .name,
      target:        (.target // "branch"),
      enforcement:   .enforcement,
      conditions:    (.conditions // {}),
      bypass_actors: ((.bypass_actors // []) | sort_by(tostring)),
      rules: ((.rules // [])
              | map({ type: .type, parameters: (.parameters // {}) })
              | sort_by(.type))
    }
  '
}

# github_policy_render_ruleset <policy-file> <ruleset-key> <owner/repo>
# The desired GitHub API payload for one ruleset on one repository, already
# normalized. Resolution order: canonical ruleset -> repository override.
#
#   * `_comment` and `key` are stripped — they are ours, not GitHub's.
#   * rules listed in the repository's `rules.disable` are removed.
#   * `rules.enforcement` overrides the ruleset's enforcement.
#   * required_status_checks contexts come from the repository override paired
#     with the account-wide integration_id, never from the canonical file.
#   * when a repository resolves to ZERO contexts the required_status_checks
#     rule is dropped entirely. A status-check rule gating on nothing is not a
#     weaker gate, it is a lie in the UI.
github_policy_render_ruleset() {
  local policy="$1" key="$2" repo="$3"
  [ -f "$policy" ] || { github_fail bad_response "policy file not found: $policy"; return 1; }

  local out
  out="$(jq --arg key "$key" --arg repo "$repo" '
    . as $p
    | ($p.rulesets[] | select(.key == $key)) as $rs
    | ($p.repositories[$repo] // {}) as $ov
    | ($p.required_checks.integration_id) as $iid
    | ($ov.required_checks.contexts // $p.required_checks.default_contexts) as $ctx
    | ($ov.rules.disable // []) as $disable
    | {
        name:          $rs.name,
        target:        $rs.target,
        enforcement:   ($ov.rules.enforcement // $rs.enforcement),
        conditions:    $rs.conditions,
        bypass_actors: $rs.bypass_actors,
        rules: (
          $rs.rules
          | map(select(.type as $t | $disable | index($t) | not))
          | map(del(._comment))
          | map(
              if .type == "required_status_checks"
              then .parameters.required_status_checks =
                     ($ctx | map({ context: ., integration_id: $iid }))
              else . end
            )
          | map(select(
              (.type != "required_status_checks")
              or ((.parameters.required_status_checks | length) > 0)
            ))
        )
      }
  ' "$policy" 2>/dev/null)" || { github_fail bad_response "could not render ruleset '$key' from $policy"; return 1; }

  if [ -z "$out" ] || [ "$out" = "null" ]; then
    github_fail bad_response "policy $policy declares no ruleset with key '$key'"
    return 1
  fi
  printf '%s' "$out" | github_ruleset_normalize
}

# github_ruleset_matches <policy-file> <ruleset-key> <owner/repo>
# The idempotence primitive everything downstream rests on. Returns:
#   0  live content equals desired content — a no-op, proven by content
#   2  the ruleset does not exist on the repository yet
#   3  it exists and differs; the unified diff is on stdout
#   1  the comparison could not be made; GITHUB_LAST_CLASS says why
github_ruleset_matches() {
  local policy="$1" key="$2" repo="$3"
  local desired live name rc work

  name="$(jq -r --arg k "$key" '.rulesets[] | select(.key == $k) | .name' "$policy" 2>/dev/null)"
  [ -n "$name" ] || { github_fail bad_response "no ruleset with key '$key' in $policy"; return 1; }

  desired="$(github_policy_render_ruleset "$policy" "$key" "$repo")" || return 1

  rc=0
  live="$(github_get_ruleset_by_name "$repo" "$name")" || rc=$?
  [ "$rc" = "1" ] && return 1
  [ "$rc" = "2" ] && return 2

  work="$(mktemp -d)" || { github_fail unknown "could not create a temp dir"; return 1; }
  printf '%s\n' "$desired" >"$work/desired"
  printf '%s' "$live" | github_ruleset_normalize >"$work/live"

  if cmp -s "$work/desired" "$work/live"; then
    rm -rf "$work"
    github_ok
    return 0
  fi
  diff -u "$work/live" "$work/desired" 2>/dev/null | sed '1,2d'
  rm -rf "$work"
  github_ok
  return 3
}

# github_verify_policy <policy-file> <owner/repo>
# Read-only verification of the whole policy against one repository. Prints one
# tab-separated record per ruleset:  <key><TAB>up_to_date|absent|drifted|error
# Returns 0 when every ruleset is up to date, 3 when any drifts or is absent,
# 1 when any check could not be made.
github_verify_policy() {
  local policy="$1" repo="$2" key rc worst=0
  for key in $(jq -r '.rulesets[].key' "$policy"); do
    rc=0
    github_ruleset_matches "$policy" "$key" "$repo" >/dev/null || rc=$?
    case "$rc" in
      0) printf '%s\tup_to_date\n' "$key" ;;
      2) printf '%s\tabsent\n' "$key";  [ "$worst" -lt 3 ] && worst=3 ;;
      3) printf '%s\tdrifted\n' "$key"; [ "$worst" -lt 3 ] && worst=3 ;;
      *) printf '%s\terror\t%s\n' "$key" "$(github_last_class)"; worst=1 ;;
    esac
  done
  [ "$worst" = "1" ] && return 1
  return "$worst"
}

# ---------------------------------------------------------------------------
# Writes — every one of these mutates live branch governance
# ---------------------------------------------------------------------------
# Callers are responsible for confirming with the user first (core/global-rules.md:
# "Before mutating live infrastructure … state the side effect and confirm").
# Nothing in this file prompts, and nothing calls these on its own.

# github_create_ruleset <owner/repo> <payload-file>
github_create_ruleset() {
  github_api_json POST "repos/$1/rulesets" 'has("id")' --input "$2"
}

# github_update_ruleset <owner/repo> <ruleset-id> <payload-file>
github_update_ruleset() {
  github_api_json PUT "repos/$1/rulesets/$2" 'has("id")' --input "$3"
}

# github_delete_ruleset <owner/repo> <ruleset-id>
github_delete_ruleset() {
  github_api DELETE "repos/$1/rulesets/$2" >/dev/null
}

# github_render_payload_file <policy-file> <ruleset-key> <owner/repo> <out-file>
# The write path's companion to the render above: the same content, written
# where `gh api --input` can read it. Rendering once and diffing the same bytes
# that get sent is what makes "no-op" provable rather than asserted.
github_render_payload_file() {
  local out; out="$(github_policy_render_ruleset "$1" "$2" "$3")" || return 1
  printf '%s\n' "$out" >"$4"
}
