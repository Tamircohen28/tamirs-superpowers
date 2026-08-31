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
       tool_input:(if $t=="Bash" then {command:$c} else {file_path:$c} end)}' \
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

harness_summary
