#!/usr/bin/env bash
# test-docs.sh — documentation tests (REFACTOR-SPEC §20 "Documentation tests").
#
# CI must check: internal links, referenced files, install commands syntactically,
# platform names, version strings, skill counts, agent counts, and capability
# tables generated from the registry. Each of those is a section below.
#
# WHY A SEPARATE SUITE FROM test-static.sh
#   test-static.sh asks "is this repo well-formed". This asks "does the prose tell
#   the truth about the repo". The failure modes are different: a stale count is
#   perfectly valid markdown, and a broken install command parses fine as prose.
#   Keeping them apart also lets CI run this one on a docs-only change and skip the
#   expensive platform matrix.
#
# Usage: bash tests/test-docs.sh [--strict]
#   --strict promotes the advisory checks (link rot in files the refactor is still
#   rewriting) to failures.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require jq git
cd "$REPO_ROOT" || exit 1

STRICT=false
[ "${1:-}" = "--strict" ] && STRICT=true

REG="core/capabilities/platforms.json"

# Docs are written per SURFACE — "Claude Code" and "Claude Desktop" are different install
# guides — so flatten before asking which names must appear. Unverified surfaces are
# checked separately below: they are omitted from the flat view on purpose.
# shellcheck source=scripts/lib/registry.sh
. "$REPO_ROOT/scripts/lib/registry.sh"
REG_CANONICAL="$REG"
REG="$(registry_flat_tmp "$REG")"
trap 'rm -f "$REG"' EXIT
TARGETS="docs/engineering/build-and-release/platform-targets.json"

# ---------------------------------------------------------------------------
section "the documented information architecture exists"

# REFACTOR-SPEC §20 enumerates these by name. A missing file here is not link rot,
# it is a missing chapter.
required_user=(
  docs/user/README.md docs/user/getting-started.md docs/user/concepts.md
  docs/user/configuration.md docs/user/orchestration.md docs/user/skills.md
  docs/user/agents.md docs/user/troubleshooting.md docs/user/platform-differences.md
  docs/user/install/claude-code.md docs/user/install/claude-desktop.md
  docs/user/install/cursor.md docs/user/install/codex.md
  docs/user/install/gemini.md docs/user/install/opencode.md
)
missing=""
for f in "${required_user[@]}"; do [ -f "$f" ] || missing="$missing $f"; done
judge "every docs/user file required by §20 exists" "" "$missing"

required_eng=(
  docs/engineering/architecture/overview.md
  docs/engineering/architecture/capability-model.md
  docs/engineering/architecture/adapter-contract.md
  docs/engineering/architecture/skill-schema.md
  docs/engineering/architecture/orchestration-state-machine.md
  docs/engineering/architecture/branch-worktree-model.md
  docs/engineering/architecture/validation-tiers.md
  docs/engineering/architecture/adding-a-platform.md
  docs/engineering/build-and-release/versioning.md
  docs/engineering/build-and-release/testing-matrix.md
)
missing=""
for f in "${required_eng[@]}"; do [ -f "$f" ] || missing="$missing $f"; done
judge "every docs/engineering file required by §20 exists" "" "$missing"

# ---------------------------------------------------------------------------
section "internal links and referenced files resolve"

broken=""
while IFS= read -r f; do
  dir="$(dirname "$f")"
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    case "$target" in
      http://*|https://*|mailto:*|'#'*) continue ;;
      '...'|URL|PATH|'<'*) continue ;;
      *'`'*|*'…'*) continue ;;   # prose with backticks/ellipsis inside the
                                      # parens, not a link the naive ](...) grab
                                      # can interpret
    esac
    t="${target%%#*}"
    [ -n "$t" ] || continue
    case "$t" in
      /*) resolved=".$t" ;;
      *)  resolved="$dir/$t" ;;
    esac
    [ -e "$resolved" ] || broken="$broken
    $f -> $target"
  done < <(grep -oE '\]\([^)]+\)' "$f" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//')
done < <(find docs README.md CLAUDE.md AGENTS.md -name '*.md' -o -name 'README.md' 2>/dev/null | sort -u)
if [ -z "$broken" ]; then
  ok "every internal docs link resolves"
elif [ "$STRICT" = true ]; then
  bad "every internal docs link resolves" "$broken"
else
  warn "docs link rot (advisory until the docs rewrite lands):$broken"
fi

# Files referenced in prose as `path/to/thing` backticks — only paths that look
# like repo paths, to avoid flagging shell snippets.
ghost=""
while IFS= read -r pair; do
  [ -n "$pair" ] || continue
  f="${pair%%:*}"; ref="${pair#*:}"
  case "$ref" in *'...'*|*'<'*) continue ;; esac   # documented placeholders
  [ -e "$ref" ] || ghost="$ghost
    $f -> $ref"
# docs/engineering/refactor/ is a FROZEN Phase 0 inventory, taken at a named
# baseline commit and deliberately not maintained as the refactor moves files.
# Link-checking a historical snapshot against the current tree asserts that the
# past should match the present, which is backwards — the snapshot is only
# useful because it does not move. test-static.sh already excludes it from its
# link check; this check was inconsistent with it and flagged a file the refactor
# had legitimately deleted.
done < <(grep -rohE '`(docs|skills|core|scripts|hooks|agents|platforms|rules|templates)/[A-Za-z0-9._/-]+`' \
           docs README.md CLAUDE.md AGENTS.md 2>/dev/null \
           --exclude-dir=refactor \
         | tr -d '`' | sort -u | sed 's#^#docs:#')
if [ -z "$ghost" ]; then
  ok "every repo path named in backticks exists"
elif [ "$STRICT" = true ]; then
  bad "every repo path named in backticks exists" "$ghost"
else
  warn "referenced paths that do not exist (advisory):$ghost"
fi

# ---------------------------------------------------------------------------
section "install commands are syntactically valid"

# A shell block in an install guide is a promise. It does not have to RUN here —
# it has to parse, which catches the unbalanced quote and the stray backtick that
# make a copy-paste install fail on the user's first minute.
# Blocks are parsed ONE AT A TIME — concatenating them would invent syntax errors
# that no reader would ever hit. Blocks containing an angle-bracket placeholder
# (`gemini skills uninstall <name>`) are prose, not runnable shell: `<name>` is a
# redirection to bash and would fail for a reason that is not a documentation bug.
badsh=""
BLKDIR="$(harness_tmpdir)"
for guide in docs/user/install/*.md; do
  [ -f "$guide" ] || continue
  n=0
  awk -v out="$BLKDIR" '
    /^```(bash|sh|shell)$/ { n++; f=1; file=sprintf("%s/blk-%03d.sh", out, n); next }
    /^```/ { f=0; next }
    f { print > file }' "$guide"
  for blk in "$BLKDIR"/blk-*.sh; do
    [ -f "$blk" ] || continue
    n=$((n + 1))
    grep -qE '<[A-Za-z][A-Za-z0-9._-]*>' "$blk" && { rm -f "$blk"; continue; }
    bash -n "$blk" 2>/dev/null || badsh="$badsh $guide(block $n)"
    rm -f "$blk"
  done
done
judge "every runnable shell block in an install guide parses" "" "$badsh"

# Slash-command install lines must name a marketplace/plugin that exists.
if [ -f docs/user/install/claude-code.md ]; then
  judge "the Claude install guide names this plugin" yes \
    "$(has "$(cat docs/user/install/claude-code.md)" "tamirs-superpowers")"
fi

# Every install guide must document verify / update / uninstall (§28 acceptance).
incomplete=""
for guide in docs/user/install/*.md; do
  base="$(basename "$guide")"
  [ "$base" = "README.md" ] && continue
  body="$(tr 'A-Z' 'a-z' < "$guide")"
  for word in verify update uninstall; do
    case "$body" in *"$word"*) ;; *) incomplete="$incomplete $base:$word" ;; esac
  done
done
judge "every install guide documents verify, update and uninstall" "" "$incomplete"

# ---------------------------------------------------------------------------
section "platform names are consistent with the registry"

# The registry owns display names. Docs inventing 'Gemini-CLI' or 'OpenCode CLI'
# is exactly the drift that makes a support matrix untrustworthy.
missing_names=""
while IFS= read -r dn; do
  [ -n "$dn" ] || continue
  grep -rqF "$dn" README.md docs/user/platform-differences.md 2>/dev/null \
    || missing_names="$missing_names '$dn'"
done < <(jq -r '.platforms | to_entries[] | select(.value.runtime_surface_of == null) | .value.display_name' "$REG")
judge "every registry display_name appears in README and platform-differences" "" "$missing_names"

# The opposite direction (scanning the doc for platform names the registry does
# not know) was tried and removed: first-column table cells are prose headings as
# often as they are platform names, so it produced only false positives. The
# registry-to-docs direction above is the one that catches a real gap.

# ---------------------------------------------------------------------------
section "version strings agree"

manifest_version="$(jq -r .version .claude-plugin/plugin.json)"
judge "plugin-version.json agrees with the Claude manifest" \
  "$manifest_version" "$(jq -r .version plugin-version.json 2>/dev/null)"
for m in .codex-plugin/plugin.json .cursor-plugin/plugin.json gemini-extension.json; do
  [ -f "$m" ] || continue
  judge "$m agrees with the Claude manifest" "$manifest_version" "$(jq -r .version "$m")"
done

# A version quoted in prose must be the current one.
stale=""
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  printf '%s' "$hit" | grep -qF "$manifest_version" && continue
  stale="$stale
    $hit"
done < <(grep -rnoE 'v?[0-9]+\.[0-9]+\.[0-9]+' README.md docs/user/install/*.md 2>/dev/null \
          | grep -vE 'CHANGELOG|[0-9]+\.[0-9]+\.[0-9]+\.' || true)
if [ -z "$stale" ]; then
  ok "every version string in the README and install guides is current"
else
  warn "version strings that are not $manifest_version (may be legitimate history):$stale"
fi

# ---------------------------------------------------------------------------
section "skill and agent counts match the filesystem"

# check-doc-claims.sh already computes every count from the tree with far better
# messages than a grep. Run it; do not reimplement it.
rc=0; out="$(bash scripts/check-doc-claims.sh . 2>&1)" || rc=$?
if [ "$rc" -eq 0 ]; then
  ok "documented skill counts and target coverage match the filesystem"
else
  printf '%s\n' "$out" | sed 's/^/       /' | head -15
  bad "documented skill counts and target coverage match the filesystem" "exit $rc"
fi

agents_n="$(find agents -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
if [ -f docs/user/agents.md ]; then
  named=0
  while IFS= read -r a; do
    grep -qF "$(basename "$a" .md)" docs/user/agents.md && named=$((named + 1))
  done < <(find agents -maxdepth 1 -name '*.md')
  judge "docs/user/agents.md names every shipped agent" "$agents_n" "$named"
else
  skip "agent count in docs" "docs/user/agents.md not present"
fi

# ---------------------------------------------------------------------------
section "capability tables are derivable from the registry"

# The docs may summarise, but they must not CONTRADICT. Every capability id and
# every platform key mentioned in the capability docs has to exist in the registry.
# The meaningful direction is COMPLETENESS: the registry defines the vocabulary,
# so a capability the registry defines but the capability doc never names is a
# capability users cannot find out about. (The opposite direction — scanning every
# backticked token in the doc — was tried and matched every JSON key on the page.)
undocumented=""
CAPDOC="docs/engineering/architecture/capability-model.md"
if [ -f "$CAPDOC" ]; then
  while IFS= read -r cap; do
    [ -n "$cap" ] || continue
    grep -qF "$cap" "$CAPDOC" docs/user/platform-differences.md 2>/dev/null \
      || undocumented="$undocumented $cap"
  done < <(jq -r '.capability_definitions | keys[]' "$REG")
  judge "every registry capability is named in the capability docs" "" "$undocumented"
else
  skip "capability doc completeness" "$CAPDOC not present"
fi

# And every capability definition must carry the degradation story the spec
# requires — "never silently pretend" is unenforceable if the doc never says how.
nodegrade="$(jq -r '.capability_definitions | to_entries[] | select((.value.degradation // "") == "") | .key' "$REG")"
judge "every capability definition states its degradation path" "" "$nodegrade"

if [ -f "$TARGETS" ]; then
  reg_n="$(jq -r '[.platforms | to_entries[] | select(.value.runtime_surface_of == null)] | length' "$REG")"
  tgt_n="$(jq -r '(.supported_targets // []) | length' "$TARGETS")"
  judge "platform-targets.json covers every first-class registry platform" "$reg_n" "$tgt_n"

  nodoc=""
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -f "$d" ] || nodoc="$nodoc $d"
  done < <(jq -r '(.targets // {}) | to_entries[] | .value.install_doc // empty' "$TARGETS")
  judge "every target's declared install_doc exists" "" "$nodoc"
else
  skip "platform-targets coverage" "$TARGETS not present"
fi

harness_summary
