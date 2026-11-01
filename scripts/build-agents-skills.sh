#!/usr/bin/env bash
# build-agents-skills.sh — generate the portable .agents/skills/ mirror.
#
# Usage:
#   bash scripts/build-agents-skills.sh [repo-root] [--check]
#   bash scripts/build-agents-skills.sh -h | --help
#
# Generates:
#   .agents/skills/<name>  — relative symlink to skills/<domain>/<name>
#
# --check regenerates into a temp dir and compares, so CI can fail on drift without
# writing to the working tree. Drift includes entries whose canonical source was
# deleted; a normal run prunes those.
#
# WHY THIS EXISTS
#   `.agents/skills/` is the one skills root several hosts now read from a repo
#   without any install step: Codex (repository skill discovery), Gemini CLI (an
#   alias of the workspace tier `.gemini/skills/`, and the higher-precedence one
#   of the two), Antigravity (where `agy plugin import gemini` moves workspace
#   skills to), OpenCode and Copilot. Every one of them discovers a skill exactly
#   ONE level below the root — `.agents/skills/<name>/SKILL.md` — and this repo's
#   canonical tree is two levels deep (`skills/<domain>/<name>/`), so pointing
#   any of them at the canonical tree finds nothing. The same reasoning as
#   `.gemini/skills/` (scripts/build-gemini-extension.sh), whose shape this
#   mirrors exactly: one relative symlink per skill, so there is still exactly
#   one copy of every skill in the repository and the mirror cannot drift in
#   content, only in membership — which --check enforces.
#
# WHAT IS MIRRORED
#   Every skills/<domain>/<name>/SKILL.md, the same two-level glob as the Gemini
#   mirror: every skill, including the three internal companions
#   (changelog-review, docs-review, mcp-pagination). They carry
#   `user-invocable: false` in their frontmatter, which is the field that hides
#   them from a slash surface; a host that ignores the field shows them, exactly
#   as .gemini/skills/ already does, and omitting them here would make the two
#   mirrors disagree about what the plugin ships. The gold fixtures under
#   skills/repo/_contract/fixtures/ sit deeper than the glob and are never mirrored.
#
# KNOWN LIMIT
#   OpenCode 1 did not follow symlinks for skill discovery at any level (verified
#   1.18.11, see platforms/README.md) and symlink following is unmeasured on
#   OpenCode 2, so this mirror is treated as invisible to OpenCode in place; opencode.json keeps pointing at the canonical tree. The tarball a
#   host installs from (scripts/build-dist.sh) dereferences symlinks, so a
#   shipped .agents/skills/ is plain directories.
#
# Exit 0 on success; 1 if --check finds drift; 2 on a malformed or colliding source.
set -euo pipefail

usage() { sed -n '2,13p' "$0" | sed 's/^#[[:space:]]\{0,1\}//'; exit "${1:-0}"; }

ROOT="."
CHECK=false
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage 0 ;;
    --check) CHECK=true ;;
    -*) printf 'Unknown flag: %s\n' "$arg" >&2; usage 1 ;;
    *) ROOT="$arg" ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"

SKILL_SRC="$ROOT/skills"
REAL_DEST="$ROOT/.agents/skills"
DEST="$REAL_DEST"
if [[ "$CHECK" == true ]]; then
  DEST="$(mktemp -d)/skills"
  trap 'rm -rf "$(dirname "$DEST")"' EXIT
fi
mkdir -p "$DEST"

skill_count=0
skill_names=()
declare -a seen_names=()
declare -a seen_sources=()

while IFS= read -r skillmd; do
  [[ -e "$skillmd" ]] || continue
  dir="$(dirname "$skillmd")"
  name="$(basename "$dir")"
  domain="$(basename "$(dirname "$dir")")"
  for i in "${!seen_names[@]}"; do
    if [[ "${seen_names[$i]}" == "$name" ]]; then
      echo "ERROR: skill name collision on flattening: '$name' exists in both" >&2
      echo "         ${seen_sources[$i]}" >&2
      echo "         skills/$domain/$name" >&2
      echo "       .agents/skills/ is a flat namespace; rename one of them." >&2
      exit 2
    fi
  done
  seen_names+=("$name")
  seen_sources+=("skills/$domain/$name")
  ln -sfn "../../skills/$domain/$name" "$DEST/$name"
  skill_names+=("$name")
  skill_count=$((skill_count + 1))
done < <(find "$SKILL_SRC" -mindepth 3 -maxdepth 3 -name SKILL.md 2>/dev/null | sort)

if (( skill_count == 0 )); then
  echo "ERROR: no canonical skills found at skills/<domain>/<name>/SKILL.md" >&2
  echo "       Refusing to generate an empty mirror — an empty .agents/skills/ is" >&2
  echo "       indistinguishable from a working one until a host finds no skills." >&2
  exit 2
fi

# Prune entries whose canonical source is gone (normal run only).
pruned=0
if [[ "$CHECK" != true ]]; then
  for existing in "$DEST"/*; do
    [[ -e "$existing" || -L "$existing" ]] || continue
    eb="$(basename "$existing")"
    found=false
    for n in "${skill_names[@]}"; do [[ "$n" == "$eb" ]] && found=true && break; done
    if [[ "$found" == false ]]; then rm -rf "$existing"; pruned=$((pruned + 1)); fi
  done
fi

# Compared as name -> link target, never by content: `diff -r` would follow the
# links and compare the canonical tree with itself.
link_manifest() {
  local d="$1" e
  for e in "$d"/*; do
    [[ -e "$e" || -L "$e" ]] || continue
    printf '%s -> %s\n' "$(basename "$e")" "$(readlink "$e" 2>/dev/null || echo '<not-a-symlink>')"
  done | sort
}

if [[ "$CHECK" == true ]]; then
  if [[ ! -d "$REAL_DEST" ]]; then
    echo "ERROR: .agents/skills/ is missing. Run: bash scripts/build-agents-skills.sh ." >&2
    exit 1
  fi
  if ! diff -u <(link_manifest "$REAL_DEST") <(link_manifest "$DEST") >&2; then
    echo "ERROR: .agents/skills/ is out of sync with skills/. It is GENERATED — run: bash scripts/build-agents-skills.sh ." >&2
    exit 1
  fi
  echo ".agents/skills in sync ($skill_count skill(s))"
  exit 0
fi
echo "Generated .agents/skills: $skill_count symlink(s)${pruned:+ (pruned $pruned stale)}"
