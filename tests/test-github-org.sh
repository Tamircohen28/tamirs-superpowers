#!/usr/bin/env bash
# test-github-org.sh — the suite for scripts/lib/github-org.sh and the
# organization path through scripts/github-policy.sh.
#
# WHAT MAKES THIS SUITE SAFE TO RUN
#   The subject can create and update ORGANIZATION rulesets, which govern every
#   repository in an organization — including repositories that do not exist
#   yet. This machine is logged into a live account that owns two real
#   organizations, so a suite that reached the network could rewrite governance
#   for twenty repositories at once. It cannot: `gh` is resolved from a temp bin
#   dir holding tests/lib/fake-gh.sh, the first assertions prove the shim is
#   what the subject finds on PATH, and every later assertion is made against a
#   recorded call log. `gh_mutations` returning 0 is the proof a read path
#   stayed a read path.
#
# NON-VACUITY IS THE HOUSE RULE (inherited from tests/test-github-policy.sh)
#   Every "this is not reported" is paired with a planted positive proving the
#   detector fires; every "nothing was written" is paired with proof that
#   something was read; assertions compare specific values, never truthiness.
#
# GROUND TRUTH
#   The two degrade scenarios are not invented. Measured 2026-08-19 against the
#   real API, read-only:
#     GET /orgs/ProductionMasterAI/rulesets -> 200 []          (plan: team)
#     GET /orgs/SentinelAIOrg/rulesets      -> 403 "Upgrade to GitHub Team
#                                                   to enable this feature."  (plan: free)
#
# bash 3.2. `set -uo pipefail`, not -e: the assertions are the control flow.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"
# shellcheck source=tests/lib/fake-gh.sh
source "$REPO_ROOT/tests/lib/fake-gh.sh"

harness_require git jq awk sed

POLICY="$REPO_ROOT/config/github/repository-policy.json"
TMP="$(harness_tmpdir)"
FIX="$TMP/fixtures"
ROOT="$TMP/root"
OUT="$TMP/stdout"
ERR="$TMP/stderr"
RC=0
ORG="ProductionMasterAI"

mkdir -p "$TMP/bin" "$TMP/home" "$TMP/work"
cp -R "$REPO_ROOT/tests/fixtures/github" "$FIX"
harness_new_repo "$ROOT" main
ln -s "$REPO_ROOT/scripts" "$ROOT/scripts"
ln -s "$REPO_ROOT/config"  "$ROOT/config"

REAL_GH="$(command -v gh 2>/dev/null || true)"
fake_gh_install "$TMP/bin" "$TMP/gh.log" "$FIX/org-available"
PATH="$TMP/bin:$PATH"
export PATH
export HOME="$TMP/home"
export GH_CONFIG_DIR="$TMP/home/gh"
export GH_TOKEN="" GITHUB_TOKEN=""
export NO_COLOR=1

# The libraries under test, sourced into this shell for the unit sections. Only
# after PATH is rewritten, so nothing they do at source time could reach a real
# `gh`.
# shellcheck source=scripts/lib/github-common.sh
source "$REPO_ROOT/scripts/lib/github-common.sh"
# shellcheck source=scripts/lib/github-org.sh
source "$REPO_ROOT/scripts/lib/github-org.sh"
github_state_trap

W="$TMP/work"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# scenario <fixture-dir> — point the mock at a scenario and give that scenario
# an API-shaped repository listing for `orgs/{org}/repos`. The shared
# _defaults/repo-list.json is in `gh repo list --json` shape (nameWithOwner),
# which `list_repos_paged` reads with `.full_name` — it would silently yield an
# empty fleet, and every org assertion would pass against nothing.
scenario() {
  fake_gh_use_fixtures "$FIX/$1"
  git -C "$ROOT" remote remove origin >/dev/null 2>&1
  git -C "$ROOT" remote add origin "git@github.com:$ORG/example-service.git"
  rm -rf "$ROOT/.github"
  mkdir -p "$ROOT/.github/workflows"
}

# org_repo_list <fixture-dir> <name>... — write the API-shaped listing.
org_repo_list() {
  local d="$FIX/$1"; shift
  printf '%s\n' "$@" | jq -R --arg org "$ORG" '{
      full_name: ($org + "/" + .),
      name: .,
      fork: false,
      archived: false,
      default_branch: "main",
      visibility: "private",
      owner: { login: $org, type: "Organization" }
    }' | jq -s . >"$d/repo-list.json"
}

for d in org-available org-plan-free org-scope org-stricter org-drift org-notfound org-unreachable; do
  org_repo_list "$d" example-service ppfa-proxy-gw ppfa-telemetry
done

# run_policy <args...> — one entrypoint invocation with a fresh call log.
run_policy() {
  fake_gh_reset
  ( cd "$ROOT" && bash "$ROOT/scripts/github-policy.sh" "$@" ) >"$OUT" 2>"$ERR"
  RC=$?
}

# run_policy_live <args...> — the same, with the unattended-write authorisation
# the LIVE-TARGET GATE requires. Every mutation count uses this, including the
# ones expecting ZERO: without it the gate is what produces the zero and "the
# org guard blocked this write" would be indistinguishable from "no terminal".
run_policy_live() {
  fake_gh_reset
  ( cd "$ROOT" && GITHUB_POLICY_ALLOW_LIVE=1 \
      bash "$ROOT/scripts/github-policy.sh" "$@" ) >"$OUT" 2>"$ERR"
  RC=$?
}

reads()     { awk -F'\t' '$2 == "GET" { n++ } END { print n + 0 }' "$FAKE_GH_LOG"; }
writes_to() { awk -F'\t' -v p="$1" '$2 != "GET" && index($3, p) { n++ } END { print n + 0 }' "$FAKE_GH_LOG"; }
gets_to()   { awk -F'\t' -v p="$1" '$2 == "GET" && index($3, p) { n++ } END { print n + 0 }' "$FAKE_GH_LOG"; }
# body_to <path-fragment> [nth] — request body of the nth mutation whose path
# matches. `gh_last_body` counts back from the end of the WHOLE log, which is
# the wrong window here: an org apply also writes repository rulesets, so the
# last mutation is not the org one.
body_to()   { awk -F'\t' -v p="$1" '$2 != "GET" && index($3, p) { print $4 }' "$FAKE_GH_LOG" \
                | sed -n "${2:-1}p"; }
outhas()    { has "$(cat "$OUT" "$ERR" 2>/dev/null)" "$1"; }
jout()      { jq -r "$1" <"$OUT" 2>/dev/null; }
# field_of <key> <file> — the value of a `key<TAB>value` record. `substr`, not
# `$1=""`: rebuilding the record with awk's default OFS would turn every tab
# into a space and leave a leading one, which is exactly the kind of assertion
# that fails on a whitespace nobody can see.
field_of()  { awk -F'\t' -v k="$1" '$1 == k { print substr($0, index($0, "\t") + 1) }' "$2"; }

atleast() {
  if [ "${3:-0}" -ge "$2" ]; then ok "$1"; else bad "$1" "expected at least $2, got ${3:-0}"; fi
}

# unit <fixture-dir> — reset the log and point the mock, for a library call made
# in this shell rather than through the entrypoint.
unit() { fake_gh_reset; fake_gh_use_fixtures "$FIX/$1"; }

# ---------------------------------------------------------------------------
section "0 — the hermeticity boundary itself"
# ---------------------------------------------------------------------------
judge "0: gh resolves to the shim"        "$TMP/bin/gh" "$(command -v gh)"
if [ -n "$REAL_GH" ]; then
  judge "0: and not to the real gh"       "no"  "$(has "$(command -v gh)" "$REAL_GH")"
else
  skip "0: and not to the real gh" "no real gh installed to shadow"
fi
judge "0: the shim answers --version"     "yes" "$(has "$(gh --version)" "fake-gh")"

# ---------------------------------------------------------------------------
section "1 — github_org_probe: available"
# ---------------------------------------------------------------------------
unit org-available
RC=0; LIST="$(github_org_probe "$ORG")" || RC=$?
judge "1: probe returns 0 when org rulesets are readable" "0"   "$RC"
judge "1: the JSON array reaches the caller"              "0"   "$(printf '%s' "$LIST" | jq 'length')"
judge "1: availability is recorded"                       "yes" "$(github_org_available)"
judge "1: with class ok"                                  "ok"  "$(github_org_class)"
judge "1: the probe cost exactly one GET"                 "1"   "$(gets_to 'orgs/')"
judge "1: and mutated nothing"                            "0"   "$(gh_mutations)"
# Non-vacuity: the recorded state must be readable ACROSS a command
# substitution, which is the whole reason it is file-backed. The assertions
# above ran after `LIST="$( ... )"`, so a variable-only implementation would
# have returned empty here and this pair is what proves it did not.
judge "1: the reason survived the subshell"               "yes" \
  "$(has "$(github_org_reason)" "readable")"

# ---------------------------------------------------------------------------
section "2 — github_org_probe: the plan wall (SentinelAIOrg, measured)"
# ---------------------------------------------------------------------------
unit org-plan-free
RC=0; github_org_probe "$ORG" >/dev/null || RC=$?
judge "2: a plan wall is a DEGRADE (2), not a failure (1)" "2"    "$RC"
judge "2: availability is no"                             "no"   "$(github_org_available)"
judge "2: classified as a plan limit, not a permission"   "plan" "$(github_org_class)"
judge "2: the reason says what the user was told to do"   "yes" \
  "$(has "$(github_org_reason)" "unavailable on this organization's plan")"
judge "2: and names the fallback"                         "yes" \
  "$(has "$(github_org_reason)" "falling back to per-repository policy")"
judge "2: the raw GitHub wording is carried through"      "yes" \
  "$(has "$(github_org_reason)" "Upgrade to GitHub Team")"
judge "2: read-only"                                      "0"    "$(gh_mutations)"
# Non-vacuity: the available scenario must NOT produce that reason, or the
# assertions above would pass on a constant string.
unit org-available
github_org_probe "$ORG" >/dev/null
judge "2 (guard): an available org does not claim a plan limit" "no" \
  "$(has "$(github_org_reason)" "unavailable on this organization's plan")"
judge "2 (guard): and is not classed plan"                "ok"   "$(github_org_class)"

# ---------------------------------------------------------------------------
section "3 — github_org_probe: the other degrades, each distinguished"
# ---------------------------------------------------------------------------
unit org-scope
RC=0; github_org_probe "$ORG" >/dev/null || RC=$?
judge "3: a missing scope degrades"                       "2"     "$RC"
judge "3: classed scope, not plan"                        "scope" "$(github_org_class)"
judge "3: and names the remedy"                           "yes" \
  "$(has "$(github_org_reason)" "gh auth refresh")"

unit org-notfound
RC=0; github_org_probe "$ORG" >/dev/null || RC=$?
judge "3: an invisible org degrades"                      "2"         "$RC"
judge "3: classed not_found"                              "not_found" "$(github_org_class)"

unit org-unreachable
RC=0; github_org_probe "$ORG" >/dev/null || RC=$?
judge "3: a 5xx is a real failure, not a degrade"         "1"     "$RC"
judge "3: classed error"                                  "error" "$(github_org_class)"
judge "3: nothing was written on any degrade path"        "0"     "$(gh_mutations)"

# ---------------------------------------------------------------------------
section "4 — rendering an organization ruleset"
# ---------------------------------------------------------------------------
github_org_render_ruleset "$POLICY" safety "$ORG" >"$W/safety.json"
judge "4: default targeting is every repository"  "~ALL" \
  "$(jq -r '.conditions.repository_name.include | join(",")' "$W/safety.json")"
judge "4: ref targeting is still the magic ref"   "~DEFAULT_BRANCH" \
  "$(jq -r '.conditions.ref_name.include | join(",")' "$W/safety.json")"
judge "4: NO literal branch name is rendered"     "0" \
  "$(grep -c -E '"(main|master|trunk|develop)"' "$W/safety.json")"
judge "4: the safety rules survive"               "deletion,non_fast_forward" \
  "$(jq -r '[.rules[].type] | sort | join(",")' "$W/safety.json")"

github_org_render_ruleset "$POLICY" pr_ci "$ORG" >"$W/prci.json"
# The one thing that does NOT survive the trip up to org level.
judge "4: required_status_checks is DROPPED at org level" "0" \
  "$(jq '[.rules[] | select(.type == "required_status_checks")] | length' "$W/prci.json")"
judge "4: because contexts are per-repository"    "per_repository" \
  "$(jq -r '.required_checks.source' "$POLICY")"
# Non-vacuity: the rule is dropped for want of contexts, not because the
# renderer forgot it — the repository-level render of the SAME key, for a
# repository that does declare contexts, still carries it.
github_policy_render_ruleset "$POLICY" pr_ci "Tamircohen28/tamirs-superpowers" >"$W/prci-repo.json"
judge "4 (guard): the repo-level render still carries it" "1" \
  "$(jq '[.rules[] | select(.type == "required_status_checks")] | length' "$W/prci-repo.json")"
# Repository overrides must not leak into an org-wide ruleset.
judge "4: one repo's approval override does not become the org's" "0" \
  "$(jq '[.rules[] | select(.type=="pull_request")][0].parameters.required_approving_review_count' "$W/prci.json")"
judge "4 (guard): that override is real at repo level" "1" \
  "$(jq '[.rules[] | select(.type=="pull_request")][0].parameters.required_approving_review_count' "$W/prci-repo.json")"

github_org_render_ruleset "$POLICY" safety "$ORG" 'ppfa-*' 'sentinel-*' >"$W/safety-narrow.json"
judge "4: explicit include patterns are honoured" "ppfa-*,sentinel-*" \
  "$(jq -r '.conditions.repository_name.include | join(",")' "$W/safety-narrow.json")"
judge "4: rendering made no API call"             "0" "$(gh_mutations)"

# ---------------------------------------------------------------------------
section "5 — the targeting decision"
# ---------------------------------------------------------------------------
unit org-available
github_org_probe "$ORG" >/dev/null
github_org_targeting "$ORG" 8 no >"$W/t1"
judge "5: available and unfiltered means organization-level" "org" "$(field_of mode "$W/t1")"
judge "5: and the reason is the user's own argument"         "yes" \
  "$(has "$(field_of reason "$W/t1")" "instead of visiting 8 repositories")"

github_org_targeting "$ORG" 8 yes >"$W/t2"
judge "5: a repository filter forces per-repository"         "per_repo" "$(field_of mode "$W/t2")"
judge "5: with the ERE-versus-glob reason stated"            "yes" \
  "$(has "$(field_of reason "$W/t2")" "POSIX EREs")"

unit org-plan-free
github_org_probe "$ORG" >/dev/null
github_org_targeting "$ORG" 12 no >"$W/t3"
judge "5: an unavailable org falls back"                     "per_repo" "$(field_of mode "$W/t3")"
judge "5: carrying the plan reason, not a generic one"       "yes" \
  "$(has "$(field_of reason "$W/t3")" "plan")"
judge "5: the whole decision cost no mutation"               "0" "$(gh_mutations)"

# ---------------------------------------------------------------------------
section "6 — an organization ruleset stricter than canonical"
# ---------------------------------------------------------------------------
unit org-stricter
RC=0; github_org_conflicts "$ORG" >"$W/conf" || RC=$?
judge "6: conflicts could be read"                 "0" "$RC"
atleast "6: at least one conflict line"            "1" "$(wc -l <"$W/conf" | tr -d ' ')"
judge "6: names the ruleset"                       "yes" "$(has "$(cat "$W/conf")" "Org baseline - reviews")"
judge "6: reports the approval requirement"        "yes" "$(has "$(cat "$W/conf")" "requires 2 approving review(s)")"
judge "6: reports strict up-to-date"               "yes" "$(has "$(cat "$W/conf")" "branch must be up to date")"
judge "6: reports the CODEOWNERS requirement"      "yes" "$(has "$(cat "$W/conf")" "CODEOWNERS")"
judge "6: reading a conflict wrote nothing"        "0" "$(gh_mutations)"
atleast "6: and it did read"                       "2" "$(reads)"
# Non-vacuity: an org with no rulesets must report no conflicts.
unit org-available
RC=0; github_org_conflicts "$ORG" >"$W/conf0" || RC=$?
judge "6 (guard): an empty org has no conflicts"   "0" "$(wc -l <"$W/conf0" | tr -d ' ')"

# ---------------------------------------------------------------------------
section "7 — the weakening guard, including the org-only dimension"
# ---------------------------------------------------------------------------
cp "$W/safety.json" "$W/w-live.json"
cp "$W/safety-narrow.json" "$W/w-desired.json"
judge "7: narrowing coverage from ~ALL is a weakening" "yes" \
  "$(has "$(github_org_weakens "$W/w-live.json" "$W/w-desired.json")" "would narrow repository coverage")"
judge "7: and it names what it would shrink to"        "yes" \
  "$(has "$(github_org_weakens "$W/w-live.json" "$W/w-desired.json")" "ppfa-*, sentinel-*")"
# Identical documents weaken nothing — the guard must not fire on a no-op.
judge "7 (guard): identical rulesets weaken nothing"   "" \
  "$(github_org_weakens "$W/safety.json" "$W/safety.json")"
# A rules-level weakening is still caught up here.
jq '.rules = [.rules[] | if .type=="pull_request"
      then .parameters.required_approving_review_count = 2
           | .parameters.required_review_thread_resolution = true
      else . end]' "$W/prci.json" >"$W/w-strict.json"
judge "7: lowering approvals is caught"                "yes" \
  "$(has "$(github_org_weakens "$W/w-strict.json" "$W/prci.json")" "would lower required approving reviews from 2 to 0")"
judge "7: the guard is offline"                        "0" "$(gh_mutations)"

# ---------------------------------------------------------------------------
section "8 — github_org_verify"
# ---------------------------------------------------------------------------
unit org-available
RC=0; github_org_verify "$POLICY" "$ORG" >"$W/v-absent" || RC=$?
judge "8: an org with no rulesets reports drift"   "3" "$RC"
judge "8: both canonical rulesets are absent"      "safety:absent pr_ci:absent" \
  "$(awk -F'\t' '{printf "%s:%s ", $1, $2}' "$W/v-absent" | sed 's/ $//')"
judge "8: verify wrote nothing"                    "0" "$(gh_mutations)"
atleast "8: verify read"                           "1" "$(reads)"

unit org-drift
RC=0; github_org_verify "$POLICY" "$ORG" >"$W/v-drift" || RC=$?
judge "8: a partially-drifted org reports drift"   "3" "$RC"
judge "8: safety is up to date, PR & CI drifts"    "safety:up_to_date pr_ci:drifted" \
  "$(awk -F'\t' '{printf "%s:%s ", $1, $2}' "$W/v-drift" | sed 's/ $//')"
judge "8: verifying a drifted org wrote nothing"   "0" "$(gh_mutations)"

unit org-plan-free
RC=0; github_org_verify "$POLICY" "$ORG" >/dev/null || RC=$?
judge "8: verify degrades (2) when org rulesets are unavailable" "2" "$RC"

# ---------------------------------------------------------------------------
section "9 — the write primitives (against the mock, never GitHub)"
# ---------------------------------------------------------------------------
unit org-available
github_org_render_payload_file "$POLICY" safety "$ORG" "$W/payload.json"
github_org_create_ruleset "$ORG" "$W/payload.json" >/dev/null
judge "9: create issues exactly one mutation"       "1" "$(gh_mutations)"
judge "9: to the organization endpoint"             "1" "$(writes_to "orgs/$ORG/rulesets")"
judge "9: POST, not PUT"                            "1" \
  "$(awk -F'\t' '$2 == "POST" { n++ } END { print n + 0 }' "$FAKE_GH_LOG")"
judge "9: the body is the payload that was rendered" "Default Branch - Safety" \
  "$(gh_last_body 1 | jq -r '.name')"
judge "9: carrying the org-wide targeting"          "~ALL" \
  "$(gh_last_body 1 | jq -r '.conditions.repository_name.include | join(",")')"

unit org-drift
github_org_render_payload_file "$POLICY" pr_ci "$ORG" "$W/payload2.json"
github_org_update_ruleset "$ORG" 40000002 "$W/payload2.json" >/dev/null
judge "9: update issues exactly one mutation"       "1" "$(gh_mutations)"
judge "9: PUT to the ruleset id that was read"      "1" "$(writes_to "orgs/$ORG/rulesets/40000002")"

# ---------------------------------------------------------------------------
section "10 — the derived approval count (audit §0.1)"
# ---------------------------------------------------------------------------
judge "10: no bypass, solo         -> 0" "0" "$(github_derive_review_count no  0)"
judge "10: no bypass, ten people   -> 0" "0" "$(github_derive_review_count no  10)"
judge "10: bypass, solo            -> 0" "0" "$(github_derive_review_count yes 1)"
judge "10: bypass, zero            -> 0" "0" "$(github_derive_review_count yes 0)"
judge "10: bypass, two people      -> 1" "1" "$(github_derive_review_count yes 2)"
judge "10: bypass, nineteen people -> 1" "1" "$(github_derive_review_count yes 19)"
judge "10: a non-numeric count is 0, never an error" "0" "$(github_derive_review_count yes banana)"

# Laziness: the collaborator call costs one extra request per repository, and
# without a bypass actor the answer is 0 for ANY collaborator count. So it must
# not be made.
unit org-available
printf '{"bypass_actors": []}\n' >"$W/nobypass.json"
github_review_count_for "$ORG/example-service" "$W/nobypass.json" >"$W/rc-none"
judge "10: no bypass derives 0"                     "0" "$(field_of count "$W/rc-none")"
judge "10: and queries no collaborators at all"     "0" "$(gets_to 'collaborators')"
judge "10: saying so rather than reporting unknown" "not-queried" "$(field_of collaborators "$W/rc-none")"
judge "10: no bypass path made no request whatsoever" "0" "$(reads)"

# Planted positive: with a bypass actor the call IS attempted. The mock has no
# fixture for `repos/*/*/collaborators` (that mapping lives in
# tests/lib/fake-gh.sh, requested — session-files/requests/gh-org-rulesets.md),
# so this also exercises the degrade: an unreadable count must resolve to 0 with
# a stated reason, never to a conjured requirement.
unit org-available
printf '{"bypass_actors": [{"actor_type":"RepositoryRole","actor_id":5,"bypass_mode":"always"}]}\n' >"$W/bypass.json"
github_review_count_for "$ORG/example-service" "$W/bypass.json" >"$W/rc-bypass"
judge "10 (positive): a bypass actor triggers the query" "1" "$(gets_to 'collaborators')"
judge "10: bypass recorded"                              "yes" "$(field_of bypass "$W/rc-bypass")"
judge "10: an unreadable count degrades to 0"            "0"   "$(field_of count "$W/rc-bypass")"
judge "10: and says the count is unknown"                "unknown" "$(field_of collaborators "$W/rc-bypass")"
judge "10: with the safe-direction reasoning"            "yes" \
  "$(has "$(field_of reason "$W/rc-bypass")" "--admin")"
judge "10: deriving a count never wrote anything"        "0" "$(gh_mutations)"

# ---------------------------------------------------------------------------
section "11 — classic protection aggregated with rulesets"
# ---------------------------------------------------------------------------
# The dangerous case: rulesets AND classic protection on the same branch. The
# rulesets read compliant; the classic rule is what actually gates a merge.
unit classic-overlap
RC=0; github_classic_aggregate "Tamircohen28/example-repo" main >"$W/cls" || RC=$?
judge "11: findings are reported (rc 3)"          "3"       "$RC"
judge "11: classic protection is present"         "present" "$(field_of classic "$W/cls")"
judge "11: alongside two rulesets"                "2"       "$(field_of rulesets "$W/cls")"
judge "11: strict is detected on the classic side" "true"   "$(field_of strict_classic "$W/cls")"
judge "11: the strict finding is CRITICAL"        "1" \
  "$(awk -F'\t' '$1=="finding" && $2=="critical"' "$W/cls" | wc -l | tr -d ' ')"
judge "11: it names the setting it silently defeats" "yes" \
  "$(has "$(cat "$W/cls")" "strict_required_status_checks_policy: false")"
judge "11: and explains the aggregation"          "yes" \
  "$(has "$(cat "$W/cls")" "the stricter requirement wins")"
judge "11: classic approvals are surfaced too"    "yes" \
  "$(has "$(cat "$W/cls")" "requires 1 approving review(s)")"
judge "11: detecting it wrote nothing"            "0" "$(gh_mutations)"
atleast "11: and it read both mechanisms"         "2" "$(reads)"

# The classic-ONLY repository is a different finding: nothing to aggregate with,
# so the report says "migrate", not "both apply". Pairing the two is what proves
# the aggregation line above is produced by the overlap and not by the presence
# of classic protection alone.
unit classic-protection
RC=0; github_classic_aggregate "Tamircohen28/example-repo" main >"$W/cls-only" || RC=$?
judge "11: a classic-only repo still reports (rc 3)" "3" "$RC"
judge "11: with zero rulesets"                       "0" "$(field_of rulesets "$W/cls-only")"
judge "11: and does NOT claim both mechanisms apply" "no" \
  "$(has "$(cat "$W/cls-only")" "GitHub applies both")"
judge "11: it says migrate instead"                  "yes" \
  "$(has "$(cat "$W/cls-only")" "no ruleset targets it")"

# The migration path is printed, never executed.
fake_gh_reset
github_classic_migration_plan "Tamircohen28/example-repo" main >"$W/plan"
judge "11: the plan raises the ruleset BEFORE removing classic" "yes" \
  "$(has "$(cat "$W/plan")" "while classic protection is still")"
judge "11: and refuses to do the removal step"    "yes" \
  "$(has "$(cat "$W/plan")" "will not do step 4 for you")"
judge "11: it warns about the Convert-to-ruleset button" "yes" \
  "$(has "$(cat "$W/plan")" "LEAVES CLASSIC ENABLED")"
judge "11: printing a plan made no API call"      "0" "$(reads)"
judge "11: and wrote nothing"                     "0" "$(gh_mutations)"

# Non-vacuity: a rulesets-only repository must produce none of that.
unit compliant
RC=0; github_classic_aggregate "Tamircohen28/tamirs-superpowers" master >"$W/cls0" || RC=$?
judge "11 (guard): no classic protection means rc 0" "0"      "$RC"
judge "11 (guard): reported absent"                  "absent"  "$(field_of classic "$W/cls0")"
judge "11 (guard): and produces zero findings"       "0" \
  "$(awk -F'\t' '$1=="finding"' "$W/cls0" | wc -l | tr -d ' ')"

# ---------------------------------------------------------------------------
section "12 — the entrypoint: --org reports the organization plan"
# ---------------------------------------------------------------------------
scenario org-available
run_policy plan --org "$ORG"
judge "12: the org block is printed"              "yes" "$(outhas 'Organization-level rulesets')"
judge "12: org-level is named as preferred"       "yes" "$(outhas 'organization-level is available and preferred')"
judge "12: with the user's own framing"           "yes" "$(outhas 'instead of visiting')"
judge "12: both canonical rulesets are absent up there" "yes" \
  "$(outhas 'not present at organization level')"
judge "12: the org-level plan is shown"           "yes" "$(outhas 'Organization-level plan (nothing written)')"
judge "12: and the one command that applies it"   "yes" "$(outhas "apply --org $ORG --org-level")"
judge "12: the per-repository caveat is stated"   "yes" \
  "$(outhas 'Required status-check contexts stay per-repository')"
judge "12: planning an org wrote nothing"         "0"   "$(gh_mutations)"
atleast "12: and it read the org"                 "1"   "$(gets_to "orgs/$ORG/rulesets")"
atleast "12: and swept the repositories"          "3"   "$(reads)"

# ---------------------------------------------------------------------------
section "13 — the entrypoint: degrading honestly"
# ---------------------------------------------------------------------------
scenario org-plan-free
run_policy plan --org "$ORG"
judge "13: the plan wall is reported in the user's words" "yes" \
  "$(outhas "unavailable on this organization's plan")"
judge "13: the fallback is stated, not implied"   "yes" \
  "$(outhas 'Falling back to per-repository policy')"
judge "13: it does NOT claim org-level is preferred" "no" \
  "$(outhas 'organization-level is available and preferred')"
judge "13: and it does not offer --org-level"     "no"  "$(outhas '--org-level')"
judge "13: the per-repository sweep still ran"    "yes" "$(outhas 'GitHub Repository Standards')"
judge "13: degrading wrote nothing"               "0"   "$(gh_mutations)"
atleast "13: and the sweep read the repositories" "3"   "$(reads)"

scenario org-scope
run_policy plan --org "$ORG"
judge "13: a scope wall names the scope, not the plan" "yes" "$(outhas 'admin:org')"
judge "13: and is not reported as a plan limit"        "no" \
  "$(outhas "unavailable on this organization's plan")"
judge "13: scope degrade wrote nothing"                "0"  "$(gh_mutations)"

# ---------------------------------------------------------------------------
section "14 — the entrypoint: a filter forces per-repository, and says why"
# ---------------------------------------------------------------------------
scenario org-available
run_policy plan --org "$ORG" --exclude 'ppfa-'
judge "14: targeting falls back to per-repository" "yes" "$(outhas 'Targeting: per-repository')"
judge "14: with the ERE-versus-glob reason"        "yes" "$(outhas 'POSIX EREs')"
judge "14: no org-level plan is offered"           "no"  "$(outhas 'Organization-level plan')"
judge "14: the filter was actually applied"        "no"  "$(outhas 'ppfa-proxy-gw')"
judge "14: and nothing was written"                "0"   "$(gh_mutations)"

# ---------------------------------------------------------------------------
section "15 — an organization ruleset stricter than canonical is left alone"
# ---------------------------------------------------------------------------
scenario org-stricter
run_policy_live apply --org "$ORG" --org-level --yes
judge "15: the conflict is reported"        "yes" "$(outhas 'CONFLICT')"
judge "15: naming the org ruleset"          "yes" "$(outhas 'Org baseline - reviews')"
judge "15: NOTHING was written to the org"  "0"   "$(writes_to "orgs/$ORG")"
atleast "15: while live state was read"     "2"   "$(reads)"

# ---------------------------------------------------------------------------
section "16 — the org-level write path, and the two gates on it"
# ---------------------------------------------------------------------------
scenario org-available
run_policy_live apply --org "$ORG" --yes
judge "16: apply --org WITHOUT --org-level writes no org ruleset" "0" "$(writes_to "orgs/$ORG")"
judge "16: and recommends the one-write path instead"             "yes" \
  "$(outhas "apply --org $ORG --org-level")"
atleast "16: while still doing the per-repository work"           "1" \
  "$(writes_to 'repos/')"

scenario org-available
run_policy_live apply --org "$ORG" --org-level --yes
judge "16 (positive): --org-level writes exactly the two canonical rulesets" "2" \
  "$(writes_to "orgs/$ORG/rulesets")"
judge "16: both are creates"  "2" \
  "$(awk -F'\t' -v p="orgs/$ORG/rulesets" '$2 == "POST" && index($3, p) { n++ } END { print n + 0 }' "$FAKE_GH_LOG")"
judge "16: the first body targets every repository" "~ALL" \
  "$(body_to "orgs/$ORG/rulesets" 1 | jq -r '.conditions.repository_name.include | join(",")' 2>/dev/null)"
judge "16: and the second does too" "~ALL" \
  "$(body_to "orgs/$ORG/rulesets" 2 | jq -r '.conditions.repository_name.include | join(",")' 2>/dev/null)"
judge "16: the two bodies are the two canonical rulesets" "Default Branch - PR & CI,Default Branch - Safety" \
  "$(printf '%s\n%s\n' "$(body_to "orgs/$ORG/rulesets" 1 | jq -r .name)" \
                        "$(body_to "orgs/$ORG/rulesets" 2 | jq -r .name)" | sort | paste -sd, -)"
judge "16: and no org ruleset was ever deleted"     "0" \
  "$(awk -F'\t' '$2 == "DELETE" { n++ } END { print n + 0 }' "$FAKE_GH_LOG")"

# The LIVE-TARGET GATE covers org writes exactly as it covers repository writes.
scenario org-available
fake_gh_reset
( cd "$ROOT" && bash "$ROOT/scripts/github-policy.sh" apply --org "$ORG" --org-level --yes ) \
  >"$OUT" 2>"$ERR"
judge "16 (gate): --yes alone, no terminal, writes no org ruleset" "0" "$(writes_to "orgs/$ORG")"
judge "16 (gate): and says why"                                    "yes" \
  "$(outhas 'refusing to write without a terminal')"
atleast "16 (gate): the refusal still read live state"             "1" "$(reads)"

run_policy plan --org-level
judge "16: --org-level without --org is refused" "1" "$RC"
judge "16: with the reason"                      "yes" "$(outhas 'org-level applies to --org')"

# ---------------------------------------------------------------------------
section "17 — the entrypoint reports the classic/ruleset overlap prominently"
# ---------------------------------------------------------------------------
fake_gh_use_fixtures "$FIX/classic-overlap"
git -C "$ROOT" remote remove origin >/dev/null 2>&1
git -C "$ROOT" remote add origin "git@github.com:Tamircohen28/example-repo.git"
rm -rf "$ROOT/.github"; mkdir -p "$ROOT/.github/workflows"
run_policy audit --repo Tamircohen28/example-repo
judge "17: the overlap is named"          "yes" "$(outhas 'GitHub applies both and the stricter requirement wins')"
judge "17: the strict hazard is named"    "yes" "$(outhas 'silently defeats strict_required_status_checks_policy: false')"
judge "17: the migration path is offered" "yes" "$(outhas 'Migration path (manual, in this order')"
judge "17: classic protection is never written" "0" "$(writes_to 'branches/')"
judge "17: auditing wrote nothing at all"       "0" "$(gh_mutations)"
atleast "17: and it read"                       "3" "$(reads)"

# Non-vacuity: a repository with rulesets and no classic protection must say
# none of that, or every assertion above would pass on a constant string.
fake_gh_use_fixtures "$FIX/compliant"
git -C "$ROOT" remote remove origin >/dev/null 2>&1
git -C "$ROOT" remote add origin "git@github.com:Tamircohen28/tamirs-superpowers.git"
run_policy audit --repo Tamircohen28/tamirs-superpowers
judge "17 (guard): a rulesets-only repo reports no overlap" "no" \
  "$(outhas 'GitHub applies both')"
judge "17 (guard): and no migration path"                   "no" \
  "$(outhas 'Migration path (manual')"

# ---------------------------------------------------------------------------
section "18 — the mock never fell through"
# ---------------------------------------------------------------------------
# Exit 78 / "no fixture mapping" would mean an assertion above was made against
# a command that never really ran.
judge "18: no unmapped path in the last run" "no" "$(has "$(cat "$ERR")" 'no fixture mapping')"
judge "18: no missing fixture in the last run" "no" "$(has "$(cat "$ERR")" 'no fixture for')"

harness_summary
