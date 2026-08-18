#!/usr/bin/env bash
# test-static.sh — static repository tests (REFACTOR-SPEC §22.1).
#
# THE FILE SET
#   `git ls-files --cached --others --exclude-standard` — tracked files PLUS
#   untracked files that are not ignored. Tracked-only would miss a file added in
#   this very change; everything-on-disk would sweep in .dev-files/, node_modules
#   and session scratch. The gitignore is the repo's own statement of what it
#   ships, so it is the right filter.
#
# DELEGATION, NOT DUPLICATION
#   Version drift, generated-adapter drift and count drift already have dedicated
#   scripts with better error messages than a grep could produce. This suite runs
#   THOSE and reports their exit codes. Reimplementing them here would double the
#   maintenance and halve the accuracy.
#
# Usage: bash tests/test-static.sh [--strict]
#   --strict also fails on the checks that are advisory by default (link rot in
#   docs the refactor is still rewriting).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require git jq

STRICT=false
[ "${1:-}" = "--strict" ] && STRICT=true

cd "$REPO_ROOT" || exit 1

TMP="$(harness_tmpdir)"
FILES="$TMP/files.txt"
FILES0="$TMP/files.z"
git ls-files --cached --others --exclude-standard > "$FILES"
git ls-files -z --cached --others --exclude-standard > "$FILES0"

# scan <extended-regex> [file-list] — grep a NUL-separated file list, NUL-safe (a
# path with a space must not split into two nonexistent paths) and ARG_MAX-safe.
#
# It goes through portable_xargs0 for a reason worth recording: this was first
# written as `xargs -0 -a "$FILES0"`, which is GNU-only. On macOS BSD xargs
# rejected `-a`, the trailing `|| true` swallowed the error, and the secret /
# maintainer-path / employer-reference scanners all reported clean against a repo
# they had never actually read. That is why the self-test section below exists.
scan() { portable_xargs0 "${2:-$FILES0}" grep -nIE "$1" 2>/dev/null || true; }

# Files whose PURPOSE is to name a forbidden pattern: this scanner, the shim it
# documents, and the repo's own employer-IP guards. Naming them explicitly (rather
# than exempting by regex) keeps the exemption visible in review — a silent
# pattern-based carve-out is how a real leak eventually slips through.
SELF_REFERENTIAL='^(tests/test-static\.sh|tests/lib/portable\.sh|hooks/wix-ip-guard\.sh|\.claude/skills/run-tamirs-superpowers/smoke\.sh|scripts/check-doc-claims\.sh):'

# strip_noise — remove comment-only hits and self-referential files from a
# `file:line:content` stream. A rule stated in a comment is documentation, not a
# violation, and flagging it trains people to ignore the check.
strip_noise() {
  grep -vE "$SELF_REFERENTIAL" \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
    || true
}
scan_i() { portable_xargs0 "${2:-$FILES0}" grep -nIiE "$1" 2>/dev/null || true; }

# The scanner patterns live here, not inline at each use, so the self-test below
# exercises the SAME regex the real check uses. A positive control against a
# different pattern proves nothing.
SECRET_RE='(ghp_|github_pat_|gho_|ghs_)[A-Za-z0-9_]{16,}|sk-[A-Za-z0-9]{32,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
HOMEPATH_RE='/(Users|home)/[A-Za-z0-9._-]+'
EMPLOYER_RE='\b(wix\.com|wixpress|\.wixprod|gas[ -]?town|gas[ -]?city|cmux)\b'
PLACEHOLDERS='/Users/(you|username|your-name|<you>|\$USER|\$\{USER\})'

judge "the shipped file set is non-empty" yes \
  "$(if [ -s "$FILES" ]; then echo yes; else echo no; fi)"
# ---------------------------------------------------------------------------
section "harness self-test (a scanner that cannot fail proves nothing)"

# POSITIVE CONTROLS. Each scanner below reports "clean" against a clean repo — and
# reported exactly the same thing while it was silently broken by a GNU-only
# `xargs -a` that BSD xargs rejected and a trailing `|| true` swallowed. So every
# scanner is first run against a file KNOWN to be dirty. If it does not fire
# there, its clean verdict on the real tree means nothing.
CTRL="$(harness_tmpdir)"
printf 'token = ghp_%s\n' "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" > "$CTRL/secret.txt"
printf 'path = /Users/somerealname/src/thing\n'             > "$CTRL/homepath.txt"
printf 'see the gas town runbook\n'                         > "$CTRL/employer.txt"
CTRL0="$CTRL/list.z"
printf '%s\0%s\0%s\0' "$CTRL/secret.txt" "$CTRL/homepath.txt" "$CTRL/employer.txt" > "$CTRL0"

judge "the secret scanner fires on a planted token"       1 "$(scan   "$SECRET_RE"   "$CTRL0" | grep -c .)"
judge "the home-path scanner fires on a planted path"     1 "$(scan   "$HOMEPATH_RE" "$CTRL0" | grep -c .)"
judge "the employer scanner fires on a planted reference" 1 "$(scan_i "$EMPLOYER_RE" "$CTRL0" | grep -c .)"
judge "a real home directory survives the placeholder filter" yes \
  "$(if scan "$HOMEPATH_RE" "$CTRL0" | grep -qvE "$PLACEHOLDERS"; then echo yes; else echo no; fi)"

# portable_xargs0 is the shim all three depend on. The bug it replaced was a total
# no-op, so assert it reads the list at all.
judge "portable_xargs0 reads a NUL-separated list" 3 \
  "$(portable_xargs0 "$CTRL0" printf '%s\n' | grep -c .)"

# The watchdog is hand-rolled on this machine — neither timeout nor gtimeout is
# installed — so it is tested rather than trusted.
judge "portable_timeout names its implementation" yes \
  "$(impl="$(portable_timeout_impl)"
     if [ "$impl" = timeout ] || [ "$impl" = gtimeout ] || [ "$impl" = bash-watchdog ]; then
       echo yes; else echo "no ($impl)"; fi)"
judge "portable_timeout passes a fast command's success through" 0 \
  "$(portable_timeout 5 true >/dev/null 2>&1; echo $?)"
judge "portable_timeout passes a fast command's failure through" 3 \
  "$(portable_timeout 5 sh -c 'exit 3' >/dev/null 2>&1; echo $?)"
judge "portable_timeout kills an overrunning command, returning 124" 124 \
  "$(portable_timeout 1 sleep 30 >/dev/null 2>&1; echo $?)"
watchdog_start="$(date +%s)"
portable_timeout 1 sleep 30 >/dev/null 2>&1 || true
watchdog_elapsed=$(( $(date +%s) - watchdog_start ))
judge "and it does so promptly (<=5s for a 1s budget)" yes \
  "$(if [ "$watchdog_elapsed" -le 5 ]; then echo yes; else echo "no (${watchdog_elapsed}s)"; fi)"


# files_matching <suffix-glob>
files_matching() { grep -E "$1" "$FILES" || true; }

# ---------------------------------------------------------------------------
section "JSON parses"

bad_json=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  jq empty "$f" >/dev/null 2>&1 || bad_json="$bad_json $f"
done < <(files_matching '\.json$')
judge "every shipped .json parses" "" "$bad_json"

# ---------------------------------------------------------------------------
section "YAML / frontmatter parses"

if python3 -c "import yaml" >/dev/null 2>&1; then
  bad_yaml=""
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$f" >/dev/null 2>&1 \
      || bad_yaml="$bad_yaml $f"
  done < <(files_matching '\.(ya?ml)$')
  judge "every shipped .yaml/.yml parses" "" "$bad_yaml"

  fm_rc=0
  python3 scripts/validate-skill-frontmatter.py --json >"$TMP/fm.json" 2>/dev/null || fm_rc=$?
  judge "SKILL.md frontmatter parses for every skill" 0 \
    "$(jq -r '[.results[] | select(.errors | any(test("frontmatter|YAML")))] | length' "$TMP/fm.json" 2>/dev/null || echo parse-error)"
else
  skip "YAML parse checks" "PyYAML not installed"
fi

# ---------------------------------------------------------------------------
section "shellcheck"

if harness_have shellcheck; then
  sc_fail=""
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    shellcheck -S warning --exclude SC2034 "$f" >"$TMP/sc.out" 2>&1 || {
      sc_fail="$sc_fail $f"
      sed 's/^/       /' "$TMP/sc.out" | head -8
    }
  done < <(files_matching '\.sh$')
  judge "every shipped .sh is shellcheck-clean at -S warning" "" "$sc_fail"
else
  skip "shellcheck" "shellcheck not installed (brew install shellcheck)"
fi

# ---------------------------------------------------------------------------
section "executable bits"

# The repo's actual convention — verified against what is already committed — is
# that hooks and scripts are invoked as `bash <path>` (hooks.json and the Makefile
# both do), so their mode bit is not load-bearing and asserting on it would just
# codify an accident. Two rules ARE load-bearing:
#   1. a test entrypoint is run directly by a human and by CI;
#   2. a SOURCED library must not be executable, because +x on a library is the
#      signal that someone will eventually run it standalone and get set -e
#      semantics it was never written for.
nonexec=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  [ -x "$f" ] || nonexec="$nonexec $f"
done < <(files_matching '^tests/test-[^/]*\.sh$')
judge "every tests/test-*.sh entrypoint is executable" "" "$nonexec"

sourced_x=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  [ -x "$f" ] && sourced_x="$sourced_x $f"
done < <(files_matching '^(hooks|tests)/(lib|orchestration|contract|docs)/.*\.sh$' | grep -v '/run\.sh$')
# Advisory: this is a convention this suite introduces, and pre-existing files
# predate it. Failing the build on a rule invented after the fact is how a suite
# earns a blanket --no-verify.
if [ -z "$sourced_x" ]; then
  ok "no sourced library carries the executable bit"
else
  warn "sourced libraries carrying +x (advisory):$sourced_x"
fi

# The converse: a markdown or json file with +x is an accident.
stray=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  [ -x "$f" ] && stray="$stray $f"
done < <(files_matching '\.(md|json|ya?ml|mdc|toml)$')
judge "no documentation or config file is marked executable" "" "$stray"

# ---------------------------------------------------------------------------
section "no absolute maintainer paths"

# /Users/you and friends are documentation placeholders and must stay. A real
# home directory is a leak of the maintainer's machine into a shipped file.
leaks=""
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  printf '%s' "$hit" | grep -qE "$PLACEHOLDERS" && continue
  leaks="$leaks
    $hit"
done < <(scan "$HOMEPATH_RE" | strip_noise | grep -vE "$PLACEHOLDERS" | grep -vE '^tests/' || true)
judge "no shipped file hardcodes a real home directory" "" "$leaks"

# ---------------------------------------------------------------------------
section "no secrets"

# Shapes, not entropy heuristics: a token-shaped literal is the thing that must
# never be committed, and .mcp.json is required to use ${ENV_VAR} placeholders.
secret_hits=""
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  secret_hits="$secret_hits
    $hit"
done < <(scan "$SECRET_RE" | strip_noise | grep -vE '^tests/' || true)
judge "no token-shaped literal is committed" "" "$secret_hits"

if [ -f .mcp.json ]; then
  literal="$(jq -r '.. | strings | select(test("^(ghp_|sk-|AKIA)"))' .mcp.json 2>/dev/null || true)"
  judge ".mcp.json carries no literal credential" "" "$literal"
  judge ".mcp.json uses \${ENV_VAR} placeholders" yes \
    "$(has "$(cat .mcp.json)" '${')"
fi

# ---------------------------------------------------------------------------
section "no employer / internal references"

# Enumerated in the repo's own hard constraints. Matched case-insensitively and
# word-bounded so 'wixel' or a URL fragment does not produce noise.
emp=""
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  emp="$emp
    $hit"
done < <(scan_i "$EMPLOYER_RE" | strip_noise | grep -vE '^(tests/|session-files/)' || true)
judge "no employer-internal or foreign-orchestrator reference is shipped" "" "$emp"

# ---------------------------------------------------------------------------
section "broken internal links"

broken=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  dir="$(dirname "$f")"
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    case "$target" in
      http://*|https://*|mailto:*|'#'*) continue ;;
      '...'|URL|PATH|'<'*) continue ;;   # documented placeholders, not links
      *'`'*|*'…'*) continue ;;        # prose with backticks/ellipsis inside the parens,
                                           # not a link target — the naive ](...) grab misreads it
    esac
    t="${target%%#*}"
    [ -n "$t" ] || continue
    case "$t" in
      /*) resolved="$REPO_ROOT$t" ;;
      *)  resolved="$dir/$t" ;;
    esac
    [ -e "$resolved" ] || broken="$broken
    $f -> $target"
  done < <(grep -oE '\]\([^)]+\)' "$f" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//')
  # Templates and gold fixtures describe files that will exist in a SCAFFOLDED
  # repo, not in this one; resolving their links here asserts the wrong thing.
done < <(files_matching '\.md$' \
          | grep -vE '^(docs/engineering/refactor/|CHANGELOG\.md)' \
          | grep -vE '_contract/(templates|fixtures)/')
if [ -z "$broken" ]; then
  ok "every internal markdown link resolves"
elif [ "$STRICT" = true ]; then
  bad "every internal markdown link resolves" "$broken"
else
  warn "internal link rot (advisory until the docs rewrite lands):$broken"
fi

# ---------------------------------------------------------------------------
section "no GNU-only invocations in shipped shell"

# rules/dev/user-facing-script-standards.md §3: macOS and Linux are both
# first-class. A GNU-only spelling is green in CI and broken on the maintainer's
# machine — worse than an outright break, because nothing goes red to warn you.
#
# THE FALLBACK IDIOM IS CORRECT AND MUST NOT BE FLAGGED.
#   stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null
# is the right way to write this: BSD spelling first, GNU spelling as fallback.
# A naive grep for `stat -c` flags that line and trains people to ignore the
# check. So each pattern carries a COUNTERPART: if the counterpart appears within
# a few lines of the hit, the call is guarded and the hit is dropped. A pattern
# with an empty counterpart is never exonerated — there is no portable spelling.
#
# Format: <gnu-regex>~~<counterpart-regex, may be empty>~~<human label>
# The separator is `~~`, not `|`: two patterns contain `|` inside an ERE
# alternation, and splitting on `|` silently truncated them so they matched
# nothing. That is precisely the failure the self-test below now guards against.
GNUISM_TABLE='xargs[[:space:]]+(-[0-9A-Za-z]+[[:space:]]+)*-a[[:space:]]~~~~xargs -a (GNU-only; redirect stdin)
readlink[[:space:]]+-f~~~~readlink -f (GNU-only; use portable_realpath)
grep[[:space:]]+-[A-Za-z]*P[[:space:]]~~~~grep -P (GNU-only; use grep -E)
mktemp[[:space:]]+-p[[:space:]]~~~~mktemp -p (GNU-only)
stat[[:space:]]+-c[[:space:]]~~stat[[:space:]]+-f~~stat -c (GNU-only; pair with stat -f)
date[[:space:]]+-d[[:space:]]~~date[[:space:]]+-v~~date -d (GNU-only; pair with date -v)
date[[:space:]]+--iso-8601~~date[[:space:]]+-v~~date --iso-8601 (GNU-only)
[^a-z-]sha256sum~~shasum~~sha256sum (GNU-only; pair with shasum -a 256)
[^_a-zA-Z-]mapfile[[:space:]]~~BASH_VERSINFO~~mapfile (bash 4+; macOS ships 3.2)
[^_a-zA-Z-]readarray[[:space:]]~~BASH_VERSINFO~~readarray (bash 4+; macOS ships 3.2)
declare[[:space:]]+-A[[:space:]]~~BASH_VERSINFO~~declare -A (bash 4+; macOS ships 3.2)
[$][{][A-Za-z_][A-Za-z0-9_]*(\^\^|,,)[}]~~BASH_VERSINFO~~parameter-case expansion ${var^^} / ${var,,} (bash 4+; macOS ships 3.2)
sed[[:space:]]+-i[[:space:]]+-~~sed[[:space:]]+-i[[:space:]]*([.][Bb]ak|.{2})~~bare sed -i (GNU-only; use sed -i.bak or a BSD-first fallback)'

# guarded <file> <line> <counterpart-regex> — does the portable counterpart appear
# within 8 lines of the hit? That window covers a `||` fallback written across a
# backslash-continued multi-line command, which is how these are usually spelled.
guarded() {
  local f="$1" ln="$2" cp="$3" lo hi
  [ -n "$cp" ] || return 1
  lo=$(( ln > 8 ? ln - 8 : 1 )); hi=$(( ln + 8 ))
  sed -n "${lo},${hi}p" "$f" 2>/dev/null | grep -qE "$cp"
}

gnuisms=""
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  re="${entry%%~~*}"
  rest="${entry#*~~}"
  cp="${rest%%~~*}"
  label="${rest#*~~}"
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    f="${hit%%:*}"; rest2="${hit#*:}"; ln="${rest2%%:*}"
    case "$ln" in ''|*[!0-9]*) continue ;; esac
    guarded "$f" "$ln" "$cp" && continue
    gnuisms="$gnuisms
    $f:$ln   <- $label"
  done < <(scan "$re" | strip_noise | grep -E '\.sh:' || true)
done <<EOF
$GNUISM_TABLE
EOF
judge "no shipped .sh uses an unguarded GNU-only spelling" "" "$gnuisms"

# `timeout` is absent from the development machine entirely (no coreutils), so an
# unguarded call is a hard break there even though ubuntu-latest has it. A call
# guarded by `command -v`, or routed through the tests/ shim, is fine.
unguarded=""
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  f="${hit%%:*}"
  grep -q 'command -v timeout\|command -v gtimeout\|portable_timeout' "$f" 2>/dev/null && continue
  unguarded="$unguarded
    $hit"
done < <(scan '(^|[^_[:alnum:]-])g?timeout[[:space:]]+[0-9]' | strip_noise | grep -E '\.sh:' || true)
judge "no shipped .sh calls timeout/gtimeout without a guard or fallback" "" "$unguarded"
# The GNU-ism detector gets the same treatment, and needs it: its pattern table
# was first written with `|` as the field separator, which silently truncated the
# two patterns that contain `|` inside an ERE alternation. It reported a clean
# repo while matching nothing at all. These controls plant one guarded and one
# unguarded call of each shape and assert the detector tells them apart.
GCTRL="$CTRL/gnu"
mkdir -p "$GCTRL"
cat > "$GCTRL/dirty.sh" <<'DIRTY'
#!/usr/bin/env bash
name="${var^^}"
mtime="$(stat -c %Y "$f")"
cutoff="$(date -d '90 days ago' +%s)"
sum="$(sha256sum "$f")"
DIRTY
cat > "$GCTRL/clean.sh" <<'CLEAN'
#!/usr/bin/env bash
mtime="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
if date -v-90d +%s >/dev/null 2>&1; then cutoff="$(date -v-90d +%s)"; else cutoff="$(date -d '90 days ago' +%s)"; fi
sum="$(shasum -a 256 "$f" 2>/dev/null || sha256sum "$f")"
CLEAN
GCTRL0="$GCTRL/list.z"
printf '%s\0%s\0' "$GCTRL/dirty.sh" "$GCTRL/clean.sh" > "$GCTRL0"

# Reuse the real table and the real `guarded` helper — a control that reimplements
# the logic it is controlling is worthless.
ctrl_dirty=""; ctrl_clean=""
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  re="${entry%%~~*}"; rest="${entry#*~~}"; cp="${rest%%~~*}"
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    f="${hit%%:*}"; rest2="${hit#*:}"; ln="${rest2%%:*}"
    case "$ln" in ''|*[!0-9]*) continue ;; esac
    guarded "$f" "$ln" "$cp" && continue
    case "$f" in *dirty.sh) ctrl_dirty="$ctrl_dirty $ln" ;; *clean.sh) ctrl_clean="$ctrl_clean $ln" ;; esac
  done < <(scan "$re" "$GCTRL0" | grep -E '\.sh:' || true)
done <<EOF
$GNUISM_TABLE
EOF
judge "the GNU-ism detector flags all four unguarded calls" 4 "$(set -- $ctrl_dirty; echo $#)"
judge "and exonerates every BSD-first fallback" "" "$ctrl_clean"
# Stdin must never block (rules/dev/user-facing-script-standards.md §4). The
# failure is not merely a hang: hooks/lib/hook-output.sh fail-closes on empty
# PreToolUse stdout on Cursor, so a hook killed by its hooks.json timeout DENIES
# the user's tool call for a reason unrelated to what it guards. A guard whose
# answer would have been ALLOW turns into a block.
#
# TWO MATCHING RULES, both learned from misses in the first version of this check:
#   1. The QUOTED form counts. `input="$(cat)"` is the spelling 14 of this repo's
#      19 stdin-reading hooks actually used; a regex anchored on `=\$\(` saw none
#      of them and under-reported the population by three quarters.
#   2. Comments do not count. A header comment describing the defect is
#      documentation; flagging it is how a check earns a blanket ignore.
STDIN_CAT_RE='=[[:space:]]*"?\$\([[:space:]]*cat[[:space:]]*\)"?'
STDIN_GUARD_RE='read[[:space:]]+(-r[[:space:]]+)?-t|-t[[:space:]]+0|command -v timeout|portable_timeout|hook_read_stdin'

# stdin_unbounded <file> — 0 when the file reads stdin with no bound. Comments are
# stripped first. (`sed 's/#.*$//'` also blanks a `#` inside a string literal; that
# can only cause an under-report, never a false accusation, which is the right way
# for this to be wrong.)
stdin_unbounded() {
  sed 's/[[:space:]]*#.*$//' "$1" 2>/dev/null | grep -qE "$STDIN_CAT_RE" || return 1
  grep -qE "$STDIN_GUARD_RE" "$1" 2>/dev/null && return 1
  return 0
}

blocking=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  stdin_unbounded "$f" && blocking="$blocking $f"
done < <(files_matching '\.sh$')

# Positive control. Every hook in the tree has since been fixed, so the real scan
# is expected to be clean — which is exactly the state in which a broken detector
# is indistinguishable from a healthy repo. These four fixtures pin both matching
# rules and both guard forms.
SCTRL="$CTRL/stdin"
mkdir -p "$SCTRL"
printf '#!/usr/bin/env bash\ninput=$(cat)\n'                                    > "$SCTRL/bare.sh"
printf '#!/usr/bin/env bash\ninput="$(cat)"\n'                                  > "$SCTRL/quoted.sh"
printf '#!/usr/bin/env bash\n# reads stdin with input="$(cat)" — prose only\nx=1\n' > "$SCTRL/comment.sh"
printf '#!/usr/bin/env bash\ninput="$(cat)"\nwhile read -r -t 2 l; do :; done\n' > "$SCTRL/guarded.sh"

judge "the stdin detector catches the bare form"        yes "$(stdin_unbounded "$SCTRL/bare.sh"    && echo yes || echo no)"
judge "the stdin detector catches the QUOTED form"      yes "$(stdin_unbounded "$SCTRL/quoted.sh"  && echo yes || echo no)"
judge "the stdin detector ignores a comment describing it" no "$(stdin_unbounded "$SCTRL/comment.sh" && echo yes || echo no)"
judge "the stdin detector exonerates a bounded read"    no  "$(stdin_unbounded "$SCTRL/guarded.sh" && echo yes || echo no)"
# ---------------------------------------------------------------------------
# Placeholder composed from a possibly-empty substring.
#
# The shape behind two real bugs in this repo, suggested as a check by
# hooks-audit after the second one:
#
#     short_id="${session_id:0:8}"      # empty when there is no session id
#     task_slug="session-${short_id}"   # -> "session-", a real branch name
#
# A default that is correct for one caller shape and INVENTS information for
# another. `is_git_repo ""` falling through `${1:-.}` to `.` is the same mistake.
#
# SCOPE, stated honestly — this is a cheap grep, not dataflow analysis:
#   - Only identifier-sized substrings (N<=16) count. `${url:0:120}` is display
#     truncation, benign, and was 10 of the 13 hits before this bound was added.
#   - A guard on either the derived or the source variable ANYWHERE in the file
#     exonerates every use in that file. So it under-reports: it catches "never
#     guarded at all" (which is what both real bugs looked like) and will miss a
#     second unguarded use in a file that guards elsewhere.
#   - A hit is not automatically a bug. A composition with another
#     provably-non-empty component (`"${date_stamp}_${cwd_slug}_${short_id}"`)
#     still identifies something. Hence advisory, not a gate.
placeholders=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    ln="${hit%%:*}"
    lhs="$(printf '%s' "$hit" | sed -nE 's/^[0-9]+:[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p')"
    src="$(printf '%s' "$hit" | sed -nE 's/.*\$\{([A-Za-z_][A-Za-z0-9_]*):0:[0-9]+\}.*/\1/p')"
    guarded=no
    for v in "$lhs" "$src"; do
      [ -n "$v" ] || continue
      grep -qE "[-][nz][[:space:]]+\"?\\\$\{?$v" "$f" 2>/dev/null && guarded=yes
    done
    [ "$guarded" = yes ] && continue
    placeholders="$placeholders
    $f:$ln  ($lhs from $src)"
  done < <(sed 's/[[:space:]]*#.*$//' "$f" 2>/dev/null \
           | grep -nE '^[^=]*[A-Za-z_][A-Za-z0-9_]*=[^=]*\$\{[A-Za-z_][A-Za-z0-9_]*:0:([0-9]|1[0-6])\}' || true)
done < <(files_matching '\.sh$')

# Positive control: both real bugs are fixed, so the tree is expected to be
# near-clean — the state in which a broken detector looks identical to a healthy
# repo. Fixture 1 is the original bug verbatim; fixture 2 is the same line with
# the guard that fixed it; fixture 3 is display truncation, which must not fire.
PCTRL="$CTRL/placeholder"
mkdir -p "$PCTRL"
printf '#!/usr/bin/env bash\nshort_id="${session_id:0:8}"\ntask_slug="session-${short_id}"\n' > "$PCTRL/bug.sh"
printf '#!/usr/bin/env bash\nshort_id="${session_id:0:8}"\nif [[ -z "$short_id" ]]; then exit 0; fi\ntask_slug="session-${short_id}"\n' > "$PCTRL/fixed.sh"
printf '#!/usr/bin/env bash\nmsg="truncated: ${url:0:120}"\n' > "$PCTRL/display.sh"

ph_hits() {
  sed 's/[[:space:]]*#.*$//' "$1" | grep -qE '^[^=]*[A-Za-z_][A-Za-z0-9_]*=[^=]*\$\{[A-Za-z_][A-Za-z0-9_]*:0:([0-9]|1[0-6])\}' || return 1
  grep -qE '[-][nz][[:space:]]+"?\$\{?(short_id|session_id)' "$1" && return 1
  return 0
}
judge "the placeholder detector catches the original bug shape" yes "$(ph_hits "$PCTRL/bug.sh"     && echo yes || echo no)"
judge "the placeholder detector exonerates the guarded form"    no  "$(ph_hits "$PCTRL/fixed.sh"   && echo yes || echo no)"
judge "the placeholder detector ignores display truncation"     no  "$(ph_hits "$PCTRL/display.sh" && echo yes || echo no)"

if [ -z "$placeholders" ]; then
  ok "no identifier is composed from an unguarded possibly-empty substring"
elif [ "$STRICT" = true ]; then
  bad "no identifier is composed from an unguarded possibly-empty substring" "$placeholders"
else
  warn "identifier composed from an unguarded possibly-empty substring (advisory — a non-empty sibling component may make it benign):$placeholders"
fi


if [ -z "$blocking" ]; then
  ok "no shipped .sh reads stdin with an unbounded \$(cat)"
elif [ "$STRICT" = true ]; then
  bad "no shipped .sh reads stdin with an unbounded \$(cat)" "$blocking"
else
  warn "unbounded \$(cat) stdin reads (advisory — each needs a caller-context check):$blocking"
fi



# ---------------------------------------------------------------------------
section "generated-file drift"

run_script() {  # run_script <label> <interpreter> <script> [args...]
  local label="$1"; shift
  local target="$2"
  if [ ! -f "$target" ]; then skip "$label" "$target not present"; return; fi
  local rc=0 out
  out="$(portable_timeout "${CHECK_SCRIPT_TIMEOUT:-180}" "$@" 2>&1)" || rc=$?
  if [ "$rc" -eq 124 ]; then
    bad "$label" "timed out (watchdog: $(portable_timeout_impl))"
    return
  fi
  if [ "$rc" -eq 0 ]; then ok "$label"; else
    printf '%s\n' "$out" | sed 's/^/       /' | head -15
    bad "$label" "exit $rc"
  fi
}

run_script "generated opencode agents are in sync" bash scripts/build-opencode-agents.sh . --check
run_script "no agent adapter drift"                bash scripts/check-agent-drift.sh .
run_script "capability registry is well-formed"    bash scripts/check-capability-registry.sh .
run_script "marketplace schema is a record"        bash scripts/check-marketplace-schema.sh .

# ---------------------------------------------------------------------------
section "version drift"

run_script "plugin manifests agree on version" \
  bash skills/repo/_contract/scripts/check-manifest-version-alignment.sh . --manifests-only

# ---------------------------------------------------------------------------
section "skill / agent count drift"

run_script "documented skill and target counts match the filesystem" \
  bash scripts/check-doc-claims.sh .

# Agent count drift: every canonical role/agent must have its adapters.
agents_n="$(find agents -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
opencode_n="$(find .opencode/agent -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
judge "every agents/*.md has an .opencode/agent/*.md adapter" "$agents_n" "$opencode_n"

harness_summary
