#!/usr/bin/env bash
# check-doc-claims.sh — assert prose claims match the repo they describe.
#
# Usage:
#   check-doc-claims.sh [repo-root]
#   check-doc-claims.sh --expected      # print the numbers the docs must state, then exit
#   check-doc-claims.sh -h | --help
#
# Three classes of claim rot this catches, all observed in this repo:
#
#   1. Skill count. "26 skills" is asserted in README, CLAUDE.md, AGENTS.md and every
#      per-target install guide, and "26 bundled skills" in every plugin/marketplace
#      manifest description — the string users see in the install UI. Adding one skill
#      silently falsifies all of them, and nothing failed: AGENTS.md sat at "25 skills"
#      across two releases, and the manifests drifted twice for the same reason. Every
#      count is computed from the filesystem; no expected value is hardcoded anywhere in
#      this script, so adding a skill moves the requirement automatically.
#   2. Target count. "four supported targets" is prose that a fifth target falsifies.
#      The number of supported targets is counted from platform-targets.json.
#   3. Target coverage. Every target in platform-targets.json supported_targets must be
#      named in README, AGENTS.md and CLAUDE.md by the display_name the capability
#      registry gives it, and must declare an install_doc that exists. A target added to
#      the JSON but missing from the prose is invisible to users.
#
# A target whose validated_against is "unknown" is declared but not yet validated: its
# prose and install-guide requirements are warnings until a real version is recorded,
# matching check-platform-targets.sh. Everything else is a hard failure.
#
# Only *prose* is scanned. Fenced code blocks, indented code blocks, inline backtick spans
# and double-quoted counts are evidence, not assertions about the current tree: a doc that
# quotes measured output ("Doc claims check passed (27 skills...)" from a baseline run), a
# changelog quoting an old value, or a tutorial transcript is a point-in-time record, and
# "fixing" its numbers would falsify it. Without this rule the checker pressures every such
# document into corruption. Verify both halves of the rule with --self-test.
#
# Exit 0 if checks pass; 1 on failure.
set -euo pipefail

usage() {
  sed -n '2,28p' "$0" | sed -E 's/^# ?//'
  exit "${1:-0}"
}
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

EXPECTED_ONLY=false
SELF_TEST=false
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --expected) EXPECTED_ONLY=true ;;
    --self-test) SELF_TEST=true ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *) ARGS+=("$arg") ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${ARGS[0]:-.}" && pwd)"
FAILED=0
TARGETS_JSON="$ROOT/docs/engineering/build-and-release/platform-targets.json"
REGISTRY="$ROOT/core/capabilities/platforms.json"

# The registry is rooted at the platform and lists its runtime surfaces underneath;
# the checks here are per-surface, so read the flattened one-entry-per-surface view.
#
# Resolve the library from THIS SCRIPT's directory, not from $ROOT. $ROOT is the tree being
# audited, and this script is run against other repos (repo-standards points it at a target)
# and against synthetic roots (--self-test). Sourcing a tool's own library out of the tree it
# is inspecting only works while the two happen to be the same checkout: everywhere else the
# `.` fails under `set -e` and the run dies before a single claim is checked. That is why
# --self-test reported 5 of 7 cases failing for a reason none of them were testing.
# shellcheck source=scripts/lib/registry.sh
. "$SCRIPT_DIR/lib/registry.sh"
REGISTRY="$(registry_flat_tmp "$REGISTRY")"
trap 'rm -f "$REGISTRY"' EXIT

err() { echo "ERROR: $*" >&2; FAILED=$(( FAILED + 1 )); }
warn() { echo "WARN: $*" >&2; }

# Number words, so "four supported targets" is checkable prose rather than a blind spot.
number_word() {
  case "$1" in
    1) echo "one" ;; 2) echo "two" ;; 3) echo "three" ;; 4) echo "four" ;;
    5) echo "five" ;; 6) echo "six" ;; 7) echo "seven" ;; 8) echo "eight" ;;
    9) echo "nine" ;; 10) echo "ten" ;; *) echo "" ;;
  esac
}

# Emit "file:line:text" for prose lines only — fenced blocks, indented code blocks and
# inline code spans stripped. $1 is the root, $2 the find -name pattern.
prose_lines() {
  local root="$1" pattern="$2"
  find "$root" -name "$pattern" -type f \
    -not -path '*/.git/*' -not -path '*/node_modules/*' \
    -not -path '*_contract/fixtures/*' -not -path '*/session-files/*' 2>/dev/null \
  | while IFS= read -r f; do
      awk -v fname="${f#"$root"/}" '
        # A fence line toggles the state and is itself never a claim. Matches ``` and ~~~
        # with any info string (```bash, ```jsonc).
        /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
        fence { next }
        # Indented code block: four spaces or a tab at line start.
        /^(    |\t)/ { next }
        {
          line = $0
          # Inline code spans are quoted evidence for the same reason fences are.
          gsub(/`[^`]*`/, "", line)
          print fname ":" FNR ":" line
        }
      ' "$f"
    done
}

# A count inside double quotes is being *reported*, not asserted — changelog entries
# quote the stale value they fixed ("16 skills in 7 domains"). Skip those; a real claim
# is written as bare prose.
is_quoted() { [[ "$1" =~ \"[^\"]*[0-9]+\ (bundled\ )?skills[^\"]*\" ]]; }

# --- self-test ---
# The code-block exemption must not become a hole real drift can hide in. These cases pin
# both halves: a stale count in ordinary prose still fails, and the same stale number as
# quoted evidence still passes. Run: check-doc-claims.sh --self-test
if [[ "$SELF_TEST" == true ]]; then
  st_root="$(mktemp -d)"
  trap 'rm -rf "$st_root"' EXIT
  mkdir -p "$st_root/skills/a" "$st_root/skills/b" "$st_root/skills/c"
  for d in a b c; do printf -- '---\nname: %s\n---\n' "$d" >"$st_root/skills/$d/SKILL.md"; done
  # Tree ships 3 skills. Every case below writes the wrong number, 27.

  # A one-target platform record, so the validated-version cases below have something to
  # assert against. install_doc must point at a file that exists, or section 3 would fail
  # every case for a reason that has nothing to do with what the case is testing.
  mkdir -p "$st_root/docs/engineering/build-and-release" "$st_root/docs/user/install"
  : >"$st_root/docs/user/install/cursor.md"
  cat >"$st_root/docs/engineering/build-and-release/platform-targets.json" <<'ST_JSON'
{
  "supported_targets": ["cursor"],
  "targets": {
    "cursor": {
      "display_name": "Cursor IDE",
      "validated_against": "3.18.9",
      "install_doc": "docs/user/install/cursor.md"
    }
  }
}
ST_JSON

  st_pass=0 st_fail=0
  st_case() {
    local name="$1" want="$2" body="$3"
    printf '%s\n' "$body" >"$st_root/DOC.md"
    local got=0
    bash "$0" "$st_root" >/dev/null 2>&1 || got=1
    if [[ "$got" == "$want" ]]; then
      echo "  ok    $name (expected $( [[ $want == 1 ]] && echo fail || echo pass ))"
      st_pass=$(( st_pass + 1 ))
    else
      echo "  FAIL  $name — expected exit $want, got $got" >&2
      st_fail=$(( st_fail + 1 ))
    fi
  }

  echo "check-doc-claims self-test (tree ships 3 skills; every case writes 27):"
  st_case "stale count in prose"            1 'This plugin bundles 27 skills.'
  st_case "stale count in a fenced block"   0 'Baseline measurement:

```
$ bash scripts/check-doc-claims.sh <baseline>
Doc claims check passed (27 skills, targets consistent)
```

Recorded verbatim.'
  st_case "stale count in a ~~~ fence"      0 'Output:

~~~text
27 skills counted
~~~'
  st_case "stale count in an indented block" 0 'Output was:

    Doc claims check passed (27 skills)

as recorded.'
  st_case "stale count in inline backticks" 0 'The baseline reported `27 skills` before the fix.'
  st_case "stale count double-quoted"       0 'The old string was "27 skills in 7 domains".'
  st_case "prose after a closed fence"      1 '```
27 skills
```

The tree ships 27 skills today.'

  # Section 4: the record pins cursor at 3.18.9.
  st_case "stale validated version in prose"  1 '| Cursor IDE | IDE | supported - validated 3.16.17 |'
  st_case "correct validated version in prose" 0 '| Cursor IDE | IDE | supported - validated 3.18.9 |'
  st_case "stale validated version in a fence" 0 'Recorded output:

```
Cursor IDE — validated 3.16.17
```
'

  echo "self-test: $st_pass passed, $st_fail failed"
  (( st_fail == 0 )) || exit 1
  exit 0
fi

# --- computed truth ---
# Shipped skills = SKILL.md under skills/, excluding contract test fixtures.
actual=$(find "$ROOT/skills" -name SKILL.md 2>/dev/null \
         | grep -v '_contract/fixtures' | wc -l | tr -d ' ')

target_count=0
if [[ -f "$TARGETS_JSON" ]]; then
  target_count=$(jq -r '(.supported_targets // []) | length' "$TARGETS_JSON" 2>/dev/null || echo 0)
fi
target_word=$(number_word "$target_count")

# Display names come from the capability registry so there is exactly one spelling of
# each platform in the repo; platform-targets.json is the fallback for repos without one.
display_name() {
  local key="$1" name=""
  if [[ -f "$REGISTRY" ]]; then
    name=$(jq -r --arg k "$key" '.platforms[$k].display_name // empty' "$REGISTRY" 2>/dev/null || true)
  fi
  if [[ -z "$name" && -f "$TARGETS_JSON" ]]; then
    name=$(jq -r --arg k "$key" '.targets[$k].display_name // empty' "$TARGETS_JSON" 2>/dev/null || true)
  fi
  [[ -n "$name" ]] || name="$key"
  echo "$name"
}

if [[ "$EXPECTED_ONLY" == true ]]; then
  echo "skills: $actual"
  echo "supported_targets: $target_count (\"$target_word\")"
  if [[ -f "$TARGETS_JSON" ]]; then
    for key in $(jq -r '(.supported_targets // []) | .[]' "$TARGETS_JSON"); do
      echo "target: $key -> $(display_name "$key")"
    done
  fi
  exit 0
fi

# --- 1. Skill count ---
if [[ "$actual" == "0" ]]; then
  err "found 0 shipped skills under skills/ — refusing to validate counts against an empty tree"
else
  while IFS= read -r hit; do
    file="${hit%%:*}"
    is_quoted "$hit" && continue
    claimed=$(sed -E 's/.*[^0-9]([0-9]+) skills.*/\1/' <<<"$hit")
    [[ "$claimed" =~ ^[0-9]+$ ]] || continue
    if [[ "$claimed" != "$actual" ]]; then
      err "$file claims $claimed skills; the tree ships $actual"
    fi
  done < <(prose_lines "$ROOT" '*.md' | grep -E '[0-9]+ skills' || true)

  # Manifest descriptions carry the same claim as "N bundled skills". These render in
  # the plugin install UI, so a stale count is user-visible on every target.
  while IFS= read -r hit; do
    file="${hit%%:*}"
    claimed=$(sed -E 's/.*[^0-9]([0-9]+) bundled skills.*/\1/' <<<"$hit")
    [[ "$claimed" =~ ^[0-9]+$ ]] || continue
    if [[ "$claimed" != "$actual" ]]; then
      err "${file#"$ROOT"/} claims $claimed bundled skills; the tree ships $actual"
    fi
  done < <(grep -rn -E '[0-9]+ bundled skills' "$ROOT" --include='*.json' 2>/dev/null \
             | grep -v '/.git/' | grep -v '_contract/fixtures' || true)
fi

# --- 2. Target count in prose ---
if (( target_count > 0 )) && [[ -n "$target_word" ]]; then
  while IFS= read -r hit; do
    file="${hit%%:*}"
    # A count in double quotes is being reported, not asserted (skill prose quoting the
    # stale value it warns about). Same rule as the skill count above.
    [[ "$hit" =~ \"[^\"]*(one|two|three|four|five|six|seven|eight|nine|ten)\ supported\ targets[^\"]*\" ]] && continue
    claimed_word=$(sed -E 's/.*[^a-z](one|two|three|four|five|six|seven|eight|nine|ten) supported targets.*/\1/' <<<"$hit")
    [[ -n "$claimed_word" ]] || continue
    if [[ "$claimed_word" != "$target_word" ]]; then
      err "$file says '$claimed_word supported targets'; platform-targets.json declares $target_count ('$target_word')"
    fi
  done < <(prose_lines "$ROOT" '*.md' | grep -v 'CHANGELOG' \
             | grep -E '(one|two|three|four|five|six|seven|eight|nine|ten) supported targets' || true)
fi

# --- 3. Target coverage ---
if [[ -f "$TARGETS_JSON" ]]; then
  jq empty "$TARGETS_JSON" 2>/dev/null || err "$TARGETS_JSON: invalid JSON"

  targets=$(jq -r '(.supported_targets // []) | .[]' "$TARGETS_JSON" 2>/dev/null || true)
  for key in $targets; do
    name=$(display_name "$key")
    unvalidated=false
    [[ "$(jq -r ".targets.\"$key\".validated_against // empty" "$TARGETS_JSON")" == "unknown" ]] && unvalidated=true

    # Docs legitimately use the short form of a proper name ("Codex" for "Codex CLI").
    # Either spelling proves the target is discoverable.
    short="${name% CLI}"
    for doc in README.md AGENTS.md CLAUDE.md; do
      [[ -f "$ROOT/$doc" ]] || continue
      if ! grep -qF "$name" "$ROOT/$doc" && ! grep -qF "$short" "$ROOT/$doc"; then
        if [[ "$unvalidated" == true ]]; then
          warn "$doc never names declared target '$name' (warning only while validated_against is \"unknown\")"
        else
          err "$doc never names supported target '$name' — users cannot discover it"
        fi
      fi
    done

    # install_doc must be declared and must exist.
    install_doc=$(jq -r ".targets.\"$key\".install_doc // empty" "$TARGETS_JSON")
    if [[ -z "$install_doc" ]]; then
      err "platform-targets.json: target '$key' declares no install_doc"
    elif [[ ! -f "$ROOT/$install_doc" ]]; then
      if [[ "$unvalidated" == true ]]; then
        warn "platform-targets.json: declared target '$key' install_doc '$install_doc' does not exist yet (warning only while validated_against is \"unknown\")"
      else
        err "platform-targets.json: target '$key' install_doc points at missing file '$install_doc'"
      fi
    fi
  done
fi

# --- 4. Validated version in prose ---
# The README's per-target badges are generated from platform-targets.json, but the prose
# table beside them is hand-written -- and a hand-typed version drifts silently, because
# nothing derived it. The Cursor row read "validated 3.16.17" for two minor versions while
# the badge three lines above it correctly said 3.18.9, and every check passed the whole
# time: the badge was asserted, the target count was asserted, the version in the sentence
# was not. Assert the prose against the same record the badge is built from.
if [[ -f "$TARGETS_JSON" ]]; then
  # Gather the candidate lines once; re-walking every *.md per target is needless work.
  version_lines=$(prose_lines "$ROOT" '*.md' | grep -v 'CHANGELOG' \
                    | grep -E 'validated [0-9]+\.[0-9]+\.[0-9]+' || true)
  if [[ -n "$version_lines" ]]; then
    for key in $(jq -r '(.supported_targets // []) | .[]' "$TARGETS_JSON" 2>/dev/null || true); do
      pinned=$(jq -r ".targets.\"$key\".validated_against // empty" "$TARGETS_JSON")
      # "unknown" is the honest state for a declared-but-unvalidated target: nothing to assert.
      [[ -n "$pinned" && "$pinned" != "unknown" ]] || continue
      name=$(display_name "$key")
      short="${name% CLI}"
      while IFS= read -r hit; do
        file="${hit%%:*}"
        rest="${hit#*:}"; lineno="${rest%%:*}"; text="${rest#*:}"
        # Only judge a line that actually names this target.
        [[ "$text" == *"$name"* || "$text" == *"$short"* ]] || continue
        claimed=$(sed -E 's/.*validated ([0-9]+\.[0-9]+\.[0-9]+).*/\1/' <<<"$text")
        [[ "$claimed" != "$text" ]] || continue
        if [[ "$claimed" != "$pinned" ]]; then
          err "$file:$lineno says '$name ... validated $claimed'; platform-targets.json pins $pinned"
        fi
      done <<<"$version_lines"
    done
  fi
fi

if (( FAILED > 0 )); then
  echo "Doc claims check failed ($FAILED error(s))" >&2
  echo "Expected values: bash $(basename "$0") --expected" >&2
  exit 1
fi

echo "Doc claims check passed ($actual skills, $target_count supported targets, coverage consistent)"
