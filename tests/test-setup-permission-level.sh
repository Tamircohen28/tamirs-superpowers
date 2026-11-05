#!/usr/bin/env bash
# test-setup-permission-level.sh — the setup-time permission level step and the
# optional Codex execpolicy rules (ADR 004 item 9: D3, D7, D8, D10).
#
# WHAT IS PINNED
#   * setup writes the user file exactly where the resolver reads it, 0600 in a
#     0700 dir, with a lock the resolver accepts (`resolve-permission.sh --level`
#     reports the level from `user_file`);
#   * a run that cannot prompt never writes without --permission-level, never
#     changes an existing file and never raises one;
#   * the interactive prompt (driven with injected answers, below) maps its
#     choices, keeps other keys, shows a diff, defaults to No and re-locks an
#     unverified file only after showing it in full;
#   * Claude Code and Gemini CLI get a note instead of a second prompt;
#   * the Codex rules file appears only on opt-in and only this installer's own
#     file is ever removed.
#
# NOTHING TOUCHES THE REAL HOME
#   HOME is a temp tree for every setup run. The permission file is not under
#   HOME but under the passwd home (D3), so every run also points
#   TAMIRS_PERMISSION_TEST_ROOT at a temp root. The resolver library honours that
#   variable only when an ANCESTOR shell is running one of the permission suites,
#   this one included (scripts/lib/permission-common.sh, "THE TEST OVERRIDE AND
#   ITS GUARD"), so every run is simply a child of this script. setup itself
#   refuses to write when the variable is set and the library refused it, and the
#   suite aborts before any write if the override is not honoured. A witness on
#   the real config dir is compared at the end.
#
# HOW THE PROMPT IS DRIVEN
#   CI has no TTY, and setup reads /dev/tty only. The interactive cases source
#   scripts/lib/setup-common.sh and replace setup_can_prompt and setup_ask — the
#   two functions every setup prompt goes through — with ones that answer from a
#   file and count the questions.
#
# Usage: bash tests/test-setup-permission-level.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require jq python3
SETUP="$REPO_ROOT/scripts/setup.sh"
RESOLVE="$REPO_ROOT/scripts/resolve-permission.sh"

# Inputs that would change a result or redirect a write.
unset CODEX_HOME CURSOR_CONFIG_DIR OPENCODE_CONFIG_DIR GEMINI_CONFIG_DIR CLAUDE_CONFIG_DIR XDG_CONFIG_HOME \
  TS_PERMISSION_LEVEL CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL TAMIRS_AUTO_MERGE \
  SETUP_YES SETUP_TARGETS SETUP_ONLY SETUP_DESTRUCTIVE SETUP_PERMISSION_LEVEL SETUP_CODEX_RULES \
  TAMIRS_PERMISSION_TEST_ROOT TAMIRS_PERMISSION_TEST_SESSION
export NO_COLOR=1
# setup writes through scripts/plugin-config.sh, which finds the agent session it
# runs in from its process ancestry (ADR 004 D5) -- and this suite may itself run
# under an agent. Under the test root (and only there) the writer honours this
# override; "none" is the user's own terminal, which is what setup is.
export TAMIRS_PERMISSION_TEST_SESSION=none

REAL_PASSWD_HOME="$(python3 -I -S -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
REAL_CFG="$REAL_PASSWD_HOME/.config/tamirs-superpowers"
witness() { ls -lA "$REAL_CFG" 2>/dev/null | shasum | awk '{print $1}'; }
REAL_BEFORE="$(witness)"

FIX="$(harness_tmpdir)"
NOWHERE="$(harness_tmpdir)"   # cwd for every run: no repository, no project file

new_root() { local r; r="$(harness_tmpdir)"; chmod 700 "$r"; printf '%s' "$r"; }
in_root() { local root="$1"; shift; (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$root" "$@"); }
setup_in() { local root="$1" home="$2"; shift 2; in_root "$root" env HOME="$home" bash "$SETUP" "$@" 2>&1; }
level_of() { in_root "$1" bash "$RESOLVE" --level --json --host "${2:-codex}" 2>/dev/null; }
pfile() { printf '%s/.config/tamirs-superpowers/permissions.json' "$1"; }
plock() { printf '%s/.config/tamirs-superpowers/permissions.lock' "$1"; }
mode_of() { python3 -I -S -c 'import os, stat, sys; print("%o" % stat.S_IMODE(os.stat(sys.argv[1]).st_mode))' "$1" 2>/dev/null || printf 'MISSING'; }
sum() { [ -f "$1" ] && shasum "$1" | awk '{print $1}' || printf 'MISSING'; }
sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }
relock() {   # an independent lock writer: proves the format, not just setup's own
  local root="$1" lk
  lk="$(plock "$root")"
  jq -n --arg s "$(sha256_of "$(pfile "$root")")" '{sha256: $s, by: "plugin-config", at: "2026-11-04T00:00:00Z"}' > "$lk"
  chmod 600 "$lk"
}

# drive <root> <answers...> — run the level step with injected answers (one per
# question; "" = Enter). Env FLAG = --permission-level, ROUTE = prompt route,
# NOTES = host notes. Prints the step's output; the question count lands in
# <root>/asked.
drive() {
  local root="$1" ans; shift
  ans="$root/answers"
  : > "$ans"; printf '0' > "$root/asked"
  for a in "$@"; do printf '%s\n' "$a" >> "$ans"; done
  in_root "$root" env FLAG="${FLAG:-}" ROUTE="${ROUTE:-yes}" NOTES="${NOTES:-}" bash -c '
    set -uo pipefail
    SETUP_REPO_ROOT="$1"; ANS="$2"; COUNT="$3"
    . "$SETUP_REPO_ROOT/scripts/lib/setup-common.sh"
    setup_can_prompt() { return 0; }
    setup_ask() {
      local n a
      n="$(cat "$COUNT")"; n=$((n + 1)); printf "%s" "$n" > "$COUNT"
      a="$(sed -n "${n}p" "$ANS")"
      [ -n "$a" ] || a="$2"
      printf "%s\n" "$1" >&2
      printf "%s" "$a"
    }
    # The library asks through setup_ask_into (answer into a variable, no
    # subshell); route it through the scripted setup_ask above.
    setup_ask_into() { local __a; __a="$(setup_ask "$2" "$3")"; printf -v "$1" "%s" "$__a"; }
    SETUP_PERM_PROMPT_ROUTE="$ROUTE"; SETUP_PERM_NOTES="$NOTES"; SETUP_PERMISSION_LEVEL="$FLAG"
    setup_permission_level_step apply
    echo "STEP_RC=$?"
  ' drive "$REPO_ROOT" "$ans" "$root/asked" 2>&1
}

# ---------------------------------------------------------------------------
section "the test root is honoured (precondition for every write below)"

ROOT="$(new_root)"
src="$(in_root "$ROOT" bash -c '. "$1"; perm_dirs' x "$REPO_ROOT/scripts/lib/permission-common.sh" 2>/dev/null | jq -r '.home_source')"
if [ "$src" != test-root ]; then
  bad "the resolver honours TAMIRS_PERMISSION_TEST_ROOT under this suite" "home_source=$src"
  printf 'FATAL: refusing to run write cases: they would target the real home\n'
  harness_summary
fi
ok "the resolver honours TAMIRS_PERMISSION_TEST_ROOT under this suite"

# When the library refuses the root, setup must refuse to write rather than fall
# through to the passwd home. Refused two ways: a root that is not 0700, and a
# process orphaned away from this suite (its ancestry runs no permission suite).
# Only the path resolution is exercised here; nothing is written.
paths_probe='SETUP_REPO_ROOT="$1"; . "$SETUP_REPO_ROOT/scripts/lib/setup-common.sh"
  setup_perm_paths; printf "%s|%s" "$SETUP_PERM_HOME_SOURCE" "${SETUP_PERM_WRITABLE%%:*}"'
LOOSE="$(new_root)"; chmod 755 "$LOOSE"
got="$(in_root "$LOOSE" bash -c "$paths_probe" x "$REPO_ROOT" 2>/dev/null)"
judge "a refused test root (mode 0755) makes setup refuse to write" "passwd|no" "$got"
OD="$(harness_tmpdir)"
( exec /bin/sh -c 'sleep 1; cd "$4"; TAMIRS_PERMISSION_TEST_ROOT="$1" bash -c "$5" x "$2" > "$3/out" 2>/dev/null; echo $? > "$3/rc"' \
    sh "$ROOT" "$REPO_ROOT" "$OD" "$NOWHERE" "$paths_probe" >/dev/null 2>&1 & )
n=0
while [ ! -s "$OD/rc" ] && [ "$n" -lt 150 ]; do sleep 0.1; n=$((n + 1)); done
judge "a root refused by ancestry (orphaned process) makes setup refuse to write" "passwd|no" "$(cat "$OD/out" 2>/dev/null)"

# ---------------------------------------------------------------------------
section "non-interactive: no flag writes nothing"

ROOT="$(new_root)"; H="$(harness_tmpdir)"
out="$(setup_in "$ROOT" "$H" apply --yes --targets codex --only permission-level)"; rc=$?
judge "apply --yes with no flag exits 0" 0 "$rc"
judge "apply --yes with no flag writes no file" no "$(exists "$(pfile "$ROOT")")"
judge "it says why nothing was written" yes "$(has "$out" 'nothing written (no terminal to ask on)')"
judge "the resolver still answers supervised" supervised "$(level_of "$ROOT" | jq -r .level)"

out="$(setup_in "$ROOT" "$H" apply --targets codex --permission-level standard </dev/null)"; rc=$?
judge "no TTY and no --yes: exits 0" 0 "$rc"
judge "no TTY and no --yes: a flag only plans" no "$(exists "$(pfile "$ROOT")")"
judge "no TTY and no --yes: says what apply would do" yes "$(has "$out" 'apply would set the level to standard')"

out="$(setup_in "$ROOT" "$H" plan --targets codex --permission-level unattended)"
judge "plan with a flag writes nothing" no "$(exists "$(pfile "$ROOT")")"

out="$(setup_in "$ROOT" "$H" apply --yes --targets codex --permission-level root)"; rc=$?
judge "an unknown level is a usage error" 1 "$rc"
judge "the error names the known levels" yes "$(has "$out" 'known: supervised,standard,unattended')"

# ---------------------------------------------------------------------------
section "--permission-level writes the file the resolver reads"

out="$(setup_in "$ROOT" "$H" apply --yes --targets codex --only permission-level --permission-level standard)"; rc=$?
judge "--permission-level standard --yes exits 0" 0 "$rc"
judge "the user file exists" yes "$(exists "$(pfile "$ROOT")")"
judge "the user file is 0600" 600 "$(mode_of "$(pfile "$ROOT")")"
judge "its dir is 0700" 700 "$(mode_of "$ROOT/.config/tamirs-superpowers")"
judge "the lock is 0600" 600 "$(mode_of "$(plock "$ROOT")")"
judge "the file holds version 1 and the level" '{"level":"standard","version":1}' "$(jq -c -S . "$(pfile "$ROOT")")"
judge "the lock hashes the exact bytes" "$(sha256_of "$(pfile "$ROOT")")" "$(jq -r .sha256 "$(plock "$ROOT")")"
judge "the lock is the D6 writer's" plugin-config "$(jq -r .by "$(plock "$ROOT")")"
lv="$(level_of "$ROOT")"
judge "resolve-permission.sh --level reads standard" standard "$(printf '%s' "$lv" | jq -r .level)"
judge "from the user file" user_file.level "$(printf '%s' "$lv" | jq -r .level_source)"
judge "and reads it as verified" verified "$(printf '%s' "$lv" | jq -r '.level_sources[] | select(.source == "user_file") | .state')"
judge "the run says it was written" yes "$(has "$out" 'written: level standard')"
judge "HOME got no permission file" no "$(exists "$H/.config/tamirs-superpowers")"

# ---------------------------------------------------------------------------
section "non-interactive never changes an existing file, and never raises it"

before="$(sum "$(pfile "$ROOT")")"; lock_before="$(sum "$(plock "$ROOT")")"
out="$(setup_in "$ROOT" "$H" apply --yes --targets codex --only permission-level --permission-level unattended)"; rc=$?
judge "a non-interactive raise exits 1" 1 "$rc"
judge "a non-interactive raise leaves the file" "$before" "$(sum "$(pfile "$ROOT")")"
judge "and the lock" "$lock_before" "$(sum "$(plock "$ROOT")")"
judge "it says it was not raised" yes "$(has "$out" 'not raised (standard -> unattended)')"
judge "it shows the diff it refused" yes "$(has "$out" '+  "level": "unattended"')"
judge "the resolver still reads standard" standard "$(level_of "$ROOT" | jq -r .level)"

out="$(setup_in "$ROOT" "$H" apply --yes --targets codex --only permission-level --permission-level supervised)"; rc=$?
judge "a non-interactive lowering of an existing file exits 1" 1 "$rc"
judge "and leaves the file (a diff needs a terminal confirmation)" "$before" "$(sum "$(pfile "$ROOT")")"
judge "it says a terminal confirmation is needed" yes "$(has "$out" 'changes only after you confirm its diff on a terminal')"

out="$(setup_in "$ROOT" "$H" apply --yes --targets codex --only permission-level --permission-level standard)"; rc=$?
judge "the same level again exits 0" 0 "$rc"
judge "and is a no-op" yes "$(has "$out" 'already standard')"
judge "the file is byte-identical" "$before" "$(sum "$(pfile "$ROOT")")"

out="$(setup_in "$ROOT" "$H" apply --yes --targets codex --only permission-level)"; rc=$?
judge "no flag, existing file: kept" yes "$(has "$out" 'kept as is (no terminal to ask on)')"
judge "and untouched" "$before" "$(sum "$(pfile "$ROOT")")"

out="$(setup_in "$ROOT" "$H" remove --yes --targets codex --only permission-level)"; rc=$?
judge "remove exits 0" 0 "$rc"
judge "remove leaves the user's policy file" "$before" "$(sum "$(pfile "$ROOT")")"
judge "remove says it is left in place" yes "$(has "$out" 'left in place')"

# ---------------------------------------------------------------------------
section "interactive prompt (injected answers)"

R1="$(new_root)"
out="$(drive "$R1" 3)"
judge "choice 3 on an absent file writes unattended" unattended "$(jq -r .level "$(pfile "$R1")" 2>/dev/null)"
judge "one question was asked" 1 "$(cat "$R1/asked")"
judge "the menu explains each level" yes "$(has "$out" 'still asks before merging, closing or deleting anything')"
judge "the menu names where it is stored" yes "$(has "$out" '.config/tamirs-superpowers/permissions.json')"
judge "the resolver reads unattended" unattended "$(level_of "$R1" | jq -r .level)"
judge "the step returned 0" yes "$(has "$out" 'STEP_RC=0')"

R2="$(new_root)"
drive "$R2" "" >/dev/null
judge "Enter on an absent file records the default, supervised" supervised "$(jq -r .level "$(pfile "$R2")" 2>/dev/null)"

R3="$(new_root)"
drive "$R3" k >/dev/null
judge "k keeps: no file written" no "$(exists "$(pfile "$R3")")"
drive "$R3" x y z >/dev/null
judge "three unrecognised answers keep: no file" no "$(exists "$(pfile "$R3")")"
judge "and stop asking after three" 3 "$(cat "$R3/asked")"
drive "$R3" unattended >/dev/null
judge "a level name is accepted as an answer" unattended "$(jq -r .level "$(pfile "$R3")" 2>/dev/null)"

# An existing file: other keys survive, the diff is shown, the default is No.
jq '. + {skills: {"pr-dev": "standard"}}' "$(pfile "$R1")" > "$R1/tmp" && cat "$R1/tmp" > "$(pfile "$R1")"
relock "$R1"
judge "an independently written lock verifies too" verified \
  "$(level_of "$R1" | jq -r '.level_sources[] | select(.source == "user_file") | .state')"
before="$(sum "$(pfile "$R1")")"
out="$(drive "$R1" 1 "")"
judge "Enter at the confirm question means No" "$before" "$(sum "$(pfile "$R1")")"
judge "the diff was shown before asking" yes "$(has "$out" '+  "level": "supervised"')"
judge "two questions: level, then confirm" 2 "$(cat "$R1/asked")"
out="$(drive "$R1" 1 n)"
judge "n at the confirm question keeps the file" "$before" "$(sum "$(pfile "$R1")")"
out="$(drive "$R1" 1 y)"
judge "y writes the lower level" supervised "$(jq -r .level "$(pfile "$R1")")"
judge "every other key is kept" '{"pr-dev":"standard"}' "$(jq -c .skills "$(pfile "$R1")")"
judge "the rewritten file is still 0600" 600 "$(mode_of "$(pfile "$R1")")"
judge "the resolver reads supervised, verified" "supervised verified" \
  "$(level_of "$R1" | jq -r '[.level, (.level_sources[] | select(.source == "user_file") | .state)] | join(" ")')"
out="$(drive "$R1" "")"
judge "Enter on an existing file keeps its level: nothing to do" yes "$(has "$out" 'already supervised')"

# A file edited behind the lock: shown in full, re-locked only on confirmation.
jq '.level = "unattended"' "$(pfile "$R1")" > "$R1/tmp" && cat "$R1/tmp" > "$(pfile "$R1")"
judge "a file edited behind its lock reads tighten-only" tighten-only \
  "$(level_of "$R1" | jq -r '.level_sources[] | select(.source == "user_file") | .state')"
out="$(drive "$R1" 2 y)"
judge "changing it warns that it is not verified" yes "$(has "$out" 'is not verified')"
judge "and that confirming re-locks all of it" yes "$(has "$out" 're-locks ALL of its content')"
judge "after confirming it is verified again" "standard verified" \
  "$(level_of "$R1" | jq -r '[.level, (.level_sources[] | select(.source == "user_file") | .state)] | join(" ")')"

# A flag on a terminal: no level question, the confirm still applies.
out="$(FLAG=unattended drive "$R1" y)"
judge "a flag on a terminal asks only the confirm question" 1 "$(cat "$R1/asked")"
judge "and raises once confirmed" unattended "$(jq -r .level "$(pfile "$R1")")"

# An invalid file is never touched, by either path.
R4="$(new_root)"
mkdir -p "$R4/.config/tamirs-superpowers" && chmod 700 "$R4/.config/tamirs-superpowers"
printf 'not json\n' > "$(pfile "$R4")"; chmod 600 "$(pfile "$R4")"
before="$(sum "$(pfile "$R4")")"
out="$(drive "$R4" 2 y)"
judge "an invalid file: no question asked" 0 "$(cat "$R4/asked")"
judge "an invalid file is not touched interactively" "$before" "$(sum "$(pfile "$R4")")"
judge "it says why" yes "$(has "$out" 'is not touched while it is invalid')"
out="$(setup_in "$R4" "$H" apply --yes --targets codex --only permission-level --permission-level standard)"; rc=$?
judge "an invalid file with a flag exits 1" 1 "$rc"
judge "and is not touched" "$before" "$(sum "$(pfile "$R4")")"

# ---------------------------------------------------------------------------
section "the write goes through the D6 writer (scripts/plugin-config.sh)"

R7="$(new_root)"
out="$(setup_in "$R7" "$H" apply --yes --targets codex --only permission-level --permission-level standard)"
judge "a first write: the writer's lock (by plugin-config), no .bak" "plugin-config|no" \
  "$(jq -r .by "$(plock "$R7")")|$(exists "$(pfile "$R7").bak")"
# Inside an agent session the writer holds a raise pending (D5): setup reports it
# as not written and prints the confirm command.
out="$(FLAG=unattended TAMIRS_PERMISSION_TEST_SESSION=claude drive "$R7" y)"
judge "inside an agent session a raise is not written" standard "$(jq -r .level "$(pfile "$R7")")"
judge "setup says it waits for the confirm" yes "$(has "$out" 'not written yet')"
judge "and prints the writer's confirm command" yes "$(has "$out" 'plugin-config.sh confirm ')"
judge "the step returned 1" yes "$(has "$out" 'STEP_RC=1')"
out="$(FLAG=supervised TAMIRS_PERMISSION_TEST_SESSION=codex drive "$R7" y)"
judge "a lowering is written at once, even in a session with no channel" supervised "$(jq -r .level "$(pfile "$R7")")"
judge "the replaced bytes are kept as permissions.json.bak" standard "$(jq -r .level "$(pfile "$R7").bak" 2>/dev/null)"
judge "the resolver reads the writer's file as verified" "supervised verified" \
  "$(level_of "$R7" | jq -r '[.level, (.level_sources[] | select(.source == "user_file") | .state)] | join(" ")')"

# ---------------------------------------------------------------------------
section "Claude Code and Gemini CLI: a note, not a second prompt (D7)"

R5="$(new_root)"
out="$(ROUTE=no NOTES="Claude Code: the level is the plugin option" drive "$R5")"
judge "no prompt route: no question asked" 0 "$(cat "$R5/asked")"
judge "no prompt route: no file written" no "$(exists "$(pfile "$R5")")"
judge "the note is printed" yes "$(has "$out" 'Claude Code: the level is the plugin option')"

out="$(setup_in "$R5" "$H" apply --yes --targets claude,gemini --only permission-level)"
judge "claude names its own route" yes "$(has "$out" '/config or /plugin configure')"
judge "gemini names its own route" yes "$(has "$out" 'gemini extensions config tamirs-superpowers TS_PERMISSION_LEVEL')"
judge "claude+gemini alone do not run the level step" no "$(has "$out" 'none yet, so every host runs supervised')"
for t in cursor opencode codex; do
  out="$(setup_in "$R5" "$H" apply --yes --targets "$t" --only permission-level)"
  judge "$t (no install-time option) runs the level step" yes "$(has "$out" 'none yet, so every host runs supervised')"
done
out="$(setup_in "$R5" "$H" apply --yes --targets claude --only statusline)"
judge "--only another module skips the level step" no "$(has "$out" 'Permission level')"

# ---------------------------------------------------------------------------
section "Codex execpolicy rules only on opt-in"

R6="$(new_root)"; CH="$(harness_tmpdir)"
RULES="$CH/.codex/rules/tamirs-superpowers.rules"
out="$(setup_in "$R6" "$CH" apply --yes --targets codex)"; rc=$?
judge "apply --yes without opt-in exits 0" 0 "$rc"
judge "apply --yes without opt-in writes no rules file" no "$(exists "$RULES")"
judge "the plan says how to opt in" yes "$(has "$out" 'opt in with --codex-rules')"

out="$(setup_in "$R6" "$CH" plan --targets codex --codex-rules)"
judge "plan --codex-rules writes nothing" no "$(exists "$RULES")"

out="$(setup_in "$R6" "$CH" apply --yes --targets codex --codex-rules)"; rc=$?
judge "apply --codex-rules exits 0" 0 "$rc"
judge "the rules file exists" yes "$(exists "$RULES")"
judge "it starts with this installer's header" \
  "# tamirs-superpowers Codex execpolicy rules -- generated by scripts/setup.sh" "$(head -1 "$RULES" 2>/dev/null)"
judge "it says rules are experimental" yes "$(has "$(cat "$RULES" 2>/dev/null)" 'EXPERIMENTAL')"
judge "an R4 form gets a prompt rule" yes "$(has "$(cat "$RULES" 2>/dev/null)" 'pattern = ["gh", "release", "create"],
    decision = "prompt",')"
judge "a never_auto R3 form gets a prompt rule" yes "$(has "$(cat "$RULES" 2>/dev/null)" 'pattern = ["gh", "pr", "merge"]')"
judge "an R3 id on the unattended list gets none (gh pr close)" no "$(has "$(cat "$RULES" 2>/dev/null)" '"gh", "pr", "close"')"
judge "an R2 form gets none (gh pr create)" no "$(has "$(cat "$RULES" 2>/dev/null)" '"gh", "pr", "create"')"
judge "no wildcard reaches a pattern" no "$(has "$(cat "$RULES" 2>/dev/null)" '"*"')"
judge "every rule is prompt, none forbidden or allow" 0 "$(grep -cE 'decision = "(forbidden|allow)"' "$RULES" 2>/dev/null)"
n_rules="$(grep -c '^prefix_rule(' "$RULES" 2>/dev/null || printf 0)"
judge "one decision per rule" "$n_rules" "$(grep -c 'decision = "prompt"' "$RULES" 2>/dev/null)"

before="$(sum "$RULES")"
out="$(setup_in "$R6" "$CH" apply --yes --targets codex)"
judge "a generated file counts as opted in: apply keeps it current" "$before" "$(sum "$RULES")"
judge "and reports it up to date" 1 "$(printf '%s\n' "$out" | grep 'rules/\*\.rules' | grep -c 'already up to date')"
out="$(setup_in "$R6" "$CH" apply --yes --targets codex --no-codex-rules)"
judge "--no-codex-rules leaves it as it is" "$before" "$(sum "$RULES")"

out="$(setup_in "$R6" "$CH" remove --yes --targets codex --only execpolicy)"; rc=$?
judge "remove --only execpolicy exits 0" 0 "$rc"
judge "remove deletes the generated rules file" no "$(exists "$RULES")"

CH2="$(harness_tmpdir)"
in_root "$R6" env HOME="$CH2" SETUP_CODEX_RULES=1 bash "$SETUP" apply --yes --targets codex --only execpolicy >/dev/null 2>&1
judge "SETUP_CODEX_RULES=1 is the env twin" yes "$(exists "$CH2/.codex/rules/tamirs-superpowers.rules")"

# A file of the same name that the user wrote is theirs.
CH3="$(harness_tmpdir)"; mkdir -p "$CH3/.codex/rules"
printf 'prefix_rule(pattern = ["make"], decision = "prompt")\n' > "$CH3/.codex/rules/tamirs-superpowers.rules"
mine="$(sum "$CH3/.codex/rules/tamirs-superpowers.rules")"
setup_in "$R6" "$CH3" apply --yes --targets codex >/dev/null
judge "a user-written file is not adopted without opt-in" "$mine" "$(sum "$CH3/.codex/rules/tamirs-superpowers.rules")"
setup_in "$R6" "$CH3" remove --yes --targets codex >/dev/null
judge "remove never deletes a user-written file" "$mine" "$(sum "$CH3/.codex/rules/tamirs-superpowers.rules")"

# The opt-in question itself: asked only on an interactive apply, default No.
codex_init() {   # codex_init <interactive yes|no> <answer> -> "<opt>|<questions>|<prompt text>"
  local d; d="$(harness_tmpdir)"
  (cd "$NOWHERE" && bash -c '
    SETUP_REPO_ROOT="$1"; SETUP_INTERACTIVE_APPLY="$2"; ANSWER="$3"; SETUP_TARGET_DIR="$4/.codex"
    SETUP_MODULES="agents-md config"; Q=0
    . "$SETUP_REPO_ROOT/scripts/lib/setup-common.sh"
    . "$SETUP_REPO_ROOT/scripts/lib/setup-codex.sh"
    setup_can_prompt() { return 0; }
    setup_ask() { printf "%s" "${ANSWER:-$2}"; }
    setup_ask_into() { printf -v "$1" "%s" "${ANSWER:-$3}"; }
    codex_target_init 2> "$4/prompt"
    printf "%s|%s|" "$CODEX_RULES_OPT" "$SETUP_MODULES"; cat "$4/prompt"' x "$REPO_ROOT" "$1" "$2" "$d" 2>&1)
}
got="$(codex_init yes y)"
judge "the opt-in question: y opts in" "yes|agents-md config execpolicy" "$(printf '%s' "$got" | head -1 | cut -d'|' -f1,2)"
judge "the opt-in question says rules are experimental" yes "$(has "$got" 'EXPERIMENTAL in Codex')"
judge "the opt-in question: Enter means No" "no" "$(codex_init yes '' | head -1 | cut -d'|' -f1)"
judge "no question outside an interactive apply" "|agents-md config execpolicy|" "$(codex_init no y | head -1)"

# Codex parses what was generated, when Codex is installed (local, no network).
CH4="$(harness_tmpdir)"
setup_in "$R6" "$CH4" apply --yes --targets codex --only execpolicy --codex-rules >/dev/null
if harness_have codex && codex execpolicy --help >/dev/null 2>&1; then
  dec="$(cd "$NOWHERE" && HOME="$CH4" codex execpolicy check --rules "$CH4/.codex/rules/tamirs-superpowers.rules" -- gh release create v1 2>/dev/null | jq -r '.decision // "none"' 2>/dev/null)"
  judge "codex execpolicy check: gh release create asks" prompt "$dec"
  dec="$(cd "$NOWHERE" && HOME="$CH4" codex execpolicy check --rules "$CH4/.codex/rules/tamirs-superpowers.rules" -- gh pr create 2>/dev/null | jq -r '.decision // "none"' 2>/dev/null)"
  judge "codex execpolicy check: gh pr create matches nothing" none "$dec"
else
  skip "codex execpolicy check" "codex CLI not installed"
fi

# ---------------------------------------------------------------------------
section "the real config dir was never touched"

judge "real $REAL_CFG witness unchanged" "$REAL_BEFORE" "$(witness)"

harness_summary
