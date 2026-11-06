#!/usr/bin/env bash
# check-hook-answers.sh — local proxy for the plugin directory's HOOK_GRANTS_PERMISSION rule.
#
# The directory's scanner flags a PreToolUse hook it cannot prove unable to approve a tool call. It only
# runs after a release, so this script reproduces the rule locally: it reads hooks/hooks.json, takes every
# PreToolUse entry's command, resolves the script it runs, follows every file that script loads, and reports
# each place in that closure where one of four rules fires:
#
#   r1  a shell printf whose format string holds a % conversion (%s, %d, %b, %q, ... ; %% is not one).
#       Python %-formatting is not counted: the rule is about printf.
#   r2  a backslash escape that spells a character by number or hides a quote: \xNN, \NNN (octal),
#       \0NN, \uNNNN, \UNNNNNNNN, and \' (which covers the '\'' idiom).
#   r3  the word allow or approve (case-insensitive, whole word) inside a quoted string: shell single,
#       double and $'...' quotes, non-python heredoc bodies, python string literals (docstrings included),
#       and jq programs, which are shell-quoted strings. A variable name ($allow) is not string text.
#   r4  stderr merged into stdout: 2>&1, &>, &>>, |& in shell code; stderr=STDOUT and
#       sys.stderr = sys.stdout in python code.
#
# COMMENTS ARE EXCLUDED from every rule: shell `#` comments and python `#` comments. Strings are excluded
# from r4 (a "2>&1" in a message is data, not a redirection). r2 applies to code and strings alike.
#
# HOW IT READS A FILE (never executes one)
#   Shell is lexed character by character into code / quote / string / comment / heredoc classes, with
#   $( ), ${ }, backticks and case patterns nested. A heredoc whose delimiter contains PY, or whose opening
#   line names python, is an embedded python program and is tokenized with python's own tokenize module,
#   so its strings and comments are exact too. Python files are tokenized the same way.
#
# THE CLOSURE (what "every file it loads" means here — printed, so it is auditable)
#   - shell: any path written after a variable or a command substitution in code or a double-quoted
#     string ("${SCRIPT_DIR}/lib/x.sh", "$(dirname "$0")/lib/x.sh", "$ROOT/scripts/lib/y.sh"), which is
#     how a hook sources a lib, execs a script or runs `python3 .../x.py`. The suffix is resolved against
#     the file's own directory, then each parent up to ROOT; the first existing match is followed.
#   - python: `import m` / `from m import` where m.py exists in the file's directory, its lib/, or hooks/lib.
#   Only files under ROOT/hooks/ or ROOT/scripts/ are followed.
#
# Usage:
#   scripts/check-hook-answers.sh [ROOT] [--json] [--summary] [--hook <path>] [-v] [-h]
#
# Arguments:
#   ROOT            plugin root holding hooks/hooks.json (default: this script's repository)
#
# Flags:
#   --json          one JSON document instead of text: hooks, closure, findings, counts, totals
#   --summary       text mode: print only the per-hook count table
#   --hook <path>   check one hook script (relative to ROOT or absolute); it need not be in hooks.json
#   -v, --verbose   text mode: print each closure edge with the line that loads it
#   -h, --help      this help
#
# Exit status: 0 every count is zero · 1 at least one finding · 2 usage or input error.
#
# Example:
#   scripts/check-hook-answers.sh --summary
#   scripts/check-hook-answers.sh --hook hooks/docker-guard.py
#   scripts/check-hook-answers.sh . --json | jq '.totals'
set -euo pipefail

usage() { sed -n '2,/^set -euo pipefail$/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; }

ROOT=""
JSON=0
SUMMARY=0
VERBOSE=0
HOOK=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --json) JSON=1 ;;
    --summary) SUMMARY=1 ;;
    -v|--verbose) VERBOSE=1 ;;
    --hook)
      [ "$#" -ge 2 ] || { echo "check-hook-answers: --hook needs a path" >&2; exit 2; }
      HOOK="$2"; shift ;;
    --hook=*) HOOK="${1#--hook=}" ;;
    -*) echo "check-hook-answers: unknown flag: $1 (see --help)" >&2; exit 2 ;;
    *)
      [ -z "$ROOT" ] || { echo "check-hook-answers: more than one ROOT given (see --help)" >&2; exit 2; }
      ROOT="$1" ;;
  esac
  shift
done

if [ -z "$ROOT" ]; then
  ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
fi
[ -d "$ROOT" ] || { echo "check-hook-answers: not a directory: $ROOT" >&2; exit 2; }
ROOT="$(CDPATH='' cd -- "$ROOT" && pwd -P)"
command -v python3 >/dev/null || { echo "check-hook-answers: python3 is required" >&2; exit 2; }

IFS= read -r -d '' CHA_PY <<'PY' || true
import bisect, io, json, os, re, sys, tokenize

ROOT, JSON_OUT, SUMMARY, VERBOSE, HOOK = sys.argv[1], sys.argv[2] == "1", sys.argv[3] == "1", sys.argv[4] == "1", sys.argv[5]

RULES = {
    "r1": "printf format string with a % conversion",
    "r2": "backslash escape (\\xNN, \\NNN, \\uNNNN, \\')",
    "r3": "allow/approve inside a quoted string",
    "r4": "stderr merged into stdout (2>&1, &>, |&, stderr=STDOUT)",
}
RULE_IDS = sorted(RULES)

# Character classes. C shell code, c python code, Q a quote delimiter, S single-quoted / $'' / python string,
# D double-quoted text, H non-python heredoc body, T python docstring, K comment.
STRING_CLASSES = set("SDHT")

def die(msg):
    sys.stderr.write("check-hook-answers: %s\n" % msg)
    sys.exit(2)

# ---------------------------------------------------------------------------------------------------- shell
SH_BREAK = set(" \t\n;&|<>()")
NAME_START = re.compile(r"[A-Za-z_]")

class ShellLexer:
    def __init__(self, src):
        self.s, self.n, self.i = src, len(src), 0
        self.cls = ["C"] * len(src)
        self.pending = []       # heredocs whose bodies start at the next code newline
        self.py_ranges = []     # (start, end) of heredoc bodies that are python programs

    def mark(self, a, b, c):
        for k in range(a, min(b, self.n)):
            self.cls[k] = c

    def run(self):
        while self.i < self.n:
            self.code(None)
            if self.i < self.n:     # a stray closer at top level: step over it
                self.i += 1
        return self

    def code(self, stop):
        s, n = self.s, self.n
        word_start, paren, case_depth = True, 0, 0
        while self.i < n:
            i, c = self.i, s[self.i]
            if c == "\\":
                self.i += 2
                word_start = i + 1 < n and s[i + 1] == "\n"
                continue
            if c == "\n":
                self.i += 1
                if self.pending:
                    self.read_heredocs()
                word_start = True
                continue
            if stop == ")" and c == ")":
                if paren > 0:
                    paren -= 1
                elif case_depth == 0:
                    return
                self.i += 1
                word_start = True
                continue
            if stop == "`" and c == "`":
                return
            if c == "#" and word_start:
                j = s.find("\n", i)
                j = n if j < 0 else j
                self.mark(i, j, "K")
                self.i = j
                continue
            if c == "'":
                self.single(i)
            elif c == '"':
                self.double(i)
            elif c == "$" and i + 1 < n and s[i + 1] == "'":
                self.ansi_c(i)
            elif c == "$" and s.startswith("$((", i):
                self.i = i + 3
                self.code(")")
                self.i += 1
                if self.i < n and s[self.i] == ")":
                    self.i += 1
            elif c == "$" and i + 1 < n and s[i + 1] == "(":
                self.i = i + 2
                self.code(")")
                self.i += 1
            elif c == "$" and i + 1 < n and s[i + 1] == "{":
                self.param(i, "C")
            elif c == "`":
                self.i = i + 1
                self.code("`")
                self.i += 1
            elif s.startswith("<<<", i):
                self.i = i + 3            # a herestring, not a heredoc
            elif s.startswith("<<", i):
                self.heredoc_op(i)
            elif c == "(":
                paren += 1
                self.i = i + 1
            else:
                if word_start and NAME_START.match(c):
                    m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", s[i:i + 64])
                    w = m.group(0)
                    end = i + len(w)
                    if end >= n or s[end] in SH_BREAK:
                        if w == "case":
                            case_depth += 1
                        elif w == "esac" and case_depth:
                            case_depth -= 1
                    self.i = end
                    word_start = False
                    continue
                self.i = i + 1
            word_start = c in SH_BREAK

    def single(self, i):
        j = self.s.find("'", i + 1)
        j = self.n if j < 0 else j
        self.mark(i, i + 1, "Q")
        self.mark(i + 1, j, "S")
        self.mark(j, j + 1, "Q")
        self.i = j + 1

    def ansi_c(self, i):
        s, n = self.s, self.n
        self.mark(i, i + 2, "Q")
        j = i + 2
        while j < n and s[j] != "'":
            j += 2 if s[j] == "\\" else 1
        self.mark(i + 2, j, "S")
        self.mark(j, j + 1, "Q")
        self.i = j + 1

    def double(self, i):
        s, n = self.s, self.n
        self.mark(i, i + 1, "Q")
        j = i + 1
        while j < n:
            c = s[j]
            if c == "\\":
                self.mark(j, j + 2, "D")
                j += 2
            elif c == '"':
                self.mark(j, j + 1, "Q")
                self.i = j + 1
                return
            elif c == "$" and s.startswith("$((", j):
                self.i = j + 3
                self.code(")")
                j = self.i + 1
                if j < n and s[j] == ")":
                    j += 1
            elif c == "$" and j + 1 < n and s[j + 1] == "(":
                self.i = j + 2
                self.code(")")
                j = self.i + 1
            elif c == "$" and j + 1 < n and s[j + 1] == "{":
                self.param(j, "D")
                j = self.i
            elif c == "$" and j + 1 < n and (NAME_START.match(s[j + 1]) or s[j + 1] in "0123456789#?@*!$-"):
                m = re.match(r"\$(?:[A-Za-z_][A-Za-z0-9_]*|.)", s[j:j + 64])
                j += len(m.group(0))      # an expansion's name is code, not string text
            elif c == "`":
                self.i = j + 1
                self.code("`")
                j = self.i + 1
            else:
                self.mark(j, j + 1, "D")
                j += 1
        self.i = n

    def param(self, i, inner):
        """${...}: the name is code; the operator's word takes `inner`. Inside double quotes a single quote
        is literal (bash), so only a ${ } outside them opens a single-quoted string."""
        s, n = self.s, self.n
        j = i + 2
        m = re.match(r"[#!]?(?:[A-Za-z_][A-Za-z0-9_]*|[0-9]+|[@*#?$!-])", s[j:j + 64])
        if m:
            j += len(m.group(0))
        depth = 0
        while j < n:
            c = s[j]
            if c == "\\":
                self.mark(j, j + 2, inner)
                j += 2
            elif c == "}" and depth == 0:
                self.i = j + 1
                return
            elif c == "}":
                depth -= 1
                j += 1
            elif c == "{":
                depth += 1
                j += 1
            elif c == "'" and inner == "C":
                self.single(j)
                j = self.i
            elif c == '"':
                self.double(j)
                j = self.i
            elif c == "$" and j + 1 < n and s[j + 1] == "(":
                self.i = j + 2
                self.code(")")
                j = self.i + 1
            elif c == "$" and j + 1 < n and s[j + 1] == "{":
                self.param(j, inner)
                j = self.i
            elif c == "$":
                m = re.match(r"\$(?:[A-Za-z_][A-Za-z0-9_]*|.)?", s[j:j + 64])
                j += max(1, len(m.group(0)))
            else:
                self.mark(j, j + 1, inner)
                j += 1
        self.i = n

    def heredoc_op(self, i):
        s = self.s
        m = re.match(r"<<(-?)[ \t]*(?:'([^'\n]*)'|\"([^\"\n]*)\"|\\?([A-Za-z0-9_.-]+))", s[i:i + 200])
        if not m:
            self.i = i + 2
            return
        delim = m.group(2) if m.group(2) is not None else (m.group(3) if m.group(3) is not None else m.group(4))
        line_start = s.rfind("\n", 0, i) + 1
        opener = s[line_start:i]
        is_py = "PY" in delim.upper() or re.search(r"\bpython3?\b", opener) is not None
        self.pending.append((delim, m.group(1) == "-", is_py))
        self.i = i + len(m.group(0))

    def read_heredocs(self):
        s, n = self.s, self.n
        for delim, strip_tabs, is_py in self.pending:
            body_start = j = self.i
            while j < n:
                e = s.find("\n", j)
                e = n if e < 0 else e
                line = s[j:e]
                if (line.lstrip("\t") if strip_tabs else line) == delim:
                    break
                j = e + 1
            body_end = min(j, n)
            if is_py:
                self.py_ranges.append((body_start, body_end))
            else:
                self.mark(body_start, body_end, "H")
            e = s.find("\n", body_end)
            self.i = n if e < 0 else e + 1
        self.pending = []

# --------------------------------------------------------------------------------------------------- python
STRING_TOKENS = {"STRING", "FSTRING_MIDDLE", "TSTRING_MIDDLE"}
QUOTE_TOKENS = {"FSTRING_START", "FSTRING_END", "TSTRING_START", "TSTRING_END"}

def classify_python(src, cls, base, warnings, where):
    """Write python classes for src (which sits at offset `base` of the file) into cls; return imports."""
    starts = [0]
    for k, ch in enumerate(src):
        if ch == "\n":
            starts.append(k + 1)
    def off(row, col):
        return base + starts[row - 1] + col
    for k in range(base, base + len(src)):
        cls[k] = "c"
    imports = []
    try:
        toks = list(tokenize.generate_tokens(io.StringIO(src).readline))
    except (tokenize.TokenError, SyntaxError, IndentationError) as exc:
        warnings.append("%s: python could not be tokenized (%s); its text is scanned as code" % (where, exc))
        return imports
    prev = []
    stmt_start = {tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT, tokenize.ENCODING}
    for idx, t in enumerate(toks):
        name = tokenize.tok_name[t.type]
        a, b = off(*t.start), off(*t.end)
        if name == "COMMENT":
            for k in range(a, b):
                cls[k] = "K"
        elif name in STRING_TOKENS:
            nxt = toks[idx + 1].type if idx + 1 < len(toks) else tokenize.NEWLINE
            doc = name == "STRING" and (not prev or prev[-1].type in stmt_start) and nxt in (tokenize.NEWLINE, tokenize.ENDMARKER)
            for k in range(a, b):
                cls[k] = "T" if doc else "S"
        elif name in QUOTE_TOKENS:
            for k in range(a, b):
                cls[k] = "Q"
        elif name == "NAME":
            if len(prev) >= 1 and prev[-1].string in ("import", "from") and tokenize.tok_name[prev[-1].type] == "NAME":
                imports.append((t.string, base + starts[t.start[0] - 1]))
            elif len(prev) >= 2 and prev[-1].string == "," and _in_import(prev):
                imports.append((t.string, base + starts[t.start[0] - 1]))
        if name not in ("NL", "COMMENT"):
            prev.append(t)
            if len(prev) > 64:
                del prev[:32]
    return imports

def _in_import(prev):
    for t in reversed(prev):
        if t.type == tokenize.NEWLINE:
            return False
        if t.type == tokenize.NAME and t.string == "import":
            return True
    return False

# ---------------------------------------------------------------------------------------------- one file
CONVERSION = re.compile(r"%[-+ #0'\d]*(?:\*|\d+)?(?:\.(?:\*|\d*))?[diouxXfFeEgGaAcsbq]|%\([^)]*\)T")
R2 = re.compile(r"\\x[0-9A-Fa-f]{1,2}|\\0[0-7]{1,3}|\\[1-7][0-7]{2}|\\u[0-9A-Fa-f]{4}|\\U[0-9A-Fa-f]{8}|\\'")
R3 = re.compile(r"\b(?:allow|approve)\b", re.I)
R4_SH = re.compile(r"(?<![0-9])2>&1(?![0-9])|&>>?|\|&")
R4_PY = re.compile(r"stderr\s*=\s*(?:subprocess\.)?STDOUT\b|sys\.stderr\s*=\s*sys\.stdout\b")
PATH_REF = re.compile(r"(?:\$\{[^}\n]*\}|\$[A-Za-z_][A-Za-z0-9_]*|\))\"?((?:/[A-Za-z0-9_.-]+)+\.(?:sh|py))\b")
PY_JOIN = re.compile(r"^[ \t]*([A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*os\.path\.join\(", re.M)
KEYWORDS_BEFORE_CMD = {"then", "do", "else", "elif", "if", "while", "until", "command", "builtin", "exec", "time", "!"}

class Scan:
    def __init__(self, path, rel):
        self.path, self.rel = path, rel
        with open(path, encoding="utf-8", errors="replace") as fh:
            self.src = fh.read()
        self.line_starts = [0] + [m.end() for m in re.finditer("\n", self.src)]
        self.warnings, self.imports, self.findings, self.docstring_lines = [], [], [], set()
        first = self.src.split("\n", 1)[0]
        self.is_py = path.endswith(".py") or (first.startswith("#!") and "python" in first)
        if self.is_py:
            self.cls = ["c"] * len(self.src)
            self.py_ranges = [(0, len(self.src))]
            self.imports = classify_python(self.src, self.cls, 0, self.warnings, rel)
        else:
            lx = ShellLexer(self.src).run()
            self.cls = lx.cls
            self.py_ranges = lx.py_ranges
            for a, b in lx.py_ranges:
                self.imports += classify_python(self.src[a:b], self.cls, a, self.warnings, "%s:%d" % (rel, self.line_of(a)))

    def line_of(self, k):
        return bisect.bisect_right(self.line_starts, k)

    def line_text(self, line):
        a = self.line_starts[line - 1]
        e = self.src.find("\n", a)
        return self.src[a:e if e >= 0 else len(self.src)].strip()

    def mask(self, keep):
        return "".join(ch if (cl in keep or ch == "\n") else " " for ch, cl in zip(self.src, self.cls))

    def add(self, rule, k):
        self.findings.append((self.line_of(k), rule))

    def run_rules(self):
        all_but_comments = self.mask(set("CcQSDHT"))
        for m in R2.finditer(all_but_comments):
            self.add("r2", m.start())
        for m in R3.finditer(self.mask(STRING_CLASSES)):
            self.add("r3", m.start())
            if self.cls[m.start()] == "T":
                self.docstring_lines.add(self.line_of(m.start()))
        for m in R4_SH.finditer(self.mask({"C"})):
            self.add("r4", m.start())
        for m in R4_PY.finditer(self.mask({"c"})):
            self.add("r4", m.start())
        self.printf_rule()
        seen, out = set(), []
        for line, rule in sorted(self.findings):
            if (line, rule) not in seen:
                seen.add((line, rule))
                x = {"file": self.rel, "line": line, "rule": rule, "text": self.line_text(line)[:160]}
                if rule == "r3" and line in self.docstring_lines:
                    x["docstring"] = True
                out.append(x)
        self.findings = out

    # r1: a code word `printf` in command position; its first non-option argument is the format.
    def printf_rule(self):
        s, cls, n = self.src, self.cls, len(self.src)
        for m in re.finditer(r"printf", s):
            a, b = m.start(), m.end()
            if any(cls[k] != "C" for k in range(a, b)):
                continue
            if a > 0 and not (cls[a - 1] == "C" and s[a - 1] in " \t\n;&|()!{`"):
                continue          # part of a longer word: xprintf, "a"printf, $printf
            if b < n and not (s[b] in " \t\n;&|)" and cls[b] == "C"):
                continue
            if not self.command_position(a):
                continue
            words = self.words_after(b)
            k = 0
            while k < len(words) and words[k][0] in ("-v", "--"):
                k += 2 if words[k][0] == "-v" else 1
            if k < len(words) and CONVERSION.search(words[k][1].replace("%%", "")):
                self.add("r1", a)

    def command_position(self, a):
        s, cls = self.src, self.cls
        j = a - 1
        while j >= 0 and cls[j] == "C" and s[j] in " \t":
            j -= 1
        if j < 0:
            return True
        if cls[j] == "C" and s[j] in "\n;&|()!{`":
            return True
        e = j + 1
        while j >= 0 and cls[j] == "C" and s[j] not in " \t\n;&|()":
            j -= 1
        return s[j + 1:e] in KEYWORDS_BEFORE_CMD

    def words_after(self, b, limit=4):
        """The next few shell words after offset b, as (raw code text, literal text) pairs."""
        s, cls, n = self.src, self.cls, len(self.src)
        words, j = [], b
        while j < n and len(words) < limit:
            while j < n and cls[j] == "C" and s[j] in " \t":
                j += 1
            if j + 1 < n and s[j] == "\\" and s[j + 1] == "\n":
                j += 2
                continue
            if j >= n or cls[j] == "K" or (cls[j] == "C" and s[j] in "\n;&|<>()"):
                break
            raw, lit = [], []
            while j < n and not (cls[j] == "C" and s[j] in " \t\n;&|<>()") and cls[j] != "K":
                if cls[j] != "Q":
                    lit.append(s[j])
                raw.append(s[j])
                j += 1
            words.append(("".join(raw), "".join(lit)))
        return words

    def references(self):
        """(suffix, line, how) for every path this file loads or runs."""
        refs = []
        if not self.is_py:
            m_text = self.mask(set("CQD"))
            for m in PATH_REF.finditer(m_text):
                line = self.line_of(m.start())
                before = m_text[self.line_starts[line - 1]:m.start()]
                if re.search(r"(?:^|[\s;&|(])(?:source|\.)\s+\"?$", before):
                    how = "source"
                elif re.search(r"\bpython3?(?:\s+-\S+)*\s+\"?$", before):
                    how = "python"
                elif re.search(r"\b(?:bash|sh|exec)(?:\s+-\S+)*\s+\"?$", before):
                    how = "exec"
                else:
                    how = "path"
                refs.append((m.group(1), line, how))
        for mod, line_off in self.imports:
            refs.append(("/" + mod + ".py", self.line_of(line_off), "import"))
        refs += self.python_exec_refs()
        return refs

    def python_exec_refs(self):
        """NAME = os.path.join(..., "x.sh") in python, followed only when NAME is then used inside an argv list
        or a subprocess call, so a path the code merely compares against is not taken for one it runs."""
        refs, text = [], self.mask(set("cQST"))
        for a, b in self.py_ranges:
            region = text[a:b]
            for m in PY_JOIN.finditer(region):
                depth, k = 1, m.end()
                while k < len(region) and depth:
                    depth += {"(": 1, ")": -1}.get(region[k], 0)
                    k += 1
                lits = [x[1] for x in re.findall(r"(['\"])([^'\"\n]*)\1", region[m.end():k])]
                if not lits or not re.search(r"\.(?:sh|py)$", lits[-1]):
                    continue
                name = re.escape(m.group(1))
                used = re.search(r"\[[^\]\n]*\b%s\b|\b(?:Popen|run|call|check_call|check_output)\([^\n]*\b%s\b" % (name, name), region)
                if used:
                    refs.append(("/" + "/".join(x.strip("/") for x in lits), self.line_of(a + m.start(1)), "python-exec"))
        return refs

# ------------------------------------------------------------------------------------------------ closure
def under_followed_tree(path):
    rel = os.path.relpath(path, ROOT)
    return rel.startswith("hooks" + os.sep) or rel.startswith("scripts" + os.sep)

def resolve(suffix, from_file, how):
    d = os.path.dirname(from_file)
    if how == "import":
        dirs = [d, os.path.join(d, "lib"), os.path.join(ROOT, "hooks", "lib")]
        cands = [os.path.join(x, suffix.lstrip("/")) for x in dirs]
    else:
        cands = []
        while True:
            cands.append(os.path.normpath(d + suffix))
            if os.path.normpath(d) == ROOT or len(d) <= len(ROOT):
                break
            d = os.path.dirname(d)
    for c in cands:
        if os.path.isfile(c) and under_followed_tree(c):
            return os.path.realpath(c)
    return None

SCANS = {}
def scan(path):
    if path not in SCANS:
        sc = Scan(path, os.path.relpath(path, ROOT))
        sc.run_rules()
        SCANS[path] = sc
    return SCANS[path]

def closure(entry):
    order, edges, todo, seen = [entry], [], [entry], {entry}
    while todo:
        f = todo.pop(0)
        for suffix, line, how in scan(f).references():
            t = resolve(suffix, f, how)
            if t is None or t == f:
                continue
            if t not in seen:
                seen.add(t)
                order.append(t)
                todo.append(t)
                edges.append({"file": os.path.relpath(t, ROOT), "via": "%s:%d" % (os.path.relpath(f, ROOT), line), "how": how})
    return order, edges

# ---------------------------------------------------------------------------------------------- entries
def hook_entries():
    if HOOK:
        p = HOOK if os.path.isabs(HOOK) else os.path.join(ROOT, HOOK)
        if not os.path.isfile(p):
            die("no such hook script: %s" % HOOK)
        return [(os.path.realpath(p), ["--hook"])]
    hj = os.path.join(ROOT, "hooks", "hooks.json")
    try:
        with open(hj, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError) as exc:
        die("cannot read %s: %s" % (hj, exc))
    entries, index = [], {}
    for group in (doc.get("hooks") or {}).get("PreToolUse") or []:
        matcher = group.get("matcher", "*")
        for h in group.get("hooks") or []:
            cmd = h.get("command")
            if h.get("type", "command") != "command" or not isinstance(cmd, str):
                continue
            m = re.search(r"\$\{?CLAUDE_PLUGIN_ROOT\}?\"?((?:/[^\"'\s]+)+)", cmd) or re.search(r"(?:^|\s)\"?((?:hooks|scripts)/[^\"'\s]+)", cmd)
            if not m:
                die("cannot find the script in PreToolUse command: %s" % cmd)
            p = os.path.normpath(os.path.join(ROOT, m.group(1).lstrip("/")))
            if not os.path.isfile(p):
                die("PreToolUse command names a missing script: %s" % cmd)
            p = os.path.realpath(p)
            if p not in index:
                index[p] = len(entries)
                entries.append((p, []))
            if matcher not in entries[index[p]][1]:
                entries[index[p]][1].append(matcher)
    if not entries:
        die("%s has no PreToolUse command hooks" % hj)
    return entries

def main():
    hooks, totals, warnings = [], {r: 0 for r in RULE_IDS}, []
    for path, matchers in hook_entries():
        files, edges = closure(path)
        findings = []
        for f in files:
            findings += scan(f).findings
            warnings += [w for w in scan(f).warnings if w not in warnings]
        counts = {r: sum(1 for x in findings if x["rule"] == r) for r in RULE_IDS}
        for r in RULE_IDS:
            totals[r] += counts[r]
        hooks.append({"hook": os.path.relpath(path, ROOT), "matchers": matchers,
                      "closure": [os.path.relpath(f, ROOT) for f in files], "edges": edges,
                      "counts": counts, "total": sum(counts.values()), "findings": findings})
    clean = all(v == 0 for v in totals.values())
    if JSON_OUT:
        json.dump({"root": ROOT, "rules": RULES, "comments_excluded": True, "hooks": hooks,
                   "totals": totals, "total": sum(totals.values()), "clean": clean, "warnings": warnings},
                  sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        out = sys.stdout.write
        if not SUMMARY:
            out("check-hook-answers: PreToolUse closure under %s (comments excluded)\n" % ROOT)
            for r in RULE_IDS:
                out("  %s  %s\n" % (r, RULES[r]))
            for h in hooks:
                out("\n== %s  [%s]\n" % (h["hook"], ", ".join(h["matchers"])))
                out("  closure (%d files):\n" % len(h["closure"]))
                out("    %s\n" % h["hook"])
                for e in h["edges"]:
                    out("    %s%s\n" % (e["file"], ("  <- %s %s" % (e["via"], e["how"])) if VERBOSE else ""))
                for x in h["findings"]:
                    tag = " (docstring)" if x.get("docstring") else ""
                    out("  %s:%d %s%s  %s\n" % (x["file"], x["line"], x["rule"], tag, x["text"]))
            out("\n")
        width = max([len(h["hook"]) for h in hooks] + [5])
        out("%-*s  %4s  %4s  %4s  %4s  %5s\n" % (width, "hook", "r1", "r2", "r3", "r4", "total"))
        for h in hooks:
            c = h["counts"]
            out("%-*s  %4d  %4d  %4d  %4d  %5d\n" % (width, h["hook"], c["r1"], c["r2"], c["r3"], c["r4"], h["total"]))
        out("%-*s  %4d  %4d  %4d  %4d  %5d\n" % (width, "TOTAL", totals["r1"], totals["r2"], totals["r3"], totals["r4"], sum(totals.values())))
        out("result: %s\n" % ("clean" if clean else "findings"))
        for w in warnings:
            sys.stderr.write("check-hook-answers: warning: %s\n" % w)
    return 0 if clean else 1

sys.exit(main())
PY

exec python3 -I -S -c "$CHA_PY" "$ROOT" "$JSON" "$SUMMARY" "$VERBOSE" "$HOOK"
