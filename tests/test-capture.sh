#!/usr/bin/env bash
# test-capture.sh — behaviour tests for scripts/capture-config.sh (PLAN Phase 6).
#
# WHAT IS ACTUALLY BEING PINNED
#   Capture is the direction that can leak. Every case here is a property whose
#   failure would be invisible until it had already put something in a public
#   repo: a credential printed in a "refused" line, a machine path adopted as
#   policy, a repo-side `_comment` round-tripping back in as data, an IP-scan hit
#   that takes down the whole run instead of the one hunk that carried it, or a
#   headless run that adopts on the user's behalf.
#
# HOME IS FAKE AND SO IS THE REPO.
#   Every case runs with HOME pointed at a mktemp -d tree, so the suite can never
#   read or write the real ~/.claude, ~/.cursor, ~/.codex, ~/.gemini or
#   ~/.config/opencode. It also runs capture against a COPY of this repo, because
#   adopting a hunk writes to the canonical source — a suite that ran against the
#   checkout would leave staged edits behind on every pass. Both are asserted
#   afterwards rather than left to the reader to notice.
#
# Usage: bash tests/test-capture.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require jq
REAL_HOME="$HOME"

# --- fixtures ---------------------------------------------------------------

# repo_mirror — the subset of the repo capture reads, copied so that adoption
# has somewhere to write. Not the whole checkout: the contract fixtures carry a
# node_modules tree, and copying it per case would dominate the runtime.
repo_mirror() {
  local m d
  m="$(harness_tmpdir)/repo"
  mkdir -p "$m/skills/repo/_contract"
  for d in scripts platforms core templates; do
    cp -R "$REPO_ROOT/$d" "$m/" 2>/dev/null || true
  done
  cp -R "$REPO_ROOT/skills/repo/_contract/scripts" "$m/skills/repo/_contract/" 2>/dev/null || true
  printf '%s' "$m"
}

# A planted token that is shaped like a real one and is not a real one. It is
# defined once so the "never printed" assertion can grep for this exact string.
PLANTED_TOKEN='ghp_0000000000000000000000000000000000'

# fake_home — one machine, hand-edited in every way the classifier has to tell
# apart. Every value here is a deliberate probe of one classification rule.
fake_home() {
  local h; h="$(harness_tmpdir)"
  mkdir -p "$h/.claude"
  cat > "$h/.claude/settings.json" <<JSON
{
  "effortLevel": "high",
  "permissions": {
    "allow": [
      "Bash(terraform plan:*)",
      "Read(/Users/somebody/notes/**)"
    ]
  },
  "env": {
    "GITHUB_TOKEN": "${PLANTED_TOKEN}",
    "REGISTRY": "\${NPM_REGISTRY}"
  },
  "enabledPlugins": { "someplugin@other-marketplace": true },
  "_comment": "repo-side documentation that must never round-trip",
  "hasCompletedOnboarding": true,
  "internalRegistry": "https://artifactory.example-co.internal/npm"
}
JSON
  printf '%s' "$h"
}

# with_rules <home> — a hand-added rule in the global CLAUDE.md, which is the
# canonical-rules capture path and the one that has to reach all five platforms.
with_rules() {
  local h="$1"
  cp "$REPO_ROOT/templates/global-CLAUDE.md" "$h/.claude/CLAUDE.md"
  printf '\n## Working Agreements\n\n- Always run the linter before opening a PR.\n' >> "$h/.claude/CLAUDE.md"
}

run_capture() { local m="$1" h="$2"; shift 2; HOME="$h" bash "$m/scripts/capture-config.sh" "$@" 2>&1; }

guard_real_home() {
  printf '%s' "$(ls -A "$REAL_HOME/.claude" 2>/dev/null | sort | shasum | awk '{print $1}')"
}
REAL_HOME_BEFORE="$(guard_real_home)"
# Scoped to the two trees capture WRITES. A whole-tree hash would also catch
# edits made by anything else sharing this checkout, and a guard that fails for
# reasons outside the thing it guards gets disabled rather than fixed.
REAL_REPO_BEFORE="$(cd "$REPO_ROOT" && git status --porcelain -- core platforms 2>/dev/null | shasum | awk '{print $1}')"

MIRROR="$(repo_mirror)"
HOME_A="$(fake_home)"

# ---------------------------------------------------------------------------
section "CLI contract"

out="$(run_capture "$MIRROR" "$HOME_A" --help)"; rc=$?
judge "--help exits 0" 0 "$rc"
judge "--help documents the three verbs" yes "$(has "$out" 'detect   diff the machine')"
judge "--help states that stdin is never read" yes "$(has "$out" 'STDIN IS NEVER READ')"

out="$(run_capture "$MIRROR" "$HOME_A" --nonsense)"; rc=$?
judge "unknown flag exits 1" 1 "$rc"

out="$(run_capture "$MIRROR" "$HOME_A" detect --targets emacs)"; rc=$?
judge "unknown target exits 1" 1 "$rc"
judge "unknown target lists the known ones" yes "$(has "$out" 'known: claude,cursor,codex,gemini,opencode')"

out="$(run_capture "$MIRROR" "$HOME_A" detect review)"; rc=$?
judge "two verbs is an error" 1 "$rc"

# ---------------------------------------------------------------------------
section "detect finds a hand-edited value"

JSONOUT="$(HOME="$HOME_A" bash "$MIRROR/scripts/capture-config.sh" detect --targets claude --json 2>/dev/null)"
judge "detect --json emits a parseable document" yes \
  "$(if printf '%s' "$JSONOUT" | jq empty 2>/dev/null; then echo yes; else echo no; fi)"

cls_of() { printf '%s' "$JSONOUT" | jq -r --arg k "$1" '.hunks[] | select(.key==$k) | .classification' | head -1; }
val_of() { printf '%s' "$JSONOUT" | jq -r --arg k "$1" '.hunks[] | select(.key==$k) | .machine_value' | head -1; }

judge "the hand-edited effortLevel is reported" high \
  "$(printf '%s' "$JSONOUT" | jq -r '.hunks[] | select(.key=="effortLevel") | .machine_value' | jq -r . 2>/dev/null)"
judge "a value the repo already asserts is NOT reported" "" \
  "$(printf '%s' "$JSONOUT" | jq -r '.hunks[] | select(.key=="theme") | .key' | head -1)"

# ---------------------------------------------------------------------------
section "classification — one probe per class"

judge "a new permission entry is portable" portable "$(cls_of permissions.allow)"
judge "an env var NAME is portable, not a secret" portable "$(cls_of env.REGISTRY)"
judge "a token-shaped value is a secret" secret "$(cls_of env.GITHUB_TOKEN)"
judge "another marketplace's plugin is third-party" third-party \
  "$(cls_of 'enabledPlugins.someplugin@other-marketplace')"
judge "onboarding state is machine-local" machine-local "$(cls_of hasCompletedOnboarding)"
judge "an unrecognised key is unknown, not assumed portable" unknown "$(cls_of internalRegistry)"

judge "third-party hunks name their owner" yes \
  "$(has "$(printf '%s' "$JSONOUT" | jq -r '.hunks[] | select(.classification=="third-party") | .reason')" 'other-marketplace')"

judge "only portable and unknown are offerable" yes \
  "$(n="$(printf '%s' "$JSONOUT" | jq '[.hunks[] | select(.blocked==null) | select(.classification=="portable" or .classification=="unknown")] | length')"
     o="$(printf '%s' "$JSONOUT" | jq '.summary.offerable')"
     if [ "$n" = "$o" ]; then echo yes; else echo "no ($n vs $o)"; fi)"

# ---------------------------------------------------------------------------
section "a secret is refused AND never printed"

judge "the secret hunk carries no machine value in --json" null \
  "$(printf '%s' "$JSONOUT" | jq -r '.hunks[] | select(.classification=="secret") | .machine_value' | head -1)"
judge "the planted token appears nowhere in the JSON output" "" \
  "$(printf '%s' "$JSONOUT" | grep -c "$PLANTED_TOKEN" | sed 's/^0$//')"

HUMAN="$(run_capture "$MIRROR" "$HOME_A" detect --targets claude)"
judge "the planted token appears nowhere in the human output" "" \
  "$(printf '%s' "$HUMAN" | grep -c "$PLANTED_TOKEN" | sed 's/^0$//')"
judge "the refusal is visible as a refusal" yes "$(has "$HUMAN" 'refused — not printed')"
judge "the reason does not quote the value" yes \
  "$(has "$(printf '%s' "$JSONOUT" | jq -r '.hunks[] | select(.classification=="secret") | .reason')" 'token-shaped')"

# ---------------------------------------------------------------------------
section "an absolute path is reclassified, never adopted"

judge "a permission holding /Users/<name> is machine-local" machine-local \
  "$(printf '%s' "$JSONOUT" | jq -r '.hunks[] | select(.machine_value != null) | select(.machine_value | test("/Users/somebody")) | .classification' | head -1)"
judge "and it says why" yes \
  "$(has "$(printf '%s' "$JSONOUT" | jq -r '.hunks[] | select(.machine_value != null) | select(.machine_value | test("/Users/somebody")) | .reason')" 'absolute home path')"
judge "the same key path is portable for a value without a machine path" portable \
  "$(printf '%s' "$JSONOUT" | jq -r '.hunks[] | select(.key=="permissions.allow") | select(.machine_value | test("terraform")) | .classification')"

# ---------------------------------------------------------------------------
section "\`_\`-prefixed metadata never round-trips"

judge "no hunk is produced for a _-prefixed key" "" \
  "$(printf '%s' "$JSONOUT" | jq -r '.hunks[] | select(.key | startswith("_")) | .key' | head -1)"
judge "and none is nested inside one either" "" \
  "$(printf '%s' "$JSONOUT" | jq -r '.hunks[] | select(.key | test("(^|\\.)_")) | .key' | head -1)"

# ---------------------------------------------------------------------------
section "the IP scan blocks at HUNK granularity, not run granularity"

# The planted reference sits next to clean, obviously-portable values. If the
# scanner took the run down, or blocked its neighbours, the offerable count
# below would collapse — which is the whole point of scanning per hunk.
HOME_IP="$(fake_home)"
python3 - "$HOME_IP/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["permissions"]["allow"].append("Bash(deploy --host build.acme-co.internal:*)")
json.dump(d, open(p, "w"), indent=2)
PY
IPJSON="$(HOME="$HOME_IP" bash "$MIRROR/scripts/capture-config.sh" detect --targets claude --json 2>/dev/null)"
judge "the planted internal host is blocked" yes \
  "$(printf '%s' "$IPJSON" | jq -r '[.hunks[] | select(.machine_value != null) | select(.machine_value | test("acme-co.internal")) | .blocked] | if (.[0] // null) != null then "yes" else "no" end')"
judge "the block names the IP scan" yes \
  "$(has "$(printf '%s' "$IPJSON" | jq -r '.hunks[] | select(.machine_value != null) | select(.machine_value | test("acme-co.internal")) | .blocked')" 'IP scan hit')"
judge "a blocked hunk is not offerable" no \
  "$(printf '%s' "$IPJSON" | jq -r '[.hunks[] | select(.machine_value != null) | select(.machine_value | test("acme-co.internal")) | select(.blocked == null)] | if length > 0 then "yes" else "no" end')"
judge "its clean neighbour in the same array is still offered" portable \
  "$(printf '%s' "$IPJSON" | jq -r '.hunks[] | select(.machine_value != null) | select(.machine_value | test("terraform")) | .classification')"
judge "the run still succeeds" 0 \
  "$(HOME="$HOME_IP" bash "$MIRROR/scripts/capture-config.sh" detect --targets claude >/dev/null 2>&1; echo $?)"

# A user-supplied employer pattern is the site-specific half of the scan. A
# public repo cannot ship a private employer's name, so the pattern is data.
IPJSON2="$(TAMIRS_EMPLOYER_PATTERN='\bmegacorp-internal\b' HOME="$HOME_IP" \
  bash "$MIRROR/scripts/capture-config.sh" detect --targets claude --json 2>/dev/null)"
judge "the scan honours a user-supplied employer pattern (control: clean without it)" null \
  "$(printf '%s' "$JSONOUT" | jq -r '.hunks[] | select(.key=="effortLevel") | .blocked')"
HOME_EMP="$(fake_home)"
python3 - "$HOME_EMP/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["permissions"]["allow"].append("Bash(git clone git@megacorp-internal:team/repo:*)")
json.dump(d, open(p, "w"), indent=2)
PY
EMPJSON="$(TAMIRS_EMPLOYER_PATTERN='megacorp-internal' HOME="$HOME_EMP" \
  bash "$MIRROR/scripts/capture-config.sh" detect --targets claude --json 2>/dev/null)"
judge "a planted employer reference is blocked" yes \
  "$(printf '%s' "$EMPJSON" | jq -r '[.hunks[] | select(.machine_value != null) | select(.machine_value | test("megacorp-internal")) | select(.blocked != null)] | if length > 0 then "yes" else "no" end')"
judge "and the clean hunks beside it are untouched" portable \
  "$(printf '%s' "$EMPJSON" | jq -r '.hunks[] | select(.machine_value != null) | select(.machine_value | test("terraform")) | .classification')"

# ---------------------------------------------------------------------------
section "no TTY prints the change set and adopts NOTHING"

HOME_B="$(fake_home)"; with_rules "$HOME_B"
MIRROR_B="$(repo_mirror)"
before="$(find "$MIRROR_B/core" "$MIRROR_B/platforms" -type f -exec shasum {} \; | sort | shasum | awk '{print $1}')"
out="$(run_capture "$MIRROR_B" "$HOME_B" review --targets claude)"; rc=$?
after="$(find "$MIRROR_B/core" "$MIRROR_B/platforms" -type f -exec shasum {} \; | sort | shasum | awk '{print $1}')"
judge "review without a terminal exits 0" 0 "$rc"
judge "review without a terminal says why" yes "$(has "$out" 'no TTY')"
judge "review without a terminal writes nothing to the repo" "$before" "$after"
judge "it still printed the change set" yes "$(has "$out" 'offerable')"

# ---------------------------------------------------------------------------
section "skip is the default on empty input"

# TESTED AT THE DECISION, NOT THROUGH A PTY. `script(1)` on macOS does not make
# its pty the child's controlling terminal, so /dev/tty inside it still refers to
# the outer terminal: a pty-driven case here passes whether or not the default is
# skip, which is the worst kind of green. capture_decide is the function the
# prompt loop actually consults, so asserting it directly is both honest and
# stronger — every answer is covered, not just the one a script could type.
decide() {
  ( SETUP_REPO_ROOT="$MIRROR"
    # shellcheck source=/dev/null
    . "$MIRROR/scripts/lib/setup-common.sh"
    # shellcheck source=/dev/null
    . "$MIRROR/scripts/lib/capture-common.sh"
    capture_decide "$1" )
}
judge "empty input (a bare return) is skip"    skip      "$(decide '')"
judge "whitespace is skip"                     skip      "$(decide ' ')"
judge "an unrecognised answer is skip"         skip      "$(decide 'maybe')"
judge "n is skip"                              skip      "$(decide 'n')"
judge "y adopts"                               adopt     "$(decide 'y')"
judge "Y adopts (case-insensitive)"            adopt     "$(decide 'Y')"
judge "a adopts the rest"                      adopt-all "$(decide 'a')"
judge "q quits"                                quit      "$(decide 'q')"
judge "s asks for more context"                show      "$(decide 's')"

# And the prompt a person sees has to match that default.
judge "the prompt capitalises N" yes \
  "$(if grep -qF '[y/N/a/q/s]' "$MIRROR/scripts/capture-config.sh"; then echo yes; else echo no; fi)"
judge "the prompt's default argument is n" yes \
  "$(if grep -qF "setup_ask 'Adopt into the repo? [y/N/a/q/s] ' n" "$MIRROR/scripts/capture-config.sh"; then echo yes; else echo no; fi)"
judge "the prompt reads /dev/tty, never stdin" "" \
  "$(grep -n 'read .*<&0\|read -r [a-z]*$' "$MIRROR/scripts/capture-config.sh" | head -1)"

# ---------------------------------------------------------------------------
section "an adopted hunk lands in the CANONICAL SOURCE"

MIRROR_C="$(repo_mirror)"
HOME_C="$(fake_home)"; with_rules "$HOME_C"
ADOPT="$(run_capture "$MIRROR_C" "$HOME_C" review --targets claude --adopt all)"
judge "the adopt cycle exits 0" 0 "$?"

judge "the captured rule landed in core/global-rules.md" yes \
  "$(if grep -qF 'Always run the linter before opening a PR.' "$MIRROR_C/core/global-rules.md"; then echo yes; else echo no; fi)"
judge "the captured permission landed in platforms/claude/settings.d/" yes \
  "$(if jq -e '.permissions.allow | index("Bash(terraform plan:*)")' \
        "$MIRROR_C/platforms/claude/settings.d/permissions-allow.json" >/dev/null 2>&1; then echo yes; else echo no; fi)"
judge "the captured effortLevel landed in the defaults fragment" high \
  "$(jq -r '.effortLevel' "$MIRROR_C/platforms/claude/settings.d/defaults.json")"

# The negative half: capture must not have written a platform's rendered file,
# and must not have created a repo-side copy of the machine's settings.json.
judge "no rendered platform file was written" "" \
  "$(find "$MIRROR_C/platforms" -name 'settings.json' -path '*templates*' -newer "$MIRROR_C/scripts/capture-config.sh" 2>/dev/null | grep -v gemini || true)"
judge "the machine-local path was NOT adopted" "" \
  "$(grep -o '/Users/somebody' "$MIRROR_C/platforms/claude/settings.d/permissions-allow.json" 2>/dev/null | head -1)"
judge "the secret was NOT adopted anywhere in the repo" "" \
  "$(grep -rl "$PLANTED_TOKEN" "$MIRROR_C/core" "$MIRROR_C/platforms" 2>/dev/null | head -1)"
judge "the third-party plugin was NOT adopted" "" \
  "$(grep -o 'other-marketplace' "$MIRROR_C/platforms/claude/settings.d/plugins.json" 2>/dev/null | head -1)"
judge "a repo-side _comment survived staging (it is ours, not captured)" yes \
  "$(if jq -e 'has("_comment")' "$MIRROR_C/platforms/claude/settings.d/defaults.json" >/dev/null; then echo yes; else echo no; fi)"

# ---------------------------------------------------------------------------
section "propagation renders the adopted rule to the other targets"

judge "the propagation report is printed" yes "$(has "$ADOPT" 'Propagation')"
for t in "Codex CLI" "Gemini CLI" "Cursor" "OpenCode"; do
  judge "the captured rule reaches $t" yes "$(has "$ADOPT" "$t")"
done
judge "the rule text itself appears in the downstream diff" yes \
  "$(has "$ADOPT" '+- Always run the linter before opening a PR.')"

# Proved against the renderers, not against the report: run the Codex renderer
# on the updated repo and look for the line.
CODEX_RENDER="$(cd "$MIRROR_C" && SETUP_REPO_ROOT="$MIRROR_C" bash -c '
  . scripts/lib/setup-common.sh
  SETUP_TARGET_DIR="$PWD/nowhere"
  . scripts/lib/setup-codex.sh
  codex_agents_md_render /nonexistent-by-design')"
judge "codex_agents_md_render emits the captured rule" yes \
  "$(has "$CODEX_RENDER" 'Always run the linter before opening a PR.')"

# ---------------------------------------------------------------------------
section "delivery — gated, one commit per platform, and it never merges"

# A whole git repo, because every property here is a git property. The stub
# Makefile stands in for `make validate` so the gate can be driven both ways
# without running the full suite recursively.
MIRROR_G="$(repo_mirror)"
HOME_G="$(fake_home)"; with_rules "$HOME_G"
printf 'validate:\n\t@exit 1\n' > "$MIRROR_G/Makefile"
git -C "$MIRROR_G" init -q -b master .
git -C "$MIRROR_G" config user.email test@example.invalid
git -C "$MIRROR_G" config user.name "Test Harness"
git -C "$MIRROR_G" config commit.gpgsign false
git -C "$MIRROR_G" add -A >/dev/null 2>&1
git -C "$MIRROR_G" commit -q -m baseline

out="$(run_capture "$MIRROR_G" "$HOME_G" deliver)"; rc=$?
judge "deliver with nothing adopted is a no-op, not an error" 0 "$rc"
judge "and it says what to do instead" yes "$(has "$out" "Run 'review'")"

run_capture "$MIRROR_G" "$HOME_G" review --adopt all >/dev/null 2>&1
judge "review staged something to deliver" yes \
  "$(if [ -n "$(git -C "$MIRROR_G" status --porcelain -- core platforms)" ]; then echo yes; else echo no; fi)"

out="$(run_capture "$MIRROR_G" "$HOME_G" deliver)"; rc=$?
judge "a failing make validate blocks delivery" 1 "$rc"
judge "and says so" yes "$(has "$out" 'make validate failed')"
judge "no branch was created behind the failed gate" master \
  "$(git -C "$MIRROR_G" rev-parse --abbrev-ref HEAD)"

printf 'validate:\n\t@echo ok\n' > "$MIRROR_G/Makefile"
out="$(run_capture "$MIRROR_G" "$HOME_G" deliver)"
# `has`, not an inline `case`: a `case` written inside $( ) has its `)` read as
# the closing paren of the substitution. The harness carries `has` for this.
BRANCH_G="$(git -C "$MIRROR_G" rev-parse --abbrev-ref HEAD)"
judge "delivery creates a capture/<date>-<slug> branch" yes "$(has "$BRANCH_G" 'capture/')"
judge "the branch name carries today's UTC date" yes \
  "$(has "$BRANCH_G" "capture/$(date -u +%Y%m%d)-")"
judge "one commit per platform touched" 2 \
  "$(git -C "$MIRROR_G" log --oneline master..HEAD | grep -c 'feat(capture)')"
judge "the working tree is clean afterwards" "" \
  "$(git -C "$MIRROR_G" status --porcelain -- core platforms)"
judge "nothing was pushed" "" "$(git -C "$MIRROR_G" remote)"
judge "the PR body exists" yes "$(exists "$MIRROR_G/.git/CAPTURE_PR_BODY.md")"
judge "it names what was captured" yes \
  "$(has "$(cat "$MIRROR_G/.git/CAPTURE_PR_BODY.md")" '| `effortLevel` |')"
judge "it names where the rule now renders" yes \
  "$(has "$(cat "$MIRROR_G/.git/CAPTURE_PR_BODY.md")" 'core/global-rules.md` -> Codex')"
judge "it records the refusal WITHOUT the value" yes \
  "$(b="$(cat "$MIRROR_G/.git/CAPTURE_PR_BODY.md")"
     if [ "$(has "$b" 'env.GITHUB_TOKEN` — **refused**')" = yes ] \
        && [ "$(has "$b" "$PLANTED_TOKEN")" = no ]; then echo yes; else echo no; fi)"
judge "it says why each skipped hunk was skipped" yes \
  "$(has "$(cat "$MIRROR_G/.git/CAPTURE_PR_BODY.md")" 'absolute home path')"
judge "the adoption record holds no secret value" "" \
  "$(grep -c "$PLANTED_TOKEN" "$MIRROR_G/.git/capture-state.json" 2>/dev/null | sed 's/^0$//')"
judge "delivery hands off rather than merging" yes \
  "$(has "$out" 'never merges')"
judge "delivery does not run gh itself" yes \
  "$(has "$out" 'Open it:  gh pr create')"

# ---------------------------------------------------------------------------
section "capture and setup.sh cannot disagree about what differs"

# THE PROPERTY THAT MAKES "ONE DIFFER" MORE THAN A CLAIM.
# Capture calls the same `<target>_<module>_render` functions setup.sh calls and
# the same normalisation primitives; the only difference is the argument it
# passes. This case asserts the consequence directly: on a machine whose files
# capture reports as differing, `setup.sh plan` must also report a change for
# the same path — and where capture finds nothing, setup must report `ok`.
HOME_D="$(fake_home)"
CAPJSON="$(HOME="$HOME_D" bash "$MIRROR/scripts/capture-config.sh" detect --targets claude --json 2>/dev/null)"
SETJSON="$(HOME="$HOME_D" bash "$MIRROR/scripts/setup.sh" plan --targets claude --json 2>/dev/null)"
judge "setup.sh plan --json still parses (the shared contract)" yes \
  "$(if printf '%s' "$SETJSON" | jq empty 2>/dev/null; then echo yes; else echo no; fi)"

capfile="$(printf '%s' "$CAPJSON" | jq -r '[.hunks[].file] | unique[]' | head -1)"
judge "capture and setup agree that settings.json differs" yes \
  "$(printf '%s' "$SETJSON" | jq -r --arg p "$capfile" \
      '[.changes[] | select(.path==$p) | select(.status=="modify" or .status=="create")] | if length > 0 then "yes" else "no" end')"

# The converse, on a machine rendered FROM the repo: apply first, then both
# directions must be quiet. This is the case that catches a normalisation drift,
# because only a whitespace or ordering difference could make one of them speak.
HOME_E="$(harness_tmpdir)"; mkdir -p "$HOME_E/.claude"
HOME="$HOME_E" bash "$MIRROR/scripts/setup.sh" apply --yes --targets claude >/dev/null 2>&1
SET2="$(HOME="$HOME_E" bash "$MIRROR/scripts/setup.sh" plan --targets claude --json 2>/dev/null)"
CAP2="$(HOME="$HOME_E" bash "$MIRROR/scripts/capture-config.sh" detect --targets claude --json 2>/dev/null)"
judge "after apply, setup reports no settings.json change" 0 \
  "$(printf '%s' "$SET2" | jq '[.changes[] | select(.path | endswith(".claude/settings.json")) | select(.status=="modify" or .status=="create")] | length')"
judge "after apply, capture reports no offerable hunk for settings.json" 0 \
  "$(printf '%s' "$CAP2" | jq '[.hunks[] | select(.file | endswith(".claude/settings.json")) | select(.blocked==null) | select(.classification=="portable" or .classification=="unknown")] | length')"

# ---------------------------------------------------------------------------
section "the suite touched nothing real"

judge "the real ~/.claude is unchanged" "$REAL_HOME_BEFORE" "$(guard_real_home)"
judge "the repo's canonical sources are unchanged" "$REAL_REPO_BEFORE" \
  "$(cd "$REPO_ROOT" && git status --porcelain -- core platforms 2>/dev/null | shasum | awk '{print $1}')"
judge "no fake HOME is the real one" no \
  "$(for h in "$HOME_A" "$HOME_B" "$HOME_C" "$HOME_D" "$HOME_E" "$HOME_G" "$HOME_IP" "$HOME_EMP"; do
       [ "$h" = "$REAL_HOME" ] && echo yes && exit 0
     done; echo no)"

harness_summary
