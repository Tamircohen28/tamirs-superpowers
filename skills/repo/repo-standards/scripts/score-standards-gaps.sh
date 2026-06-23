#!/usr/bin/env bash
# score-standards-gaps.sh — P1/P2/P3 gaps from standards-inventory JSON.
#
# Usage: standards-inventory.sh <root> | score-standards-gaps.sh
set -euo pipefail

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
rv=$(echo "$INV" | jq -r '.branch_governance.required_approving_reviews')
h_mis=$(echo "$INV" | jq -r '.hygiene.misplaced_top_level_docs')
h_ticket=$(echo "$INV" | jq -r '.hygiene.ticket_named_outside_engineering')
h_empty=$(echo "$INV" | jq -r '.hygiene.empty_dirs')
h_self=$(echo "$INV" | jq -r '.hygiene.self_hosted_ci')

[[ "$r_exists" != true ]] && { add_gap "S1-01" "P1" "README.md missing" 1; inc P1; }
[[ "$r_exists" == true && "$r_badges" != true ]] && { add_gap "S1-02" "P2" "README missing CI/license badges" 1; inc P2; }
[[ "$r_prereq" != true ]] && { add_gap "S1-03" "P2" "README missing Prerequisites section" 1; inc P2; }
[[ "$r_qs" != true ]] && { add_gap "S1-04" "P2" "README missing Quick Start section" 1; inc P2; }
[[ "$d_user" != true ]] && { add_gap "S2-01" "P2" "docs/user/ missing" 2; inc P2; }
[[ "$d_eng" != true ]] && { add_gap "S2-02" "P2" "docs/engineering/ missing" 2; inc P2; }
[[ "$d_cl" != true ]] && { add_gap "S2-03" "P2" "docs/CHANGELOG.md missing" 2; inc P2; }
[[ "$d_contrib" != true ]] && { add_gap "S2-04" "P2" "docs/CONTRIBUTING.md missing" 2; inc P2; }
[[ "$g_ci" != true ]] && { add_gap "S3-01" "P1" "No .github/workflows CI" 3; inc P1; }
[[ "$g_secret" != true ]] && { add_gap "S3-02" "P2" "CI missing secret-scan job" 3; inc P2; }
[[ "$g_pr" != true ]] && { add_gap "S3-03" "P2" "Missing .github/pull_request_template.md" 3; inc P2; }
[[ "$g_dep" != true ]] && { add_gap "S3-04" "P3" "Missing dependabot.yml" 3; inc P3; }
[[ "$lic" != true ]] && { add_gap "S5-01" "P1" "LICENSE missing" 1; inc P1; }
[[ "$gi" != true ]] && { add_gap "S5-02" "P2" ".gitignore missing" 1; inc P2; }
[[ "$co" != true ]] && { add_gap "S4-01" "P2" "CODEOWNERS missing" 4; inc P2; }
[[ "$bp" != true ]] && { add_gap "S4-02" "P2" "Branch protection not configured" 4; inc P2; }
[[ "$bp" == true && "$rv" -lt 1 ]] && { add_gap "S4-03" "P2" "Branch protection requires at least 1 approving review" 4; inc P2; }
(( h_mis > 0 )) && { add_gap "S6-01" "P1" "docs/*.md files outside docs/README.md at docs root" 0; inc P1; }
(( h_ticket > 0 )) && { add_gap "S6-02" "P2" "Ticket-named markdown outside docs/engineering/" 0; inc P2; }
(( h_empty > 5 )) && { add_gap "S6-03" "P3" "Many empty directories ($h_empty)" 0; inc P3; }
[[ "$h_self" == true ]] && { add_gap "S6-04" "P1" "Self-hosted CI runner in workflows" 3; inc P1; }

GAPS_JSON="["
for i in "${!GAPS[@]}"; do
  [[ $i -gt 0 ]] && GAPS_JSON+=","
  GAPS_JSON+="${GAPS[$i]}"
done
GAPS_JSON+="]"

jq -nc --argjson gaps "$GAPS_JSON" --argjson p1 "$P1" --argjson p2 "$P2" --argjson p3 "$P3" \
  '{gaps: $gaps, counts: {p1: $p1, p2: $p2, p3: $p3}}'
