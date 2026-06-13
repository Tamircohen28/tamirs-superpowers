#!/usr/bin/env bash
# check-stale-refs.sh — find files referencing deleted agents or old architecture patterns.
# Usage: bash .claude/skills/repo-review/scripts/check-stale-refs.sh [ROOT_DIR]
#
# AGENT DETECTION APPROACH:
# Do NOT hardcode a list of "deleted" agents. Agent .md files reference their own names,
# so any hardcoded list will produce false positives (the file flagging itself).
# Instead, derive deleted agents from git history: agents whose .md was git-rm'd but
# whose name still appears in other files.
#
# An agent is only truly deleted if ALL of these are true:
#   1. git log --diff-filter=D shows its plugin/agents/pm-<name>.md was removed
#   2. It is NOT referenced in plugin/skills/investigate/SKILL.md
#   3. It is NOT referenced in plugin/pipeline/steps.json
#   4. plugin/agents/pm-<name>.md does not currently exist

ROOT_DIR="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Derive deleted agents from git history instead of a hardcoded list.
# Only agents whose .md file was actually git-rm'd are candidates.
DELETED_AGENTS=()
while IFS= read -r path; do
  [ -z "$path" ] && continue
  name=$(basename "$path" .md)
  # Skip if the file still exists (was restored)
  [ -f "$ROOT_DIR/$path" ] && continue
  # Skip if still referenced in the active pipeline
  if grep -q "$name" "$ROOT_DIR/plugin/skills/investigate/SKILL.md" 2>/dev/null || \
     grep -q "$name" "$ROOT_DIR/plugin/pipeline/steps.json" 2>/dev/null; then
    continue
  fi
  DELETED_AGENTS+=("$name")
done < <(git -C "$ROOT_DIR" log --diff-filter=D --name-only --pretty=format: -- 'plugin/agents/pm-*.md' 2>/dev/null | grep 'pm-' | sort -u)

# Old structural patterns — should no longer appear in active docs
OLD_PATTERNS=(
  "plugin/commands/"
  "src/agents/prompts/"
  "platforms/claude/agents/"
  "[Ll]ang[Gg]raph"
  "typescript.*investigation"
  "TypeScript.*service"
)

# Files intentionally historical — exempt from stale-ref checks
EXEMPT_PATTERNS=(
  "known-regressions-archive"
  "pipeline-design-decisions"
  "CHANGELOG"
)

is_exempt() {
  local file="$1"
  for pat in "${EXEMPT_PATTERNS[@]}"; do
    [[ "$file" == *"$pat"* ]] && return 0
  done
  return 1
}

echo "=== Stale Reference Report ==="
echo "ROOT: $ROOT_DIR"
echo ""

echo "--- Deleted agent references ---"
any_agent=0
for agent in "${DELETED_AGENTS[@]}"; do
  hits=()
  while IFS= read -r f; do
    rel="${f#$ROOT_DIR/}"
    is_exempt "$rel" && continue
    # Skip plugin/agents/ — agent files reference their own names (self-reference is expected)
    [[ "$rel" == plugin/agents/* ]] && continue
    hits+=("$rel")
  done < <(grep -rl "$agent" "$ROOT_DIR" \
    --include="*.md" --include="*.sh" --include="*.json" --include="*.yaml" --include="*.yml" \
    --exclude-dir=".git" --exclude-dir="node_modules" --exclude-dir="dist" \
    2>/dev/null)
  if [ "${#hits[@]}" -gt 0 ]; then
    echo "  $agent:"
    for h in "${hits[@]}"; do echo "    $h"; done
    any_agent=1
  fi
done
[ "$any_agent" -eq 0 ] && echo "  (none)"

echo ""
echo "--- Old architecture pattern references ---"
any_arch=0
for pattern in "${OLD_PATTERNS[@]}"; do
  hits=()
  while IFS= read -r f; do
    rel="${f#$ROOT_DIR/}"
    is_exempt "$rel" && continue
    hits+=("$rel")
  done < <(grep -rlE "$pattern" "$ROOT_DIR" \
    --include="*.md" --include="*.sh" \
    --exclude-dir=".git" --exclude-dir="node_modules" --exclude-dir="dist" \
    2>/dev/null)
  if [ "${#hits[@]}" -gt 0 ]; then
    echo "  '$pattern':"
    for h in "${hits[@]}"; do echo "    $h"; done
    any_arch=1
  fi
done
[ "$any_arch" -eq 0 ] && echo "  (none)"
