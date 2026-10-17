#!/usr/bin/env bash
# build-cursor-rules.sh — generate .cursor/rules/*.mdc from platforms/cursor/rules.map.json.
#
# Usage:
#   bash scripts/build-cursor-rules.sh [repo-root] [--check]
#   bash scripts/build-cursor-rules.sh -h | --help
#
# Example:
#   bash scripts/build-cursor-rules.sh . --check    # what CI runs (make cursor-rules-check)
#
# --check regenerates into a temp dir and diffs, so CI can fail on drift without
# writing to the working tree. Drift includes an adapter whose map entry was removed;
# a normal run prunes those. Manual adapters are verified in both modes and never
# rewritten.
#
# WHY THIS EXISTS
#   Every rule in rules/dev/ needs exactly one .cursor/rules/<basename>.mdc, and
#   tests/contract/cursor.sh enforced that mapping by COUNTING files only. The thirteen
#   .mdc files were hand-maintained: a rule renamed in rules/dev/ left a stale adapter
#   pointing at a path that no longer existed, and a summary edited in the adapter
#   never reached the canonical rule. Nothing failed, because nothing compared them.
#   This generator makes the adapters output, the same way .opencode/agents/,
#   .cursor/commands/ and .gemini/ already are, with the same --check drift gate.
#
# WHY A MAP FILE AND NOT THE RULE ITSELF
#   A Cursor rule carries three things the canonical rule does not: Cursor-only
#   frontmatter (`description`, `alwaysApply`, `globs`), and a SHORT pointer-style
#   summary — the adapters are deliberately not full copies, because a restated rule
#   drifts (rules/README.md). Those cannot be derived from rules/dev/*.md, and they
#   must not be written INTO rules/dev/*.md, which every other platform reads through
#   AGENTS.md. So they live in platforms/cursor/rules.map.json, keyed by basename, and
#   the generator assembles frontmatter + a generated-file comment + the canonical
#   pointer + the summary. Edit the map, never the .mdc.
#
# WHY FIVE ADAPTERS ARE `manual: true`
#   commit-conventions, hooks-guide, plugin-structure, skills-guide and
#   skill-frontmatter thin into core/policies, AGENTS.md or a schema, not into a
#   rules/dev rule, and carry Cursor-specific prose (a hooks.json example, the repo
#   table). They are listed in the map with their canonical source so the map is the
#   complete inventory of .cursor/rules/; the generator checks each exists and opens
#   with frontmatter, and leaves the content alone.
#
# Exit 0 on success; 1 if --check finds drift or a manual adapter is broken;
# 2 on a malformed map, a rules/dev rule with no map entry, or a missing source.
set -euo pipefail

usage() { sed -n '2,14p' "$0" | sed 's/^#[[:space:]]\{0,1\}//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

ROOT="."
CHECK=false
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=true ;;
    -*) echo "Unknown flag: $arg" >&2; usage 1 ;;
    *) ROOT="$arg" ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"

command -v jq >/dev/null 2>&1 || { echo "error: jq is required (reads the map file)" >&2; exit 1; }

MAP="$ROOT/platforms/cursor/rules.map.json"
SRC_DIR="$ROOT/rules/dev"
REAL_DEST="$ROOT/.cursor/rules"
MAP_REL="platforms/cursor/rules.map.json"
GENERATOR="scripts/build-cursor-rules.sh"

[[ -f "$MAP" ]] || { echo "ERROR: $MAP_REL not found" >&2; exit 2; }
jq empty "$MAP" 2>/dev/null || { echo "ERROR: $MAP_REL is not valid JSON" >&2; exit 2; }
[[ -d "$SRC_DIR" ]] || { echo "No rules/dev/ directory — nothing to build"; exit 0; }

DEST="$REAL_DEST"
if [[ "$CHECK" == true ]]; then
  DEST="$(mktemp -d)"
  trap 'rm -rf "$DEST"' EXIT
fi
mkdir -p "$DEST"

# One field of one entry, raw. Missing -> empty string. Tested against null, not
# with `//`, because `//` also swallows a literal `false` (alwaysApply: false).
map_get() { jq -r --arg k "$1" --arg f "$2" '.rules[$k][$f] | if . == null then empty else . end' "$MAP"; }

fail=0
generated=()
manual=()
count=0

# --- coverage: every rules/dev rule has a generated entry; every entry has a source ---
for f in "$SRC_DIR"/*.md; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f" .md)"
  [[ "$base" == "README" ]] && continue   # the index, not a rule; no adapter by design
  kind="$(jq -r --arg k "$base" '.rules[$k] | if . == null then "missing" elif .manual == true then "manual" else "generated" end' "$MAP")"
  case "$kind" in
    generated) ;;
    missing) echo "ERROR: rules/dev/$base.md has no entry in $MAP_REL — add one (description, alwaysApply, title, summary)" >&2; exit 2 ;;
    manual)  echo "ERROR: rules/dev/$base.md is listed as manual in $MAP_REL — a rules/dev rule must be generated" >&2; exit 2 ;;
  esac
done

while IFS= read -r key; do
  [[ -n "$key" ]] || continue
  src="$(map_get "$key" source)"
  [[ -n "$src" ]] || { echo "ERROR: $MAP_REL entry '$key' has no 'source'" >&2; exit 2; }
  src_path="${src%%#*}"   # a source may carry a section anchor
  [[ -e "$ROOT/$src_path" ]] || { echo "ERROR: $MAP_REL entry '$key' names a source that does not exist: $src" >&2; exit 2; }

  if [[ "$(map_get "$key" manual)" == "true" ]]; then
    manual+=("$key")
    continue
  fi

  [[ "$src" == rules/dev/*.md ]] || { echo "ERROR: generated entry '$key' must point at rules/dev/<file>.md (got: $src)" >&2; exit 2; }
  desc="$(map_get "$key" description)"
  title="$(map_get "$key" title)"
  always="$(map_get "$key" alwaysApply)"
  [[ -n "$desc" ]]  || { echo "ERROR: $MAP_REL entry '$key' has no 'description'" >&2; exit 2; }
  [[ -n "$title" ]] || { echo "ERROR: $MAP_REL entry '$key' has no 'title'" >&2; exit 2; }
  [[ "$always" == "true" || "$always" == "false" ]] || { echo "ERROR: $MAP_REL entry '$key' needs alwaysApply: true|false" >&2; exit 2; }
  note="$(jq -r --arg k "$key" '.rules[$k].canonical_note // "."' "$MAP")"

  {
    echo "---"
    jq -r --arg k "$key" '"description: " + (.rules[$k].description | @json)' "$MAP"
    echo "alwaysApply: $always"
    # globs is emitted as written: an array as `["a", "b"]`, a string as `"a,b"`.
    jq -r --arg k "$key" '
      .rules[$k].globs
      | if . == null then empty
        elif type == "array" then "globs: [" + (map(@json) | join(", ")) + "]"
        else "globs: " + @json end' "$MAP"
    echo "---"
    echo
    echo "<!-- GENERATED FILE — DO NOT EDIT."
    echo "     Source:    $src (frontmatter + summary: $MAP_REL)"
    echo "     Generator: $GENERATOR"
    echo "     Regenerate: make cursor-rules -->"
    echo
    echo "# $title"
    echo
    echo "Canonical rule: \`$src\`$note"
    echo
    jq -r --arg k "$key" '.rules[$k].summary // "" | if type == "array" then join("\n") else . end' "$MAP"
  } > "$DEST/$key.mdc"
  generated+=("$key")
  count=$((count + 1))
done < <(jq -r '.rules | keys[]' "$MAP")

# --- manual adapters: must exist in the REAL tree and open with frontmatter -----
for key in "${manual[@]:-}"; do
  [[ -n "$key" ]] || continue
  mf="$REAL_DEST/$key.mdc"
  if [[ ! -f "$mf" ]]; then
    echo "ERROR: manual adapter .cursor/rules/$key.mdc is listed in $MAP_REL but does not exist" >&2
    fail=1
  elif ! head -1 "$mf" | grep -q '^---[[:space:]]*$'; then
    echo "ERROR: manual adapter .cursor/rules/$key.mdc does not open with YAML frontmatter" >&2
    fail=1
  elif grep -q 'GENERATED FILE — DO NOT EDIT' "$mf"; then
    echo "ERROR: manual adapter .cursor/rules/$key.mdc carries the generated-file marker — either drop 'manual: true' or remove the marker" >&2
    fail=1
  fi
done

# --- stale adapters: an .mdc in the real tree that the map does not name ---------
stale=()
for existing in "$REAL_DEST"/*.mdc; do
  [[ -e "$existing" ]] || continue
  eb="$(basename "$existing" .mdc)"
  listed=false
  for g in "${generated[@]:-}" "${manual[@]:-}"; do [[ "$g" == "$eb" ]] && listed=true && break; done
  [[ "$listed" == false ]] && stale+=("$eb")
done

if [[ "$CHECK" == true ]]; then
  drift=""
  for key in "${generated[@]:-}"; do
    [[ -n "$key" ]] || continue
    if [[ ! -f "$REAL_DEST/$key.mdc" ]]; then
      drift="${drift}  missing: .cursor/rules/$key.mdc"$'\n'
    elif ! cmp -s "$DEST/$key.mdc" "$REAL_DEST/$key.mdc"; then
      drift="${drift}  changed: .cursor/rules/$key.mdc"$'\n'
      drift="${drift}$(diff -u "$REAL_DEST/$key.mdc" "$DEST/$key.mdc" || true)"$'\n'
    fi
  done
  for s in "${stale[@]:-}"; do
    [[ -n "$s" ]] || continue
    drift="${drift}  not in map: .cursor/rules/$s.mdc (add it to $MAP_REL as generated or manual, or delete it)"$'\n'
  done
  if [[ -n "$drift" ]]; then
    {
      echo "ERROR: .cursor/rules/ is out of sync with $MAP_REL."
      echo "       These files are GENERATED — fix the map (or rules/dev/), then run: make cursor-rules"
      echo
      printf '%s' "$drift"
    } >&2
    exit 1
  fi
  [[ "$fail" -eq 0 ]] || exit 1
  echo "Cursor rule adapters in sync ($count generated, ${#manual[@]} manual)"
  exit 0
fi

pruned=0
for s in "${stale[@]:-}"; do
  [[ -n "$s" ]] || continue
  rm -f "$REAL_DEST/$s.mdc"
  echo "pruned: .cursor/rules/$s.mdc (not in $MAP_REL)" >&2
  pruned=$((pruned + 1))
done

[[ "$fail" -eq 0 ]] || exit 1
suffix=""; [[ "$pruned" -gt 0 ]] && suffix=", pruned $pruned stale"
echo "Generated $count Cursor rule adapter(s) in .cursor/rules/ (${#manual[@]} manual left untouched)$suffix"
