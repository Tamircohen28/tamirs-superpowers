#!/usr/bin/env bash
# test-sensitive-protected-paths.sh — ADR 004 D10.1 / security review S-03:
# guard-sensitive-files.sh denies writes to the plugin's own policy, its guard
# files and every host settings store, by realpath, with no override.
#
# WHAT EACH GROUP PROVES
#   - every D10.1 location is denied through Edit/Write AND through Bash
#     (cp, sed -i, python3 -c / heredoc, >, tee, mv, rm, ln -s);
#   - the home those locations hang off is the passwd entry, not $HOME — and a
#     different $HOME only adds a second protected home, never moves the first;
#   - a symlink, or a symlinked parent directory, does not carry a write past
#     the check (realpath), and `ln` cannot make a protected file reachable;
#   - an unresolved write (an interpreter, a variable) that NAMES a protected
#     path is a deny, while one that names none stays the advisory it was;
#   - PM_ALLOW_PROTECTED unlocks nothing protected, but still unlocks the
#     generated-file rules (lockfiles) it always did — never a workflow, since
#     env switches only tighten (D3) and a cloned repo's settings can set it;
#   - the running plugin's guard files: deny in an installed copy, an R4 ask in
#     a source checkout (hook_ask when the platform has one, else deny);
#   - no deny text names PM_ALLOW_PROTECTED or the GitHub MCP write tool (D10.5);
#   - the fallback table in write-targets.py equals actions.json, and is what
#     a copy without the catalog uses.
#   Every protected case is paired with a read, a mention or an unprotected
#   neighbour that must stay allowed, so a guard that denies everything fails.
#
# Hermetic: the guard only JUDGES payloads, so the real passwd home is named in
# them but never written; every file and symlink created lives under mktemp.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"

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

# A plugin copy with no .git (an installed cache), one that is a source
# checkout, the same with a hook_ask, and one without its catalog.
plugin_copy() {
  mkdir -p "$1/core" "$1/scripts/lib"
  cp -R "$ROOT/hooks" "$1/hooks"
  cp -R "$ROOT/core/permissions" "$1/core/permissions"
}
INST="$TMP/installed/tamirs-superpowers"; plugin_copy "$INST"
SRC="$TMP/src-plain";                     plugin_copy "$SRC"; git -C "$SRC" init -q
# The real hook-output.sh defines hook_ask (ADR 004 D8). This fixture models a
# library without it, so the guard's fail-closed branch is still exercised.
printf '\nunset -f hook_ask 2>/dev/null || true\n' >> "$SRC/hooks/lib/hook-output.sh"
SRC_ASK="$TMP/src-ask";                   plugin_copy "$SRC_ASK"; git -C "$SRC_ASK" init -q
cat >> "$SRC_ASK/hooks/lib/hook-output.sh" <<'STUB'

# test stub: the Claude PreToolUse ask shape.
hook_ask() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}
STUB
NOCAT="$TMP/nocat"; plugin_copy "$NOCAT"; rm -f "$NOCAT/core/permissions/actions.json"

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
section "every D10.1 location is denied through Edit/Write"
# ===========================================================================
for rel in \
  .config/tamirs-superpowers/permissions.json \
  .config/tamirs-superpowers/permissions.lock \
  .local/state/tamirs-superpowers/tickets/t1 \
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
  .tamirs-superpowers/permissions.json \
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
judge "> into the permission file"        deny "$(vb "echo '{}' > $PHOME/.config/tamirs-superpowers/permissions.json")"
judge ">> into the lock"                  deny "$(vb "echo x >> $PHOME/.config/tamirs-superpowers/permissions.lock")"
judge "tee -a into project settings"      deny "$(vb "echo x | tee -a .claude/settings.local.json")"
judge "tee into the project policy"       deny "$(vb "echo x | tee .tamirs-superpowers/permissions.json")"
judge "python3 -c open(...) on codex config" deny \
  "$(vb "python3 -c \"open('$PHOME/.codex/config.toml','w').write('x')\"")"
judge "python3 heredoc naming ~/.cursor/hooks.json" deny \
  "$(vb "$(printf 'python3 - <<%s\nimport os\nopen(os.path.expanduser("~/.cursor/hooks.json"),"w")\nEOF\n' "'EOF'")")"
# shellcheck disable=SC2016  # the $OUT is the payload's, not this shell's
judge "a variable-built target naming a protected path" deny \
  "$(vb 'OUT=~/.claude/settings.json; echo x > $OUT')"
judge "code piped into a shell naming the state dir" deny \
  "$(vb "echo 'echo x > ~/.local/state/tamirs-superpowers/seen/t' | bash")"
judge "mv a protected file away"          deny "$(vb "mv $PHOME/.config/gh/hosts.yml /tmp/hosts.yml")"
judge "rm -rf the policy dir"             deny "$(vb "rm -rf $PHOME/.config/tamirs-superpowers")"
judge "rm -rf a dir that contains host settings" deny "$(vb "rm -rf ~/.claude")"
judge "rm of the project hook"            deny "$(vb "rm -f .git/hooks/pre-commit")"

section "... and the same paths READ or MENTIONED stay allowed"
judge "cat ~/.claude/settings.json"           allow "$(vb "cat ~/.claude/settings.json")"
judge "grep in ~/.gitconfig"                  allow "$(vb "grep -n user $PHOME/.gitconfig")"
judge "jq . on the permission file"           allow "$(vb "jq . $PHOME/.config/tamirs-superpowers/permissions.json")"
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
judge "cp onto the permission file"         deny "$(vb "cp /tmp/a $PHOME/.config/tamirs-superpowers/permissions.json")"
judge "> through a symlink"                 deny "$(vb "echo x > $TMP/innocent.json")"
judge "python3 -c naming opencode config"   deny "$(vb "python3 -c \"open('$PHOME/.config/opencode/opencode.json','w')\"")"
judge "an installed guard file"             deny "$(vg "$INST/hooks/guard-sensitive-files.sh" Write "$INST/hooks/lib/write-targets.py")"
judge "a source-checkout guard file is still an ask" ask \
  "$(vg "$SRC_ASK/hooks/guard-sensitive-files.sh" Write "$SRC_ASK/hooks/permission-guard.sh")"
section "... and is still honoured for the generated-file rules, workflows excepted"
judge "Edit a lockfile"                     allow "$(v Edit "$REPO/yarn.lock")"
judge "Bash write to a lockfile"            allow "$(vb "echo x > yarn.lock")"
judge "Write a workflow is still denied (F6)" deny "$(v Write "$REPO/.github/workflows/ci.yml")"
unset PM_ALLOW_PROTECTED

# ===========================================================================
section "the running plugin's guard files"
# ===========================================================================
for rel in hooks/guard-sensitive-files.sh hooks/permission-guard.sh hooks/lib/write-targets.py \
           hooks/lib/hook-output.sh hooks/hooks.json core/permissions/actions.json \
           scripts/resolve-permission.sh scripts/lib/permission-common.sh scripts/plugin-config.sh
do
  judge "installed copy: Write $rel" deny "$(vg "$INST/hooks/guard-sensitive-files.sh" Write "$INST/$rel")"
done
judge "installed copy: sed -i a guard" deny \
  "$(vg "$INST/hooks/guard-sensitive-files.sh" Bash "sed -i.bak 's/deny/allow/' $INST/hooks/guard-sensitive-files.sh")"
judge "installed copy: an interpreter naming a guard" deny \
  "$(vg "$INST/hooks/guard-sensitive-files.sh" Bash "python3 -c \"open('$INST/hooks/lib/hook-output.sh','w')\"")"
judge "installed copy: its README is not a guard" allow \
  "$(vg "$INST/hooks/guard-sensitive-files.sh" Write "$INST/README.md")"
judge "installed copy: a skill is not a guard"    allow \
  "$(vg "$INST/hooks/guard-sensitive-files.sh" Write "$INST/skills/x/SKILL.md")"
judge "source checkout with hook_ask: an ask" ask \
  "$(vg "$SRC_ASK/hooks/guard-sensitive-files.sh" Edit "$SRC_ASK/hooks/guard-sensitive-files.sh")"
judge "source checkout with hook_ask: a deny still outranks the ask" deny \
  "$(vg "$SRC_ASK/hooks/guard-sensitive-files.sh" Bash "echo x > $SRC_ASK/hooks/x.sh; echo y > $PHOME/.gitconfig")"
plain_out="$(run_guard "$SRC/hooks/guard-sensitive-files.sh" Edit "$SRC/hooks/hooks.json")"
judge "source checkout without hook_ask: fails closed to deny" deny "$(decision "$plain_out")"
judge "  ... and says it is a source-checkout guard file" yes "$(has "$(reason "$plain_out")" "source checkout")"
judge "another plugin copy's guards are not this guard's" allow \
  "$(vg "$INST/hooks/guard-sensitive-files.sh" Write "$SRC/hooks/guard-sensitive-files.sh")"
judge "CLAUDE_PLUGIN_ROOT adds a protected root, never removes one" deny \
  "$(payload Write "$INST/hooks/hooks.json" | CLAUDE_PLUGIN_ROOT="$INST" bash "$SRC_ASK/hooks/guard-sensitive-files.sh" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision')"

# ===========================================================================
section "deny texts name no bypass (D10.5)"
# ===========================================================================
texts=""
for c in "Edit|$PHOME/.claude/settings.json" "Edit|$REPO/yarn.lock" "Write|$REPO/.github/workflows/ci.yml" \
         "Bash|echo x > $TMP/innocent.json" "Bash|python3 -c \"open('$PHOME/.gitconfig','w')\""; do
  texts="$texts$(reason "$(run_guard "$GUARD" "${c%%|*}" "${c#*|}")")"$'\n'
done
judge "five deny reasons were produced" 5 "$(printf '%s' "$texts" | grep -c 'BLOCKED')"
judge "none names PM_ALLOW_PROTECTED"       no "$(has "$texts" PM_ALLOW_PROTECTED)"
judge "none names create_or_update_file"    no "$(has "$texts" create_or_update_file)"
judge "none points at the GitHub MCP"       no "$(has "$texts" "GitHub MCP")"
judge "the workflow text is the R4 ask"     yes "$(has "$texts" "R4 action (workflow.edit)")"
judge "the protected text sends it to the user" yes "$(has "$texts" "ask them to make this change themselves")"

# ===========================================================================
section "the table: actions.json, with a fallback that equals it"
# ===========================================================================
parity="$(python3 - "$ROOT" <<'PY'
import importlib.util, json, sys
root = sys.argv[1]
spec = importlib.util.spec_from_file_location("wt", root + "/hooks/lib/write-targets.py")
wt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wt)
cat = json.load(open(root + "/core/permissions/actions.json"))["actions"]
by_id = dict((a["id"], a) for a in cat)
same = all(wt.FALLBACK_PROTECTED[i] == by_id[i]["equivalents"]["paths"] for i in wt.PROTECTED_IDS)
read = wt.protected_table(root) == [(i, p) for i in wt.PROTECTED_IDS for p in by_id[i]["equivalents"]["paths"]]
print("yes" if same and read else "no")
PY
)"
judge "FALLBACK_PROTECTED equals actions.json, and the catalog is what is read" yes "$parity"
judge "without the catalog the fallback still denies host settings" deny \
  "$(vg "$NOCAT/hooks/guard-sensitive-files.sh" Edit "$PHOME/.claude/settings.json")"
judge "  ... and the copy's own guard files" deny \
  "$(vg "$NOCAT/hooks/guard-sensitive-files.sh" Edit "$NOCAT/hooks/hooks.json")"

# ===========================================================================
section "platform dialects carry the deny"
# ===========================================================================
codex_out="$(payload Edit "$PHOME/.codex/config.toml" | CODEX_HOME="$TMP/codex" bash "$GUARD" 2>/dev/null)"
judge "codex: deny with a non-empty reason" yes \
  "$(printf '%s' "$codex_out" | jq -e '.hookSpecificOutput.permissionDecision=="deny" and (.hookSpecificOutput.permissionDecisionReason|length>0)' >/dev/null 2>&1 && echo yes || echo no)"
cursor_out="$(jq -n --arg p "$PHOME/.cursor/hooks.json" --arg cwd "$REPO" \
  '{tool_name:"Write", cwd:$cwd, cursor_version:"3", tool_input:{file_path:$p}}' | bash "$GUARD" 2>/dev/null)"
judge "cursor: permission deny" deny "$(printf '%s' "$cursor_out" | jq -r '.permission' 2>/dev/null)"

harness_summary
