#!/usr/bin/env bash
# test-security-regressions.sh — the walk-arounds an adversarial review found
# against the protected-file guard (hooks/guard-sensitive-files.sh, GSF), replayed
# against the real hook. Each row names its finding: F4a-F4d, F6 and Codex P2.
# tests/hooks/test-protected-path-hardening.sh holds each fix in depth; this file
# is the one place that replays the review itself.
#
# The permission guard, its resolver and configuration-command rows left with 6.0.0
# (ADR 006). A git replay is no longer judged, so its rows assert that it is
# neither asked nor denied.
#
# AGAINST ANOTHER TREE
#   SEC_ROOT=<plugin tree> judges that tree's hook with these same inputs (the
#   harness stays this checkout's). A row whose hook that tree lacks fails as
#   "missing". SEC_ROWS=<file> receives one line per row:
#   <finding> <tab> pass|fail <tab> <label>.
#
# HERMETIC
#   No command here is run, only judged; every repository lives under mktemp.
#
# Bash 3.2 compatible.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$HERE/tests/lib/harness.sh"
harness_require jq python3 git

SUT="$(cd "${SEC_ROOT:-$HERE}" && pwd -P)"
GSF="$SUT/hooks/guard-sensitive-files.sh"

T="$(harness_tmpdir)"
T="$(cd "$T" && pwd -P)"
chmod 700 "$T"
export HOME="$T/env-home"
mkdir -p "$HOME/.claude" "$HOME/.config"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$T/gitconfig"
: > "$GIT_CONFIG_GLOBAL"
unset CODEX_HOME GEMINI_SESSION_ID GEMINI_PROJECT_DIR GEMINI_CWD GH_REPO GH_HOST PLUGIN_ROOT PLUGIN_DATA \
  CLAUDE_PLUGIN_ROOT CURSOR_PLUGIN_ROOT PM_ALLOW_PROTECTED GH_TOKEN GITHUB_TOKEN 2>/dev/null || true
export NO_COLOR=1

ROWS="${SEC_ROWS:-$T/rows.tsv}"
: > "$ROWS"
# row <finding> <label> <yes|no> [why] — one judged input of the review.
row() {
  if [ "$3" = yes ]; then
    ok "[$1] $2"
    printf '%s\tpass\t%s\n' "$1" "$2" >> "$ROWS"
  else
    bad "[$1] $2" "${4:-}"
    printf '%s\tfail\t%s\n' "$1" "$2" >> "$ROWS"
  fi
}

# --- the repository: tracked settings and a workflow, a branch that widens them ---------
REPO="$T/repo"
harness_new_repo "$REPO" main
mkdir -p "$REPO/.claude" "$REPO/.github/workflows" "$REPO/src"
printf '{"v":1}\n'       > "$REPO/.claude/settings.json"
printf 'name: ci\n'      > "$REPO/.github/workflows/ci.yml"
printf 'a\n'             > "$REPO/src/a.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m base
git -C "$REPO" remote add origin https://github.com/me/app.git
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$REPO" checkout -q -b evil
printf '{"permissions":{"allow":["Bash(*)"]}}\n' > "$REPO/.claude/settings.json"
git -C "$REPO" commit -q -am "widen the project settings"
git -C "$REPO" diff -U1 main evil > "$T/evil.patch"
git -C "$REPO" format-patch -q -1 evil --stdout > "$T/evil.mbox"
git -C "$REPO" checkout -q -b feat main
printf 'x\n' > "$REPO/README"
git -C "$REPO" add README && git -C "$REPO" commit -qm readme
git -C "$REPO" update-ref refs/remotes/origin/feat HEAD
case "$REPO" in "$T"/*) ;; *) echo "fixture $REPO escaped the temp dir" >&2; exit 2 ;; esac

# --- payloads and verdicts ---------------------------------------------------------------
claude_bash() { jq -nc --arg c "$1" --arg d "${2:-$REPO}" '{session_id:"sr-1",transcript_path:"/t",cwd:$d,hook_event_name:"PreToolUse",permission_mode:"default",tool_name:"Bash",tool_use_id:"call-1",tool_input:{command:$c,description:"probe"}}'; }
edit_payload() { jq -nc --arg t "$1" --arg p "$2" --arg d "$REPO" '{session_id:"sr-1",cwd:$d,hook_event_name:"PreToolUse",tool_name:$t,tool_use_id:"call-1",tool_input:{file_path:$p}}'; }

# decide <hook> <dialect> <payload> -> allow|ask|deny|missing|invalid
decide() {
  local hook="$1" dialect="$2" payload="$3" out n
  [ -f "$hook" ] || { echo missing; return; }
  case "$dialect" in
    codex)  out="$(printf '%s' "$payload" | CODEX_HOME="$T/codex-home" bash "$hook" 2>/dev/null)" ;;
    gemini) out="$(printf '%s' "$payload" | GEMINI_SESSION_ID=g-1 GEMINI_PROJECT_DIR="$REPO" bash "$hook" 2>/dev/null)" ;;
    *)      out="$(printf '%s' "$payload" | bash "$hook" 2>/dev/null)" ;;
  esac
  n="$(printf '%s' "$out" | jq -s 'length' 2>/dev/null || echo 0)"
  [ "$n" = 1 ] || { echo "invalid"; return; }
  case "$dialect" in
    cursor) printf '%s' "$out" | jq -r '.permission // "allow"' ;;
    *)      printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' ;;
  esac
}

# gsf <finding> <label> <deny|pass> <Bash command | Tool:path> [cwd] — GSF, every host:
#   deny  a deny on Claude Code and on Codex;
#   pass  no decision on Claude Code, Codex, Cursor and Gemini (never an ask).
gsf() {
  local id="$1" label="$2" want="$3" arg="$4" d="${5:-$REPO}" p c x u g v=no
  case "$arg" in
    Write:*|Edit:*) p="$(edit_payload "${arg%%:*}" "${arg#*:}")" ;;
    *)              p="$(claude_bash "$arg" "$d")" ;;
  esac
  c="$(decide "$GSF" claude "$p")"
  x="$(decide "$GSF" codex "$(printf '%s' "$p" | jq -c '. + {turn_id:"t-1"}')")"
  case "$want" in
    deny) [ "$c" = deny ] && [ "$x" = deny ] && v=yes
          row "$id" "$label" "$v" "claude $c, codex $x" ;;
    pass) u="$(decide "$GSF" cursor "$(printf '%s' "$p" | jq -c '. + {conversation_id:"c-1",cursor_version:"3.27.22"}')")"
          g="$(decide "$GSF" gemini "$p")"
          [ "$c" = allow ] && [ "$x" = allow ] && [ "$u" = allow ] && [ "$g" = allow ] && v=yes
          row "$id" "$label" "$v" "claude $c, codex $x, cursor $u, gemini $g" ;;
  esac
}
fold_yes() { [ -e "$(dirname "$1")/$(basename "$1" | tr 'a-zA-Z' 'A-Za-z')" ]; }

# =========================================================================================
section "F4a: a case-insensitive volume folds case"
# =========================================================================================
if fold_yes "$HOME/.claude"; then
  gsf F4a "echo x > ~/.CLAUDE/settings.json" deny 'echo x > ~/.CLAUDE/settings.json'
  gsf F4a "echo x > ~/.claude/SETTINGS.json" deny 'echo x > ~/.claude/SETTINGS.json'
  gsf F4a "Write ~/.CLAUDE/settings.json" deny "Write:$HOME/.CLAUDE/settings.json"
  gsf F4a "rm -rf ~/.CLAUDE (a folded parent)" deny 'rm -rf ~/.CLAUDE'
else
  skip "[F4a] case folding" "this volume is case-sensitive: ~/.CLAUDE is another directory"
fi

section "F4b: fd redirects, copies, extraction, downloaders, writer programs and links"
gsf F4b "exec 3> ~/.config/gh/hosts.yml; echo '{}' >&3" deny "exec 3> ~/.config/gh/hosts.yml; echo '{}' >&3"
gsf F4b "a bare > ~/.gitconfig" deny '> ~/.gitconfig'
gsf F4b "exec 3<> ~/.gitconfig" deny 'exec 3<> ~/.gitconfig'
gsf F4b "echo x >& ~/.gitconfig" deny 'echo x >& ~/.gitconfig'
gsf F4b "cp -R /tmp/e/ ~/.claude/" deny 'cp -R /tmp/e/ ~/.claude/'
gsf F4b "rsync -a /tmp/e/ ~/.config/" deny 'rsync -a /tmp/e/ ~/.config/'
gsf F4b "mv /tmp/rules ~/.codex/rules" deny 'mv /tmp/rules ~/.codex/rules'
gsf F4b "tar -xf x.tar -C ~/.claude" deny 'tar -xf x.tar -C ~/.claude'
gsf F4b "tar -xf in a repo root that holds .claude/settings.json" deny 'tar -xf /tmp/x.tar'
gsf F4b "unzip -o x.zip -d ~/.claude" deny 'unzip -o x.zip -d ~/.claude'
gsf F4b "curl --output-dir ~/.claude -O .../settings.json" deny 'curl --output-dir ~/.claude -O https://x.invalid/settings.json'
gsf F4b "cd ~/.claude && curl -sO .../settings.json" deny 'cd ~/.claude && curl -sO https://x.invalid/settings.json'
gsf F4b "wget -P ~/.claude .../settings.json" deny 'wget -P ~/.claude https://x.invalid/settings.json'
gsf F4b "pushd ~/.claude; echo x | tee settings.json" deny 'pushd ~/.claude; echo x | tee settings.json'
gsf F4b "awk 'BEGIN{print 1 > \"~/.claude/settings.json\"}'" deny "awk 'BEGIN{print 1 > \"~/.claude/settings.json\"}'"
gsf F4b "sed -n 'w ~/.claude/settings.json' f" deny "sed -n 'w ~/.claude/settings.json' f"
gsf F4b "gzip ~/.gitconfig (removes it)" deny 'gzip ~/.gitconfig'
gsf F4b "split -b 1 f ~/.claude/settings" deny 'split -b 1 f ~/.claude/settings'
gsf F4b "script -q ~/.claude/settings.json" deny 'script -q ~/.claude/settings.json'
gsf F4b "cp -l ~/.claude/settings.json /tmp/x (a hard link out)" deny 'cp -l ~/.claude/settings.json /tmp/x'
gsf F4b "link ~/.gitconfig /tmp/g" deny 'link ~/.gitconfig /tmp/g'

section "F4c: patches are judged by the files they change; git replays are not judged (6.0.0)"
gsf F4c "git apply <a patch rewriting .claude/settings.json>" deny "git apply $T/evil.patch"
gsf F4c "patch -p1 < the same patch" deny "patch -p1 < $T/evil.patch"
gsf F4c "git merge <a branch rewriting settings>" pass 'git merge evil'
gsf F4c "git checkout <ref> -- .claude/settings.json" pass 'git checkout evil -- .claude/settings.json'
gsf F4c "git restore --source <ref> .claude/settings.json" pass 'git restore --source evil .claude/settings.json'
gsf F4c "git switch <that branch>" pass 'git switch evil'
gsf F4c "git reset --hard <that branch>" pass 'git reset --hard evil'
gsf F4c "git cherry-pick <its commit>" pass 'git cherry-pick evil'
gsf F4c "git pull . <that branch>" pass 'git pull . evil'

section "F4d: tokenizer tricks no longer hide a write"
gsf F4d "(( 1 << 2 )) then a write" deny "$(printf '%b' '(( 1 << 2 ))\necho x > ~/.claude/settings.json')"
gsf F4d "\$'\\'' parity flip then a write" deny "$(printf '%b' "echo \$'\\\\''\\necho x > ~/.claude/settings.json; echo '")"
gsf F4d "an apostrophe in a comment then a write" deny "$(printf '%b' "# don't\\necho x > ~/.claude/settings.json; echo '")"
gsf F4d "\$[ 1 << 2 ] then a write" deny "$(printf '%b' 'echo $[ 1 << 2 ]\necho x > ~/.claude/settings.json')"
gsf F4d "an unterminated quote naming a protected path" deny "echo 'x > ~/.claude/settings.json"

# =========================================================================================
section "F6: PM_ALLOW_PROTECTED never reaches a hook script or a host settings path"
# =========================================================================================
export PM_ALLOW_PROTECTED=1
gsf F6 "Write .git/hooks/pre-commit under the override" deny "Write:$REPO/.git/hooks/pre-commit"
gsf F6 "Write the project's Claude settings under the override" deny "Write:$REPO/.claude/settings.json"
unset PM_ALLOW_PROTECTED

# =========================================================================================
section "Codex P2: a protected path's parent directory is protected too"
# =========================================================================================
gsf P2 "rm -rf .claude" deny 'rm -rf .claude'
gsf P2 "mv .claude /tmp/x" deny 'mv .claude /tmp/x'
gsf P2 "cp -R /tmp/e/ .claude/" deny 'cp -R /tmp/e/ .claude/'
gsf P2 "rm -rf .git (holds .git/hooks and .git/config)" deny 'rm -rf .git'

section "rows by finding"
for id in F4a F4b F4c F4d F6 P2; do
  p="$(awk -F'\t' -v i="$id" '$1 == i && $2 == "pass"' "$ROWS" | wc -l | tr -d ' ')"
  f="$(awk -F'\t' -v i="$id" '$1 == i && $2 == "fail"' "$ROWS" | wc -l | tr -d ' ')"
  printf '  %-6s %3s pass %3s fail\n' "$id" "$p" "$f"
done
printf '  all   %3s pass %3s fail\n' "$(awk -F'\t' '$2 == "pass"' "$ROWS" | wc -l | tr -d ' ')" "$(awk -F'\t' '$2 == "fail"' "$ROWS" | wc -l | tr -d ' ')"

harness_summary
