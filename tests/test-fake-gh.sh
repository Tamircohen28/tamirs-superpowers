#!/usr/bin/env bash
# test-fake-gh.sh — tests for the mock, not with it.
#
# WHY TEST A TEST DOUBLE
#   Every GitHub-policy test is only as trustworthy as this shim. A mock that
#   returns empty on an unmapped path, or forgets to record a POST, turns a whole
#   suite green while proving nothing — and this session has already been bitten
#   three times by exactly that shape of silent pass: a `jq //` swallowing
#   `false`, a `$(case …)` capturing shell source, a detector matching the wrong
#   quoting. So: the shim serves the right fixture, records what it was asked to
#   send, produces each error class faithfully, fails LOUDLY when it does not
#   know an answer, and provably never reaches the network.
#
#   The last one is not decoration. The feature under test creates and updates
#   branch rulesets on 19 live repositories. If the shim is not genuinely first
#   on PATH, a test run edits the author's real repos.
#
# Usage: bash tests/test-fake-gh.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"
# shellcheck source=tests/lib/fake-gh.sh
source "$REPO_ROOT/tests/lib/fake-gh.sh"

harness_require jq

FIX="$REPO_ROOT/tests/fixtures/github"
TMP="$(harness_tmpdir)"
BIN="$TMP/bin"
TRIPBIN="$TMP/tripbin"
TRIPWIRE="$TMP/tripwire"
LOG="$TMP/gh.log"
FAKE_HOME="$TMP/home"
mkdir -p "$TRIPBIN" "$FAKE_HOME"

REAL_GH="$(command -v gh 2>/dev/null || echo '<none on this machine>')"

# The tripwire sits BETWEEN the shim and the real gh. Any `gh` that the shim
# fails to answer for — wrong PATH order, an absolute-path call, a subshell that
# reset PATH — lands here, leaves a file, and exits 97. Its absence at the end of
# the run is the proof that no invocation escaped the mock.
cat > "$TRIPBIN/gh" <<TRIP
#!/usr/bin/env bash
printf 'ESCAPED: %s\n' "\$*" >> "$TRIPWIRE"
exit 97
TRIP
chmod +x "$TRIPBIN/gh"

fake_gh_install "$BIN" "$LOG" "$FIX/compliant"
PATH="$BIN:$TRIPBIN:$PATH"
export PATH HOME="$FAKE_HOME"
# A real gh that somehow ran must not find credentials either.
unset GH_TOKEN GITHUB_TOKEN GH_CONFIG_DIR 2>/dev/null || true

# run <args...> — invoke the shim, capturing stdout, stderr and exit code into
# ROUT / RERR / RRC. Assertions are the control flow here, so nothing may exit.
ROUT=""; RERR=""; RRC=0
run() {
  ROUT="$(gh "$@" 2>"$TMP/stderr")"
  RRC=$?
  RERR="$(cat "$TMP/stderr")"
  return 0
}

# ---------------------------------------------------------------------------
section "installation and PATH"
# ---------------------------------------------------------------------------

judge "gh resolves to the shim, not the real binary" "$BIN/gh" "$(command -v gh)"
judge "the real gh is elsewhere on this machine" no "$(has "$BIN/gh" "$REAL_GH")"
judge "the shim never invokes another gh" no "$(has "$(cat "$BIN/gh")" 'exec gh')"
judge "the shim is executable" yes "$(if [ -x "$BIN/gh" ]; then echo yes; else echo no; fi)"

# ---------------------------------------------------------------------------
section "serving fixtures by path"
# ---------------------------------------------------------------------------

run api repos/Tamircohen28/tamirs-superpowers/rulesets
judge "rulesets list succeeds" 0 "$RRC"
judge "rulesets list has both canonical rulesets" 2 "$(printf '%s' "$ROUT" | jq 'length')"
judge "rulesets list names the Safety ruleset" "Default Branch - Safety" \
  "$(printf '%s' "$ROUT" | jq -r '.[0].name')"

run api repos/Tamircohen28/tamirs-superpowers/rulesets/21049069
judge "ruleset detail is served by id" 21049069 "$(printf '%s' "$ROUT" | jq -r '.id')"
judge "ruleset detail carries rules (list summaries do not)" 3 \
  "$(printf '%s' "$ROUT" | jq '.rules | length')"

run api repos/Tamircohen28/tamirs-superpowers
judge "repo metadata is served" master "$(printf '%s' "$ROUT" | jq -r '.default_branch')"

run api repos/Tamircohen28/tamirs-superpowers/actions/workflows
judge "workflows are served" 2 "$(printf '%s' "$ROUT" | jq -r '.total_count')"

run api "repos/Tamircohen28/tamirs-superpowers/rulesets?includes_parents=false"
judge "a query string does not defeat path mapping" 0 "$RRC"

run api /repos/Tamircohen28/tamirs-superpowers/rulesets
judge "a leading slash does not defeat path mapping" 0 "$RRC"

run api repos/Tamircohen28/tamirs-superpowers/rulesets --jq '.[].id'
judge "--jq is applied to the fixture" "21049068
21049069" "$ROUT"

run api repos/Tamircohen28/tamirs-superpowers --silent
judge "--silent suppresses the body" "" "$ROUT"

run api repos/Tamircohen28/tamirs-superpowers -i
judge "-i prepends a status line" yes "$(has "$ROUT" 'HTTP/2.0 200')"

run auth status
judge "gh auth status succeeds" 0 "$RRC"
judge "gh auth status reports the ground-truth scopes" yes "$(has "$ROUT" "admin:org")"

run repo list Tamircohen28 --json nameWithOwner,defaultBranchRef
judge "gh repo list serves the fleet" 19 "$(printf '%s' "$ROUT" | jq 'length')"
judge "the fleet has 15 main defaults" 15 \
  "$(printf '%s' "$ROUT" | jq '[.[] | select(.defaultBranchRef.name == "main")] | length')"
judge "the fleet has 4 master defaults" 4 \
  "$(printf '%s' "$ROUT" | jq '[.[] | select(.defaultBranchRef.name == "master")] | length')"

# ---------------------------------------------------------------------------
section "unknown paths fail loudly"
# ---------------------------------------------------------------------------
# The single most dangerous failure mode for a mock: answering a question it was
# never taught. Empty output plus exit 0 reads to the caller as "no rulesets".

run api repos/Tamircohen28/tamirs-superpowers/collaborators
judge "an unmapped path exits 78, not 0" 78 "$RRC"
judge "an unmapped path prints nothing on stdout" "" "$ROUT"
judge "an unmapped path says which path it could not serve" yes "$(has "$RERR" 'collaborators')"

run api orgs/SentinelAIOrg/rulesets
judge "a mapped path with no fixture exits 78" 78 "$RRC"
judge "the miss names the fixture it looked for" yes "$(has "$RERR" "org-rulesets.json")"

# Scenario-root fixtures are deliberately repo-agnostic: `compliant` describes a
# state, not a repository, so any owner/repo gets it. Per-repo state comes from
# `by-repo/`, exercised under "fleet" below. Pinning this here so a future reader
# does not "fix" it into a 404.
run api repos/Tamircohen28/no-such-repo/rulesets
judge "a scenario's fixtures answer for any repo" 2 "$(printf '%s' "$ROUT" | jq 'length')"

run pr create --title x
judge "an unsupported subcommand exits 78" 78 "$RRC"
judge "the unsupported subcommand is named" yes "$(has "$RERR" 'pr')"

run api
judge "gh api with no path exits 78" 78 "$RRC"

# ---------------------------------------------------------------------------
section "recording reads and mutations"
# ---------------------------------------------------------------------------

fake_gh_reset
run api repos/Tamircohen28/tamirs-superpowers/rulesets
run api repos/Tamircohen28/tamirs-superpowers/rulesets/21049068
judge "reads are recorded" 2 "$(gh_calls 'rulesets')"
judge "reads are not mutations — a dry run sent nothing" 0 "$(gh_mutations)"

fake_gh_reset
CREATE_BODY='{"name":"Default Branch - Safety","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"non_fast_forward"}]}'
printf '%s' "$CREATE_BODY" > "$TMP/create.json"
run api -X POST repos/Tamircohen28/example-repo/rulesets --input "$TMP/create.json"
judge "POST succeeds against the _defaults write response" 0 "$RRC"
judge "POST is counted as a mutation" 1 "$(gh_mutations)"
judge "the POST body is recorded verbatim" "$(printf '%s' "$CREATE_BODY" | jq -c .)" "$(gh_last_body 1)"
judge "the recorded body keeps ~DEFAULT_BRANCH" yes "$(has "$(gh_last_body 1)" '~DEFAULT_BRANCH')"
judge "the recorded body contains no literal branch name" no "$(has "$(gh_last_body 1)" '"master"')"

run api -X PUT repos/Tamircohen28/example-repo/rulesets/21049069 --input "$TMP/create.json"
judge "two mutations recorded" 2 "$(gh_mutations)"
judge "gh_last_body 2 reaches back past the newest mutation" \
  "$(printf '%s' "$CREATE_BODY" | jq -c .)" "$(gh_last_body 2)"
judge "the PUT method is in the log" 1 "$(grep -c '	PUT	' "$LOG")"

run api --input - -X POST repos/Tamircohen28/example-repo/rulesets <<< "$CREATE_BODY"
judge "--input - reads the body from stdin" 3 "$(gh_mutations)"

fake_gh_reset
run api -X PATCH repos/Tamircohen28/example-repo -f name=example -F delete_branch_on_merge=true
judge "-f/-F build a request body" \
  '{"name":"example","delete_branch_on_merge":true}' "$(gh_last_body 1)"
judge "-F keeps a JSON boolean unquoted" no "$(has "$(gh_last_body 1)" '"true"')"

fake_gh_reset
run api repos/Tamircohen28/example-repo -f name=x
judge "a body with no -X implies POST, as real gh does" 1 "$(gh_mutations)"

fake_gh_reset
run api -X DELETE repos/Tamircohen28/example-repo/rulesets/40000001
judge "DELETE is recorded as a mutation" 1 "$(gh_mutations)"
judge "gh_calls matches on the raw argv" 1 "$(gh_calls '40000001')"

# ---------------------------------------------------------------------------
section "error injection — every class"
# ---------------------------------------------------------------------------

# envelope <status-token> <expected-status-field> — inject, call, and check that
# the response is GitHub's real error envelope rather than a bare exit code.
envelope() {
  local tok="$1" want="$2" path="repos/Tamircohen28/example-repo/rulesets"
  fake_gh_reset
  fake_gh_error ANY "$path" "$tok"
  run api "$path"
  judge "$tok — exits 1 (an HTTP error, not a mock miss)" 1 "$RRC"
  judge "$tok — body carries status $want" "$want" "$(printf '%s' "$ROUT" | jq -r '.status')"
  judge "$tok — body has a message" yes \
    "$(if [ -n "$(printf '%s' "$ROUT" | jq -r '.message // empty')" ]; then echo yes; else echo no; fi)"
  judge "$tok — body has documentation_url" yes \
    "$(if [ -n "$(printf '%s' "$ROUT" | jq -r '.documentation_url // empty')" ]; then echo yes; else echo no; fi)"
  judge "$tok — stderr mimics gh's one-liner" yes "$(has "$RERR" "(HTTP $want)")"
  judge "$tok — the failed call is still recorded" 1 "$(gh_calls 'rulesets')"
}

envelope 401 401
envelope 403 403
envelope 404 404
envelope 409 409
envelope 422 422
envelope 403-rate-limit 403

# The two 403s must be distinguishable, or a transient throttle gets handled as a
# permanent permission failure.
fake_gh_reset
fake_gh_error ANY 'repos/*/*/rulesets' 403
run api repos/Tamircohen28/example-repo/rulesets
PERM_MSG="$(printf '%s' "$ROUT" | jq -r '.message')"
fake_gh_reset
fake_gh_error ANY 'repos/*/*/rulesets' 403-rate-limit
run api repos/Tamircohen28/example-repo/rulesets
RATE_MSG="$(printf '%s' "$ROUT" | jq -r '.message')"
judge "permission 403 and rate-limit 403 differ in message" no "$(has "$PERM_MSG" "rate limit")"
judge "the rate-limit 403 says so" yes "$(has "$RATE_MSG" "rate limit exceeded")"
judge "rate limiting surfaces Retry-After" yes "$(has "$RERR" 'retry-after: 60')"
run api repos/Tamircohen28/example-repo/rulesets -i
judge "-i puts Retry-After in the header block" yes "$(has "$ROUT" 'retry-after: 60')"

# 422 is the only class with a structured errors array; reporting only .message
# would tell the user "Validation Failed" and nothing else.
fake_gh_reset
fake_gh_error POST 'repos/*/*/rulesets' 422
run api -X POST repos/Tamircohen28/example-repo/rulesets --input "$TMP/create.json"
judge "422 carries a structured errors array" "Ruleset" \
  "$(printf '%s' "$ROUT" | jq -r '.errors[0].resource')"
judge "422 names the offending field" "rules" "$(printf '%s' "$ROUT" | jq -r '.errors[0].field')"

# Injection is per method+path, not global.
fake_gh_reset
fake_gh_error PUT 'repos/*/*/rulesets/*' 409
run api repos/Tamircohen28/tamirs-superpowers/rulesets
judge "a PUT-scoped error leaves GETs alone" 0 "$RRC"
run api -X PUT repos/Tamircohen28/tamirs-superpowers/rulesets/21049069 --input "$TMP/create.json"
judge "a PUT-scoped error fires on the PUT" 1 "$RRC"
judge "the 409 body is a Conflict" "Conflict" "$(printf '%s' "$ROUT" | jq -r '.message')"

fake_gh_reset

# ---------------------------------------------------------------------------
section "scenarios carry their own errors"
# ---------------------------------------------------------------------------

fake_gh_use_fixtures "$FIX/no-permission"
fake_gh_reset
run api repos/Tamircohen28/example-repo/rulesets
judge "no-permission: rulesets are 403 with no test setup" 1 "$RRC"
judge "no-permission: the message names the token" yes "$(has "$ROUT" 'personal access token')"
run api repos/Tamircohen28/example-repo
judge "no-permission: repo metadata still reads (this is what makes it confusing)" 0 "$RRC"

fake_gh_use_fixtures "$FIX/auth-failed"
run auth status
judge "auth-failed: gh auth status itself fails" 1 "$RRC"
judge "auth-failed: 401 Bad credentials" "Bad credentials" "$(printf '%s' "$ROUT" | jq -r '.message')"

fake_gh_use_fixtures "$FIX/no-rulesets"
fake_gh_reset
run api repos/Tamircohen28/example-repo/branches/main/protection
judge "no-rulesets: classic protection 404s, as on the real repo" 1 "$RRC"
judge "no-rulesets: the 404 is Not Found, not a mock miss" "Not Found" \
  "$(printf '%s' "$ROUT" | jq -r '.message')"
run api repos/Tamircohen28/example-repo/rulesets
judge "no-rulesets: an empty list is a value, not an error" "[]" "$(printf '%s' "$ROUT" | jq -c .)"

fake_gh_use_fixtures "$FIX/classic-protection"
run api repos/Tamircohen28/example-repo/branches/main/protection
judge "classic-protection: protection is served" 0 "$RRC"
judge "classic-protection: strict is on (the forbidden setting, legacy spelling)" true \
  "$(printf '%s' "$ROUT" | jq -r '.required_status_checks.strict')"
run api repos/Tamircohen28/example-repo/rulesets
judge "classic-protection: no rulesets alongside it" 0 "$(printf '%s' "$ROUT" | jq 'length')"

# ---------------------------------------------------------------------------
section "scenario swapping and per-repo overrides"
# ---------------------------------------------------------------------------

for b in main master trunk; do
  fake_gh_use_fixtures "$FIX/default-$b"
  run api repos/Tamircohen28/example-repo
  judge "default-$b serves default_branch=$b" "$b" "$(printf '%s' "$ROUT" | jq -r '.default_branch')"
done

fake_gh_use_fixtures "$FIX/fleet"
fake_gh_reset
run api repos/Tamircohen28/tamirs-superpowers/rulesets
judge "fleet: the compliant repo has two rulesets" 2 "$(printf '%s' "$ROUT" | jq 'length')"
run api repos/Tamircohen28/job-tracker-web/rulesets
judge "fleet: the ungoverned repo has none" 0 "$(printf '%s' "$ROUT" | jq 'length')"
run api repos/Tamircohen28/whoRuz/rulesets/21049069
judge "fleet: the drifted repo is drifted" true \
  "$(printf '%s' "$ROUT" | jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.strict_required_status_checks_policy')"
run api repos/Tamircohen28/tamirs-superpowers
judge "fleet: per-repo default branch is master" master "$(printf '%s' "$ROUT" | jq -r '.default_branch')"
run api repos/Tamircohen28/job-tracker-web
judge "fleet: per-repo default branch is main" main "$(printf '%s' "$ROUT" | jq -r '.default_branch')"
run api repos/Tamircohen28/not-enumerated/rulesets
judge "fleet: a repo with no by-repo entry fails loudly" 78 "$RRC"

# ---------------------------------------------------------------------------
section "sequenced fixtures (apply, then read back)"
# ---------------------------------------------------------------------------

SEQ="$TMP/fix/seqdemo"
mkdir -p "$SEQ/rulesets.seq"
printf '[]\n' > "$SEQ/rulesets.seq/1.json"
printf '[{"id":1,"name":"Default Branch - Safety"}]\n' > "$SEQ/rulesets.seq/2.json"
fake_gh_use_fixtures "$SEQ"
run api repos/o/r/rulesets
judge "seq: first read is the before state" 0 "$(printf '%s' "$ROUT" | jq 'length')"
run api repos/o/r/rulesets
judge "seq: second read is the after state" 1 "$(printf '%s' "$ROUT" | jq 'length')"
run api repos/o/r/rulesets
judge "seq: the last entry repeats rather than running out" 1 "$(printf '%s' "$ROUT" | jq 'length')"
fake_gh_use_fixtures "$SEQ"
run api repos/o/r/rulesets
judge "seq: a scenario swap restarts the sequence" 0 "$(printf '%s' "$ROUT" | jq 'length')"

# ---------------------------------------------------------------------------
section "fixture integrity"
# ---------------------------------------------------------------------------
# The fixtures are the ground truth these tests assert against. If one drifts,
# every suite built on it drifts silently.

BADJSON=""
for f in $(find "$FIX" -name '*.json' | sort); do
  jq empty "$f" 2>/dev/null || BADJSON="$BADJSON $f"
done
judge "every fixture is valid JSON" "" "$BADJSON"

MISSING_README=""
for d in "$FIX"/*/; do
  [ -f "$d/README.md" ] || MISSING_README="$MISSING_README $(basename "$d")"
done
judge "every fixture directory has a README" "" "$MISSING_README"

judge "compliant: strict_required_status_checks_policy is false" false \
  "$(jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.strict_required_status_checks_policy' \
      "$FIX/compliant/ruleset-21049069.json")"
judge "drifted: the same field is true" true \
  "$(jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.strict_required_status_checks_policy' \
      "$FIX/drifted/ruleset-21049069.json")"
# The two must differ in that field ALONE — otherwise a detector could pass the
# drift test for the wrong reason.
judge "compliant and drifted differ only in that boolean" "" \
  "$(diff <(jq -S '.rules |= map(if .type=="required_status_checks" then .parameters.strict_required_status_checks_policy = "X" else . end)' "$FIX/compliant/ruleset-21049069.json") \
          <(jq -S '.rules |= map(if .type=="required_status_checks" then .parameters.strict_required_status_checks_policy = "X" else . end) | .source = "Tamircohen28/tamirs-superpowers" | ._links.self.href = "https://api.github.com/repos/Tamircohen28/tamirs-superpowers/rulesets/21049069" | ._links.html.href = "https://github.com/Tamircohen28/tamirs-superpowers/rules/21049069"' "$FIX/drifted/ruleset-21049069.json"))"

judge "compliant: 9 required contexts, per ground truth" 9 \
  "$(jq '[.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[]] | length' \
      "$FIX/compliant/ruleset-21049069.json")"
# 1, not 0. The owner's posture is that an approval binds COLLABORATORS while the
# admin bypass actor on this ruleset exempts the owner — so the requirement is real
# for everyone else and never blocks the solo flow. Canonical still defaults to 0;
# this repo carries a per-repository override. Do not "restore" this to 0.
judge "compliant: 1 approving review (binds collaborators; owner has the bypass)" 1 \
  "$(jq -r '.rules[] | select(.type=="pull_request") | .parameters.required_approving_review_count' \
      "$FIX/compliant/ruleset-21049069.json")"
judge "compliant: thread resolution required" true \
  "$(jq -r '.rules[] | select(.type=="pull_request") | .parameters.required_review_thread_resolution' \
      "$FIX/compliant/ruleset-21049069.json")"
judge "compliant: targets ~DEFAULT_BRANCH, never a literal" "~DEFAULT_BRANCH" \
  "$(jq -r '.conditions.ref_name.include[0]' "$FIX/compliant/ruleset-21049069.json")"
judge "compliant: contexts carry the Actions integration_id" 15368 \
  "$(jq -r '[.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].integration_id] | unique | .[0]' \
      "$FIX/compliant/ruleset-21049069.json")"
judge "different-checks shares no context with compliant" 0 \
  "$(jq -n --slurpfile a "$FIX/compliant/ruleset-21049069.json" --slurpfile b "$FIX/different-checks/ruleset-21049069.json" \
      '[$a[0].rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context] as $x
       | [$b[0].rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context] as $y
       | [$x[] | select(. as $c | $y | index($c))] | length')"
judge "custom-ruleset keeps a third, unowned ruleset" 3 "$(jq 'length' "$FIX/custom-ruleset/rulesets.json")"
judge "org-conflict lists an Organization-sourced ruleset" "Organization" \
  "$(jq -r '[.[] | select(.source_type=="Organization")][0].source_type' "$FIX/org-conflict/rulesets.json")"
judge "org-conflict's org ruleset demands 2 reviews" 2 \
  "$(jq -r '.rules[] | select(.type=="pull_request") | .parameters.required_approving_review_count' \
      "$FIX/org-conflict/ruleset-30000001.json")"
judge "no-actions has no workflows" 0 "$(jq -r '.total_count' "$FIX/no-actions/workflows.json")"
judge "partial has Safety only" "Default Branch - Safety" "$(jq -r '.[0].name' "$FIX/partial/rulesets.json")"
judge "partial has exactly one ruleset" 1 "$(jq 'length' "$FIX/partial/rulesets.json")"

# ---------------------------------------------------------------------------
section "hermeticity — no network, no stray writes"
# ---------------------------------------------------------------------------

judge "nothing escaped to a gh beyond the shim" no "$(exists "$TRIPWIRE")"
judge "the tripwire would have fired if reached" 97 \
  "$( "$TRIPBIN/gh" probe >/dev/null 2>&1; echo $?)"
# That probe is the only intentional tripwire hit; clear it so the check above
# stays meaningful for anyone re-reading the file.
judge "the tripwire records what hit it" yes "$(has "$(cat "$TRIPWIRE" 2>/dev/null)" 'probe')"
rm -f "$TRIPWIRE"

judge "HOME was written to by nothing" "" "$(find "$FAKE_HOME" -mindepth 1 2>/dev/null)"
judge "state lives beside the log, inside the temp dir" yes \
  "$(has "$FAKE_GH_STATE" "$TMP")"
judge "every recorded call is accounted for in the log" yes \
  "$(if [ -s "$LOG" ] || [ "$(gh_mutations)" = "0" ]; then echo yes; else echo no; fi)"

# The shim's own source must not reference a network transport. A grep is a weak
# check on its own; combined with the tripwire it closes the "called by absolute
# path" hole a PATH check alone leaves open.
judge "the shim library makes no network calls" "" \
  "$(grep -nE '(^|[^_a-zA-Z])(curl|wget|nc|ssh)[[:space:]]' "$REPO_ROOT/tests/lib/fake-gh.sh" || true)"

# ---------------------------------------------------------------------------
section "the --include header contract"
# ---------------------------------------------------------------------------
# scripts/lib/github-common.sh runs every call as
#   gh api --include --method <M> <path>
# and classifies from the status line PLUS retry-after, x-oauth-scopes and
# x-ratelimit-remaining. A shim emitting a bare JSON body would satisfy the
# fixture assertions above while every classification path went untested.

fake_gh_use_fixtures "$FIX/compliant"
fake_gh_reset
run api --include --method GET repos/Tamircohen28/tamirs-superpowers/rulesets
judge "--include --method is the real call shape" 0 "$RRC"
judge "  status line first" yes "$(has "$ROUT" 'HTTP/2.0 200')"
judge "  x-oauth-scopes present" yes "$(has "$ROUT" 'x-oauth-scopes: admin:org')"
judge "  x-ratelimit-remaining present" yes "$(has "$ROUT" 'x-ratelimit-remaining: 4999')"
judge "  a blank line separates headers from body" yes "$(has "$ROUT" '
[')"
judge "  the body still parses once the headers are stripped" 2 \
  "$(printf '%s' "$ROUT" | awk 'f{print} /^$/{f=1}' | jq 'length')"

# The error path is the one that was emitting a bare status line.
fake_gh_reset
fake_gh_error ANY 'repos/*/*/rulesets' 403
run api --include --method GET repos/Tamircohen28/example-repo/rulesets
judge "a plain 403 carries a full header block" yes "$(has "$ROUT" 'x-oauth-scopes:')"
judge "  and a HEALTHY remaining quota, so 'remaining: 0' stays meaningful" yes \
  "$(has "$ROUT" 'x-ratelimit-remaining: 4999')"
judge "  and no retry-after, which is a throttle-only header" no "$(has "$ROUT" 'retry-after:')"

fake_gh_reset
fake_gh_error ANY 'repos/*/*/rulesets' 403-rate-limit
run api --include --method GET repos/Tamircohen28/example-repo/rulesets
judge "a rate-limit 403 zeroes the remaining quota" yes "$(has "$ROUT" 'x-ratelimit-remaining: 0')"
judge "  and carries retry-after" yes "$(has "$ROUT" 'retry-after: 60')"

fake_gh_use_fixtures "$FIX/insufficient-scope"
fake_gh_reset
run api --include --method GET repos/Tamircohen28/example-repo/rulesets
judge "scopes.txt drives x-oauth-scopes" yes "$(has "$ROUT" 'x-oauth-scopes: gist, read:user')"
judge "  the scope-failure body names the missing scope" yes "$(has "$ROUT" 'administration')"

fake_gh_use_fixtures "$FIX/server-error"
fake_gh_reset
run api --include --method GET repos/Tamircohen28/example-repo/rulesets
judge "a 502 renders as a 5xx status line" yes "$(has "$ROUT" 'HTTP/2.0 502')"

fake_gh_reset
fake_gh_error ANY 'repos/*/*/rulesets' no-response
run api --include --method GET repos/Tamircohen28/example-repo/rulesets
judge "no-response emits NO status line — the only way to reach 'network'" "" "$ROUT"
judge "  and still fails" 1 "$RRC"

# ---------------------------------------------------------------------------
section "classification through the real library"
# ---------------------------------------------------------------------------
# Asserting my own header format against my own expectations proves only that I
# am self-consistent. This drives scripts/lib/github-common.sh — the actual
# consumer — so the header block is verified by the code that reads it.

GHLIB="$REPO_ROOT/scripts/lib/github-common.sh"
if [ ! -f "$GHLIB" ]; then
  skip "classification through github-common.sh" "scripts/lib/github-common.sh not present"
else
  # classify <fixture> <token|-> <expected-class>
  classify() {
    local fixture="$1" tok="$2" want="$3" got
    got="$(
      set -uo pipefail
      export FAKE_GH_LOG="$LOG" FAKE_GH_STATE FAKE_GH_ERRORS
      # shellcheck source=scripts/lib/github-common.sh
      source "$GHLIB" >/dev/null 2>&1
      fake_gh_use_fixtures "$FIX/$fixture" >/dev/null 2>&1
      : > "$FAKE_GH_ERRORS"
      [ "$tok" = "-" ] || printf 'ANY repos/*/*/rulesets %s\n' "$tok" >> "$FAKE_GH_ERRORS"
      github_api GET "repos/Tamircohen28/example-repo/rulesets" >/dev/null 2>&1
      github_last_class
    )"
    judge "$fixture${tok:+/$tok} classifies as $want" "$want" "$got"
  }

  classify compliant          -               ok
  classify no-permission      -               insufficient_scope
  classify insufficient-scope -               insufficient_scope
  classify org-policy         -               org_policy
  classify rate-limited       -               rate_limited
  classify compliant          401             unauthenticated
  classify compliant          429             rate_limited
  classify compliant          404             not_found
  classify compliant          404-unsupported unsupported
  classify compliant          409             conflict
  classify compliant          422             invalid_request
  classify compliant          451             org_policy
  classify compliant          502             network
  classify compliant          no-response     network
  # All three of these are HTTP 403 and differ only in `.message`. That is not a
  # quirk of the mock — it is how GitHub actually reports them, and getting the
  # class wrong sends the operator to the wrong fix: re-authorize a token, ask an
  # org admin, or wait out a throttle.
  #
  # The default 403 body says "Resource not accessible by personal access
  # token", which matches the scope branch. `forbidden` is the residual class,
  # reached only when rate-limit, quota, org-policy AND scope wording have all
  # failed to match, so it needs a body no other fixture produces —
  # forbidden/errors/403.json. Asserting it against the default body would pass
  # for the wrong reason.
  classify compliant          403             insufficient_scope
  classify forbidden          -               forbidden

  # PRECEDENCE REGRESSION GUARD. Both of GitHub's real org-restriction 403s
  # mention OAuth:
  #   "...the `X` organization has enabled OAuth App access restrictions..."
  #   "Resource protected by organization SAML enforcement. You must grant your
  #    OAuth token access to this organization."
  # github_api therefore tests org-policy wording BEFORE scope wording. Reversed,
  # both land on insufficient_scope and the operator is sent to `gh auth refresh`
  # — a command that cannot fix an org restriction. The ordering is load-bearing
  # and now carries a "do not reorder" comment in the library; these two cases
  # are what would fail if someone did it anyway.
  classify org-policy         -               org_policy
  classify compliant          403-saml        org_policy

  # ...and the guard is only meaningful if those bodies really would match the
  # scope branch. Assert the collision exists rather than trusting the comment:
  # if a future edit sanitised "OAuth" out of these messages, the two cases above
  # would still pass while testing nothing.
  fake_gh_reset
  fake_gh_error ANY 'repos/*/*/rulesets' 403-saml
  run api repos/Tamircohen28/example-repo/rulesets
  judge "the SAML body really does contain OAuth (else the guard is vacuous)" yes \
    "$(has "$(printf '%s' "$ROUT" | jq -r '.message' | tr 'A-Z' 'a-z')" 'oauth')"
  fake_gh_use_fixtures "$FIX/org-policy"
  fake_gh_reset
  run api repos/Tamircohen28/example-repo/rulesets
  judge "the OAuth-App-restrictions body does too" yes \
    "$(has "$(printf '%s' "$ROUT" | jq -r '.message' | tr 'A-Z' 'a-z')" 'oauth')"
fi

fake_gh_use_fixtures "$FIX/compliant"
fake_gh_reset

harness_summary
