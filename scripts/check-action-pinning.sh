#!/usr/bin/env bash
# check-action-pinning.sh — fail when a workflow trusts a mutable action ref.
#
# WHY THIS EXISTS
#   `uses: actions/checkout@v7` does not name a version. It names a tag, and a
#   tag is a pointer the action's owner can move at any time — `v7` pointed at
#   v7.0.0 when a workflow was written and at v7.0.1 a week later, with no commit
#   in this repository and no PR to review. That is a third party's write access
#   to this repo's CI, and the whole point of `permissions:` blocks and secret
#   scanning is undone by it. A 40-character commit SHA is immutable; the
#   `# v7.0.0` comment beside it is what keeps it readable, and what Dependabot
#   rewrites when it proposes a bump.
#
#   `.github/workflows/ci.yml` already did this correctly. `release.yml` did not,
#   and nothing noticed, because the standard was practised rather than checked —
#   which is the same failure mode as a validator nobody runs.
#
#   The gold fixtures matter more than either. `skills/repo/_contract/fixtures/`
#   is copied into every repository scaffolded from this plugin, so an unpinned
#   `uses:` there is not one repo's problem; it is the default every future repo
#   inherits. The same is true of `skills/repo/_contract/templates/`, which is
#   what repo-scaffold actually renders -- and which the first version of this
#   script could not see, because it scanned a list of roots its author wrote
#   from memory. It now scans the whole repository. A checker must not decide its
#   verdict by where it happened to look.
#
# WHAT IS SCANNED
#   Every *.yml, *.yaml, *.tmpl and *.md in the tree (.git, node_modules and
#   .venv pruned). `.tmpl` because scaffold templates are workflows before they
#   are rendered; `.md` because template documentation carries real workflow
#   bodies in fenced blocks -- and ONLY fenced blocks there, since prose about a
#   mutable ref is not a mutable ref.
#
# WHAT COUNTS AS PINNED
#   uses: owner/repo@<40 hex>              — pinned
#   uses: owner/repo@<40 hex> # v7.0.0     — pinned, and readable. Preferred.
#   uses: owner/repo@v7                    — NOT pinned: a movable tag
#   uses: owner/repo@main                  — NOT pinned: a branch
#
# WHAT PASSES WITHOUT A 40-CHAR COMMIT SHA, AND WHY
#   (the old heading was "WHAT IS EXEMPT", which is what let a docker entry
#   describing itself as exempt sit above code that failed the build)
#   ./path            a local action in this same repository — it moves only when
#                     this repo moves, so there is nothing external to pin.
#   docker://...@sha256:<64 hex>
#                     a digest-pinned image — immutable, same guarantee as a
#                     commit SHA, so it passes. Any other docker ref
#                     (`docker://img:v1`, `docker://img:latest`) is a movable
#                     tag and FAILS. The earlier version of
#                     this header said "reported, not failed" while the code
#                     reported unconditionally and every finding exits 1 — so a
#                     correctly digest-pinned ref was told to pin by digest. A
#                     check whose correction does not clear it is what drives
#                     someone to add the path-shaped carve-out warned about
#                     below.
#   action-pin-ok:    an explicit, readable waiver — but only in the comment
#                     part of the line, after a `#`. A path-shaped carve-out is
#                     how the mutable ref creeps back; a waiver that matches
#                     anywhere on the line lets an action called
#                     `owner/action-pin-ok` waive itself.
#
# Usage: check-action-pinning.sh [<repo_root>] [--self-test]
# Exit:  0 clean · 1 mutable refs found · 2 usage/environment
set -uo pipefail

ROOT="."
SELF_TEST=0
# Resolved before any cd, because the self-test re-invokes this script.
case "$0" in /*) SELF="$0" ;; *) SELF="$PWD/$0" ;; esac
for arg in "$@"; do
  case "$arg" in
    --self-test) SELF_TEST=1 ;;
    # Print the header block itself, not a line range. A hardcoded '2,36p'
    # silently truncates the moment the header grows -- the help text quietly
    # ceasing to describe the script is the same defect this script exists for.
    -h|--help) sed -n '2,${/^#/!q;p;}' "$0" | sed 's/^#[ ]\{0,1\}//'; exit 0 ;;
    -*) echo "check-action-pinning.sh: unknown option '$arg'" >&2; exit 2 ;;
    *) ROOT="$arg" ;;
  esac
done

# scan <dir> — every "path:line:ref" whose ref is not a 40-hex SHA.
# Prints nothing when clean. Never fails the shell; the caller decides.
scan() {
  local dir="$1" f line trimmed n ref md fence digest
  [ -d "$dir" ] || return 0
  while IFS= read -r f; do
    n=0; fence=0
    case "$f" in *.md) md=1 ;; *) md=0 ;; esac
    while IFS= read -r line; do
      n=$((n + 1))
      trimmed="${line#"${line%%[![:space:]]*}"}"

      # In Markdown, only fenced blocks are configuration; everything else is
      # prose ABOUT configuration. Without this, CHANGELOG.md's own entry
      # explaining that `uses: actions/checkout@v7` names a movable tag is
      # reported as a movable tag.
      if [ "$md" -eq 1 ]; then
        case "$trimmed" in '```'*|'~~~'*) fence=$((1 - fence)); continue ;; esac
        [ "$fence" -eq 1 ] || continue
      fi

      # The waiver must live in a comment, not merely somewhere on the line.
      # `*action-pin-ok:*` is the same substring match that made `causes:` parse
      # as a step: an action whose own name carries the token -- say
      # `uses: owner/action-pin-ok@v1` -- would waive itself and never be
      # reported. Only the text after the first `#` can waive.
      case "$line" in
        *'#'*) case "${line#*#}" in *action-pin-ok:*) continue ;; esac ;;
      esac

      # `uses:` must be the YAML key, not a substring. Globbing *uses:* anywhere
      # on the line makes "**Common errors and their causes:**" parse as a step
      # -- ca-uses:. Found by running this against the tree, not the fixtures.
      case "$trimmed" in '- '*) trimmed="${trimmed#- }"; trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}" ;; esac
      case "$trimmed" in
        uses:*) ref="${trimmed#uses:}" ;;
        *) continue ;;
      esac
      ref="${ref%%#*}"
      ref="$(printf '%s' "$ref" | tr -d " \"'" )"
      [ -n "$ref" ] || continue
      case "$ref" in
        ./*|.\\*) continue ;;                    # local action: nothing external
        # A docker image is pinned the same way an action is, by an immutable
        # identifier; only the syntax differs (`@sha256:<64 hex>`, not a
        # 40-char commit SHA). Route it through that test rather than
        # reporting every docker ref -- an unconditional report fails a ref
        # that is already correct, and tells you to do the thing you just did.
        docker://*)
          digest="${ref##*@sha256:}"
          if [ "$digest" != "$ref" ] && [ ${#digest} -eq 64 ] \
             && [ -z "$(printf '%s' "$digest" | tr -d 'a-f0-9')" ]; then
            continue
          fi
          printf '%s:%s:%s (docker ref — pin by @sha256:<digest>)\n' "$f" "$n" "$ref"
          continue ;;
      esac
      case "$ref" in
        *@*) : ;;
        *) printf '%s:%s:%s (no ref at all)\n' "$f" "$n" "$ref"; continue ;;
      esac
      case "${ref##*@}" in
        [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) : ;;
        *) printf '%s:%s:%s\n' "$f" "$n" "$ref" ;;
      esac
    done < "$f"
  done < <(find "$dir" \( -name .git -o -name node_modules -o -name .venv \) -prune -o \
           \( -name '*.yml' -o -name '*.yaml' -o -name '*.tmpl' -o -name '*.md' \) \
           -type f -print 2>/dev/null | sort)
}

# --- positive control ------------------------------------------------------
# A checker that has never been shown to fail is indistinguishable from one that
# cannot. This builds both a violating workflow and its corrected twin.
self_test() {
  local tmp rc=0 out planted_rc
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/bad" "$tmp/good"

  cat > "$tmp/bad/w.yml" <<'YML'
jobs:
  a:
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@main
      - uses: ./.github/actions/local
      - uses: some/act@1111111111111111111111111111111111111111 # v1.2.3
      - uses: waived/act@v2 # action-pin-ok: vendor publishes no SHA
      - uses: docker://ghcr.io/owner/action-pin-ok:v1
      - uses: docker://ghcr.io/owner/pinned@sha256:2222222222222222222222222222222222222222222222222222222222222222
      - uses: docker://ghcr.io/owner/shortdigest@sha256:abc123
YML
  out="$(scan "$tmp/bad")"
  [ "$(printf '%s\n' "$out" | grep -c 'checkout@v7')" = 1 ] \
    || { echo "  self-test: movable tag not caught" >&2; rc=1; }
  [ "$(printf '%s\n' "$out" | grep -c 'setup-node@main')" = 1 ] \
    || { echo "  self-test: branch ref not caught" >&2; rc=1; }
  [ "$(printf '%s\n' "$out" | grep -c 'actions/local')" = 0 ] \
    || { echo "  self-test: local action wrongly flagged" >&2; rc=1; }
  [ "$(printf '%s\n' "$out" | grep -c 'some/act')" = 0 ] \
    || { echo "  self-test: SHA-pinned ref wrongly flagged" >&2; rc=1; }
  [ "$(printf '%s\n' "$out" | grep -c 'waived/act')" = 0 ] \
    || { echo "  self-test: action-pin-ok waiver ignored" >&2; rc=1; }
  [ "$(printf '%s\n' "$out" | grep -c 'owner/action-pin-ok')" = 1 ] \
    || { echo "  self-test: waiver token in the ref itself waived the line" >&2; rc=1; }
  # The docker branch used to print unconditionally, so a ref that is already
  # digest-pinned was reported and told to pin by digest. A check whose own
  # remedy does not clear it teaches people to carve paths out instead.
  [ "$(printf '%s\n' "$out" | grep -c 'owner/pinned')" = 0 ] \
    || { echo "  self-test: digest-pinned docker ref wrongly flagged" >&2; rc=1; }
  # ...and the digest test must be the real one: 64 lowercase hex, not merely
  # the presence of the literal '@sha256:'. A truncated digest is not a pin.
  [ "$(printf '%s\n' "$out" | grep -c 'owner/shortdigest')" = 1 ] \
    || { echo "  self-test: truncated docker digest accepted as a pin" >&2; rc=1; }
  [ "$(printf '%s\n' "$out" | grep -c 'docker ref')" = 2 ] \
    || { echo "  self-test: docker findings not reported as docker refs" >&2; rc=1; }

  # --- cases the fixtures did not have, and the real tree did -----------------
  # Each of these three was a live false positive, found by running the detector
  # against this repository rather than against what its author imagined.
  cat > "$tmp/bad/prose.md" <<'MD'
- `uses: actions/checkout@v7` names a tag, not a version. Do not copy this line.
A doc may also show the bare key in prose, like so:

uses: prose/unfenced@v2

```yaml
      - uses: prose/fenced@v9
```
MD
  cat > "$tmp/bad/sub.yml" <<'YML'
# comment mentioning uses: commented/out@v3 which is not a step
steps:
  - name: notes
    run: echo "**Common errors and their causes:**"
YML
  cat > "$tmp/bad/t.yml.tmpl" <<'TMPL'
jobs:
  a:
    steps:
      - uses: tmpl/act@v1
TMPL
  out="$(scan "$tmp/bad")"
  [ "$(printf '%s\n' "$out" | grep -c 'checkout@v7')" = 1 ] \
    || { echo "  self-test: markdown PROSE wrongly flagged (or bad/w.yml missed)" >&2; rc=1; }
  [ "$(printf '%s\n' "$out" | grep -c 'prose/fenced')" = 1 ] \
    || { echo "  self-test: fenced markdown block not scanned" >&2; rc=1; }
  [ "$(printf '%s\n' "$out" | grep -c 'prose/unfenced')" = 0 ] \
    || { echo "  self-test: unfenced markdown prose read as a step" >&2; rc=1; }
  # sub.yml contains NO step at all: a YAML comment naming a ref, and a run: line
  # ending in "causes:". Any finding from it is a false positive, whatever it says
  # -- assert on the file, not on the text, because the report prints the extracted
  # ref and never the source line.
  [ "$(printf '%s\n' "$out" | grep -c 'sub.yml')" = 0 ] \
    || { echo "  self-test: false positive in a file with no steps" >&2; rc=1; }
  [ "$(printf '%s\n' "$out" | grep -c 'tmpl/act')" = 1 ] \
    || { echo "  self-test: .tmpl scaffold template not scanned" >&2; rc=1; }

  cat > "$tmp/good/w.yml" <<'YML'
jobs:
  a:
    steps:
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
YML
  [ -z "$(scan "$tmp/good")" ] \
    || { echo "  self-test: corrected workflow still flagged" >&2; rc=1; }

  # Everything above calls scan() directly, so none of it exercises the ROOT the
  # top level actually scans: revert `scan "."` to `scan ".github/workflows"` and
  # every assertion so far stays green. That is exactly the half that hid 18
  # mutable refs in the scaffold templates, so it needs an end-to-end case --
  # re-run this script against a planted tree whose only unpinned ref lives
  # outside .github, and require it to fail.
  mkdir -p "$tmp/tree/.github/workflows" "$tmp/tree/templates"
  cat > "$tmp/tree/.github/workflows/ci.yml" <<'YML'
jobs:
  a:
    steps:
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
YML
  cat > "$tmp/tree/templates/scaffold.yml.tmpl" <<'TMPL'
jobs:
  a:
    steps:
      - uses: outside/dot-github@v1
TMPL
  bash "$SELF" "$tmp/tree" >/dev/null 2>&1; planted_rc=$?
  [ "$planted_rc" -eq 1 ] \
    || { echo "  self-test: top-level scan root misses refs outside .github (exit $planted_rc)" >&2; rc=1; }

  [ "$rc" -eq 0 ] && echo "  self-test passed (detector fires, and goes quiet when fixed)"
  return "$rc"
}

if [ "$SELF_TEST" -eq 1 ]; then
  self_test || exit 1
fi

cd "$ROOT" 2>/dev/null || { echo "check-action-pinning.sh: no such directory: $ROOT" >&2; exit 2; }

# The whole repository, not a list of places to look. The previous version named
# ".github/workflows" and the fixtures dir, and so could not see the 18 mutable
# refs in skills/repo/_contract/templates/ — the files repo-scaffold actually
# renders into a new repository. A checker whose verdict depends on the
# completeness of its author's memory reports "all refs are pinned" while
# unpinned refs sit two directories away. Scan everything; waive by comment.
findings="$(scan ".")"

if [ -n "$findings" ]; then
  echo "  mutable action refs — pin to a 40-char commit SHA with a '# <version>' comment:" >&2
  printf '%s\n' "$findings" | sed 's/^/    /' >&2
  echo "  resolve with: gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq .object.sha" >&2
  exit 1
fi

echo "  all action refs are SHA-pinned"
