#!/usr/bin/env bash
# sync-contract-scripts.sh — regenerate (or assert) the contract's duplicated files.
#
# Usage:
#   sync-contract-scripts.sh [repo-root]            # regenerate copies from canonical
#   sync-contract-scripts.sh [repo-root] --check    # assert copies match; exit 1 on drift
#   sync-contract-scripts.sh -h | --help
#
# Several files exist in three places by necessity: the plugin's own scripts/, the
# scaffold template that repo-scaffold renders, and each gold fixture that must exercise
# the same logic a scaffolded repo will run. Hand-maintaining those copies does not work.
# Two forks were found in this repo, both invisible because nothing compared them:
#
#   * fixtures/*/scripts/check-feature-equivalence.sh sat on a pre-fix revision of
#     scripts/check-feature-equivalence.sh for as long as fixtures were outside the
#     lint scope, so the fixtures were testing logic the live script no longer had.
#   * templates/check-manifest-version-alignment.sh.tmpl never received
#     --allow-pending-release, directional ahead/behind drift detection, or the BSD-sed
#     usage() fix, so every scaffolded repo inherited three already-fixed defects.
#
# The mapping is data, in ../script-sync.json — adding a copy is an edit there, not here.
# Groups are processed in declaration order, so a chain (registry -> template -> fixtures)
# propagates in a single pass when the links are declared in that order.
# Same shape as `make opencode-agents` / `make opencode-agents-check`.
#
# Exit 0 when everything matches (or was regenerated); 1 on drift under --check.
set -euo pipefail

usage() { sed -n '2,25p' "$0" | sed -E 's/^# ?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$CONTRACT_DIR/script-sync.json"

CHECK=false
ROOT=""
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=true ;;
    -*) echo "sync-contract-scripts: unknown flag: $arg" >&2; exit 1 ;;
    *) ROOT="$arg" ;;
  esac
done

# Default root: the repo that owns this contract directory (skills/repo/_contract -> up 3).
if [[ -z "$ROOT" ]]; then
  ROOT="$(cd "$CONTRACT_DIR/../../.." && pwd)"
fi
ROOT="$(cd "$ROOT" && pwd)"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required by sync-contract-scripts.sh" >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "ERROR: missing $MANIFEST" >&2; exit 1; }

DRIFTED=0
CHECKED=0
UPDATED=0

# Render the canonical file for one copy: apply the group's substitutions, then the
# copy's own. Keys are bare names; the placeholder form is {{KEY}}.
#
# reverse=true goes the other way — concrete value back to {{KEY}}. That is how a
# parameterised template is generated FROM a live instance: core/capabilities/platforms.json
# is the real registry, and templates/core/capabilities/platforms.json.tmpl is that same
# file with this repo's owner/name lifted out. Without it the template is a hand-copy that
# silently rots the moment the registry is corrected — which is exactly what happened to
# the OpenCode symlink guidance.
render() {
  # python3, not bash ${var//a/b}: bash string replacement over a 30 KB registry is
  # quadratic, and it turned a 25-copy sync into minutes.
  python3 - "$1" "$2" "${3:-false}" <<'RENDER_PY'
import json, sys
src, subs, reverse = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3] == "true"
text = open(src, encoding="utf-8").read()
for k, v in subs.items():
    if reverse:
        text = text.replace(v, "{{%s}}" % k)
    else:
        text = text.replace("{{%s}}" % k, v)
sys.stdout.write(text)
RENDER_PY
}

while IFS=$'\t' read -r gid canonical group_subs copy_json; do
  [[ -n "$gid" ]] || continue
  src="$ROOT/$canonical"
  if [[ ! -f "$src" ]]; then
    echo "ERROR: [$gid] canonical source missing: $canonical" >&2
    DRIFTED=$(( DRIFTED + 1 ))
    continue
  fi

  # Each copy is either a plain path string or {path, substitutions}.
  while IFS=$'\t' read -r cpath copy_subs copy_reverse; do
    [[ -n "$cpath" ]] || continue
    dst="$ROOT/$cpath"
    subs="$(jq -nc --argjson a "$group_subs" --argjson b "$copy_subs" '$a * $b')"

    expected="$(render "$src" "$subs" "$copy_reverse")"
    CHECKED=$(( CHECKED + 1 ))

    if [[ -f "$dst" ]] && [[ "$expected" == "$(cat "$dst")" ]]; then
      continue
    fi

    if [[ "$CHECK" == true ]]; then
      DRIFTED=$(( DRIFTED + 1 ))
      echo "DRIFT: $cpath" >&2
      echo "       is not the rendered form of $canonical" >&2
      if [[ -f "$dst" ]]; then
        diff <(printf '%s' "$expected") "$dst" | head -20 | sed 's/^/       /' >&2 || true
      else
        echo "       (file does not exist)" >&2
      fi
    else
      mkdir -p "$(dirname "$dst")"
      printf '%s' "$expected" >"$dst"
      [[ -x "$src" ]] && chmod +x "$dst"
      echo "updated: $cpath"
      UPDATED=$(( UPDATED + 1 ))
    fi
  done < <(jq -r --arg g "$gid" '
    .groups[] | select(.id == $g) | .copies[]
    | if type == "string" then [., {}, false] else [.path, (.substitutions // {}), (.reverse // false)] end
    | "\(.[0])\t\(.[1] | tojson)\t\(.[2])"' "$MANIFEST")
done < <(jq -r '.groups[] | "\(.id)\t\(.canonical)\t\(.substitutions // {} | tojson)\t"' "$MANIFEST")

# Derived capability mirrors. Copying a fixture's registry is only half the job: its
# platform-targets.json mirrors that registry and goes stale the moment the registry moves.
if [[ "$CHECK" != true ]]; then
  SYNC_CAPS="$ROOT/scripts/check-platform-targets.sh"
  if [[ -f "$SYNC_CAPS" ]]; then
    while IFS= read -r froot; do
      [[ -n "$froot" ]] || continue
      [[ -f "$ROOT/$froot/core/capabilities/platforms.json" ]] || continue
      [[ -f "$ROOT/$froot/docs/engineering/build-and-release/platform-targets.json" ]] || continue
      # Capture, do not pipe: `| grep -q` exits early, and under `set -o pipefail` the
      # resulting SIGPIPE makes the whole pipeline look like a failure even on a match.
      mirror_out="$(bash "$SYNC_CAPS" "$ROOT/$froot" --sync-capabilities 2>/dev/null || true)"
      if [[ "$mirror_out" == *"Regenerated"* ]]; then
        echo "updated: $froot/docs/engineering/build-and-release/platform-targets.json (capability mirror)"
        UPDATED=$(( UPDATED + 1 ))
      fi
    done < <(jq -r '.capability_mirror_roots.roots // [] | .[]' "$MANIFEST")
  fi
fi

if (( DRIFTED > 0 )); then
  echo "Contract script sync FAILED — $DRIFTED of $CHECKED copy/copies have forked from their canonical source" >&2
  echo "Regenerate with: bash skills/repo/_contract/scripts/sync-contract-scripts.sh" >&2
  exit 1
fi

if [[ "$CHECK" == true ]]; then
  echo "Contract script sync check passed ($CHECKED copies identical to canonical)"
else
  echo "Contract script sync complete ($CHECKED copies, $UPDATED updated)"
fi
