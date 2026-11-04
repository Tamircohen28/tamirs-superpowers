#!/usr/bin/env bash
# test-write-target-guard.sh — the sensitive-file guard decides on the PATH
# BEING WRITTEN, not on which tool is doing the writing.
#
# WHAT THIS SUITE IS FOR
#   The guard used to be wired to `Edit|Write|MultiEdit|…` and to read a
#   `file_path` out of the payload, so every path it protected stayed writable
#   through `Bash`: `cat > f <<EOF`, `sed -i`, `tee`, `cp`. It was enforced on
#   the actors that announced themselves and invisible to everything else, which
#   is the worst possible distribution for a control whose subject is an agent —
#   agents have Bash.
#
#   Every case below therefore comes in a matched pair, because the two ways to
#   get this wrong pull in opposite directions:
#
#     - BLOCKS   — the Bash-mediated write that used to walk straight past
#     - ALLOWS   — the read-only command that merely MENTIONS a protected path
#
#   The second half is not decoration. The cheap fix for the first half is to
#   grep the command string, and that is a defect this repo already has on
#   record: `docker-guard.py` matches command text and has blocked a read-only
#   `grep` whose pattern contained a matching literal, and a `git commit -m`
#   whose message prose did. A suite with only the BLOCKS half passes just as
#   happily on a guard that has traded a known gap for a wall of false
#   positives.
#
#   The third group asserts the guard says so when it cannot tell, rather than
#   returning an answer indistinguishable from "nothing protected was touched".
#
# Hermetic: temp fixtures only, no network, no gh, no writes outside mktemp.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"

harness_require git jq python3

TMP="$(harness_tmpdir)"
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
unset GH_TOKEN GITHUB_TOKEN PM_ALLOW_PROTECTED 2>/dev/null || true

GUARD="$ROOT/hooks/guard-sensitive-files.sh"

# A repo carrying one of every protected shape at once.
REPO="$TMP/repo"
harness_new_repo "$REPO"
mkdir -p "$REPO/.github/workflows" "$REPO/src/components/ui" "$REPO/dist" \
         "$REPO/build" "$REPO/.yarn/releases" "$REPO/scripts"
printf 'dist/\n'          > "$REPO/.gitignore"
printf '{"style":"x"}\n'  > "$REPO/components.json"
printf 'x\n'              > "$REPO/yarn.lock"
printf 'x\n'              > "$REPO/dist/bundle.js"
printf 'x\n'              > "$REPO/build/keep.js"
git -C "$REPO" remote add origin https://github.com/example/x.git 2>/dev/null || true

# The once-per-session notice markers (#336) live under CLAUDE_PLUGIN_DATA or
# TMPDIR; both are pointed into the fixture so no test touches the real ones.
unset CLAUDE_PLUGIN_DATA 2>/dev/null || true
export TMPDIR="$TMP/tmpdir"
mkdir -p "$TMPDIR"

# verdict <tool> <command-or-path> -> deny | warn | allow
# SESSION, when set, is the payload's session_id (no session id => no notice marker).
SESSION=""
verdict() {
  jq -n --arg t "$1" --arg c "$2" --arg cwd "$REPO" --arg s "$SESSION" \
     '{tool_name:$t, cwd:$cwd,
       tool_input:(if $t=="Bash" or $t=="Shell" then {command:$c} else {file_path:$c} end)}
      + (if $s != "" then {session_id:$s} else {} end)' \
  | bash "$GUARD" 2>/dev/null \
  | jq -r 'if .hookSpecificOutput.permissionDecision=="deny" then "deny"
           elif .hookSpecificOutput.additionalContext then "warn"
           else "allow" end' 2>/dev/null
}
bash_verdict() { verdict Bash "$1"; }
# notice <command> -> the additionalContext text of a Bash call, "" when none.
notice() {
  jq -n --arg c "$1" --arg cwd "$REPO" --arg s "$SESSION" \
     '{tool_name:"Bash", cwd:$cwd, tool_input:{command:$c}}
      + (if $s != "" then {session_id:$s} else {} end)' \
  | bash "$GUARD" 2>/dev/null \
  | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}

# ===========================================================================
section "Bash-mediated writes to a protected path are BLOCKED"
# ===========================================================================

judge "heredoc into a workflow"       deny "$(bash_verdict "$(printf 'cat > .github/workflows/ci.yml <<%s\nname: CI\nEOF\n' "'EOF'")")"
judge "sed -i on a lockfile"          deny "$(bash_verdict "sed -i.bak 's/a/b/' yarn.lock")"
judge "tee into a lockfile"           deny "$(bash_verdict "echo x | tee pnpm-lock.yaml")"
judge "append redirect to a workflow" deny "$(bash_verdict "echo x >> .github/workflows/ci.yml")"
judge "cp into the workflows dir"     deny "$(bash_verdict "cp /tmp/ci.yml .github/workflows/")"
judge "mv onto a workflow"            deny "$(bash_verdict "mv /tmp/a.yml .github/workflows/ci.yml")"
judge "curl -o a workflow"            deny "$(bash_verdict "curl -sSL https://x/y -o .github/workflows/ci.yml")"
judge "redirect into .yarn/releases"  deny "$(bash_verdict "printf x > .yarn/releases/yarn-4.0.0.cjs")"
judge "redirect into gitignored dist" deny "$(bash_verdict "echo x > dist/bundle.js")"
judge "heredoc into shadcn ui"        deny "$(bash_verdict "$(printf 'cat > src/components/ui/b.tsx <<%s\nx\nEOF\n' "'EOF'")")"
judge "rm of a workflow"              deny "$(bash_verdict "rm -f .github/workflows/ci.yml")"
judge "a write after cd into the repo" deny "$(bash_verdict "cd $REPO && echo x > yarn.lock")"

# ===========================================================================
section "a protected path merely MENTIONED is ALLOWED — the known false positive"
# ===========================================================================

judge "grep whose PATTERN is a protected path" allow \
  "$(bash_verdict "grep -rn '.github/workflows/ci.yml' src/")"
judge "git commit -m whose MESSAGE names one"  allow \
  "$(bash_verdict "git commit -m 'fix .github/workflows/ci.yml, regenerate yarn.lock'")"
judge "a sed SCRIPT containing one"            allow \
  "$(bash_verdict "sed -i.bak 's#.github/workflows/ci.yml#x#' src/app.ts")"
judge "a heredoc BODY containing one"          allow \
  "$(bash_verdict "$(printf 'cat > README.md <<%s\nnever hand-edit yarn.lock\nEOF\n' "'EOF'")")"
judge "echo of a warning about one"            allow \
  "$(bash_verdict "echo 'do not edit .github/workflows/ci.yml'")"
judge "cat of a protected file (a read)"       allow "$(bash_verdict "cat yarn.lock")"
judge "the package manager regenerating it"    allow \
  "$(bash_verdict "yarn install --mode update-lockfile")"

section "and ordinary writes stay ALLOWED"
judge "an unprotected source file"     allow "$(bash_verdict "$(printf 'cat > src/app.ts <<%s\nx\nEOF\n' "'EOF'")")"
judge "a TRACKED build/ (not ignored)" allow "$(bash_verdict "echo x > build/keep.js")"
judge "a log redirect with 2>&1"       allow "$(bash_verdict "make build > /tmp/log.txt 2>&1")"
judge "deleting genuine build output"  allow "$(bash_verdict "rm -f dist/bundle.js")"
judge "running a named script"         allow "$(bash_verdict "bash scripts/build.sh")"

# ===========================================================================
section "what it cannot decide, it SAYS — never a silent allow"
# ===========================================================================
# The failure being defended against: returning a value indistinguishable from
# "no protected file was touched" when the real answer is "could not determine".

judge "a target from a variable the command never assigns" warn "$(bash_verdict "echo x > \$OUT")"
judge "a target from a substitution"      warn "$(bash_verdict "echo x > \$(mktemp)")"
judge "python3 -c writing inline"         warn "$(bash_verdict "python3 -c \"open('yarn.lock','w')\"")"
judge "code piped into a shell"           warn "$(bash_verdict "echo 'echo x > yarn.lock' | bash")"
judge "xargs building the command"        warn "$(bash_verdict "ls | xargs -I{} cp {} .github/workflows/")"
judge "find -exec"                        warn "$(bash_verdict "find . -name '*.yml' -exec rm {} +")"
judge "a patch naming its own targets"    warn "$(bash_verdict "git apply /tmp/p.patch")"
judge "a glob that may cover more"        warn "$(bash_verdict "rm -rf dist/*")"

# ===========================================================================
section "the Edit/Write path is unchanged"
# ===========================================================================

judge "Edit of a lockfile"          deny  "$(verdict Edit  "$REPO/yarn.lock")"
judge "Write of a workflow"         deny  "$(verdict Write "$REPO/.github/workflows/ci.yml")"
judge "Edit of ordinary source"     allow "$(verdict Edit  "$REPO/src/app.ts")"
judge "Edit of a relative path"     deny  "$(verdict Edit  "yarn.lock")"

# ===========================================================================
section "the override is honoured, and is the only way past"
# ===========================================================================
# PM_ALLOW_PROTECTED is the USER's to set (AGENTS.md hard rule 19). The test
# asserts it still works; nothing in the guard may set it.

judge "PM_ALLOW_PROTECTED=1 allows a Bash write" allow \
  "$(PM_ALLOW_PROTECTED=1 bash_verdict "echo x > yarn.lock")"
judge "  ... and the guard reads it, never sets it" no \
  "$(has "$(grep -E '^[[:space:]]*(export[[:space:]]+)?PM_ALLOW_PROTECTED=' "$GUARD" "$ROOT/hooks/lib/write-targets.py" 2>/dev/null)" PM_ALLOW_PROTECTED)"

# ===========================================================================
# The five walk-arounds found in review of the PR that introduced this guard.
#
# Each was a way to reach a protected path with the guard installed and
# silent — not a way to defeat it, which is the point: every one is a shape an
# agent writes by habit. A guard with a documented walk-past is the defect this
# suite exists to close, so each gets the assertion it lacked.
# ===========================================================================

section "1. the shipped version changes when the shipped hook does"
# A marketplace install caches hooks against the manifest version. Changing hook
# behaviour without bumping it leaves every installed copy running the OLD hook
# while `/plugin update` reports them current — the guard is "installed" and
# absent at the same time. 3.4.0 is the last version whose hooks had no
# write-target guard at all; shipping this wiring under it, ever again, would
# hand that stale cache the new version number.
PRE_GUARD_VERSION="3.4.0"
CANON_VERSION="$(jq -r '.version' "$ROOT/plugin-version.json" 2>/dev/null)"
# yes when $1 is strictly newer than $2, by semver ordering.
newer_than() {
  if [ "$1" = "$2" ]; then echo no; return; fi
  if [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$2" ]; then
    echo yes
  else
    echo no
  fi
}

judge "canonical version is above the pre-guard release" yes \
  "$(newer_than "$CANON_VERSION" "$PRE_GUARD_VERSION")"
judge "every manifest agrees with it" 0 \
  "$(bash "$ROOT/scripts/check-version-truth.sh" --check "$ROOT" >/dev/null 2>&1; echo $?)"

section "2. the guard is wired for every tool name that runs a shell"
# `records_for()` has always handled a `Shell` payload; only the hook MATCHER
# said `Bash`. On a host that names the tool `Shell`, `tee yarn.lock` kept the
# full pre-PR bypass — the guard was installed and never invoked.
HOOKS_JSON="$ROOT/hooks/hooks.json"
guard_matchers() {
  jq -r '.hooks.PreToolUse[]
         | select(any(.hooks[]; .command | test("guard-sensitive-files")))
         | .matcher' "$HOOKS_JSON" 2>/dev/null
}
judge "a Bash-matching block invokes the guard"  yes "$(has "$(guard_matchers)" "Bash")"
judge "and it matches Shell too"                 yes "$(has "$(guard_matchers)" "Shell")"
# The wiring is only worth asserting if the guard actually decides on that payload.
shell_verdict() { verdict Shell "$1"; }
judge "tee into a lockfile, as a Shell call"     deny "$(shell_verdict "tee yarn.lock")"
judge "redirect into a workflow, as a Shell call" deny \
  "$(shell_verdict "echo x >> .github/workflows/ci.yml")"
judge "a mention is still allowed on Shell"      allow "$(shell_verdict "cat yarn.lock")"

section "3. a wrapper's own OPTIONS are consumed, not left in argv0's place"
# Stripping only the wrapper NAME made its first option the command: `env -i tee
# yarn.lock` was parsed as running `-i`, which writes nothing, so the write to
# the lockfile was reported as no write at all.
judge "env -i tee"          deny "$(bash_verdict "env -i tee yarn.lock")"
judge "nice -n 10 tee"      deny "$(bash_verdict "nice -n 10 tee yarn.lock")"
judge "nice -n10 tee"       deny "$(bash_verdict "nice -n10 tee yarn.lock")"
judge "sudo -u root tee"    deny "$(bash_verdict "sudo -u root tee yarn.lock")"
judge "sudo -- tee"         deny "$(bash_verdict "sudo -- tee yarn.lock")"
judge "stacked wrappers"    deny "$(bash_verdict "env -u FOO nice -n5 sudo -H tee yarn.lock")"
judge "env FOO=bar tee"     deny "$(bash_verdict "env FOO=bar tee yarn.lock")"
# An option that MOVES THE FRAME is not consumed as an ordinary value — doing so
# would resolve the target against the wrong directory and answer confidently.
judge "env -C says so rather than guessing" warn "$(bash_verdict "env -C /tmp tee yarn.lock")"
judge "an unknown wrapper option says so"   warn "$(bash_verdict "sudo --frobnicate tee yarn.lock")"
judge "a wrapped ordinary write is allowed" allow "$(bash_verdict "sudo -u root tee src/app.ts")"

section "4. a value-taking option's VALUE is not an operand"
# `install -m 0644 /tmp/a yarn.lock` counted `0644` as a second SOURCE, which
# made the last operand look like a DIRECTORY: the guard reported writes to
# `yarn.lock/0644` and `yarn.lock/a` and never reported the write to the
# lockfile itself.
judge "install -m 0644"        deny "$(bash_verdict "install -m 0644 /tmp/a yarn.lock")"
judge "install -m0644 -o root" deny "$(bash_verdict "install -m0644 -o root /tmp/a yarn.lock")"
judge "install -m 0644 into the workflows dir" deny \
  "$(bash_verdict "install -m 0644 /tmp/a .github/workflows/ci.yml")"
judge "cp -S .bak onto a lockfile" deny "$(bash_verdict "cp -S .bak /tmp/a yarn.lock")"
judge "sed -i -e, script given by flag" deny "$(bash_verdict "sed -i -e 's/a/b/' yarn.lock")"
judge "touch -r ref"           deny "$(bash_verdict "touch -r /tmp/ref yarn.lock")"
judge "truncate -s 0"          deny "$(bash_verdict "truncate -s 0 yarn.lock")"
# `-t DIR` no longer leaves the directory sitting in the operand list as its own
# "source", which used to invent a target named after the directory.
judge "cp -t dir does not invent dir/dir" allow "$(bash_verdict "cp -t /tmp a b")"
# For cp/mv/install/ln/rsync the DESTINATION is decided by operand position, so
# an option this parse cannot size makes every later operand a guess.
judge "an unknown cp option says so"      warn "$(bash_verdict "cp --frobnicate /tmp/a yarn.lock")"
judge "a plain cp is still allowed"       allow "$(bash_verdict "cp /tmp/a src/app.ts")"
judge "sed -e naming a path in its SCRIPT is still allowed" allow \
  "$(bash_verdict "sed -i -e 's#x#yarn.lock#' src/app.ts")"

section "5. a subshell's cd dies at the closing paren"
# One global cwd, never restored at `)`, resolved `(cd /tmp); echo x > PROTECTED`
# against /tmp — so a protected path was reported as an unprotected one while
# Bash wrote the protected one. The write and the check disagreed about which
# file was being written, which is the worst shape a guard can fail in.
# Every case here writes a REPO-SCOPED protected path (shadcn UI, which is only
# protected because $REPO/components.json exists). A lockfile would not
# discriminate: `*.lock` is protected wherever it lands, so `/tmp/yarn.lock` is
# denied too and the assertion would pass whether or not the cd was scoped.
judge "write after a subshell cd"      deny \
  "$(bash_verdict "(cd /tmp; true); echo x > src/components/ui/button.tsx")"
judge "  ... and after && inside it"   deny \
  "$(bash_verdict "(cd /tmp && true); printf x > src/components/ui/button.tsx")"
judge "a cd in a PIPELINE is scoped too" deny \
  "$(bash_verdict "cd /tmp | true; echo x > src/components/ui/button.tsx")"
judge "nested subshells restore one level each" deny \
  "$(bash_verdict "(cd /tmp; (cd /var; true)); echo x > src/components/ui/button.tsx")"
# The subshell's own writes still resolve INSIDE it, and a real `cd` still moves
# the frame — the fix must not have been "ignore cd".
# Same path string, opposite verdict: under $REPO it is generated shadcn UI
# (components.json is there), under /tmp it is nothing in particular. Only a cd
# that actually took effect can produce the allow.
judge "a write INSIDE the subshell uses its cwd" allow \
  "$(bash_verdict "(cd /tmp; echo x > src/components/ui/button.tsx)")"
judge "an unscoped cd still moves the frame"     deny \
  "$(bash_verdict "cd $REPO && echo x > yarn.lock")"
judge "an unbalanced ) leaves cwd unknown"       warn \
  "$(bash_verdict "cd /tmp; true); echo x > yarn.lock")"

# ===========================================================================
section "6. a variable assigned a literal in the same command is resolved (#336)"
# ===========================================================================
# `S=/tmp/x; cp a "$S/b"` was UNSURE: an advisory on every scratch write of a
# session, and — since an advisory is an allow — a walk-past for
# `"$S/package-lock.json"`. Resolving the literal answers the real question.
# Every resolved case is paired with the shapes that must NOT resolve, because
# a guessed value is a confident wrong answer in either direction.
# shellcheck disable=SC2016  # every $S below is the payload's, not this shell's
S_SCRATCH="$TMP/scratch"; mkdir -p "$S_SCRATCH"
judge "a literal scratch dir: no notice"      allow "$(bash_verdict "S=$S_SCRATCH; cp /tmp/a \"\$S/b\"")"
judge "a lockfile through the variable: BLOCKED" deny \
  "$(bash_verdict "S=$S_SCRATCH; cp /tmp/a \"\$S/package-lock.json\"")"
judge "a workflow through the variable: BLOCKED" deny \
  "$(bash_verdict "OUT=.github/workflows/ci.yml; echo x > \$OUT")"
judge "a redirect through \${S}"              deny "$(bash_verdict "S=$REPO; echo x > \"\${S}/yarn.lock\"")"
judge "export NAME=literal is a builtin: not resolved" warn "$(bash_verdict "export S=$REPO; echo x > \$S/yarn.lock")"
judge "a double-quoted literal"               deny "$(bash_verdict "S=\"$REPO\"; echo x > \$S/yarn.lock")"
judge "a chain of literals"                   deny "$(bash_verdict "R=$REPO; S=\$R; echo x > \$S/yarn.lock")"
judge "cd through the variable moves the frame" deny "$(bash_verdict "S=$REPO; cd \$S && echo x > yarn.lock")"
judge "  ... and a resolved ordinary write is allowed" allow \
  "$(bash_verdict "S=$REPO; echo x > \$S/src/app.ts")"
# What must stay UNSURE: the value is not a literal, or the assignment might
# not have run, or something later may have changed it.
judge "a substitution value"            warn "$(bash_verdict "S=\$(mktemp -d); echo x > \$S/yarn.lock")"
judge "reassigned by a substitution"    warn "$(bash_verdict "S=$REPO; S=\$(mktemp -d); echo x > \$S/yarn.lock")"
judge "the NAME=value cmd prefix form"  warn "$(bash_verdict "S=$REPO echo x > \$S/yarn.lock")"
judge "assigned in a subshell"          warn "$(bash_verdict "(S=$REPO); echo x > \$S/yarn.lock")"
judge "assigned in a pipeline"          warn "$(bash_verdict "S=$REPO | true; echo x > \$S/yarn.lock")"
judge "assigned after &&"               warn "$(bash_verdict "false && S=$REPO; echo x > \$S/yarn.lock")"
judge "assigned under then"             warn "$(bash_verdict "if true; then S=$REPO; fi; echo x > \$S/yarn.lock")"
judge "unset afterwards"                warn "$(bash_verdict "S=$REPO; unset S; echo x > \$S/yarn.lock")"
judge "read afterwards"                 warn "$(bash_verdict "S=$REPO; read S; echo x > \$S/yarn.lock")"
judge "a for loop variable"             warn "$(bash_verdict "S=$REPO; for S in a; do :; done; echo x > \$S/yarn.lock")"
judge "appended with +="                warn "$(bash_verdict "S=$REPO; S+=/x; echo x > \$S/yarn.lock")"
judge "an array"                        warn "$(bash_verdict "S=($REPO); echo x > \$S/yarn.lock")"
judge "arithmetic afterwards"           warn "$(bash_verdict "S=$REPO; ((S=1)); echo x > \$S/yarn.lock")"
judge "a \${S:=} expansion afterwards"  warn "$(bash_verdict "S=$REPO; : \"\${S:=x}\"; echo x > \$S/yarn.lock")"
judge "eval in between"                 warn "$(bash_verdict "S=$REPO; eval true; echo x > \$S/yarn.lock")"
judge "a different parameter form"      warn "$(bash_verdict "S=$REPO; echo x > \"\${S:-/d}/yarn.lock\"")"
judge "an escaped dollar is not a variable" warn "$(bash_verdict "S=$REPO; echo x > \\\$S/yarn.lock")"
judge "an unquoted use that would word-split" warn "$(bash_verdict "S='$REPO /x'; echo x > \$S/yarn.lock")"
judge "a glob through the variable is still a glob" warn "$(bash_verdict "S=$S_SCRATCH; rm -f \$S/*.txt")"
# The table is the command's text, never this process's environment: a variable
# the session exports but the command never assigns stays unresolved.
judge "an exported variable the command never assigns stays unresolved" warn \
  "$(S="$REPO" bash_verdict "echo x > \$S/yarn.lock")"

# Codex review of PR #359, two P1 bypasses: each made a protected write look like
# a /tmp write, which the guard then cleared silently — worse than the advisory
# the parent revision gave. Every row here writes the repo's workflow through a
# variable whose TRUE value is .github; the hardened answer is deny (resolved
# correctly) or warn (left unresolved), and never allow. `checked` maps both
# safe answers to one word so the assertion survives a later improvement that
# turns a warn into a deny.
checked() { case "$(bash_verdict "$1")" in deny|warn) echo checked ;; *) echo allow ;; esac; }
W='$S/workflows/ci.yml'
# (1) An assignment anywhere inside a compound command is forgotten, not only
#     in the segment that begins with `then`/`do`.
judge "P1-1 the exact case: second statement of a then-body" checked \
  "$(checked "S=.github; if false; then :; S=/tmp; fi; echo x > \"$W\"")"
judge "P1-1 an elif body"           checked "$(checked "S=.github; if false; then :; elif true; then S=/tmp; fi; echo x > \"$W\"")"
judge "P1-1 an else body"           checked "$(checked "S=.github; if false; then :; else :; S=/tmp; fi; echo x > \"$W\"")"
judge "P1-1 a nested loop body"     checked "$(checked "S=.github; for i in 1; do for j in 1; do :; S=/tmp; done; done; echo x > \"$W\"")"
judge "P1-1 a while body"           checked "$(checked "S=.github; while false; do :; S=/tmp; done; echo x > \"$W\"")"
judge "P1-1 a case body"            checked "$(checked "S=.github; case x in a) :; S=/tmp;; esac; echo x > \"$W\"")"
judge "P1-1 a brace group"          checked "$(checked "S=.github; { S=/tmp; }; echo x > \"$W\"")"
judge "P1-1 a subshell"             checked "$(checked "S=.github; (S=/tmp); echo x > \"$W\"")"
judge "P1-1 a function body"        checked "$(checked "S=.github; f() { S=/tmp; }; f; echo x > \"$W\"")"
judge "P1-1 export inside a body"   checked "$(checked "S=.github; if false; then :; export S=/tmp; fi; echo x > \"$W\"")"
judge "P1-1 declare inside a body"  checked "$(checked "S=.github; if false; then :; declare S=/tmp; fi; echo x > \"$W\"")"
judge "P1-1 the body on its own lines" checked \
  "$(checked "$(printf 'S=.github\nif false\nthen\n  S=/tmp\nfi\necho x > "%s"' "$W")")"
judge "P1-1 a subshell assignment is not restored over a later one" checked \
  "$(checked "S=/tmp; (S=.github; case x in a) :;; esac; echo x > \"$W\")")"
# (2) A command's redirections are opened before the command runs, so they
#     resolve with the table as it stood before that command's assignments.
#     (Under the whitelist below a name assigned twice, or by a builtin, is
#     not resolved at all, so these are now UNSURE; the row holds either way.)
judge "P1-2 the exact case: export with a redirect" checked \
  "$(checked "S=.github; export S=/tmp > \"$W\"")"
judge "P1-2 declare with a redirect"  checked "$(checked "S=.github; declare S=/tmp > \"$W\"")"
judge "P1-2 local with a redirect"    checked "$(checked "S=.github; local S=/tmp > \"$W\"")"
judge "P1-2 readonly with a redirect" checked "$(checked "S=.github; readonly S=/tmp > \"$W\"")"
judge "P1-2 typeset with a redirect"  checked "$(checked "S=.github; typeset S=/tmp > \"$W\"")"
judge "P1-2 a bare assignment with a redirect" checked "$(checked "S=.github; S=/tmp > \"$W\"")"
judge "P1-2 printf -v with a redirect" checked "$(checked "S=.github; printf -v S /tmp > \"$W\"")"
judge "P1-2 a name assigned twice resolves nowhere" warn \
  "$(bash_verdict "S=src; export S=/tmp > \"\$S/app.ts\"; echo y > \"\$S/z\"")"
# (3) Round three: a declaration builtin expands every operand before it
#     assigns any (`export S=/tmp T="$S"` gives T the OLD S), and `S[0]=` was
#     not read as touching S. Rather than name each form, the table is now a
#     WHITELIST on the whole command text: NAME resolves only when it occurs
#     exactly once as `NAME=` and everywhere else only as `$NAME`/`${NAME}`,
#     that one assignment is a bare top-level statement, and the text names
#     no eval/source/./exec/`sh -c`. Every other occurrence disqualifies it.
judge "P1-3 the exact case: export with two operands" checked \
  "$(checked "S=.github; export S=/tmp T=\"\$S\"; echo x > \"\$T/workflows/ci.yml\"")"
judge "P1-3 a bare second operand too"      checked \
  "$(checked "S=.github; T=\"\$S\" S=/tmp; echo x > \"\$T/workflows/ci.yml\"")"
judge "P1-4 the exact case: an indexed assignment" checked \
  "$(checked "S=/tmp; S[0]=.github; echo x > \"$W\"")"
judge "P1-4 an indexed expansion"           warn "$(bash_verdict "S=$REPO; echo x > \"\${S[0]}/yarn.lock\"")"
judge "P1-4 \$S[ is not trusted either"     warn "$(bash_verdict "S=$REPO; echo x > \"\$S[0]/yarn.lock\"")"
judge "a nameref"                           checked \
  "$(checked "S=/tmp; declare -n R=S; R=.github; cp /tmp/a \"$W\"")"
judge "  ... the row as reviewed"           warn "$(bash_verdict "S=/tmp; declare -n R=S; R=.github; cp a \"\$S/ci.yml\"")"
judge "let afterwards"                      warn "$(bash_verdict "S=/tmp; let S=1; echo x > \"$W\"")"
judge "getopts afterwards"                  warn "$(bash_verdict "S=$REPO; getopts a S; echo x > \$S/yarn.lock")"
# (The payload below is only judged, never run; the version guard in it is
# what a real script would carry, and what the static GNU-ism check expects.)
judge "mapfile afterwards"                  warn \
  "$(bash_verdict "S=$REPO; [ \"\${BASH_VERSINFO[0]}\" -ge 4 ] && mapfile S; echo x > \$S/yarn.lock")"
judge "\${#S} afterwards"                   warn "$(bash_verdict "S=$REPO; : \"\${#S}\"; echo x > \$S/yarn.lock")"
judge "the name as a bare word anywhere"    warn "$(bash_verdict "S=$REPO; echo S; echo x > \$S/yarn.lock")"
judge "a quoted name is a command, not an assignment" warn "$(bash_verdict "\"S=$REPO\"; echo x > \$S/yarn.lock")"
judge "  ... even inside a comment"         warn "$(bash_verdict "S=$REPO; echo x > \$S/yarn.lock # S is scratch")"
judge "  ... even inside a heredoc body"    warn \
  "$(bash_verdict "$(printf 'S=%s; cat <<EOF\nS=other\nEOF\necho x > $S/yarn.lock' "$REPO")")"
judge "exec anywhere resolves nothing"      warn "$(bash_verdict "S=$REPO; exec 3>/dev/null; echo x > \$S/yarn.lock")"
judge "bash -c anywhere resolves nothing"   warn "$(bash_verdict "S=$REPO; bash -c true; echo x > \$S/yarn.lock")"
judge "/bin/sh -ec anywhere resolves nothing" warn "$(bash_verdict "S=$REPO; /bin/sh -ec true; echo x > \$S/yarn.lock")"
judge "source anywhere resolves nothing"    warn "$(bash_verdict "S=$REPO; source ./env; echo x > \$S/yarn.lock")"
judge ". anywhere resolves nothing"         warn "$(bash_verdict "S=$REPO; . ./env; echo x > \$S/yarn.lock")"
# (4) Round four. Names bash sets on its own carry no `NAME=` in the text:
#     `read` with no operand sets REPLY, `cd` sets PWD. The Bash manual's
#     "Shell Variables" list is a closed denylist (SHELL_MANAGED_NAMES).
judge "P1-5 the exact case: REPLY set by read"   checked \
  "$(checked "$(printf 'REPLY=/tmp; read <<< .github; echo x > "$REPLY/workflows/ci.yml"')")"
judge "P1-5 the exact case: PWD set by cd"       checked \
  "$(checked 'PWD=/tmp; cd .github; echo x > "$PWD/workflows/ci.yml"')"
judge "P1-5 OLDPWD"                              warn "$(bash_verdict "OLDPWD=$REPO; cd /; echo x > \$OLDPWD/yarn.lock")"
judge "P1-5 OPTARG"                              warn "$(bash_verdict "OPTARG=$REPO; getopts a: x -a y; echo x > \$OPTARG/yarn.lock")"
judge "P1-5 RANDOM"                              warn "$(bash_verdict "RANDOM=$REPO; echo x > \$RANDOM/yarn.lock")"
judge "P1-5 a BASH_* name"                       warn "$(bash_verdict "BASH_REMATCH=$REPO; echo x > \$BASH_REMATCH/yarn.lock")"
judge "P1-5 an LC_ name"                         warn "$(bash_verdict "LC_ALL=$REPO; echo x > \$LC_ALL/yarn.lock")"
judge "P1-5 the underscore"                      warn "$(bash_verdict "_=$REPO; echo x > \$_/yarn.lock")"
judge "P1-5 TMPDIR"                              warn "$(bash_verdict "TMPDIR=$REPO; echo x > \$TMPDIR/yarn.lock")"
#     A newline after `&&`, `||` or `|` closes an empty segment; the operator
#     must keep governing the next line (a comment line in between too).
judge "P1-6 the exact case: assignment after &&-newline" checked \
  "$(checked "$(printf 'S=.github; false &&\nS=/tmp; echo x > "%s"' "$W")")"
judge "P1-6 after ||-newline"                    checked \
  "$(checked "$(printf 'S=.github; true ||\nS=/tmp; echo x > "%s"' "$W")")"
judge "P1-6 after |-newline (a pipeline component)" warn \
  "$(bash_verdict "$(printf 'true |\nS=%s; echo x > $S/yarn.lock' "$REPO")")"
judge "P1-6 a comment line between && and the assignment" checked \
  "$(checked "$(printf 'S=.github; false && # later\nS=/tmp; echo x > "%s"' "$W")")"
judge "P1-6 a blank line between && and the assignment" checked \
  "$(checked "$(printf 'S=.github; false &&\n\nS=/tmp; echo x > "%s"' "$W")")"
judge "P1-6 a newline after ; is still unconditional" deny \
  "$(bash_verdict "$(printf 'true;\nS=%s; echo x > $S/yarn.lock' "$REPO")")"
judge "P1-6 (false) && on the next line is conditional" warn \
  "$(bash_verdict "$(printf '(false) &&\nS=%s; echo x > $S/yarn.lock' "$REPO")")"
# ... and the whitelist admits the plain case this issue is about.
judge "the plain case still resolves: a scratch write, no notice" allow \
  "$(bash_verdict "S=$S_SCRATCH; cp /tmp/a \"\$S/b\"")"
judge "the plain case still resolves: a lockfile, a block" deny \
  "$(bash_verdict "S=$REPO; echo x > \"\$S/yarn.lock\"")"
judge "a heredoc that only expands the name is fine" deny \
  "$(bash_verdict "$(printf 'S=%s; cat <<EOF\n$S\nEOF\necho x > $S/yarn.lock' "$REPO")")"
# Found while writing the rows above, present on the parent revision too: a
# reserved word that introduces a command sat in argv0's place, so the write
# primitive after it was never parsed and `if true; then cp /tmp/a yarn.lock;
# fi` was cleared with no record at all (a redirection after `then` was caught,
# being the shell's; a cp/tee/sed -i was not). Same class — a reserved word in
# command position mishandled — so it is closed here.
judge "cp after then is parsed"      deny "$(bash_verdict "if true; then cp /tmp/a yarn.lock; fi")"
judge "tee after do is parsed"       deny "$(bash_verdict "while true; do tee yarn.lock; done")"
judge "cp inside a brace group"      deny "$(bash_verdict "{ cp /tmp/a yarn.lock; }")"
judge "cp as the if condition"       deny "$(bash_verdict "if cp /tmp/a yarn.lock; then :; fi")"
judge "sed -i after else"            deny "$(bash_verdict "if false; then :; else sed -i.bak s/a/b/ yarn.lock; fi")"
judge "a negated write"              deny "$(bash_verdict "! tee yarn.lock")"
judge "a mention after then is still a mention" allow "$(bash_verdict "if true; then cat yarn.lock; fi")"
# The scoping must not have been "ignore every compound": a top-level literal
# still resolves inside a body that only USES it.
judge "a top-level literal used inside a loop body resolves" deny \
  "$(bash_verdict "S=$REPO; for f in a; do cp \$f \"\$S/yarn.lock\"; done")"
judge "a top-level literal used inside a then-body resolves" deny \
  "$(bash_verdict "S=$REPO; if true; then echo x > \"\$S/yarn.lock\"; fi")"
judge "a top-level literal after a closed compound resolves" deny \
  "$(bash_verdict "if true; then :; fi; S=$REPO; echo x > \"\$S/yarn.lock\"")"

# ===========================================================================
section "7. each unresolved-write kind is explained once per session (#336)"
# ===========================================================================
# Sixty identical hundred-token paragraphs in one session buried its two real
# blocks. The paragraph is shown once per (session, kind of reason); a repeat
# is one line that still names what was not checked — never silence.
FULL="NOT checked against the protected-path rules"
BRIEF="same notice as earlier this session"
SESSION="sess-$$-a"
first="$(notice "python3 -c \"open('x','w')\"")"
second="$(notice "python3 -c \"open('y','w')\"")"
judge "the first inline-interpreter notice is the full paragraph" yes "$(has "$first" "$FULL")"
judge "the second is not"                                        no  "$(has "$second" "$FULL")"
judge "  ... but is still a notice"                              yes "$(has "$second" "$BRIEF")"
judge "  ... naming the kind that was not checked"               yes "$(has "$second" "runs code supplied to it")"
judge "  ... and the verdict is still warn, never allow"        warn "$(bash_verdict "python3 -c \"open('z','w')\"")"
judge "a different kind in the same session is full again"      yes \
  "$(has "$(notice "echo x > \$(mktemp)")" "$FULL")"
judge "  ... and a repeat of it is brief"                        no \
  "$(has "$(notice "echo x > \$(mktemp)")" "$FULL")"
judge "a new kind beside a repeat: full, with the repeat folded in" yes \
  "$(has "$(notice "rm -rf dist/*; python3 -c \"open('w','w')\"")" "(same unresolved-write notice as earlier this session")"
SESSION="sess-$$-b"
judge "another session starts over"                              yes \
  "$(has "$(notice "python3 -c \"open('x','w')\"")" "$FULL")"
SESSION=""
judge "no session id: the full notice every time"                yes \
  "$(has "$(notice "python3 -c \"open('x','w')\"")" "$FULL")"
judge "  ... and again"                                          yes \
  "$(has "$(notice "python3 -c \"open('x','w')\"")" "$FULL")"
judge "a block is never deduplicated"                            deny \
  "$(SESSION="sess-$$-a" bash_verdict "python3 -c \"open('yarn.lock','w')\"; echo x > yarn.lock")"
judge "the markers live under the fixture TMPDIR, nowhere else" yes \
  "$(exists "$TMPDIR/guard-sensitive-files")"

harness_summary
