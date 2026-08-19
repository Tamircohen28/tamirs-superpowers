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

# ---------------------------------------------------------------------------
# Branch governance (S4) — rulesets are authoritative, classic protection is legacy
# ---------------------------------------------------------------------------
# Rewritten 2026-08-19. The previous read probed ONLY classic
# `repos/{o}/{r}/branches/{b}/protection`, which returns 404 on a repository that
# is correctly governed by branch rulesets. That made this inventory report the
# plugin's own repo — protected by two active rulesets — as unprotected, and
# score-standards-gaps.sh emitted S4-02/03/06 as gaps against a compliant repo.
#
# Every GitHub read now goes through scripts/lib/github-common.sh, the single gh
# abstraction. Rulesets are the source of truth; classic protection is reported
# separately as a legacy migration item and its ABSENCE IS NEVER A GAP.
#
# Nothing here restates policy content. Ruleset names, the required contexts and
# the rule set itself live in config/github/repository-policy.json and are read
# from it at runtime (_contract/README.md: "If a path or check is not in
# standards-contract.json, it does not belong in either skill's prose" — the same
# rule applies to the policy document).
gh_readable=false
gov_source=unknown
branch_protection=false
required_reviews=0
requires_ci_check=false
allow_auto_merge=false
delete_branch_on_merge=false
classic_protection=unknown
ruleset_safety=false
ruleset_pr_ci=false
strict_status_checks=false
requires_conversation_resolution=false
requires_linear_history=false
blocks_force_push=false
blocks_deletion=false
actions_checked=false
actions_violations=0

# Where the plugin's own tree sits relative to this script. A consumer repo that
# vendored only _contract/scripts has no lib and no policy: that is a degraded
# read, reported as such, never an error and never a gap.
CONTRACT_SRC_ROOT="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd || true)"
GH_LIB="${GITHUB_COMMON_LIB:-${CONTRACT_SRC_ROOT}/scripts/lib/github-common.sh}"
GH_POLICY="${GITHUB_POLICY_FILE:-${CONTRACT_SRC_ROOT}/config/github/repository-policy.json}"
GH_CLI_SCRIPT="${CONTRACT_SRC_ROOT}/scripts/github-policy.sh"

# CONTRACT_OFFLINE=1 means "make no network call at all". The gold fixtures run
# under it, so the probe is skipped outright rather than attempted and filtered
# after the fact — a skipped check must not cost a round trip it will discard.
if [[ "${CONTRACT_OFFLINE:-}" != "1" ]] \
  && [[ -f "$GH_LIB" ]] && [[ -f "$GH_POLICY" ]] \
  && command -v jq &>/dev/null \
  && git -C "$ROOT" rev-parse --is-inside-work-tree &>/dev/null; then

  # shellcheck source=../../../../scripts/lib/github-common.sh
  . "$GH_LIB"
  github_state_trap || true

  remote_url=$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)
  if [[ "$remote_url" =~ github.com[:/]([^/]+)/([^/.]+) ]]; then
    gh_owner="${BASH_REMATCH[1]}"
    gh_name="${BASH_REMATCH[2]%.git}"
    gh_slug="$gh_owner/$gh_name"

    if github_have && [[ "$(github_probe)" == ready ]]; then
      gh_work="$(mktemp -d)"
      trap 'rm -rf "$gh_work"' EXIT

      # --- repository object: merge settings + the real default branch --------
      # Never guessed from a literal: the governed fleet mixes both spellings.
      if repo_meta="$(github_repo_view "$gh_slug" 2>/dev/null)"; then
        gh_readable=true
        allow_auto_merge=$(echo "$repo_meta" | jq -r '.allow_auto_merge // false')
        delete_branch_on_merge=$(echo "$repo_meta" | jq -r '.delete_branch_on_merge // false')
        default_branch=$(echo "$repo_meta" | jq -r '.default_branch // empty')
      fi

      if [[ "$gh_readable" == true ]]; then
        # --- rulesets that actually govern the default branch ----------------
        echo '[]' >"$gh_work/applicable.json"
        if rs_list="$(github_list_rulesets "$gh_slug" 2>/dev/null)"; then
          : >"$gh_work/details.ndjson"
          for rs_id in $(echo "$rs_list" | jq -r '.[] | select(.target == "branch") | .id'); do
            github_get_ruleset "$gh_slug" "$rs_id" 2>/dev/null \
              | jq -c '.' >>"$gh_work/details.ndjson" || true
          done
          jq -s --arg b "$default_branch" '
            map(select(
              (.enforcement == "active")
              and ((.conditions.ref_name.include // [])
                   | any(. == "~ALL" or . == "~DEFAULT_BRANCH" or . == ("refs/heads/" + $b)))
            ))
          ' "$gh_work/details.ndjson" >"$gh_work/applicable.json"
        fi

        rules_of() { jq -r --arg t "$1" 'map((.rules // [])[] | select(.type == $t)) | length' "$gh_work/applicable.json"; }
        (( $(rules_of deletion) > 0 )) && blocks_deletion=true
        (( $(rules_of non_fast_forward) > 0 )) && blocks_force_push=true
        (( $(rules_of required_linear_history) > 0 )) && requires_linear_history=true

        # strict_required_status_checks_policy MUST stay false. It is the "branch
        # must be up to date before merging" toggle, and the objective -> DAG ->
        # workers -> ONE PR architecture depends on it being off: with it on,
        # every merge invalidates every other open branch. Any active ruleset
        # demanding it makes the whole merge gate strict, so ANY wins here.
        if jq -e '
          map((.rules // [])[]
              | select(.type == "required_status_checks")
              | .parameters.strict_required_status_checks_policy // false)
          | any(. == true)
        ' "$gh_work/applicable.json" >/dev/null 2>&1; then
          strict_status_checks=true
        fi

        # Any required status-check context at all. NOT a literal "CI": contexts
        # are per-repo (9 here, out of 15 CI jobs) and must never be globalised.
        if jq -e '
          map((.rules // [])[]
              | select(.type == "required_status_checks")
              | (.parameters.required_status_checks // []) | length)
          | any(. > 0)
        ' "$gh_work/applicable.json" >/dev/null 2>&1; then
          requires_ci_check=true
        fi

        if jq -e '
          map((.rules // [])[]
              | select(.type == "pull_request")
              | .parameters.required_review_thread_resolution // false)
          | any(. == true)
        ' "$gh_work/applicable.json" >/dev/null 2>&1; then
          requires_conversation_resolution=true
        fi

        required_reviews=$(jq -r '
          [ .[] | (.rules // [])[]
                 | select(.type == "pull_request")
                 | .parameters.required_approving_review_count // 0 ] | max // 0
        ' "$gh_work/applicable.json")

        (( $(jq 'length' "$gh_work/applicable.json") > 0 )) && { branch_protection=true; gov_source=rulesets; }

        # --- the two canonical rulesets, by name, read from the policy --------
        while IFS="$(printf '\t')" read -r rs_key rs_name; do
          [[ -n "$rs_key" ]] || continue
          rs_active=false
          if jq -e --arg n "$rs_name" 'any(.name == $n)' "$gh_work/applicable.json" >/dev/null 2>&1; then
            rs_active=true
          fi
          case "$rs_key" in
            safety) ruleset_safety="$rs_active" ;;
            pr_ci)  ruleset_pr_ci="$rs_active" ;;
          esac
        done < <(jq -r '.rulesets[] | .key + "\t" + .name' "$GH_POLICY")

        # --- classic protection: legacy, reported, never the source of truth --
        classic_rc=0
        github_classic_protection "$gh_slug" "$default_branch" >/dev/null 2>&1 || classic_rc=$?
        case "$classic_rc" in
          0) classic_protection=present
             # A repo with no rulesets but with classic protection is protected.
             if [[ "$gov_source" == unknown ]]; then
               gov_source=classic; branch_protection=true
               prot="$(github_classic_protection "$gh_slug" "$default_branch" 2>/dev/null || true)"
               required_reviews=$(echo "$prot" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')
               [[ "$(echo "$prot" | jq -r '(.required_status_checks.contexts // []) | length')" -gt 0 ]] && requires_ci_check=true
               [[ "$(echo "$prot" | jq -r '.required_conversation_resolution.enabled // false')" == true ]] && requires_conversation_resolution=true
               [[ "$(echo "$prot" | jq -r '.required_linear_history.enabled // false')" == true ]] && requires_linear_history=true
               [[ "$(echo "$prot" | jq -r '.allow_force_pushes.enabled // true')" == false ]] && blocks_force_push=true
               [[ "$(echo "$prot" | jq -r '.allow_deletions.enabled // true')" == false ]] && blocks_deletion=true
             fi
             ;;
          2) classic_protection=absent ;;
          *) classic_protection=unknown ;;
        esac
        [[ "$gov_source" == unknown ]] && gov_source=none

        # --- Actions concurrency ---------------------------------------------
        # Delegated to scripts/github-policy.sh, which owns the workflow
        # classification table in config/github/repository-policy.json. Nothing
        # about cancellable-vs-stateful is re-decided here: a second copy of that
        # judgement is exactly the duplicated-rules problem this work removes.
        if [[ -f "$GH_CLI_SCRIPT" ]]; then
          if audit_json="$(bash "$GH_CLI_SCRIPT" audit --repo "$gh_slug" --json 2>/dev/null)"; then
            if echo "$audit_json" | jq -e 'type == "object" and has("changes")' >/dev/null 2>&1; then
              actions_checked=true
              actions_violations=$(echo "$audit_json" | jq '
                [ .changes[] | select(.label | startswith("actions:"))
                             | select(.status == "modify" or .status == "create") ] | length')
            fi
          fi
        fi
      fi
    fi
  fi
fi
hygiene=$(bash "$(dirname "$0")/check-repo-hygiene.sh" "$ROOT")

# README branding facts (anchor form, header emoji, badge-version truth, banner
# quality). Delegated for the same reason hygiene is: the analysis needs python3
# and an SVG/raster reader, and none of that belongs inline in a jq assembler.
# The script always exits 0 and always emits an object; when a fact could not be
# determined it says `"checked": false` and the scorer emits no gap for it.
branding=$(bash "$(dirname "$0")/check-readme-branding.sh" "$ROOT" --json)

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
  --argjson gh_readable "$gh_readable" \
  --arg gov_source "$gov_source" \
  --arg classic_protection "$classic_protection" \
  --argjson ruleset_safety "$ruleset_safety" \
  --argjson ruleset_pr_ci "$ruleset_pr_ci" \
  --argjson strict_status_checks "$strict_status_checks" \
  --argjson requires_conversation_resolution "$requires_conversation_resolution" \
  --argjson requires_linear_history "$requires_linear_history" \
  --argjson blocks_force_push "$blocks_force_push" \
  --argjson blocks_deletion "$blocks_deletion" \
  --argjson actions_checked "$actions_checked" \
  --argjson actions_violations "$actions_violations" \
  --argjson hygiene "$hygiene" \
  --argjson branding "$branding" \
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
      has_multi_install: $readme_has_multi_install,
      branding: $branding.branding
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
      readable: $gh_readable,
      source: $gov_source,
      protection_enabled: $branch_protection,
      required_approving_reviews: $required_reviews,
      requires_ci_check: $requires_ci_check,
      allow_auto_merge: $allow_auto_merge,
      delete_branch_on_merge: $delete_branch_on_merge,
      rulesets: {
        safety_active: $ruleset_safety,
        pr_ci_active: $ruleset_pr_ci,
        strict_required_status_checks: $strict_status_checks,
        requires_conversation_resolution: $requires_conversation_resolution,
        requires_linear_history: $requires_linear_history,
        blocks_force_push: $blocks_force_push,
        blocks_deletion: $blocks_deletion
      },
      legacy_classic_protection: $classic_protection,
      actions: {
        checked: $actions_checked,
        violations: $actions_violations
      }
    },
    hygiene: $hygiene.hygiene
  }'
