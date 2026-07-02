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
readme_has_banner=false
readme_has_author_badge=false
readme_has_version_badge=false
readme_has_ai_targets=false
readme_has_multi_install=false
if [[ -f "$ROOT/README.md" ]]; then
  grep -q 'img.shields.io\|badge' "$ROOT/README.md" 2>/dev/null && readme_has_badges=true
  grep -qi 'prerequisite' "$ROOT/README.md" 2>/dev/null && readme_has_prereq=true
  grep -qi 'quick start\|getting started' "$ROOT/README.md" 2>/dev/null && readme_has_quickstart=true
  grep -qi 'license' "$ROOT/README.md" 2>/dev/null && readme_has_license_line=true
  if grep -qiE 'author|Tamircohen28|github\.com/[^/]+)\]' "$ROOT/README.md" 2>/dev/null; then
    readme_has_author_badge=true
  fi
  if grep -qiE 'version-|badge/version|version-[0-9]' "$ROOT/README.md" 2>/dev/null; then
    readme_has_version_badge=true
  fi
  if grep -qiE 'Claude Code|Cursor|Codex' "$ROOT/README.md" 2>/dev/null \
    && grep -qiE 'AI target|badge.*Claude|badge.*Cursor|badge.*Codex' "$ROOT/README.md" 2>/dev/null; then
    readme_has_ai_targets=true
  fi
  # Banner: README references assets/banner.* OR the asset file itself exists
  if grep -qiE 'assets/banner\.(svg|png|jpg|webp)' "$ROOT/README.md" 2>/dev/null; then
    readme_has_banner=true
  else
    for _ext in svg png jpg webp; do
      [[ -f "$ROOT/assets/banner.$_ext" ]] && { readme_has_banner=true; break; }
    done
  fi
  # Multi-target install: Claude + Cursor and/or Codex headings under Quick Start
  claude_qs=false
  cursor_qs=false
  codex_qs=false
  grep -qiE '### Claude|## Claude|Claude Code' "$ROOT/README.md" 2>/dev/null && claude_qs=true
  grep -qiE '### Cursor|## Cursor' "$ROOT/README.md" 2>/dev/null && cursor_qs=true
  grep -qiE '### Codex|## Codex' "$ROOT/README.md" 2>/dev/null && codex_qs=true
  platform_docs=0
  [[ "$claude_qs" == true ]] && platform_docs=$((platform_docs + 1))
  [[ "$cursor_qs" == true ]] && platform_docs=$((platform_docs + 1))
  [[ "$codex_qs" == true ]] && platform_docs=$((platform_docs + 1))
  if (( platform_docs >= 2 )); then
    readme_has_multi_install=true
  fi
fi

root_changelog=$(exists "$ROOT/CHANGELOG.md")
versioning_doc=$(exists "$ROOT/docs/engineering/build-and-release/versioning.md")
changelog_unreleased=false
if [[ -f "$ROOT/docs/CHANGELOG.md" ]]; then
  grep -q '\[Unreleased\]' "$ROOT/docs/CHANGELOG.md" 2>/dev/null && changelog_unreleased=true
fi
agents_references_versioning=false
if [[ -f "$ROOT/AGENTS.md" ]]; then
  grep -qiE 'versioning|semver|changelog' "$ROOT/AGENTS.md" 2>/dev/null && agents_references_versioning=true
fi

makefile_install=false
makefile_update=false
makefile_uninstall=false
if [[ -f "$ROOT/Makefile" ]]; then
  grep -qE '^install:' "$ROOT/Makefile" 2>/dev/null && makefile_install=true
  grep -qE '^update:' "$ROOT/Makefile" 2>/dev/null && makefile_update=true
  grep -qE '^uninstall:' "$ROOT/Makefile" 2>/dev/null && makefile_uninstall=true
fi

ai_platform_count=0
[[ -f "$ROOT/.claude-plugin/plugin.json" || -f "$ROOT/CLAUDE.md" || -d "$ROOT/.claude/rules" ]] && ai_platform_count=$((ai_platform_count + 1))
[[ -f "$ROOT/.cursor-plugin/plugin.json" || -d "$ROOT/.cursor/rules" || -f "$ROOT/.cursorrules" ]] && ai_platform_count=$((ai_platform_count + 1))
[[ -f "$ROOT/.codex-plugin/plugin.json" || -f "$ROOT/AGENTS.md" ]] && ai_platform_count=$((ai_platform_count + 1))

manifest_versions_match=true
manifest_version=""
for manifest in .claude-plugin/plugin.json .cursor-plugin/plugin.json .codex-plugin/plugin.json; do
  if [[ -f "$ROOT/$manifest" ]] && command -v jq &>/dev/null; then
    v=$(jq -r '.version // empty' "$ROOT/$manifest" 2>/dev/null || true)
    [[ -z "$v" ]] && continue
    if [[ -z "$manifest_version" ]]; then
      manifest_version="$v"
    elif [[ "$v" != "$manifest_version" ]]; then
      manifest_versions_match=false
    fi
  fi
done
manifest_count=0
[[ -f "$ROOT/.claude-plugin/plugin.json" ]] && manifest_count=$((manifest_count + 1))
[[ -f "$ROOT/.cursor-plugin/plugin.json" ]] && manifest_count=$((manifest_count + 1))
[[ -f "$ROOT/.codex-plugin/plugin.json" ]] && manifest_count=$((manifest_count + 1))

# S10-05: declared manifest version must match the latest release tag (no
# unreleased version bumps sitting on main). Only evaluated when the repo
# has at least one manifest and at least one semver-looking tag — a repo
# that hasn't cut its first release yet can't drift.
manifest_version_tag_match=true
release_tags_exist=false
if (( manifest_count > 0 )) && [[ -n "$manifest_version" ]] && command -v git &>/dev/null; then
  latest_tag_ver=$(cd "$ROOT" && git tag -l 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null \
    | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 || true)
  if [[ -n "$latest_tag_ver" ]]; then
    release_tags_exist=true
    [[ "$latest_tag_ver" != "$manifest_version" ]] && manifest_version_tag_match=false
  fi
fi

docs_readme=$(exists "$ROOT/docs/README.md")
contributing=$(exists "$ROOT/docs/CONTRIBUTING.md")
changelog=$(exists "$ROOT/docs/CHANGELOG.md")
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
requires_ci_check=false
allow_auto_merge=false
delete_branch_on_merge=false
if command -v gh &>/dev/null && git -C "$ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
  remote_url=$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)
  if [[ "$remote_url" =~ github.com[:/]([^/]+)/([^/.]+) ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]%.git}"
    default_branch=$(git -C "$ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo master)
    repo_meta=$(gh api "repos/$owner/$repo" 2>/dev/null || true)
    if [[ -n "$repo_meta" ]]; then
      allow_auto_merge=$(echo "$repo_meta" | jq -r '.allow_auto_merge // false')
      delete_branch_on_merge=$(echo "$repo_meta" | jq -r '.delete_branch_on_merge // false')
    fi
    prot=$(gh api "repos/$owner/$repo/branches/$default_branch/protection" 2>/dev/null || true)
    if [[ -n "$prot" ]]; then
      branch_protection=true
      required_reviews=$(echo "$prot" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')
      if echo "$prot" | jq -e '(.required_status_checks.contexts // []) | index("CI") != null' >/dev/null; then
        requires_ci_check=true
      fi
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
  --argjson readme_has_banner "$readme_has_banner" \
  --argjson readme_has_author_badge "$readme_has_author_badge" \
  --argjson readme_has_version_badge "$readme_has_version_badge" \
  --argjson readme_has_ai_targets "$readme_has_ai_targets" \
  --argjson readme_has_multi_install "$readme_has_multi_install" \
  --argjson root_changelog "$root_changelog" \
  --argjson versioning_doc "$versioning_doc" \
  --argjson changelog_unreleased "$changelog_unreleased" \
  --argjson agents_references_versioning "$agents_references_versioning" \
  --argjson makefile_install "$makefile_install" \
  --argjson makefile_update "$makefile_update" \
  --argjson makefile_uninstall "$makefile_uninstall" \
  --argjson ai_platform_count "$ai_platform_count" \
  --argjson manifest_versions_match "$manifest_versions_match" \
  --argjson manifest_count "$manifest_count" \
  --argjson manifest_version_tag_match "$manifest_version_tag_match" \
  --argjson release_tags_exist "$release_tags_exist" \
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
  --argjson requires_ci_check "$requires_ci_check" \
  --argjson allow_auto_merge "$allow_auto_merge" \
  --argjson delete_branch_on_merge "$delete_branch_on_merge" \
  --argjson hygiene "$hygiene" \
  '{
    root: $root,
    readme: {
      exists: $readme_exists,
      has_badges: $readme_has_badges,
      has_prerequisites: $readme_has_prereq,
      has_quick_start: $readme_has_quickstart,
      has_license_line: $readme_has_license_line,
      has_banner: $readme_has_banner,
      has_author_badge: $readme_has_author_badge,
      has_version_badge: $readme_has_version_badge,
      has_ai_targets: $readme_has_ai_targets,
      has_multi_install: $readme_has_multi_install
    },
    makefile: {
      install: $makefile_install,
      update: $makefile_update,
      uninstall: $makefile_uninstall
    },
    versioning: {
      root_changelog: $root_changelog,
      versioning_doc: $versioning_doc,
      changelog_unreleased: $changelog_unreleased,
      agents_references_versioning: $agents_references_versioning,
      manifest_versions_match: $manifest_versions_match,
      manifest_count: $manifest_count,
      manifest_version_tag_match: $manifest_version_tag_match,
      release_tags_exist: $release_tags_exist
    },
    ai_platforms: { count: $ai_platform_count },
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
      required_approving_reviews: $required_reviews,
      requires_ci_check: $requires_ci_check,
      allow_auto_merge: $allow_auto_merge,
      delete_branch_on_merge: $delete_branch_on_merge
    },
    hygiene: $hygiene.hygiene
  }'
