#!/usr/bin/env bash
# test-pg-graphql.sh — hooks/lib/pg_graphql.py, the GraphQL reader behind
# hooks/permission-guard.sh's GitHub GraphQL classification (issue #349, ADR 004).
#
# WHAT IT PROVES
#   1. Every GraphQL walk-around tests/test-security-regressions.sh replays
#      (P1-e, P1-f, P1-g, P1-h) reads as a server reads it: the real root
#      fields, or ok False. P1-e's escaped keyword is fed DECODED, because
#      decoding the JSON body is the caller's job; undecoded it must still fail.
#   2. The grammar: aliases, arguments, directives, variables, fragments,
#      inline and nested fragments, comments and strings full of delimiters,
#      block strings and their one escape, numbers, ignored tokens.
#   3. Fail closed: malformed documents, type-system definitions, undefined
#      fragments, fragment cycles at any depth, ambiguous operation sets, the
#      64 KB cap, the depth cap and the resolution budget all give ok False.
#   4. The module is what its docstring claims: it imports nothing (no I/O, no
#      regular expressions), compiles, parses under Python 3.9's grammar, and
#      when a 3.9 interpreter is on the machine the whole suite runs there too.
#
# HOW IT DRIVES THE MODULE
#   The way the engine does: `python3 -I -S`, the module's directory first on
#   sys.path, `import pg_graphql`; -B keeps the import from writing a
#   __pycache__ into the tree. Each case prints one line per document,
#       <type>:<name or ->:<root,fields>:<v when uses_variables, else ->
#   joined by " | " when there are several operations, or ERR<tab><reason>.
#
# Hermetic: no network, no HOME, no gh; generated inputs go through pipes.
# Bash 3.2 compatible.
# shellcheck disable=SC2016  # every '$name' here is a GraphQL variable, literal by design
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
harness_require python3

LIB="$ROOT/hooks/lib"
MOD="$LIB/pg_graphql.py"
T="$(harness_tmpdir)"

# The driver. Modes: raw (stdin is the document), json (stdin is a JSON body: an
# object's "query", or any other JSON value handed to analyze() as it is).
DRIVER='
import json, sys
sys.path.insert(0, sys.argv[1])
import pg_graphql
raw = sys.stdin.buffer.read().decode("utf-8")
doc = raw
if sys.argv[2] == "json":
    doc = json.loads(raw)
    if isinstance(doc, dict):
        doc = doc["query"]
r = pg_graphql.analyze(doc)
if r["ok"]:
    print(" | ".join("%s:%s:%s:%s" % (o["type"], o["name"] or "-", ",".join(o["root_fields"]),
                                      "v" if o["uses_variables"] else "-") for o in r["operations"]))
else:
    print("ERR\t" + r["error"])
'

PY=python3
TAG=""

drive() { "$PY" -I -S -B -c "$DRIVER" "$LIB" "$1" 2>&1; }
gq() { printf '%s' "$1" | drive "${2:-raw}"; }
# gen <python expression> — the document a Python expression builds (sizes, depths).
gen() { "$PY" -I -S -c "import sys; sys.stdout.buffer.write(($1).encode('utf-8'))" | drive raw; }

# reads <label> <document> <expected summary> [mode]
reads() { judge "$TAG$1" "$3" "$(gq "$2" "${4:-raw}")"; }

# verdict_err <label> <output> [needle]
verdict_err() {
  case "$2" in
    ERR*)
      if [ -n "${3:-}" ] && [ "$(has "$2" "$3")" = no ]; then
        bad "$TAG$1" "rejected, but the reason lacks '$3': $2"
      else
        ok "$TAG$1"
      fi ;;
    *) bad "$TAG$1" "expected ok False, got '$2'" ;;
  esac
}
# rejects <label> <document> [needle in the reason] [mode]
rejects() { verdict_err "$1" "$(gq "$2" "${4:-raw}")" "${3:-}"; }

# A backslash-u, assembled at run time: a literal one in this file is one an editor or
# a tool layer can silently decode, which is how this suite once tested `mutation` as P1-e.
U="\\u"
# The documents tests/test-security-regressions.sh feeds the guard.
FRAG='mutation { addComment(input:{subjectId:"I",body:"x"}) { clientMutationId } ...Approve } fragment Approve on Mutation { addPullRequestReview(input:{pullRequestId:"P",event:APPROVE}) { clientMutationId } }'
FRAGJ='{"query":"mutation { addComment(input:{subjectId:\"I\",body:\"x\"}) { clientMutationId } ...A } fragment A on Mutation { addPullRequestReview(input:{pullRequestId:\"P\",event:APPROVE}) { clientMutationId } }"}'
GQ='{"query":"mutat'"$U"'0069on{deleteRepository(input:{repositoryId:\"R\"}){clientMutationId}}"}'
EXPJ='{"query":"{{m}}{deleteRepository(input:{repositoryId:\"R\"}){clientMutationId}}"}'
QS='mutation { addComment(input:{subjectId:"I",body:"("}) { clientMutationId } addPullRequestReview(input:{pullRequestId:"P",event:APPROVE}) { clientMutationId } }'
QB='mutation { addComment(input:{subjectId:"I",body:"""a ( b"""}) { clientMutationId } addPullRequestReview(input:{pullRequestId:"P",event:APPROVE}) { clientMutationId } }'
DEL='deleteRepository(input:{repositoryId:"R"}) { clientMutationId }'
APPROVE='addPullRequestReview(input:{pullRequestId:"P",event:APPROVE}) { clientMutationId }'
CMT='addComment(input:{subjectId:"I",body:"x"}) { clientMutationId }'
BOTH='mutation:-:addComment,addPullRequestReview:-'

cases() {
  # ========================================================================================
  section "${TAG}the security-regression documents (P1-e, P1-f, P1-g, P1-h)"
  # ========================================================================================
  judge "${TAG}P1-e: the body really carries the backslash escape" yes "$(has "$GQ" "mutat\\")"
  reads "P1-e: the escaped keyword, decoded from the JSON body, is a mutation" "$GQ" 'mutation:-:deleteRepository:-' json
  reads "P1-e: the same document as the caller hands it over, decoded" 'mutation{deleteRepository(input:{repositoryId:"R"}){clientMutationId}}' 'mutation:-:deleteRepository:-'
  rejects "P1-e: left undecoded, the escape is a lexical error (fails closed)" 'mutat'"$U"'0069on{deleteRepository(input:{repositoryId:"R"}){clientMutationId}}' 'U+005C'
  rejects "P1-e: a form body (query=mutation{...}) is not a document" 'query=mutation{deleteRepository}'
  reads "P1-f: a fragment spread carries addPullRequestReview" "$FRAG" "$BOTH"
  reads "P1-f: the same through a curl JSON body" "$FRAGJ" "$BOTH" json
  rejects "P1-g: an unexpanded curl {{m}} template is a syntax error" "$EXPJ" '' json
  reads "P1-h: '(' inside a string argument hides nothing" "$QS" "$BOTH"
  reads "P1-h: '(' inside a block string hides nothing" "$QB" "$BOTH"
  reads "a '#' comment holding ')' and '}' hides nothing" $'mutation { '"$CMT"$' # ) }\n '"$APPROVE"' }' "$BOTH"
  reads "an escaped quote inside a string does not end it" 'mutation { addComment(input:{subjectId:"I",body:"\" ) {"}) { clientMutationId } '"$APPROVE"' }' "$BOTH"
  reads "a string spelling '\"} mutation { ...' stays a string of a query" 'query { search(query: "\"} mutation { deleteRepository", type: REPOSITORY, first: 1) { issueCount } }' 'query:-:search:-'
  reads "a literal backslash before an escaped triple quote does not close a block string" 'mutation { addComment(input:{subjectId:"I",body:"""x \\""" deleteRepository(input:{}) { id } """}) { clientMutationId } }' 'mutation:-:addComment:-'

  # ========================================================================================
  section "${TAG}aliases, directives, fragments"
  # ========================================================================================
  reads "an alias is not the field: x: deleteRepository" 'mutation { x: '"$DEL"' }' 'mutation:-:deleteRepository:-'
  reads "an alias that names a harmless mutation: addComment: deleteRepository" 'mutation { addComment: '"$DEL"' }' 'mutation:-:deleteRepository:-'
  reads "an alias with ignored tokens around every punctuator" 'mutation { x , : deleteRepository ( input : { repositoryId : "R" } ) { clientMutationId } }' 'mutation:-:deleteRepository:-'
  reads "nested spreads resolve transitively" 'mutation { ...A } fragment A on Mutation { ...B } fragment B on Mutation { '"$APPROVE"' }' 'mutation:-:addPullRequestReview:-'
  reads "a fragment defined before the operation" 'fragment B on Mutation { mergePullRequest(input:{pullRequestId:"P"}) { clientMutationId } } mutation { ...B }' 'mutation:-:mergePullRequest:-'
  reads "an inline fragment at the root" 'mutation { ... on Mutation { '"$DEL"' } }' 'mutation:-:deleteRepository:-'
  reads "nested inline fragments, with and without a type condition or a directive" 'mutation { ... { ... on Mutation { ... @include(if: true) { '"$DEL"' } } } }' 'mutation:-:deleteRepository:-'
  reads "...on with no space is an inline fragment" 'mutation { ...on Mutation { '"$DEL"' } }' 'mutation:-:deleteRepository:-'
  reads "a spread inside an inline fragment inside a fragment" 'mutation { ... on Mutation { ...F } } fragment F on Mutation { ... { mergePullRequest(input:{pullRequestId:"P"}) { clientMutationId } } }' 'mutation:-:mergePullRequest:-'
  reads "a spread with a directive" 'mutation { ...F @include(if: true) } fragment F on Mutation { closeIssue(input:{issueId:"I"}) { clientMutationId } }' 'mutation:-:closeIssue:-'
  reads "a fragment named like a keyword (query)" 'mutation { ...query } fragment query on Mutation { '"$DEL"' }' 'mutation:-:deleteRepository:-'
  reads "@skip(if: true) is not evaluated: the field is still reported" 'mutation { deleteRepository(input:{repositoryId:"R"}) @skip(if: true) { clientMutationId } }' 'mutation:-:deleteRepository:-'
  reads "operation name, variables, defaults and directives" 'mutation Del($id: ID!, $flag: Boolean = false, $l: [String!]! = ["a"]) @op(x: 1) { deleteRepository(input:{repositoryId:$id}) @include(if: $flag) { clientMutationId } }' 'mutation:Del:deleteRepository:v'
  reads "a field selected twice is reported once" 'mutation { a: closeIssue(input:{issueId:"1"}) { clientMutationId } b: closeIssue(input:{issueId:"2"}) { clientMutationId } }' 'mutation:-:closeIssue:-'
  reads "a diamond of fragments is not a cycle" '{ ...A ...B } fragment A on Q { ...C } fragment B on Q { ...C x } fragment C on Q { c }' 'query:-:c,x:-'
  reads "a spread below the root adds no root field" 'query { viewer { ...F } } fragment F on User { login deleteRepository }' 'query:-:viewer:-'
  reads "an unused fragment is read, not reported" '{ a } fragment F on Q { b }' 'query:-:a:-'
  reads "__typename at the root of a mutation" 'mutation { __typename }' 'mutation:-:__typename:-'

  # ========================================================================================
  section "${TAG}queries, shorthand, several operations, variables"
  # ========================================================================================
  reads "shorthand query" '{ viewer { login } }' 'query:-:viewer:-'
  reads "a plain query reports only its root fields" 'query Q { repository(owner: "o", name: "n") { pullRequests(first: 5, states: [OPEN]) { nodes { title number } } } }' 'query:Q:repository:-'
  reads "nested fields named deleteRepository and mutation are not root fields" 'query { repository(owner:"o",name:"n") { deleteRepository mutation } }' 'query:-:repository:-'
  reads "a root field named mutation in a shorthand query" '{ mutation }' 'query:-:mutation:-'
  reads "an operation named like a mutation field" 'query deleteRepository { viewer { login } }' 'query:deleteRepository:viewer:-'
  reads "a comment spelling a mutation" $'# mutation { deleteRepository }\n{ viewer { login } }' 'query:-:viewer:-'
  reads "query + mutation" 'query A { viewer { login } } mutation B { '"$DEL"' }' 'query:A:viewer:- | mutation:B:deleteRepository:-'
  reads "query + mutation + subscription over shared fragments" 'query A { ...V } mutation B { ...M } subscription C { s } fragment V on Query { viewer { login } } fragment M on Mutation { mergePullRequest(input:{pullRequestId:"P"}) { clientMutationId } }' 'query:A:viewer:- | mutation:B:mergePullRequest:- | subscription:C:s:-'
  reads "a variable reached only through a nested fragment" 'query Q { ...F } fragment F on Query { viewer { ...G } } fragment G on User { repo(name: $n) { id } }' 'query:Q:viewer:v'
  reads "a declared, unused variable still counts" 'query Q($x: Int) { viewer { login } }' 'query:Q:viewer:v'
  reads "ignored tokens between \$ and the name" 'mutation ( $ id : ID ! ) { deleteRepository ( input : { repositoryId : $ id } ) { clientMutationId } }' 'mutation:-:deleteRepository:v'
  reads "uses_variables is per operation" 'query A($x: Int) { a(x: $x) } query B { b }' 'query:A:a:v | query:B:b:-'

  # ========================================================================================
  section "${TAG}lexical grammar"
  # ========================================================================================
  reads "block string: an escaped triple quote and delimiters inside" 'mutation { addComment(input:{subjectId:"I",body:"""a \""" } ( b"""}) { clientMutationId } '"$APPROVE"' }' "$BOTH"
  reads "block string across lines, with a '#' that is content" $'mutation { addComment(input:{subjectId:"I",body:"""\n  line ) }\n  # not a comment\n"""}) { clientMutationId } closeIssue(input:{issueId:"I"}) { clientMutationId } }' 'mutation:-:addComment,closeIssue:-'
  reads "every string escape, \\u{...} and a surrogate pair" '{ a(s: "\" \\ \/ \b \f \n \r \t '"$U"'00e9 \u{1F600} '"$U"D83D"$U"'DE00 é") }' 'query:-:a:-'
  reads "a comment ends at a bare CR" $'mutation { closeIssue(input:{issueId:"I"}) { clientMutationId } # c\r'"$DEL"' }' 'mutation:-:closeIssue,deleteRepository:-'
  reads "CRLF line endings and tabs" $'mutation {\r\n\tcloseIssue(input:{issueId:"I"}) { clientMutationId }\r\n}' 'mutation:-:closeIssue:-'
  reads "commas and byte order marks are ignored" $'\xef\xbb\xbf{ a, b,, \xef\xbb\xbf c }' 'query:-:a,b,c:-'
  reads "int and float values" '{ a(i: 0, j: -12, f: 1.5, e: 1e10, g: -0.5E-3, h: [1, 2.0], k: 3E+2) }' 'query:-:a:-'
  reads "list, object, enum, boolean and null values" '{ a(l: [], o: {}, n: {x: [{y: null}]}, e: OPEN, b: true, c: false) }' 'query:-:a:-'

  # ========================================================================================
  section "${TAG}malformed documents fail closed"
  # ========================================================================================
  rejects "empty document" '' 'empty'
  rejects "white space only" $'  \n\t, ' 'empty'
  rejects "a comment only" '# nothing' 'empty'
  rejects "mutation {" 'mutation {'
  rejects "missing the closing brace" 'mutation { '"$DEL"
  rejects "an extra closing brace" '{ a } }'
  rejects "an empty selection set" '{}'
  rejects "mutation with no selection set" 'mutation'
  rejects "a selection set where a field belongs" 'mutation {{ a }}'
  rejects "empty arguments" '{ a() }'
  rejects "an argument with no value" '{ a(x:) }'
  rejects "unclosed arguments" '{ a(x: 1 }'
  rejects "'..'" '{ a .. b }' 'spread'
  rejects "a lone '.'" '{ a . b }' 'spread'
  rejects "unterminated string" '{ a(s: "x) }' 'unterminated string'
  rejects "a line break inside a string" $'{ a(s: "line\nbreak") }' 'span lines'
  rejects "an invalid escape" '{ a(s: "\q") }' 'escape'
  rejects "a short \\u escape" '{ a(s: "\u12") }' 'four hex'
  rejects "an empty \\u{} escape" '{ a(s: "\u{}") }'
  rejects "\\u{110000} is past Unicode" '{ a(s: "\u{110000}") }' 'scalar'
  rejects "\\u{D800} is a surrogate" '{ a(s: "\u{D800}") }' 'scalar'
  rejects "a lone leading surrogate escape" '{ a(s: "\uD800") }' 'leading surrogate'
  rejects "a lone trailing surrogate escape" '{ a(s: "\uDC00") }' 'trailing surrogate'
  rejects "unterminated block string" '{ a(s: """x) }' 'unterminated block string'
  rejects "a raw control character inside a string" $'{ a(s: "x\x01") }' 'U+0001'
  rejects "NUL inside a string (JSON-decoded)" '"{ a(s: \"\u0000\") }"' 'U+0000' json
  rejects "a lone surrogate character (JSON-decoded)" '"{ a(s: \"\ud800\") }"' 'U+D800' json
  rejects "a leading zero" '{ a(n: 01) }' 'leading zero'
  rejects "'1.' with no fraction digit" '{ a(n: 1.) }'
  rejects "a number running into a name (1a)" '{ a(n: 1a) }'
  rejects "an exponent with no digit" '{ a(n: 1e) }'
  rejects "1.5.2" '{ a(n: 1.5.2) }'
  rejects "a bare '-'" '{ a(n: -) }'
  rejects "'.5'" '{ a(n: .5) }'
  rejects "'\$' with no name" '{ a(x: $) }'
  rejects "an unexpected character" '{ a % }' 'U+0025'
  rejects "a non-ASCII name" '{ délété }' 'U+00E9'
  rejects "a no-break space as white space" $'{ a\xc2\xa0b }' 'U+00A0'
  rejects "a type definition" 'type Query { a: Int }' 'type-system'
  rejects "a schema definition" 'schema { query: Query }'
  rejects "a type extension" 'extend type Q { a: Int }'
  rejects "a scalar definition" 'scalar Date'
  rejects "a directive definition" 'directive @x on FIELD'
  rejects "a description before an operation" '"desc" query { a }'
  rejects "an operation keyword is case-sensitive" 'Mutation { '"$DEL"' }'
  rejects "a named operation with no selection set" 'query Q'
  rejects "a fragment named 'on'" '{ ...x } fragment on on Q { a }' "named 'on'"
  rejects "a fragment with no type condition" '{ ...F } fragment F { a }'
  rejects "a fragment with variables" '{ ...F } fragment F($x: Int) on Q { a }'
  rejects "a variable in a default value" 'query($a: Int = $b) { a }' 'constant'
  rejects "a variable in a variable definition's directive" 'query($a: Int @d(x: $b)) { a }' 'constant'
  rejects "an unclosed list type" 'query($a: [Int) { a }'
  rejects "a doubled '!'" 'query($a: Int!!) { a }'
  rejects "a variable with no type" 'query($a) { a }'
  rejects "empty variable definitions" 'query() { a }'
  rejects "a spread where an operation belongs" 'mutation ...F fragment F on Mutation { a }'

  # ========================================================================================
  section "${TAG}fragment rules fail closed"
  # ========================================================================================
  rejects "an undefined fragment at the root" 'mutation { ...Missing }' "'Missing' is not defined"
  rejects "an undefined fragment below the root" 'query { viewer { ...Missing } }' 'not defined'
  rejects "an undefined fragment spread by an unused fragment" '{ a } fragment F on Q { ...Missing }' 'not defined'
  rejects "two fragments with one name" '{ ...F } fragment F on Q { a } fragment F on Q { b }' 'defined twice'
  rejects "a fragment spreading itself" '{ ...A } fragment A on Q { ...A }' 'cycle'
  rejects "a two-fragment cycle carrying a mutation" 'mutation { ...A } fragment A on Mutation { ...B } fragment B on Mutation { '"$DEL"' ...A }' 'cycle'
  rejects "a cycle through nested selections" '{ ...A } fragment A on Q { x { ...B } } fragment B on X { y { ...A } }' 'cycle'
  rejects "a cycle through an inline fragment" '{ ...A } fragment A on Q { ... on Q { ...A } }' 'cycle'
  rejects "a cycle among fragments no operation uses" '{ a } fragment A on Q { ...B } fragment B on Q { ...A }' 'cycle'

  # ========================================================================================
  section "${TAG}operation-set rules fail closed"
  # ========================================================================================
  rejects "an anonymous operation beside a named one" '{ a } query B { b }' 'anonymous'
  rejects "two anonymous operations" '{ a } { b }' 'anonymous'
  rejects "a shorthand query beside a mutation" '{ viewer { login } } mutation { '"$DEL"' }' 'anonymous'
  rejects "two operations with one name" 'query A { a } mutation A { b }' 'defined twice'
  rejects "fragments and no operation" 'fragment F on Q { a }' 'no operation'

  # ========================================================================================
  section "${TAG}limits fail closed"
  # ========================================================================================
  judge "${TAG}exactly 65536 bytes is read" 'query:-:a:-' "$(gen '"{ a }" + " " * (65536 - 5)')"
  verdict_err "65537 bytes is refused" "$(gen '"{ a }" + " " * (65537 - 5)')" 'over 65536 bytes'
  verdict_err "the cap counts UTF-8 bytes, not characters" "$(gen '"{ a } # " + chr(0xe9) * 33000')" 'over 65536 bytes'
  judge "${TAG}100 nested selection sets are read" 'query:-:a:-' "$(gen '"{" + "a{" * 99 + "b" + "}" * 100')"
  verdict_err "200 nested selection sets are refused" "$(gen '"{" + "a{" * 199 + "b" + "}" * 200')" 'deeper than 128'
  verdict_err "20000 nested list values are refused, not a crash" "$(gen '"{ a(x: " + "[" * 20000 + "]" * 20000 + ") }"')" 'deeper than 128'
  verdict_err "20000 nested list types are refused, not a crash" "$(gen '"query($v: " + "[" * 20000 + "Int" + "]" * 20000 + ") { a }"')" 'deeper than 128'
  CHAIN='"".join("fragment f%d on Q { f%d ...f%d } " % (i, i, i + 1) for i in range(199)) + "fragment f199 on Q { f199 } "'
  judge "${TAG}a 200-fragment chain under 10 operations is read, in order" \
    "$("$PY" -I -S -c 'print(" | ".join("query:q%d:%s:-" % (j, ",".join("f%d" % i for i in range(200))) for j in range(10)))')" \
    "$(gen "$CHAIN"' + "".join("query q%d { ...f0 } " % i for i in range(10))')"
  verdict_err "a fragment chain past the step budget is refused" \
    "$(gen '"".join("fragment f%d on Q { f%d ...f%d } " % (i, i, i + 1) for i in range(999)) + "fragment f999 on Q { f999 } " + "".join("query q%d { ...f0 } " % i for i in range(150))')" 'steps'
}

cases

# ==========================================================================================
section "the module itself"
# ==========================================================================================
judge "it imports nothing (so no I/O and no regular expressions)" "none" "$(python3 -I -S -c '
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
mods = set()
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        mods |= {a.name.split(".")[0] for a in node.names}
    elif isinstance(node, ast.ImportFrom):
        mods.add(node.module or "")
print(",".join(sorted(mods)) or "none")' "$MOD" 2>&1)"
judge "it names no I/O or code-loading builtin" "none" "$(python3 -I -S -c '
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
banned = {"open", "print", "input", "exec", "eval", "compile", "__import__", "breakpoint", "globals", "vars"}
hits = sorted({n.id for n in ast.walk(tree) if isinstance(n, ast.Name) and n.id in banned})
print(",".join(hits) or "none")' "$MOD" 2>&1)"
judge "py_compile accepts it" "compiled" "$(python3 -I -S -c '
import py_compile, sys
py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)
print("compiled")' "$MOD" "$T/pg_graphql.pyc" 2>&1)"
judge "it parses under Python 3.9's grammar" "ok" "$(python3 -I -S -c '
import ast, sys
ast.parse(open(sys.argv[1], encoding="utf-8").read(), filename=sys.argv[1], feature_version=(3, 9))
print("ok")' "$MOD" 2>&1)"
judge "analyze() keeps its documented shape, and is deterministic" "shape ok" "$(python3 -I -S -B -c '
import sys
sys.path.insert(0, sys.argv[1])
from pg_graphql import analyze
good = analyze("mutation M($x: ID) { a: deleteRepository(input: {id: $x}) { clientMutationId } }")
assert set(good) == {"ok", "operations", "error"} and good["ok"] is True and good["error"] is None, good
op = good["operations"][0]
assert set(op) == {"type", "name", "root_fields", "uses_variables"}, op
assert op == {"type": "mutation", "name": "M", "root_fields": ["deleteRepository"], "uses_variables": True}, op
bad = analyze("{")
assert bad["ok"] is False and bad["operations"] == [] and isinstance(bad["error"], str) and bad["error"], bad
for v in (None, b"{ a }", 1, ["{ a }"]):
    r = analyze(v)
    assert r == {"ok": False, "operations": [], "error": "the document is not a string"}, (v, r)
assert analyze("{ a }") == analyze("{ a }")
print("shape ok")' "$LIB" 2>&1)"

# The whole suite again under a Python 3.9 interpreter, the oldest the module supports.
PY39=""
for c in python3.9 /usr/bin/python3; do
  if command -v "$c" >/dev/null 2>&1 \
     && "$c" -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 9) else 1)' 2>/dev/null; then
    PY39="$c"
    break
  fi
done
if python3 -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 9) else 1)' 2>/dev/null; then
  skip "Python 3.9 rerun" "python3 is itself 3.9: the run above was the 3.9 run"
elif [ -n "$PY39" ]; then
  PY="$PY39"
  TAG="[3.9] "
  cases
else
  skip "Python 3.9 rerun" "no Python 3.9 interpreter on this machine; the feature_version=(3, 9) parse above still ran"
fi

harness_summary
