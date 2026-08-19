#!/usr/bin/env bash
# fake-gh.sh — a recording, fixture-serving `gh` that never touches the network.
#
# WHY THIS EXISTS
#   The GitHub-policy feature creates and updates *branch rulesets* across the
#   author's real repositories. A test suite for it that reached the real API
#   would either mutate live governance or, if it declined to, prove nothing. So
#   every test runs against this shim: `gh` resolved from a temp bin dir, canned
#   responses read from fixture files, and every invocation appended to a log so
#   a test can assert exactly what *would* have been sent — including asserting
#   that a dry run sent nothing at all.
#
#   It generalizes `fake_gh_install` in tests/lib/fake-agent.sh, which records
#   argv and stubs two subcommands but cannot return a response body. That one is
#   still right for the orchestration sims; this one is for API-shaped tests.
#   fake-agent.sh is deliberately left untouched — the two coexist, and a suite
#   picks whichever it needs. Do not source both into one shell: they both define
#   `gh_calls`, over different logs.
#
# ONE FILE, TWO ROLES
#   Sourced, it exports the install/assert helpers. Executed, it *is* the shim
#   (`$bindir/gh` is a two-line wrapper that execs this file). fake-agent.sh
#   heredocs the whole program into the shim, which is fine for ten lines but
#   would put ~250 lines of parser beyond shellcheck's reach. Same shape — a
#   heredoc'd executable on PATH — with the body kept lintable.
#
# INTERFACE
#   fake_gh_install <bindir> <logfile> <fixture_dir>   install + export env
#   fake_gh_use_fixtures <fixture_dir>                 swap scenarios mid-test
#   fake_gh_error <METHOD|ANY> <path-glob> <status>    inject an HTTP error
#   fake_gh_reset                                      clear log, errors, counters
#   gh_calls <pattern>                                 count matching invocations
#   gh_mutations                                       count non-GET invocations
#   gh_last_body <n>                                   body of the n-th-last mutation
#   gh_log                                             cat the raw log (debugging)
#
# LOG FORMAT — one tab-separated line per invocation:
#   <seq>\t<method>\t<path>\t<body>\t<argv>
#   `method` is GET for reads, the real verb for writes; `body` is `-` when there
#   was none, otherwise the request body compacted to one line. `argv` is the raw
#   command line, which is what `gh_calls` greps.
#
# bash 3.2: no associative arrays, no mapfile, no ${var^^}.

# shellcheck shell=bash

_FGH_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ---------------------------------------------------------------------------
# Install / configure  (sourced side)
# ---------------------------------------------------------------------------

# fake_gh_install <bindir> <logfile> <fixture_dir>
#
# Writes an executable `gh` into <bindir> and exports the environment the shim
# reads. The caller is responsible for putting <bindir> FIRST on PATH — that is
# the whole hermeticity boundary, so it stays visible in the test rather than
# hidden in here.
fake_gh_install() {
  local bindir="$1" log="$2" fixtures="$3"
  mkdir -p "$bindir"
  : > "$log"

  FAKE_GH_LOG="$log"
  FAKE_GH_STATE="$(dirname "$log")/.fake-gh-state"
  FAKE_GH_ERRORS="$FAKE_GH_STATE/errors.txt"
  rm -rf "$FAKE_GH_STATE"
  mkdir -p "$FAKE_GH_STATE"
  : > "$FAKE_GH_ERRORS"
  export FAKE_GH_LOG FAKE_GH_STATE FAKE_GH_ERRORS

  fake_gh_use_fixtures "$fixtures"

  cat > "$bindir/gh" <<SHIM
#!/usr/bin/env bash
# Installed by tests/lib/fake-gh.sh. Serves fixtures; never reaches the network.
exec bash "$_FGH_SELF" "\$@"
SHIM
  chmod +x "$bindir/gh"
}

# fake_gh_use_fixtures <fixture_dir> — point the shim at a different scenario.
# The shared last-resort dir is <fixture_dir>/../_defaults, so scenarios only
# have to carry the responses that make them that scenario.
fake_gh_use_fixtures() {
  FAKE_GH_FIXTURES="$(cd "$1" && pwd)"
  FAKE_GH_DEFAULTS="$(cd "$FAKE_GH_FIXTURES/.." && pwd)/_defaults"
  export FAKE_GH_FIXTURES FAKE_GH_DEFAULTS
  # Sequenced fixtures are per-scenario; a scenario swap restarts them.
  rm -f "$FAKE_GH_STATE"/seq-* 2>/dev/null || true
}

# fake_gh_error <METHOD|ANY> <path-glob> <status>
#
# status is one of: 401 403 403-rate-limit 404 409 422. Injected rules are
# consulted before fixtures and before the scenario's own errors.txt, so a test
# can turn one call into a failure without editing a fixture. <path-glob> is a
# bash `case` pattern matched against the API path with no leading slash, e.g.
# 'repos/*/*/rulesets'.
fake_gh_error() { printf '%s %s %s\n' "$1" "$2" "$3" >> "$FAKE_GH_ERRORS"; }

# fake_gh_reset — forget every recorded call, injected error and sequence cursor.
fake_gh_reset() {
  : > "$FAKE_GH_LOG"
  : > "$FAKE_GH_ERRORS"
  rm -f "$FAKE_GH_STATE"/seq-* "$FAKE_GH_STATE/seqno" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Assertions  (sourced side)
# ---------------------------------------------------------------------------

# gh_calls <pattern> — recorded invocations whose log line matches (argv included).
gh_calls() { grep -c -- "$1" "$FAKE_GH_LOG" 2>/dev/null || true; }

# gh_mutations — recorded invocations that were not GETs. `0` here is the proof
# that a dry run stayed a dry run.
gh_mutations() { awk -F'\t' '$2 != "GET" { n++ } END { print n + 0 }' "$FAKE_GH_LOG"; }

# gh_last_body <n> — request body of the n-th mutation counting back from the
# end (n=1 is the most recent). Empty when there is no such mutation.
gh_last_body() {
  local n="${1:-1}"
  awk -F'\t' '$2 != "GET" { print $4 }' "$FAKE_GH_LOG" | tail -n "$n" | head -n 1
}

# gh_log — the raw log, for a failing test's error message.
gh_log() { cat "$FAKE_GH_LOG"; }

# ---------------------------------------------------------------------------
# The shim  (executed side)
# ---------------------------------------------------------------------------

# Exit 78 is reserved for "the mock does not know how to answer this". It is
# distinct from 1 (an HTTP error the mock produced on purpose) so a test can tell
# a missing fixture apart from a simulated failure instead of reading them both
# as "the command failed".
_FGH_EX_UNMAPPED=78

_fgh_die() {
  printf 'fake-gh: %s\n' "$1" >&2
  printf 'fake-gh: fixtures=%s defaults=%s\n' "${FAKE_GH_FIXTURES:-unset}" "${FAKE_GH_DEFAULTS:-unset}" >&2
  exit "$_FGH_EX_UNMAPPED"
}

_fgh_compact() {
  local body="$1"
  [ -n "$body" ] || { printf '%s' '-'; return; }
  printf '%s' "$body" | jq -c . 2>/dev/null || printf '%s' "$body" | tr '\n\t' '  '
}

_fgh_log() {
  local n
  mkdir -p "$FAKE_GH_STATE"
  n=$(cat "$FAKE_GH_STATE/seqno" 2>/dev/null || echo 0)
  n=$((n + 1))
  printf '%s\n' "$n" > "$FAKE_GH_STATE/seqno"
  printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$1" "$2" "$(_fgh_compact "$3")" "$4" >> "$FAKE_GH_LOG"
}

# _fgh_fixture_name <path> — the fixture basename an API path maps to, or empty.
#
# Matching is on "<slash-count>:<path>", not on the path alone. A bash `case`
# glob matches `/` like any other character, so a bare `repos/*/*` also matches
# `repos/o/r/collaborators` — which made an unmapped sub-resource silently
# return repository metadata with exit 0. tests/test-fake-gh.sh caught that; the
# segment count is what keeps each pattern to the shape it names.
_fgh_fixture_name() {
  local p="$1" n
  n="$(printf '%s' "$p" | tr -cd '/' | wc -c | tr -d ' ')"
  case "$n:$p" in
    4:repos/*/*/rulesets/*)            printf 'ruleset-%s' "${p##*/}" ;;
    3:repos/*/*/rulesets)              printf 'rulesets' ;;
    5:repos/*/*/branches/*/protection) printf 'protection' ;;
    4:repos/*/*/actions/workflows)     printf 'workflows' ;;
    4:repos/*/*/actions/runs)          printf 'runs' ;;
    3:orgs/*/rulesets/*)               printf 'org-ruleset-%s' "${p##*/}" ;;
    2:orgs/*/rulesets)                 printf 'org-rulesets' ;;
    1:user/repos|2:users/*/repos|2:orgs/*/repos) printf 'repo-list' ;;
    0:rate_limit)                      printf 'rate-limit' ;;
    0:user)                            printf 'user' ;;
    2:repos/*/*)                       printf 'repo' ;;
    *)                                 printf '' ;;
  esac
}

# _fgh_resolve <method> <owner> <repo> <name> — first fixture file that exists,
# or empty. Per-repo overrides win, so a fleet test can give 19 repos 19 states
# out of one scenario dir.
_fgh_resolve() {
  local method="$1" owner="$2" repo="$3" name="$4" c seqdir n
  for c in \
    "$FAKE_GH_FIXTURES/by-repo/${owner}__${repo}/$method-$name.json" \
    "$FAKE_GH_FIXTURES/by-repo/${owner}__${repo}/$name.json" \
    "$FAKE_GH_FIXTURES/$method-$name.json"; do
    [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done

  # Sequenced fixture: <name>.seq/1.json, 2.json, ... Serves each in turn and
  # then repeats the last, which is how "apply, then re-read and see the new
  # state" is expressed without the mock having to model GitHub's semantics.
  seqdir="$FAKE_GH_FIXTURES/$name.seq"
  if [ -d "$seqdir" ]; then
    n=$(cat "$FAKE_GH_STATE/seq-$name" 2>/dev/null || echo 0)
    n=$((n + 1))
    while [ "$n" -gt 1 ] && [ ! -f "$seqdir/$n.json" ]; do n=$((n - 1)); done
    printf '%s\n' "$n" > "$FAKE_GH_STATE/seq-$name"
    [ -f "$seqdir/$n.json" ] && { printf '%s' "$seqdir/$n.json"; return 0; }
  fi

  for c in \
    "$FAKE_GH_FIXTURES/$name.json" \
    "$FAKE_GH_DEFAULTS/$method-$name.json" \
    "$FAKE_GH_DEFAULTS/$name.json"; do
    [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done

  # Last resort, WRITES ONLY: _defaults/POST.json and friends. A write test
  # asserts on the body that was sent, so demanding a bespoke response fixture
  # for every mutation would be ceremony. Reads get no such fallback — an
  # unmapped GET must fail, or the mock would answer questions it does not know.
  if [ "$method" != "GET" ] && [ -f "$FAKE_GH_DEFAULTS/$method.json" ]; then
    printf '%s' "$FAKE_GH_DEFAULTS/$method.json"
    return 0
  fi
  return 1
}

# _fgh_injected <method> <path> — echo the status token for the first matching
# error rule, or nothing. Runtime injections first, then the scenario's own
# errors.txt (so a scenario can BE "the 403 one" without any test setup).
_fgh_injected() {
  local method="$1" path="$2" f m pat st
  for f in "$FAKE_GH_ERRORS" "$FAKE_GH_FIXTURES/errors.txt"; do
    [ -f "$f" ] || continue
    while read -r m pat st; do
      case "$m" in ''|'#'*) continue ;; esac
      [ -n "$st" ] || continue
      if [ "$m" = "ANY" ] || [ "$m" = "$method" ]; then
        # shellcheck disable=SC2254  # pat is intentionally a glob
        case "$path" in $pat) printf '%s' "$st"; return 0 ;; esac
      fi
    done < "$f"
  done
  return 1
}

# _fgh_error_body <status-token> — GitHub's real error envelope. A scenario may
# override any of these with errors/<token>.json.
_fgh_error_body() {
  local tok="$1" over="$FAKE_GH_FIXTURES/errors/$1.json"
  [ -f "$over" ] && { cat "$over"; return; }
  case "$tok" in
    401) cat <<'J'
{"message":"Bad credentials","documentation_url":"https://docs.github.com/rest","status":"401"}
J
      ;;
    403) cat <<'J'
{"message":"Resource not accessible by personal access token","documentation_url":"https://docs.github.com/rest/repos/rules#get-all-repository-rulesets","status":"403"}
J
      ;;
    403-rate-limit) cat <<'J'
{"message":"API rate limit exceeded for user ID 12345.","documentation_url":"https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting","status":"403"}
J
      ;;
    404) cat <<'J'
{"message":"Not Found","documentation_url":"https://docs.github.com/rest/repos/rules#get-a-repository-ruleset","status":"404"}
J
      ;;
    409) cat <<'J'
{"message":"Conflict","documentation_url":"https://docs.github.com/rest/repos/rules#update-a-repository-ruleset","status":"409"}
J
      ;;
    422) cat <<'J'
{"message":"Validation Failed","errors":[{"resource":"Ruleset","code":"invalid","field":"rules"}],"documentation_url":"https://docs.github.com/rest/repos/rules#create-a-repository-ruleset","status":"422"}
J
      ;;
    *) _fgh_die "unknown error status token '$tok' (use 401|403|403-rate-limit|404|409|422)" ;;
  esac
}

_fgh_error_code() { case "$1" in 403-rate-limit) printf '403' ;; *) printf '%s' "$1" ;; esac; }

# _fgh_fail <status-token> — emit like `gh api` does on a non-2xx: body on
# stdout, a one-line summary on stderr, exit 1. Rate limiting additionally
# surfaces Retry-After, which is the only thing a backoff path can key on.
_fgh_fail() {
  local tok="$1" body code msg
  body="$(_fgh_error_body "$tok")"
  code="$(_fgh_error_code "$tok")"
  msg="$(printf '%s' "$body" | jq -r '.message')"
  if [ "$_FGH_INCLUDE" = "yes" ]; then
    printf 'HTTP/2.0 %s\n' "$code"
    [ "$tok" = "403-rate-limit" ] && printf 'retry-after: 60\nx-ratelimit-remaining: 0\nx-ratelimit-reset: 1755620000\n'
    printf '\n'
  fi
  printf '%s\n' "$body"
  if [ "$tok" = "403-rate-limit" ]; then
    printf 'retry-after: 60\n' >&2
    printf 'x-ratelimit-remaining: 0\n' >&2
  fi
  printf 'gh: %s (HTTP %s)\n' "$msg" "$code" >&2
  exit 1
}

# _fgh_emit <file> — stdout for a successful call, honouring --jq/-i/--silent.
_fgh_emit() {
  local f="$1"
  [ "$_FGH_SILENT" = "yes" ] && return 0
  if [ "$_FGH_INCLUDE" = "yes" ]; then
    printf 'HTTP/2.0 200\ncontent-type: application/json\nx-ratelimit-remaining: 4999\n\n'
  fi
  if [ -n "$_FGH_JQ" ]; then
    jq -r "$_FGH_JQ" < "$f"
  else
    cat "$f"
  fi
}

# _fgh_api <args...> — `gh api`.
_fgh_api() {
  local method="" path="" body="" fields="{}" k v arg owner repo name fixture tok
  while [ "$#" -gt 0 ]; do
    arg="$1"
    case "$arg" in
      -X|--method)   method="$2"; shift 2 ;;
      -H|--header)   shift 2 ;;
      -q|--jq)       _FGH_JQ="$2"; shift 2 ;;
      -t|--template) shift 2 ;;
      --silent)      _FGH_SILENT=yes; shift ;;
      -i|--include)  _FGH_INCLUDE=yes; shift ;;
      --paginate|--cache|--verbose) shift ;;
      --input)
        if [ "$2" = "-" ]; then body="$(cat)"; else body="$(cat "$2")"; fi
        shift 2 ;;
      -f|--raw-field|-F|--field)
        k="${2%%=*}"; v="${2#*=}"
        if [ "$arg" = "-F" ] || [ "$arg" = "--field" ]; then
          # -F is typed: valid JSON stays JSON, anything else is a string.
          if printf '%s' "$v" | jq -e . >/dev/null 2>&1; then
            fields="$(printf '%s' "$fields" | jq --arg k "$k" --argjson v "$v" '.[$k]=$v')"
          else
            fields="$(printf '%s' "$fields" | jq --arg k "$k" --arg v "$v" '.[$k]=$v')"
          fi
        else
          fields="$(printf '%s' "$fields" | jq --arg k "$k" --arg v "$v" '.[$k]=$v')"
        fi
        shift 2 ;;
      -*) shift ;;
      *)  [ -n "$path" ] || path="$arg"; shift ;;
    esac
  done

  [ "$fields" = "{}" ] || body="$fields"
  path="${path#/}"
  path="${path%%\?*}"
  [ -n "$path" ] || _fgh_die "gh api called without a path"

  # Real gh: no -X and a body means POST.
  if [ -z "$method" ]; then
    if [ -n "$body" ] && [ "$body" != "{}" ]; then method=POST; else method=GET; fi
  fi

  _fgh_log "$method" "$path" "$body" "$_FGH_ARGV"

  if tok="$(_fgh_injected "$method" "$path")"; then _fgh_fail "$tok"; fi

  owner="$(printf '%s' "$path" | cut -d/ -f2)"
  repo="$(printf '%s' "$path" | cut -d/ -f3)"
  name="$(_fgh_fixture_name "$path")"
  [ -n "$name" ] || _fgh_die "no fixture mapping for path '$path' (method $method)"

  if fixture="$(_fgh_resolve "$method" "$owner" "$repo" "$name")"; then
    _fgh_emit "$fixture"
  else
    _fgh_die "no fixture for $method $path (looked for '$name.json' under the scenario, then _defaults)"
  fi
}

# _fgh_repo <args...> — `gh repo view|list|create`.
_fgh_repo() {
  local sub="${1:-}" fixture
  shift || true
  local arg json_fields="" want_jq=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json) json_fields="$2"; shift 2 ;;
      -q|--jq) want_jq="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$want_jq" ] && _FGH_JQ="$want_jq"

  case "$sub" in
    view)
      _fgh_log GET "gh:repo/view" "" "$_FGH_ARGV"
      fixture="$(_fgh_resolve GET "" "" repo-view)" \
        || _fgh_die "no fixture for 'gh repo view' (expected repo-view.json)"
      _fgh_emit "$fixture" ;;
    list)
      _fgh_log GET "gh:repo/list" "" "$_FGH_ARGV"
      fixture="$(_fgh_resolve GET "" "" repo-list)" \
        || _fgh_die "no fixture for 'gh repo list' (expected repo-list.json)"
      if [ -z "$_FGH_JQ" ] && [ -z "$json_fields" ]; then
        # Tabular form, as gh prints when --json is absent.
        jq -r '.[] | [.nameWithOwner, (.description // ""), (if .isPrivate then "private" else "public" end)] | @tsv' < "$fixture"
      else
        _fgh_emit "$fixture"
      fi ;;
    create)
      _fgh_log POST "gh:repo/create" "" "$_FGH_ARGV"
      printf 'https://github.com/example/example\n' ;;
    *) _fgh_die "unsupported 'gh repo' subcommand: ${sub:-<none>}" ;;
  esac
}

# _fgh_auth <args...> — `gh auth status|token`.
_fgh_auth() {
  local sub="${1:-}" tok fixture
  case "$sub" in
    status)
      _fgh_log GET "gh:auth/status" "" "$_FGH_ARGV"
      if tok="$(_fgh_injected GET "gh:auth/status")"; then _fgh_fail "$tok"; fi
      fixture=""
      [ -f "$FAKE_GH_FIXTURES/auth-status.txt" ] && fixture="$FAKE_GH_FIXTURES/auth-status.txt"
      [ -n "$fixture" ] || { [ -f "$FAKE_GH_DEFAULTS/auth-status.txt" ] && fixture="$FAKE_GH_DEFAULTS/auth-status.txt"; }
      if [ -n "$fixture" ]; then
        cat "$fixture"
      else
        printf 'github.com\n  ✓ Logged in to github.com account Tamircohen28 (keyring)\n  - Token scopes: %s\n' \
          "'admin:org', 'admin:public_key', 'delete_repo', 'gist', 'repo', 'workflow'"
      fi ;;
    token)
      _fgh_log GET "gh:auth/token" "" "$_FGH_ARGV"
      if tok="$(_fgh_injected GET "gh:auth/token")"; then _fgh_fail "$tok"; fi
      printf 'gho_fakeTokenForTestsOnly\n' ;;
    *) _fgh_die "unsupported 'gh auth' subcommand: ${sub:-<none>}" ;;
  esac
}

_fgh_main() {
  _FGH_ARGV="$*"
  _FGH_JQ=""
  _FGH_SILENT=no
  _FGH_INCLUDE=no
  : "${FAKE_GH_LOG:?fake-gh: FAKE_GH_LOG unset — call fake_gh_install}"
  : "${FAKE_GH_FIXTURES:?fake-gh: FAKE_GH_FIXTURES unset — call fake_gh_install}"
  : "${FAKE_GH_STATE:=$(dirname "$FAKE_GH_LOG")/.fake-gh-state}"
  : "${FAKE_GH_ERRORS:=$FAKE_GH_STATE/errors.txt}"

  local sub="${1:-}"
  shift || true
  case "$sub" in
    api)  _fgh_api "$@" ;;
    repo) _fgh_repo "$@" ;;
    auth) _fgh_auth "$@" ;;
    --version|version) printf 'gh version 2.62.0 (fake-gh)\n' ;;
    *) _fgh_die "unsupported gh subcommand: ${sub:-<none>}" ;;
  esac
}

# Executed (not sourced) → this process IS the gh the test called. The explicit
# `exit $?` matters: without it the script would fall off the end and return 0,
# hiding any non-zero status the handler produced.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  _fgh_main "$@"
  exit $?
fi
