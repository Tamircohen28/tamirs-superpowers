#!/usr/bin/env bash
# test-github-policy.sh — the feature suite for scripts/github-policy.sh.
#
# WHAT MAKES THIS SUITE SAFE TO RUN
#   The subject creates and updates branch rulesets across every repository the
#   authenticated user owns. This machine is logged into a live account with
#   real repositories, so a suite that reached the network could rewrite live
#   branch governance. It cannot: `gh` is resolved from a temp bin dir holding
#   tests/lib/fake-gh.sh, the first assertions in the file prove that the shim —
#   and not the real `gh` — is what the subject will find on PATH, and every
#   later assertion is made against a recorded call log rather than against
#   GitHub. `gh_mutations` returning 0 is the proof a read path stayed a read
#   path.
#
# HOW THE SUBJECT IS ROOTED WITHOUT COPYING IT
#   github-policy.sh derives POLICY_REPO_ROOT from its own location, and reads
#   `.github/workflows` and `git remote get-url origin` from there. A hermetic
#   temp root with SYMLINKS to the real `scripts/` and `config/` gives the tests
#   full control of both — bash's logical `cd` keeps the symlinked path, so the
#   script computes POLICY_REPO_ROOT as the temp root while executing the real,
#   unmodified source file. Nothing is copied and nothing in the checkout is
#   touched.
#
# NON-VACUITY IS THE HOUSE RULE
#   Four bugs in this feature's development were checks that passed while
#   testing nothing. So no assertion here stands alone:
#     * every "no mutations" assertion is paired with an assertion that the mock
#       actually recorded the reads — a suite where the subject never ran at all
#       would otherwise pass identically;
#     * every negative ("this is not reported") is paired with a planted
#       positive proving the detector fires;
#     * assertions compare specific values, never truthiness.
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
TARGET_REPO="Tamircohen28/tamirs-superpowers"

# ---------------------------------------------------------------------------
# Hermetic environment
# ---------------------------------------------------------------------------
REAL_GH="$(command -v gh 2>/dev/null || true)"

mkdir -p "$TMP/bin" "$TMP/home" "$TMP/render"
cp -R "$REPO_ROOT/tests/fixtures/github" "$FIX"
harness_new_repo "$ROOT" main
ln -s "$REPO_ROOT/scripts" "$ROOT/scripts"
ln -s "$REPO_ROOT/config"  "$ROOT/config"

fake_gh_install "$TMP/bin" "$TMP/gh.log" "$FIX/compliant"
PATH="$TMP/bin:$PATH"
export PATH
export HOME="$TMP/home"
export GH_CONFIG_DIR="$TMP/home/gh"
export GH_TOKEN="" GITHUB_TOKEN=""
export NO_COLOR=1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# scenario <fixture-dir> <origin owner/repo> — point the mock at a scenario and
# give the hermetic root the `origin` that makes <owner/repo> its own checkout.
# The workflows directory is recreated empty every time: the subject prefers the
# local working tree when the target IS this checkout, and a file left behind by
# an earlier test would silently change a later one's Actions findings.
scenario() {
  fake_gh_use_fixtures "$FIX/$1"
  git -C "$ROOT" remote remove origin >/dev/null 2>&1
  git -C "$ROOT" remote add origin "git@github.com:$2.git"
  rm -rf "$ROOT/.github"
  mkdir -p "$ROOT/.github/workflows"
}

# run_policy <args...> — one invocation, with a fresh call log. Stdout and
# stderr are captured separately because `--json` splits the document from the
# human report across the two.
run_policy() {
  fake_gh_reset
  ( cd "$ROOT" && bash "$ROOT/scripts/github-policy.sh" "$@" ) >"$OUT" 2>"$ERR"
  RC=$?
}

# run_policy_live <args...> — the same, with the unattended-write authorisation
# the LIVE-TARGET GATE requires. Every assertion that counts mutations uses this,
# including the ones expecting ZERO: without it the gate is what produces the
# zero, and "the org guard blocked this write" would be indistinguishable from
# "no terminal, so nothing was going to be written anyway". The gate itself is
# tested on its own, further down, where its absence is the point.
run_policy_live() {
  fake_gh_reset
  ( cd "$ROOT" && GITHUB_POLICY_ALLOW_LIVE=1 \
      bash "$ROOT/scripts/github-policy.sh" "$@" ) >"$OUT" 2>"$ERR"
  RC=$?
}

reads()      { awk -F'\t' '$2 == "GET" { n++ } END { print n + 0 }' "$FAKE_GH_LOG"; }
writes_to()  { awk -F'\t' -v p="$1" '$2 != "GET" && index($3, p) { n++ } END { print n + 0 }' "$FAKE_GH_LOG"; }
jout()       { jq -r "$1" <"$OUT" 2>/dev/null; }
outhas()     { has "$(cat "$OUT" "$ERR" 2>/dev/null)" "$1"; }

# atleast <name> <minimum> <actual> — the non-vacuity primitive. "Nothing was
# written" only means something if something was read.
atleast() {
  if [ "${3:-0}" -ge "$2" ]; then ok "$1"; else bad "$1" "expected at least $2, got ${3:-0}"; fi
}

# plant_workflow <filename> — body on stdin.
plant_workflow() { cat >"$ROOT/.github/workflows/$1"; }

# jqi <file> <jq-args...> — edit a fixture in place.
jqi() { local f="$1"; shift; jq "$@" "$f" >"$f.new" && mv "$f.new" "$f"; }

# derive <new-scenario> <from-scenario> — a scenario is a directory, and every
# drift scenario in this suite is another one with a single field changed.
derive() { rm -rf "${FIX:?}/${1:?}"; cp -R "$FIX/$2" "$FIX/$1"; }

# ---------------------------------------------------------------------------
# Scenario derivation
# ---------------------------------------------------------------------------
# `compliant/` is the ground truth: the two rulesets as they actually stand on
# Tamircohen28/tamirs-superpowers, bypass actor and all. Canonical must resolve
# to the same thing through the repository's policy overrides, and the section
# below asserts exactly that — so a policy edit that forgets the fixture (or a
# fixture that drifts from the policy) fails ONE named assertion instead of
# scattering failures across twenty scenarios that all have the same cause.
#
# Every other scenario in this group is `compliant` with exactly one field
# changed, derived here rather than committed, so "one field apart" is true by
# construction rather than by somebody remembering to keep it true.

derive canonical compliant

# render_canonical <ruleset-key> <out-file> — what the policy says this repo
# should look like, produced by the shipped renderer in a subshell so this
# suite's shell never inherits the subject's library.
render_canonical() {
  bash -c '. "$1/scripts/lib/github-common.sh"
           github_render_payload_file "$2" "$3" "$4" "$5"' \
    _ "$REPO_ROOT" "$POLICY" "$1" "$TARGET_REPO" "$2"
}
render_canonical safety "$TMP/render/safety.json"
render_canonical pr_ci  "$TMP/render/pr_ci.json"

CANON_APPROVALS="$(jq -r '.rules[] | select(.type == "pull_request")
                          | .parameters.required_approving_review_count' "$TMP/render/pr_ci.json")"
HIGHER_APPROVALS=$((CANON_APPROVALS + 1))

# One boolean, three levels deep, is the whole difference from canonical.
derive strict-drift canonical
jqi "$FIX/strict-drift/ruleset-21049069.json" \
  '.rules |= map(if .type == "required_status_checks"
                 then .parameters.strict_required_status_checks_policy = true else . end)'

# The bypass actor is already on the canonical fixture, because it is on the
# real repository. This variant additionally DRIFTS, so a write must happen and
# must carry the actor through — a run that writes nothing could "preserve" an
# actor by doing nothing at all. `evaluate` -> `active` is a STRENGTHENING, so
# the weakening guard does not block it and it really does reach the API.
derive bypass-actor-drift canonical
jqi "$FIX/bypass-actor-drift/ruleset-21049069.json" '.enforcement = "evaluate"'
jqi "$FIX/bypass-actor-drift/rulesets.json" \
  'map(if .id == 21049069 then .enforcement = "evaluate" else . end)'

# One control set HIGHER than canonical: applying the policy here would lower it.
derive higher-approvals canonical
jqi "$FIX/higher-approvals/ruleset-21049069.json" --argjson n "$HIGHER_APPROVALS" \
  '.rules |= map(if .type == "pull_request"
                 then .parameters.required_approving_review_count = $n else . end)'

# The fleet's "compliant" member has to be compliant against the same policy.
cp "$FIX/canonical/ruleset-21049068.json" "$FIX/canonical/ruleset-21049069.json" \
   "$FIX/fleet/by-repo/Tamircohen28__tamirs-superpowers/"

# `gh repo list` shape is not the REST `user/repos` shape, and bulk scope reads
# the REST one. Three repositories, the three the fleet scenario answers for.
jq -n '[{ full_name: "Tamircohen28/tamirs-superpowers", default_branch: "master" },
        { full_name: "Tamircohen28/job-tracker-web",    default_branch: "main" },
        { full_name: "Tamircohen28/whoRuz",             default_branch: "main" }]
       | to_entries | map(.value + {
           id: (900000000 + .key), name: (.value.full_name | split("/")[1]),
           private: true, fork: false, archived: false, disabled: false,
           owner: { login: (.value.full_name | split("/")[0]), id: 61120534,
                    type: "User", site_admin: false } })' >"$FIX/fleet/repo-list.json"

# ProductionMasterAI is an organization, and the org-ruleset path keys on the
# owner type. The committed fixture says "User"; see the report accompanying
# this suite.
jqi "$FIX/org-conflict/repo.json" '.owner.type = "Organization"'

# ---------------------------------------------------------------------------
section "hermeticity — the real gh must be unreachable"
# ---------------------------------------------------------------------------
judge "gh on PATH is the fixture shim"        "$TMP/bin/gh" "$(command -v gh)"
judge "the shim identifies itself as fake-gh" "yes"         "$(has "$(gh --version 2>&1)" "fake-gh")"
judge "the shim delegates to tests/lib/fake-gh.sh" "yes"    "$(has "$(cat "$TMP/bin/gh")" "fake-gh.sh")"
if [ -n "$REAL_GH" ]; then
  if [ "$REAL_GH" = "$(command -v gh)" ]; then
    bad "the real gh is shadowed" "PATH still resolves gh to $REAL_GH"
  else
    ok "the real gh ($REAL_GH) is shadowed by the shim"
  fi
else
  skip "the real gh is shadowed" "no real gh on this machine to shadow"
fi
# A network call would need a client; the shim's whole program is these two files.
judge "nothing on the test PATH can reach the network" "0" \
  "$(grep -rlE '\bcurl\b|\bwget\b|api\.github\.com/[a-z]' "$TMP/bin" 2>/dev/null | wc -l | tr -d ' ')"
judge "the hermetic root's policy is the checkout's policy" "yes" \
  "$(exists "$ROOT/config/github/repository-policy.json")"
judge "the fixture tree the tests mutate is a private copy" "no" \
  "$(has "$FIX" "$REPO_ROOT")"

# ---------------------------------------------------------------------------
section "the committed ground truth still matches the policy"
# ---------------------------------------------------------------------------
# THE STALENESS GUARD. `compliant/` claims to be Tamircohen28/tamirs-superpowers
# as it actually is; the policy claims to describe what it should be. When those
# two drift apart every scenario built on `compliant` starts failing at once,
# and the cause is invisible in any one of them — that is precisely what
# happened when a per-repository `required_approving_review_count` was added to
# the policy and the fixture was left at the old value. So the comparison is
# made HERE, once, by name.
#
# The comparison is the subject's own: normalize live, carry the live bypass
# actors into the desired payload (they are preserved, never asserted), and the
# two must be equal. Values are then cross-checked against the policy document
# read by an independent path, so this is not the renderer agreeing with itself.
for key in safety:21049068 pr_ci:21049069; do
  rkey="${key%%:*}"; rid="${key##*:}"
  jq -s '.[0] as $live | .[1] as $desired
         | $desired + { bypass_actors: ($live.bypass_actors // []) }' \
    "$FIX/compliant/ruleset-$rid.json" "$TMP/render/$rkey.json" \
    | bash -c '. "$1/scripts/lib/github-common.sh"; github_ruleset_normalize' _ "$REPO_ROOT" \
    >"$TMP/desired-$rkey.json"
  bash -c '. "$1/scripts/lib/github-common.sh"; github_ruleset_normalize' _ "$REPO_ROOT" \
    <"$FIX/compliant/ruleset-$rid.json" >"$TMP/live-$rkey.json"
  if cmp -s "$TMP/desired-$rkey.json" "$TMP/live-$rkey.json"; then
    ok "the compliant fixture matches what the policy renders for $rkey"
  else
    bad "the compliant fixture matches what the policy renders for $rkey" \
        "fixture and policy disagree — refresh tests/fixtures/github/compliant/ruleset-$rid.json or the policy: $(diff "$TMP/live-$rkey.json" "$TMP/desired-$rkey.json" | tr '\n' ' ')"
  fi
done

# Independent reads of the policy document, so the guard above cannot pass by
# both sides being empty or both sides being wrong in the same way.
POLICY_CTX="$(jq -r '.repositories["'"$TARGET_REPO"'"].required_checks.contexts | length' "$POLICY")"
POLICY_APPROVALS="$(jq -r '.repositories["'"$TARGET_REPO"'"].rules.parameters.pull_request.required_approving_review_count
                           // (.rulesets[] | select(.key == "pr_ci") | .rules[]
                               | select(.type == "pull_request")
                               | .parameters.required_approving_review_count)' "$POLICY")"
judge   "ground truth: contexts match what the policy declares for this repo" "$POLICY_CTX" \
  "$(jq -r '[.rules[] | select(.type == "required_status_checks")
             | .parameters.required_status_checks[]] | length' "$FIX/compliant/ruleset-21049069.json")"
atleast "ground truth: the policy declares at least one context" "1"      "$POLICY_CTX"
judge   "ground truth: approvals match what the policy declares" "$POLICY_APPROVALS" "$CANON_APPROVALS"
judge   "ground truth: and the fixture carries that same number" "$POLICY_APPROVALS" \
  "$(jq -r '.rules[] | select(.type == "pull_request")
            | .parameters.required_approving_review_count' "$FIX/compliant/ruleset-21049069.json")"
judge   "ground truth: strict is off, as the architecture requires" "false" \
  "$(jq -r '.rules[] | select(.type == "required_status_checks")
            | .parameters.strict_required_status_checks_policy' "$FIX/compliant/ruleset-21049069.json")"
judge   "ground truth: the target is the magic ref, not a branch name" "~DEFAULT_BRANCH" \
  "$(jq -r '.conditions.ref_name.include[0]' "$FIX/compliant/ruleset-21049069.json")"
# The live repository carries an admin bypass actor. That is the fact the
# preservation ruling exists for, so the fixture has to carry it too.
judge   "ground truth: the live ruleset carries its admin bypass actor" "RepositoryRole 5 always" \
  "$(jq -r '.bypass_actors[0] | "\(.actor_type) \(.actor_id) \(.bypass_mode)"' \
      "$FIX/compliant/ruleset-21049069.json")"
judge   "ground truth: and canonical does NOT assert one" "0" \
  "$(jq '.bypass_actors | length' "$TMP/render/pr_ci.json")"
# Server-owned junk must be present, or "normalization works" is untested here.
judge "ground truth: live state carries server-owned fields to normalize away" "true" \
  "$(jq -r 'has("id") and has("node_id") and has("_links")
            and has("created_at") and has("current_user_can_bypass")' \
      "$FIX/compliant/ruleset-21049069.json")"
judge "ground truth: and those fields are absent from the desired payload" "false" \
  "$(jq -r 'has("id") or has("_links") or has("created_at")' "$TMP/render/pr_ci.json")"

# ---------------------------------------------------------------------------
section "1/2/3 — default branch is resolved, never spelled"
# ---------------------------------------------------------------------------
# One scenario per spelling. The request bodies must come out byte-identical:
# a run against only `main` would pass with a hardcoded default.
for spelling in main master trunk; do
  scenario "default-$spelling" "Tamircohen28/example-repo"
  run_policy_live apply --repo Tamircohen28/example-repo --yes
  judge "$spelling: two rulesets were created"   "2" "$(gh_mutations)"
  atleast "$spelling: the mock served reads"     "3" "$(reads)"
  gh_last_body 2 >"$TMP/body-$spelling-1.json"
  gh_last_body 1 >"$TMP/body-$spelling-2.json"
  judge "$spelling: the repo's branch was read"  "1" \
    "$(gh_calls "repos/Tamircohen28/example-repo	")"
  judge "$spelling: payload targets ~DEFAULT_BRANCH" "yes" \
    "$(has "$(cat "$TMP/body-$spelling-2.json")" "~DEFAULT_BRANCH")"
  # The literal is the bug. Search for all three spellings, not just this one:
  # a payload that hardcoded `main` would pass a test that only looked for
  # `trunk` while running the trunk scenario.
  for literal in main master trunk; do
    if grep -qiF "\"$literal\"" "$TMP/body-$spelling-1.json" "$TMP/body-$spelling-2.json"; then
      bad "$spelling: payload contains no literal branch name" "found \"$literal\""
    fi
  done
  ok "$spelling: payload contains no literal branch name"
done
judge "1 vs 2: main and master produce identical Safety payloads" "identical" \
  "$(cmp -s "$TMP/body-main-1.json" "$TMP/body-master-1.json" && echo identical || echo differs)"
judge "1 vs 3: main and trunk produce identical PR & CI payloads" "identical" \
  "$(cmp -s "$TMP/body-main-2.json" "$TMP/body-trunk-2.json" && echo identical || echo differs)"
# Non-vacuity for the comparison above: cmp must be capable of reporting a
# difference, so prove it does on two payloads that genuinely differ.
judge "cmp discriminates (guard)" "differs" \
  "$(cmp -s "$TMP/body-main-1.json" "$TMP/body-main-2.json" && echo identical || echo differs)"

# ---------------------------------------------------------------------------
section "4 — an already-compliant repository"
# ---------------------------------------------------------------------------
scenario canonical "$TARGET_REPO"
run_policy audit --repo "$TARGET_REPO" --json
judge   "4: bucket is already_compliant" "already_compliant" "$(jout '.repositories[0].bucket')"
judge   "4: both rulesets report up to date" "2"             "$(jout '.summary.up_to_date')"
judge   "4: zero planned changes" "0"                        "$(jout '.summary.changes')"
judge   "4: zero mutations" "0"                              "$(gh_mutations)"
atleast "4: the mock served reads" "5"                       "$(reads)"
run_policy audit --repo "$TARGET_REPO"
judge   "4: human report says COMPLIANT" "yes"               "$(outhas 'Result: COMPLIANT')"
judge   "4: exit 0 for a compliant repository" "0"           "$RC"

# ---------------------------------------------------------------------------
section "5 — classic branch-protection migration"
# ---------------------------------------------------------------------------
scenario classic-protection "Tamircohen28/example-repo"
run_policy plan --repo Tamircohen28/example-repo --json
judge "5: classic protection is reported"      "1" \
  "$(jout '[.changes[] | select(.label == "classic protection")] | length')"
judge "5: it is reported as a migration, not a change" "migration" \
  "$(jout '.changes[] | select(.label == "classic protection") | .blocked')"
judge "5: both rulesets are proposed for creation" "2"       "$(jout '.summary.changes')"
judge "5: the repo is not reported as unprotected" "drifted" "$(jout '.repositories[0].bucket')"
judge "5: zero mutations while planning" "0"                 "$(gh_mutations)"
judge "5: classic protection was never written" "0"          "$(writes_to 'branches/')"
atleast "5: the mock served reads" "4"                       "$(reads)"
run_policy plan --repo Tamircohen28/example-repo
judge "5: human report names the migration" "yes" \
  "$(outhas 'classic branch protection is present on main')"
# Non-vacuity: the same line must NOT appear on a repo that has no classic
# protection, or the assertion above would pass on a constant string.
scenario canonical "$TARGET_REPO"
run_policy audit --repo "$TARGET_REPO"
judge "5 (guard): a rulesets-only repo reports no classic protection" "yes" \
  "$(outhas 'no classic branch protection')"

# ---------------------------------------------------------------------------
section "6 — a repository with no rulesets at all"
# ---------------------------------------------------------------------------
scenario no-rulesets "Tamircohen28/example-repo"
run_policy plan --repo Tamircohen28/example-repo --json
judge "6: both rulesets are absent and planned" "2"          "$(jout '.summary.changes')"
judge "6: nothing is reported as up to date" "0"             "$(jout '.summary.up_to_date')"
judge "6: [] is a state, not a failure" "0"                  "$(jout '.summary.failed')"
judge "6: statuses are create/create" "create create" \
  "$(jout '[.changes[].status] | join(" ")')"
judge "6: plan wrote nothing" "0"                            "$(gh_mutations)"
atleast "6: the mock served reads" "4"                       "$(reads)"
run_policy_live apply --repo Tamircohen28/example-repo --yes
judge "6: apply issued exactly two creates" "2"              "$(gh_mutations)"
judge "6: both creates were POSTs to the rulesets collection" "2" \
  "$(writes_to 'repos/Tamircohen28/example-repo/rulesets')"
judge "6: created payload carries the canonical Safety name" "Default Branch - Safety" \
  "$(gh_last_body 2 | jq -r '.name')"
judge "6: created payload carries the canonical PR & CI name" "Default Branch - PR & CI" \
  "$(gh_last_body 1 | jq -r '.name')"
judge "6: a created ruleset gets no bypass actors" "0" \
  "$(gh_last_body 1 | jq -r '.bypass_actors | length')"

# ---------------------------------------------------------------------------
section "7 — partially configured (Safety present, PR & CI absent)"
# ---------------------------------------------------------------------------
scenario partial "Tamircohen28/example-repo"
run_policy plan --repo Tamircohen28/example-repo --json
judge "7: Safety is recognised as already present" "ok" \
  "$(jout '.changes[] | select(.label == "Default Branch - Safety") | .status')"
judge "7: PR & CI is the only thing to create" "create" \
  "$(jout '.changes[] | select(.label | startswith("Default Branch - PR")) | .status')"
judge "7: exactly one planned change" "1"                    "$(jout '.summary.changes')"
judge "7: exactly one already up to date" "1"                "$(jout '.summary.up_to_date')"
run_policy_live apply --repo Tamircohen28/example-repo --yes
judge "7: apply performed exactly one mutation" "1"          "$(gh_mutations)"
judge "7: and it created PR & CI, not Safety" "Default Branch - PR & CI" \
  "$(gh_last_body 1 | jq -r '.name')"
atleast "7: the mock served reads" "4"                       "$(reads)"

# ---------------------------------------------------------------------------
section "8 — a custom, unrelated ruleset survives untouched"
# ---------------------------------------------------------------------------
# Non-vacuity first: the scenario has to actually contain the foreign ruleset,
# otherwise "it was never touched" is a statement about nothing.
judge "8 (guard): the fixture lists a foreign ruleset 40000001" "1" \
  "$(jq '[.[] | select(.id == 40000001)] | length' "$FIX/custom-ruleset/rulesets.json")"
judge "8 (guard): the foreign ruleset targets tags" "tag" \
  "$(jq -r '.target' "$FIX/custom-ruleset/ruleset-40000001.json")"
scenario custom-ruleset "Tamircohen28/example-repo"
run_policy_live apply --repo Tamircohen28/example-repo --yes
judge "8: the foreign ruleset was never read, written or deleted" "0" "$(gh_calls '40000001')"
judge "8: no DELETE was ever issued" "0"                     "$(gh_calls 'DELETE')"
judge "8: no ruleset was deleted or replaced" "0"            "$(gh_mutations)"
atleast "8: the mock served reads" "4"                       "$(reads)"

# ---------------------------------------------------------------------------
section "9 — an organization ruleset is reported, never bypassed"
# ---------------------------------------------------------------------------
scenario org-conflict "ProductionMasterAI/example-service"
run_policy plan --repo ProductionMasterAI/example-service --json
judge "9: the org ruleset is recorded as a conflict" "conflict" \
  "$(jout '.changes[] | select(.label == "organization ruleset") | .status')"
judge "9: blocked by org_policy, not by anything else" "org_policy" \
  "$(jout '.changes[] | select(.label == "organization ruleset") | .blocked')"
judge "9: the repository lands in the conflict bucket" "conflict" \
  "$(jout '.repositories[0].bucket')"
judge "9: exactly one conflicted repository" "1"             "$(jout '.summary.conflicts')"
judge "9: the reason names the org ruleset" "yes" \
  "$(has "$(jout '.repositories[0].note')" 'Org baseline - reviews')"
judge "9: the org ruleset was never written" "0"             "$(writes_to '30000001')"
judge "9: nothing at all was written" "0"                    "$(gh_mutations)"
atleast "9: the mock served reads" "5"                       "$(reads)"
# Even with --yes and the weakening guard lifted, an org conflict is absolute:
# there is no flag that routes around it.
run_policy_live apply --repo ProductionMasterAI/example-service --yes --allow-weakening
judge "9: --yes --allow-weakening still writes nothing" "0"  "$(gh_mutations)"
atleast "9: the blocked apply still read live state" "5"     "$(reads)"

# ---------------------------------------------------------------------------
section "10 — missing GitHub permissions (403)"
# ---------------------------------------------------------------------------
scenario no-permission "Tamircohen28/example-repo"
run_policy audit --repo Tamircohen28/example-repo --json
judge "10: the repository is reported as failed" "failed"    "$(jout '.repositories[0].bucket')"
judge "10: exactly one failure" "1"                          "$(jout '.summary.failed')"
judge "10: the 403 is classified as a scope problem" "yes" \
  "$(has "$(jout '.repositories[0].note')" 'missing an OAuth scope')"
judge "10: the note carries the HTTP status" "yes" \
  "$(has "$(jout '.repositories[0].note')" 'HTTP 403')"
judge "10: a read that 403s writes nothing" "0"              "$(gh_mutations)"
atleast "10: the mock served reads before failing" "2"       "$(reads)"
run_policy audit --repo Tamircohen28/example-repo
judge "10: exit 3 signals the failure" "3"                   "$RC"
# Non-vacuity: the classifier must not report this on a healthy repository.
scenario canonical "$TARGET_REPO"
run_policy audit --repo "$TARGET_REPO" --json
judge "10 (guard): a healthy repo reports no scope failure" "0" "$(jout '.summary.failed')"

# ---------------------------------------------------------------------------
section "11 — a repository without Actions"
# ---------------------------------------------------------------------------
scenario no-actions "Tamircohen28/example-repo"
run_policy plan --repo Tamircohen28/example-repo
judge "11: the Actions section reports no workflows" "yes"   "$(outhas 'no workflows')"
judge "11: no workflow finding is invented" "no"             "$(outhas 'concurrency block')"
judge "11: branch governance is still planned" "yes"         "$(outhas 'not present on this repository')"
judge "11: nothing was written" "0"                          "$(gh_mutations)"
atleast "11: the mock served reads" "4"                      "$(reads)"
run_policy plan --repo Tamircohen28/example-repo --json
judge "11: no actions: change is recorded" "0" \
  "$(jout '[.changes[] | select(.label | startswith("actions:"))] | length')"

# ---------------------------------------------------------------------------
section "12 — required checks are per-repository, never globalised"
# ---------------------------------------------------------------------------
scenario different-checks "Tamircohen28/example-repo"
run_policy plan --repo Tamircohen28/example-repo --json
DC_NOTE="$(jout '.changes[] | select(.label | startswith("Default Branch - PR")) | .note')"
judge "12: this repo's own contexts are what is discussed" "yes" "$(has "$DC_NOTE" 'lint (node 20)')"
judge "12: a context with spaces survives intact" "yes"      "$(has "$DC_NOTE" 'build, lint (node 20), test')"
judge "12: another repo's contexts are not proposed" "no"    "$(has "$DC_NOTE" 'shellcheck')"
judge "12: no request ever mentions a foreign context" "0"   "$(gh_calls 'Repo contract')"
judge "12: nothing was rewritten" "0"                        "$(gh_mutations)"
atleast "12: the mock served reads" "4"                      "$(reads)"
# Non-vacuity: contexts DO get rendered for the repository that declares them,
# so their absence above is per-repo resolution and not a policy that simply
# never carries contexts at all.
judge "12 (guard): the plugin repo's contexts include the one just excluded" "yes" \
  "$(has "$(jq -r '.repositories["'"$TARGET_REPO"'"].required_checks.contexts | join(",")' "$POLICY")" 'shellcheck')"
judge "12 (guard): an unlisted repository declares none" "null" \
  "$(jq -r 'if (.repositories["Tamircohen28/example-repo"] | not) then "null" else "present" end' "$POLICY")"

# ---------------------------------------------------------------------------
section "13/14 — Actions concurrency: kind decides, not the absence of a block"
# ---------------------------------------------------------------------------
scenario canonical "$TARGET_REPO"
# Four workflows in ONE run, so the discriminations are made against each other
# rather than against four separate, individually-tunable runs.
plant_workflow ci.yml <<'YAML'
name: CI
on:
  pull_request:
  push:
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: make validate
YAML
plant_workflow pr-validate.yml <<'YAML'
name: PR Validate
on:
  pull_request:
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: shellcheck scripts/x.sh
YAML
plant_workflow release.yml <<'YAML'
name: Release
on:
  release:
    types: [published]
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - run: gh release create v1
YAML
plant_workflow deploy.yml <<'YAML'
name: Deploy
on:
  push:
    branches: [trunk]
concurrency:
  group: ${{ github.workflow }}
  cancel-in-progress: true
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - run: terraform apply
YAML
run_policy audit --repo "$TARGET_REPO" --json
judge "13: a cancellable workflow with no concurrency is a finding" "modify" \
  "$(jout '.changes[] | select(.label == "actions:ci.yml") | .status')"
judge "13: and the finding names the missing block" "missing concurrency block" \
  "$(jout '.changes[] | select(.label == "actions:ci.yml") | .note')"
judge "13: the fix is marked as a human edit, not a script write" "manual" \
  "$(jout '.changes[] | select(.label == "actions:ci.yml") | .blocked')"
judge "13: an expression-valued cancel-in-progress counts as present" "0" \
  "$(jout '[.changes[] | select(.label == "actions:pr-validate.yml")] | length')"
judge "14: a stateful workflow with NO block is excused by kind" "0" \
  "$(jout '[.changes[] | select(.label == "actions:release.yml")] | length')"
judge "14: a stateful workflow WITH cancellation is a hazard" "modify" \
  "$(jout '.changes[] | select(.label == "actions:deploy.yml") | .status')"
judge "14: and the hazard is named" "cancellation enabled on a stateful workflow" \
  "$(jout '.changes[] | select(.label == "actions:deploy.yml") | .note')"
judge "13/14: exactly two Actions findings" "2" \
  "$(jout '[.changes[] | select(.label | startswith("actions:"))] | length')"
judge "13/14: analysing workflows wrote nothing" "0"         "$(gh_mutations)"
run_policy audit --repo "$TARGET_REPO"
judge "13: the expression form is reported as cancelling" "yes" \
  "$(outhas 'pr-validate.yml — superseded PR runs cancelled (pull_request only)')"
judge "14: the never-cancel workflow is informational" "yes" \
  "$(outhas 'release.yml — cancellation intentionally not enabled')"
judge "13/14: an Actions finding makes the repo non-compliant" "3" "$RC"
# Non-vacuity for "excused by kind": release.yml and ci.yml BOTH lack a
# concurrency block, and only one is excused. Keyed on the absence of the block
# rather than on the workflow's kind, both would be excused — which is exactly
# what the pair of assertions above rules out.
judge "13/14 (guard): both excused and flagged workflows lack a block" "no" \
  "$(has "$(cat "$ROOT/.github/workflows/ci.yml" "$ROOT/.github/workflows/release.yml")" 'concurrency:')"

# ---------------------------------------------------------------------------
section "15 — dry-run bulk synchronization"
# ---------------------------------------------------------------------------
scenario fleet "$TARGET_REPO"
run_policy plan --all --json
judge   "15: all three repositories were visited" "3"        "$(jout '.repositories | length')"
judge   "15: mixed outcomes are reported per repo" "already_compliant drifted conflict" \
  "$(jout '[.repositories[].bucket] | join(" ")')"
judge   "15: both default-branch spellings in one run" "master main main" \
  "$(jout '[.repositories[].default_branch] | join(" ")')"
judge   "15: a dry run mutates nothing" "0"                  "$(gh_mutations)"
atleast "15: the mock served reads for every repo" "10"      "$(reads)"
run_policy plan --all
judge "15: the bulk report groups by outcome" "yes"          "$(outhas 'WOULD UPDATE (1)')"
judge "15: and says nothing was written" "yes"               "$(outhas 'Nothing has been written')"
judge "15: drift exits 3" "3"                                "$RC"

# ---------------------------------------------------------------------------
section "16 — one repository's 403 must not abort the sweep"
# ---------------------------------------------------------------------------
scenario fleet "$TARGET_REPO"
fake_gh_reset
fake_gh_error ANY 'repos/Tamircohen28/whoRuz/rulesets*' 403
( cd "$ROOT" && GITHUB_POLICY_ALLOW_LIVE=1 \
    bash "$ROOT/scripts/github-policy.sh" apply --all --yes --json ) >"$OUT" 2>"$ERR"
RC=$?
judge "16: the sweep still visited all three repositories" "3" "$(jout '.repositories | length')"
judge "16: only the forbidden repository failed" "1"         "$(jout '.summary.failed')"
judge "16: and it is the one that was denied" "failed" \
  "$(jout '.repositories[] | select(.repo == "Tamircohen28/whoRuz") | .bucket')"
judge "16: the healthy repository was still reconciled" "updated" \
  "$(jout '.repositories[] | select(.repo == "Tamircohen28/job-tracker-web") | .bucket')"
judge "16: the compliant repository was left alone" "already_compliant" \
  "$(jout '.repositories[] | select(.repo == "'"$TARGET_REPO"'") | .bucket')"
judge "16: exactly the two creates the healthy repo needed" "2" "$(gh_mutations)"
judge "16: every write went to the healthy repository" "2" \
  "$(writes_to 'repos/Tamircohen28/job-tracker-web/rulesets')"
judge "16: nothing was written to the denied repository" "0" "$(writes_to 'whoRuz')"

# ---------------------------------------------------------------------------
section "17 — idempotency: a second sync is a no-op"
# ---------------------------------------------------------------------------
scenario canonical "$TARGET_REPO"
run_policy_live apply --repo "$TARGET_REPO" --yes
judge   "17: first apply against a compliant repo writes nothing" "0" "$(gh_mutations)"
FIRST_READS="$(reads)"
atleast "17: but it did read the live state" "5"             "$FIRST_READS"
run_policy_live apply --repo "$TARGET_REPO" --yes
judge   "17: second apply writes nothing either" "0"         "$(gh_mutations)"
judge   "17: and re-read the same live state" "$FIRST_READS" "$(reads)"
run_policy_live verify --repo "$TARGET_REPO" --json
judge   "17: verify agrees the repo is still compliant" "already_compliant" \
  "$(jout '.repositories[0].bucket')"
judge   "17: and verify itself wrote nothing" "0"            "$(gh_mutations)"
# Non-vacuity: the same verb, same flags, against a repo that DOES need work,
# must write. Otherwise "zero mutations" would only prove apply never writes.
scenario no-rulesets "Tamircohen28/example-repo"
run_policy_live apply --repo Tamircohen28/example-repo --yes
judge "17 (guard): the same apply writes when there is work to do" "2" "$(gh_mutations)"

# ---------------------------------------------------------------------------
section "strict_required_status_checks_policy: true is detected"
# ---------------------------------------------------------------------------
# The single setting the whole architecture depends on staying false, nested
# three levels deep in one of two rulesets. Turning it off again is a weakening,
# so the correct answer is a reported conflict, not a silent rewrite.
scenario strict-drift "$TARGET_REPO"
run_policy plan --repo "$TARGET_REPO" --json
judge "strict: the repo is NOT reported compliant" "conflict" "$(jout '.repositories[0].bucket')"
judge "strict: PR & CI is the ruleset that differs" "conflict" \
  "$(jout '.changes[] | select(.label | startswith("Default Branch - PR")) | .status')"
judge "strict: and the reason is exactly the strict toggle" \
  'would turn OFF strict "branch must be up to date", which this repository currently enforces' \
  "$(jout '.changes[] | select(.label | startswith("Default Branch - PR")) | .note')"
judge "strict: the Safety ruleset is untouched by the finding" "ok" \
  "$(jout '.changes[] | select(.label == "Default Branch - Safety") | .status')"
judge "strict: detecting it writes nothing" "0"              "$(gh_mutations)"
atleast "strict: the mock served reads" "5"                  "$(reads)"
# Non-vacuity: the fixture differs from the canonical one in exactly this one
# boolean — a detector that always fires would also have failed the canonical
# scenario above, and one that compares only names or rule types finds nothing
# here at all.
judge "strict (guard): the fixture flips exactly one boolean" "true" \
  "$(jq -r '.rules[] | select(.type == "required_status_checks")
            | .parameters.strict_required_status_checks_policy' \
      "$FIX/strict-drift/ruleset-21049069.json")"
judge "strict (guard): nothing else differs from canonical" "0" \
  "$(diff <(jq -S . "$FIX/canonical/ruleset-21049069.json") \
          <(jq -S . "$FIX/strict-drift/ruleset-21049069.json") \
     | grep -E '^[<>]' | grep -vc 'strict_required_status_checks_policy')"

# ---------------------------------------------------------------------------
section "bypass actors are preserved, never asserted"
# ---------------------------------------------------------------------------
# The regression that would silently take away someone's ability to merge. The
# canonical policy says `bypass_actors: []`; a repository that carries one must
# keep it, and must not be reported as drifted for having it.
scenario canonical "$TARGET_REPO"
run_policy_live apply --repo "$TARGET_REPO" --yes --json
judge   "bypass: a preserved actor is not drift" "already_compliant" \
  "$(jout '.repositories[0].bucket')"
judge   "bypass: both rulesets read as up to date" "2"       "$(jout '.summary.up_to_date')"
judge   "bypass: zero mutations — the actor is not stripped" "0" "$(gh_mutations)"
atleast "bypass: the mock served reads" "5"                  "$(reads)"
run_policy audit --repo "$TARGET_REPO"
judge "bypass: the actor is surfaced rather than hidden" "yes" \
  "$(outhas 'Bypass actors (preserved, not asserted by policy)')"
judge "bypass: and it is named" "yes"                        "$(outhas 'RepositoryRole 5 (always)')"
judge "bypass: it does not make the repository non-compliant" "0" "$RC"
# The sharper case: a repository that DOES need a write must carry its bypass
# actor through into the payload. A run where nothing is written could "preserve"
# an actor by doing nothing at all.
scenario bypass-actor-drift "$TARGET_REPO"
run_policy_live apply --repo "$TARGET_REPO" --yes
judge "bypass: the drifting ruleset was updated" "1"         "$(gh_mutations)"
judge "bypass: with a PUT to the existing ruleset" "1"       "$(writes_to 'rulesets/21049069')"
judge "bypass: the payload still carries the actor" "1"      "$(gh_last_body 1 | jq -r '.bypass_actors | length')"
judge "bypass: with its identity intact" "RepositoryRole 5 always" \
  "$(gh_last_body 1 | jq -r '.bypass_actors[0] | "\(.actor_type) \(.actor_id) \(.bypass_mode)"')"
judge "bypass: while the real drift WAS corrected" "active"  "$(gh_last_body 1 | jq -r '.enforcement')"
# Non-vacuity: the canonical policy really does say `[]`, so the actor in that
# payload came from live state and not from the policy document.
judge "bypass (guard): canonical PR & CI declares no bypass actors" "0" \
  "$(jq '.rulesets[] | select(.key == "pr_ci") | .bypass_actors | length' "$POLICY")"
judge "bypass (guard): and the rendered desired payload has none either" "0" \
  "$(jq '.bypass_actors | length' "$TMP/render/pr_ci.json")"

# ---------------------------------------------------------------------------
section "lowering an existing control is refused"
# ---------------------------------------------------------------------------
# Live requires one more approving review than canonical. Applying the policy
# would take that away, so it must be reported and refused, not applied.
scenario higher-approvals "$TARGET_REPO"
run_policy plan --repo "$TARGET_REPO" --json
judge "lower: the repository is BLOCKED, not quietly downgraded" "conflict" \
  "$(jout '.repositories[0].bucket')"
judge "lower: the change is a conflict" "conflict" \
  "$(jout '.changes[] | select(.label | startswith("Default Branch - PR")) | .status')"
judge "lower: blocked by the weakening guard" "weakens_existing_control" \
  "$(jout '.changes[] | select(.label | startswith("Default Branch - PR")) | .blocked')"
judge "lower: and it is marked destructive" "true" \
  "$(jout '.changes[] | select(.label | startswith("Default Branch - PR")) | .destructive')"
judge "lower: the reason names both numbers" \
  "would lower required approving reviews from $HIGHER_APPROVALS to $CANON_APPROVALS" \
  "$(jout '.changes[] | select(.label | startswith("Default Branch - PR")) | .note')"
judge "lower: nothing was written" "0"                       "$(gh_mutations)"
run_policy_live apply --repo "$TARGET_REPO" --yes
judge "lower: even apply --yes refuses" "0"                  "$(gh_mutations)"
atleast "lower: the refusing run still read live state" "5"  "$(reads)"
run_policy plan --repo "$TARGET_REPO"
judge "lower: the human report says BLOCKED" "yes"           "$(outhas 'Result: BLOCKED')"
judge "lower: exit 3" "3"                                    "$RC"
# The escape hatch exists, is explicit, and is not implied by --yes.
run_policy_live apply --repo "$TARGET_REPO" --yes --allow-weakening
judge "lower: --allow-weakening is what unblocks it" "1"     "$(gh_mutations)"
judge "lower: and the applied payload is the canonical value" "$CANON_APPROVALS" \
  "$(gh_last_body 1 | jq -r '.rules[] | select(.type == "pull_request")
                             | .parameters.required_approving_review_count')"

# ---------------------------------------------------------------------------
section "read paths make zero mutating calls"
# ---------------------------------------------------------------------------
# The safety boundary of the whole feature, asserted across every scenario the
# suite owns rather than at one convenient spot. Each row also asserts the mock
# recorded reads, so a scenario that failed to run at all cannot pass as "safe".
# `--yes --allow-weakening` is passed deliberately: not even the two flags that
# authorise writing may make a read verb write.
for combo in \
  "audit canonical Tamircohen28/tamirs-superpowers" \
  "audit no-rulesets Tamircohen28/example-repo" \
  "audit drifted Tamircohen28/example-repo" \
  "audit classic-protection Tamircohen28/example-repo" \
  "audit custom-ruleset Tamircohen28/example-repo" \
  "audit different-checks Tamircohen28/example-repo" \
  "audit no-permission Tamircohen28/example-repo" \
  "audit strict-drift Tamircohen28/tamirs-superpowers" \
  "audit bypass-actor-drift Tamircohen28/tamirs-superpowers" \
  "plan canonical Tamircohen28/tamirs-superpowers" \
  "plan partial Tamircohen28/example-repo" \
  "plan higher-approvals Tamircohen28/tamirs-superpowers" \
  "plan org-conflict ProductionMasterAI/example-service" \
  "verify no-rulesets Tamircohen28/example-repo" \
  "verify canonical Tamircohen28/tamirs-superpowers"; do
  # shellcheck disable=SC2086  # each row is three space-separated words by design
  set -- $combo
  verb="$1"; fixture="$2"; target="$3"
  scenario "$fixture" "$target"
  run_policy_live "$verb" --repo "$target" --yes --allow-weakening
  judge   "$verb on $fixture: zero mutations" "0"            "$(gh_mutations)"
  atleast "$verb on $fixture: reads were recorded" "2"       "$(reads)"
done
scenario fleet "$TARGET_REPO"
run_policy plan --all --yes
judge   "plan --all --yes: zero mutations" "0"               "$(gh_mutations)"
atleast "plan --all --yes: reads were recorded" "10"         "$(reads)"

# ---------------------------------------------------------------------------
section "no TTY, and the live-target gate: print the plan, adopt nothing"
# ---------------------------------------------------------------------------
# stdout here is a file, so setup_can_prompt is false by construction — the same
# situation as CI, a hook, or a piped run.
scenario no-rulesets "Tamircohen28/example-repo"
run_policy apply --repo Tamircohen28/example-repo
judge "no-TTY: single-repo apply degrades to a plan" "yes"   "$(outhas 'no TTY — cannot confirm')"
judge "no-TTY: and writes nothing" "0"                       "$(gh_mutations)"
judge "no-TTY: the plan is still printed" "yes"              "$(outhas 'Nothing has been written')"
judge "no-TTY: a degraded run is a success, not a failure" "0" "$RC"
atleast "no-TTY: it still read live state" "4"               "$(reads)"
scenario fleet "$TARGET_REPO"
run_policy apply --all
judge "no-TTY: bulk apply degrades too" "yes"                "$(outhas 'cannot confirm a bulk apply')"
judge "no-TTY: a 3-repo sweep writes nothing" "0"            "$(gh_mutations)"
atleast "no-TTY: the sweep still read every repo" "10"       "$(reads)"

# THE LIVE-TARGET GATE. --yes confirms individual changes; it is deliberately
# NOT the authorisation to mutate real repositories with nobody watching. That
# distinction was added after an unattended --yes run reverted a deliberate
# setting on the author's own repository, so it is asserted here directly: same
# command, same scenario, the only difference is the environment variable.
scenario no-rulesets "Tamircohen28/example-repo"
run_policy apply --repo Tamircohen28/example-repo --yes
judge "gate: --yes alone does NOT authorise an unattended write" "0" "$(gh_mutations)"
judge "gate: and it says why" "yes" \
  "$(outhas 'it does not authorise unattended mutation of live repositories')"
judge "gate: and it names the way to opt in" "yes"           "$(outhas 'GITHUB_POLICY_ALLOW_LIVE=1')"
judge "gate: the plan is shown instead" "yes"                "$(outhas 'Nothing has been written')"
judge "gate: a refused write is not an error" "0"            "$RC"
atleast "gate: the refusal still read live state" "4"        "$(reads)"
# Non-vacuity: the ONLY difference between these two runs is the variable, so a
# gate that blocked everything unconditionally would fail here.
run_policy_live apply --repo Tamircohen28/example-repo --yes
judge "gate: GITHUB_POLICY_ALLOW_LIVE=1 plus --yes is what writes" "2" "$(gh_mutations)"
judge "gate: and the writes are the two canonical creates" "2" \
  "$(writes_to 'repos/Tamircohen28/example-repo/rulesets')"
# The variable is not a substitute for --yes either: both are required.
run_policy_live apply --repo Tamircohen28/example-repo
judge "gate: the variable alone, without --yes, still writes nothing" "0" "$(gh_mutations)"
atleast "gate: and that run read live state too" "4"         "$(reads)"
scenario fleet "$TARGET_REPO"
run_policy apply --all --yes
judge "gate: a bulk --yes sweep is refused the same way" "0"  "$(gh_mutations)"
run_policy_live apply --all --yes
atleast "gate: and authorised, the same sweep does write" "1" "$(gh_mutations)"

# ---------------------------------------------------------------------------
section "flag handling"
# ---------------------------------------------------------------------------
scenario canonical "$TARGET_REPO"
run_policy --help
judge "help: exits 0" "0"                                    "$RC"
judge "help: documents the verbs" "yes"                      "$(outhas 'audit|plan|apply|verify')"
judge "help: made no API call at all" "0"                    "$(reads)"
run_policy audit --repo "$TARGET_REPO" --nonsense
judge "unknown flag: exits 1" "1"                            "$RC"
judge "unknown flag: says which one" "yes"                   "$(outhas 'unknown flag: --nonsense')"
judge "unknown flag: made no API call" "0"                   "$(reads)"
run_policy audit --all
judge "scope: audit refuses --all" "1"                       "$RC"
judge "scope: and says to use plan" "yes"                    "$(outhas "use 'plan' for --all")"
judge "scope: refusing costs no API call" "0"                "$(reads)"
run_policy plan --repo "$TARGET_REPO" --all
judge "scope: two scopes at once is refused" "1"             "$RC"
judge "scope: with the reason" "yes"                         "$(outhas 'exactly one of --repo / --all / --org')"

# ---------------------------------------------------------------------------
section "the mock itself never fell through"
# ---------------------------------------------------------------------------
# Exit 78 is fake-gh's "I do not know how to answer this". A suite that quietly
# accumulated those would be asserting on degraded output.
judge "fake-gh answered the last run without falling through" "no" \
  "$(has "$(cat "$ERR")" 'no fixture mapping')"

harness_summary
