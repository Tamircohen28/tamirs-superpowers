"""pg_graphql — read a GraphQL executable document the way a GraphQL server reads it.

hooks/permission-guard.sh uses this to learn which root fields a GitHub GraphQL
call (`gh api graphql -f query=...`, a JSON body POSTed to /graphql) would run,
so a mutation is classified by the fields it really selects (ADR 004, issue #349).

    analyze(doc) -> {
        "ok":         bool,
        "operations": [{"type":           "query" | "mutation" | "subscription",
                        "name":           str | None,
                        "root_fields":    [str, ...],
                        "uses_variables": bool}, ...],
        "error":      str | None,
    }

WHY A LEXER AND A PARSER, NOT A SCANNER
    The engine's first GraphQL reader found `mutation` with a regular expression
    and counted braces after it. Review rounds kept finding documents it read
    differently from the server: a JSON-escaped keyword, a fragment carrying the
    real mutation, a `(` inside a string argument that hid every field after it,
    the same inside a block string. Each fix taught the scanner one more corner
    of the grammar. This module is the grammar instead — the lexical syntax and
    the executable-document syntax of the GraphQL specification, October 2021
    edition — so a delimiter inside a string or a comment is never a delimiter,
    an alias is never mistaken for the field, and a fragment is resolved rather
    than guessed at.

THE CONTRACT: FAIL CLOSED
    ok is True only when the whole document lexes, parses, and every fragment it
    spreads resolves. Anything else is ok False, operations [] and a reason:
      - any lexical or syntax error, including a type-system definition (an
        executable document cannot carry one) and a description string;
      - a spread of an undefined fragment, or two fragments with one name;
      - a fragment cycle, at any depth, whether or not an operation uses it
        (the spec's "Fragment spreads must not form cycles");
      - an anonymous operation beside another one, or two operations with one
        name ("Lone Anonymous Operation", "Operation Name Uniqueness"): the
        server refuses such a document, and the caller must never have to guess
        which operation an `operationName` it cannot see would pick;
      - a document with no operation at all;
      - input over MAX_BYTES of UTF-8, nesting deeper than MAX_DEPTH, or
        fragment resolution needing more than MAX_STEPS steps;
      - an argument that is not a str.
    The caller turns ok False into UNCLASSIFIED. Where this reader is stricter
    than a server (a control character inside a string, U+00A0 as white space,
    `1a` with no space) the cost is a question to the user, never a wrong
    answer, which is the only direction a guard may err in.

WHAT root_fields MEANS
    The field names — never the aliases — an operation selects at its top
    level: `x: deleteRepository(...)` reports `deleteRepository`. A fragment
    spread or an inline fragment at the top level is resolved transitively, so
    `mutation { ...A } fragment A on Mutation { ...B } fragment B on Mutation
    { addPullRequestReview(...) }` reports `addPullRequestReview`. Directives
    are not evaluated: a field under `@skip(if: true)` is still reported,
    because whether it runs can turn on a variable this module never sees, and
    over-reporting a field asks where under-reporting one would allow. A type
    condition is not checked either, for the same reason. Each name appears
    once, in first-seen order. Fields below the top level are not reported: a
    nested field that happens to share a mutation's name is not a mutation.

    uses_variables is True when the operation declares a variable or refers to
    one anywhere in its own body or in any fragment it reaches, at any depth.

WHAT IT DOES NOT DO
    It does not decode JSON: a JSON-escaped keyword (`mutat\\u0069on`) is the
    caller's to decode first — undecoded it is a lexical error here, so it still
    fails closed. It does not validate against a schema and does not expand
    templates (curl's `{{name}}` is a syntax error). It performs no I/O and
    imports nothing; it is a pure function of its argument and runs on Python
    3.9 and later.
"""

MAX_BYTES = 64 * 1024     # the document, measured as UTF-8
MAX_DEPTH = 128           # nested selection sets, list/object values and list types
MAX_STEPS = 200000        # fragment-resolution work across every operation

_OPERATION_TYPES = ("query", "mutation", "subscription")
_NAME_START = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_")
_DIGITS = frozenset("0123456789")
_NAME_CONTINUE = _NAME_START | _DIGITS
_HEX = frozenset("0123456789abcdefABCDEF")
_PUNCTUATORS = frozenset("!$&():=@[]{|}")     # `...` is the one multi-character punctuator
_IGNORED = frozenset(" \t\n\r," + chr(0xFEFF))   # white space, line terminators, comma, byte order mark
_ESCAPES = frozenset('"\\/bfnrt')


class _Reject(Exception):
    """The document is not one this module can read; `pos` is a character offset or None."""

    def __init__(self, pos, why):
        Exception.__init__(self, why)
        self.pos = pos
        self.why = why


def _where(src, pos):
    if pos is None:
        return ""
    line, line_start, k = 1, 0, 0
    while k < pos:
        c = src[k]
        if c == "\n" or (c == "\r" and src[k + 1:k + 2] != "\n"):
            line, line_start = line + 1, k + 1
        k += 1
    return " (line %d, column %d)" % (line, pos - line_start + 1)


def _describe(tok):
    kind, value = tok[0], tok[1]
    if kind == "eof":
        return "the end of the document"
    if kind == "punct":
        return "'%s'" % value
    if kind == "name":
        return "name '%s'" % (value if len(value) <= 40 else value[:40] + "...")
    if kind == "string":
        return "a string"
    return "the number %s" % value[:40]


# --------------------------------------------------------------------------------------------------
# Lexer: the October 2021 lexical grammar. Tokens are (kind, value, offset); kind is one of
# punct, name, int, float, string, eof. String values are validated, never decoded: no caller
# needs one, and the boundary of the string is the only thing that decides what is code.
# --------------------------------------------------------------------------------------------------

def _check_char(src, i):
    """SourceCharacter inside a string or a comment. Stricter than the spec on purpose: a C0
    control other than tab is refused, and so is a lone surrogate (not a Unicode scalar value)."""
    o = ord(src[i])
    if (o < 0x20 and o != 0x09) or 0xD800 <= o <= 0xDFFF:
        raise _Reject(i, "character U+%04X is not allowed here" % o)


def _skip_digits(src, i):
    n = len(src)
    while i < n and src[i] in _DIGITS:
        i += 1
    return i


def _lex_number(src, i, toks):
    """IntValue / FloatValue, with the spec's lookahead: no digit, `.` or name start may follow."""
    start, n = i, len(src)
    if src[i] == "-":
        i += 1
    if i >= n or src[i] not in _DIGITS:
        raise _Reject(start, "'-' must begin a number")
    if src[i] == "0":
        i += 1
        if i < n and src[i] in _DIGITS:
            raise _Reject(start, "a number cannot have a leading zero")
    else:
        i = _skip_digits(src, i)
    kind = "int"
    if i < n and src[i] == ".":
        i += 1
        if i >= n or src[i] not in _DIGITS:
            raise _Reject(i, "a fraction needs a digit after '.'")
        i, kind = _skip_digits(src, i), "float"
    if i < n and src[i] in "eE":
        i += 1
        if i < n and src[i] in "+-":
            i += 1
        if i >= n or src[i] not in _DIGITS:
            raise _Reject(i, "an exponent needs a digit")
        i, kind = _skip_digits(src, i), "float"
    if i < n and (src[i] == "." or src[i] in _NAME_START):
        raise _Reject(i, "a number cannot be followed by '.' or a name character")
    toks.append((kind, src[start:i], start))
    return i


def _hex4(src, k):
    h = src[k:k + 4]
    if len(h) != 4 or any(c not in _HEX for c in h):
        return None
    return int(h, 16)


def _lex_unicode_escape(src, i):
    """`\\uXXXX` (a surrogate only as a leading+trailing pair) or `\\u{X...}` (a scalar value)."""
    k = i + 2
    if src[k:k + 1] == "{":
        j, n = k + 1, len(src)
        while j < n and src[j] in _HEX:
            j += 1
        if j == k + 1 or src[j:j + 1] != "}":
            raise _Reject(i, "a \\u{...} escape needs hex digits and a closing '}'")
        cp = int(src[k + 1:j], 16)
        if cp > 0x10FFFF or 0xD800 <= cp <= 0xDFFF:
            raise _Reject(i, "a \\u{...} escape must name a Unicode scalar value")
        return j + 1
    cp = _hex4(src, k)
    if cp is None:
        raise _Reject(i, "a \\u escape needs four hex digits")
    k += 4
    if 0xDC00 <= cp <= 0xDFFF:
        raise _Reject(i, "a trailing surrogate escape with no leading surrogate before it")
    if 0xD800 <= cp <= 0xDBFF:
        low = _hex4(src, k + 2) if src[k:k + 2] == "\\u" else None
        if low is None or not 0xDC00 <= low <= 0xDFFF:
            raise _Reject(i, "a leading surrogate escape with no trailing surrogate after it")
        k += 6
    return k


def _lex_string(src, i):
    start, n = i, len(src)
    i += 1
    while True:
        if i >= n:
            raise _Reject(start, "unterminated string")
        c = src[i]
        if c == '"':
            return i + 1
        if c == "\n" or c == "\r":
            raise _Reject(i, "a string cannot span lines (a block string can)")
        if c == "\\":
            e = src[i + 1:i + 2]
            if e == "u":
                i = _lex_unicode_escape(src, i)
            elif e in _ESCAPES:
                i += 2
            else:
                raise _Reject(i, "invalid escape sequence in a string")
            continue
        _check_char(src, i)
        i += 1


def _lex_block_string(src, i):
    """A block string: a backslash before three quotes is the only escape; any other backslash is a
    literal character, and line terminators are content."""
    start, n = i, len(src)
    i += 3
    while True:
        if i >= n:
            raise _Reject(start, "unterminated block string")
        c = src[i]
        if c == '"' and src[i:i + 3] == '"""':
            return i + 3
        if c == "\\" and src[i + 1:i + 4] == '"""':
            i += 4
            continue
        if c != "\n" and c != "\r":
            _check_char(src, i)
        i += 1


def _lex(src):
    toks, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c in _IGNORED:
            i += 1
        elif c == "#":
            i += 1
            while i < n and src[i] != "\n" and src[i] != "\r":
                _check_char(src, i)
                i += 1
        elif c in _PUNCTUATORS:
            toks.append(("punct", c, i))
            i += 1
        elif c == ".":
            if src[i:i + 3] != "...":
                raise _Reject(i, "'.' is only valid as the spread '...'")
            toks.append(("punct", "...", i))
            i += 3
        elif c in _NAME_START:
            j = i + 1
            while j < n and src[j] in _NAME_CONTINUE:
                j += 1
            toks.append(("name", src[i:j], i))
            i = j
        elif c == "-" or c in _DIGITS:
            i = _lex_number(src, i, toks)
        elif c == '"':
            j = _lex_block_string(src, i) if src[i:i + 3] == '"""' else _lex_string(src, i)
            toks.append(("string", None, i))
            i = j
        else:
            raise _Reject(i, "unexpected character U+%04X" % ord(c))
    toks.append(("eof", None, n))
    return toks


# --------------------------------------------------------------------------------------------------
# Parser: the executable-document grammar. Recursive descent, bounded by MAX_DEPTH.
# --------------------------------------------------------------------------------------------------

class _Body:
    """What one operation or fragment definition carries.

    root            ("field" | "spread", name) at the top level, inline fragments flattened in
    spreads         every fragment it spreads at any depth, name -> offset of the first spread
    uses_variables  a variable is declared or referenced in it
    """

    __slots__ = ("root", "spreads", "uses_variables")

    def __init__(self):
        self.root = []
        self.spreads = {}
        self.uses_variables = False


class _Parser:
    def __init__(self, toks):
        self.toks = toks
        self.k = 0
        self.depth = 0
        self.operations = []    # (type, name, body, offset)
        self.fragments = {}     # name -> body

    def _peek(self):
        return self.toks[self.k]

    def _take(self):
        tok = self.toks[self.k]
        if tok[0] != "eof":
            self.k += 1
        return tok

    def _at(self, punct):
        tok = self.toks[self.k]
        return tok[0] == "punct" and tok[1] == punct

    def _expect(self, punct):
        tok = self._take()
        if tok[0] != "punct" or tok[1] != punct:
            raise _Reject(tok[2], "expected '%s', found %s" % (punct, _describe(tok)))

    def _name(self):
        tok = self._take()
        if tok[0] != "name":
            raise _Reject(tok[2], "expected a name, found %s" % _describe(tok))
        return tok[1]

    def _keyword(self, word):
        tok = self._take()
        if tok[0] != "name" or tok[1] != word:
            raise _Reject(tok[2], "expected '%s', found %s" % (word, _describe(tok)))

    def _enter(self, pos):
        self.depth += 1
        if self.depth > MAX_DEPTH:
            raise _Reject(pos, "the document nests deeper than %d levels" % MAX_DEPTH)

    def document(self):
        if self._peek()[0] == "eof":
            raise _Reject(None, "the document is empty")
        while self._peek()[0] != "eof":
            self._definition()

    def _definition(self):
        tok = self._peek()
        if tok[0] == "punct" and tok[1] == "{":
            body = _Body()
            self._selection_set(body, True)
            self.operations.append(("query", None, body, tok[2]))
            return
        if tok[0] == "name" and tok[1] in _OPERATION_TYPES:
            self._take()
            name = self._take()[1] if self._peek()[0] == "name" else None
            body = _Body()
            if self._at("("):
                self._variable_definitions(body)
            self._directives(body, False)
            self._selection_set(body, True)
            self.operations.append((tok[1], name, body, tok[2]))
            return
        if tok[0] == "name" and tok[1] == "fragment":
            self._take()
            name_tok = self._peek()
            name = self._name()
            if name == "on":
                raise _Reject(name_tok[2], "a fragment cannot be named 'on'")
            self._keyword("on")
            self._name()
            body = _Body()
            self._directives(body, False)
            self._selection_set(body, True)
            if name in self.fragments:
                raise _Reject(name_tok[2], "fragment '%s' is defined twice" % name)
            self.fragments[name] = body
            return
        raise _Reject(tok[2], "expected an operation or a fragment, found %s (an executable document carries "
                              "no type-system definitions)" % _describe(tok))

    def _selection_set(self, body, at_root):
        tok = self._peek()
        self._expect("{")
        self._enter(tok[2])
        while True:
            self._selection(body, at_root)
            if self._at("}"):
                self._take()
                break
        self.depth -= 1

    def _selection(self, body, at_root):
        if self._at("..."):
            self._take()
            tok = self._peek()
            if tok[0] == "name" and tok[1] != "on":          # ...FragmentName
                self._take()
                body.spreads.setdefault(tok[1], tok[2])
                if at_root:
                    body.root.append(("spread", tok[1]))
                self._directives(body, False)
                return
            if tok[0] == "name":                             # ... on Type
                self._take()
                self._name()
            self._directives(body, False)
            self._selection_set(body, at_root)               # an inline fragment stays at its level
            return
        name = self._name()
        if self._at(":"):                                    # alias: name
            self._take()
            name = self._name()
        if at_root:
            body.root.append(("field", name))
        if self._at("("):
            self._arguments(body, False)
        self._directives(body, False)
        if self._at("{"):
            self._selection_set(body, False)

    def _arguments(self, body, const):
        self._expect("(")
        while True:
            self._name()
            self._expect(":")
            self._value(body, const)
            if self._at(")"):
                self._take()
                return

    def _directives(self, body, const):
        while self._at("@"):
            self._take()
            self._name()
            if self._at("("):
                self._arguments(body, const)

    def _value(self, body, const):
        tok = self._take()
        kind, value, pos = tok
        if kind in ("name", "int", "float", "string"):       # names are true/false/null/enum values
            return
        if kind == "punct" and value == "$":
            if const:
                raise _Reject(pos, "a variable cannot appear in a constant value")
            self._name()
            body.uses_variables = True
            return
        if kind == "punct" and value == "[":
            self._enter(pos)
            while not self._at("]"):
                self._value(body, const)
            self._take()
            self.depth -= 1
            return
        if kind == "punct" and value == "{":
            self._enter(pos)
            while not self._at("}"):
                self._name()
                self._expect(":")
                self._value(body, const)
            self._take()
            self.depth -= 1
            return
        raise _Reject(pos, "expected a value, found %s" % _describe(tok))

    def _variable_definitions(self, body):
        self._expect("(")
        while True:
            self._expect("$")
            self._name()
            body.uses_variables = True
            self._expect(":")
            self._type()
            if self._at("="):
                self._take()
                self._value(body, True)
            self._directives(body, True)
            if self._at(")"):
                self._take()
                return

    def _type(self):
        tok = self._peek()
        if self._at("["):
            self._take()
            self._enter(tok[2])
            self._type()
            self._expect("]")
            self.depth -= 1
        else:
            self._name()
        if self._at("!"):
            self._take()


# --------------------------------------------------------------------------------------------------
# Resolution: document-level rules, then each operation's root fields. Iterative, so a long
# fragment chain cannot exhaust the interpreter's stack, and metered by MAX_STEPS.
# --------------------------------------------------------------------------------------------------

def _spend(budget):
    budget[0] -= 1
    if budget[0] < 0:
        raise _Reject(None, "resolving the document's fragments needs more than %d steps" % MAX_STEPS)


def _reject_cycles(frags):
    state = {}      # name -> 1 while on the DFS path, 2 when finished
    for start in frags:
        if start in state:
            continue
        state[start] = 1
        stack = [(start, iter(frags[start].spreads))]
        while stack:
            node, edges = stack[-1]
            nxt = next(edges, None)
            if nxt is None:
                state[node] = 2
                stack.pop()
                continue
            seen = state.get(nxt)
            if seen == 1:
                raise _Reject(frags[node].spreads[nxt],
                              "fragment '%s' reaches itself through '%s' (a fragment cycle)" % (nxt, node))
            if seen is None:
                state[nxt] = 1
                stack.append((nxt, iter(frags[nxt].spreads)))


def _root_fields(body, frags, budget):
    names, seen, spread = [], set(), set()
    stack = [iter(body.root)]
    while stack:
        item = next(stack[-1], None)
        if item is None:
            stack.pop()
            continue
        _spend(budget)
        kind, name = item
        if kind == "field":
            if name not in seen:
                seen.add(name)
                names.append(name)
        elif name not in spread:
            spread.add(name)
            stack.append(iter(frags[name].root))
    return names


def _uses_variables(body, frags, budget):
    if body.uses_variables:
        return True
    seen, todo = set(), list(body.spreads)
    while todo:
        _spend(budget)
        name = todo.pop()
        if name in seen:
            continue
        seen.add(name)
        if frags[name].uses_variables:
            return True
        todo.extend(frags[name].spreads)
    return False


def _resolve(parser):
    ops, frags = parser.operations, parser.fragments
    if not ops:
        raise _Reject(None, "the document defines no operation")
    if len(ops) > 1:
        names = set()
        for _, name, _, pos in ops:
            if name is None:
                raise _Reject(pos, "an anonymous operation must be the only operation in the document")
            if name in names:
                raise _Reject(pos, "operation '%s' is defined twice" % name)
            names.add(name)
    for body in [op[2] for op in ops] + list(frags.values()):
        for name, pos in body.spreads.items():
            if name not in frags:
                raise _Reject(pos, "fragment '%s' is not defined" % name)
    _reject_cycles(frags)
    budget = [MAX_STEPS]
    return [{"type": typ, "name": name, "root_fields": _root_fields(body, frags, budget),
             "uses_variables": _uses_variables(body, frags, budget)}
            for typ, name, body, _ in ops]


def _fail(why):
    return {"ok": False, "operations": [], "error": why}


def analyze(doc):
    """Read `doc` (a GraphQL executable document, already JSON-decoded). See the module docstring."""
    if not isinstance(doc, str):
        return _fail("the document is not a string")
    try:
        if len(doc) > MAX_BYTES or len(doc.encode("utf-8", "surrogatepass")) > MAX_BYTES:
            raise _Reject(None, "the document is over %d bytes" % MAX_BYTES)
        parser = _Parser(_lex(doc))
        parser.document()
        return {"ok": True, "operations": _resolve(parser), "error": None}
    except _Reject as e:
        return _fail(e.why + _where(doc, e.pos))
    except RecursionError:
        return _fail("the document nests too deeply to read")
    except Exception as e:      # a defect here must never read as a clean document
        return _fail("the GraphQL reader failed (%s)" % type(e).__name__)
