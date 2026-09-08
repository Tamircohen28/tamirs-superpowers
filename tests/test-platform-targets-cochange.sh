#!/usr/bin/env bash
# test-platform-targets-cochange.sh — the co-change gate must judge the whole change,
# and must judge it by the paths it actually watches.
#
# WHY THIS FILE EXISTS
#   Two defects in `check-platform-targets.sh --require-co-change`, both of the shape
#   this repo keeps finding: a checker whose verdict came from where it happened to
#   look rather than from what it was asked to check.
#
#   1. DIFF RANGE. The gate diffed `HEAD~1 HEAD`. A push of several commits, and every
#      PR longer than one commit, was therefore judged by its tip alone: a violation in
#      any earlier commit passed silently. The range must start at the merge-base with
#      the push/PR base (GITHUB_BASE_REF on pull_request, the event payload's
#      before-SHA on push), falling back to HEAD~1 only when neither exists — a local
#      `make platform-targets-cochange` has no CI env and must keep working.
#
#   2. PATH AS REGEX. The gate did `grep -q "^${p}"` with a WATCH_PATH as the pattern,
#      so every `.` in a watched path matched any character:
#      `core/capabilities/platforms.json` also matched
#      `core/capabilities/platforms_json.txt`. Over-matching makes the gate fire on
#      files nobody asked it to watch, which trains people to ignore it. Matching must
#      be literal: entries ending in `/` are directory prefixes, the rest exact files.
#
#   3. BYTE CHANGE READ AS CLAIM CHANGE. `core/capabilities/platforms.json` was
#      watched by the same rule as the prose paths: any edit to it demanded a
#      co-change in platform-targets.json. But platform-targets.json's `capabilities`
#      and `capability_gaps` are a DERIVED mirror of that registry, and a normal run
#      of the script already asserts semantically that they match. So a notes-only
#      correction -- a prose fix to a capability whose status did not move, which
#      nothing derives from -- fired a gate whose only remedy was to commit an
#      unrelated edit to the derived doc. A gap asserted from where the checker looked
#      rather than from what is true, and the more corrosive direction: acting on it
#      means manufacturing drift to make a checker green. The registry is now judged
#      on its capability STATUS and platform/surface projection, and a projection that
#      cannot be made falls back to the byte answer rather than to silence.
#
#   Every case is asserted in both directions. The over-match cases are paired with the
#   real watched path, so a "fix" that simply stops matching anything fails here, and
#   the range cases are paired with a clean multi-commit range, so a fix that always
#   fires fails here too.
#
# Usage: bash tests/test-platform-targets-cochange.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require git jq
CHECK="$REPO_ROOT/scripts/check-platform-targets.sh"

TMP="$(harness_tmpdir)"
TARGETS='docs/engineering/build-and-release/platform-targets.json'

# new_repo <name> — hermetic repo on `master` with one base commit, mirroring the
# real repo's default branch so a pull_request base ref means something here.
new_repo() {
  local d="$TMP/$1"
  harness_new_repo "$d" master
  printf '%s\n' "$d"
}

# commit <repo> <message> <path>... — one commit touching exactly those paths.
commit() {
  local d="$1" msg="$2"; shift 2
  local rel
  for rel in "$@"; do
    mkdir -p "$d/$(dirname "$rel")"
    printf 'touched by %s\n' "$msg" >> "$d/$rel"
  done
  git -C "$d" add -A
  git -C "$d" commit -q -m "$msg"
}

# gate <repo> [env-assignment...] — run the co-change gate, echo fired|clean.
# CI env is stripped first: `make test-hooks` itself runs under GITHUB_EVENT_NAME on
# CI, and a test that inherited the workflow's own event payload would be measuring
# the harness instead of the script.
gate() {
  local d="$1"; shift
  if env -u GITHUB_EVENT_NAME -u GITHUB_EVENT_PATH -u GITHUB_BASE_REF \
        -u PLATFORM_TARGETS_BASE_REF "$@" \
        bash "$CHECK" "$d" --require-co-change >/dev/null 2>&1; then
    echo clean
  else
    echo fired
  fi
}

# push_event <repo> <before-sha> — a minimal GitHub `push` event payload file.
push_event() {
  local f
  f="$(mktemp "$TMP/event.XXXXXX")"
  jq -n --arg b "$2" '{before: $b}' > "$f"
  printf '%s\n' "$f"
}

# registry <repo> <status> <notes> — a minimal schema_version 2 capability registry,
# the real shape: platform -> surfaces -> capabilities -> status. Written whole rather
# than appended to, because the point of these cases is what the JSON *means*.
registry() {
  local d="$1"
  mkdir -p "$d/core/capabilities"
  jq -n --arg s "$2" --arg n "$3" '{
    schema_version: 2,
    platforms: { codex: { display_name: "Codex", surfaces: { codex: {
      support: "supported",
      capabilities: { subagents: { status: $s, notes: $n } }
    } } } }
  }' > "$d/core/capabilities/platforms.json"
}

# commit_all <repo> <message> — commit whatever is in the tree.
commit_all() {
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
}

# --- BUG 1: the range must cover the whole push/PR, not just its last commit ------

section "diff range — a violation in an earlier commit of the push"

d="$(new_repo range-push)"
base="$(git -C "$d" rev-parse HEAD)"
# The violation is in the FIRST commit; the tip is innocent. HEAD~1..HEAD sees only
# the tip and reports success.
commit "$d" "watched path, no platform-targets" 'skills/repo/repo-standards/SKILL.md'
commit "$d" "unrelated tip commit" 'docs/notes.md'

judge "push event: violation in an earlier commit is caught" fired \
  "$(gate "$d" GITHUB_EVENT_NAME=push GITHUB_EVENT_PATH="$(push_event "$d" "$base")")"

judge "explicit base ref: violation in an earlier commit is caught" fired \
  "$(gate "$d" PLATFORM_TARGETS_BASE_REF="$base")"

d2="$(new_repo range-pr)"
git -C "$d2" checkout -q -b feature
commit "$d2" "watched path, no platform-targets" 'skills/documentation/platform-sync/SKILL.md'
commit "$d2" "unrelated tip commit" 'docs/notes.md'

judge "pull_request event: whole branch is inspected, not just the tip" fired \
  "$(gate "$d2" GITHUB_EVENT_NAME=pull_request GITHUB_BASE_REF=master)"

section "diff range — the same range must stay quiet when the change is complete"

d3="$(new_repo range-clean)"
base3="$(git -C "$d3" rev-parse HEAD)"
commit "$d3" "watched path" 'skills/repo/repo-standards/SKILL.md'
commit "$d3" "co-changed platform targets" "$TARGETS"
commit "$d3" "unrelated tip commit" 'docs/notes.md'

judge "watched path + platform-targets.json across the range passes" clean \
  "$(gate "$d3" GITHUB_EVENT_NAME=push GITHUB_EVENT_PATH="$(push_event "$d3" "$base3")")"

d4="$(new_repo range-untouched)"
base4="$(git -C "$d4" rev-parse HEAD)"
commit "$d4" "nothing watched" 'docs/notes.md'
commit "$d4" "still nothing watched" 'docs/more-notes.md'

judge "a range touching no watched path passes" clean \
  "$(gate "$d4" GITHUB_EVENT_NAME=push GITHUB_EVENT_PATH="$(push_event "$d4" "$base4")")"

section "diff range — no CI env still falls back to HEAD~1"

d5="$(new_repo range-local)"
commit "$d5" "watched path, no platform-targets" 'core/capabilities/platforms.json'
judge "local run with no CI env still catches a tip-commit violation" fired \
  "$(gate "$d5")"

d6="$(new_repo range-local-clean)"
commit "$d6" "unrelated" 'docs/notes.md'
judge "local run with no CI env passes on an unwatched tip commit" clean \
  "$(gate "$d6")"

d7="$(new_repo range-zero-before)"
commit "$d7" "watched path, no platform-targets" 'core/capabilities/platforms.json'
judge "branch-creation push (all-zero before-SHA) degrades to HEAD~1" fired \
  "$(gate "$d7" GITHUB_EVENT_NAME=push \
       GITHUB_EVENT_PATH="$(push_event "$d7" 0000000000000000000000000000000000000000)")"

# --- BUG 2: a watched path is a literal path, not a regex -------------------------

section "path matching — '.' must not match any character"

d8="$(new_repo regex-file)"
# `^core/capabilities/platforms.json` as a REGEX matches this path: the `.` before
# `json` matches the `_`. It is neither the watched file nor inside a watched dir.
commit "$d8" "path that only matches the regex" 'core/capabilities/platforms_json.txt'
judge "platforms_json.txt does not trip the platforms.json watch" clean "$(gate "$d8")"

d9="$(new_repo regex-file-real)"
commit "$d9" "the real watched file" 'core/capabilities/platforms.json'
judge "the real platforms.json still trips the watch" fired "$(gate "$d9")"

d10="$(new_repo regex-md)"
# `skills/repo/_contract/references/platform-specs.md` -> the `.` before `md` again.
commit "$d10" "regex-only match on platform-specs.md" \
  'skills/repo/_contract/references/platform-specsXmd'
judge "platform-specsXmd does not trip the platform-specs.md watch" clean "$(gate "$d10")"

d11="$(new_repo regex-md-real)"
commit "$d11" "the real platform-specs.md" \
  'skills/repo/_contract/references/platform-specs.md'
judge "the real platform-specs.md still trips the watch" fired "$(gate "$d11")"

section "path matching — directory prefixes vs exact files"

d12="$(new_repo dir-prefix)"
commit "$d12" "file inside a watched directory" 'docs/user/install/claude-desktop.md'
judge "a file under a watched directory trips the watch" fired "$(gate "$d12")"

d13="$(new_repo dir-sibling)"
# `docs/user/install/` is a DIRECTORY entry: a sibling file whose name merely starts
# with the same characters is not inside it.
commit "$d13" "sibling of a watched directory" 'docs/user/install-notes.md'
judge "a sibling path sharing the directory's prefix does not trip it" clean \
  "$(gate "$d13")"

d14="$(new_repo file-prefix)"
# `core/capabilities/platforms.json` is an EXACT file entry, not a prefix.
commit "$d14" "backup beside a watched file" 'core/capabilities/platforms.json.bak'
judge "platforms.json.bak does not trip the exact-file watch" clean "$(gate "$d14")"

section "registry watch — the question is whether a CLAIM changed, not whether bytes did"

d15="$(new_repo registry-notes)"
registry "$d15" unknown "the original explanation"
commit_all "$d15" "registry at base"
registry "$d15" unknown "a better sourced explanation — same status, same claim"
commit_all "$d15" "notes-only correction"
judge "a notes-only registry edit does not demand a derived-doc co-change" clean \
  "$(gate "$d15")"

# Paired positive control: a "fix" that simply stops watching the registry fails here.
d16="$(new_repo registry-status)"
registry "$d16" native "measured"
commit_all "$d16" "registry at base"
registry "$d16" unknown "demoted — the evidence did not survive checking"
commit_all "$d16" "capability demotion"
judge "a capability STATUS change still demands the co-change" fired "$(gate "$d16")"

d17="$(new_repo registry-status-cochanged)"
registry "$d17" native "measured"
commit_all "$d17" "registry at base"
registry "$d17" unknown "demoted"
mkdir -p "$d17/$(dirname "$TARGETS")"
printf 'refreshed\n' >> "$d17/$TARGETS"
commit_all "$d17" "demotion plus refreshed platform targets"
judge "a status change with platform-targets.json co-changed passes" clean \
  "$(gate "$d17")"

d18="$(new_repo registry-surface)"
registry "$d18" unknown "note"
commit_all "$d18" "registry at base"
jq '.platforms.codex.surfaces.codex.support = "unverified"' \
  "$d18/core/capabilities/platforms.json" > "$d18/core/capabilities/platforms.json.new"
mv "$d18/core/capabilities/platforms.json.new" "$d18/core/capabilities/platforms.json"
commit_all "$d18" "surface dropped to unverified"
judge "dropping a surface still demands the co-change" fired "$(gate "$d18")"

section "registry watch — a projection that cannot be made must not read as 'no change'"

d19="$(new_repo registry-added)"
registry "$d19" unknown "note"
commit_all "$d19" "registry added in this change"
judge "a registry absent at base cannot be projected, so the gate still fires" fired \
  "$(gate "$d19")"

d20="$(new_repo registry-v1)"
mkdir -p "$d20/core/capabilities"
# schema_version 1 is flat — no `surfaces`, so the status projection comes back as `{}`
# for both sides and a bare emptiness test would compare them EQUAL. Equal-because-
# unreadable is exactly the defect this gate is supposed to be free of; it must degrade
# to the byte answer instead.
jq -n '{schema_version: 1,
        platforms: {codex: {capabilities: {subagents: {status: "unknown", notes: "a"}}}}}' \
  > "$d20/core/capabilities/platforms.json"
commit_all "$d20" "v1 registry at base"
jq -n '{schema_version: 1,
        platforms: {codex: {capabilities: {subagents: {status: "unknown", notes: "b"}}}}}' \
  > "$d20/core/capabilities/platforms.json"
commit_all "$d20" "v1 registry, notes-only edit"
judge "a schema_version 1 registry cannot be projected, so it falls back to firing" \
  fired "$(gate "$d20")"

harness_summary
