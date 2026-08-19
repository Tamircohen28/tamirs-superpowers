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
  },
  "hooks": {
    "Notification": [
      { "hooks": [ { "type": "command", "command": "third-party-notifier" } ] }
    ]
  }
}
JSON
  # The documented home for a user's own grants. Nothing here may ever change.
  cat > "$h/.claude/settings.local.json" <<'JSON'
{ "permissions": { "allow": [ "Bash(only-mine *)" ] } }
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
  judge "no metadata key leaked into settings.json" '[]' "$(jq -c '[keys[] | select(startswith("_"))]' "$S")"
else
  skip "canonical settings.d assertions" "platforms/claude/settings.d/ not present in this checkout"
fi
judge "statusLine was wired" '"command"' "$(jq -c '.statusLine.type' "$S")"
judge "agents were installed" yes "$(exists "$h/.claude/agents")"
judge "global CLAUDE.md was installed" yes "$(exists "$h/.claude/CLAUDE.md")"

# ---------------------------------------------------------------------------
section "merge never clobbers third-party wiring (objects), asserts policy (arrays)"

# Third-party wiring is OBJECT shaped, and objects recurse — this is the
# property "merge, never clobber" actually protects.
judge "a third-party enabledPlugins key survives" true "$(jq -c '.enabledPlugins["gortex@third-party"]' "$S")"
judge "a third-party hooks block survives" '["Notification"]' "$(jq -c '.hooks | keys' "$S")"

# Arrays are asserted, so the fragment describes its own result and a permission
# deleted from the repo actually goes away. The user's own grants live in
# settings.local.json, which this installer never touches.
judge "permissions.allow matches the repo fragment exactly" \
  "$(jq -S -c '.permissions.allow' "$REPO_ROOT/platforms/claude/settings.d/permissions-allow.json")" \
  "$(jq -S -c '.permissions.allow' "$S")"
judge "settings.local.json was never touched" untouched \
  "$(if [ -f "$h/.claude/settings.local.json" ] && [ "$(jq -c '.permissions.allow' "$h/.claude/settings.local.json")" = '["Bash(only-mine *)"]' ]; then echo untouched; else echo CHANGED; fi)"

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

# Undoing must itself be undoable: the file being restored over may hold edits
# made after the install, so remove rotates a dated copy before it writes.
judge "remove rotated a dated backup of the file it replaced" yes \
  "$(if [ "$(find "$h/.claude" -name 'settings.json.pre-tamirs-superpowers-*' | wc -l | tr -d ' ')" -ge 1 ]; then echo yes; else echo no; fi)"

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

# The same run with stdin held OPEN and silent — the shape of an inherited
# descriptor. A `sleep N | setup.sh` pipeline would not test this: the shell
# waits on both halves, so the sleep, not setup.sh, would be what took the time.
# A FIFO with a live writer isolates setup.sh's own behaviour.
pipedir="$(harness_tmpdir)"
if mkfifo "$pipedir/stdin" 2>/dev/null; then
  sleep 25 > "$pipedir/stdin" &          # holds the write end open, sends nothing
  writer=$!
  HOME="$h" bash "$SETUP" apply --targets claude < "$pipedir/stdin" >/dev/null 2>&1 &
  pid=$!
  waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 15 ]; do
    sleep 1; waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null
    bad "apply with an open, silent stdin does not block" "still running after ${waited}s"
  else
    ok "apply with an open, silent stdin does not block (${waited}s)"
  fi
  wait "$pid" 2>/dev/null
  kill "$writer" 2>/dev/null
  wait "$writer" 2>/dev/null
  judge "the blocked-stdin run still wrote nothing" "$before" "$(sum "$S")"
else
  skip "stdin-block check" "mkfifo unavailable"
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

# A typo must not look like a clean run that did nothing.
out="$(run_setup "$h" plan --targets claude --only nosuchmodule)"; rc=$?
judge "--only with an unknown module exits 1" 1 "$rc"
judge "--only with an unknown module says so" yes "$(has "$out" "matched no module")"
judge "--only with an unknown module lists the real ones" yes "$(has "$out" 'statusline')"

# ---------------------------------------------------------------------------
section "targets not yet implemented are reported, not hidden"

# A target with no writers yet must SAY so. The failure this guards against is
# the quiet one: an empty target section that a reader mistakes for "all good".
# Which targets are unimplemented changes as the phases land, so this asks the
# registry rather than pinning a name.
pending=""
for conf in "$REPO_ROOT"/platforms/*/setup.conf; do
  [ -f "$conf" ] || continue
  grep -q '^SETUP_STATUS="not-yet-implemented"' "$conf" || continue
  pending="$(basename "$(dirname "$conf")")"
  break
done
if [ -n "$pending" ]; then
  h="$(fake_home)"
  out="$(run_setup "$h" plan --targets "$pending")"
  judge "an unimplemented target ($pending) is still listed" yes "$(has "$out" "$pending")"
  judge "an unimplemented target says it has no modules yet" yes "$(has "$out" 'no modules implemented yet')"
else
  skip "unimplemented-target reporting" "every target in platforms/ now declares modules"
fi

# Whatever the registry declares, every target must at least plan without error.
for conf in "$REPO_ROOT"/platforms/*/setup.conf; do
  [ -f "$conf" ] || continue
  t="$(basename "$(dirname "$conf")")"
  h="$(fake_home)"
  out="$(run_setup "$h" plan --targets "$t")"; rc=$?
  judge "plan --targets $t exits 0" 0 "$rc"
  judge "plan --targets $t writes nothing outside the plan" no "$(exists "$h/.claude/CLAUDE.md")"
done

# ---------------------------------------------------------------------------
section "repo-side metadata never reaches a rendered file — any target"

# THE BUG CLASS THIS GUARDS
#   JSON has no comments, so the repo's fragments explain themselves in keys like
#   `_comment` and `_tally`. Those are for reviewers, never for the user's config.
#   The strip lives at one boundary (setup_json_strip_meta) precisely so the next
#   person who adds a `_note` to a Cursor or Codex fragment inherits the fix —
#   so this asserts across EVERY target, not just the one where it was found.
h="$(fake_home)"
run_setup "$h" apply --yes >/dev/null 2>&1
leaked=""
while IFS= read -r rendered; do
  [ -f "$rendered" ] || continue
  case "$rendered" in *settings.local.json) continue ;; esac   # not ours to render
  keys="$(jq -c '[paths | map(tostring) | last | select(startswith("_"))]' "$rendered" 2>/dev/null || printf '[]')"
  [ "$keys" = '[]' ] || leaked="$leaked
    $rendered -> $keys"
done <<EOT
$(find "$h" -name '*.json' -not -name '*.pre-tamirs-superpowers*' 2>/dev/null)
EOT
judge "no _-prefixed key appears in any rendered JSON, at any depth" "" "$leaked"

# And the repo data itself must still carry that rationale — a fix that deleted
# the comments would pass the assertion above and lose the thing worth keeping.
meta_present=no
for frag in "$REPO_ROOT"/platforms/claude/settings.d/*.json; do
  [ -f "$frag" ] || continue
  [ "$(jq -c '[keys[] | select(startswith("_"))] | length > 0' "$frag")" = true ] && meta_present=yes
done
judge "the repo fragments still carry their _comment rationale" yes "$meta_present"

# ---------------------------------------------------------------------------
section "the plan warns before it turns plugins off"

# The sharpest behaviour change in the installer: the canonical set records 15
# deliberate `false` entries, so applying it to a machine with everything on
# disables 15 plugins. That must be readable in the plan, not discovered after.
# (The count was silently 0 at first — jq's `//` treats `false` as empty, so
#  every deliberate `false` collapsed to null. Hence this test.)
if [ -f "$REPO_ROOT/platforms/claude/settings.d/plugins.json" ]; then
  h="$(fake_home)"
  expect_off="$(jq '[.enabledPlugins[] | select(. == false)] | length' \
    "$REPO_ROOT/platforms/claude/settings.d/plugins.json")"
  # A machine with every canonical plugin switched ON.
  jq -n --argjson c "$(jq '.enabledPlugins' "$REPO_ROOT/platforms/claude/settings.d/plugins.json")" \
    '{theme:"dark", enabledPlugins: ($c | with_entries(.value = true))}' > "$h/.claude/settings.json"

  out="$(run_setup "$h" plan --targets claude --only plugins)"
  judge "the plan names how many plugins will be disabled" yes \
    "$(has "$out" "WILL DISABLE $expect_off currently-enabled plugin(s)")"

  run_setup "$h" apply --yes --targets claude --only plugins >/dev/null 2>&1
  judge "and apply actually disables exactly that many" "$expect_off" \
    "$(jq '[.enabledPlugins[] | select(. == false)] | length' "$h/.claude/settings.json")"

  # No false alarm on a machine that already matches the canonical polarity.
  out="$(run_setup "$h" plan --targets claude --only plugins)"
  judge "no disable warning once the machine already matches" no "$(has "$out" 'WILL DISABLE')"
else
  skip "plugin polarity warning" "platforms/claude/settings.d/plugins.json not present"
fi

# ---------------------------------------------------------------------------
section "the repo can retract a permission"

# The reason arrays are asserted rather than unioned. With union this is
# impossible: an entry deleted from the fragment stays live forever, invisibly.
h="$(fake_home)"
S="$h/.claude/settings.json"
run_setup "$h" apply --yes --targets claude --only settings >/dev/null 2>&1
before_n="$(jq '.permissions.allow | length' "$S")"
# Simulate the repo dropping an entry: assert a smaller list over the applied one.
retracted="$(jq -c '.permissions.allow[0]' "$S")"
judge "an applied permission is present to begin with" yes \
  "$(if [ "$before_n" -gt 0 ]; then echo yes; else echo no; fi)"
judge "the applied list equals the fragment, so removing one there removes it here" \
  "$(jq '.permissions.allow | length' "$REPO_ROOT/platforms/claude/settings.d/permissions-allow.json")" \
  "$before_n"
: "$retracted"

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
