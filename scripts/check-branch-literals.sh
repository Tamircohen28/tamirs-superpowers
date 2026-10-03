#!/usr/bin/env bash
# check-branch-literals.sh — fail when a default-branch name is hardcoded.
#
# WHY THIS EXISTS
#   A default branch is a fact about a repository, not a constant. This plugin
#   *generates* repositories, so a literal `main` or `master` in a template is
#   copied into every repo scaffolded from it. And a wrong branch name does not
#   error: `git diff origin/master` on a `main` repo prints nothing, `git branch
#   --merged origin/main` on a `master` repo matches nothing, and a workflow
#   filtered on `branches: [master]` simply never runs. Every failure mode is
#   silent, which is why it needs a checker rather than a code review.
#
#   `scripts/check-github-policy.sh` already enforces this ban inside
#   `config/github/repository-policy.json`. This extends the same ban to the
#   parts of the tree that generate, set up, or validate other repositories.
#
# WHAT IT FLAGS — only *actionable* literals, in branch position:
#   origin/main            refs/heads/master        ${VAR:-main}
#   branches: [main]       a YAML branch list item
#   git checkout|switch|rebase|merge|pull main      push origin master
#   --base main            --head master            SOME_BRANCH="main"
#
#   It deliberately does NOT flag the words themselves. "the main session",
#   "thread 'main' panicked", a github.com/.../blob/main/ URL and a sentence
#   explaining why `[main, master]` is wrong are all legitimate.
#
# WAIVERS — explicit, never pattern-shaped:
#   * a line carrying the marker  branch-literal-ok: <reason>
#   * a path listed in ALLOWED_PATHS below, each with its reason
#   Both forms keep the exemption readable in review. A broad regex carve-out is
#   how the literal creeps back.
#
# Usage: check-branch-literals.sh [<repo_root>] [--self-test]
# Exit:  0 clean · 1 literals found · 2 usage/environment
set -uo pipefail

ROOT="."
SELF_TEST=0
for arg in "$@"; do
  case "$arg" in
    --self-test) SELF_TEST=1 ;;
    -h|--help) sed -n '2,33p' "$0" | sed 's/^#[ ]\{0,1\}//'; exit 0 ;;
    -*) echo "check-branch-literals.sh: unknown option '$arg'" >&2; exit 2 ;;
    *) ROOT="$arg" ;;
  esac
done

cd "$ROOT" 2>/dev/null || { echo "check-branch-literals.sh: no such directory: $ROOT" >&2; exit 2; }

# Trees that generate, configure, or validate repositories. tests/ is excluded
# on purpose: a test fixture that pins a concrete branch name is how the
# resolver gets tested, and tests/lib/fake-gh.sh must be free to name one.
SCAN_DIRS='^(skills|scripts|hooks|rules|core|templates)/'

# Paths whose PURPOSE is to name the pattern, plus this scanner itself.
# Each entry states why. Anything not listed here must resolve the branch.
# Matched against the "path:line:content" grep output, so it is anchored with a
# trailing colon rather than end-of-line.
ALLOWED_PATHS='^(scripts/check-branch-literals\.sh|scripts/check-github-policy\.sh):'
#   scripts/check-branch-literals.sh — this file; the patterns live here.
#   scripts/check-github-policy.sh   — the sibling ban inside the policy JSON;
#                                      its jq selector names both words.

# Branch-position patterns. Each alternative requires *branch context* — a ref
# path, a shell default-expansion, a git subcommand, a CLI flag, or an
# assignment to a branch-named variable — so the bare words never match.
PATTERN='(origin/(main|master)([^A-Za-z0-9._-]|$)'
PATTERN="$PATTERN"'|refs/(heads|remotes/origin)/(main|master)([^A-Za-z0-9._-]|$)'
PATTERN="$PATTERN"'|:-(main|master)\}'
PATTERN="$PATTERN"'|branches: *\[[^]]*(main|master)([^A-Za-z0-9._-]|\]|$)'
PATTERN="$PATTERN"'|^[[:space:]]*-[[:space:]]+(main|master)[[:space:]]*$'
PATTERN="$PATTERN"'|git +(checkout|switch|rebase|merge|pull) +(main|master)([^A-Za-z0-9._-]|$)'
PATTERN="$PATTERN"'|push +(-u +)?origin +(main|master)([^A-Za-z0-9._-]|$)'
PATTERN="$PATTERN"'|--(base|head) +(main|master)([^A-Za-z0-9._-]|$)'
PATTERN="$PATTERN"'|[Bb][Rr][Aa][Nn][Cc][Hh][A-Za-z_]*"?[[:space:]]*[:=][[:space:]]*"?'"'"'?(main|master)([^A-Za-z0-9._-]|$))'

scan_tree() {
  local list
  list="$(git ls-files --cached --others --exclude-standard 2>/dev/null | grep -E "$SCAN_DIRS")" || true
  [ -n "$list" ] || return 0
  printf '%s\n' "$list" \
    | tr '\n' '\0' \
    | xargs -0 grep -nIE "$PATTERN" 2>/dev/null \
    | grep -vE "$ALLOWED_PATHS" \
    | grep -v 'branch-literal-ok' \
    || true
}

# --- positive control ------------------------------------------------------
# Proves the detector actually fires. A check that has never been shown to fail
# is indistinguishable from a check that greps nothing, and this repo has
# shipped several of those.
self_test() {
  local tmp rc=0 out
  tmp="$(mktemp -d)" || return 2
  trap 'rm -rf "$tmp"' RETURN

  planted() { printf '%s\n' "$1" | grep -qE "$PATTERN"; }

  local must_fire=(
    'DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"'
    'git diff origin/master -- skills/'
    '    branches: [master]'
    'git push origin main'
    'gh pr create --base master --head feat/x'
    'BASE_BRANCH="main"'
    '  "base_branch": "master",'
    'git checkout main'
    'git -C "$r" rev-parse refs/heads/master'
  )
  local must_not_fire=(
    'Run the role inline in the main session, sequentially.'
    "thread 'main' panicked at 'reason', src/x.rs:42"
    'https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/skills.md'
    '# Enumerating names (`[main]`, `[master]`, or both) is how a workflow'
    'int main(void) { return 0; }'
    'PROTECTED_RE="^(${DEFAULT}|main|master|develop|HEAD)\$"'
  )

  for out in "${must_fire[@]}"; do
    if planted "$out"; then :; else
      printf 'self-test FAIL: detector did not fire on: %s\n' "$out" >&2; rc=1
    fi
  done
  for out in "${must_not_fire[@]}"; do
    if planted "$out"; then
      printf 'self-test FAIL: detector fired on a legitimate line: %s\n' "$out" >&2; rc=1
    fi
  done

  # End-to-end: a planted file inside a scanned tree must be reported.
  local plant="skills/.branch-literal-positive-control.sh"
  if [ ! -e "$plant" ]; then
    printf '#!/usr/bin/env bash\nDEFAULT_BRANCH="${DEFAULT_BRANCH:-master}"\n' > "$plant"
    if scan_tree | grep -q "$plant"; then :; else
      printf 'self-test FAIL: a planted literal in %s was not reported\n' "$plant" >&2; rc=1
    fi
    rm -f "$plant"
  fi

  [ "$rc" -eq 0 ] && printf 'ok:    positive control — detector fires on %d planted literals and none of %d legitimate lines\n' \
    "${#must_fire[@]}" "${#must_not_fire[@]}"
  return "$rc"
}

if [ "$SELF_TEST" -eq 1 ]; then
  self_test || exit 1
fi

HITS="$(scan_tree)"
if [ -n "$HITS" ]; then
  echo "FAIL:  hardcoded default-branch names (resolve them; do not guess):" >&2
  printf '%s\n' "$HITS" | sed 's/^/       /' >&2
  cat >&2 <<'MSG'

       Use skills/dev-workflow/_shared/scripts/default-branch.sh — it reads
       origin/HEAD, then gh, and fails with a named cause rather than falling
       back to a literal. In generated workflow YAML, omit on.*.branches
       entirely and gate at job level with
         if: github.ref == format('refs/heads/{0}', github.event.repository.default_branch)
       If a literal is genuinely correct, append  branch-literal-ok: <reason>
       to the line, or add the path to ALLOWED_PATHS with a reason.
MSG
  exit 1
fi

echo "ok:    no hardcoded default-branch names in skills/ scripts/ hooks/ rules/ core/ templates/"
