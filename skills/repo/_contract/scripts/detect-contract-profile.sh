#!/usr/bin/env bash
# detect-contract-profile.sh — choose the standards contract profile for a repo
# root, and answer the repo-shape questions the rest of the plugin keeps guessing.
#
# Usage:
#   detect-contract-profile.sh [repo-root]            # -> app-gold | plugin-gold
#   detect-contract-profile.sh [repo-root] --json     # -> shape facts as JSON
#   detect-contract-profile.sh [repo-root] --shape    # -> shape facts as KEY=VALUE
#
# WHY THE SHAPE MODE EXISTS
#   Several scripts each re-answered "is this a plugin repo?", "does this repo
#   have CI?", "does this repo publish releases?" — usually by assuming the
#   answer is yes. doctor.sh hard-failed with "no canonical version" on every
#   ordinary app repo for exactly that reason. One detector, read by everyone,
#   is how those answers stop drifting apart.
#
#   The PROFILE is deliberately still decided by `canonical/rules` alone: it
#   selects which assertion set a repo is graded against, and widening it would
#   silently re-grade existing repos. Shape facts are additive and score nothing.
set -euo pipefail

ROOT="${1:-.}"
MODE="profile"
for arg in "$@"; do
  case "$arg" in
    --json)  MODE="json" ;;
    --shape) MODE="shape" ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*) echo "detect-contract-profile: unknown flag: $arg" >&2; exit 1 ;;
    *) ROOT="$arg" ;;
  esac
done

if ! ROOT="$(cd "$ROOT" 2>/dev/null && pwd)"; then
  # Unreadable root: answer the safe default and say nothing else.
  echo "app-gold"
  exit 0
fi

# --- profile (unchanged semantics) -------------------------------------------
if [[ -d "$ROOT/canonical/rules" ]]; then
  PROFILE="plugin-gold"
else
  PROFILE="app-gold"
fi

if [[ "$MODE" == "profile" ]]; then
  echo "$PROFILE"
  exit 0
fi

bool() { case "$1" in 1) echo true ;; *) echo false ;; esac; }

# --- is this an agent-kit / plugin repo at all? ------------------------------
# Distinct from the profile: a repo can ship a Claude Code plugin manifest
# without the canonical/ build layout that plugin-gold grades.
MANIFEST_COUNT=0
for m in .claude-plugin/plugin.json .cursor-plugin/plugin.json .codex-plugin/plugin.json; do
  [[ -f "$ROOT/$m" ]] && MANIFEST_COUNT=$((MANIFEST_COUNT + 1))
done
[[ -f "$ROOT/.claude-plugin/marketplace.json" ]] && MANIFEST_COUNT=$((MANIFEST_COUNT + 1))
IS_PLUGIN=0
(( MANIFEST_COUNT > 0 )) && IS_PLUGIN=1
[[ -d "$ROOT/canonical/rules" || -f "$ROOT/agent-kit.config.json" ]] && IS_PLUGIN=1

HAS_CANONICAL_VERSION=0
[[ -f "$ROOT/plugin-version.json" ]] && HAS_CANONICAL_VERSION=1

# --- CI: which system, if any ------------------------------------------------
CI_SYSTEM=none
if [[ -d "$ROOT/.github/workflows" ]] \
   && find "$ROOT/.github/workflows" \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | grep -q .; then
  CI_SYSTEM=github_actions
elif [[ -f "$ROOT/.gitlab-ci.yml" ]];                then CI_SYSTEM=gitlab_ci
elif [[ -d "$ROOT/.circleci" ]];                     then CI_SYSTEM=circleci
elif [[ -d "$ROOT/.buildkite" ]];                    then CI_SYSTEM=buildkite
elif [[ -f "$ROOT/azure-pipelines.yml" ]];           then CI_SYSTEM=azure_pipelines
elif [[ -f "$ROOT/Jenkinsfile" ]];                   then CI_SYSTEM=jenkins
elif [[ -f "$ROOT/.travis.yml" ]];                   then CI_SYSTEM=travis
fi
HAS_CI=0
[[ "$CI_SYSTEM" != none ]] && HAS_CI=1

# --- release model -----------------------------------------------------------
HAS_RELEASE_TAGS=0
if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" tag -l 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null | grep -q . && HAS_RELEASE_TAGS=1
fi
HAS_RELEASE_MODEL=0
(( HAS_RELEASE_TAGS == 1 || MANIFEST_COUNT > 0 )) && HAS_RELEASE_MODEL=1

# --- published: is this repo distributed to anyone, or an experiment? --------
# The observable difference between "a product with users" and "a scratch repo"
# is whether it is installable or released. A one-file experiment has neither.
HAS_MAKEFILE=0
MAKEFILE_INSTALL=0
if [[ -f "$ROOT/Makefile" ]]; then
  HAS_MAKEFILE=1
  grep -qE '^install:' "$ROOT/Makefile" 2>/dev/null && MAKEFILE_INSTALL=1
fi
PKG_PUBLISHABLE=0
if [[ -f "$ROOT/package.json" ]] && command -v jq >/dev/null 2>&1; then
  [[ "$(jq -r '.private // false' "$ROOT/package.json" 2>/dev/null)" != "true" \
     && "$(jq -r '.name // empty' "$ROOT/package.json" 2>/dev/null)" != "" ]] && PKG_PUBLISHABLE=1
fi
PUBLISHED=0
(( HAS_RELEASE_MODEL == 1 || MAKEFILE_INSTALL == 1 || PKG_PUBLISHABLE == 1 )) && PUBLISHED=1

# --- how many AI harnesses does this repo target? ----------------------------
AI_PLATFORM_COUNT=0
[[ -f "$ROOT/.claude-plugin/plugin.json" || -f "$ROOT/CLAUDE.md" || -d "$ROOT/.claude/rules" ]] \
  && AI_PLATFORM_COUNT=$((AI_PLATFORM_COUNT + 1))
[[ -f "$ROOT/.cursor-plugin/plugin.json" || -d "$ROOT/.cursor/rules" || -f "$ROOT/.cursorrules" ]] \
  && AI_PLATFORM_COUNT=$((AI_PLATFORM_COUNT + 1))
[[ -f "$ROOT/.codex-plugin/plugin.json" || -f "$ROOT/AGENTS.md" ]] \
  && AI_PLATFORM_COUNT=$((AI_PLATFORM_COUNT + 1))
[[ -f "$ROOT/opencode.json" || -f "$ROOT/opencode.jsonc" ]] \
  && AI_PLATFORM_COUNT=$((AI_PLATFORM_COUNT + 1))
[[ -f "$ROOT/GEMINI.md" || -f "$ROOT/gemini-extension.json" ]] \
  && AI_PLATFORM_COUNT=$((AI_PLATFORM_COUNT + 1))

# --- shadcn: the only honest signal that src/components/ui is generated ------
SHADCN=0
[[ -f "$ROOT/components.json" ]] && SHADCN=1

if [[ "$MODE" == "shape" ]]; then
  cat <<EOF
PROFILE=$PROFILE
IS_PLUGIN_REPO=$(bool "$IS_PLUGIN")
PLUGIN_MANIFEST_COUNT=$MANIFEST_COUNT
HAS_CANONICAL_VERSION=$(bool "$HAS_CANONICAL_VERSION")
CI_SYSTEM=$CI_SYSTEM
HAS_CI=$(bool "$HAS_CI")
HAS_RELEASE_TAGS=$(bool "$HAS_RELEASE_TAGS")
HAS_RELEASE_MODEL=$(bool "$HAS_RELEASE_MODEL")
HAS_MAKEFILE=$(bool "$HAS_MAKEFILE")
PUBLISHED=$(bool "$PUBLISHED")
AI_PLATFORM_COUNT=$AI_PLATFORM_COUNT
SHADCN=$(bool "$SHADCN")
EOF
  exit 0
fi

cat <<EOF
{
  "root": "$ROOT",
  "profile": "$PROFILE",
  "is_plugin_repo": $(bool "$IS_PLUGIN"),
  "plugin_manifest_count": $MANIFEST_COUNT,
  "has_canonical_version": $(bool "$HAS_CANONICAL_VERSION"),
  "ci_system": "$CI_SYSTEM",
  "has_ci": $(bool "$HAS_CI"),
  "has_release_tags": $(bool "$HAS_RELEASE_TAGS"),
  "has_release_model": $(bool "$HAS_RELEASE_MODEL"),
  "has_makefile": $(bool "$HAS_MAKEFILE"),
  "published": $(bool "$PUBLISHED"),
  "ai_platform_count": $AI_PLATFORM_COUNT,
  "shadcn": $(bool "$SHADCN")
}
EOF
