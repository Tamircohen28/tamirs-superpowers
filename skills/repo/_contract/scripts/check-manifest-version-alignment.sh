#!/usr/bin/env bash
# check-manifest-version-alignment.sh — enforce S10-04/S10-05: plugin manifests
# must agree with each other, and must not be ahead of (or behind) the latest
# release tag once the repo has cut at least one release.
#
# Usage:
#   check-manifest-version-alignment.sh [repo-root] [--manifests-only]
#                                       [--allow-pending-release]
#   check-manifest-version-alignment.sh -h | --help
#
# --manifests-only skips the tag comparison (S10-05) and only checks manifests
# agree with each other (S10-04) — use this mid-release, after bumping
# manifests but before the tag exists yet.
#
# --allow-pending-release downgrades "manifest ahead of latest tag" from an
# error to a warning. Merging a version-bumping PR pushes a manifest whose tag
# cannot exist yet — the release workflow only runs afterwards — so on
# push-to-master that state is expected, not drift. Manifest *behind* the
# latest tag is still a hard error under this flag: nothing legitimate moves a
# manifest backwards past a cut release.
#
# Exit 0 if aligned; 1 if drift detected.
set -euo pipefail

# `\?` is a GNU extension — BSD/macOS sed leaves the `# ` prefixes in place.
usage() { sed -n '2,20p' "$0" | sed 's/^#[[:space:]]\{0,1\}//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

MANIFESTS_ONLY=false
ALLOW_PENDING=false
ROOT="."
for arg in "$@"; do
  case "$arg" in
    --manifests-only)        MANIFESTS_ONLY=true ;;
    --allow-pending-release) ALLOW_PENDING=true ;;
    *)                       ROOT="$arg" ;;
  esac
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
    # Which way does the drift point? Sorting both and taking the tail gives the
    # higher of the two. Pre-release suffixes (1.9.0-beta) sort by their numeric
    # fields only, same as the tag lookup above — close enough for ordering.
    HIGHER=$(printf '%s\n%s\n' "$MANIFEST_VERSION" "$LATEST_TAG_VER" \
      | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)

    if [[ "$HIGHER" == "$MANIFEST_VERSION" ]] && [[ "$ALLOW_PENDING" == true ]]; then
      # Manifest ahead: a version bump merged and its release has not been cut
      # yet. Expected for the minutes between merge and the release workflow.
      echo "::warning::Release pending — manifests are at $MANIFEST_VERSION but the latest tag is v$LATEST_TAG_VER. Cut it with: gh workflow run release.yml -f version=$MANIFEST_VERSION"
      echo "Release pending: manifests $MANIFEST_VERSION > latest tag v$LATEST_TAG_VER (allowed)"
    elif [[ "$HIGHER" == "$MANIFEST_VERSION" ]]; then
      err "manifest version ($MANIFEST_VERSION) is ahead of the latest release tag (v$LATEST_TAG_VER) — cut the release with: gh workflow run release.yml -f version=$MANIFEST_VERSION"
    else
      err "manifest version ($MANIFEST_VERSION) is BEHIND the latest release tag (v$LATEST_TAG_VER) — manifests must never move backwards past a cut release"
    fi
  fi
fi

if (( FAILED > 0 )); then
  echo "Manifest version alignment check failed ($FAILED error(s))" >&2
  exit 1
fi

echo "Manifest version alignment check passed ($MANIFEST_VERSION)"
