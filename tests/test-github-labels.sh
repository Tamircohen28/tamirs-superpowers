#!/usr/bin/env bash
# test-github-labels.sh — the feature suite for scripts/github-labels.sh and
# scripts/check-github-labels.sh.
#
# WHAT MAKES THIS SUITE SAFE TO RUN
#   The subject creates, updates and (with --prune) deletes labels on every
#   repository the authenticated user owns. This machine is logged into a live
#   account, so a suite that reached the network could rewrite real labels and
#   strip them from real issues. It cannot: `gh` is resolved from a temp bin dir
#   holding tests/lib/fake-gh.sh, the first assertions prove the shim is what the
#   subject finds on PATH, and every later assertion is made against a recorded
#   call log. `gh_mutations` returning 0 is the proof a read path stayed a read.
#
# HOW THE SUBJECT IS ROOTED
#   github-labels.sh derives its repo root from its own location and reads
#   config/github/labels.json and core/capabilities/platforms.json from there.
#   A hermetic temp root with SYMLINKS to the real scripts/, config/ and core/
#   gives the tests the real, unmodified subject.
#
# NON-VACUITY IS THE HOUSE RULE
#   Every "no mutations" assertion is paired with one proving the reads were
#   recorded; every negative is paired with a planted positive; every count is
#   a specific number, never truthiness. The expected agent:<platform> labels
#   are DERIVED from the capability registry inside the test, never listed.
#
# bash 3.2. `set -uo pipefail`, not -e: the assertions are the control flow.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"
# shellcheck source=tests/lib/fake-gh.sh
source "$REPO_ROOT/tests/lib/fake-gh.sh"

harness_require git jq awk sed

TMP="$(harness_tmpdir)"
FIX="$TMP/fixtures"
ROOT="$TMP/root"
OUT="$TMP/stdout"
ERR="$TMP/stderr"
RC=0
TARGET_REPO="Tamircohen28/example-repo"
LABELS_FILE="$REPO_ROOT/config/github/labels.json"
REGISTRY="$REPO_ROOT/core/capabilities/platforms.json"

# ---------------------------------------------------------------------------
# Hermetic environment
# ---------------------------------------------------------------------------
mkdir -p "$TMP/bin" "$TMP/home"
cp -R "$REPO_ROOT/tests/fixtures/github" "$FIX"
harness_new_repo "$ROOT" main
ln -s "$REPO_ROOT/scripts" "$ROOT/scripts"
ln -s "$REPO_ROOT/config" "$ROOT/config"
ln -s "$REPO_ROOT/core"   "$ROOT/core"

fake_gh_install "$TMP/bin" "$TMP/gh.log" "$FIX/labels-compliant"
PATH="$TMP/bin:$PATH"
export PATH
export HOME="$TMP/home"
export GH_CONFIG_DIR="$TMP/home/gh"
export GH_TOKEN="" GITHUB_TOKEN=""
export NO_COLOR=1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
scenario() { fake_gh_use_fixtures "$FIX/$1"; }

# run_labels <args...> — one invocation with a fresh call log. stdout and
# stderr are captured separately because `--json` splits the document from the
# human report. stdout is a file, so no run here has a terminal.
run_labels() {
  fake_gh_reset
  ( cd "$ROOT" && bash "$ROOT/scripts/github-labels.sh" "$@" ) >"$OUT" 2>"$ERR"
  RC=$?
}
# run_labels_live — kept as the name every mutation count uses (each passes
# --yes, the only way to write without a terminal).
run_labels_live() { run_labels "$@"; }
# run_labels_raw — as run_labels, but WITHOUT fake_gh_reset, so an error
# injected with fake_gh_error just before it is still in force (reset clears
# injected errors along with the log).
run_labels_raw() {
  ( cd "$ROOT" && bash "$ROOT/scripts/github-labels.sh" "$@" ) >"$OUT" 2>"$ERR"
  RC=$?
}
outhas() { has "$(cat "$OUT")" "$1"; }
errhas() { has "$(cat "$ERR")" "$1"; }
anyhas() { has "$(cat "$OUT" "$ERR")" "$1"; }
# calls <METHOD> <path-suffix> — recorded invocations whose method and path
# match exactly (the log is seq, method, path, body, argv).
calls() { awk -F'\t' -v m="$1" -v p="$2" '$2 == m && $3 == p { n++ } END { print n + 0 }' "$FAKE_GH_LOG"; }
# body_of <METHOD> <path> — the compacted request body of the first such call.
body_of() { awk -F'\t' -v m="$1" -v p="$2" '$2 == m && $3 == p { print $4; exit }' "$FAKE_GH_LOG"; }

PLATFORMS="$(jq -r '.platforms | keys[]' "$REGISTRY")"
N_PLATFORMS="$(printf '%s\n' "$PLATFORMS" | grep -c .)"
N_FILE="$(jq '.labels | length' "$LABELS_FILE")"
N_DEFAULTS="$(jq '[.labels[] | select(.origin == "github-default")] | length' "$LABELS_FILE")"
N_TAMIRS=$((N_FILE - N_DEFAULTS))
# labels-missing carries the nine defaults + agent:any (drifted) + one extra, so:
EXPECT_OK=$N_DEFAULTS
EXPECT_UPDATE=1
EXPECT_CREATE=$((N_TAMIRS - 1 + N_PLATFORMS))
LABELS_PATH="repos/$TARGET_REPO/labels"

# ---------------------------------------------------------------------------
section "hermeticity — the shim, not the real gh, is on PATH"
judge "gh resolves to the temp shim"  "$TMP/bin/gh" "$(command -v gh)"
judge "the shim identifies itself"    "yes" "$(has "$(gh --version 2>&1)" "fake-gh")"
judge "the registry declares platforms (the test derives its expectations from it)" "yes" "$([ "$N_PLATFORMS" -ge 1 ] && echo yes || echo no)"

# ---------------------------------------------------------------------------
section "audit — a repository missing most of the set"
scenario labels-missing
run_labels audit --repo "$TARGET_REPO"
judge "audit exits 3 on drift"                      3   "$RC"
judge "audit reports the drifted bucket"            yes "$(outhas "$TARGET_REPO · labels")"
judge "audit reports the drifted bucket by name"    yes "$(outhas "· drifted")"
judge "the summary line counts ok/create/update/extra exactly" yes \
  "$(outhas "$EXPECT_OK ok · $EXPECT_CREATE to create · $EXPECT_UPDATE to update · 1 extra · 0 to delete")"
judge "the drifted agent:any is an update"          yes "$(outhas "~ agent:any")"
judge "  with the description change spelled out"   yes "$(outhas "description \"Unclaimed\" →")"
judge "the extra label is reported as extra"        yes "$(outhas "stale-experiment")"
judge "  and marked left alone"                     yes "$(outhas "left alone (--prune deletes it)")"
judge "a colour that differs only by case is NOT drift (invalid: E4E669)" yes "$(outhas "✓ invalid")"
judge "chore is a create with its canonical colour" yes "$(outhas "+ chore")"
judge "  and the create row shows the colour and description" yes "$(outhas "#fef2c0")"
missing_platform=""
while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ "$(outhas "+ agent:$p")" = yes ] || missing_platform="$missing_platform $p"
done <<<"$PLATFORMS"
judge "every agent:<platform> from the registry is a create" "" "$missing_platform"
judge "audit performed no mutation"                 0   "$(gh_mutations)"
judge "  and did read the repository"               1   "$(calls GET "repos/$TARGET_REPO")"
judge "  and did read the labels"                   1   "$(calls GET "$LABELS_PATH")"
judge "audit points at plan to remediate"           yes "$(outhas "Remediate:  bash scripts/github-labels.sh plan --repo $TARGET_REPO")"

# ---------------------------------------------------------------------------
section "audit — a compliant repository"
scenario labels-compliant
run_labels audit --repo "$TARGET_REPO"
judge "audit exits 0 when compliant"                0   "$RC"
judge "reports compliant"                           yes "$(outhas "· compliant")"
judge "nothing to create"                           yes "$(outhas "0 to create · 0 to update · 0 extra")"
judge "no mutation"                                 0   "$(gh_mutations)"
judge "  the labels were read"                      1   "$(calls GET "$LABELS_PATH")"

# ---------------------------------------------------------------------------
section "plan — never writes"
scenario labels-missing
run_labels plan --repo "$TARGET_REPO"
judge "plan exits 3 on drift"                       3   "$RC"
judge "plan says nothing was written"               yes "$(outhas "Nothing has been written")"
judge "plan performed no mutation"                  0   "$(gh_mutations)"
run_labels plan --repo "$TARGET_REPO" --prune
judge "plan --prune lists the extra as a delete"    yes "$(outhas "- stale-experiment")"
judge "  and still performed no mutation"           0   "$(gh_mutations)"
run_labels --dry-run --repo "$TARGET_REPO"
judge "--dry-run is plan"                           yes "$(outhas "Nothing has been written")"

# ---------------------------------------------------------------------------
section "apply — creates and updates, never deletes without --prune"
scenario labels-missing
run_labels_live apply --repo "$TARGET_REPO" --yes
judge "apply exits 0"                               0   "$RC"
judge "the repository is reported updated"          yes "$(outhas "· updated")"
judge "one POST per missing label"                  "$EXPECT_CREATE" "$(calls POST "$LABELS_PATH")"
judge "one PATCH for the drifted label"             1   "$(calls PATCH "$LABELS_PATH/agent%3Aany")"
judge "no DELETE without --prune"                   0   "$(awk -F'\t' '$2 == "DELETE" { n++ } END { print n + 0 }' "$FAKE_GH_LOG")"
judge "total mutations = creates + updates"         $((EXPECT_CREATE + EXPECT_UPDATE)) "$(gh_mutations)"
chore_body="$(awk -F'\t' -v p="$LABELS_PATH" '$2 == "POST" && $3 == p && $4 ~ /"name":"chore"/ { print $4; exit }' "$FAKE_GH_LOG")"
judge "the chore POST carries the canonical colour"  "fef2c0" "$(jq -r '.color' <<<"$chore_body")"
judge "  and the canonical description"             "$(jq -r '.labels[] | select(.name == "chore") | .description' "$LABELS_FILE")" "$(jq -r '.description' <<<"$chore_body")"
missing_platform=""
while IFS= read -r p; do
  [ -n "$p" ] || continue
  dn="$(jq -r --arg k "$p" '.platforms[$k].display_name' "$REGISTRY")"
  b="$(awk -F'\t' -v p="$LABELS_PATH" -v n="\"name\":\"agent:$p\"" '$2 == "POST" && $3 == p && index($4, n) { print $4; exit }' "$FAKE_GH_LOG")"
  [ -n "$b" ] || { missing_platform="$missing_platform $p(no POST)"; continue; }
  [ "$(has "$(jq -r '.description' <<<"$b")" "$dn")" = yes ] || missing_platform="$missing_platform $p(description lacks $dn)"
done <<<"$PLATFORMS"
judge "every agent:<platform> POST carries the registry display_name" "" "$missing_platform"
patch_body="$(body_of PATCH "$LABELS_PATH/agent%3Aany")"
judge "the PATCH sends the canonical description"   "$(jq -r '.labels[] | select(.name == "agent:any") | .description' "$LABELS_FILE")" "$(jq -r '.description' <<<"$patch_body")"
judge "  and no new_name when the name already matches" "null" "$(jq -r '.new_name' <<<"$patch_body")"
judge "apply points at audit to verify"             yes "$(outhas "Verify:     bash scripts/github-labels.sh audit --repo $TARGET_REPO")"

section "apply --prune — the one path that deletes"
scenario labels-missing
run_labels_live apply --repo "$TARGET_REPO" --yes --prune
judge "apply --prune exits 0"                       0   "$RC"
judge "exactly one DELETE, for the extra label"     1   "$(calls DELETE "$LABELS_PATH/stale-experiment")"
judge "  and no other DELETE"                       1   "$(awk -F'\t' '$2 == "DELETE" { n++ } END { print n + 0 }' "$FAKE_GH_LOG")"
judge "creates are unchanged by --prune"            "$EXPECT_CREATE" "$(calls POST "$LABELS_PATH")"

section "apply — idempotent on a compliant repository"
scenario labels-compliant
run_labels_live apply --repo "$TARGET_REPO" --yes --prune
judge "apply exits 0"                               0   "$RC"
judge "zero mutations"                              0   "$(gh_mutations)"
judge "  the labels were read"                      1   "$(calls GET "$LABELS_PATH")"
judge "reports compliant"                           yes "$(outhas "· compliant")"

# ---------------------------------------------------------------------------
section "no TTY — apply without --yes prints the plan and writes nothing"
scenario labels-missing
run_labels apply --repo "$TARGET_REPO"
judge "no TTY: exits 0 (degraded to plan)"          0   "$RC"
judge "no TTY: nothing written"                     0   "$(gh_mutations)"
judge "  the labels were still read"                1   "$(calls GET "$LABELS_PATH")"
judge "no TTY: says it cannot confirm"              yes "$(errhas "no TTY — cannot confirm")"
judge "no TTY: names --yes"                         yes "$(errhas "re-run with --yes to apply")"
judge "no TTY: the plan was still printed"          yes "$(outhas "+ chore")"
run_labels apply --repo "$TARGET_REPO" --prune
judge "no TTY + --prune: deletes nothing"           0   "$(gh_mutations)"

# ---------------------------------------------------------------------------
section "--json"
scenario labels-missing
run_labels audit --repo "$TARGET_REPO" --json
judge "json: stdout parses"                         yes "$(jq empty "$OUT" >/dev/null 2>&1 && echo yes || echo no)"
judge "json: verb"                                  audit "$(jq -r '.verb' "$OUT")"
judge "json: one repo"                              1   "$(jq '.repos | length' "$OUT")"
judge "json: bucket"                                drifted "$(jq -r '.repos[0].bucket' "$OUT")"
judge "json: create count"                          "$EXPECT_CREATE" "$(jq '.repos[0].summary.create' "$OUT")"
judge "json: update count"                          "$EXPECT_UPDATE" "$(jq '.repos[0].summary.update' "$OUT")"
judge "json: extra count"                           1   "$(jq '.repos[0].summary.extra' "$OUT")"
judge "json: the missing names are listed"          yes "$(has "$(jq -r '[.repos[0].changes[] | select(.status == "create") | .name] | join(",")' "$OUT")" "chore")"
judge "json: totals"                                "$EXPECT_CREATE" "$(jq '.summary.create' "$OUT")"
judge "json: prune false"                           false "$(jq '.prune' "$OUT")"
judge "json: not degraded"                          false "$(jq '.degraded' "$OUT")"
judge "json: human report went to stderr, not stdout" no "$(outhas "Remediate:")"
judge "json: drift exits 3, exactly as the human audit does" 3 "$RC"
run_labels apply --repo "$TARGET_REPO" --json
judge "json: a degraded apply says so"              true "$(jq '.degraded' "$OUT")"
judge "  and wrote nothing"                         0   "$(gh_mutations)"
judge "  and exits 0 (degraded is a success)"       0   "$RC"
scenario labels-compliant
run_labels audit --repo "$TARGET_REPO" --json
judge "json: compliant exits 0"                     0   "$RC"
judge "  with the compliant bucket"                 compliant "$(jq -r '.repos[0].bucket' "$OUT")"
# The exit code is decided before either renderer runs. An early `exit 0` on
# the JSON path once let a failed read exit 0 while the human audit exited 3,
# so a caller parsing --json could not tell "compliant" from "could not read".
scenario labels-missing
fake_gh_reset
fake_gh_error GET 'repos/*/*/labels' 403-rate-limit
run_labels_raw audit --repo "$TARGET_REPO" --json
judge "json: a failed read exits 3, like the human audit" 3 "$RC"
judge "  the document still parses"                 yes "$(jq empty "$OUT" >/dev/null 2>&1 && echo yes || echo no)"
judge "  and names the failed bucket"               failed "$(jq -r '.repos[0].bucket' "$OUT")"
judge "  with the rate-limit reason"                yes "$(has "$(jq -r '.repos[0].note' "$OUT")" "rate limit")"
fake_gh_reset
fake_gh_error POST 'repos/*/*/labels' 422
run_labels_raw apply --repo "$TARGET_REPO" --yes --json
judge "json: failed writes exit 3"                  3   "$RC"
judge "  and the failed count is in the document"   "$EXPECT_CREATE" "$(jq '.repos[0].summary.failed' "$OUT")"
fake_gh_reset

# ---------------------------------------------------------------------------
section "API failures are a bucket, never an abort"
scenario labels-missing
fake_gh_reset
fake_gh_error POST 'repos/*/*/labels' 422
run_labels_raw apply --repo "$TARGET_REPO" --yes
judge "a 422 on create exits 3"                     3   "$RC"
judge "the repository is reported failed"           yes "$(outhas "· failed")"
judge "  with the count of failed writes"           yes "$(outhas "$EXPECT_CREATE write(s) failed")"
judge "  the PATCH still went through"              1   "$(calls PATCH "$LABELS_PATH/agent%3Aany")"
judge "  and each failed row says why"              yes "$(outhas "✗ chore")"
fake_gh_reset
fake_gh_error GET 'repos/*/*/labels' 403-rate-limit
run_labels_raw audit --repo "$TARGET_REPO"
judge "a rate limit on the read exits 3"            3   "$RC"
judge "  and is named as a rate limit, not a permission failure" yes "$(outhas "rate limit")"
judge "  nothing was written"                       0   "$(gh_mutations)"
judge "  the read was attempted"                    1   "$(calls GET "$LABELS_PATH")"
fake_gh_reset
fake_gh_error GET 'repos/*/*' 404
run_labels_raw audit --repo "$TARGET_REPO"
judge "an unknown repository exits 1"               1   "$RC"
judge "  with the not-found explanation"            yes "$(errhas "not found")"
fake_gh_reset

# ---------------------------------------------------------------------------
section "CLI contract"
run_labels --help
judge "--help exits 0"                              0   "$RC"
judge "--help documents --prune"                    yes "$(outhas "--prune")"
judge "--help documents --yes"                      yes "$(outhas "--yes, -y")"
run_labels --bogus
judge "unknown flag exits 1"                        1   "$RC"
judge "  and hints at --help"                       yes "$(errhas "Try: bash scripts/github-labels.sh --help")"
run_labels audit --all
judge "audit --all is refused"                      1   "$RC"
run_labels audit --repo a/b --org c
judge "two scopes are refused"                      1   "$RC"
run_labels audit --repo noslash
judge "a repo without owner/ is refused"            1   "$RC"

# ---------------------------------------------------------------------------
section "check-github-labels.sh — offline invariants"
CHK="$REPO_ROOT/scripts/check-github-labels.sh"
rc=0; out="$(bash "$CHK" "$REPO_ROOT" 2>&1)" || rc=$?
judge "the real tree passes"                        0   "$rc"
judge "  and says so"                               yes "$(has "$out" "GitHub label set check passed")"

# plant <jq-filter> <label> <needle> — a mutated copy of the tree's label set
# must FAIL with the named error. A check that cannot fail proves nothing.
PLANT="$TMP/plant"
plant() {
  rm -rf "$PLANT"
  mkdir -p "$PLANT/config/github" "$PLANT/core/schemas" "$PLANT/core/capabilities" "$PLANT/.github/ISSUE_TEMPLATE"
  cp "$REPO_ROOT/core/schemas/github-labels.json" "$PLANT/core/schemas/"
  cp "$REGISTRY" "$PLANT/core/capabilities/"
  jq "$1" "$LABELS_FILE" >"$PLANT/config/github/labels.json"
  local prc=0 pout
  pout="$(bash "$CHK" "$PLANT" 2>&1)" || prc=$?
  judge "planted: $2 fails"                         1   "$prc"
  judge "  naming the defect"                       yes "$(has "$pout" "$3")"
}
plant '.labels += [{name: "Bug", color: "000000", description: "dup", origin: "tamirs", _comment: "x"}]' \
      "a name that collides case-insensitively" "collide case-insensitively"
plant '(.labels[] | select(.name == "chore") | .color) = "#fef2c0"' \
      "a colour with a leading #" "not six lowercase hex digits"
plant '(.labels[] | select(.name == "chore") | ._comment) = ""' \
      "a non-default label with no reason" "carries no _comment"
plant '.labels += [{name: "agent:claude", color: "c5def5", description: "x", origin: "tamirs", _comment: "x"}]' \
      "a hardcoded agent:<platform> label" "hardcodes a platform"
plant 'del(.labels[] | select(.name == "wontfix"))' \
      "a missing GitHub default" "GitHub default label 'wontfix' is missing"
plant '(.labels[] | select(.name == "bug") | .origin) = "tamirs" | (.labels[] | select(.name == "bug") | ._comment) = "x"' \
      "a default re-marked as ours" "GitHub default label 'bug' is missing"
plant '(.labels[] | select(.name == "chore") | .description) = ("x" * 101)' \
      "a description over 100 characters" "longer than 100 characters"
if python3 -c 'import yaml' 2>/dev/null; then
  rm -rf "$PLANT"
  mkdir -p "$PLANT/config/github" "$PLANT/core/schemas" "$PLANT/core/capabilities" "$PLANT/.github/ISSUE_TEMPLATE"
  cp "$LABELS_FILE" "$PLANT/config/github/"
  cp "$REPO_ROOT/core/schemas/github-labels.json" "$PLANT/core/schemas/"
  cp "$REGISTRY" "$PLANT/core/capabilities/"
  printf 'name: Feature\ndescription: x\nlabels: [feature]\nbody: []\n' >"$PLANT/.github/ISSUE_TEMPLATE/feature.yml"
  printf 'version: 2\nupdates:\n  - package-ecosystem: npm\n    directory: /\n    schedule: {interval: weekly}\n    labels:\n      - chore\n      - typo-label\n' >"$PLANT/.github/dependabot.yml"
  prc=0; pout="$(bash "$CHK" "$PLANT" 2>&1)" || prc=$?
  judge "planted: a template naming a label the set lacks fails" 1 "$prc"
  judge "  the template is named"                   yes "$(has "$pout" "feature.yml labels with 'feature'")"
  judge "  and so is the dependabot label"          yes "$(has "$pout" "dependabot.yml labels with 'typo-label'")"
  judge "  while chore, which the set provides, is not reported" no "$(has "$pout" "with 'chore'")"
  printf 'name: Agent\ndescription: x\nlabels:\n  - agent:%s\nbody: []\n' "$(printf '%s\n' "$PLATFORMS" | head -1)" >"$PLANT/.github/ISSUE_TEMPLATE/feature.yml"
  rm -f "$PLANT/.github/dependabot.yml"
  prc=0; pout="$(bash "$CHK" "$PLANT" 2>&1)" || prc=$?
  judge "a template naming a registry-derived agent label passes" 0 "$prc"
else
  skip "planted template/dependabot label checks" "PyYAML not importable"
fi

harness_summary
