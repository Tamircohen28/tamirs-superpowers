#!/usr/bin/env bash
# check-manifest-version-alignment.sh — enforce S10-04/S10-05: plugin manifests
# must agree with each other, and must not be ahead of (or behind) the latest
# release tag once the repo has cut at least one release.
#
# Usage:
#   check-manifest-version-alignment.sh [repo-root] [--manifests-only]
#   check-manifest-version-alignment.sh -h | --help
#
# --manifests-only skips the tag comparison (S10-05) and only checks manifests
# agree with each other (S10-04) — use this mid-release, after bumping
# manifests but before the tag exists yet.
#
# Exit 0 if aligned; 1 if drift detected.
set -euo pipefail

usage() { sed -n '2,13p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

MANIFESTS_ONLY=false
ROOT="."
for arg in "$@"; do
  if [[ "$arg" == "--manifests-only" ]]; then
    MANIFESTS_ONLY=true
  else
    ROOT="$arg"
  fi
done
ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

err() { echo "ERROR: $*" >&2; FAILED=1; }

MANIFEST_VERSION=""
FIRST_MANIFEST=""
for manifest in .claude-plugin/plugin.json .cursor-plugin/plugin.json .codex-plugin/plugin.json; do
  path="$ROOT/$manifest"
  [[ -f "$path" ]] || continue
  v=$(jq -r '.version // empty' "$path" 2>/dev/null || true)
  if [[ -z "$v" ]]; then
    err "$manifest has no .version field"
    continue
  fi
  if [[ -z "$MANIFEST_VERSION" ]]; then
    MANIFEST_VERSION="$v"
    FIRST_MANIFEST="$manifest"
  elif [[ "$v" != "$MANIFEST_VERSION" ]]; then
    err "$manifest version ($v) does not match $FIRST_MANIFEST version ($MANIFEST_VERSION)"
  fi
done

if [[ -z "$MANIFEST_VERSION" ]]; then
  echo "No plugin.json manifests found — nothing to check"
  exit 0
fi

if [[ "$MANIFESTS_ONLY" != true ]]; then
  # Latest release tag, if any (vX.Y.Z convention). A repo with no tags yet
  # hasn't cut a first release — nothing to drift from.
  LATEST_TAG_VER=$(cd "$ROOT" && git tag -l 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null \
    | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 || true)

  if [[ -n "$LATEST_TAG_VER" && "$LATEST_TAG_VER" != "$MANIFEST_VERSION" ]]; then
    err "manifest version ($MANIFEST_VERSION) does not match latest release tag (v$LATEST_TAG_VER) — bump manifests and tags together via the release workflow, never by hand"
  fi
fi

if (( FAILED > 0 )); then
  echo "Manifest version alignment check failed ($FAILED error(s))" >&2
  exit 1
fi

echo "Manifest version alignment check passed ($MANIFEST_VERSION)"
