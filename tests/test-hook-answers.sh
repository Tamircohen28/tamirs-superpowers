#!/usr/bin/env bash
# Behaviour tests for scripts/check-hook-answers.sh, the local proxy for the plugin directory's
# HOOK_GRANTS_PERMISSION rule.
#
# WHAT IS BEING PROTECTED
#   The proxy is the only evidence the objective has before a release: the real scanner runs after one.
#   A proxy that under-reports lets a hold survive a release round; one that over-reports sends workers
#   rewriting code the scanner never objected to. So every rule gets a case that must fire AND a near-miss
#   that must not, comments get their own fixture (they are excluded), and the closure is tested through
#   each way a hook loads a file: source, $(dirname) source, python3 <path>, import, and a python argv.
#
# Hermetic: every fixture is a throwaway tree under harness_tmpdir; no hook is executed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/check-hook-answers.sh"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
harness_require python3

# hooks_json <dir> <command>... — a hooks.json whose PreToolUse runs each command under matcher Bash.
hooks_json() {
  local dir="$1"; shift
  mkdir -p "$dir/hooks"
  python3 -c '
import json, sys
groups = [{"matcher": "Bash", "hooks": [{"type": "command", "command": c}]} for c in sys.argv[2:]]
groups.append({"matcher": "Edit", "hooks": [{"type": "command", "command": sys.argv[2]}]})
json.dump({"hooks": {"PreToolUse": groups, "PostToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}\"/hooks/post.sh"}]}]}}, open(sys.argv[1], "w"))
' "$dir/hooks/hooks.json" "$@"
}

# run_check <args>... — sets OUT and RC.
run_check() { OUT="$(bash "$CHECK" "$@" 2>&1)"; RC=$?; }

# expect_finding <name> <"file:line rule"> / expect_none <name> <"file:line"> — against $OUT.
expect_finding() { judge "$1" yes "$(has "$OUT" "  $2")"; }
expect_none()    { judge "$1" no "$(has "$OUT" "  $2 ")"; }

H='bash "${CLAUDE_PLUGIN_ROOT}"/hooks/h.sh'

section "r1 — printf with a % conversion"
d="$(harness_tmpdir)"; hooks_json "$d" "$H"
cat > "$d/hooks/h.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$x"
printf 'plain text\n'
printf -v v '%d' 3
printf '100%%\n'
case $x in a) printf '%s' y ;; esac
echo "printf '%s' is only text here"
x=$(printf '%b' "$y")
EOF
run_check "$d"
judge "r1 fixture exits 1" 1 "$RC"
expect_finding "printf '%s' is r1" "hooks/h.sh:2 r1"
expect_none "a format with no conversion is not r1" "hooks/h.sh:3"
expect_finding "printf -v skips to the format" "hooks/h.sh:4 r1"
expect_none "%% alone is not a conversion" "hooks/h.sh:5"
expect_finding "printf after a case pattern is in command position" "hooks/h.sh:6 r1"
expect_none "printf inside a quoted string is not a command" "hooks/h.sh:7"
expect_finding "printf inside \$( ) is r1" "hooks/h.sh:8 r1"

section "r2 — backslash escapes"
d="$(harness_tmpdir)"; hooks_json "$d" "$H"
cat > "$d/hooks/h.sh" <<'EOF'
#!/usr/bin/env bash
echo 'it'\''s'
x="\x27"
y=$'\047'
echo "a\nb"
z="\u0027"
EOF
run_check "$d"
judge "r2 fixture exits 1" 1 "$RC"
expect_finding "the '\\'' idiom is r2" "hooks/h.sh:2 r2"
expect_finding "\\x27 is r2" "hooks/h.sh:3 r2"
expect_finding "\\047 is r2" "hooks/h.sh:4 r2"
expect_none "\\n is not r2" "hooks/h.sh:5"
expect_finding "\\u0027 is r2" "hooks/h.sh:6 r2"

section "r3 — allow / approve inside a quoted string"
d="$(harness_tmpdir)"; hooks_json "$d" "$H"
cat > "$d/hooks/h.sh" <<'EOF'
#!/usr/bin/env bash
echo '{"permissionDecision":"allow"}'
echo "please Approve this"
case $v in allow) : ;; esac
echo "$allow"
echo "allowed allowlist"
jq -n '{a: "allow"}'
cat <<TXT
you may allow it
TXT
python3 - <<'PY'
# allow, in a python comment
x = "allow"
PY
echo done
EOF
run_check "$d"
judge "r3 fixture exits 1" 1 "$RC"
expect_finding "single-quoted JSON is r3" "hooks/h.sh:2 r3"
expect_finding "double-quoted, any case, is r3" "hooks/h.sh:3 r3"
expect_none "an unquoted case pattern is not r3" "hooks/h.sh:4"
expect_none "a variable name is not string text" "hooks/h.sh:5"
expect_none "allowed / allowlist are not the whole word" "hooks/h.sh:6"
expect_finding "a quoted jq program is r3" "hooks/h.sh:7 r3"
expect_finding "a heredoc body is string text" "hooks/h.sh:9 r3"
expect_none "a python comment inside a PY heredoc is excluded" "hooks/h.sh:12"
expect_finding "a python string inside a PY heredoc is r3" "hooks/h.sh:13 r3"
expect_none "the heredoc ends at its delimiter" "hooks/h.sh:15"

section "r4 — stderr merged into stdout"
d="$(harness_tmpdir)"; hooks_json "$d" "$H"
cat > "$d/hooks/h.sh" <<'EOF'
#!/usr/bin/env bash
cmd 2>&1
cmd &>/dev/null
cmd |& tee f
echo hi >&2
echo "2>&1 is only text"
cmd 2>/dev/null
EOF
run_check "$d"
judge "r4 fixture exits 1" 1 "$RC"
expect_finding "2>&1 is r4" "hooks/h.sh:2 r4"
expect_finding "&> is r4" "hooks/h.sh:3 r4"
expect_finding "|& is r4" "hooks/h.sh:4 r4"
expect_none ">&2 is not r4" "hooks/h.sh:5"
expect_none "2>&1 inside a string is not r4" "hooks/h.sh:6"
expect_none "2>/dev/null is not r4" "hooks/h.sh:7"

section "python hook file"
d="$(harness_tmpdir)"; hooks_json "$d" 'python3 "${CLAUDE_PLUGIN_ROOT}/hooks/g.py"'
cat > "$d/hooks/g.py" <<'EOF'
"""Module docstring: allow is documented here."""
import subprocess
# allow, approve, 2>&1 in a comment
subprocess.run(["x"], stderr=subprocess.STDOUT)
VERDICT = "allow"
NOTE = "\x27"
EOF
run_check "$d"
judge "python fixture exits 1" 1 "$RC"
expect_finding "a docstring is r3, tagged" "hooks/g.py:1 r3 (docstring)"
expect_none "a python comment is excluded" "hooks/g.py:3"
expect_finding "stderr=subprocess.STDOUT is r4" "hooks/g.py:4 r4"
expect_finding "a python string literal is r3" "hooks/g.py:5 r3"
expect_finding "an escape in a python string is r2" "hooks/g.py:6 r2"

section "comments are excluded"
d="$(harness_tmpdir)"; hooks_json "$d" "$H"
cat > "$d/hooks/h.sh" <<'EOF'
#!/usr/bin/env bash
# printf '%s\n' x 2>&1 "allow" '\x27' it'\''s
echo ok  # trailing: printf '%s' 2>&1 'approve'
EOF
run_check "$d"
judge "violations only in comments exit 0" 0 "$RC"
judge "and report clean" yes "$(has "$OUT" "result: clean")"

section "a clean fixture"
d="$(harness_tmpdir)"; hooks_json "$d" "$H"
cat > "$d/hooks/h.sh" <<'EOF'
#!/usr/bin/env bash
input="$(cat)"
echo '{}'
echo "denied: $input" >&2
printf 'done\n'
exit 0
EOF
run_check "$d"
judge "clean fixture exits 0" 0 "$RC"
judge "clean fixture says clean" yes "$(has "$OUT" "result: clean")"

section "closure following"
d="$(harness_tmpdir)"; hooks_json "$d" "$H" 'python3 "${CLAUDE_PLUGIN_ROOT}/hooks/g.py"'
mkdir -p "$d/hooks/lib" "$d/scripts"
cat > "$d/hooks/h.sh" <<'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# source "${SCRIPT_DIR}/lib/unused.sh"
source "${SCRIPT_DIR}/lib/out.sh"
python3 "$SCRIPT_DIR/lib/t.py"
EOF
cat > "$d/hooks/lib/out.sh" <<'EOF'
#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/deep.sh"
emit() { printf '%s\n' "$1"; }
EOF
cat > "$d/hooks/lib/deep.sh" <<'EOF'
#!/usr/bin/env bash
probe() { command -v jq >/dev/null 2>&1; }
EOF
cat > "$d/hooks/lib/t.py" <<'EOF'
import os, subprocess, sys
import helper
ROOT = sys.argv[1]
RES = os.path.join(ROOT, "scripts", "res.sh")
OTHER = os.path.join(ROOT, "scripts", "other.sh")
subprocess.run(["bash", RES])
print(OTHER == sys.argv[2])
EOF
printf 'X = "approve"\n' > "$d/hooks/lib/helper.py"
printf '#!/usr/bin/env bash\necho "allow"\n' > "$d/scripts/res.sh"
printf '#!/usr/bin/env bash\necho "allow"\n' > "$d/scripts/other.sh"
printf '#!/usr/bin/env bash\nprintf "%%s" "allow"\n' > "$d/hooks/lib/unused.sh"
printf '#!/usr/bin/env bash\necho "allow"\n' > "$d/hooks/post.sh"
printf 'print("ok")\n' > "$d/hooks/g.py"
run_check "$d" -v
judge "closure fixture exits 1" 1 "$RC"
expect_finding "a sourced lib's line is reported under the hook" "hooks/lib/out.sh:3 r1"
expect_finding "a lib sourced by \$(dirname) is followed" "hooks/lib/deep.sh:2 r4"
expect_finding "an imported python module is followed" "hooks/lib/helper.py:1 r3"
expect_finding "a script in a python argv is followed" "scripts/res.sh:2 r3"
judge "a path the python only compares is not followed" no "$(has "$OUT" "scripts/other.sh")"
judge "a path named in a comment is not followed" no "$(has "$OUT" "hooks/lib/unused.sh")"
judge "PostToolUse hooks are not checked" no "$(has "$OUT" "hooks/post.sh")"
judge "-v prints the edge that loads a file" yes "$(has "$OUT" "hooks/lib/out.sh  <- hooks/h.sh:4 source")"
judge "-v names a python argv edge" yes "$(has "$OUT" "scripts/res.sh  <- hooks/lib/t.py:4 python-exec")"

section "--json"
run_check "$d" --json
judge "--json exits 1 on findings" 1 "$RC"
summary="$(printf '%s' "$OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
h = {x["hook"]: x for x in d["hooks"]}
sh = h["hooks/h.sh"]
print(len(d["hooks"]), ",".join(sh["matchers"]), sh["counts"]["r1"], sh["counts"]["r3"], sh["counts"]["r4"],
      "hooks/lib/helper.py" in sh["closure"], h["hooks/g.py"]["total"], d["clean"], d["comments_excluded"])
' 2>&1)"
judge "--json parses: hooks, deduped matchers, counts, closure, clean flag" "2 Bash,Edit 1 2 1 True 0 False True" "$summary"

section "--hook and --summary"
run_check "$d" --hook hooks/lib/deep.sh --summary
judge "--hook on one file reports its count" 1 "$RC"
judge "--summary prints only the table" no "$(has "$OUT" "closure (")"
judge "--summary row" yes "$(has "$OUT" "hooks/lib/deep.sh     0     0     0     1      1")"

section "CLI contract"
run_check -h
judge "-h exits 0" 0 "$RC"
judge "-h prints usage" yes "$(has "$OUT" "Usage:")"
run_check --nope
judge "an unknown flag exits 2" 2 "$RC"
d="$(harness_tmpdir)"
run_check "$d"
judge "a ROOT without hooks.json exits 2" 2 "$RC"
run_check "$d" --hook missing.sh
judge "--hook on a missing file exits 2" 2 "$RC"

harness_summary
