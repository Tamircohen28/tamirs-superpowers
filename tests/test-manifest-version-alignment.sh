#!/usr/bin/env bash
# The manifest/tag alignment check reads only RELEASE tags. release.yml also tags the
# generated Claude-only tree v<version>-claude; that tag matched the vX.Y.Z glob, sorted
# past its own release, and read a push at the released version as "manifest BEHIND the
# latest tag" — master went red on the first post-release commit of 5.0.0. Hermetic: a
# temp git repo with one manifest and the tags each case needs.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
harness_require jq git
CHECK="$ROOT/skills/repo/_contract/scripts/check-manifest-version-alignment.sh"
TMP="$(harness_tmpdir)"

mkrepo() { # <dir> <manifest-version>
  harness_new_repo "$1"
  mkdir -p "$1/.claude-plugin"
  printf '{"name":"probe","version":"%s"}\n' "$2" > "$1/.claude-plugin/plugin.json"
  git -C "$1" add -A >/dev/null && git -C "$1" commit -qm manifest
}
rc_of() { bash "$CHECK" "$@" >/dev/null 2>&1; echo $?; }

section "a Claude distribution tag beside its release is not a newer release"
R="$TMP/released"; mkrepo "$R" 5.0.0
git -C "$R" tag v5.0.0 && git -C "$R" tag v5.0.0-claude && git -C "$R" tag claude
judge "manifest at the released version passes with v5.0.0 and v5.0.0-claude present" 0 "$(rc_of "$R" --allow-pending-release)"
judge "and passes without --allow-pending-release" 0 "$(rc_of "$R")"
git -C "$R" tag v5.0.1-claude
judge "a stray v5.0.1-claude with no v5.0.1 release changes nothing" 0 "$(rc_of "$R")"

section "a real newer release still fails a stale manifest"
git -C "$R" tag v5.0.1
out="$(bash "$CHECK" "$R" --allow-pending-release 2>&1)"; rc=$?
judge "manifest 5.0.0 behind release v5.0.1 fails" 1 "$rc"
judge "the message names the release tag, not the distribution tag" yes "$(has "$out" 'latest release tag (v5.0.1)')"

section "a pending release warns and passes on push, fails otherwise"
P="$TMP/pending"; mkrepo "$P" 5.1.0
git -C "$P" tag v5.0.0 && git -C "$P" tag v5.0.0-claude
judge "manifest ahead with --allow-pending-release passes" 0 "$(rc_of "$P" --allow-pending-release)"
judge "manifest ahead without the flag fails" 1 "$(rc_of "$P")"
judge "--manifests-only skips the tag comparison" 0 "$(rc_of "$P" --manifests-only)"

section "a prerelease tag still counts as a release"
Q="$TMP/pre"; mkrepo "$Q" 5.1.0-beta
git -C "$Q" tag v5.1.0-beta && git -C "$Q" tag v5.1.0-beta-claude
judge "manifest at the prerelease version passes beside its distribution tag" 0 "$(rc_of "$Q")"

harness_summary
