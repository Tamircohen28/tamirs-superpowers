#!/usr/bin/env bash
# standards-inventory.sh — JSON snapshot of Tamir repo standards compliance.
#
# Usage: standards-inventory.sh <repo-root>
set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd || { echo '{"error":"not a directory"}'; exit 0; })"

exists() { [[ -f "$1" ]] && echo true || echo false; }

readme_exists=$(exists "$ROOT/README.md")
readme_has_badges=false
readme_has_prereq=false
readme_has_quickstart=false
readme_has_license_line=false
if [[ -f "$ROOT/README.md" ]]; then
  grep -q 'img.shields.io\|badge' "$ROOT/README.md" 2>/dev/null && readme_has_badges=true
  grep -qi 'prerequisite' "$ROOT/README.md" 2>/dev/null && readme_has_prereq=true
  grep -qi 'quick start\|getting started' "$ROOT/README.md" 2>/dev/null && readme_has_quickstart=true
  grep -qi 'license' "$ROOT/README.md" 2>/dev/null && readme_has_license_line=true
fi

docs_readme=$(exists "$ROOT/docs/README.md")
changelog=$(exists "$ROOT/docs/CHANGELOG.md")
contributing=$(exists "$ROOT/docs/CONTRIBUTING.md")
user_docs=false
eng_docs=false
[[ -d "$ROOT/docs/user" ]] && user_docs=true
[[ -d "$ROOT/docs/engineering" ]] && eng_docs=true

ci_workflow=false
secret_scan_job=false
pr_template=false
dependabot=false
if [[ -d "$ROOT/.github/workflows" ]]; then
  find "$ROOT/.github/workflows" -name '*.yml' -o -name '*.yaml' 2>/dev/null | grep -q . && ci_workflow=true
  while IFS= read -r wf; do
    [[ -f "$wf" ]] || continue
    if grep -Eiq '^[[:space:]]{2}[a-zA-Z0-9_-]*(secret[-_]?scan|scan[-_]?secret)' "$wf" 2>/dev/null; then
      secret_scan_job=true
      break
    fi
    if grep -Eiq 'gitleaks|trufflehog|detect-secrets' "$wf" 2>/dev/null; then
      secret_scan_job=true
      break
    fi
  done < <(find "$ROOT/.github/workflows" \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
fi
[[ -f "$ROOT/.github/pull_request_template.md" ]] && pr_template=true
[[ -f "$ROOT/.github/dependabot.yml" ]] && dependabot=true

license_file=$(exists "$ROOT/LICENSE")
codeowners=$(exists "$ROOT/CODEOWNERS")
gitignore=$(exists "$ROOT/.gitignore")
claude_md=$(exists "$ROOT/CLAUDE.md")
agents_md=$(exists "$ROOT/AGENTS.md")

branch_protection=false
required_reviews=0
if command -v gh &>/dev/null && git -C "$ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
  remote_url=$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)
  if [[ "$remote_url" =~ github.com[:/]([^/]+)/([^/.]+) ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]%.git}"
    default_branch=$(git -C "$ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo master)
    prot=$(gh api "repos/$owner/$repo/branches/$default_branch/protection" 2>/dev/null || true)
    if [[ -n "$prot" ]]; then
      branch_protection=true
      required_reviews=$(echo "$prot" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')
    fi
  fi
fi

hygiene=$(bash "$(dirname "$0")/check-repo-hygiene.sh" "$ROOT")

jq -nc \
  --arg root "$ROOT" \
  --argjson readme_exists "$readme_exists" \
  --argjson readme_has_badges "$readme_has_badges" \
  --argjson readme_has_prereq "$readme_has_prereq" \
  --argjson readme_has_quickstart "$readme_has_quickstart" \
  --argjson readme_has_license_line "$readme_has_license_line" \
  --argjson docs_readme "$docs_readme" \
  --argjson changelog "$changelog" \
  --argjson contributing "$contributing" \
  --argjson user_docs "$user_docs" \
  --argjson eng_docs "$eng_docs" \
  --argjson ci_workflow "$ci_workflow" \
  --argjson secret_scan_job "$secret_scan_job" \
  --argjson pr_template "$pr_template" \
  --argjson dependabot "$dependabot" \
  --argjson license_file "$license_file" \
  --argjson codeowners "$codeowners" \
  --argjson gitignore "$gitignore" \
  --argjson claude_md "$claude_md" \
  --argjson agents_md "$agents_md" \
  --argjson branch_protection "$branch_protection" \
  --argjson required_reviews "$required_reviews" \
  --argjson hygiene "$hygiene" \
  '{
    root: $root,
    readme: {
      exists: $readme_exists,
      has_badges: $readme_has_badges,
      has_prerequisites: $readme_has_prereq,
      has_quick_start: $readme_has_quickstart,
      has_license_line: $readme_has_license_line
    },
    docs: {
      readme: $docs_readme,
      changelog: $changelog,
      contributing: $contributing,
      user_dir: $user_docs,
      engineering_dir: $eng_docs
    },
    github: {
      ci_workflow: $ci_workflow,
      secret_scan_job: $secret_scan_job,
      pr_template: $pr_template,
      dependabot: $dependabot
    },
    root_files: {
      license: $license_file,
      codeowners: $codeowners,
      gitignore: $gitignore,
      claude_md: $claude_md,
      agents_md: $agents_md
    },
    branch_governance: {
      protection_enabled: $branch_protection,
      required_approving_reviews: $required_reviews
    },
    hygiene: $hygiene.hygiene
  }'
