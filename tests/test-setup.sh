#!/usr/bin/env bash
# test-setup.sh — behaviour tests for scripts/setup.sh (PLAN Phase 2).
#
# WHAT IS ACTUALLY BEING PINNED
#   Every property here is one that, if it broke, would break it silently and on
#   someone else's machine: a `plan` that writes, an `apply` that is not
#   idempotent, a merge that eats a third-party key, a prompt that blocks a hook.
#   None of them are visible from reading the script.
#
# HOME IS FAKE, ALWAYS. Each case runs with HOME pointed at a mktemp -d tree, so
# the suite can never touch the real ~/.claude. `guard_real_home` asserts that
# explicitly rather than trusting the reader to notice.
#
# Usage: bash tests/test-setup.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require jq
SETUP="$REPO_ROOT/scripts/setup.sh"
REAL_HOME="$HOME"

# --- fixtures ---------------------------------------------------------------

# fake_home — a HOME with a pre-existing settings.json carrying THIRD-PARTY
# wiring. The cmux permission entry and the gortex plugin key are the point of
# the fixture: they are things this repo does not own and must never destroy.
fake_home() {
  local h; h="$(harness_tmpdir)"
  mkdir -p "$h/.claude"
  cat > "$h/.claude/settings.json" <<'JSON'
{
  "theme": "light",
  "permissions": {
    "allow": [
      "Bash(cmux *)"
    ]
  },
  "enabledPlugins": {
    "gortex@third-party": true
  }
}
JSON
  printf '%s' "$h"
}

run_setup() { local h="$1"; shift; HOME="$h" bash "$SETUP" "$@" 2>&1; }
sum() { [ -f "$1" ] && shasum "$1" | awk '{print $1}' || printf 'MISSING'; }

guard_real_home() {
  # The real ~/.claude must be untouched by this suite. Compare a cheap witness
  # before and after the whole run.
  printf '%s' "$(ls -A "$REAL_HOME/.claude" 2>/dev/null | sort | shasum | awk '{print $1}')"
}
REAL_HOME_BEFORE="$(guard_real_home)"

# ---------------------------------------------------------------------------
section "CLI contract (rules/dev/user-facing-script-standards.md §1)"

h="$(fake_home)"
out="$(run_setup "$h" --help)"; rc=$?
judge "--help exits 0" 0 "$rc"
judge "--help documents the verbs" yes "$(has "$out" 'plan     detect targets')"
judge "--help shows an example" yes "$(has "$out" 'bash scripts/setup.sh apply --targets claude')"

out="$(run_setup "$h" --nonsense)"; rc=$?
judge "unknown flag exits 1" 1 "$rc"
judge "unknown flag names itself" yes "$(has "$out" 'unknown flag: --nonsense')"

out="$(run_setup "$h" plan --targets emacs)"; rc=$?
judge "unknown target exits 1" 1 "$rc"
judge "unknown target lists the known ones" yes "$(has "$out" 'known: claude,cursor,codex,gemini,opencode')"

out="$(run_setup "$h" plan apply)"; rc=$?
judge "two verbs is an error" 1 "$rc"

# ---------------------------------------------------------------------------
section "plan never writes"

h="$(fake_home)"
S="$h/.claude/settings.json"
before="$(sum "$S")"
out="$(run_setup "$h" plan --targets claude)"; rc=$?
judge "plan exits 0" 0 "$rc"
judge "plan does not modify settings.json" "$before" "$(sum "$S")"
judge "plan creates no CLAUDE.md" no "$(exists "$h/.claude/CLAUDE.md")"
judge "plan creates no agents dir" no "$(exists "$h/.claude/agents")"
judge "plan creates no backup" no "$(exists "${S}.pre-tamirs-superpowers")"
judge "plan says nothing was written" yes "$(has "$out" 'Nothing has been written')"

# --dry-run is the same verb by another name.
before="$(sum "$S")"
run_setup "$h" apply --dry-run --targets claude >/dev/null 2>&1
judge "--dry-run does not write either" "$before" "$(sum "$S")"

# ---------------------------------------------------------------------------
section "apply --yes is non-interactive and writes"

h="$(fake_home)"
S="$h/.claude/settings.json"
out="$(run_setup "$h" apply --yes --targets claude)"; rc=$?
judge "apply --yes exits 0" 0 "$rc"
if [ -d "$REPO_ROOT/platforms/claude/settings.d" ]; then
  judge "settings.json gained the canonical model" '"opus[1m]"' "$(jq -c '.model' "$S")"
  judge "settings.json gained permissions.defaultMode" '"bypassPermissions"' "$(jq -c '.permissions.defaultMode' "$S")"
  judge "no _comment metadata key leaked into settings.json" '[]' "$(jq -c '[keys[] | select(startswith("_"))]' "$S")"
else
  skip "canonical settings.d assertions" "platforms/claude/settings.d/ not present in this checkout"
fi
judge "statusLine was wired" '"command"' "$(jq -c '.statusLine.type' "$S")"
judge "agents were installed" yes "$(exists "$h/.claude/agents")"
judge "global CLAUDE.md was installed" yes "$(exists "$h/.claude/CLAUDE.md")"

# ---------------------------------------------------------------------------
section "merge never clobbers third-party wiring"

judge "a pre-existing permission entry survives" 0 "$(jq -c '.permissions.allow | index("Bash(cmux *)")' "$S")"
judge "a third-party enabledPlugins key survives" true "$(jq -c '.enabledPlugins["gortex@third-party"]' "$S")"

# ---------------------------------------------------------------------------
section "the fixed backup name exists so remove can find it"

judge "backup written under the fixed name" yes "$(exists "${S}.pre-tamirs-superpowers")"
judge "backup is the file as it was before we ran" light "$(jq -r '.theme' "${S}.pre-tamirs-superpowers")"

# ---------------------------------------------------------------------------
section "idempotence — the second apply changes nothing"

after_first="$(sum "$S")"
out="$(run_setup "$h" apply --yes --targets claude)"; rc=$?
judge "second apply exits 0" 0 "$rc"
judge "second apply reports nothing to do" yes "$(has "$out" 'Everything is already up to date')"
judge "second apply leaves the file byte-identical" "$after_first" "$(sum "$S")"
judge "second apply does not rotate a new backup" 1 \
  "$(find "$h/.claude" -name 'settings.json.pre-tamirs-superpowers*' | wc -l | tr -d ' ')"

# ---------------------------------------------------------------------------
section "remove is symmetric with apply"

out="$(run_setup "$h" remove --yes --targets claude)"; rc=$?
judge "remove exits 0" 0 "$rc"
judge "remove restores the pre-install settings" light "$(jq -r '.theme' "$S")"
judge "remove restores the third-party plugin key" true "$(jq -c '.enabledPlugins["gortex@third-party"]' "$S")"
judge "remove drops the keys we added" null "$(jq -c '.statusLine' "$S")"
judge "remove deletes the CLAUDE.md it created" no "$(exists "$h/.claude/CLAUDE.md")"
judge "remove deletes the agents it installed" 0 \
  "$(find "$h/.claude/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"

out="$(run_setup "$h" remove --yes --targets claude)"
judge "a second remove is a no-op" yes "$(has "$out" 'Everything is already up to date')"

# ---------------------------------------------------------------------------
section "no TTY: print the plan, exit 0, write nothing, never block"

# THE failure this repo has actually been bitten by: a script that waits on an
# inherited descriptor takes the whole session down. setup.sh never reads stdin,
# so closing it must change nothing except that we decline to prompt.
h="$(fake_home)"
S="$h/.claude/settings.json"
before="$(sum "$S")"
out="$(HOME="$h" bash "$SETUP" apply --targets claude </dev/null 2>&1)"; rc=$?
judge "no-TTY apply exits 0" 0 "$rc"
judge "no-TTY apply writes nothing" "$before" "$(sum "$S")"
judge "no-TTY apply says why and how to proceed" yes "$(has "$out" 'no TTY')"
judge "no-TTY apply names --yes as the way out" yes "$(has "$out" 're-run with --yes')"

# The same run with stdin held open on a pipe that never delivers: if anything
# read stdin instead of /dev/tty, this would hang and the timeout would fire.
if harness_have portable_timeout || command -v perl >/dev/null 2>&1; then
  start="$(date +%s)"
  ( sleep 30 | HOME="$h" bash "$SETUP" apply --targets claude >/dev/null 2>&1 ) &
  pid=$!
  waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 20 ]; do
    sleep 1; waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null
    bad "apply with an open, silent stdin does not block" "still running after ${waited}s"
  else
    ok "apply with an open, silent stdin does not block (${waited}s)"
  fi
  wait "$pid" 2>/dev/null
  : "$start"
else
  skip "stdin-block check" "no timeout mechanism available"
fi

# ---------------------------------------------------------------------------
section "no-TTY default verb is plan, not apply"

h="$(fake_home)"
before="$(sum "$h/.claude/settings.json")"
out="$(HOME="$h" bash "$SETUP" --targets claude </dev/null 2>&1)"; rc=$?
judge "bare invocation with no TTY exits 0" 0 "$rc"
judge "bare invocation with no TTY writes nothing" "$before" "$(sum "$h/.claude/settings.json")"

# ---------------------------------------------------------------------------
section "--only narrows the run, and matches a module family"

h="$(fake_home)"
S="$h/.claude/settings.json"
run_setup "$h" apply --yes --targets claude --only statusline >/dev/null 2>&1
judge "--only statusline wires the statusline" '"command"' "$(jq -c '.statusLine.type' "$S")"
judge "--only statusline does not install agents" no "$(exists "$h/.claude/agents")"
judge "--only statusline does not touch the model" null "$(jq -c '.model' "$S")"

out="$(run_setup "$h" plan --targets claude --only notifications)"
judge "--only notifications matches both notifications-* modules" 2 \
  "$(printf '%s\n' "$out" | grep -c 'pushover')"

# ---------------------------------------------------------------------------
section "targets not yet implemented are reported, not hidden"

h="$(fake_home)"
mkdir -p "$h/.cursor"
out="$(run_setup "$h" plan --targets cursor)"
judge "cursor is planned" yes "$(has "$out" 'Cursor')"
judge "cursor says it has no modules yet" yes "$(has "$out" 'no modules implemented yet')"

# ---------------------------------------------------------------------------
section "--json is parseable and describes the same plan"

h="$(fake_home)"
json="$(HOME="$h" bash "$SETUP" plan --targets claude --json 2>/dev/null)"
if printf '%s' "$json" | jq empty 2>/dev/null; then
  ok "--json emits one parseable document on stdout"
  judge "--json reports the verb" '"plan"' "$(printf '%s' "$json" | jq -c '.verb')"
  judge "--json lists the claude target" '"claude"' "$(printf '%s' "$json" | jq -c '.targets[0].name')"
  judge "--json has a change list" yes \
    "$(if [ "$(printf '%s' "$json" | jq '.changes | length')" -gt 0 ]; then echo yes; else echo no; fi)"
else
  bad "--json emits one parseable document on stdout" "$(printf '%s' "$json" | head -3)"
fi
judge "--json still writes nothing" no "$(exists "$h/.claude/CLAUDE.md")"

# ---------------------------------------------------------------------------
section "env twins work for CI"

h="$(fake_home)"
S="$h/.claude/settings.json"
before="$(sum "$S")"
HOME="$h" SETUP_TARGETS=claude SETUP_ONLY=statusline SETUP_YES=1 bash "$SETUP" apply >/dev/null 2>&1
judge "SETUP_YES + SETUP_TARGETS + SETUP_ONLY apply" '"command"' "$(jq -c '.statusLine.type' "$S")"
judge "SETUP_ONLY still narrowed the run" no "$(exists "$h/.claude/agents")"
[ "$before" = "$(sum "$S")" ] && bad "env twins actually wrote something" "file unchanged" || ok "env twins actually wrote something"

# ---------------------------------------------------------------------------
section "the real ~/.claude was never touched"

judge "real HOME witness unchanged" "$REAL_HOME_BEFORE" "$(guard_real_home)"

harness_summary
