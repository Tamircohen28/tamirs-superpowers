#!/usr/bin/env bash
# test-pg-http.sh — hooks/lib/pg_http.py, the table-driven argv model of curl, wget,
# httpie, xh and gh api that permission-guard reads HTTP client calls with (issue #349).
#
# WHAT IT PROVES
#   1. Every HTTP-client walk-around of the PR #348 reviews (the F8, P1 and P1-a ... P1-i
#      rows of tests/test-security-regressions.sh) reads as the request the client would
#      really send: the method its body implies, every URL, the body as curl assembles it,
#      or UNKNOWN where the words cannot show it (a file, stdin, a template, an override).
#   2. Each client's own option forms: attached, separate and clustered for every value
#      option with a role; --opt=value; curl --next groups, URL globs, --url, --expand-*,
#      -K, -G; wget -e, long-option prefixes, -n letters; httpie/xh METHOD words, request
#      items and stdin; gh api's pflag forms.
#   3. Fail-closed: an option the table does not list, a missing value, a combination the
#      client refuses make the call unknown — never a guessed flag that could swallow a URL.
#   4. Ordinary calls (plain GETs, `curl -sSL <url> -o out`) stay ok and known.
#   5. The tables agree with the installed tools: `curl --help all`, `gh api --help`, and
#      `wget --help` where GNU Wget is installed; a listed option whose help says it takes
#      a value (or does not) the other way fails, an option the table lacks only warns
#      (the module reads it as unknown, which is the safe side).
#   6. The module is Python 3.9 syntax, stdlib only, and does no I/O.
#
# HOW
#   One python3 pass computes every row (argv lists are Python literals, so no shell
#   quoting is in the way) and prints label/expected/actual; bash judges each line. The
#   pass must report the row count it printed, so a crash cannot read as a vacuous pass.
#   Python runs with -B and compiles into the temp dir: nothing is written into the tree.
#
# HERMETIC
#   Nothing is sent anywhere: the module is only asked about words. The only commands run
#   are `curl --help all`, `curl --version`, `gh api --help` and `wget --help`/`--version`.
#
# Bash 3.2 compatible.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$HERE/tests/lib/harness.sh"
harness_require python3

LIB="$HERE/hooks/lib/pg_http.py"
T="$(harness_tmpdir)"

# judge_rows <file> — judge every "label<TAB>expected<TAB>actual" line; the last line is "END<TAB><count>".
judge_rows() {
  local label want got n=0 end=""
  while IFS="$(printf '\t')" read -r label want got; do
    if [ "$label" = END ]; then end="$want"; continue; fi
    judge "$label" "$want" "$got"
    n=$((n + 1))
  done < "$1"
  judge "the row pass reported every row it printed" "$end" "$n"
}

section "the module compiles and imports"
judge "py_compile" ok "$(python3 -B -c 'import py_compile,sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)' "$LIB" "$T/pg_http.pyc" 2>&1 && echo ok)"
judge "importing it prints nothing" "" "$(python3 -B -I -S -c 'import importlib.util,sys
s=importlib.util.spec_from_file_location("pg_http",sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)' "$LIB" 2>&1)"

python3 -B -I -S - "$LIB" > "$T/rows.tsv" 2> "$T/rows.err" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("pg_http", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

ROWS = []
REPO = "https://api.github.com/repos/me/app"
REL, ISS, REV, GQL = REPO + "/releases", REPO + "/issues", REPO + "/pulls/1/reviews", "https://api.github.com/graphql"
MERGE = "api.github.com/repos/a/b/pulls/1/merge"


def yn(v):
    return "yes" if v else "no"


def show(v):
    if v is True or v is False:
        return yn(v)
    if v is None:
        return "none"
    if isinstance(v, str):
        return v
    return json.dumps(v, separators=(",", ":"))


# The facts a row can check: S is "<methods> known|unknown", the one most rows assert.
FACTS = {
    "S": lambda r: ",".join(str(q["method"]) for q in r["requests"]) + " " + ("unknown" if r["unknown"] else "known"),
    "ok": lambda r: yn(r["ok"]),
    "unknown": lambda r: yn(r["unknown"]),
    "targets": lambda r: yn(r["targets_unknown"]),
    "urls": lambda r: [u for q in r["requests"] for u in q["urls"]],
    "groups": lambda r: [q["urls"] for q in r["requests"]],
    "body": lambda r: r["requests"][0]["body"] if r["requests"] else "no request",
    "fields": lambda r: r["requests"][0]["fields"] if r["requests"] else "no request",
    "bodyu": lambda r: [yn(q["body_unknown"]) for q in r["requests"]],
    "route": lambda r: [yn(q["route_override"]) for q in r["requests"]],
    "routes": lambda r: [x for q in r["requests"] for x in q["routes"]],
    "headers": lambda r: [h for q in r["requests"] for h in q["headers"]],
    "nreq": lambda r: len(r["requests"]),
    "cfg": lambda r: yn(r["default_config"]),
}


def row(label, want, prog, *argv, **kw):
    fact = kw.get("f", "S")
    try:
        got = show(FACTS[fact](m.parse(prog, list(argv))))
    except Exception as e:   # a row that crashes the module fails, it does not vanish
        got = "CRASH %s: %s" % (type(e).__name__, e)
    ROWS.append(("%s [%s]" % (label, fact), show(want), got))


# ===== 1. the review's walk-arounds ===================================================================
# F8: methods are read in any case, httpie/xh take the method as their first word.
row("F8 curl -X PUT https://API.GITHUB.COM/.../merge", "PUT known", "curl", "-X", "PUT",
    "https://API.GITHUB.COM/repos/acme/app/pulls/1/merge")
row("F8 http PUT api.github.com/.../merge: a PUT whose body may be stdin", "PUT unknown", "http", "PUT", MERGE)
row("F8   ... the URL is the second word", [MERGE], "http", "PUT", MERGE, f="urls")
row("F8 http --ignore-stdin PUT .../merge: a PUT, known", "PUT known", "http", "--ignore-stdin", "PUT", MERGE)
row("F8 xh PUT .../merge", "PUT unknown", "xh", "PUT", MERGE)
row("F8 xh -I PUT .../merge", "PUT known", "xh", "-I", "PUT", MERGE)
row("F8 http put (lower case) is PUT", "PUT known", "http", "-I", "put", MERGE)

# P1: an attached or clustered body is a POST.
for argv in (['-d{"tag_name":"v1"}', REL], ['--data={"tag_name":"v1"}', REL], ["-sd", '{"tag_name":"v1"}', REL]):
    row("P1 curl %s" % argv[0], "POST known", "curl", *argv)
    row("P1   ... its body's fields", ["tag_name=v1"], "curl", *argv, f="fields")
row("P1 curl -F name=v1 .../releases", "POST known", "curl", "-F", "name=v1", REL)
row("P1   ... the form field", ["name=v1"], "curl", "-F", "name=v1", REL, f="fields")

# P1-a: gh api pflag forms, curl --expand-*, wget -e.
for argv in (["-ftag_name=v1"], ["-Ftag_name=v1"], ["-f=tag_name=v1"], ["--field=tag_name=v1"],
             ["--raw-field=tag_name=v1"]):
    row("P1-a gh api .../releases %s" % argv[0], "POST known", "gh", "api", "repos/me/app/releases", *argv)
    row("P1-a   ... field", ["tag_name=v1"], "gh", "api", "repos/me/app/releases", *argv, f="fields")
row("P1-a gh api .../releases --input=body.json: a POST whose body is a file", "POST unknown", "gh", "api",
    "repos/me/app/releases", "--input=body.json")
row("P1-a gh api -HAccept:x .../releases -ftag_name=v1", "POST known", "gh", "api", "-HAccept:x",
    "repos/me/app/releases", "-ftag_name=v1")
row("P1-a   ... the header is -H's attached value, not the endpoint", ["repos/me/app/releases"], "gh", "api",
    "-HAccept:x", "repos/me/app/releases", "-ftag_name=v1", f="urls")
row("P1-a   ... and is a header", ["Accept:x"], "gh", "api", "-HAccept:x", "repos/me/app/releases",
    "-ftag_name=v1", f="headers")
row("P1-a gh api -iXDELETE repos/me/app (a pflag cluster)", "DELETE known", "gh", "api", "-iXDELETE", "repos/me/app")
row("P1-a curl --expand-data '{...}' (no template) is --data", "POST known", "curl", "--expand-data",
    '{"tag_name":"v1"}', REL)
row("P1-a   ... fields", ["tag_name=v1"], "curl", "--expand-data", '{"tag_name":"v1"}', REL, f="fields")
row("P1-a curl --expand-request DELETE repos/me/app", "DELETE known", "curl", "--expand-request", "DELETE", REPO)
row("P1-a wget -e method=DELETE repos/me/app", "DELETE known", "wget", "-e", "method=DELETE", REPO)
row("P1-a wget -qe post_data=x .../releases", "POST known", "wget", "-qe", "post_data=x", REL)
row("P1-a   ... body", "x", "wget", "-qe", "post_data=x", REL, f="body")

# P1-b: every URL of a multi-transfer call.
row("P1-b curl -X POST -d '{...}' .../issues .../releases", [ISS, REL], "curl", "-X", "POST", "-d",
    '{"title":"x","tag_name":"v1"}', ISS, REL, f="urls")
row("P1-b curl -d '{...}' --url .../issues --url .../releases", [ISS, REL], "curl", "-d", '{"tag_name":"v1"}',
    "--url", ISS, "--url", REL, f="urls")
row("P1-b wget --post-data '{...}' .../issues .../releases", [ISS, REL], "wget", "--post-data",
    '{"tag_name":"v1"}', ISS, REL, f="urls")
row("P1-b   ... both POSTed", "POST known", "wget", "--post-data", '{"tag_name":"v1"}', ISS, REL)
row("P1-b gh api .../issues .../releases -f ...: both endpoints", ["repos/me/app/issues", "repos/me/app/releases"],
    "gh", "api", "repos/me/app/issues", "repos/me/app/releases", "-f", "title=x", "-f", "tag_name=v1", f="urls")
row("P1-b   ... and gh refuses two, so the targets are unknown", "yes", "gh", "api", "repos/me/app/issues",
    "repos/me/app/releases", "-f", "title=x", f="targets")
row("P1-b curl -X DELETE <repo> --next -X GET .../issues: one method per group", "DELETE,GET known", "curl", "-X",
    "DELETE", REPO, "--next", "-X", "GET", ISS)
row("P1-b   ... each group its own URL", [[REPO], [ISS]], "curl", "-X", "DELETE", REPO, "--next", "-X", "GET", ISS,
    f="groups")
row("P1-b curl -d x .../issues '.../{releases,x}' (a URL glob) expands", [ISS, REL, REPO + "/x"], "curl", "-d", "x",
    ISS, REPO + "/{releases,x}", f="urls")
row("P1-b curl -d x .../issues --expand-url '{{u}}' --variable u=...: unknown", "POST unknown", "curl", "-d", "x", ISS,
    "--expand-url", "{{u}}", "--variable", "u=" + REL)
row("P1-b curl -K cfg.txt (URLs from a file)", "yes", "curl", "-K", "cfg.txt", f="unknown")
row("P1-b curl -sK cfg.txt https://example.com", "GET unknown", "curl", "-sK", "cfg.txt", "https://example.com")
row("P1-b wget -i urls.txt (URLs from a file)", "yes", "wget", "-i", "urls.txt", f="unknown")

# P1-c: a request-target or route override.
for label, argv in (
        ("--json ... --request-target /...releases .../issues",
         ["--json", '{"tag_name":"v1","title":"x"}', "--request-target", "/repos/me/app/releases", ISS]),
        ("-d x --request-target=/...releases .../issues", ["-d", "x", "--request-target=/repos/me/app/releases", ISS]),
        ("-X POST -d x --connect-to example.com:443:api.github.com:443 https://example.com/...",
         ["-X", "POST", "-d", "x", "--connect-to", "example.com:443:api.github.com:443",
          "https://example.com/repos/me/app/releases"]),
        ("-X POST -d x -H 'Host: api.github.com' https://203.0.113.5/...",
         ["-X", "POST", "-d", "x", "-H", "Host: api.github.com", "https://203.0.113.5/repos/me/app/releases"]),
        ("-X POST -d x --header='host: api.github.com' https://203.0.113.5/...",
         ["-X", "POST", "-d", "x", "--header=host: api.github.com", "https://203.0.113.5/repos/me/app/releases"]),
        ("-d x --unix-socket /tmp/s .../issues", ["-d", "x", "--unix-socket", "/tmp/s", ISS])):
    row("P1-c curl %s: a route override" % label, ["yes"], "curl", *argv, f="route")
    row("P1-c   ... so the call is unknown", "yes", "curl", *argv, f="unknown")
row("P1-c the override is reported as written", ["--connect-to example.com:443:api.github.com:443"], "curl", "-d",
    "x", "--connect-to", "example.com:443:api.github.com:443", "https://example.com/x", f="routes")

# P1-d: a body read from a file or stdin is unknown.
for prog, argv in (("gh", ["api", "repos/me/app/pulls/1/reviews", "--input", "approval.json"]),
                   ("gh", ["api", "repos/me/app/pulls/1/reviews", "--input=approval.json"]),
                   ("gh", ["api", "repos/me/app/pulls/1/reviews", "-F", "event=@ev.txt"]),
                   ("curl", ["--json", "@approval.json", REV]),
                   ("curl", ["-d", "@approval.json", REV]),
                   ("curl", ["--data-binary", "@-", REV])):
    row("P1-d %s %s" % (prog, " ".join(argv[-3:])), "POST unknown", prog, *argv)
    row("P1-d   ... body_unknown", ["yes"], prog, *argv, f="bodyu")

# P1-e: a JSON body is decoded before its fields are read; a file body is unknown.
GQ = '{"query":"mutat\\u0069on{deleteRepository(input:{repositoryId:\\"R\\"}){clientMutationId}}"}'
DOC = 'query=mutation{deleteRepository(input:{repositoryId:"R"}){clientMutationId}}'
row("P1-e curl --json '{query: mutat\\u0069on...}': the decoded query", [DOC], "curl", "-H", "Authorization: token x",
    "--json", GQ, GQL, f="fields")
row("P1-e curl -d '{query: mutat\\u0069on...}': the decoded query", [DOC], "curl", "-d", GQ, GQL, f="fields")
row("P1-e curl -d @q.json .../graphql", "POST unknown", "curl", "-d", "@q.json", GQL)
row("P1-e curl -d 'query=mutation{...}' (not JSON): known body, no fields", "none", "curl", "-d",
    "query=mutation{deleteRepository}", GQL, f="fields")

# P1-f / P1-h: the GraphQL document reaches the caller whole (task-001 tokenises it).
FRAG = ('mutation { addComment(input:{subjectId:"I",body:"("}) { clientMutationId } ...A } fragment A on Mutation '
        '{ addPullRequestReview(input:{pullRequestId:"P",event:APPROVE}) { clientMutationId } }')
row("P1-f gh api graphql -f query=<fragment doc>: the document, whole", ["query=" + FRAG], "gh", "api", "graphql",
    "-f", "query=" + FRAG, f="fields")
row("P1-f curl --json '{\"query\": <fragment doc>}': the document, whole", ["query=" + FRAG], "curl", "--json",
    json.dumps({"query": FRAG}), GQL, f="fields")

# P1-g: an --expand-* template is unknown.
EXPJ = '{"query":"{{m}}{deleteRepository(input:{repositoryId:\\"R\\"}){clientMutationId}}"}'
row("P1-g curl --variable m=mutation --expand-json '{query: {{m}}...}'", "POST unknown", "curl", "--variable",
    "m=mutation", "--expand-json", EXPJ, GQL)
row("P1-g curl --variable m=mutation --expand-data '{query: {{m}}...}'", "POST unknown", "curl", "--variable",
    "m=mutation", "--expand-data", EXPJ, GQL)
row("P1-g curl --variable e=APPROVE --expand-json '{event: {{e}}}'", "POST unknown", "curl", "--variable",
    "e=APPROVE", "--expand-json", '{"event":"{{e}}"}', REV)

# P1-i: curl joins --json pieces as they are and -d pieces with '&'.
row("P1-i curl --json '{\"event\":' --json '\"APPROVE\"}': one body", '{"event":"APPROVE"}', "curl", "--json",
    '{"event":', "--json", '"APPROVE"}', REV, f="body")
row("P1-i   ... whose field is event=APPROVE", ["event=APPROVE"], "curl", "--json", '{"event":', "--json",
    '"APPROVE"}', REV, f="fields")
row("P1-i curl -d '{\"event\"' -d ':\"APPROVE\"}': joined with '&'", '{"event"&:"APPROVE"}', "curl", "-d",
    '{"event"', "-d", ':"APPROVE"}', REV, f="body")
row("P1-i   ... which is not JSON: no fields", "none", "curl", "-d", '{"event"', "-d", ':"APPROVE"}', REV, f="fields")
row("P1-i curl -d '{\"a\":' --json '1}' (a --json piece after -d: no '&')", '{"a":1}', "curl", "-d", '{"a":',
    "--json", "1}", REV, f="body")
row("P1-i curl --json '{\"a\":1' -d '}' (a -d piece after --json: '&')", '{"a":1&}', "curl", "--json", '{"a":1',
    "-d", "}", REV, f="body")
row("JSON: a duplicate key keeps both values", ["event=COMMENT", "event=APPROVE"], "curl", "-d",
    '{"event":"COMMENT","event":"APPROVE"}', REV, f="fields")
row("JSON: a nested value is reported as JSON", ['a={"b":1}'], "curl", "-d", '{"a":{"b":1}}', REV, f="fields")
row("JSON: an array body has no fields", "none", "curl", "-d", "[1]", REV, f="fields")

# ===== 2. curl's own forms ============================================================================
U = "https://api.github.com/x"
for argv in (["-X", "POST"], ["-XPOST"], ["-sXPOST"], ["-sSLXPOST"], ["--request", "POST"], ["--request=POST"],
             ["-X", "post"]):
    row("curl %s" % " ".join(argv), "POST known", "curl", *argv, U)
row("curl -X 'GET /x HTTP/1.1' is no plain method: unknown", "None unknown", "curl", "-X", "GET /x HTTP/1.1", U)
for argv in (["-d", "x"], ["-dx"], ["-sdx"], ["-sd", "x"], ["--data", "x"], ["--data=x"], ["--data-ascii", "x"],
             ["--data-binary", "x"], ["--json", "x"], ["--json=x"]):
    row("curl %s: body x" % " ".join(argv), "x", "curl", *argv, U, f="body")
    row("curl %s: POST" % " ".join(argv), "POST known", "curl", *argv, U)
row("curl --data-raw @x is literal", "@x", "curl", "--data-raw", "@x", U, f="body")
row("curl --data-urlencode 'a=b&c' encodes the content", "a=b%26c", "curl", "--data-urlencode", "a=b&c", U, f="body")
row("curl --data-urlencode '=x y' encodes, no name", "x%20y", "curl", "--data-urlencode", "=x y", U, f="body")
row("curl --data-urlencode 'plain text'", "plain%20text", "curl", "--data-urlencode", "plain text", U, f="body")
row("curl --data-urlencode a=1 --data-urlencode b=2 joins with '&'", "a=1&b=2", "curl", "--data-urlencode", "a=1",
    "--data-urlencode", "b=2", U, f="body")
row("curl --data-urlencode name@file reads a file", "POST unknown", "curl", "--data-urlencode", "name@file", U)
row("curl --data-urlencode @file reads a file", "POST unknown", "curl", "--data-urlencode", "@file", U)
for argv in (["-F", "n=v"], ["-Fn=v"], ["-sFn=v"], ["--form", "n=v"], ["--form=n=v"], ["--form-string", "n=v"]):
    row("curl %s: form POST" % " ".join(argv), "POST known", "curl", *argv, U)
    row("curl %s: field" % " ".join(argv), ["n=v"], "curl", *argv, U, f="fields")
row("curl -F 'f=@file' uploads a file", "POST unknown", "curl", "-F", "f=@file", U)
row("curl -F 'f=<file' reads a part from a file", "POST unknown", "curl", "-F", "f=<file", U)
row("curl --form-string 'f=@file' is literal", "POST known", "curl", "--form-string", "f=@file", U)
row("curl -F novalue: curl refuses it", "yes", "curl", "-F", "novalue", U, f="unknown")
for argv in (["-T", "f"], ["-Tf"], ["-sTf"], ["--upload-file", "f"], ["--upload-file=f"], ["-T", "-"]):
    row("curl %s: a PUT of a file" % " ".join(argv), "PUT unknown", "curl", *argv, U)
for argv in (["-H", "X: y"], ["-HX: y"], ["-sHX: y"], ["--header", "X: y"], ["--header=X: y"]):
    row("curl %s: a header" % " ".join(argv), ["X: y"], "curl", *argv, U, f="headers")
    row("curl %s: not a route" % " ".join(argv), ["no"], "curl", *argv, U, f="route")
for argv in (["-H", "Host: api.github.com"], ["-HHost: api.github.com"], ["-sHhost:api.github.com"],
             ["--header=Host: x"], ["-H", "Host;"], ["-H", "@headers.txt"], ["-H", "X: a\r\nHost: api.github.com"]):
    row("curl %r: a route override" % " ".join(argv), ["yes"], "curl", *argv, U, f="route")
for argv in (["--url", U], ["--url=" + U], ["--expand-url", U]):
    row("curl %s" % argv[0].split("=")[0], [U], "curl", *argv, f="urls")
row("curl --url @file (curl 8.13+): URLs from a file", "yes", "curl", "--url", "@urls.txt", f="targets")
for argv in (["-K", "c"], ["-Kc"], ["-sKc"], ["--config", "c"], ["--config=c"], ["-K", "-"]):
    row("curl %s: options from a file" % " ".join(argv), "yes", "curl", *argv, U, f="targets")
for argv in (["--request-target", "/x"], ["--request-target=/x"], ["--unix-socket", "/s"], ["--unix-socket=/s"],
             ["--abstract-unix-socket", "s"], ["--connect-to", "a:443:b:443"], ["--resolve", "a:443:1.2.3.4"],
             ["--resolve=a:443:1.2.3.4"], ["--alt-svc", "cache.txt"]):
    row("curl %s: a route override" % " ".join(argv), ["yes"], "curl", *argv, U, f="route")

# -G, -I and the request kinds curl refuses to mix (measured on curl 8.7.1).
row("curl -G -d a=b: a GET", "GET known", "curl", "-G", "-d", "a=b", U)
row("curl -G -d a=b: the data is the query", [U + "?a=b"], "curl", "-G", "-d", "a=b", U, f="urls")
row("curl -Gd a=b (cluster): the same", [U + "?a=b"], "curl", "-Gd", "a=b", U, f="urls")
row("curl --get -d a=b ...?q=1: '&'", [U + "?q=1&a=b"], "curl", "--get", "-d", "a=b", U + "?q=1", f="urls")
row("curl -G --no-get -d x: a POST again", "POST known", "curl", "-G", "--no-get", "-d", "x", U)
row("curl -G -d @f: the query is a file", "GET unknown", "curl", "-G", "-d", "@f", U)
row("curl -G -F a=b: curl still posts the form", "POST known", "curl", "-G", "-F", "a=b", U)
row("curl -G -T f: curl still puts the file", "PUT unknown", "curl", "-G", "-T", "f", U)
row("curl -G -d x -I: a HEAD with the query", "HEAD known", "curl", "-G", "-d", "x", "-I", U)
row("curl -I", "HEAD known", "curl", "-I", U)
row("curl --head", "HEAD known", "curl", "--head", U)
row("curl -I -d x: curl refuses", "None unknown", "curl", "-I", "-d", "x", U)
row("curl -T f -d x: curl refuses", "None unknown", "curl", "-T", "f", "-d", "x", U)
row("curl -d x -F a=b: curl refuses", "None unknown", "curl", "-d", "x", "-F", "a=b", U)
row("curl -X POST -T f -d x: still refused", "None unknown", "curl", "-X", "POST", "-T", "f", "-d", "x", U)
row("curl -X GET -d x: the explicit method wins", "GET known", "curl", "-X", "GET", "-d", "x", U)

# URL globs.
B = "https://h/"
row("curl glob [1-3]", [B + "1", B + "2", B + "3"], "curl", B + "[1-3]", f="urls")
row("curl glob [01-03] keeps the padding", [B + "01", B + "02", B + "03"], "curl", B + "[01-03]", f="urls")
row("curl glob [a-c]", [B + "a", B + "b", B + "c"], "curl", B + "[a-c]", f="urls")
row("curl glob [1-5:2]", [B + "1", B + "3", B + "5"], "curl", B + "[1-5:2]", f="urls")
row("curl glob {a,b}{c,d}", [B + "ac", B + "ad", B + "bc", B + "bd"], "curl", B + "{a,b}{c,d}", f="urls")
row("curl glob \\{a,b\\} is literal", [B + "{a,b}"], "curl", B + "\\{a,b\\}", f="urls")
row("curl -g: no globbing", [B + "{a,b}"], "curl", "-g", B + "{a,b}", f="urls")
row("curl --globoff: no globbing", [B + "[1-2]"], "curl", "--globoff", B + "[1-2]", f="urls")
row("curl IPv6 [::1] is an address, not a range", ["http://[::1]:8080/x"], "curl", "http://[::1]:8080/x", f="urls")
for bad in ("{a,b", "{a,{b}}", "[1-1000]", "a}b", "[9-1]", "[x]"):
    row("curl glob %r curl refuses or is too large: unknown" % bad, "yes", "curl", B + bad, f="targets")

# --next groups.
row("curl -d x A --next B: POST then GET", "POST,GET known", "curl", "-d", "x", U, "--next", B)
row("curl -X DELETE A -: B ('-:' is --next)", "DELETE,GET known", "curl", "-X", "DELETE", U, "-:", B)
row("curl -s: A B (a cluster ending in ':')", "GET,GET known", "curl", U, "-s:", B)
row("curl A --next (an empty last group): curl refuses", "yes", "curl", U, "--next", f="targets")
row("curl --next A (an empty first group): curl refuses", "yes", "curl", "--next", U, f="targets")
row("curl -H 'Host: x' A --next B: only the first group re-routes", ["yes", "no"], "curl", "-H", "Host: x", U,
    "--next", B, f="route")
row("curl A --next -d @f B: only the second body is a file", ["no", "yes"], "curl", U, "--next", "-d", "@f", B,
    f="bodyu")
row("curl -G -d q A --next -d q B: -G does not carry over", "GET,POST known", "curl", "-G", "-d", "q", U, "--next",
    "-d", "q", B)
row("curl --no-next: curl refuses", "no", "curl", U, "--no-next", B, f="ok")
row("curl A B C: one request, three URLs", [[U, B, "C"]], "curl", U, B, "C", f="groups")
row("curl -d x -- -weird https://x: after --, words are URLs", ["-weird", "https://x"], "curl", "-d", "x", "--",
    "-weird", "https://x", f="urls")

# --expand-*.
row("curl --expand-url '{{u}}': unknown", "yes", "curl", "--expand-url", "{{u}}", f="targets")
row("curl --expand-request '{{m}}': unknown", "None unknown", "curl", "--expand-request", "{{m}}", U)
row("curl --expand-header 'Host: {{h}}': a route", ["yes"], "curl", "--expand-header", "Host: {{h}}", U, f="route")
row("curl --expand-header 'X: {{h}}': any templated header could be Host", ["yes"], "curl", "--expand-header",
    "X: {{h}}", U, f="route")
row("curl --expand-output '{{f}}' shapes nothing sent", "GET known", "curl", "--expand-output", "{{f}}", U)
row("curl --expand-data=x (attached)", "x", "curl", "--expand-data=x", U, f="body")
row("curl --expand-silent: --expand- needs a value option", "no", "curl", "--expand-silent", U, f="ok")
row("curl --expand-bogus x: unknown", "no", "curl", "--expand-bogus", "x", U, f="ok")

# Unknown options, missing values, negation.
row("curl --bogus <url>: not ok", "no", "curl", "--bogus", U, f="ok")
row("curl --bogus <url>: unknown", "yes", "curl", "--bogus", U, f="unknown")
row("curl --bogus <url>: the URL is still reported", [U], "curl", "--bogus", U, f="urls")
row("curl -% <url> (no such short option)", "yes", "curl", "-%", U, f="unknown")
row("curl -s% <url> (in a cluster)", "yes", "curl", "-s%", U, f="unknown")
row("curl --silent=1: curl refuses a value on a flag", "yes", "curl", "--silent=1", U, f="unknown")
row("curl --no-request-target x: --no- on a value option", "yes", "curl", "--no-request-target", "x", U, f="unknown")
row("curl --requ GET (curl takes no abbreviations)", "yes", "curl", "--requ", "GET", U, f="unknown")
row("curl <url> -d (no value)", "no", "curl", U, "-d", f="ok")
row("curl -X (no value)", "no", "curl", "-X", f="ok")
row("curl --no-silent --no-buffer -N", "GET known", "curl", "--no-silent", "--no-buffer", "-N", U)
row("curl --keepalive --ftp-ssl-reqd (accepted, unlisted)", "GET known", "curl", "--keepalive", "--ftp-ssl-reqd", U)
row("curl --ssl-sessions f (8.12) takes its value", [U], "curl", "--ssl-sessions", "f", U, f="urls")
row("curl --skip-existing (8.10) is a flag", "GET known", "curl", "--skip-existing", U)

# Default config: only a first -q stops curl reading its curlrc.
row("curl <url>: reads its curlrc", "yes", "curl", U, f="cfg")
row("curl -q <url>: no curlrc", "no", "curl", "-q", U, f="cfg")
row("curl --disable <url>: no curlrc", "no", "curl", "--disable", U, f="cfg")
row("curl -s -q <url>: -q not first, curlrc read", "yes", "curl", "-s", "-q", U, f="cfg")

# ===== 3. wget ========================================================================================
for argv in (["--method=DELETE"], ["--method", "DELETE"], ["--meth=DELETE"], ["-e", "method=DELETE"],
             ["-emethod=DELETE"], ["-qe", "method=DELETE"], ["--execute=method=DELETE"], ["--execute", "method=DELETE"],
             ["-e", "METHOD = delete"], ["-e", "Me_Th-od=delete"]):
    row("wget %s" % " ".join(argv), "DELETE known", "wget", *argv, REPO)
for argv in (["--post-data=x"], ["--post-data", "x"], ["--post-d=x"], ["-e", "post_data=x"], ["-e", "postdata=x"],
             ["-e", "post-data = x"]):
    row("wget %s: body" % " ".join(argv), "x", "wget", *argv, REL, f="body")
    row("wget %s: POST" % " ".join(argv), "POST known", "wget", *argv, REL)
row("wget --post=x is ambiguous (post-data, post-file)", "no", "wget", "--post=x", REL, f="ok")
row("wget --post-file=f", "POST unknown", "wget", "--post-file=f", REL)
row("wget -e post_file=f", "POST unknown", "wget", "-e", "post_file=f", REL)
row("wget --body-data=x --method=PUT", "PUT known", "wget", "--body-data=x", "--method=PUT", REL)
row("wget --body-data=x without --method: wget refuses", "None unknown", "wget", "--body-data=x", REL)
row("wget --body-file=f --method=PATCH", "PATCH unknown", "wget", "--body-file=f", "--method=PATCH", REL)
row("wget --post-data=x --post-file=f: wget refuses", "yes", "wget", "--post-data=x", "--post-file=f", REL,
    f="targets")
row("wget --post-data=a --post-data=b: the last is sent", "b", "wget", "--post-data=a", "--post-data=b", REL, f="body")
for argv in (["-i", "u.txt"], ["-iu.txt"], ["-qi", "u.txt"], ["--input-file=u.txt"], ["--input-file", "u.txt"],
             ["--input-f=u.txt"], ["-e", "input=u.txt"], ["--input-metalink=m"], ["--config=c"], ["-e", "chooseconfig=c"]):
    row("wget %s: URLs or options from a file" % " ".join(argv), "yes", "wget", *argv, f="targets")
row("wget --input=u.txt is ambiguous (input-file, input-metalink)", "no", "wget", "--input=u.txt", f="ok")
row("wget <url>: reads its wgetrc", "yes", "wget", REPO, f="cfg")
row("wget --no-config <url>", "no", "wget", "--no-config", REPO, f="cfg")
row("wget --header='Host: api.github.com'", ["yes"], "wget", "--header=Host: api.github.com", "https://1.2.3.4/x",
    f="route")
row("wget --header 'X: y'", ["X: y"], "wget", "--header", "X: y", REPO, f="headers")
row("wget -e 'header = Host: api.github.com'", ["yes"], "wget", "-e", "header = Host: api.github.com",
    "https://1.2.3.4/x", f="route")
row("wget -e robots=off <url>", "GET known", "wget", "-e", "robots=off", REPO)
row("wget -e bogus=1: a .wgetrc command the table lacks", "yes", "wget", "-e", "bogus=1", REPO, f="unknown")
row("wget -e novalue: wget refuses", "yes", "wget", "-e", "novalue", REPO, f="unknown")
for argv in (["-nv"], ["-ncvd"], ["-qnv"], ["-n", "v"], ["-O-"], ["-O", "-"], ["-Oout"], ["-q"], ["--quiet=off"],
             ["--no-check-cert"], ["-t3"], ["-T", "5"]):
    row("wget %s <url>" % " ".join(argv), "GET known", "wget", *argv, REPO)
row("wget -O out <url>: -O takes 'out'", [REPO], "wget", "-O", "out", REPO, f="urls")
row("wget -nx (not a -n letter)", "yes", "wget", "-nx", REPO, f="unknown")
row("wget --bogus <url>", "yes", "wget", "--bogus", REPO, f="unknown")
row("wget -Z <url> (no such short option)", "yes", "wget", "-Z", REPO, f="unknown")
row("wget -r <url>: a recursive GET", "GET known", "wget", "-r", REPO)
row("wget -r --method=DELETE: it would DELETE every link it finds", "yes", "wget", "-r", "--method=DELETE", REPO,
    f="targets")
row("wget -m --post-data=x", "yes", "wget", "-m", "--post-data=x", REPO, f="targets")
row("wget -r --no-recursive --method=DELETE", "DELETE known", "wget", "-r", "--no-recursive", "--method=DELETE", REPO)
row("wget --recursive=off --method=DELETE", "DELETE known", "wget", "--recursive=off", "--method=DELETE", REPO)
row("wget A B: one request, two URLs", [[REPO, ISS]], "wget", REPO, ISS, f="groups")
row("wget -- -x: after --, words are URLs", ["-x"], "wget", "--", "-x", f="urls")

# ===== 4. httpie and xh ===============================================================================
H = "api.github.com/repos/me/app/issues"
row("http POST <url> a=b", "POST known", "http", "POST", H, "a=b")
row("http <url> a=b: a data item implies POST", "POST known", "http", H, "a=b")
row("http <url> a=b: the body", '{"a": "b"}', "http", H, "a=b", f="body")
row("http <url> a=b n:=1 'e:=\"APPROVE\"': fields", ["a=b", "n=1", "e=APPROVE"], "http", H, "a=b", "n:=1",
    'e:="APPROVE"', f="fields")
row("http <url> a:=notjson: httpie refuses", "no", "http", H, "a:=notjson", f="ok")
for item in ("a=@f", "a:=@f", "a@f"):
    row("http <url> %s: from a file" % item, "POST unknown", "http", H, item)
row("http <url> 'a[b]=c': nested JSON this module does not assemble", "POST unknown", "http", H, "a[b]=c")
row("http <url> 'a\\=b=c': an escape", "POST unknown", "http", H, "a\\=b=c")
row("http <url> a=1 a=2: a duplicate key", "POST unknown", "http", H, "a=1", "a=2")
row("http -f <url> a=b: a form", "POST known", "http", "-f", H, "a=b")
row("http --form <url> a=b: fields", ["a=b"], "http", "--form", H, "a=b", f="fields")
row("http -I <url> q==x: a query item is no body", "GET known", "http", "-I", H, "q==x")
row("http -I <url> q==@f: a query from a file", "GET unknown", "http", "-I", H, "q==@f")
row("http -I <url> Host:api.github.com", ["yes"], "http", "-I", "1.2.3.4/x", "Host:api.github.com", f="route")
row("http -I <url> host:x (any case)", ["yes"], "http", "-I", "1.2.3.4/x", "host:x", f="route")
row("http -I <url> X-A:b is a header", ["X-A:b"], "http", "-I", H, "X-A:b", f="headers")
row("http -I <url> X-A:b is not a route", ["no"], "http", "-I", H, "X-A:b", f="route")
row("http --raw '{\"event\":\"APPROVE\"}' <url>", ["event=APPROVE"], "http", "--raw", '{"event":"APPROVE"}', H,
    f="fields")
row("http --raw=x <url>", "POST known", "http", "--raw=x", H)
row("http --raw x <url> a=b: httpie refuses", "yes", "http", "--raw", "x", H, "a=b", f="targets")
for argv in (["--session=s"], ["--session", "s"], ["--session-read-only", "s"]):
    row("http %s: a session file's headers" % " ".join(argv), ["yes"], "http", *argv, "-I", "GET", H, f="route")
row("http --ses=s: ambiguous", "no", "http", "--ses=s", "-I", "GET", H, f="ok")
row("http --ignore-std GET <url> (argparse prefix)", "GET known", "http", "--ignore-std", "GET", H)
row("http -Iv GET <url> (cluster)", "GET known", "http", "-Iv", "GET", H)
row("http -vI GET <url> (cluster)", "GET known", "http", "-vI", "GET", H)
row("http -I --no-ignore-stdin GET <url>: stdin again", "GET unknown", "http", "-I", "--no-ignore-stdin", "GET", H)
for argv in (["-o", "out"], ["-oout"], ["-o=out"], ["--output=out"], ["--output", "out"]):
    row("http %s -I GET <url>" % " ".join(argv), [H], "http", *argv, "-I", "GET", H, f="urls")
row("http <url> with nothing pinning stdin: GET or POST", "None unknown", "http", H)
row("http --bogus GET <url>", "yes", "http", "--bogus", "GET", H, f="unknown")
row("http -Z GET <url>", "yes", "http", "-Z", "GET", H, f="unknown")
row("http -I <url> justaword: httpie refuses the item", "no", "http", "-I", H, "justaword", f="ok")
row("https -I GET <url>", "GET known", "https", "-I", "GET", H)
row("http (no URL): no request", 0, "http", f="nreq")
row("xh -I PUT <url> a=b", "PUT known", "xh", "-I", "PUT", H, "a=b")
row("xh <url> a=b", "POST known", "xh", H, "a=b")
row("xh GET <url>: its body may be stdin", "GET unknown", "xh", "GET", H)
row("xh -I <url>", "GET known", "xh", "-I", H)
row("xh --resolve api.github.com:1.2.3.4", ["yes"], "xh", "--resolve", "api.github.com:1.2.3.4", "-I", "GET",
    "https://x/", f="route")
row("xh --unix-socket=/s", ["yes"], "xh", "--unix-socket=/s", "-I", "GET", "http://x/", f="route")
row("xh -Iofile GET <url> (cluster, attached)", [H], "xh", "-Iofile", "GET", H, f="urls")
row("xh -o=file -I GET <url>", [H], "xh", "-o=file", "-I", "GET", H, f="urls")
row("xh -I --no-ignore-stdin GET <url>", "GET unknown", "xh", "-I", "--no-ignore-stdin", "GET", H)
row("xh --ignore-std (clap takes no prefix)", "yes", "xh", "--ignore-std", "GET", H, f="unknown")
row("xh --bogus <url>", "yes", "xh", "--bogus", H, f="unknown")
row("xh -I <url> Host:x", ["yes"], "xh", "-I", H, "Host:x", f="route")
row("xhs -I GET example.com", "GET known", "xhs", "-I", "GET", "example.com")

# ===== 5. gh api ======================================================================================
for argv in (["-X", "POST"], ["-XPOST"], ["-X=POST"], ["--method", "POST"], ["--method=POST"], ["-iXPOST"],
             ["-iX", "POST"], ["-X", "post"]):
    row("gh api %s" % " ".join(argv), "POST known", "gh", "api", *argv, "repos/me/app/issues")
for argv in (["-f", "k=v"], ["-fk=v"], ["-f=k=v"], ["--raw-field", "k=v"], ["--raw-field=k=v"], ["-F", "k=v"],
             ["-Fk=v"], ["--field", "k=v"], ["--field=k=v"], ["-iFk=v"]):
    row("gh api %s: POST" % " ".join(argv), "POST known", "gh", "api", "repos/me/app/issues", *argv)
    row("gh api %s: field" % " ".join(argv), ["k=v"], "gh", "api", "repos/me/app/issues", *argv, f="fields")
row("gh api -F k=@f: from a file", "POST unknown", "gh", "api", "repos/me/app/issues", "-F", "k=@f")
row("gh api -F k=@-: from stdin", "POST unknown", "gh", "api", "repos/me/app/issues", "-F", "k=@-")
row("gh api -f k=@f: a literal string", "POST known", "gh", "api", "repos/me/app/issues", "-f", "k=@f")
for argv in (["--input", "f"], ["--input=f"], ["--input", "-"]):
    row("gh api %s" % " ".join(argv), "POST unknown", "gh", "api", "repos/me/app/issues", *argv)
row("gh api -X GET search/issues -f q=x: a GET with a query", "GET known", "gh", "api", "-X", "GET", "search/issues",
    "-f", "q=x")
row("gh api -H 'Host: evil': Go ignores a Host header", ["no"], "gh", "api", "-H", "Host: evil", "repos/me/app",
    f="route")
row("gh api -i=false repos/me/app", "GET known", "gh", "api", "-i=false", "repos/me/app")
row("gh api --include=false repos/me/app", "GET known", "gh", "api", "--include=false", "repos/me/app")
row("gh api --bogus repos/me/app", "yes", "gh", "api", "--bogus", "repos/me/app", f="unknown")
row("gh api -Z repos/me/app", "yes", "gh", "api", "-Z", "repos/me/app", f="unknown")
row("gh api (no endpoint): gh refuses", "yes", "gh", "api", f="targets")
row("gh api repos/me/app -f novalue: gh refuses", "no", "gh", "api", "repos/me/app", "-f", "novalue", f="ok")
row("gh api --paginate .../issues --jq '.[].title': the jq is -q's value", ["repos/me/app/issues"], "gh", "api",
    "--paginate", "repos/me/app/issues", "--jq", ".[].title", f="urls")
row("gh api -t '{{range .}}...' is an output template, not a request one", "GET known", "gh", "api", "-t",
    "{{range .}}{{.title}}{{end}}", "repos/me/app/issues")
row("prog 'gh api' works too", "DELETE known", "gh api", "-X", "DELETE", "repos/me/app")
row("gh pr list is not gh api", "no", "gh", "pr", "list", f="ok")

# ===== 6. ordinary calls stay ok and known ============================================================
for prog, argv in (("curl", ["https://example.com"]), ("curl", ["-sSL", "https://example.com", "-o", "out"]),
                   ("curl", ["-fsSL", "https://example.com/install.sh"]), ("curl", ["-O", "https://example.com/a.tgz"]),
                   ("curl", ["-s", "-H", "Accept: application/json", REPO]),
                   ("curl", ["-u", "me:pw", "-A", "agent", "-e", "https://ref", "-m", "5", REPO]),
                   ("wget", ["-q", "https://example.com/f.tgz"]), ("wget", ["-O-", "https://example.com"]),
                   ("http", ["-I", "GET", "example.com"]), ("xh", ["-I", "example.com"]),
                   ("gh", ["api", "repos/me/app"]), ("gh", ["api", "repos/me/app/pulls", "--jq", ".[].number"])):
    row("ordinary: %s %s" % (prog, " ".join(argv)), "GET known", prog, *argv)
    row("ordinary: %s %s" % (prog, " ".join(argv)), "yes", prog, *argv, f="ok")
row("ordinary: curl -sSL <url> -o out sends to the URL only", ["https://example.com"], "curl", "-sSL",
    "https://example.com", "-o", "out", f="urls")
row("curl --version: no request, nothing unknown", "no", "curl", "--version", f="unknown")
row("curl -h: no request", 0, "curl", "-h", f="nreq")

# ===== 7. program words and robustness ================================================================
row("lynx is no client this models", "no", "lynx", "x", f="ok")
row("  ... and is unknown", "yes", "lynx", "x", f="unknown")
row("/usr/bin/curl", "POST known", "/usr/bin/curl", "-d", "x", U)
row("CURL (a case-blind file system runs it)", "POST known", "CURL", "-d", "x", U)
row("curl.exe", "POST known", "curl.exe", "-d", "x", U)
row("no program at all", "no", "", f="ok")
row("parse never raises on odd words", "yes", "curl", "", "-", "--", f="ok")

for label, want, got in ROWS:
    print("%s\t%s\t%s" % (label, want.replace("\t", " ").replace("\n", "\\n"), got.replace("\t", " ").replace("\n", "\\n")))
print("END\t%d" % len(ROWS))
PY
rc=$?
judge "the row pass ran (exit 0, no stderr)" "0 " "$rc $(head -c 300 "$T/rows.err")"
section "rows"
judge_rows "$T/rows.tsv"

# ===== the tables against the installed tools =========================================================
# compare <client> < help-text: MISMATCH <name> for a listed option whose takes-value the help contradicts,
# MISSING <name> for an option the help lists and the table does not, then CHECKED <n>.
cat > "$T/compare.py" <<'PY'
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("pg_http", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
client, text = sys.argv[2], sys.stdin.read()
table = m.TABLES[client]
seen = {}
if client == "curl":
    # ` -d, --data <data>   HTTP POST data`  /  `     --anyauth   Pick any authentication method`
    for line in text.splitlines():
        g = re.match(r"^\s*(?:-\S, )?--(\S+)(.*)$", line)
        if g:
            seen[g.group(1)] = g.group(2).lstrip()[:1] in "<["
    seen.pop("help", None)   # its <category> is optional: listed as a flag on purpose
elif client == "wget":
    # `  -e,  --execute=COMMAND   ...`  /  `       --no-config   ...`; help prints no =VALUE for these three
    omits = {"max-redirect", "hsts-file", "preferred-location"}
    for line in text.splitlines():
        g = re.match(r"^\s{1,8}(?:-\S+,\s+)?--([A-Za-z0-9][\w.-]*)(=)?", line)
        if g:
            seen[g.group(1)] = bool(g.group(2)) or g.group(1) in omits
elif client == "gh api":
    # `  -F, --field key=value   Add a typed parameter`  /  `      --paginate   Make additional ...`
    for line in text.splitlines():
        g = re.match(r"^\s+(?:-\w, )?--([\w-]+)( \S+)?\s{2,}\S", line)
        if g:
            seen[g.group(1)] = bool(g.group(2))
for name, takes in sorted(seen.items()):
    o = table.long.get(name)
    if o is None and name.startswith("no-") and name[3:] in table.long and not takes:
        o = table.long[name[3:]]   # --no-<boolean>: the table lists the boolean
        if o.value:
            print("MISMATCH %s (a --no- form of a value option)" % name)
        continue
    if o is None:
        print("MISSING %s" % name)
    elif o.value != takes:
        print("MISMATCH %s (help: %s, table: %s)" % (name, "value" if takes else "flag", "value" if o.value else "flag"))
print("CHECKED %d" % len(seen))
PY
compare() { python3 -B -I -S "$T/compare.py" "$LIB" "$1"; }

section "the comparator reads a wget help it was never run on (self-test)"
FIX="$(printf '%s\n' \
  '  -e,  --execute=COMMAND           execute a .wgetrc-style command' \
  '  -nv, --no-verbose                turn off verboseness, without being quiet' \
  '       --max-redirect              maximum redirections allowed per page' \
  '       --post-data=STRING          use the POST method; send STRING as the data' \
  '  -r,  --recursive                 specify recursive download' \
  '                                     --wrapped continuation lines are not options' \
  '       --frobnicate=X              a made-up option' \
  '  -q,  --quiet=X                   a deliberate mismatch' | compare wget)"
judge "the made-up option is MISSING" yes "$(has "$FIX" "MISSING frobnicate")"
judge "the deliberate mismatch is a MISMATCH" yes "$(has "$FIX" "MISMATCH quiet")"
judge "nothing else is flagged (a wrapped line, --max-redirect's unprinted value)" 2 "$(printf '%s\n' "$FIX" | grep -c '^M')"
judge "seven options were read, the wrapped line not among them" yes "$(has "$FIX" "CHECKED 7")"

section "curl: the table against the installed curl --help all"
if harness_have curl; then
  CV="$(curl --version 2>/dev/null | head -1 | awk '{print $2}')"
  CMP="$(curl --help all 2>/dev/null | compare curl)"
  judge "curl $CV: every listed option agrees with its help about taking a value" "" "$(printf '%s\n' "$CMP" | grep '^MISMATCH')"
  judge "curl $CV: the help was read (over 200 options)" yes "$(printf '%s\n' "$CMP" | awk '/^CHECKED/ {print ($2 > 200) ? "yes" : "no"}')"
  MISS="$(printf '%s\n' "$CMP" | grep '^MISSING' | sed 's/^MISSING //' | tr '\n' ' ')"
  [ -z "$MISS" ] || warn "curl $CV lists options the table lacks (read as unknown, the safe side): $MISS"
  [ "$CV" = "8.7.1" ] || warn "the curl table was generated from 8.7.1; this machine runs $CV"
else
  skip "curl --help all" "curl is not installed"
fi

section "gh api: the table against the installed gh api --help"
if harness_have gh; then
  GV="$(gh --version 2>/dev/null | head -1 | awk '{print $3}')"
  CMP="$(gh api --help 2>/dev/null | compare "gh api")"
  judge "gh $GV: every listed flag agrees with its help about taking a value" "" "$(printf '%s\n' "$CMP" | grep '^MISMATCH')"
  judge "gh $GV: the help was read (over 10 flags)" yes "$(printf '%s\n' "$CMP" | awk '/^CHECKED/ {print ($2 > 10) ? "yes" : "no"}')"
  MISS="$(printf '%s\n' "$CMP" | grep '^MISSING' | sed 's/^MISSING //' | tr '\n' ' ')"
  [ -z "$MISS" ] || warn "gh $GV lists gh api flags the table lacks: $MISS"
else
  skip "gh api --help" "gh is not installed"
fi

section "wget: the table against the installed wget --help"
if harness_have wget && wget --version 2>/dev/null | head -1 | grep -q 'GNU Wget 1'; then
  WV="$(wget --version 2>/dev/null | head -1 | awk '{print $3}')"
  CMP="$(wget --help 2>/dev/null | compare wget)"
  judge "wget $WV: every listed option agrees with its help about taking a value" "" "$(printf '%s\n' "$CMP" | grep '^MISMATCH')"
  judge "wget $WV: the help was read (over 100 options)" yes "$(printf '%s\n' "$CMP" | awk '/^CHECKED/ {print ($2 > 100) ? "yes" : "no"}')"
  MISS="$(printf '%s\n' "$CMP" | grep '^MISSING' | sed 's/^MISSING //' | tr '\n' ' ')"
  [ -z "$MISS" ] || warn "wget $WV lists options the table lacks (read as unknown): $MISS"
else
  skip "wget --help" "GNU Wget 1.x is not installed (wget2 is a different program)"
fi

section "the module's shape: Python 3.9 syntax, stdlib only, no I/O"
SHAPE="$(python3 -B -I -S - "$LIB" <<'PY'
import ast, sys
src = open(sys.argv[1]).read()
try:
    tree = ast.parse(src, feature_version=(3, 9))
    print("py39 yes")
except SyntaxError as e:
    print("py39 no %s" % e)
    tree = ast.parse(src)
mods = set()
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        mods |= {a.name for a in node.names}
    elif isinstance(node, ast.ImportFrom):
        mods.add(node.module)
print("imports " + ",".join(sorted(mods)))
names = {n.id for n in ast.walk(tree) if isinstance(n, ast.Name)} | \
        {n.attr for n in ast.walk(tree) if isinstance(n, ast.Attribute)}
print("io " + (",".join(sorted(names & {"open", "subprocess", "socket", "os", "system", "popen", "urlopen", "environ"})) or "none"))
PY
)"
judge "it parses as Python 3.9" yes "$(has "$SHAPE" "py39 yes")"
judge "it imports the stdlib only (sys only to print under __main__)" "imports itertools,json,re,sys,urllib.parse" "$(printf '%s\n' "$SHAPE" | grep '^imports')"
judge "it names no file, process, socket or environment call" "io none" "$(printf '%s\n' "$SHAPE" | grep '^io')"

harness_summary
