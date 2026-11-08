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
#   - (#402) a protected path that is only read (stat, ls, find -exec ls, jq,
#     git diff) or only data (a heredoc body or echo text written to a file)
#     is not a write, beside an unresolved write or not — and every real write
#     form onto one (redirects, tee, sed -i, cp/mv/install/rm/ln, find
#     -delete/-exec, xargs, interpreters, git replays, dd, truncate, cd) stays
#     blocked, as do the read-back routes that would turn data into a target;
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
section "... and is still honoured for the generated-file rules"
judge "Edit a lockfile"                     allow "$(v Edit "$REPO/yarn.lock")"
judge "Bash write to a lockfile"            allow "$(vb "echo x > yarn.lock")"
judge "Write a workflow passes (5.6.7: no longer protected)" allow "$(v Write "$REPO/.github/workflows/ci.yml")"
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

# ===========================================================================
# Issue #402: a protected path that is only MENTIONED is not a write; every
# real write still is. Two tables, one per direction. `blocked` accepts deny
# or the R4 ask (a git replay); `passes` accepts allow or the advisory warn.
# Both print the verdict they got when they fail.
# ===========================================================================
blocked() { local d; d="$(vb "$2")"; case "$d" in deny|ask) d=blocked ;; esac; judge "$1" blocked "$d"; }
passes()  { local d; d="$(vb "$2")"; case "$d" in allow|warn) d=passes ;; esac; judge "$1" passes "$d"; }
NL=$'\n'
TAB=$'\t'

section "#402 (a): mentions, reads and data are not writes"
# The six reports in the issue, then close variants of each.
passes "find on the state dir with a read-only -exec ls" \
  "find ~/.local/state/tamirs-superpowers -newermt '-5 minutes' -exec ls -laT {} \\;"
passes "find -exec stat ... + on the state dir" \
  "find $PHOME/.local/state/tamirs-superpowers -type f -exec stat -f %m {} +"
passes "find -exec grep -l in the plugin cache" \
  "find ~/.claude/plugins/cache -name '*.json' -exec grep -l version {} \\;"
passes "stat of hostver beside an unrelated interpreter" \
  "stat -f %m ~/.local/state/tamirs-superpowers/hostver; python3 -c 'print(1)'"
passes "ls | head of the state dir beside an unresolved write" \
  "ls -la ~/.local/state/tamirs-superpowers | head -5; echo x > \"\$OUT\""
passes "PR body heredoc naming the state dir, to a variable path" \
  "cat > \"\$SCRATCH/pr-body.md\" <<'EOF'${NL}The guard state lives in ~/.local/state/tamirs-superpowers.${NL}EOF"
passes "unquoted heredoc naming hostver, to a variable path" \
  "cat > \$D/issue.md <<EOF${NL}State dir: \$HOME/.local/state/tamirs-superpowers/hostver${NL}EOF"
passes "issue body whose prose repeats the variable's name" \
  "D=$TMP/scratch${NL}cat > \$D/issue.md <<'EOF'${NL}## D${NL}Never hand-edit ~/.config/tamirs-superpowers/permissions.json.${NL}EOF"
passes "tee of heredoc data naming opencode.json to a variable path" \
  "tee \"\$OUT/notes.md\" >/dev/null <<'EOF'${NL}OpenCode reads opencode.json from the repo root.${NL}EOF"
passes "jq on opencode.json beside an unrelated interpreter" \
  "jq '.permission' opencode.json; python3 -c 'print(1)'"
passes "jq on opencode.json into a scratch file" "jq -r .version opencode.json > /tmp/v.txt"
passes "git diff of opencode.json beside an unresolved write" \
  "git diff -- opencode.json; echo x > \"\$OUT\""
passes "sed -n of a cached plugin script beside an interpreter" \
  "sed -n 1,40p ~/.claude/plugins/cache/m/p/5.6.3/scripts/x.sh; python3 -c 'print(1)'"
passes "echo naming the policy file into a variable path" \
  "echo \"edit ~/.config/tamirs-superpowers/permissions.json by hand\" >> \"\$NOTES\""
passes "printf naming opencode.json into a file, then an unresolved copy of another" \
  "printf '%s\\n' 'see opencode.json' > notes.txt; cp a.txt \"\$DEST\""
# stdin from /dev/null carries no program, so a named script stays a named script.
passes "a cached plugin script run with stdin from /dev/null" \
  "bash ~/.claude/plugins/cache/m/p/5.6.3/scripts/labels.sh apply </dev/null 2>&1 | tail -6"
passes "the same through a literal variable" \
  "P=~/.claude/plugins/cache/m/p/5.6.3; bash \$P/scripts/x.sh </dev/null"
# (Payload text, never run; `-k 5` keeps the static timeout lint from reading it as a call.)
# `timeout` stays the dispatcher it is on master (review of #402, D3): what it runs is opaque.
blocked "timeout around a cached plugin script stays opaque" \
  "timeout -k 5 90 bash ~/.claude/plugins/cache/m/p/5.6.3/scripts/probe.sh . 2>&1 | tail -10"
blocked "timeout over a nested env + strace"     "timeout -k 1 5 env strace cp x ~/.gitconfig"
blocked "timeout over sort -o"                   "timeout -k 1 5 sort -o ~/.gitconfig f"
blocked "timeout over git config --file"         "timeout -k 1 5 git config --file ~/.gitconfig a b"
blocked "timeout around a real write"            "timeout -k 5 90 cp /tmp/a ~/.gitconfig"
blocked "timeout with a duration it cannot read, naming a path" \
  "timeout -k 5 \$T cp /tmp/a ~/.gitconfig"
passes "python3 script.py with stdin from /dev/null" \
  "python3 ~/.claude/plugins/cache/m/p/5.6.3/hooks/lib/write-targets.py --protected </dev/null"
passes "an unresolved write run in an ordinary directory" "python3 -c \"open('hosts.yml','w')\""
passes "cat of host settings, then an interpreter on other data" \
  "cat ~/.claude/settings.json; python3 -c 'print(2)'"
passes "xargs grep over files in the plugin cache, beside an unresolved write" \
  "ls ~/.claude/plugins/cache/m/p/rules/*.mdc | xargs grep -c 'alwaysApply: true'; echo x > \"\$OUT\""
passes "xargs -0 wc -l from a find" \
  "find ~/.local/state/tamirs-superpowers -type f -print0 | xargs -0 wc -l"
passes "a literal variable whose quoted heredoc prose has '). '" \
  "W=$TMP/w; cat > \"\$W/review.md\" <<'EOF'${NL}(see ~/.claude/settings.json). Then stop.${NL}EOF"

section "#402 (b): every real write form onto a protected path stays blocked"
blocked "> onto ~/.claude/settings.json"         "echo x > ~/.claude/settings.json"
blocked ">> onto the passwd-home .gitconfig"     "echo x >> $PHOME/.gitconfig"
blocked "> after cd into a protected dir"        "cd ~/.config/gh && echo x > hosts.yml"
blocked "bare > after cd into a protected dir"   "cd ~/.config/gh; > hosts.yml"
blocked "cp after cd into ~/.claude"             "cd $PHOME/.claude && cp /tmp/a settings.json"
blocked "tee onto gh hosts"                      "echo x | tee ~/.config/gh/hosts.yml"
blocked "tee -a onto project settings"           "echo x | tee -a .claude/settings.local.json"
blocked "tee of a heredoc onto .gitconfig"       "tee ~/.gitconfig <<'EOF'${NL}x${NL}EOF"
blocked "heredoc into opencode.json"             "cat > opencode.json <<'EOF'${NL}{}${NL}EOF"
blocked "sed -i on opencode.json"                "sed -i 's/a/b/' opencode.json"
blocked "BSD sed -i '' on codex config"          "sed -i '' 's/a/b/' ~/.codex/config.toml"
blocked "perl -pi on opencode.json"              "perl -pi -e 's/a/b/' opencode.json"
blocked "cp onto opencode.json"                  "cp /tmp/a opencode.json"
blocked "mv onto cursor hooks"                   "mv /tmp/a ~/.cursor/hooks.json"
blocked "install onto .gitconfig"                "install -m 644 /tmp/a ~/.gitconfig"
blocked "rm of the permission file"              "rm -f ~/.config/tamirs-superpowers/permissions.json"
blocked "ln -sf over .gitconfig"                 "ln -sf /tmp/a ~/.gitconfig"
blocked "dd of= onto .gitconfig"                 "dd if=/dev/zero of=$PHOME/.gitconfig count=1"
blocked "truncate gh hosts"                      "truncate -s 0 ~/.config/gh/hosts.yml"
blocked "touch project settings"                 "touch .claude/settings.json"
blocked "find -delete in the policy dir"         "find ~/.config/tamirs-superpowers -name '*.json' -delete"
blocked "find -exec rm in gh config"             "find ~/.config/gh -exec rm {} \\;"
blocked "find -exec mv opencode.json away"       "find . -name opencode.json -exec mv {} /tmp \\;"
blocked "find -exec sed -i on host settings"     "find ~/.claude -name 'settings*.json' -exec sed -i s/a/b/ {} +"
blocked "find -exec tee into gh config"          "find ~/.config/gh -type f -exec tee {} \\; </dev/null"
blocked "find -exec sh -c writing"               "find ~/.config/gh -exec sh -c 'echo x > \"\$1\"' _ {} \\;"
blocked "find read-only -exec, then -exec rm"    "find ~/.config/gh -exec ls {} \\; -exec rm {} \\;"
blocked "find read-only -exec, then -delete"     "find ~/.config/gh -exec ls {} \\; -delete"
blocked "find -fprint onto .gitconfig"           "find /tmp -fprint ~/.gitconfig"
blocked "find -fls onto .gitconfig"              "find /tmp -fls ~/.gitconfig"
blocked "find -fprint0 onto .gitconfig"          "find /tmp -fprint0 ~/.gitconfig"
blocked "find -ok rm in gh config"               "yes | find ~/.config/gh -ok rm {} \\;"
blocked "find read-only -exec piped into a shell" "find ~/.config/gh -exec cat {} \\; | sh"
blocked "xargs rm of .gitconfig"                 "echo ~/.gitconfig | xargs rm"
blocked "xargs cp into gh config"                "ls ~/.config/gh/* | xargs -I{} cp /tmp/a {}"
blocked "xargs sed -i on opencode.json"          "printf '%s\\n' opencode.json | xargs sed -i s/a/b/"
blocked "xargs sh -c writing"                    "echo ~/.gitconfig | xargs -I{} sh -c 'echo x > {}'"
blocked "xargs with an option it does not know"  "echo ~/.gitconfig | xargs --frobnicate cat"
blocked "xargs tee"                              "echo ~/.gitconfig | xargs tee </dev/null"
blocked "python3 -c open(w) on opencode.json"    "python3 -c \"open('opencode.json','w').write('x')\""
blocked "python3 heredoc writing host settings" \
  "python3 - <<'EOF'${NL}import os${NL}p=os.path.expanduser('~/.claude/settings.json')${NL}open(p,'w')${NL}EOF"
blocked "python3 heredoc that only mentions opencode.json (inline code stays opaque)" \
  "python3 - <<'EOF'${NL}p='docs/x.json'${NL}s=open(p).read().replace('a','opencode.json')${NL}open(p,'w').write(s)${NL}EOF"
blocked "node -e writeFileSync on opencode.json" "node -e \"require('fs').writeFileSync('opencode.json','x')\""
blocked "perl -e open > on opencode.json"        "perl -e 'open(F, \">\", \"opencode.json\")'"
blocked "python3 via a prefix env var"           "F=~/.config/gh/hosts.yml python3 -c \"import os; open(os.environ['F'],'w')\""
blocked "python3 via an exported var"            "export F=~/.config/gh/hosts.yml; python3 -c \"import os; open(os.environ['F'],'w')\""
blocked "python3 via a shell var in its code"    "F=~/.gitconfig; python3 -c \"open('\$F','w')\""
blocked "python3 via argv"                       "python3 - $PHOME/.gitconfig <<'EOF'${NL}import sys; open(sys.argv[1],'w')${NL}EOF"
blocked "python3 after cd into a protected dir"  "cd ~/.config/gh && python3 -c \"open('hosts.yml','w')\""
blocked "python3 reading a path an echo wrote"   "echo ~/.gitconfig > /tmp/p; python3 -c \"open(open('/tmp/p').read().strip(),'w')\""
blocked "protected file piped into python3"      "cat ~/.config/gh/hosts.yml | python3 -c 'import sys; sys.stdin.read()'"
blocked "a heredoc file then bash < it"          "cat > /tmp/f <<'EOF'${NL}echo x > ~/.gitconfig${NL}EOF${NL}bash < /tmp/f"
# A named script fed anything but /dev/null may run what it is fed (`exec bash`).
printf 'exec bash\n' > "$TMP/runner.sh"
blocked "an existing script fed a heredoc stays opaque" \
  "bash $TMP/runner.sh <<'EOF'${NL}echo x > ~/.gitconfig${NL}EOF"
blocked "an existing script fed a here-string stays opaque" \
  "python3 $TMP/runner.py <<<\"open('$PHOME/.gitconfig','w')\""
blocked "a script relinked to /dev/stdin, then fed code" \
  "ln -sf /dev/stdin $TMP/runner.sh; bash $TMP/runner.sh <<'EOF'${NL}echo x > ~/.gitconfig${NL}EOF"
blocked "a FIFO as the script" \
  "mkfifo $TMP/ff; bash $TMP/ff <<'EOF'${NL}echo x > ~/.gitconfig${NL}EOF"
blocked "bash reading its program through <> on stdin" "bash <> ~/.config/gh/x.sh"
blocked "a named script in the cache fed a here-string" \
  "python3 ~/.claude/plugins/cache/m/p/5.6.3/hooks/lib/write-targets.py --protected <<<'{}'"
# Review of #402 (security-reviewer): each was a regression in the first cut.
blocked "\$_ carries an inert command's argument into cp"  "ls ~/.gitconfig; cp /tmp/a \$_"
blocked "\${_} carries a stat argument into a redirect"     "stat ~/.gitconfig; echo hi > \"\${_}\""
blocked "\${!name} indirection to \$_"                       "X=_; ls ~/.gitconfig; cp /tmp/a \${!X}"
blocked "an exported diff driver runs under an inert git diff" \
  "echo x > \$UNK; export GIT_EXTERNAL_DIFF=tee; echo pwned | git diff --no-index a ~/.gitconfig"
blocked "env-assigned diff driver under an inert git diff" \
  "echo x > \$UNK; env GIT_EXTERNAL_DIFF=tee git diff --no-index a ~/.gitconfig"
blocked "a heredoc Makefile run by make" \
  "cat > Makefile <<'EOF'${NL}all:${NL}${TAB}echo x > ~/.gitconfig${NL}EOF${NL}make; echo x > \"\$UNK\""
blocked "a heredoc conftest.py run by pytest" \
  "cat > conftest.py <<'EOF'${NL}open('$PHOME/.gitconfig','w')${NL}EOF${NL}pytest; cp a \"\$X\""
blocked "a heredoc read back as \${F}" \
  "cat > \"\$F\" <<'EOF'${NL}w $PHOME/.gitconfig${NL}EOF${NL}sed -n -f \"\${F}\" /etc/hosts; cp a \"\$X\""
blocked "xargs -l (optional value) hides rm"        "echo ~/.gitconfig | xargs -l rm ls"
blocked "xargs --replace (optional value) hides rm" "echo ~/.gitconfig | xargs --replace rm ls"
blocked "time -o writes the file it names"          "time -o ~/.gitconfig ls"
blocked "time --output= beside an unresolved write" "echo x > \$UNK; time --output=$PHOME/.gitconfig ls"
blocked "timeout over an expanded command"          "timeout -k 1 5 \$CMD x ~/.gitconfig"
blocked "timeout over setsid"                       "timeout -k 1 5 setsid cp /tmp/a ~/.gitconfig"
blocked "setsid around a write"                     "setsid cp /tmp/a ~/.gitconfig"
blocked "sort --out= abbreviation beside an unresolved write" "sort --out=$PHOME/.gitconfig /etc/hosts; cp a \"\$X\""
blocked "sed --in abbreviation beside an unresolved write"    "sed --in 's/a/b/' ~/.gitconfig; cp a \"\$X\""
blocked "sed --exp= abbreviation with a w command"            "sed -n --exp='w $PHOME/.gitconfig' /etc/hosts; cp a \"\$X\""
blocked "an inert ls into fd 3"                     "echo x > \$UNK; ls ~/.gitconfig >&3"
blocked "history expansion of the last argument"    "echo x > \$UNK; ls ~/.gitconfig; rm !\$"
blocked "timeout then -- before the command"        "timeout -k 1 5 -- cp x ~/.gitconfig"
blocked "\${X@P} prompt expansion in an inert echo" "echo x > \$UNK; echo \${X@P} ~/.gitconfig"
# Re-check of the review (D1–D4).
blocked "eval sets the env an inert git diff runs under" \
  "echo x > \$UNK; eval 'export GIT_EXTERNAL_DIFF=tee'; echo pwned | git diff --no-index a1 ~/.gitconfig"
blocked "source of an env file before an inert git diff" \
  "echo x > \$UNK; source ./env.sh; echo pwned | git diff --no-index a1 ~/.gitconfig"
blocked ". of an env file before an inert ls"   "echo x > \$UNK; . ./env.sh; ls ~/.gitconfig"
blocked "eval : before an inert ls"             "echo x > \$UNK; eval :; ls ~/.gitconfig"
blocked "BSD sed -I '' in place"                "echo x > \$UNK; sed -I '' 's/a/b/' ~/.gitconfig"
blocked "BSD sed -I.bak in place"               "sed -I.bak 's/a/b/' ~/.gitconfig"
blocked "timeout over strace"                   "timeout -k 1 5 strace cp x ~/.gitconfig"
blocked "timeout over gdb -batch"               "timeout -k 1 5 gdb -batch -ex 'shell cp x ~/.gitconfig'"
blocked "timeout over ssh"                      "timeout -k 1 5 ssh h cp x ~/.gitconfig"
blocked "timeout over docker run"               "timeout -k 1 5 docker run img cp x ~/.gitconfig"
blocked "timeout over numactl"                  "timeout -k 1 5 numactl cp x ~/.gitconfig"
blocked "a line continuation inside \${_}" \
  "echo x > \$UNK; ls ~/.gitconfig; cp x \${\\${NL}_}"
# PR #408 review (Codex P1): narrowing-disablers hidden behind a wrapper, and
# redirection-only commands that move where later "inert" output goes.
blocked "command exec > file, then an inert ls read back by python" \
  "command exec > /tmp/p; ls -d ~/.gitconfig; python3 -c \"open(open('/tmp/p').read().strip(),'w')\""
blocked "builtin exec > file, then an inert ls read back" \
  "builtin exec > /tmp/p; ls -d ~/.config/gh; D=\$(cat /tmp/p); echo x > \"\$D/hosts.yml\""
blocked "env exec > file, then an inert ls read back" \
  "env exec > /tmp/p; ls -d ~/.config/gh; D=\$(cat /tmp/p); echo x > \"\$D/hosts.yml\""
blocked "command eval sets env for an inert git diff" \
  "echo x > \$UNK; command eval 'export GIT_EXTERNAL_DIFF=tee'; echo pwned | git diff --no-index a1 ~/.gitconfig"
blocked "builtin source before an inert git diff" \
  "echo x > \$UNK; builtin source ./env.sh; echo pwned | git diff --no-index a1 ~/.gitconfig"
blocked "command export before an inert git diff" \
  "echo x > \$UNK; command export GIT_EXTERNAL_DIFF=tee; echo pwned | git diff --no-index a1 ~/.gitconfig"
blocked "bare exec 3> file, then an inert ls into fd 3" \
  "exec 3>/tmp/p; ls ~/.config/gh >&3; D=\$(cat /tmp/p); echo x > \"\$D/hosts.yml\""
blocked "{fd}> file, then an inert ls read back" \
  "exec {fd}>/tmp/p; ls -d ~/.config/gh; D=\$(cat /tmp/p); echo x > \"\$D/hosts.yml\""
blocked "a redirection-only > file beside an inert ls" \
  ">/tmp/p; ls -d ~/.config/gh; D=\$(cat /tmp/p); echo x > \"\$D/hosts.yml\""
# Round 5 (F1): a variable set without a `NAME=` word, before an inert command.
blocked "read PATH before an inert ls"          "echo x > \$UNK; read PATH <<< /tmp/b; ls ~/.gitconfig"
blocked "for PATH in … before an inert ls"      "echo x > \$UNK; for PATH in /tmp/b; do :; done; ls ~/.gitconfig"
blocked "printf -v PATH before an inert ls"     "echo x > \$UNK; printf -v PATH %s /tmp/b; ls ~/.gitconfig"
blocked "mapfile PATH before an inert ls"       "echo x > \$UNK; mapfile PATH <<< /tmp/b; ls ~/.gitconfig"
blocked "read HOME before an inert git diff"    "echo x > \$UNK; read HOME <<< /tmp/h; echo pwned | git diff --no-index a1 ~/.gitconfig"
blocked "getopts into a variable before an inert ls" "echo x > \$UNK; getopts p PATH -p; ls ~/.gitconfig"
blocked "let before an inert ls"                "echo x > \$UNK; let IFS=1; ls ~/.gitconfig"
blocked "(( )) assignment before an inert ls"   "echo x > \$UNK; (( IFS = 1 )); ls ~/.gitconfig"
blocked "\${PATH:=…} before an inert ls"        "echo x > \$UNK; : \${PATH:=/tmp/b}; ls ~/.gitconfig"
blocked "unset PATH before an inert ls"         "echo x > \$UNK; unset PATH; ls ~/.gitconfig"
# Round 5 (F2): an inert git reads config a data heredoc wrote.
blocked "a heredoc git config with fsmonitor, then git status" \
  "echo x > \$UNK; cat <<'EOF' > /tmp/gd/config${NL}[core]${NL}${TAB}fsmonitor = sh -c 'echo > $PHOME/.gitconfig' #${NL}EOF${NL}git --git-dir=/tmp/gd --work-tree=. status"
blocked "a heredoc to an unresolved config path, then plain git status" \
  "cat <<'EOF' > \"\$G/config\"${NL}[core]${NL}${TAB}fsmonitor = sh -c 'echo > $PHOME/.gitconfig' #${NL}EOF${NL}git status"
blocked "git -C into a protected dir beside an unresolved write" "echo x > \$UNK; git -C ~/.config/gh status"
blocked "a heredoc ripgrep config, then rg" \
  "cat <<'EOF' > \"\$RC\"${NL}--pre=sh -c 'echo > $PHOME/.gitconfig'${NL}EOF${NL}rg x ."
passes "git -C elsewhere, beside an unresolved write naming nothing" "echo x > \$UNK; git -C /tmp/r status"
cwd_verdict="$(v Bash "python3 -c \"open('hosts.yml','w')\"" "$HOME/.config/gh")"
case "$cwd_verdict" in deny|ask) cwd_verdict=blocked ;; esac
judge "an unresolved write run inside a protected dir (a cwd kept from an earlier call)" blocked "$cwd_verdict"
blocked "echo data read back as a sed program" \
  "echo 'w $PHOME/.gitconfig' > /tmp/p.sed; sed -n -f /tmp/p.sed /etc/hosts; cp a \"\$X\""
blocked "heredoc data read back through a glob" \
  "cat > /tmp/p.sed <<'EOF'${NL}w $PHOME/.gitconfig${NL}EOF${NL}sed -n -f /tmp/p.* /etc/hosts; cp a \"\$X\""
blocked "echo data piped to a sed program on stdin" \
  "echo 'w $PHOME/.gitconfig' | sed -n -f - /etc/hosts; cp a \"\$X\""
blocked "exec > file, then an inert ls read back" \
  "exec > /tmp/p; ls -d ~/.config/gh; exec >/dev/tty; D=\$(cat /tmp/p); echo x > \"\$D/hosts.yml\""
blocked "find -exec of a look-alike ls by path" \
  "find ~/.config/gh -exec /tmp/x/ls {} \\;"
blocked "xargs of a look-alike grep by path" \
  "echo ~/.gitconfig | xargs /tmp/x/grep"
blocked "code piped into bash -s"                "echo 'echo x > ~/.gitconfig' | bash -s"
blocked "code piped into python3 -"              "echo \"open('$PHOME/.gitconfig','w')\" | python3 -"
blocked "bash /dev/stdin fed a heredoc"          "bash /dev/stdin <<'EOF'${NL}echo x > ~/.gitconfig${NL}EOF"
blocked "python3 -i script.py fed code"          "echo \"open('$PHOME/.gitconfig','w')\" | python3 -i /tmp/s.py"
blocked "source /dev/stdin fed a heredoc"        "source /dev/stdin <<'EOF'${NL}echo x > ~/.gitconfig${NL}EOF"
blocked ". of a process substitution"            ". <(echo 'echo x > ~/.gitconfig')"
blocked "eval naming .gitconfig"                 "eval 'echo x > ~/.gitconfig'"
blocked "a substitution-built target dir"        "D=\$(echo ~/.config/gh); echo x > \"\$D/hosts.yml\""
blocked "a loop variable target"                 "for d in ~/.config/gh; do echo x > \"\$d/hosts.yml\"; done"
blocked "a target from \$(ls -d)"                "echo x > \"\$(ls -d ~/.config/gh)/hosts.yml\""
blocked "a function called with the path"        "f() { echo x > \"\$1\"; }; f ~/.gitconfig"
blocked "a function shadowing cat"               "cat() { echo x > \"\$1\"; }; cat ~/.gitconfig"
blocked "set -- then a positional target"        "set -- ~/.gitconfig; echo x > \"\$1\""
blocked "printf -v builds the target"            "printf -v D '%s' ~/.config/gh; echo x > \"\$D/hosts.yml\""
blocked "a heredoc file read back into the target" \
  "cat > /tmp/p <<'EOF'${NL}$PHOME/.config/gh${NL}EOF${NL}D=\$(cat /tmp/p); echo x > \"\$D/hosts.yml\""
blocked "an echo file read back with read"       "echo ~/.config/gh > /tmp/p; read D < /tmp/p; echo x > \"\$D/hosts.yml\""
blocked "an unquoted heredoc whose substitution writes" \
  "cat > \"\$OUT\" <<EOF${NL}\$(echo x > ~/.gitconfig)${NL}EOF"
blocked "a ls of gh config feeding a loop's target" \
  "ls -d ~/.config/gh | while read d; do echo x > \"\$d/hosts.yml\"; done"
blocked "a read-only command in a redirected group" \
  "{ ls -d ~/.config/gh; } > /tmp/p; D=\$(cat /tmp/p); echo x > \"\$D/x\""
blocked "PATH hijack before a read-only command" \
  "PATH=/tmp/evil:\$PATH; cat ~/.gitconfig; echo x > \"\$OUT\""
section "#402: the reason says whether it was judged from a target or from text"
mention_reason="$(reason "$(run_guard "$GUARD" Bash "python3 -c \"open('opencode.json','w')\"")")"
judge "a text-judged block names code it cannot read" yes "$(has "$mention_reason" "code this parse cannot read")"
judge "  ... still sends a real write to the user"     yes "$(has "$mention_reason" "ask them to make the change themselves")"
judge "  ... and asks for a target the guard can resolve" yes "$(has "$mention_reason" "so the guard can resolve its target")"
judge "  ... naming no read-only shape that skips the scan" no "$(has "$mention_reason" "jq")"
target_reason="$(reason "$(run_guard "$GUARD" Bash "echo x > ~/.gitconfig")")"
judge "a resolved write keeps the plain R4 remedy"     yes "$(has "$target_reason" "ask them to make this change themselves")"
judge "  ... with no rewrite advice"                   no  "$(has "$target_reason" "so the guard can resolve its target")"

# git replays need the files tracked and changed, so git itself names them.
GREPO="$TMP/grepo"
harness_new_repo "$GREPO"
mkdir -p "$GREPO/.claude"
printf 'a\n' > "$GREPO/opencode.json"; printf '{}\n' > "$GREPO/.claude/settings.json"
git -C "$GREPO" add -A && git -C "$GREPO" commit -q -m base
printf 'b\n' > "$GREPO/opencode.json"; printf '{"x":1}\n' > "$GREPO/.claude/settings.json"
blocked_in() { local d; d="$(v Bash "$2" "$GREPO")"; case "$d" in deny|ask) d=blocked ;; esac; judge "$1" blocked "$d"; }
blocked_in "git checkout -- onto opencode.json"  "git checkout -- opencode.json"
blocked_in "git restore of project settings"     "git restore .claude/settings.json"
blocked_in "git apply of a patch onto opencode.json" \
  "git apply <<'EOF'${NL}--- a/opencode.json${NL}+++ b/opencode.json${NL}@@ -1 +1 @@${NL}-a${NL}+b${NL}EOF"

harness_summary
