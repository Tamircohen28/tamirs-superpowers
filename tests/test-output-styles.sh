#!/usr/bin/env bash
# Tests for output-styles/*.md.
#
# WHY THE TWO FRONTMATTER ASSERTIONS ARE THE POINT
#   Both fields have defaults that quietly do the wrong thing for a plugin like this:
#
#   keep-coding-instructions defaults to FALSE, and the docs are explicit that a custom
#   style then "leave[s] out Claude Code's built-in software engineering instructions,
#   such as how to scope changes, write comments, and verify work". Shipping a dev
#   toolkit whose style silently strips the engineering instructions would be a serious
#   regression that no error reports — the session just gets worse.
#
#   force-for-plugin, if set true, "appl[ies] this style automatically whenever the
#   plugin is enabled ... Overrides the user's outputStyle setting". A plugin has no
#   business overriding a user's own choice of how Claude talks to them. It must stay
#   absent, and the test pins that rather than trusting nobody adds it later.
#
#   A misspelled field "is ignored without an error", so a typo in either one fails
#   silently too — which is the other reason these are assertions and not a comment.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/output-styles"
PASS=0; FAIL=0; FAILED=()
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); FAILED+=("$1"); echo "  FAIL $1 — $2"; }

[ -d "$DIR" ] || { echo "FATAL: $DIR missing"; exit 1; }
python3 -c "import yaml" 2>/dev/null || { echo "SKIP: pyyaml unavailable"; exit 0; }

shopt -s nullglob
styles=("$DIR"/*.md)
[ "${#styles[@]}" -gt 0 ] && ok "at least one output style ships" || bad "at least one output style ships" "none found"

for f in "${styles[@]}"; do
  n="$(basename "$f")"
  out="$(python3 - "$f" <<'PY'
import sys, yaml
t = open(sys.argv[1], encoding='utf-8').read()
if not t.startswith('---'):
    print("NOFM"); raise SystemExit
try:
    d = yaml.safe_load(t.split('---', 2)[1]) or {}
except Exception as e:
    print("BADYAML", e); raise SystemExit
body = t.split('---', 2)[2].strip()
print("OK",
      d.get('keep-coding-instructions'),
      'force-for-plugin' in d,
      bool(d.get('name')),
      bool(d.get('description')),
      len(body))
PY
)"
  set -- $out
  case "$1" in
    NOFM)    bad "$n has frontmatter" "no --- block"; continue ;;
    BADYAML) bad "$n frontmatter parses" "${*:2}"; continue ;;
  esac
  ok "$n frontmatter parses"
  [ "$2" = "True" ] && ok "$n keeps coding instructions" \
    || bad "$n keeps coding instructions" "keep-coding-instructions is '$2'; default false strips Claude Code's engineering instructions"
  [ "$3" = "False" ] && ok "$n does not force itself on users" \
    || bad "$n does not force itself on users" "force-for-plugin overrides the user's own outputStyle"
  [ "$4" = "True" ] && ok "$n declares a name" || bad "$n declares a name" "missing"
  [ "$5" = "True" ] && ok "$n declares a description" || bad "$n declares a description" "missing (shown in the /config picker)"
  [ "${6:-0}" -gt 200 ] && ok "$n has substantive instructions" || bad "$n has substantive instructions" "body is ${6:-0} chars"
done

echo "--- the manifest does not need to declare it (default discovery) ---"
if [ -d "$ROOT/output-styles" ]; then
  ok "styles live at the default output-styles/ path"
else
  bad "styles live at the default output-styles/ path" "not found"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -gt 0 ] && { printf 'failing:'; printf ' %s' "${FAILED[@]}"; echo; exit 1; }
exit 0
