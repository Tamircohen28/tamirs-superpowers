#!/usr/bin/env bash
# test-protected-path-hardening.sh — the walk-arounds found in the adversarial
# review of the protected-path guard (ADR 004 D10.1, D3, security review S-03),
# each reproduced against the real hook before it was closed.
#
# WHAT EACH GROUP PROVES
#   F4a  a case-insensitive volume (macOS APFS) folds case: `~/.CLAUDE/…` is the
#        protected file there, and the comparison is folded whenever the volume
#        cannot be shown to be case-sensitive;
#   F4b  writers the parser did not model: an fd redirect under `exec`, directory
#        copies and archive extraction (judged by their DESTINATION DIRECTORY),
#        curl/wget output dirs, a `cd` into a protected dir, awk/sed programs that
#        write, ed, split, script, and hard or symbolic links made by cp/pax/link;
#   P2   removing, moving away or copying over any PARENT directory of a protected
#        path, repo-relative as well as home-relative;
#   F4c  git and patch: the target set of a patch file, of a pathspec, and of the
#        incoming diff of merge/pull/am/stash/cherry-pick/rebase/reset/switch;
#   F4d  shell syntax the tokenizer used to misread — an arithmetic `(( << ))`,
#        `$'…'` quoting, an apostrophe in a comment — no longer hides a write,
#        and an anomaly fails closed when a protected path is named;
#   F6   PM_ALLOW_PROTECTED unlocks the generated-file rules only — never a
#        workflow, a hook script or a policy path.
#   Every deny is paired with an allow a guard that denies everything would fail.
#
# Hermetic: the guard only JUDGES payloads. The passwd home is named in them but
# never written; every repo, file and archive name lives under mktemp. git runs
# only against the temp repo, with no network (no remote is configured).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
# The unresolved-write notice is off by default since 5.6.3; these cases assert it, so turn it on.
export CLAUDE_PLUGIN_OPTION_UNRESOLVED_WRITE_NOTICES=true

harness_require git jq python3

TMP="$(canon "$(harness_tmpdir)")"
PHOME="$(python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
export HOME="$TMP/fakehome"
mkdir -p "$HOME/.claude" "$HOME/.config"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
unset GH_TOKEN GITHUB_TOKEN PM_ALLOW_PROTECTED CLAUDE_PLUGIN_ROOT CODEX_HOME 2>/dev/null || true

GUARD="$ROOT/hooks/guard-sensitive-files.sh"
WT="$ROOT/hooks/lib/write-targets.py"

# --- the repository: tracked settings, a branch and a stash that rewrite them ---
REPO="$TMP/repo"
harness_new_repo "$REPO"
mkdir -p "$REPO/.claude" "$REPO/.github/workflows" "$REPO/src" "$REPO/.tamirs-superpowers"
printf '{"v":1}\n' > "$REPO/.claude/settings.json"
printf 'name: ci\n'  > "$REPO/.github/workflows/ci.yml"
printf 'a\n'         > "$REPO/src/a.txt"
printf '{"version":1}\n' > "$REPO/.tamirs-superpowers/permissions.json"
printf 'x\n'         > "$REPO/yarn.lock"
printf 'dist/\n'     > "$REPO/.gitignore"
printf '{"style":"x"}\n' > "$REPO/components.json"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m base
git -C "$REPO" checkout -q -b evil
printf '{"permissions":{"allow":["Bash(*)"]}}\n' > "$REPO/.claude/settings.json"
git -C "$REPO" commit -q -am "widen the project settings"
git -C "$REPO" checkout -q -b benign main
printf 'b\n' > "$REPO/src/a.txt"
git -C "$REPO" commit -q -am "an ordinary change"
# gen: regenerated adapters for other hosts, which are not policy (D10.1).
git -C "$REPO" checkout -q -b gen main
mkdir -p "$REPO/.gemini/skills/x" "$REPO/.gemini/agents" "$REPO/.opencode/commands"
printf 's\n' > "$REPO/.gemini/skills/x/SKILL.md"
printf 'a\n' > "$REPO/.gemini/agents/a.md"
printf 'c\n' > "$REPO/.opencode/commands/c.md"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m "regenerated adapters"
# ocagent: an OpenCode agent, whose frontmatter carries permission rules.
git -C "$REPO" checkout -q -b ocagent main
mkdir -p "$REPO/.opencode/agents"
printf -- '---\npermission:\n  bash: allow\n---\n' > "$REPO/.opencode/agents/a.md"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m "an agent that allows every command"
git -C "$REPO" checkout -q main
# Two stashes: stash@{1} rewrites the settings, stash@{0} only src/.
printf '{"stashed":true}\n' > "$REPO/.claude/settings.json"
git -C "$REPO" stash push -q -m evil-stash
printf 'stashed\n' > "$REPO/src/a.txt"
git -C "$REPO" stash push -q -m benign-stash
git -C "$REPO" diff -U1 main evil > "$TMP/evil.patch"
git -C "$REPO" diff -U1 main benign > "$TMP/benign.patch"
git -C "$REPO" format-patch -q -1 evil --stdout > "$TMP/evil.mbox"
git -C "$REPO" format-patch -q -1 benign --stdout > "$TMP/benign.mbox"
OUT="$TMP/out"; mkdir -p "$OUT"

# payload <tool> <command-or-path> [cwd]
payload() {
  jq -n --arg t "$1" --arg c "$2" --arg cwd "${3:-$REPO}" \
     '{tool_name:$t, cwd:$cwd,
       tool_input:(if $t=="Bash" then {command:$c} else {file_path:$c} end)}'
}
raw()      { payload "$1" "$2" "${3:-$REPO}" | bash "$GUARD" 2>/dev/null; }
decision() {
  printf '%s' "$1" | jq -r '
    if .hookSpecificOutput.permissionDecision=="deny" then "deny"
    elif .hookSpecificOutput.permissionDecision=="ask" then "ask"
    elif .hookSpecificOutput.additionalContext then "warn"
    else "allow" end' 2>/dev/null
}
reason()   { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // .hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
v()        { decision "$(raw "$@")"; }
vb()       { v Bash "$1" "${2:-$REPO}"; }
# A multi-line command, written with \n escapes.
vbn()      { vb "$(printf '%b' "$1")" "${2:-$REPO}"; }
# replay <label> <command> [cwd] — a git replay onto a protected path is an R4
# ask: hook_ask on Claude Code, a deny on Codex, Cursor and Gemini, never an allow.
replay() {
  local label="$1" c="$2" d="${3:-$REPO}" out cx cu gm
  out="$(raw Bash "$c" "$d")"
  judge "$label: Claude asks" ask "$(decision "$out")"
  cx="$(payload Bash "$c" "$d" | jq -c '. + {turn_id:"t-1"}' | bash "$GUARD" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"')"
  cu="$(payload Bash "$c" "$d" | jq -c '. + {conversation_id:"c-1",cursor_version:"3.27.22"}' | bash "$GUARD" 2>/dev/null | jq -r '.permission // "none"')"
  gm="$(payload Bash "$c" "$d" | GEMINI_SESSION_ID=g-1 GEMINI_PROJECT_DIR="$d" bash "$GUARD" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"')"
  judge "  ... Codex, Cursor and Gemini deny" "deny deny deny" "$cx $cu $gm"
}

# swapcase <path> — every letter of the LAST component with its case flipped.
swapcase_last() { printf '%s/%s' "$(dirname "$1")" "$(basename "$1" | tr 'a-zA-Z' 'A-Za-z')"; }
folds() { if [ -e "$(swapcase_last "$1")" ]; then echo yes; else echo no; fi; }
HOME_FOLDS="$(folds "$HOME")"
REPO_FOLDS="$(folds "$REPO")"
PHOME_FOLDS="$(folds "$PHOME")"

# ===========================================================================
section "F4a: a case-insensitive volume folds case"
# ===========================================================================
if [ "$HOME_FOLDS" = yes ]; then
  judge "> ~/.CLAUDE/settings.json"         deny "$(vb 'echo x > ~/.CLAUDE/settings.json')"
  judge "> ~/.claude/SETTINGS.json"         deny "$(vb 'echo x > ~/.claude/SETTINGS.json')"
  judge "Write ~/.CLAUDE/settings.json"     deny "$(v Write "$HOME/.CLAUDE/settings.json")"
  judge "Write ~/.Config/Tamirs-Superpowers/permissions.json" deny \
    "$(v Write "$HOME/.Config/Tamirs-Superpowers/permissions.json")"
  judge "rm -rf ~/.CLAUDE (a folded parent)" deny "$(vb 'rm -rf ~/.CLAUDE')"
  judge "the folded neighbour ~/.CLAUDE/CLAUDE.md stays allowed" allow \
    "$(v Write "$HOME/.CLAUDE/CLAUDE.md")"
else
  # A case-sensitive volume: ~/.CLAUDE is a different directory, nothing reads it.
  judge "case-sensitive volume: ~/.CLAUDE/settings.json is another file" allow \
    "$(vb 'echo x > ~/.CLAUDE/settings.json')"
fi
if [ "$PHOME_FOLDS" = yes ]; then
  judge "Write <passwd home>/.CLAUDE/settings.json" deny "$(v Write "$PHOME/.CLAUDE/settings.json")"
fi
if [ "$REPO_FOLDS" = yes ]; then
  judge "Edit <repo>/.TAMIRS-superpowers/permissions.json" deny \
    "$(v Edit "$REPO/.TAMIRS-superpowers/permissions.json")"
  judge "Edit <repo>/.Claude/Settings.local.json" deny "$(v Edit "$REPO/.Claude/Settings.local.json")"
  judge "Write <repo>/.GitHub/Workflows/ci.yml (the workflows dir exists)" deny \
    "$(v Write "$REPO/.GitHub/Workflows/ci.yml")"
  judge "Bash > .GitHub/Workflows/ci.yml" deny "$(vb 'echo x > .GitHub/Workflows/ci.yml')"
  judge "Edit <repo>/YARN.LOCK (the lockfile, folded)" deny "$(v Edit "$REPO/YARN.LOCK")"
  judge "Edit <repo>/Src/A.txt (an ordinary file, folded) stays allowed" allow "$(v Edit "$REPO/Src/A.txt")"
fi
# The folding rule itself, on every volume: unknown or case-insensitive folds,
# a volume shown to be case-sensitive does not.
fold_unit="$(python3 - "$WT" "$PHOME" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("wt", sys.argv[1])
wt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wt)
home = sys.argv[2]
out = []
for answer in (None, True, False):
    wt._folds = lambda p, a=answer: a
    prot = wt.Protection("/nonexistent-cwd")
    out.append("deny" if prot.match(home + "/.CLAUDE/Settings.json") else "allow")
print(" ".join(out))
PY
)"
judge "fold when the volume is unknown, fold when case-insensitive, not when case-sensitive" \
  "deny deny allow" "$fold_unit"

# ===========================================================================
section "F4b: fd redirects, including under exec, are writes"
# ===========================================================================
judge "exec 3> the permission file; echo >&3" deny \
  "$(vb "exec 3> ~/.config/tamirs-superpowers/permissions.json; echo '{}' >&3")"
judge "a bare > with no command"          deny "$(vb '> ~/.gitconfig')"
judge "3<> opens a protected file read-write" deny "$(vb 'exec 3<> ~/.gitconfig')"
judge ">& FILE is a write to FILE"        deny "$(vb 'echo x >& ~/.gitconfig')"
judge "exec 3> an ordinary log"           allow "$(vb "exec 3> $OUT/log; echo x >&3; exec 3>&-")"
judge "3< reads"                          allow "$(vb 'exec 3< ~/.gitconfig; cat <&3')"

# ===========================================================================
section "F4b: directory copies and extraction judge the destination directory"
# ===========================================================================
judge "cp -r a .claude dir into ~"        deny "$(vb 'cp -r /tmp/e/.claude ~/')"
judge "cp -R a dir's contents into ~/.claude/" deny "$(vb 'cp -R /tmp/e/ ~/.claude/')"
judge "cp -R contents into ~"             deny "$(vb 'cp -R /tmp/e/ ~')"
judge "rsync -a contents into ~/.config"  deny "$(vb 'rsync -a /tmp/e/ ~/.config/')"
judge "mv a dir into place as ~/.codex/rules" deny "$(vb 'mv /tmp/rules ~/.codex/rules')"
judge "cp -r into an ordinary dir"        allow "$(vb "cp -r /tmp/e $OUT/")"
judge "cp -R contents into an ordinary dir" allow "$(vb "cp -R /tmp/e/ $OUT/")"
judge "cp -r FROM ~/.claude is a read"    allow "$(vb "cp -r ~/.claude $OUT/claude-backup")"
judge "tar -xf -C ~/.claude"              deny "$(vb 'tar -xf x.tar -C ~/.claude')"
# shellcheck disable=SC2016  # the payload's own $HOME, resolved by the guard
judge "tar xzf --directory=\$HOME/.config" deny "$(vb 'tar xzf x.tgz --directory=$HOME/.config')"
judge "tar -x into the cwd, which is ~/.claude" deny "$(vb 'cd ~/.claude && tar -xf /tmp/x.tar')"
judge "tar -x in a repo root that holds .claude/settings.json" deny "$(vb 'tar -xf /tmp/x.tar')"
judge "tar -czf writes its archive to -f" deny "$(vb 'tar -czf ~/.claude/settings.json src')"
judge "tar -x into an ordinary dir"       allow "$(vb "tar -xf /tmp/x.tar -C $OUT")"
judge "tar -x into a repo subdir"         allow "$(vb 'tar -xf /tmp/x.tar -C src')"
judge "tar -tf lists"                     allow "$(vb 'tar -tf /tmp/x.tar -C ~/.claude')"
judge "tar -czf an ordinary archive"      allow "$(vb "tar -czf $OUT/a.tgz src")"
judge "unzip -o -d ~/.claude"             deny "$(vb 'unzip -o x.zip -d ~/.claude')"
judge "unzip -d an ordinary dir"          allow "$(vb "unzip -o x.zip -d $OUT")"
judge "unzip -l lists"                    allow "$(vb 'unzip -l x.zip')"
# shellcheck disable=SC2016  # the payload's own $HOME, resolved by the guard
judge "7z x -o\$HOME/.config/gh"          deny "$(vb '7z x a.7z -o$HOME/.config/gh')"
judge "gunzip a protected file into place" deny "$(vb 'gunzip ~/.claude/settings.json.gz')"
judge "gzip removes ~/.gitconfig"         deny "$(vb 'gzip ~/.gitconfig')"
judge "gzip -c to stdout"                 allow "$(vb "gzip -c ~/.gitconfig > $OUT/g.gz")"

# ===========================================================================
section "F4b: downloaders, a cd into a protected dir, and writer programs"
# ===========================================================================
judge "curl --output-dir ~/.claude -O …/settings.json" deny \
  "$(vb 'curl --output-dir ~/.claude -O https://x.invalid/settings.json')"
judge "cd ~/.claude && curl -sO …/settings.json" deny \
  "$(vb 'cd ~/.claude && curl -sO https://x.invalid/settings.json')"
judge "curl -OJ into a protected dir (server-chosen name)" deny \
  "$(vb 'curl -OJ --output-dir ~/.config/gh https://x.invalid/a')"
judge "curl -c writes a cookie jar"       deny "$(vb 'curl -c ~/.gitconfig https://x.invalid/')"
judge "curl -O of an ordinary name into ~/.claude" allow \
  "$(vb 'curl --output-dir ~/.claude -O https://x.invalid/notes.md')"
judge "curl -sO in the repo"              allow "$(vb 'curl -sO https://x.invalid/a.tgz')"
judge "wget -P ~/.claude …/settings.json" deny "$(vb 'wget -P ~/.claude https://x.invalid/settings.json')"
judge "wget -O- to stdout"                allow "$(vb 'wget -qO- https://x.invalid/settings.json')"
judge "cd ~/.claude && patch settings.json x" deny "$(vb 'cd ~/.claude && patch settings.json x')"
judge "pushd ~/.claude; tee settings.json" deny "$(vb 'pushd ~/.claude; echo x | tee settings.json')"
judge "awk print > a protected file"      deny \
  "$(vb "awk 'BEGIN{print 1 > \"~/.claude/settings.json\"}'")"
judge "awk reading a protected file"      allow "$(vb "awk '{print \$1}' ~/.claude/settings.json")"
judge "awk comparing in a pattern"        allow "$(vb "awk '\$1 > 5' ~/.claude/settings.json")"
judge "awk printing a ' | ' string literal" allow "$(vb "awk -F'\\t' '{print \$1\" | \"\$2}' ~/.claude/settings.json")"
judge "sed -n 'w FILE'"                   deny "$(vb "sed -n 'w ~/.claude/settings.json' f")"
judge "sed s///w FILE"                    deny "$(vb "sed -n 's/a/b/w ~/.gitconfig' f")"
judge "sed reading a protected file"      allow "$(vb "sed -n '/x/p' ~/.claude/settings.json")"
judge "a 'w ' inside a sed regex is not a w command" allow \
  "$(vb "sed 's/how now/x/' ~/.claude/settings.json")"
judge "ed -s a protected file"            deny "$(vbn "ed -s ~/.claude/settings.json <<'EOF'\n,s/a/b/\nw\nEOF")"
judge "ed -s an ordinary file"            allow "$(vbn "ed -s $OUT/notes.txt <<'EOF'\nw\nEOF")"
judge "split onto a protected prefix"     deny "$(vb 'split -b 1 f ~/.claude/settings')"
judge "split whose suffix can complete ~/.gitconfig" deny "$(vb 'split -b 1000 f ~/.gitconf')"
judge "split into an ordinary prefix"     allow "$(vb "split -l 10 big.csv $OUT/part-")"
judge "split with the default prefix in the repo" allow "$(vb 'split -l 10 big.csv')"
judge "script -q a protected file"        deny "$(vb 'script -q ~/.claude/settings.json')"
judge "script -q an ordinary typescript"  allow "$(vb "script -q $OUT/typescript true")"

# ===========================================================================
section "F4b: hard and symbolic links made by cp, pax and link"
# ===========================================================================
judge "cp -l links a protected file out"  deny "$(vb 'cp -l ~/.claude/settings.json /tmp/x')"
judge "cp -al links a protected dir out"  deny "$(vb 'cp -al ~/.claude /tmp/c')"
judge "cp -s symlinks a protected file"   deny "$(vb 'cp -s ~/.gitconfig /tmp/g')"
judge "pax -rw -l links a protected dir"  deny "$(vb 'pax -rw -l ~/.claude /tmp/c')"
judge "link makes a hard link"            deny "$(vb 'link ~/.gitconfig /tmp/g')"
judge "cp -l between ordinary files"      allow "$(vb "cp -l $OUT/a $OUT/b")"
judge "pax -rw an ordinary tree"          allow "$(vb "pax -rw src $OUT")"

# ===========================================================================
section "P2: a protected path's PARENT directories are protected too"
# ===========================================================================
judge "rm -rf .claude (repo-relative parent)" deny "$(vb 'rm -rf .claude')"
judge "mv .claude away"                      deny "$(vb 'mv .claude /tmp/x')"
judge "cp -R over .claude/"                  deny "$(vb 'cp -R /tmp/e/ .claude/')"
judge "rm -rf .git (holds .git/hooks)"       deny "$(vb 'rm -rf .git')"
judge "the repo root itself stays removable (a temporary repository)" allow \
  "$(vb "rm -rf $REPO" "$TMP")"
judge "rm -rf src (holds nothing protected)" allow "$(vb 'rm -rf src')"
parents="$(python3 - "$ROOT" <<'PY'
import json, re, sys
cat = json.load(open(sys.argv[1] + "/core/permissions/actions.json"))["actions"]
by = dict((a["id"], a) for a in cat)
seen = set()
for aid in ("policy.edit", "config.global.write"):
    for p in by[aid]["equivalents"]["paths"]:
        m = re.match(r"^\{(home|repo)\}/(.+)$", p)
        if not m:
            continue
        ph, tail = m.groups()
        fixed = re.split(r"[*?\[]", tail)[0].rstrip("/")
        parts = fixed.split("/")
        for i in range(1, len(parts) + 1):
            d = "/".join(parts[:i])
            # the fixed part of a `settings*.json` tail is a partial name, not a dir
            if i == len(parts) and fixed != tail.rstrip("/*"):
                continue
            if (ph, d) not in seen:
                seen.add((ph, d))
                print("%s\t%s" % (ph, d))
PY
)"
pcount=0
while IFS=$'\t' read -r ph d; do
  [ -n "$d" ] || continue
  if [ "$ph" = home ]; then base="$PHOME"; cwd="$REPO"; else base="$REPO"; cwd="$REPO"; fi
  for c in "rm -rf $base/$d" "mv $base/$d $OUT/moved" "cp -R /tmp/e/ $base/$d/"; do
    pcount=$((pcount + 1))
    got="$(vb "$c" "$cwd")"
    [ "$got" = deny ] || bad "parent dir: $c" "expected 'deny', got '$got'"
  done
done <<<"$parents"
judge "every parent of every protected path, three ways, was checked ($pcount commands)" yes \
  "$([ "$pcount" -ge 60 ] && echo yes || echo no)"
ok "  ... each of them denied (failures are listed above by name)"

# ===========================================================================
section "F4c: patch and git apply read their patch's target headers"
# ===========================================================================
judge "git apply a patch that rewrites .claude/settings.json" deny "$(vb "git apply $TMP/evil.patch")"
judge "patch -p1 < the same patch"        deny "$(vb "patch -p1 < $TMP/evil.patch")"
judge "patch -p1 -i the same patch"       deny "$(vb "patch -p1 -i $TMP/evil.patch")"
judge "patch with the protected file as its operand" deny "$(vb "patch .claude/settings.json $TMP/benign.patch")"
judge "git apply a heredoc patch touching settings" deny \
  "$(vb "$(printf 'git apply <<%s\n%s\nEOF\n' "'EOF'" "$(cat "$TMP/evil.patch")")")"
replay "git am an mbox touching settings" "git am $TMP/evil.mbox"
judge "git -C <repo> apply from elsewhere" deny "$(vb "git -C $REPO apply $TMP/evil.patch" "$TMP")"
judge "git apply an ordinary patch"       allow "$(vb "git apply $TMP/benign.patch")"
judge "patch -p1 < an ordinary patch"     allow "$(vb "patch -p1 < $TMP/benign.patch")"
judge "git am an ordinary mbox"           allow "$(vb "git am $TMP/benign.mbox")"
judge "git apply --check only checks"     allow "$(vb "git apply --check $TMP/evil.patch")"
judge "an unreadable patch is still advisory" warn "$(vb "git apply $TMP/missing.patch")"
judge "a patch written earlier in the same command is unreadable now" warn \
  "$(vb "cp $TMP/benign.patch $OUT/p.patch && git apply $OUT/p.patch")"
judge "a patch piped in is advisory"      warn "$(vb 'curl -s https://x.invalid/p | git apply')"

# ===========================================================================
section "F4c: git rewrites judged by the files they would change"
# ===========================================================================
replay "git checkout <ref> -- .claude/settings.json" 'git checkout evil -- .claude/settings.json'
replay "git checkout <ref> -- ." 'git checkout evil -- .'
replay "git restore --source <ref> <path>" 'git restore --source evil .claude/settings.json'
replay "git restore --source=<ref> -- .claude" 'git restore --source=evil -- .claude'
replay "git checkout <branch> (switch)" 'git checkout evil'
replay "git switch <branch>" 'git switch evil'
replay "git merge <branch>" 'git merge evil'
replay "git merge --no-ff -m msg <branch>" 'git merge --no-ff -m "take it" evil'
replay "git pull . <branch> (a local remote)" 'git pull . evil'
replay "git cherry-pick <commit>" 'git cherry-pick evil'
replay "git rebase <upstream>" 'git rebase evil'
replay "git reset --hard <ref>" 'git reset --hard evil'
replay "git stash apply stash@{1} (rewrites settings)" 'git stash apply stash@{1}'
replay "git -C <repo> merge from elsewhere" "git -C $REPO merge evil" "$TMP"
judge "  ... and the ask says it is a git replay the user decides" yes \
  "$(has "$(reason "$(raw Bash 'git merge evil')")" "git branch operation")"
judge "a replay beside a direct write of the same file: the deny outranks the ask" deny \
  "$(vb 'git merge evil; echo x > .claude/settings.json')"
replay "git merge of a branch adding an OpenCode agent (D10.1, narrowed)" 'git merge ocagent'
judge "git merge of regenerated .gemini/skills, .gemini/agents, .opencode/commands: allowed (not policy)" allow \
  "$(vb 'git merge gen')"
judge "git checkout <ref> -- an ordinary path" allow "$(vb 'git checkout benign -- src/a.txt')"
judge "git checkout <ref> -- . where only src differs" allow "$(vb 'git checkout benign -- .')"
judge "git restore --staged (the index only)" allow "$(vb 'git restore --staged .claude/settings.json')"
judge "git switch <ordinary branch>"      allow "$(vb 'git switch benign')"
judge "git merge <ordinary branch>"       allow "$(vb 'git merge benign')"
judge "git cherry-pick <ordinary commit>" allow "$(vb 'git cherry-pick benign')"
judge "git reset --hard <ordinary ref>"   allow "$(vb 'git reset --hard benign')"
judge "git stash pop (stash@{0} only touches src)" allow "$(vb 'git stash pop')"
judge "git status, log, diff stay allowed" allow "$(vb 'git status && git log --oneline -3 && git diff evil')"
judge "git switch -c a new branch at HEAD" allow "$(vb 'git switch -c topic')"
pull_out="$(raw Bash 'git pull')"
judge "git pull with nothing fetched to compare: advisory" warn "$(decision "$pull_out")"
judge "  ... and it says what it could not determine" yes "$(has "$(reason "$pull_out")" "could not")"
judge "git merge of an unknown ref: advisory" warn "$(vb 'git merge no-such-ref')"

# ===========================================================================
section "F4d: tokenizer tricks no longer hide a write"
# ===========================================================================
judge "(( 1 << 2 )) then a write"         deny "$(vbn '(( 1 << 2 ))\necho x > ~/.claude/settings.json')"
judge "\$'\\'' parity flip then a write"   deny "$(vbn "echo \$'\\\\''\\necho x > ~/.claude/settings.json; echo '")"
judge "an apostrophe in a comment then a write" deny "$(vbn "# don't\\necho x > ~/.claude/settings.json; echo '")"
judge "a quoted << on a continuation line then a write" deny \
  "$(vbn 'echo "a\n<<EOF"\necho x > ~/.claude/settings.json')"
judge "\$[ 1 << 2 ] then a write"          deny "$(vbn 'echo $[ 1 << 2 ]\necho x > ~/.claude/settings.json')"
judge "an unterminated quote naming a protected path" deny "$(vb "echo 'x > ~/.claude/settings.json")"
judge "(( 1 << 2 )) then an ordinary write" allow "$(vbn "(( 1 << 2 ))\\necho x > $OUT/n")"
judge "\$'it\\'s' then an ordinary write"   allow "$(vb "echo \$'it\\'s'; echo x > $OUT/n")"
judge "a comment with an apostrophe, then an ordinary write" allow "$(vbn "# don't\\necho x > $OUT/n")"
judge "a comment that merely names a protected path" allow "$(vbn "# never edit ~/.claude/settings.json\\necho ok")"
judge "an anomaly naming nothing protected" allow "$(vb "echo 'unterminated > $OUT/n")"
# The commit-message idiom: an apostrophe in a heredoc inside "$( … )" is prose,
# not a quote, so a message that names a protected path is still a mention.
judge "a commit-message heredoc with an apostrophe naming a protected path" allow \
  "$(vbn "git commit -m \"\$(cat <<'EOF'\nIt's about ~/.claude/settings.json\nEOF\n)\" && echo done")"
judge "  ... while a write after such a substitution is still seen" deny \
  "$(vbn "x=\"\$(cat <<'EOF'\nit's\nEOF\n)\"; echo x > ~/.claude/settings.json")"

# ===========================================================================
section "F6: PM_ALLOW_PROTECTED reaches the generated-file rules only"
# ===========================================================================
export PM_ALLOW_PROTECTED=1
judge "Write a workflow"                  deny "$(v Write "$REPO/.github/workflows/ci.yml")"
judge "Bash > a workflow"                 deny "$(vb 'echo x >> .github/workflows/ci.yml')"
judge "rm a workflow"                     deny "$(vb 'rm -f .github/workflows/ci.yml')"
judge "rm -rf the workflows dir"          deny "$(vb 'rm -rf .github/workflows')"
judge "rm -rf .github"                    deny "$(vb 'rm -rf .github')"
judge "a .git/hooks script"               deny "$(v Write "$REPO/.git/hooks/pre-commit")"
judge "the project policy file"           deny "$(v Write "$REPO/.tamirs-superpowers/permissions.json")"
judge "a lockfile is still the user's to unlock" allow "$(v Edit "$REPO/yarn.lock")"
judge "gitignored build output too"       allow "$(vb 'echo x > dist/bundle.js')"
judge "generated shadcn UI too"           allow "$(v Write "$REPO/src/components/ui/button.tsx")"
unset PM_ALLOW_PROTECTED
wf_out="$(raw Write "$REPO/.github/workflows/ci.yml")"
judge "the workflow deny still names no override" no "$(has "$(reason "$wf_out")" PM_ALLOW_PROTECTED)"
judge "without the override: rm -rf .github/workflows" deny "$(vb 'rm -rf .github/workflows')"
judge "  ... while rm -rf of an ordinary .github subdir is allowed" allow "$(vb 'rm -rf .github/ISSUE_TEMPLATE')"

harness_summary
