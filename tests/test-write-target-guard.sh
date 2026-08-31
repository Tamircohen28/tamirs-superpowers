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

# verdict <tool> <command-or-path> -> deny | warn | allow
verdict() {
  jq -n --arg t "$1" --arg c "$2" --arg cwd "$REPO" \
     '{tool_name:$t, cwd:$cwd,
       tool_input:(if $t=="Bash" or $t=="Shell" then {command:$c} else {file_path:$c} end)}' \
  | bash "$GUARD" 2>/dev/null \
  | jq -r 'if .hookSpecificOutput.permissionDecision=="deny" then "deny"
           elif .hookSpecificOutput.additionalContext then "warn"
           else "allow" end' 2>/dev/null
}
bash_verdict() { verdict Bash "$1"; }

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

judge "a target built by a variable"      warn "$(bash_verdict "OUT=.github/workflows/ci.yml; echo x > \$OUT")"
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

harness_summary
