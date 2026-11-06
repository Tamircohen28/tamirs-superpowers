#!/usr/bin/env bash
# test-doc-standards.sh — every violation kind check-doc-standards.sh reports, with its control.
#
# WHY EVERY NEGATIVE HAS A POSITIVE CONTROL
#   A checker that never fires and one that always passes are the same green
#   dot. Each kind below is asserted on a fixture that HAS the defect (the check
#   must fire, at the right line), then after --fix (the check must go quiet),
#   or — for the kinds --fix never touches — must keep firing. Fixtures are
#   built in a temp dir from literal text; the live repo is read only by the
#   last section, which asserts the shipped docs are clean.
#
# Usage: bash tests/test-doc-standards.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require jq git awk
CHECK="$REPO_ROOT/scripts/check-doc-standards.sh"
INIT="$(head -n 1 "$REPO_ROOT/config/docs/mermaid-init.txt")"
TMP="$(harness_tmpdir)"

QURL="https://example.test/owner"
IURL="https://example.test/owner/repo/issues/new/choose"
FOOTER="<p align=\"center\"><a href=\"$QURL\">Have a Question?</a>&nbsp;·&nbsp;<a href=\"$IURL\">Open an Issue</a></p>"

# new_root <name> [question_url|null] [issue_url|null] — a fixture root carrying the config and init file.
new_root() {
  local d="$TMP/$1" q="${2:-$QURL}" i="${3:-$IURL}"
  mkdir -p "$d/config/docs" "$d/docs/user" "$d/docs/agent-guidelines" "$d/notes"
  cp "$REPO_ROOT/config/docs/mermaid-init.txt" "$d/config/docs/"
  [[ "$q" == null ]] || q="\"$q\""
  [[ "$i" == null ]] || i="\"$i\""
  cat > "$d/config/docs/doc-standards.json" <<EOF
{
  "human_facing": {"include": ["README.md", "docs/**/*.md"], "exclude": ["docs/agent-guidelines/**", "docs/CHANGELOG.md"]},
  "footer": {"question_text": "Have a Question?", "question_url": $q, "issue_text": "Open an Issue", "issue_url": $i},
  "mermaid": {"init_file": "mermaid-init.txt"}
}
EOF
  printf '%s\n' "$d"
}

run()   { bash "$CHECK" "$@" 2>/dev/null; }
# kinds <args...> — the distinct violation kinds, space-separated, sorted.
kinds() { run "$@" | awk '{print $2}' | sed 's/:$//' | sort -u | tr '\n' ' ' | sed 's/ $//'; }
# lines_of <kind> <args...> — the path:line of every violation of that kind.
lines_of() { local k="$1"; shift; run "$@" | awk -v k="$k:" '$2 == k {print $1}' | tr '\n' ' ' | sed 's/ $//'; }
last_nonblank() { awk 'NF {l=$0} END {print l}' "$1"; }

# ---------------------------------------------------------------------------
section "a clean doc passes and prints nothing"
R="$(new_root clean)"
printf '# Title\n\nBody.\n\n---\n\n%s\n' "$FOOTER" > "$R/docs/user/a.md"
out="$(run "$R")"; rc=$?
judge "clean root exits 0" 0 "$rc"
judge "clean root prints no violation" "" "$out"

# ---------------------------------------------------------------------------
section "footer-missing fires at the last line and --fix appends the footer"
R="$(new_root footer-missing)"
printf '# Title\n\nBody.\n' > "$R/docs/user/b.md"
judge "kind" "footer-missing" "$(kinds "$R")"
judge "reported at the file's last line" "docs/user/b.md:3" "$(lines_of footer-missing "$R")"
run "$R" >/dev/null; judge "exit 1 on a violation" 1 "$?"
run --fix "$R" >/dev/null; judge "--fix exits 0 once repaired" 0 "$?"
judge "footer is the last non-blank line" "$FOOTER" "$(last_nonblank "$R/docs/user/b.md")"
judge "a --- rule precedes it" "---" "$(awk 'NF {p=l; l=$0} END {print p}' "$R/docs/user/b.md")"
judge "body untouched" "Body." "$(sed -n '3p' "$R/docs/user/b.md")"
judge "clean after fix" "" "$(kinds "$R")"

# ---------------------------------------------------------------------------
section "footer-wrong: foreign links, and a footer with no rule above it"
R="$(new_root footer-wrong)"
printf '# T\n\nBody.\n\n---\n\n<p align="center"><a href="https://other.test">Ask</a>&nbsp;·&nbsp;<a href="https://other.test/issues">Issue</a></p>\n' > "$R/docs/user/links.md"
printf '# T\n\nBody.\n\n%s\n' "$FOOTER" > "$R/docs/user/norule.md"
judge "kind" "footer-wrong" "$(kinds "$R")"
judge "both files reported" "docs/user/links.md:7 docs/user/norule.md:5" "$(lines_of footer-wrong "$R")"
run --fix "$R" >/dev/null; judge "--fix exits 0" 0 "$?"
judge "foreign footer replaced" "$FOOTER" "$(last_nonblank "$R/docs/user/links.md")"
judge "old footer gone" 0 "$(grep -c 'other.test' "$R/docs/user/links.md")"
judge "rule inserted exactly once" 1 "$(grep -c '^---$' "$R/docs/user/norule.md")"
judge "clean after fix" "" "$(kinds "$R")"

# ---------------------------------------------------------------------------
section "README keeps its license line directly above the footer"
R="$(new_root readme)"
printf '# Repo\n\nIntro.\n\n---\n\nMIT © [Someone](https://example.test/owner)\n' > "$R/README.md"
judge "kind before fix" "footer-missing" "$(kinds "$R")"
run --fix "$R" >/dev/null
tail3="$(awk 'NF {a[++n]=$0} END {print a[n-2] "|" a[n-1] "|" a[n]}' "$R/README.md")"
judge "tail is rule | license | footer" "---|MIT © [Someone](https://example.test/owner)|$FOOTER" "$tail3"
judge "license line not duplicated" 1 "$(grep -c '^MIT ©' "$R/README.md")"
judge "clean after fix" "" "$(kinds "$R")"
# idempotent: a second --fix changes nothing
before="$(cat "$R/README.md")"; run --fix "$R" >/dev/null
judge "second --fix is a no-op" "$before" "$(cat "$R/README.md")"

# ---------------------------------------------------------------------------
section "mermaid-init-missing fires on the block's first line and --fix inserts the directive"
R="$(new_root init-missing)"
printf '# T\n\n```mermaid\nflowchart TB\n  A --> B\n```\n\n---\n\n%s\n' "$FOOTER" > "$R/docs/user/d.md"
judge "kind" "mermaid-init-missing" "$(kinds "$R")"
judge "reported at fence + 1" "docs/user/d.md:4" "$(lines_of mermaid-init-missing "$R")"
run --fix "$R" >/dev/null; judge "--fix exits 0" 0 "$?"
judge "line 4 is the canonical directive" "$INIT" "$(sed -n '4p' "$R/docs/user/d.md")"
judge "diagram body preserved" "flowchart TB" "$(sed -n '5p' "$R/docs/user/d.md")"
judge "clean after fix" "" "$(kinds "$R")"

# ---------------------------------------------------------------------------
section "mermaid-init-wrong: a different directive is replaced, never stacked"
R="$(new_root init-wrong)"
printf '# T\n\n```mermaid\n%%%%{init: {"theme":"dark"}}%%%%\nflowchart TB\n  A --> B\n```\n\n---\n\n%s\n' "$FOOTER" > "$R/docs/user/e.md"
judge "kind" "mermaid-init-wrong" "$(kinds "$R")"
run --fix "$R" >/dev/null; judge "--fix exits 0" 0 "$?"
judge "exactly one init line" 1 "$(grep -c '^%%{init' "$R/docs/user/e.md")"
judge "and it is the canonical one" "$INIT" "$(sed -n '4p' "$R/docs/user/e.md")"

# ---------------------------------------------------------------------------
section "mermaid-style is reported and never rewritten"
R="$(new_root style)"
printf '# T\n\n```mermaid\n%s\nflowchart TB\n  A --> B\n  classDef big fill:#f00\n  class A big\n  style B fill:#0f0\n```\n\n---\n\n%s\n' "$INIT" "$FOOTER" > "$R/docs/user/f.md"
judge "kind" "mermaid-style" "$(kinds "$R")"
judge "three style lines" "docs/user/f.md:7 docs/user/f.md:8 docs/user/f.md:9" "$(lines_of mermaid-style "$R")"
before="$(cat "$R/docs/user/f.md")"
run --fix "$R" >/dev/null; judge "--fix still exits 1" 1 "$?"
judge "file untouched by --fix" "$before" "$(cat "$R/docs/user/f.md")"

# ---------------------------------------------------------------------------
section "box-drawing: silent by default, flagged under --strict, allowed inside a text fence"
R="$(new_root box)"
printf '# T\n\n┌──┐\n│ A │\n└──┘\n\n```text\nsrc/\n├── a.sh\n└── b.sh\n```\n\n```\n┌─┐\n```\n\n---\n\n%s\n' "$FOOTER" > "$R/docs/user/g.md"
judge "default run is clean" "" "$(kinds "$R")"
judge "--strict kind" "box-drawing" "$(kinds --strict "$R")"
judge "prose lines and the unlabelled fence flagged, the text fence not" "docs/user/g.md:3 docs/user/g.md:4 docs/user/g.md:5 docs/user/g.md:14" "$(lines_of box-drawing --strict "$R")"
run --strict --fix "$R" >/dev/null; judge "--fix cannot repair it" 1 "$?"

# ---------------------------------------------------------------------------
section "a waived block keeps its own palette"
R="$(new_root waiver)"
printf '# T\n\n<!-- doc-standards-ok: the user asked for a light palette -->\n```mermaid\n%%%%{init: {"theme":"neutral"}}%%%%\nflowchart TB\n  A --> B\n```\n\n---\n\n%s\n' "$FOOTER" > "$R/docs/user/h.md"
judge "no violation" "" "$(kinds "$R")"
before="$(cat "$R/docs/user/h.md")"; run --fix "$R" >/dev/null
judge "--fix leaves the waived block alone" "$before" "$(cat "$R/docs/user/h.md")"

# ---------------------------------------------------------------------------
section "scope: excluded and out-of-scope files are never read"
R="$(new_root scope)"
printf '# No footer here\n' > "$R/docs/agent-guidelines/x.md"
printf '# No footer here\n' > "$R/docs/CHANGELOG.md"
printf '# No footer here\n' > "$R/notes/x.md"
printf '# No footer here\n' > "$R/docs/user/in-scope.md"
judge "only the in-scope file is reported" "docs/user/in-scope.md:1" "$(lines_of footer-missing "$R")"

# ---------------------------------------------------------------------------
section "null URLs are derived from the origin remote"
R="$(new_root derive-github null null)"
harness_new_repo "$R"
git -C "$R" remote add origin git@github.com:acme/widget.git
gh_footer='<p align="center"><a href="https://github.com/acme">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/acme/widget/issues/new/choose">Open an Issue</a></p>'
printf '# T\n\n---\n\n%s\n' "$gh_footer" > "$R/docs/user/a.md"
run "$R" >/dev/null; judge "GitHub ssh origin: expected footer accepted" 0 "$?"

R="$(new_root derive-gitlab null null)"
harness_new_repo "$R"
git -C "$R" remote add origin https://gitlab.com/acme/sub/widget.git
printf '# T\n' > "$R/docs/user/a.md"
run --fix "$R" >/dev/null
judge "GitLab https origin: group path and /-/issues/new" \
  '<p align="center"><a href="https://gitlab.com/acme/sub">Have a Question?</a>&nbsp;·&nbsp;<a href="https://gitlab.com/acme/sub/widget/-/issues/new">Open an Issue</a></p>' \
  "$(last_nonblank "$R/docs/user/a.md")"

R="$(new_root derive-none null null)"
run "$R" >/dev/null 2>&1; judge "null URLs with no origin is an environment error (2)" 2 "$?"

# ---------------------------------------------------------------------------
section "a multi-line directive is consumed whole, not just its first line"
R="$(new_root init-multiline)"
printf '# T\n\n```mermaid\n%%%%{init: {\n  "theme": "dark",\n  "themeVariables": {"x": "#000"}\n}}%%%%\nflowchart TB\n  A --> B\n```\n\n---\n\n%s\n' "$FOOTER" > "$R/docs/user/m.md"
judge "kind" "mermaid-init-wrong" "$(kinds "$R")"
judge "reported once, at the directive's first line" "docs/user/m.md:4" "$(lines_of mermaid-init-wrong "$R")"
run --fix "$R" >/dev/null; judge "--fix exits 0" 0 "$?"
judge "exactly one init line" 1 "$(grep -c '^%%{init' "$R/docs/user/m.md")"
judge "it is canonical, on line 4" "$INIT" "$(sed -n '4p' "$R/docs/user/m.md")"
judge "diagram body follows immediately" "flowchart TB" "$(sed -n '5p' "$R/docs/user/m.md")"
judge "no directive tail left in the body" 0 "$(grep -cE '^\}\}%%$|"theme": "dark"' "$R/docs/user/m.md")"
judge "clean after fix" "" "$(kinds "$R")"

R="$(new_root init-unterminated)"
printf '# T\n\n```mermaid\n%%%%{init: {"theme":"dark"\nflowchart TB\n  A --> B\n```\n\nAfter.\n\n---\n\n%s\n' "$FOOTER" > "$R/docs/user/u.md"
run --fix "$R" >/dev/null
judge "an unterminated directive stops at the fence: body kept" "flowchart TB" "$(sed -n '5p' "$R/docs/user/u.md")"
judge "and the prose after the block survives" 1 "$(grep -c '^After\.$' "$R/docs/user/u.md")"

# EOF inside an unterminated directive with no closing fence: the held-back lines are
# diagram body and must be printed at end of input, not silently dropped.
R="$(new_root init-unterminated-eof)"
printf '# T\n\n```mermaid\n%%%%{init: {"theme":"dark"\nflowchart TB\n  A --> B\n' > "$R/docs/user/z.md"
run --fix "$R" >/dev/null
judge "EOF in an unterminated directive keeps the body" "flowchart TB" "$(sed -n '5p' "$R/docs/user/z.md")"
judge "and the last body line survives" 1 "$(grep -c '^  A --> B$' "$R/docs/user/z.md")"

# ---------------------------------------------------------------------------
section "a fence nested in a list keeps its indentation on the inserted directive"
R="$(new_root list-indent)"
printf '# T\n\n1. Step one:\n\n   ```mermaid\n   flowchart TB\n     A --> B\n   ```\n\n2. Step two.\n\n---\n\n%s\n' "$FOOTER" > "$R/docs/user/l.md"
judge "kind" "mermaid-init-missing" "$(kinds "$R")"
judge "reported at fence + 1" "docs/user/l.md:6" "$(lines_of mermaid-init-missing "$R")"
run --fix "$R" >/dev/null; judge "--fix exits 0" 0 "$?"
judge "directive carries the fence indent (3 spaces)" "   $INIT" "$(sed -n '6p' "$R/docs/user/l.md")"
judge "body keeps its indent" "   flowchart TB" "$(sed -n '7p' "$R/docs/user/l.md")"
judge "closing fence still indented" '   ```' "$(sed -n '9p' "$R/docs/user/l.md")"
judge "clean after fix" "" "$(kinds "$R")"

R="$(new_root list-indent-wrong)"
printf '# T\n\n- Item:\n\n  ```mermaid\n  %%%%{init: {"theme":"dark"}}%%%%\n  flowchart TB\n  ```\n\n---\n\n%s\n' "$FOOTER" > "$R/docs/user/w.md"
judge "an indented wrong directive is reported" "mermaid-init-wrong" "$(kinds "$R")"
run --fix "$R" >/dev/null; judge "--fix exits 0" 0 "$?"
judge "replacement keeps the indent (2 spaces)" "  $INIT" "$(sed -n '6p' "$R/docs/user/w.md")"
judge "exactly one directive" 1 "$(grep -c '%%{init' "$R/docs/user/w.md")"
judge "clean after fix" "" "$(kinds "$R")"

R="$(new_root list-indent-canonical)"
printf '# T\n\n- Item:\n\n  ```mermaid\n  %s\n  flowchart TB\n  ```\n\n---\n\n%s\n' "$INIT" "$FOOTER" > "$R/docs/user/c.md"
judge "an indented canonical directive is accepted" "" "$(kinds "$R")"

# ---------------------------------------------------------------------------
section "non-ASCII filenames are enumerated, checked and fixed (git and find)"
R="$(new_root unicode-git)"
harness_new_repo "$R"
printf '# T\n' > "$R/docs/user/中文.md"
judge "git enumeration reports the file (no core.quotePath mangling)" "docs/user/中文.md:1" "$(lines_of footer-missing "$R")"
run --fix "$R" >/dev/null; judge "--fix exits 0" 0 "$?"
judge "footer appended to the non-ASCII file" "$FOOTER" "$(last_nonblank "$R/docs/user/中文.md")"
R="$(new_root unicode-find)"
printf '# T\n' > "$R/docs/user/中文.md"
judge "find enumeration reports the file" "docs/user/中文.md:1" "$(lines_of footer-missing "$R")"

# ---------------------------------------------------------------------------
section "usage and environment errors exit 2"
mkdir -p "$TMP/noconfig/docs/user"
run "$TMP/noconfig" >/dev/null 2>&1; judge "missing config" 2 "$?"
R="$(new_root badflag)"
run --bogus "$R" >/dev/null 2>&1; judge "unknown flag" 2 "$?"
run --init "$TMP/absent.txt" "$R" >/dev/null 2>&1; judge "missing --init file" 2 "$?"

# ---------------------------------------------------------------------------
section "the shipped tree is clean and the scaffold template is the same script"
bash "$CHECK" "$REPO_ROOT" >/dev/null 2>&1; judge "live repo passes check-doc-standards.sh" 0 "$?"
if cmp -s "$CHECK" "$REPO_ROOT/skills/repo/_contract/templates/check-doc-standards.sh.tmpl"; then
  ok "templates/check-doc-standards.sh.tmpl is byte-identical to scripts/check-doc-standards.sh"
else
  bad "templates/check-doc-standards.sh.tmpl is byte-identical to scripts/check-doc-standards.sh" "run skills/repo/_contract/scripts/sync-contract-scripts.sh"
fi

harness_summary
