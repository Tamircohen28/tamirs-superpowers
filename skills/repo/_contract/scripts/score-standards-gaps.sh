#!/usr/bin/env bash
# score-standards-gaps.sh — P1/P2/P3 gaps from standards-inventory JSON.
#
# Usage: standards-inventory.sh <root> | score-standards-gaps.sh [profile]
#
# WHY SOME CHECKS ARE CONDITIONAL
#   Most of this file asserted the same things against every repository: 13
#   mandatory docs files, README badges for a CI/LICENSE/release model that may
#   not exist, a root CHANGELOG and a versioning doc for a repo that never
#   tags, a Makefile install/update/uninstall lifecycle for a repo nobody
#   installs. On a one-file CLI or an internal experiment those are not defects,
#   they are rot waiting to happen, and a scorer that reports them trains people
#   to ignore it.
#
#   standards-contract.json already had exactly one key that got this right:
#   `require_capability_registry_when_multi`. The `_when_<fact>` suffix is the
#   pattern — the check applies only when an OBSERVABLE fact about the repo says
#   it should. This file now reads those keys from the contract and derives the
#   facts from the inventory it was handed. The facts:
#
#     has_ci          .github/ CI workflow present
#     release_model   a semver tag exists, or a plugin manifest declares a version
#     published       release_model, or `make install` exists, or a
#                     non-private package.json — i.e. somebody other than the
#                     author is meant to get this
#     multi_target    the repo targets >= 2 AI harnesses
#
#   A check whose `_when_*` key is absent from the contract stays unconditional,
#   so a vendored or older contract keeps today's behaviour.
set -euo pipefail

PROFILE="${1:-app-gold}"
CONTRACT_FILE="${CONTRACT_FILE:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/standards-contract.json}"

# contract_flag <dotted.path> — the contract's boolean, or "" when the key is
# absent. Absent means "not tiered", which means the check stays unconditional.
contract_flag() {
  [[ -f "$CONTRACT_FILE" ]] || return 0
  jq -r --arg p "$PROFILE" --arg k "$1" \
    '(.profiles[$p] | getpath($k | split("."))) // empty' "$CONTRACT_FILE" 2>/dev/null || true
}

INV="$(cat)"
add_gap() {
  GAPS+=("$(jq -nc --arg id "$1" --arg sev "$2" --arg msg "$3" --argjson phase "$4" \
    '{id: $id, severity: $sev, message: $msg, phase: $phase}')")
}

GAPS=()
P1=0 P2=0 P3=0
inc() { case "$1" in P1) P1=$((P1+1));; P2) P2=$((P2+1));; P3) P3=$((P3+1));; esac; }

r_exists=$(echo "$INV" | jq -r '.readme.exists')
r_badges=$(echo "$INV" | jq -r '.readme.has_badges')
r_prereq=$(echo "$INV" | jq -r '.readme.has_prerequisites')
r_qs=$(echo "$INV" | jq -r '.readme.has_quick_start')
r_lic=$(echo "$INV" | jq -r '.readme.has_license_line')
r_banner=$(echo "$INV" | jq -r '.readme.has_banner')
r_author=$(echo "$INV" | jq -r '.readme.has_author_badge')
r_version_badge=$(echo "$INV" | jq -r '.readme.has_version_badge')
r_ai_targets=$(echo "$INV" | jq -r '.readme.has_ai_targets')
r_multi_install=$(echo "$INV" | jq -r '.readme.has_multi_install')
# README branding facts (S1-11..S1-14). Every one of these defaults to a value
# that scores NO gap when the fact is absent from the inventory: an older
# inventory, a vendored copy, or a machine without python3 must stay silent
# rather than invent a defect it never measured.
r_anchor_bad=$(echo "$INV" | jq -r '.readme.branding.anchor_form.multiline_img_anchors // 0')
r_header_emoji=$(echo "$INV" | jq -r '.readme.branding.header_emoji.count // 0')
# NOTE ON `//`: jq's alternative operator treats `false` as empty, so
# `.pass // true` turns a real `false` into `true` and silently disables the
# check. Every boolean below is read with an explicit `== true` test instead.
r_badge_ver_checked=$(echo "$INV" | jq -r '(.readme.branding.badge_versions.checked == true)')
r_badge_ver_bad=$(echo "$INV" | jq -r '(.readme.branding.badge_versions.mismatches // []) | length')
r_badge_ver_detail=$(echo "$INV" | jq -r '[(.readme.branding.badge_versions.mismatches // [])[] | "\(.target) badge says \(.readme), platform-targets.json says \(.platform_targets)"] | join("; ")')
r_banner_checked=$(echo "$INV" | jq -r '(.readme.branding.banner.checked == true)')
r_banner_pass=$(echo "$INV" | jq -r 'if (.readme.branding.banner.pass == false) then false else true end')
r_banner_why=$(echo "$INV" | jq -r '(.readme.branding.banner.reasons // []) | join("; ")')
mf_install=$(echo "$INV" | jq -r '.makefile.install')
mf_update=$(echo "$INV" | jq -r '.makefile.update')
mf_uninstall=$(echo "$INV" | jq -r '.makefile.uninstall')
ai_count=$(echo "$INV" | jq -r '.ai_platforms.count')
root_cl=$(echo "$INV" | jq -r '.versioning.root_changelog')
ver_doc=$(echo "$INV" | jq -r '.versioning.versioning_doc')
cl_unrel=$(echo "$INV" | jq -r '.versioning.changelog_unreleased')
agents_ver=$(echo "$INV" | jq -r '.versioning.agents_references_versioning')
manifest_match=$(echo "$INV" | jq -r '.versioning.manifest_versions_match')
manifest_count=$(echo "$INV" | jq -r '.versioning.manifest_count')
manifest_tag_match=$(echo "$INV" | jq -r '.versioning.manifest_version_tag_match')
release_tags_exist=$(echo "$INV" | jq -r '.versioning.release_tags_exist')
agents_root=$(echo "$INV" | jq -r '.root_files.agents_md')
d_user=$(echo "$INV" | jq -r '.docs.user_dir')
d_eng=$(echo "$INV" | jq -r '.docs.engineering_dir')
d_cl=$(echo "$INV" | jq -r '.docs.changelog')
d_contrib=$(echo "$INV" | jq -r '.docs.contributing')
g_ci=$(echo "$INV" | jq -r '.github.ci_workflow')
g_secret=$(echo "$INV" | jq -r '.github.secret_scan_job')
g_pr=$(echo "$INV" | jq -r '.github.pr_template')
g_dep=$(echo "$INV" | jq -r '.github.dependabot')
lic=$(echo "$INV" | jq -r '.root_files.license')
co=$(echo "$INV" | jq -r '.root_files.codeowners')
gi=$(echo "$INV" | jq -r '.root_files.gitignore')
bp=$(echo "$INV" | jq -r '.branch_governance.protection_enabled')
ci_check=$(echo "$INV" | jq -r '.branch_governance.requires_ci_check')
auto_merge=$(echo "$INV" | jq -r '.branch_governance.allow_auto_merge')
delete_branch=$(echo "$INV" | jq -r '.branch_governance.delete_branch_on_merge')
gh_readable=$(echo "$INV" | jq -r '.branch_governance.readable // false')
rs_safety=$(echo "$INV" | jq -r '.branch_governance.rulesets.safety_active // false')
rs_pr_ci=$(echo "$INV" | jq -r '.branch_governance.rulesets.pr_ci_active // false')
rs_strict=$(echo "$INV" | jq -r '.branch_governance.rulesets.strict_required_status_checks // false')
rs_threads=$(echo "$INV" | jq -r '.branch_governance.rulesets.requires_conversation_resolution // false')
rs_linear=$(echo "$INV" | jq -r '.branch_governance.rulesets.requires_linear_history // false')
rs_force=$(echo "$INV" | jq -r '.branch_governance.rulesets.blocks_force_push // false')
rs_delete=$(echo "$INV" | jq -r '.branch_governance.rulesets.blocks_deletion // false')
act_checked=$(echo "$INV" | jq -r '.branch_governance.actions.checked // false')
act_bad=$(echo "$INV" | jq -r '.branch_governance.actions.violations // 0')
h_mis=$(echo "$INV" | jq -r '.hygiene.misplaced_top_level_docs')
h_ticket=$(echo "$INV" | jq -r '.hygiene.ticket_named_outside_engineering')
h_empty=$(echo "$INV" | jq -r '.hygiene.empty_dirs')
h_self=$(echo "$INV" | jq -r '.hygiene.self_hosted_ci')
h_root_sh=$(echo "$INV" | jq -r '.hygiene.root_shell_scripts')

# --- derived repo-shape facts ----------------------------------------------
has_ci="$g_ci"

release_model=false
if [[ "$release_tags_exist" == true ]] || (( manifest_count >= 1 )); then
  release_model=true
fi

published=false
if [[ "$release_model" == true || "$mf_install" == true ]]; then
  published=true
fi

multi_target=false
(( ai_count >= 2 )) && multi_target=true

# applies <contract-key> <fact> — true when the check should be scored.
# An absent contract key leaves the check unconditional.
applies() {
  local flag; flag="$(contract_flag "$1")"
  [[ "$flag" == "true" ]] || return 0     # not tiered -> always applies
  [[ "$2" == true ]]
}

[[ "$r_exists" != true ]] && { add_gap "S1-01" "P1" "README.md missing" 1; inc P1; }
badgeable=false
[[ "$has_ci" == true || "$lic" == true ]] && badgeable=true
if [[ "$r_exists" == true && "$r_badges" != true ]] && applies "readme.require_ci_badge_when_ci" "$badgeable"; then
  add_gap "S1-02" "P2" "README missing CI/license badges" 1; inc P2
fi
[[ "$r_exists" == true && "$r_banner" != true ]] && { add_gap "S1-05" "P2" "README missing hero banner (add assets/banner.png|jpg|webp|svg and reference it — see skills/repo/_contract/references/readme-banner.md)" 1; inc P2; }
[[ "$r_exists" == true && "$r_author" != true ]] && { add_gap "S1-06" "P2" "README missing author badge (link to GitHub profile)" 1; inc P2; }
if [[ "$r_exists" == true && "$r_version_badge" != true ]] && applies "readme.require_version_badge_when_release_model" "$release_model"; then
  add_gap "S1-07" "P2" "README missing version badge" 1; inc P2
fi
if [[ "$mf_install" != true || "$mf_update" != true || "$mf_uninstall" != true ]] \
   && applies "readme.require_makefile_lifecycle_when_published" "$published"; then
  add_gap "S1-08" "P2" "Makefile must define install, update, and uninstall targets" 1; inc P2
fi
if (( ai_count >= 2 )); then
  [[ "$r_ai_targets" != true ]] && { add_gap "S1-09" "P2" "Multi-platform repo: README missing AI-target badges row" 1; inc P2; }
  [[ "$r_multi_install" != true ]] && { add_gap "S1-10" "P2" "Multi-platform repo: README missing per-target Quick Start subsections" 1; inc P2; }
fi
# --- S1-11..S1-14: README branding ------------------------------------------
# All four are defects the badge/banner rubric asked for and nothing measured.
# See skills/repo/_contract/scripts/check-readme-branding.sh for why each one is
# a rendering/truth fact rather than a style preference.
if [[ "$r_exists" == true ]] && (( r_anchor_bad > 0 )); then
  add_gap "S1-11" "P2" "README wraps a badge <img> in a multi-line <a> ($r_anchor_bad occurrence(s)) — the newline inside the anchor renders as an underlined gap between badges; use <a href=\"...\"><img ... /></a> on one line" 1; inc P2
fi
if [[ "$r_exists" == true ]] && (( r_header_emoji > 0 )); then
  add_gap "S1-12" "P2" "README header contains $r_header_emoji emoji character(s) above the first '## ' heading — the title area and badge rows carry no emoji" 1; inc P2
fi
if [[ "$r_badge_ver_checked" == true ]] && (( r_badge_ver_bad > 0 )) \
   && applies "readme.require_badge_versions_match_platform_targets_when_multi" "$multi_target"; then
  add_gap "S1-13" "P2" "AI-target badge version(s) disagree with platform-targets.json validated_against: $r_badge_ver_detail" 1; inc P2
fi
if [[ "$r_banner_checked" == true && "$r_banner_pass" != true ]]; then
  add_gap "S1-14" "P2" "README banner is not a designed graphic: $r_banner_why (see skills/repo/_contract/references/readme-banner.md)" 1; inc P2
fi
[[ "$r_prereq" != true ]] && { add_gap "S1-03" "P2" "README missing Prerequisites section" 1; inc P2; }
[[ "$r_qs" != true ]] && { add_gap "S1-04" "P2" "README missing Quick Start section" 1; inc P2; }
if applies "docs.require_docs_tree_when_published" "$published"; then
  [[ "$d_user" != true ]] && { add_gap "S2-01" "P2" "docs/user/ missing" 2; inc P2; }
  [[ "$d_eng" != true ]] && { add_gap "S2-02" "P2" "docs/engineering/ missing" 2; inc P2; }
  [[ "$d_cl" != true ]] && { add_gap "S2-03" "P2" "docs/CHANGELOG.md missing" 2; inc P2; }
  [[ "$d_contrib" != true ]] && { add_gap "S2-04" "P2" "docs/CONTRIBUTING.md missing" 2; inc P2; }
fi
[[ "$g_ci" != true ]] && { add_gap "S3-01" "P1" "No .github/workflows CI" 3; inc P1; }
if [[ "$g_secret" != true ]] && applies "ci.require_ci_jobs_when_ci" "$has_ci"; then
  add_gap "S3-02" "P2" "CI missing secret-scan job" 3; inc P2
fi
[[ "$g_pr" != true ]] && { add_gap "S3-03" "P2" "Missing .github/pull_request_template.md" 3; inc P2; }
[[ "$g_dep" != true ]] && { add_gap "S3-04" "P3" "Missing dependabot.yml" 3; inc P3; }
if [[ "$lic" != true ]] && applies "paths.require_license_when_published" "$published"; then
  add_gap "S5-01" "P1" "LICENSE missing" 1; inc P1
fi
[[ "$gi" != true ]] && { add_gap "S5-02" "P2" ".gitignore missing" 1; inc P2; }
if [[ "$root_cl" != true ]] && applies "readme.require_root_changelog_when_release_model" "$release_model"; then
  add_gap "S5-03" "P2" "Root CHANGELOG.md missing" 1; inc P2
fi
[[ "$agents_root" != true ]] && { add_gap "S5-04" "P1" "AGENTS.md missing at repo root" 1; inc P1; }
[[ "$d_cl" == true && "$cl_unrel" != true ]] && { add_gap "S10-01" "P2" "docs/CHANGELOG.md missing [Unreleased] section" 2; inc P2; }
if [[ "$ver_doc" != true ]] && applies "readme.require_versioning_doc_when_release_model" "$release_model"; then
  add_gap "S10-02" "P2" "docs/engineering/build-and-release/versioning.md missing" 2; inc P2
fi
[[ "$agents_root" == true && "$agents_ver" != true ]] && { add_gap "S10-03" "P3" "AGENTS.md should reference versioning/changelog policy" 1; inc P3; }
(( manifest_count >= 2 )) && [[ "$manifest_match" != true ]] && { add_gap "S10-04" "P1" "Plugin manifest versions drift (.claude/.cursor/.codex plugin.json)" 1; inc P1; }
if [[ "${CONTRACT_MANIFESTS_ONLY:-}" != "1" ]]; then
  (( manifest_count >= 1 )) && [[ "$release_tags_exist" == true && "$manifest_tag_match" != true ]] && { add_gap "S10-05" "P1" "plugin.json version has no matching release tag (manifest ahead of/behind last release)" 1; inc P1; }
fi
[[ "$co" != true ]] && { add_gap "S4-01" "P2" "CODEOWNERS missing" 4; inc P2; }
# --- S4: branch governance -------------------------------------------------
# Every check below needs the GitHub API, so all of them sit behind
# CONTRACT_OFFLINE and behind `readable` — a repo whose governance could not be
# read scores no gap at all. Silence about an unread control is honest; a gap
# invented from a failed read is the defect this family used to have.
#
# Rulesets are authoritative. The absence of classic `branches/*/protection` is
# NOT a gap — it is the normal, healthy state of a rulesets-governed repo, and
# scoring it was why S4-02/03/06 fired against this very repository. Classic
# protection is carried in the inventory as `legacy_classic_protection` and
# reported as a migration item, never as a failure.
#
# S4-03 (">= 1 approving review") is RETIRED, not moved. It contradicted the
# canonical policy and the live repository, which deliberately run 0 required
# approvals with thread resolution ON — the solo-contributor posture. The
# approving-review count is policy content owned by
# config/github/repository-policy.json; github-policy.sh reports drift in it.
# Nothing here re-decides it.
if [[ "${CONTRACT_OFFLINE:-}" != "1" && "$gh_readable" == true ]]; then
  [[ "$bp" != true ]] && { add_gap "S4-02" "P2" "Default branch has no governance — no active branch ruleset and no classic protection" 4; inc P2; }
  [[ "$bp" == true && "$ci_check" != true ]] && { add_gap "S4-06" "P2" "No required status check gates a merge to the default branch" 4; inc P2; }
  # S4-04 (allow_auto_merge) is RETIRED, for the same reason S4-03 was: it
  # scored a TEAM-NORM PREFERENCE as a defect. Nothing observable separates a
  # repo that deliberately keeps auto-merge off from one that forgot to turn it
  # on, so no honest gap can be emitted. The preference is resolved per repo at
  # delivery time by pr-dev (resolve-merge-policy.sh), where it belongs.
  # `allow_auto_merge` is still carried in the inventory for reporting.
  [[ "$delete_branch" != true ]] && { add_gap "S4-05" "P3" "delete_branch_on_merge not enabled" 4; inc P3; }
  [[ "$rs_safety" != true ]] && { add_gap "S4-07" "P2" "Canonical safety ruleset (repository-policy.json key 'safety') is absent or not active on the default branch" 4; inc P2; }
  [[ "$rs_pr_ci" != true ]] && { add_gap "S4-08" "P2" "Canonical PR/CI ruleset (repository-policy.json key 'pr_ci') is absent or not active on the default branch" 4; inc P2; }
  # The one that must never silently flip: with strict on, every merge marks
  # every other open branch out of date, and the objective -> DAG -> workers ->
  # ONE PR flow stalls behind a serial rebase queue.
  [[ "$rs_strict" == true ]] && { add_gap "S4-09" "P1" "strict_required_status_checks_policy is TRUE on the default branch — it must be false" 4; inc P1; }
  [[ "$rs_threads" != true ]] && { add_gap "S4-10" "P2" "Review-thread resolution is not required before merge" 4; inc P2; }
  [[ "$rs_linear" != true ]] && { add_gap "S4-11" "P2" "Linear history is not required on the default branch" 4; inc P2; }
  [[ "$rs_force" != true ]] && { add_gap "S4-12" "P1" "Force pushes to the default branch are not blocked" 4; inc P1; }
  [[ "$rs_delete" != true ]] && { add_gap "S4-13" "P1" "Deletion of the default branch is not blocked" 4; inc P1; }
  # Concurrency is classified by github-policy.sh from the workflow-classification
  # table in the canonical policy: cancellable PR validation must carry the block,
  # a stateful workflow must NOT have cancellation on. Both directions are counted.
  [[ "$act_checked" == true && "$act_bad" -gt 0 ]] && { add_gap "S4-14" "P2" "Actions concurrency misconfigured on $act_bad workflow(s) — run: bash scripts/github-policy.sh audit" 4; inc P2; }
fi
(( h_mis > 0 )) && { add_gap "S6-01" "P1" "docs/*.md files outside docs/README.md at docs root" 0; inc P1; }
(( h_ticket > 0 )) && { add_gap "S6-02" "P2" "Ticket-named markdown outside docs/engineering/" 0; inc P2; }
(( h_empty > 5 )) && { add_gap "S6-03" "P3" "Many empty directories ($h_empty)" 0; inc P3; }
[[ "$h_self" == true ]] && { add_gap "S6-04" "P1" "Self-hosted CI runner in workflows" 3; inc P1; }
(( h_root_sh > 0 )) && { add_gap "S6-05" "P2" "Shell scripts at repo root ($h_root_sh) — move to scripts/" 0; inc P2; }

GAPS_JSON="["
for i in "${!GAPS[@]}"; do
  [[ $i -gt 0 ]] && GAPS_JSON+=","
  GAPS_JSON+="${GAPS[$i]}"
done
GAPS_JSON+="]"

jq -nc --argjson gaps "$GAPS_JSON" --argjson p1 "$P1" --argjson p2 "$P2" --argjson p3 "$P3" \
  '{gaps: $gaps, counts: {p1: $p1, p2: $p2, p3: $p3}}'
