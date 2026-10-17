#!/usr/bin/env bash
# check-repo-description.sh — the GitHub repository description must state the same
# skill and agent counts the tree ships.
#
# Usage:
#   bash scripts/check-repo-description.sh [repo-root] [--description "<text>" | --warn | --fix]
#
#   --description "<text>"  check that text instead of the live description (exit 1 on drift)
#   --warn                  report live drift as a ::warning:: and exit 0 (what CI runs)
#   --fix                   write the corrected description to GitHub (needs a token that
#                           may change repository settings); takes neither of the above
#
# WHY THIS EXISTS
#   check-doc-claims.sh holds every count in README.md, the manifests and the docs to
#   the filesystem, but the repository's GitHub description lives outside the tree and
#   is set by hand. It said "29 skills" after 5.0.0 shipped the thirtieth. This reads
#   the live description through the GitHub API (gh api, read-only) and compares the
#   "N skills" and "N specialist agents" it names with the tree. Without gh, a token
#   or the network it SKIPS (exit 0, says so): a contributor offline is not failing,
#   and CI, where the token exists, is where the drift is caught.
#
#   --description "<text>" checks that text instead of the live one (what the test
#   uses). On drift the exit is 1 and the fix is printed: this proxy and the GitHub
#   App token cannot write repository settings, so the edit is the owner's. --warn
#   reports the drift as a workflow warning and exits 0; CI runs it that way on every
#   event, because no commit can fix a stale description and a red check nobody can
#   clear from a branch only hides the next real failure. The plain exit 1 is for a
#   person running it by hand (make check-repo-description). --fix writes the corrected
#   description through the API (PATCH repos/<slug>, the call `gh repo edit` makes);
#   it needs a token that may change repository settings (a fine-grained PAT with
#   Administration: write, or a classic PAT with the repo scope), which the Actions
#   GITHUB_TOKEN never has, so .github/workflows/repo-description.yml is where --fix
#   runs. In fix mode a missing gh, a missing remote or a failed read is an ERROR, not
#   a skip: the write is the requested operation, and a green run that wrote nothing
#   would hide a revoked token.
set -euo pipefail
ROOT="."; DESC=""; DESC_GIVEN=false; WARN=false; FIX=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --description) DESC="$2"; DESC_GIVEN=true; shift 2 ;;
    --warn) WARN=true; shift ;;
    --fix) FIX=true; shift ;;
    -h|--help) sed -n '2,35p' "$0" | sed 's/^#[[:space:]]\{0,1\}//'; exit 0 ;;
    *) ROOT="$1"; shift ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"
if [[ "$FIX" == true && ( "$DESC_GIVEN" == true || "$WARN" == true ) ]]; then
  echo "ERROR: --fix writes the live description; it takes neither --description nor --warn" >&2; exit 2
fi

skills=$(find "$ROOT/skills" -name SKILL.md 2>/dev/null | grep -v '_contract/fixtures' | wc -l | tr -d ' ')
agents=$(find "$ROOT/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')

slug=""
if [[ "$DESC_GIVEN" != true ]]; then
  slug="${GITHUB_REPOSITORY:-}"
  if [[ -z "$slug" ]]; then
    url="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
    slug="$(printf '%s' "$url" | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##')"
  fi
  if [[ -z "$slug" ]] || ! command -v gh >/dev/null 2>&1; then
    if [[ "$FIX" == true ]]; then
      echo "ERROR: --fix needs a GitHub remote and gh on PATH (nothing was written)" >&2; exit 1
    fi
    echo "repo-description: SKIP (no GitHub remote or no gh on PATH)"; exit 0
  fi
  if ! json="$(gh api "repos/$slug" 2>/dev/null)"; then
    if [[ "$FIX" == true ]]; then
      echo "ERROR: --fix could not read repos/$slug (no token, an expired one, or no network); nothing was written" >&2; exit 1
    fi
    echo "repo-description: SKIP (gh api repos/$slug failed: no token or no network)"; exit 0
  fi
  DESC="$(printf '%s' "$json" | jq -r '.description // empty')"
fi
# An absent description is drift like any other (it names no count), so it takes the
# same path below and honours --warn the same way.

said_skills="$(printf '%s' "$DESC" | grep -oE '[0-9]+ skills' | head -1 | grep -oE '^[0-9]+' || true)"
said_agents="$(printf '%s' "$DESC" | grep -oE '[0-9]+ (specialist |role-based )?agents' | head -1 | grep -oE '^[0-9]+' || true)"
status=0
if [[ "$said_skills" != "$skills" ]]; then
  echo "ERROR: the repository description says '${said_skills:-no} skills'; the tree ships $skills" >&2; status=1
fi
if [[ "$said_agents" != "$agents" ]]; then
  echo "ERROR: the repository description says '${said_agents:-no} agents'; the tree ships $agents" >&2; status=1
fi
if [[ "$status" -ne 0 ]]; then
  canonical="A portable agent toolkit — $skills skills, $agents specialist agents, worktree hooks and MCP stubs — shipped from one canonical source to six agent surfaces across five platforms."
  # Substitute the counts the text already names; a text that names neither phrase (or
  # only one) cannot be patched in place, so it is replaced by the canonical sentence —
  # a fix that still lacked a count would leave the next check in drift.
  fixed="$(printf '%s' "$DESC" | sed -E "s/[0-9]+ skills/$skills skills/; s/[0-9]+ (specialist |role-based )?agents/$agents \\1agents/")"
  if ! printf '%s' "$fixed" | grep -qE "(^|[^0-9])$skills skills" \
     || ! printf '%s' "$fixed" | grep -qE "(^|[^0-9])$agents (specialist |role-based )?agents"; then
    fixed="$canonical"
  fi
  if [[ "$FIX" == true ]]; then
    if gh api -X PATCH "repos/$slug" -f description="$fixed" >/dev/null; then
      echo "repo-description: fixed — $slug now says $skills skills, $agents agents"; exit 0
    fi
    echo "ERROR: could not write the description (the token must be allowed to change repository settings)" >&2
    exit 1
  fi
  echo "       Fix (repository owner, Settings -> About, or):" >&2
  printf "         gh repo edit %s --description '%s'\n" "${slug:-<owner/repo>}" "$fixed" >&2
  if [[ "$WARN" == true ]]; then
    echo "::warning::The GitHub repository description is stale (says ${said_skills:-?} skills / ${said_agents:-?} agents; the tree ships $skills / $agents). Owner: gh repo edit ${slug:-<owner/repo>} --description '$fixed'"
    echo "repo-description: drift reported as a warning (--warn)"; exit 0
  fi
  exit 1
fi
echo "repo-description: ok ($skills skills, $agents agents)"
