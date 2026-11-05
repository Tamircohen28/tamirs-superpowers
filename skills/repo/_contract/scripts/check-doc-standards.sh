#!/usr/bin/env bash
# check-doc-standards.sh — hold every human-facing doc to the documentation standard.
#
# WHY THIS EXISTS
#   Two things were practised rather than checked. Diagrams were drawn however
#   the author felt like it — box-drawing text in one doc, an unstyled Mermaid
#   block in the next — so nothing the skills produced looked like it came from
#   one project. And the only footer check in the tree was hardcoded to a
#   different repository, so it could never pass here and no doc carried a
#   footer at all. A standard nobody can run is a wish. This script is the one
#   check behind rules/dev/documentation-standards.md.
#
# WHAT IS CHECKED — every human-facing Markdown file (globs in the config)
#   footer-missing        the file does not end with the canonical two-link footer
#   footer-wrong          a centred footer is last, but its links differ, or the
#                         `---` rule above it is missing
#   mermaid-init-missing  a ```mermaid block whose first line is not the
#                         canonical %%{init}%% directive
#   mermaid-init-wrong    a ```mermaid block that opens with a different directive
#   mermaid-style         classDef / class / style / fill: inside a Mermaid block
#   box-drawing           (--strict only) a U+2500–U+257F box-drawing character
#                         outside a ```text fence: a diagram that should be Mermaid
#
# WHAT --fix REPAIRS
#   Footers are appended or rewritten (a license line such as `MIT © …` stays
#   directly above the footer); the init line is inserted or replaced. Style
#   lines and box-drawing diagrams are reported, never rewritten — they need an
#   author.
#
# WAIVER — one Mermaid block may keep another palette when the line directly
#   above its fence reads   <!-- doc-standards-ok: <reason> -->
#
# CONFIG
#   <ROOT>/config/docs/doc-standards.json (or --config FILE) names the
#   human-facing globs, the footer texts and URLs, and the init file (resolved
#   relative to the config; --init FILE overrides). A null URL is derived from
#   `git remote get-url origin`.
#
# Usage: check-doc-standards.sh [--fix] [--strict] [--config FILE] [--init FILE] [ROOT]
# Output: one `path:line kind: detail` per violation on stdout; counts on stderr.
# Exit:  0 clean · 1 violations remain · 2 usage/environment
set -uo pipefail

ME="check-doc-standards.sh"
FIX=0
STRICT=0
ROOT=""
CONFIG=""
INIT_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix) FIX=1 ;;
    --strict) STRICT=1 ;;
    --config)
      shift
      CONFIG="${1:-}"
      [[ -n "$CONFIG" ]] || { echo "$ME: --config needs a file" >&2; exit 2; }
      ;;
    --init)
      shift
      INIT_FILE="${1:-}"
      [[ -n "$INIT_FILE" ]] || { echo "$ME: --init needs a file" >&2; exit 2; }
      ;;
    -h|--help) sed -n '2,43p' "$0" | sed 's/^#[ ]\{0,1\}//'; exit 0 ;;
    -*) echo "$ME: unknown option '$1'" >&2; exit 2 ;;
    *)
      [[ -z "$ROOT" ]] || { echo "$ME: one ROOT only" >&2; exit 2; }
      ROOT="$1"
      ;;
  esac
  shift
done
ROOT="${ROOT:-.}"

command -v jq >/dev/null 2>&1 || { echo "$ME: jq is required" >&2; exit 2; }
[[ -d "$ROOT" ]] || { echo "$ME: no such directory: $ROOT" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"

CONFIG="${CONFIG:-$ROOT/config/docs/doc-standards.json}"
[[ -f "$CONFIG" ]] || { echo "$ME: no config at $CONFIG (see rules/dev/documentation-standards.md)" >&2; exit 2; }
jq empty "$CONFIG" 2>/dev/null || { echo "$ME: $CONFIG is not valid JSON" >&2; exit 2; }
CONFIG_DIR="$(cd "$(dirname "$CONFIG")" && pwd)"

if [[ -z "$INIT_FILE" ]]; then
  rel="$(jq -r '.mermaid.init_file // "mermaid-init.txt"' "$CONFIG")"
  case "$rel" in
    /*) INIT_FILE="$rel" ;;
    *) INIT_FILE="$CONFIG_DIR/$rel" ;;
  esac
fi
[[ -f "$INIT_FILE" ]] || { echo "$ME: Mermaid init file not found: $INIT_FILE" >&2; exit 2; }
INIT_LINE="$(head -n 1 "$INIT_FILE")"
[[ "$INIT_LINE" == '%%{init:'* ]] || { echo "$ME: $INIT_FILE must start with a %%{init: directive" >&2; exit 2; }

# --- footer: texts from the config, URLs from the config or the origin remote --
O_HOST=""
O_OWNER=""
O_REPO=""
origin_parts() {
  local url
  url="$(git -C "$ROOT" remote get-url origin 2>/dev/null)" || return 1
  [[ -n "$url" ]] || return 1
  url="${url%/}"
  url="${url%.git}"
  url="${url#*://}"
  url="${url#*@}"
  [[ "$url" =~ ^([^/:]+)[:/]+(.+)/([^/]+)$ ]] || return 1
  O_HOST="${BASH_REMATCH[1]}"
  O_OWNER="${BASH_REMATCH[2]}"
  O_REPO="${BASH_REMATCH[3]}"
}

Q_TEXT="$(jq -r '.footer.question_text // "Have a Question?"' "$CONFIG")"
I_TEXT="$(jq -r '.footer.issue_text // "Open an Issue"' "$CONFIG")"
Q_URL="$(jq -r '.footer.question_url // empty' "$CONFIG")"
I_URL="$(jq -r '.footer.issue_url // empty' "$CONFIG")"
if [[ -z "$Q_URL" || -z "$I_URL" ]]; then
  if ! origin_parts; then
    echo "$ME: footer.question_url / issue_url are null and there is no origin remote to derive them from" >&2
    exit 2
  fi
  [[ -n "$Q_URL" ]] || Q_URL="https://$O_HOST/$O_OWNER"
  if [[ -z "$I_URL" ]]; then
    case "$O_HOST" in
      *gitlab*) I_URL="https://$O_HOST/$O_OWNER/$O_REPO/-/issues/new" ;;
      *) I_URL="https://$O_HOST/$O_OWNER/$O_REPO/issues/new/choose" ;;
    esac
  fi
fi
FOOTER="<p align=\"center\"><a href=\"$Q_URL\">$Q_TEXT</a>&nbsp;·&nbsp;<a href=\"$I_URL\">$I_TEXT</a></p>"
# A license line that may sit between the rule and the footer (README keeps its `MIT © …`).
LIC_RE='^[A-Za-z0-9.+-]+ © '

# --- which files are human-facing -------------------------------------------
INCLUDE=()
EXCLUDE=()
while IFS= read -r l; do [[ -n "$l" ]] && INCLUDE+=("$l"); done < <(jq -r '.human_facing.include[]?' "$CONFIG")
while IFS= read -r l; do [[ -n "$l" ]] && EXCLUDE+=("$l"); done < <(jq -r '.human_facing.exclude[]?' "$CONFIG")
[[ ${#INCLUDE[@]} -gt 0 ]] || { echo "$ME: human_facing.include is empty in $CONFIG" >&2; exit 2; }

# `[[ == ]]` pattern matching lets `*` cross `/`, so `**/` and `**` both collapse to `*`.
glob_match() {
  local p="$1" pat="$2"
  pat="${pat//\*\*\//*}"
  pat="${pat//\*\*/*}"
  # shellcheck disable=SC2053  # the pattern must stay unquoted to glob
  [[ "$p" == $pat ]]
}
is_human_facing() {
  local p="$1" pat inc=0
  for pat in "${INCLUDE[@]}"; do glob_match "$p" "$pat" && { inc=1; break; }; done
  [[ $inc -eq 1 ]] || return 1
  if [[ ${#EXCLUDE[@]} -gt 0 ]]; then
    for pat in "${EXCLUDE[@]}"; do glob_match "$p" "$pat" && return 1; done
  fi
  return 0
}

# Tracked + untracked-not-ignored files when ROOT is a repository's top level;
# a pruned find otherwise (a fixture tree inside another repo, or no git at all).
# NUL-terminated end to end: under the default core.quotePath git prints a
# non-ASCII path as "docs/\344\270\255\346\226\207.md", a quoted name that matches
# no file, so such docs silently dropped out of both the check and the fix.
# `-z` / `-print0` hand the raw bytes over, and the caller reads with -d ''.
# Nested worktree directories are dropped by the caller: they hold other branches.
list_candidates() {
  local top
  top="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$top" && "$(cd "$top" && pwd -P)" == "$(pwd -P)" ]]; then
    git -C "$ROOT" ls-files -z --cached --others --exclude-standard -- '*.md' 2>/dev/null
  else
    find . \( -name .git -o -name node_modules -o -name .venv -o -name .worktrees -o -name .agent-worktrees \) -prune \
      -o -type f -name '*.md' -print0
  fi | sort -z -u
}

# --- per-file analysis: prints  line<TAB>kind<TAB>detail  ----------------------
# Fences: a run of ``` or ~~~ opens; the same character, at least as long, with
# nothing after it, closes. Box-drawing is matched on the UTF-8 bytes
# (E2 94 xx / E2 95 xx = U+2500–U+257F) so the check needs no locale support.
analyze() {
  LC_ALL=C awk -v INIT="$INIT_LINE" -v FOOTER="$FOOTER" -v LIC="$LIC_RE" -v STRICT="$STRICT" '
    function marker(s,  m) { m = s; sub(/^[ \t]*/, "", m); if (match(m, /^(`+|~+)/)) return substr(m, 1, RLENGTH); return "" }
    function push(s) { l3 = l2; n3 = n2; l2 = l1; n2 = n1; l1 = s; n1 = NR }
    BEGIN { infence = 0; lang = ""; fm = ""; expect = 0; waived = 0; eat = 0; prev = ""; l1 = l2 = l3 = ""; n1 = n2 = n3 = 0 }
    {
      line = $0
      m = marker(line)
      # A directive that opened on an earlier line runs to its closing }%%; its JSON
      # tail is part of the directive, not diagram body, so no other check reads it.
      # An unterminated one stops at the fence rather than swallowing the file.
      if (eat) {
        if (line ~ /[}]%%[ \t]*$/) { eat = 0; prev = line; push(line); next }
        if (m == "" || length(m) < 3) { prev = line; push(line); next }
        eat = 0
      }
      if (m != "" && length(m) >= 3) {
        if (infence) {
          if (substr(m, 1, 1) == substr(fm, 1, 1) && length(m) >= length(fm) && line ~ /^[ \t]*(`+|~+)[ \t]*$/) {
            if (lang == "mermaid" && expect && !waived) printf "%d\tmermaid-init-missing\tempty Mermaid block\n", open + 1
            infence = 0; lang = ""; fm = ""; expect = 0; waived = 0
            prev = line; push(line); next
          }
        } else {
          infence = 1; fm = m
          lang = line; sub(/^[ \t]*(`+|~+)[ \t]*/, "", lang); sub(/[ \t].*$/, "", lang)
          if (lang == "mermaid") { open = NR; expect = 1; waived = (prev ~ /<!--[ \t]*doc-standards-ok:/) }
          prev = line; push(line); next
        }
      }
      if (infence && lang == "mermaid") {
        if (expect) {
          expect = 0
          # A fence nested in a list is indented, and so is every line inside it;
          # the directive is judged with that indent stripped.
          t = line; sub(/^[ \t]*/, "", t)
          if (t ~ /^%%\{init/ && t !~ /[}]%%[ \t]*$/) eat = 1
          if (!waived && t != INIT) {
            if (t ~ /^%%\{init/) printf "%d\tmermaid-init-wrong\tnot the canonical init directive\n", NR
            else printf "%d\tmermaid-init-missing\tfirst line of a Mermaid block must be the canonical init directive\n", NR
          }
        } else if (line ~ /classDef|^[ \t]*class[ \t]|fill:|^[ \t]*style[ \t]/) {
          printf "%d\tmermaid-style\tper-node styling is forbidden; the theme comes from the init line\n", NR
        }
      }
      if (STRICT == 1 && !(infence && lang == "text") && line ~ /\342[\224\225]/) {
        printf "%d\tbox-drawing\tdiagram drawn with box characters; redraw as a Mermaid block\n", NR
      }
      prev = line
      if (line !~ /^[ \t]*$/) push(line)
    }
    END {
      if (NR == 0) { printf "1\tfooter-missing\tempty file\n"; exit }
      if (l1 == FOOTER) {
        if (l2 == "---") exit
        if (l2 ~ LIC && l3 == "---") exit
        printf "%d\tfooter-wrong\tno --- rule above the footer\n", n1
      } else if (l1 ~ /^<p align="center">.*<a href=/) {
        printf "%d\tfooter-wrong\tfooter links differ from the canonical footer\n", n1
      } else {
        printf "%d\tfooter-missing\tfile must end with the canonical two-link footer\n", NR
      }
    }
  ' "$1"
}

# --- fixes --------------------------------------------------------------------
fix_mermaid() {
  local f="$1" tmp
  tmp="$(mktemp)"
  LC_ALL=C awk -v INIT="$INIT_LINE" '
    function marker(s,  m) { m = s; sub(/^[ \t]*/, "", m); if (match(m, /^(`+|~+)/)) return substr(m, 1, RLENGTH); return "" }
    BEGIN { infence = 0; lang = ""; fm = ""; ind = ""; expect = 0; waived = 0; eat = 0; nbuf = 0; prev = "" }
    {
      line = $0
      m = marker(line)
      # An old directive is consumed whole, from %%{init through its closing }%% --
      # a multi-line one spans several lines, and dropping only its first line left
      # the JSON tail and the }%% in the diagram body while the re-check, which reads
      # only the first line of a block, reported it clean. Consumed lines are held
      # back, not dropped: when the fence arrives before a closing }%% the directive
      # was unterminated and those lines were diagram body, so they are printed again
      # -- a repair must never eat a diagram. (No apostrophes in these comments: the
      # awk program is a single-quoted shell string.)
      if (eat) {
        if (line ~ /[}]%%[ \t]*$/) { eat = 0; nbuf = 0; prev = line; next }
        if (m == "" || length(m) < 3) { nbuf++; buf[nbuf] = line; prev = line; next }
        for (i = 1; i <= nbuf; i++) print buf[i]
        nbuf = 0; eat = 0
      }
      if (m != "" && length(m) >= 3) {
        if (infence) {
          if (substr(m, 1, 1) == substr(fm, 1, 1) && length(m) >= length(fm) && line ~ /^[ \t]*(`+|~+)[ \t]*$/) {
            if (lang == "mermaid" && expect && !waived) print ind INIT
            infence = 0; lang = ""; fm = ""; expect = 0; waived = 0
            print line; prev = line; next
          }
        } else {
          infence = 1; fm = m
          lang = line; sub(/^[ \t]*(`+|~+)[ \t]*/, "", lang); sub(/[ \t].*$/, "", lang)
          # A fence nested in a list is indented. The directive is written with the
          # same indent: at column zero it would leave the list item, end the fenced
          # block as Markdown sees it, and break the diagram while the re-check --
          # which compares with the indent stripped -- reported it clean.
          ind = line; sub(/[^ \t].*$/, "", ind)
          if (lang == "mermaid") { expect = 1; waived = (prev ~ /<!--[ \t]*doc-standards-ok:/) }
          print line; prev = line; next
        }
      }
      if (infence && lang == "mermaid" && !waived) {
        t = line; sub(/^[ \t]*/, "", t)
        if (expect) {
          expect = 0
          if (t == INIT) { print line; prev = line; next }
          print ind INIT
          if (t ~ /^%%\{init/) { if (t !~ /[}]%%[ \t]*$/) eat = 1; prev = line; next }
          print line; prev = line; next
        }
        if (t ~ /^%%\{init/) { if (t !~ /[}]%%[ \t]*$/) eat = 1; prev = line; next }
      }
      if (expect) expect = 0
      print line; prev = line
    }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

# Normalise the tail: drop trailing blanks, an old centred footer, a license
# line and a `---` rule; then re-append rule, license (if any) and footer.
fix_footer() {
  local f="$1" tmp lic
  tmp="$(mktemp)"
  lic="$(LC_ALL=C awk -v LIC="$LIC_RE" -v OUT="$tmp" '
    { lines[NR] = $0 }
    END {
      n = NR
      while (n > 0 && lines[n] ~ /^[ \t]*$/) n--
      if (n > 0 && lines[n] ~ /^<p align="center">.*<a href=/) { n--; while (n > 0 && lines[n] ~ /^[ \t]*$/) n-- }
      if (n > 0 && lines[n] ~ LIC) { print lines[n]; n--; while (n > 0 && lines[n] ~ /^[ \t]*$/) n-- }
      if (n > 0 && lines[n] == "---") { n--; while (n > 0 && lines[n] ~ /^[ \t]*$/) n-- }
      for (i = 1; i <= n; i++) print lines[i] > OUT
    }' "$f")"
  {
    cat "$tmp"
    printf '\n---\n\n'
    [[ -n "$lic" ]] && printf '%s\n\n' "$lic"
    printf '%s\n' "$FOOTER"
  } > "$f"
  rm -f "$tmp"
}

# --- main ---------------------------------------------------------------------
cd "$ROOT" || exit 2
FILES=0
TOTAL=0
FIXED=0
while IFS= read -r -d '' rel; do
  rel="${rel#./}"
  [[ -n "$rel" ]] || continue
  case "$rel" in
    .worktrees/*|*/.worktrees/*|.agent-worktrees/*|*/.agent-worktrees/*) continue ;;
  esac
  is_human_facing "$rel" || continue
  [[ -f "$rel" ]] || continue
  FILES=$((FILES + 1))
  ev="$(analyze "$rel")"
  if [[ $FIX -eq 1 && -n "$ev" ]]; then
    kinds="$(printf '%s\n' "$ev" | cut -f2 | sort -u | tr '\n' ' ')"
    did=""
    case " $kinds " in *" mermaid-init-missing "*|*" mermaid-init-wrong "*) fix_mermaid "$rel"; did="$did mermaid-init" ;; esac
    case " $kinds " in *" footer-missing "*|*" footer-wrong "*) fix_footer "$rel"; did="$did footer" ;; esac
    if [[ -n "$did" ]]; then
      FIXED=$((FIXED + 1))
      echo "$ME: fixed $rel:$did" >&2
      ev="$(analyze "$rel")"
    fi
  fi
  if [[ -n "$ev" ]]; then
    while IFS=$'\t' read -r ln kind detail; do
      [[ -n "$kind" ]] || continue
      echo "$rel:$ln $kind: $detail"
      TOTAL=$((TOTAL + 1))
    done <<< "$ev"
  fi
done < <(list_candidates)

if [[ $FIX -eq 1 ]]; then
  echo "$ME: $FILES human-facing files, $FIXED fixed, $TOTAL violations remain" >&2
else
  echo "$ME: $FILES human-facing files, $TOTAL violations" >&2
fi
[[ $TOTAL -eq 0 ]]
