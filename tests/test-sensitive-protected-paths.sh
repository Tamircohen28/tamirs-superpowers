#!/usr/bin/env bash
# test-sensitive-protected-paths.sh — security review S-03:
# guard-sensitive-files.sh denies writes to the installed plugin's guard files
# and every host settings store, by realpath, with no override.
#
# WHAT EACH GROUP PROVES
#   - every protected location is denied through Edit/Write AND through Bash
#     (cp, sed -i, python3 -c / heredoc, >, tee, mv, rm, ln -s);
#   - the home those locations hang off is the passwd entry, not $HOME — and a
#     different $HOME only adds a second protected home, never moves the first;
#   - a symlink, or a symlinked parent directory, does not carry a write past
#     the check (realpath), and `ln` cannot make a protected file reachable;
#   - an unresolved write (an interpreter, a variable) that NAMES a protected
#     path is a deny, while one that names none stays the advisory it was;
#   - PM_ALLOW_PROTECTED unlocks nothing protected, but still unlocks the
#     generated-file rules (lockfiles) it always did;
#   - the running plugin's guard files: deny in an installed copy; a source
#     checkout is the contributor's own tree and is not protected;
#   - no answer is ever an ask (6.0.0, ADR 006), git replays are not judged, and
#     the plugin's old permission config and state dirs are no longer protected;
#   - no deny text names PM_ALLOW_PROTECTED or the GitHub MCP write tool.
#   Every protected case is paired with a read, a mention or an unprotected
#   neighbour that must stay allowed, so a guard that denies everything fails.
#
# Hermetic: the guard only JUDGES payloads, so the real passwd home is named in
# them but never written; every file and symlink created lives under mktemp.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
# The unresolved-write notice is off by default since 5.6.3; these cases assert it, so turn it on.
export CLAUDE_PLUGIN_OPTION_UNRESOLVED_WRITE_NOTICES=true

harness_require git jq python3

TMP="$(canon "$(harness_tmpdir)")"
PHOME="$(python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
export HOME="$TMP/fakehome"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
unset GH_TOKEN GITHUB_TOKEN PM_ALLOW_PROTECTED CLAUDE_PLUGIN_ROOT CODEX_HOME 2>/dev/null || true

GUARD="$ROOT/hooks/guard-sensitive-files.sh"

REPO="$TMP/repo"
harness_new_repo "$REPO"
mkdir -p "$REPO/.github/workflows" "$REPO/sub" "$REPO/src"
printf 'x\n' > "$REPO/yarn.lock"

# A plugin copy with no .git (an installed cache), and one that is a source checkout.
plugin_copy() {
  mkdir -p "$1/scripts/lib"
  cp -R "$ROOT/hooks" "$1/hooks"
}
INST="$TMP/installed/tamirs-superpowers"; plugin_copy "$INST"
SRC="$TMP/src-plain";                     plugin_copy "$SRC"; git -C "$SRC" init -q

# payload <tool> <command-or-path> [cwd]
payload() {
  jq -n --arg t "$1" --arg c "$2" --arg cwd "${3:-$REPO}" \
     '{tool_name:$t, cwd:$cwd,
       tool_input:(if $t=="Bash" then {command:$c} else {file_path:$c} end)}'
}
# run_guard <guard> <tool> <arg> [cwd] — raw hook JSON
run_guard() { payload "$2" "$3" "${4:-$REPO}" | bash "$1" 2>/dev/null; }
# decision <json> -> deny | ask | warn | allow
decision() {
  printf '%s' "$1" | jq -r '
    if .hookSpecificOutput.permissionDecision=="deny" then "deny"
    elif .hookSpecificOutput.permissionDecision=="ask" then "ask"
    elif .hookSpecificOutput.additionalContext then "warn"
    else "allow" end' 2>/dev/null
}
reason() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
v()    { decision "$(run_guard "$GUARD" "$@")"; }
vb()   { v Bash "$1"; }
vg()   { decision "$(run_guard "$1" "$2" "$3" "${4:-$REPO}")"; }

# ===========================================================================
section "every protected location is denied through Edit/Write"
# ===========================================================================
for rel in \
  .claude/settings.json \
  .claude/settings.local.json \
  .claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/5.1.3/hooks/hooks.json \
  .gemini/settings.json \
  .gemini/policies/user.toml \
  .gemini/extensions/tamirs-superpowers/.env \
  .codex/config.toml \
  .codex/hooks.json \
  .codex/rules/default.rules \
  .codex/plugins/tamirs-superpowers/hooks.json \
  .cursor/hooks.json \
  .cursor/cli-config.json \
  .cursor/permissions.json \
  .config/opencode/opencode.json \
  .config/gh/hosts.yml \
  .gitconfig
do
  judge "Write <passwd home>/$rel" deny "$(v Write "$PHOME/$rel")"
done
for rel in \
  .claude/settings.json \
  .claude/settings.local.json \
  .gemini/settings.json \
  .gemini/policies/p.toml \
  .gemini/extensions/x/gemini-extension.json \
  .cursor/hooks.json \
  opencode.json \
  opencode.jsonc \
  .opencode/opencode.json \
  .opencode/opencode.jsonc \
  .opencode/plugin/x.ts \
  .opencode/plugins/x.ts \
  .opencode/agent/a.md \
  .opencode/agents/a.md \
  .git/hooks/pre-commit \
  .git/config
do
  judge "Edit <repo>/$rel" deny "$(v Edit "$REPO/$rel")"
done
judge "Edit of a repo-relative .claude/settings.json" deny "$(v Edit ".claude/settings.json")"

section "... and their unprotected neighbours are not"
judge "Write <passwd home>/.claude/CLAUDE.md"        allow "$(v Write "$PHOME/.claude/CLAUDE.md")"
judge "Write <passwd home>/.config/other-tool/x"     allow "$(v Write "$PHOME/.config/other-tool/x.json")"
# The permission-levels config and state (5.2-5.6) left the table in 6.0.0 (ADR 006).
judge "the old plugin config dir is not protected"   allow "$(v Write "$PHOME/.config/tamirs-superpowers/x.json")"
judge "the old plugin state dir is not protected"    allow "$(v Write "$PHOME/.local/state/tamirs-superpowers/x/t1")"
judge "a project's old plugin dir is not protected"  allow "$(v Edit "$REPO/.tamirs-superpowers/x.json")"
judge "Edit <repo>/.claude/agents/a.md"              allow "$(v Edit "$REPO/.claude/agents/a.md")"
# D10.1 narrowed: a repository's generated adapters for other hosts are not policy.
judge "Edit <repo>/.gemini/skills/x/SKILL.md"        allow "$(v Edit "$REPO/.gemini/skills/x/SKILL.md")"
judge "Edit <repo>/.gemini/agents/a.md"              allow "$(v Edit "$REPO/.gemini/agents/a.md")"
judge "Edit <repo>/.gemini/GEMINI.md"                allow "$(v Edit "$REPO/.gemini/GEMINI.md")"
judge "Edit <repo>/.opencode/commands/c.md"          allow "$(v Edit "$REPO/.opencode/commands/c.md")"
judge "rm -rf <repo>/.gemini/skills"                 allow "$(vb "rm -rf $REPO/.gemini/skills")"
judge "rm -rf <repo>/.opencode/commands"             allow "$(vb "rm -rf $REPO/.opencode/commands")"
judge "rm -rf <repo>/.gemini (holds settings.json)"  deny  "$(vb "rm -rf $REPO/.gemini")"
judge "rm -rf <repo>/.opencode (holds agents/)"      deny  "$(vb "rm -rf $REPO/.opencode")"
judge "Edit <repo>/src/settings.json"                allow "$(v Edit "$REPO/src/settings.json")"
judge "Edit a .claude/settings.json below a non-root" allow "$(v Edit "$REPO/sub/.claude/settings.json")"

section "the home is the passwd entry; a session HOME only adds one"
judge "HOME is elsewhere, passwd home still denied" deny "$(v Edit "$PHOME/.claude/settings.json")"
judge "and the session HOME is protected too"       deny "$(v Edit "$HOME/.claude/settings.json")"

# ===========================================================================
section "every Bash write form is denied"
# ===========================================================================
judge "cp onto ~/.claude/settings.json"   deny "$(vb "cp /tmp/a ~/.claude/settings.json")"
judge "cp onto the passwd-home path"      deny "$(vb "cp /tmp/a $PHOME/.claude/settings.json")"
judge "sed -i on ~/.gitconfig"            deny "$(vb "sed -i.bak 's/a/b/' $PHOME/.gitconfig")"
judge "> into the codex config"           deny "$(vb "echo '{}' > $PHOME/.codex/config.toml")"
judge ">> into ~/.gitconfig"              deny "$(vb "echo x >> $PHOME/.gitconfig")"
judge "tee -a into project settings"      deny "$(vb "echo x | tee -a .claude/settings.local.json")"
judge "tee into the project opencode.json" deny "$(vb "echo x | tee opencode.json")"
judge "python3 -c open(...) on codex config" deny \
  "$(vb "python3 -c \"open('$PHOME/.codex/config.toml','w').write('x')\"")"
judge "python3 heredoc naming ~/.cursor/hooks.json" deny \
  "$(vb "$(printf 'python3 - <<%s\nimport os\nopen(os.path.expanduser("~/.cursor/hooks.json"),"w")\nEOF\n' "'EOF'")")"
# shellcheck disable=SC2016  # the $OUT is the payload's, not this shell's
judge "a variable-built target naming a protected path" deny \
  "$(vb 'OUT=~/.claude/settings.json; echo x > $OUT')"
judge "code piped into a shell naming a host settings file" deny \
  "$(vb "echo 'echo x > ~/.codex/config.toml' | bash")"
judge "mv a protected file away"          deny "$(vb "mv $PHOME/.config/gh/hosts.yml /tmp/hosts.yml")"
judge "rm -rf the gh config dir"          deny "$(vb "rm -rf $PHOME/.config/gh")"
judge "rm -rf a dir that contains host settings" deny "$(vb "rm -rf ~/.claude")"
judge "rm of the project hook"            deny "$(vb "rm -f .git/hooks/pre-commit")"

section "... and the same paths READ or MENTIONED stay allowed"
judge "cat ~/.claude/settings.json"           allow "$(vb "cat ~/.claude/settings.json")"
judge "grep in ~/.gitconfig"                  allow "$(vb "grep -n user $PHOME/.gitconfig")"
judge "jq . on the host settings"             allow "$(vb "jq . $PHOME/.claude/settings.json")"
judge "cp FROM a protected file (a read)"     allow "$(vb "cp ~/.claude/settings.json /tmp/settings-backup.json")"
judge "commit message naming one"             allow "$(vb "git commit -m 'protect ~/.claude/settings.json'")"
judge "an unresolved write naming none: still advisory" warn "$(vb "python3 -c 'print(1)'")"
judge "an ordinary redirect"                  allow "$(vb "echo x > /tmp/notes.txt")"

# ===========================================================================
section "symlinks: the realpath decides (S-03)"
# ===========================================================================
ln -s "$PHOME/.claude/settings.json" "$TMP/innocent.json"
ln -s "$PHOME/.gemini" "$TMP/gdir"
ln -s "$TMP/plain-target.txt" "$TMP/plain-link.txt"
judge "> through a file symlink"            deny "$(vb "echo x > $TMP/innocent.json")"
judge "Edit through a file symlink"         deny "$(v Edit "$TMP/innocent.json")"
judge "Write through a symlinked parent dir" deny "$(v Write "$TMP/gdir/settings.json")"
judge "cp through a symlinked parent dir"   deny "$(vb "cp /tmp/a $TMP/gdir/policies/p.toml")"
judge "a symlink to an ordinary file is fine" allow "$(vb "echo x > $TMP/plain-link.txt")"
judge "ln -s making a protected file reachable" deny "$(vb "ln -s ~/.claude/settings.json $TMP/l2")"
judge "ln -s making a protected dir reachable"  deny "$(vb "ln -s $PHOME/.codex $TMP/l3")"
judge "ln -sf replacing ~/.gitconfig"           deny "$(vb "ln -sf $TMP/mine $PHOME/.gitconfig")"
judge "relative ln -s, resolved from the link's dir" deny \
  "$(vb "ln -s ../.claude/settings.json sub/link.json")"
judge "ln -s between ordinary files"            allow "$(vb "ln -s $TMP/a $TMP/b")"
reason_text="$(reason "$(run_guard "$GUARD" Bash "echo x > $TMP/innocent.json")")"
judge "the reason names the resolved path" yes "$(has "$reason_text" "resolves to '$PHOME/.claude/settings.json'")"

# ===========================================================================
section "PM_ALLOW_PROTECTED unlocks nothing protected"
# ===========================================================================
export PM_ALLOW_PROTECTED=1
judge "Edit ~/.claude/settings.json"        deny "$(v Edit "$PHOME/.claude/settings.json")"
judge "cp onto ~/.gitconfig"                deny "$(vb "cp /tmp/a $PHOME/.gitconfig")"
judge "> through a symlink"                 deny "$(vb "echo x > $TMP/innocent.json")"
judge "python3 -c naming opencode config"   deny "$(vb "python3 -c \"open('$PHOME/.config/opencode/opencode.json','w')\"")"
judge "an installed guard file"             deny "$(vg "$INST/hooks/guard-sensitive-files.sh" Write "$INST/hooks/lib/write-targets.py")"
judge "a source-checkout guard file is not protected" allow \
  "$(vg "$SRC/hooks/guard-sensitive-files.sh" Write "$SRC/hooks/protect-other-branches.sh")"
section "... and is still honoured for the generated-file rules"
judge "Edit a lockfile"                     allow "$(v Edit "$REPO/yarn.lock")"
judge "Bash write to a lockfile"            allow "$(vb "echo x > yarn.lock")"
judge "Write a workflow passes (5.6.7: no longer protected)" allow "$(v Write "$REPO/.github/workflows/ci.yml")"
unset PM_ALLOW_PROTECTED

# ===========================================================================
section "the running plugin's guard files"
# ===========================================================================
for rel in hooks/guard-sensitive-files.sh hooks/protect-other-branches.sh hooks/lib/write-targets.py \
           hooks/lib/hook-output.sh hooks/hooks.json
do
  judge "installed copy: Write $rel" deny "$(vg "$INST/hooks/guard-sensitive-files.sh" Write "$INST/$rel")"
done
judge "installed copy: sed -i a guard" deny \
  "$(vg "$INST/hooks/guard-sensitive-files.sh" Bash "sed -i.bak 's/deny/allow/' $INST/hooks/guard-sensitive-files.sh")"
judge "installed copy: an interpreter naming a guard" deny \
  "$(vg "$INST/hooks/guard-sensitive-files.sh" Bash "python3 -c \"open('$INST/hooks/lib/hook-output.sh','w')\"")"
judge "installed copy: a planted .git (it would read as a source checkout)" deny \
  "$(vg "$INST/hooks/guard-sensitive-files.sh" Bash "touch $INST/.git")"
judge "installed copy: its README is not a guard" allow \
  "$(vg "$INST/hooks/guard-sensitive-files.sh" Write "$INST/README.md")"
judge "installed copy: a skill is not a guard"    allow \
  "$(vg "$INST/hooks/guard-sensitive-files.sh" Write "$INST/skills/x/SKILL.md")"
judge "source checkout: its own guard file is the contributor's to edit" allow \
  "$(vg "$SRC/hooks/guard-sensitive-files.sh" Edit "$SRC/hooks/guard-sensitive-files.sh")"
judge "source checkout: a host settings write in the same command is still denied" deny \
  "$(vg "$SRC/hooks/guard-sensitive-files.sh" Bash "echo x > $SRC/hooks/x.sh; echo y > $PHOME/.gitconfig")"
judge "another plugin copy's guards are not this guard's" allow \
  "$(vg "$INST/hooks/guard-sensitive-files.sh" Write "$SRC/hooks/guard-sensitive-files.sh")"
judge "CLAUDE_PLUGIN_ROOT adds a protected root, never removes one" deny \
  "$(payload Write "$INST/hooks/hooks.json" | CLAUDE_PLUGIN_ROOT="$INST" bash "$SRC/hooks/guard-sensitive-files.sh" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision')"

# ===========================================================================
section "deny texts name no bypass"
# ===========================================================================
texts=""
for c in "Edit|$PHOME/.claude/settings.json" "Edit|$REPO/yarn.lock" "Write|$REPO/package-lock.json" \
         "Bash|echo x > $TMP/innocent.json" "Bash|python3 -c \"open('$PHOME/.gitconfig','w')\""; do
  texts="$texts$(reason "$(run_guard "$GUARD" "${c%%|*}" "${c#*|}")")"$'\n'
done
judge "five deny reasons were produced" 5 "$(printf '%s' "$texts" | grep -c 'BLOCKED')"
judge "none names PM_ALLOW_PROTECTED"       no "$(has "$texts" PM_ALLOW_PROTECTED)"
judge "none names create_or_update_file"    no "$(has "$texts" create_or_update_file)"
judge "none points at the GitHub MCP"       no "$(has "$texts" "GitHub MCP")"
judge "no reason is the removed workflow rule" no "$(has "$texts" "workflow.edit")"
judge "the protected text sends it to the user" yes "$(has "$texts" "ask them to make this change themselves")"

# ===========================================================================
section "the table holds no permission-levels entry; no answer is an ask"
# ===========================================================================
left="$(python3 - "$ROOT" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("wt", sys.argv[1] + "/hooks/lib/write-targets.py")
wt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wt)
gone = ("/.config/tamirs-superpowers/", "/.local/state/tamirs-superpowers/", "{repo}/.tamirs-superpowers/",
        "/core/" + "permissions/", "resolve-" + "permission", "plugin-" + "config", "permission-" + "common")
print(" ".join(p for _, p in wt.protected_table() if any(g in p for g in gone)))
PY
)"
judge "no removed entry is left in the protected table" "" "$left"
asked=""
for c in "Edit|$PHOME/.claude/settings.json" "Edit|$SRC/hooks/hooks.json" "Bash|echo x > $TMP/innocent.json" \
         "Bash|git -C $REPO checkout -q HEAD -- .claude/settings.json" "Bash|git -C $REPO merge --ff-only HEAD"; do
  for g in "$GUARD" "$SRC/hooks/guard-sensitive-files.sh" "$INST/hooks/guard-sensitive-files.sh"; do
    d="$(vg "$g" "${c%%|*}" "${c#*|}")"
    [ "$d" = ask ] && asked="$asked $c;"
  done
done
judge "no case answers ask" "" "$asked"
judge "a git replay onto a protected path is not judged" allow \
  "$(vb "git -C $REPO checkout -q HEAD -- .claude/settings.json")"

# ===========================================================================
section "platform dialects carry the deny"
# ===========================================================================
codex_out="$(payload Edit "$PHOME/.codex/config.toml" | CODEX_HOME="$TMP/codex" bash "$GUARD" 2>/dev/null)"
judge "codex: deny with a non-empty reason" yes \
  "$(printf '%s' "$codex_out" | jq -e '.hookSpecificOutput.permissionDecision=="deny" and (.hookSpecificOutput.permissionDecisionReason|length>0)' >/dev/null 2>&1 && echo yes || echo no)"
cursor_out="$(jq -n --arg p "$PHOME/.cursor/hooks.json" --arg cwd "$REPO" \
  '{tool_name:"Write", cwd:$cwd, cursor_version:"3", tool_input:{file_path:$p}}' | bash "$GUARD" 2>/dev/null)"
judge "cursor: permission deny" deny "$(printf '%s' "$cursor_out" | jq -r '.permission' 2>/dev/null)"


section "the unresolved-write notice is off by default (5.6.3)"
G="$ROOT/hooks/guard-sensitive-files.sh"
quiet_payload="$(jq -nc --arg c "python3 -c \"open('x','w')\"" --arg d "$ROOT" '{cwd:$d, hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}')"
quiet_out="$(printf '%s' "$quiet_payload" | env -u CLAUDE_PLUGIN_OPTION_UNRESOLVED_WRITE_NOTICES bash "$G" 2>/dev/null)"
judge "option unset: an unresolved write gets no notice" no "$(case "$quiet_out" in *"NOT checked"*|*"unresolved write"*) echo yes;; *) echo no;; esac)"
deny_payload="$(jq -nc --arg c "echo x > package-lock.json" --arg d "$ROOT" '{cwd:$d, hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}')"
deny_out="$(printf '%s' "$deny_payload" | env -u CLAUDE_PLUGIN_OPTION_UNRESOLVED_WRITE_NOTICES bash "$G" 2>/dev/null)"
judge "option unset: a resolvable protected write is still denied" deny "$(printf '%s' "$deny_out" | jq -r '.hookSpecificOutput.permissionDecision // "pass"' 2>/dev/null)"
on_out="$(printf '%s' "$quiet_payload" | CLAUDE_PLUGIN_OPTION_UNRESOLVED_WRITE_NOTICES=true bash "$G" 2>/dev/null)"
judge "option on: the notice is back" yes "$(case "$on_out" in *"NOT checked"*) echo yes;; *) echo no;; esac)"

# Claude Code's bypass mode (5.6.7): the generated-file rules step aside; host settings do not.
bp() { jq -nc --arg f "$1" --arg d "$ROOT" --arg m "$2" \
  '{cwd:$d, session_id:"s", hook_event_name:"PreToolUse", tool_name:"Edit", permission_mode:$m, tool_input:{file_path:$f, old_string:"a", new_string:"b"}}' \
  | bash "$G" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "pass"' 2>/dev/null; }
judge "default mode: editing a workflow passes" pass "$(bp "$ROOT/.github/workflows/ci.yml" default)"
judge "default mode: editing a lockfile is denied" deny "$(bp "$ROOT/package-lock.json" default)"
judge "bypass: editing a lockfile passes" pass "$(bp "$ROOT/package-lock.json" bypassPermissions)"
judge "bypass: the host settings file is still denied" deny "$(bp "$HOME/.claude/settings.json" bypassPermissions)"
judge "bypass on a Codex payload changes nothing" deny "$(jq -nc --arg f "$ROOT/package-lock.json" --arg d "$ROOT" \
  '{cwd:$d, turn_id:"t", hook_event_name:"PreToolUse", tool_name:"Edit", permission_mode:"bypassPermissions", tool_input:{file_path:$f}}' \
  | bash "$G" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "pass"' 2>/dev/null)"

harness_summary
