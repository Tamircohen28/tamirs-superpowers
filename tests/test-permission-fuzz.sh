#!/usr/bin/env bash
# test-permission-fuzz.sh — a seeded corpus of GitHub API calls fed to hooks/permission-guard.sh (PG): every
# mutating one must ask or deny, never allow; every benign one must pass (issue #349, ADR 004 D1, D8).
#
# WHAT IT GENERATES (deterministic: FUZZ_SEED, default 349; FUZZ_MUTATING mutating calls, default 2,200, drawn
# by a stratified sample from the full product of the forms below, ~9,800 calls; FUZZ_MUTATING=0 runs them all)
#   mutating  >= 2,000 calls that change something on GitHub, built from the grammars hooks/lib/pg_http.py and
#             hooks/lib/pg_graphql.py read: curl, wget, http/https (httpie), xh/xhs and `gh api`, each crossed with
#             its option forms -- attached, separate and clustered values, --opt=value, --next groups, several URLs,
#             --url, @file and stdin bodies, --expand-* templates, route overrides (--request-target,
#             --connect-to, --resolve, Host headers, sockets, sessions), split --json pieces, form encodings, -K and
#             -i files -- and with GraphQL documents that hide their mutation behind aliases, fragments (nested
#             and inline), comments, strings and block strings holding delimiters, directives, variables and
#             JSON \u escapes. Every call names the action it performs (its intended id).
#   benign    >= 200 calls that change nothing: GitHub reads in every client's forms (gh api GET, -X GET with
#             fields, --paginate, GraphQL queries with the same disguises), and requests to hosts that are not
#             GitHub, re-routed locally included (a docker socket, localhost, a dev Host header).
#
# WHAT IT HOLDS, FOR EVERY CALL
#   classify  the --classify object (the real tokeniser and engine; no resolver runs, nothing is written): a
#             mutating call is UNCLASSIFIED or reaches its intended id -- a misread to a weaker id is a failure
#             even where both would ask -- and is put to the resolver; a benign call is neither UNCLASSIFIED nor
#             put to the resolver.
#   verdict   the hook's answer to a Claude Code payload and to a Codex payload: a mutating call asks or denies on
#             Claude and denies on Codex; a benign call is allowed on both.
#
# HOW IT JUDGES (tests/lib/pg-batch.sh)
#   The whole corpus goes through PG's batch entries, --classify-batch and --judge-batch (NDJSON in, one answer
#   line per call, in order, the engine started once per process), sharded over FUZZ_JOBS processes (default
#   min(cpus, 8)). The batch reads a call through the hook's own functions and prints the hook's own answer
#   compacted, which the suite does not take on trust: a seeded sample of FUZZ_SAMPLE calls (default 150; `all`
#   is every call, today's all-single-call path with the batch beside it) is run through the real single-call
#   path -- `--classify <cmd> <cwd>`, and the hook on its stdin with the very same Claude and Codex payloads --
#   and must agree with its batch line, as JSON, line for line: the sample is the divergence detector. That the
#   detector bites is proved first on a planted divergence (a batch stub whose third answer is an allow, which
#   the check must name) before the corpus is judged, and the runner refuses a shard that prints fewer lines
#   than it read. The wall time is printed at the end.
#
# HERMETIC
#   The verdicts come from the checkout's own hook and its real scripts/resolve-permission.sh, at the default level
#   (no permission file: supervised, R0/R1 allow, R2-R4 and unknown ids ask). The resolver reads a temp passwd home
#   through TAMIRS_PERMISSION_TEST_ROOT, which it honours only under an ancestor shell running one of the permission
#   suites (this one is listed, scripts/lib/permission-common.sh TEST_SCRIPTS); every batch process and every
#   sampled single call is a descendant of this shell, so the override reaches all of them alike. The first check
#   proves the override took, and without it the suite stops rather than let a hook read the real permission
#   state. No payload carries a session id, so PG reads no state; HOME, the client config variables and git config
#   point into the temp dir; gh is tests/lib/fake-gh.sh; no command is run, only judged; no network. The real
#   home's config and state dirs are witnessed unchanged at the end.
#
# SPEED
#   python3 is put on PATH as the interpreter's own binary, so a pyenv shim's start-up is not paid on every guard
#   run of the sample. Measured on the 2,400-call corpus: ~12 minutes as 7,200 single calls on the 4-core runner;
#   under 90 s on an 8-shard laptop in batch, sample included.
#
# Bash 3.2 compatible; needs jq, python3, git.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
# shellcheck source=tests/lib/fake-gh.sh
source "$ROOT/tests/lib/fake-gh.sh"
# shellcheck source=tests/lib/pg-batch.sh
source "$ROOT/tests/lib/pg-batch.sh"
harness_require jq python3 git split
T_START="$SECONDS"

T="$(harness_tmpdir)"
T="$(cd "$T" && pwd -P)"
chmod 700 "$T"
export HOME="$T/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$T/gitconfig"
: > "$GIT_CONFIG_GLOBAL"
unset CODEX_HOME GEMINI_SESSION_ID GEMINI_PROJECT_DIR GEMINI_CWD TS_PERMISSION_LEVEL \
  CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL TAMIRS_AUTO_MERGE GH_REPO GH_HOST PLUGIN_ROOT PLUGIN_DATA \
  CLAUDE_PLUGIN_ROOT CURSOR_PLUGIN_ROOT TAMIRS_PERMISSION_TEST_SESSION \
  CURL_HOME XDG_CONFIG_HOME WGETRC HTTPIE_CONFIG_DIR XH_CONFIG_DIR GH_TOKEN GITHUB_TOKEN 2>/dev/null || true
export NO_COLOR=1

mkdir -p "$T/fx-none"
fake_gh_install "$T/bin" "$T/gh.log" "$T/fx-none"
PYBIN="$(python3 -c 'import os, sys; print(os.path.dirname(os.path.realpath(sys.executable)))' 2>/dev/null)"
export PATH="$T/bin:${PYBIN:+$PYBIN:}$PATH"

section "the suite is hermetic"
judge "gh is the fake (tests/lib/fake-gh.sh)" yes "$(gh --version 2>/dev/null | grep -q fake-gh && echo yes || echo no)"

# The resolver the verdicts come from: the checkout's, reading a temp passwd home (see HERMETIC).
PH="$T/passwd-home"
mkdir -m 700 "$PH"
export TAMIRS_PERMISSION_TEST_ROOT="$PH"
RESOLVE="$ROOT/scripts/resolve-permission.sh"
hs="$(bash "$RESOLVE" repo.read --json 2>/dev/null | jq -r '.home_source // empty')"
if [ "$hs" != "test-root" ]; then
  echo "FATAL: $RESOLVE did not take TAMIRS_PERMISSION_TEST_ROOT (home_source=$hs); refusing to run hooks that would read the real permission state" >&2
  exit 1
fi
ok "the resolver reads the temp passwd home"
judge "the default level asks for repo.delete" ask "$(bash "$RESOLVE" repo.delete --json 2>/dev/null | jq -r .verdict)"
judge "the default level allows repo.read" allow "$(bash "$RESOLVE" repo.read --json 2>/dev/null | jq -r .verdict)"
REAL_HOME="$(python3 -I -S -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
witness() { ls -lAR "$REAL_HOME/.config/tamirs-superpowers" "$REAL_HOME/.local/state/tamirs-superpowers" 2>/dev/null | shasum | awk '{print $1}'; }
REAL_BEFORE="$(witness)"

WORK="$T/work"
mkdir -p "$WORK"
CORPUS="$T/corpus.jsonl"

section "the corpus (seed ${FUZZ_SEED:-349})"
cat > "$T/gen.py" <<'GEN'
import itertools, json, random, sys

out_path, seed, want = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
rng = random.Random(seed)
API = "https://api.github.com"
O, R, N = "me", "app", "5"


def sq(s):
    """The text as one single-quoted shell word."""
    return "'" + s.replace("'", "'\\''") + "'"


def js(obj):
    return json.dumps(obj, separators=(",", ":"))


# ---- REST: (method, path, body or None, intended id). Every intended id is R2-R4: it asks at the default level.
REST = [
    ("PUT", "repos/{o}/{r}/pulls/{n}/merge", {"merge_method": "squash"}, "pr.merge"),
    ("POST", "repos/{o}/{r}/merges", {"base": "main", "head": "feat"}, "pr.merge"),
    ("DELETE", "repos/{o}/{r}", None, "repo.delete"),
    ("POST", "repos/{o}/{r}/releases", {"tag_name": "v1"}, "release.create"),
    ("PATCH", "repos/{o}/{r}/releases/7", {"name": "x"}, "release.create"),
    ("DELETE", "repos/{o}/{r}/releases/assets/9", None, "release.create"),
    ("POST", "repos/{o}/{r}/pulls/{n}/reviews", {"event": "APPROVE"}, "pr.review.approve"),
    ("POST", "repos/{o}/{r}/pulls/{n}/reviews/3/events", {"event": "APPROVE"}, "pr.review.approve"),
    ("DELETE", "repos/{o}/{r}/git/refs/heads/feat", None, "branch.delete.remote"),
    ("PATCH", "repos/{o}/{r}/git/refs/heads/feat", {"sha": "abc", "force": True}, "git.push.force"),
    ("PATCH", "repos/{o}/{r}/git/refs/heads/main", {"sha": "abc"}, "git.push.default"),
    ("POST", "repos/{o}/{r}/git/refs", {"ref": "refs/tags/v1", "sha": "abc"}, "tag.push"),
    ("POST", "repos/{o}/{r}/git/tags", {"tag": "v1"}, "tag.push"),
    ("PATCH", "repos/{o}/{r}/pulls/{n}", {"state": "closed"}, "pr.close"),
    ("PATCH", "repos/{o}/{r}/issues/{n}", {"state": "closed"}, "issue.close"),
    ("PUT", "repos/{o}/{r}/branches/main/protection", {"enforce_admins": True}, "branch_protection.write"),
    ("DELETE", "repos/{o}/{r}/branches/main/protection/enforce_admins", None, "branch_protection.write"),
    ("POST", "repos/{o}/{r}/rulesets", {"name": "x"}, "ruleset.apply"),
    ("PUT", "repos/{o}/{r}/contents/.github/workflows/ci.yml", {"message": "x", "content": "eA=="}, "workflow.edit"),
    ("POST", "user/repos", {"name": "x"}, "repo.create"),
    ("POST", "repos/{o}/{r}/forks", None, "repo.create"),
    ("PATCH", "repos/{o}/{r}", {"allow_auto_merge": True}, "repo.settings.merge"),
    ("POST", "repos/{o}/{r}/statuses/abc", {"state": "success"}, "commit.status.write"),
    ("POST", "repos/{o}/{r}/check-runs", {"name": "x", "head_sha": "abc"}, "check_run.write"),
    ("POST", "repos/{o}/{r}/issues", {"title": "x"}, "issue.create"),
    ("POST", "repos/{o}/{r}/issues/{n}/comments", {"body": "x"}, "issue.comment"),
    ("POST", "repos/{o}/{r}/pulls", {"title": "x", "head": "feat", "base": "main"}, "pr.create"),
    ("PUT", "repos/{o}/{r}/contents/docs/a.md", {"message": "x", "content": "eA=="}, "file.write.remote"),
]


# The actions whose id the body decides (the catalog's fields_all / fields_none): a variant of one is always sent
# with its body, since without it the call honestly is the weaker id (an edit, a comment, a push).
BODY_DECIDES = {"pr.review.approve", "git.push.force", "pr.close", "issue.close"}
BODY_DECIDES_PATHS = {"repos/{o}/{r}/git/refs"}


def needs_body(t):
    return t[3] in BODY_DECIDES or t[1] in BODY_DECIDES_PATHS


def path_of(t):
    return t[1].format(o=O, r=R, n=N)


# ---- GraphQL: (document, intended id); "UNCLASSIFIED" where the catalog maps the field to nothing.
MUT = [
    ("mergePullRequest", "pullRequestId", "pr.merge"),
    ("addPullRequestReview", "pullRequestId", "pr.review.approve"),
    ("deleteRef", "refId", "branch.delete.remote"),
    ("createRepository", "name", "repo.create"),
    ("updateRef", "refId", "git.push.force"),
    ("enablePullRequestAutoMerge", "pullRequestId", "pr.merge.auto"),
    ("updateRepository", "repositoryId", "repo.settings.merge"),
    ("createIssue", "repositoryId", "issue.create"),
    ("addComment", "subjectId", "issue.comment"),
    ("deleteRepository", "repositoryId", "UNCLASSIFIED"),
]


def gql_forms(field, arg):
    call = '%s(input: {%s: "x"}) { clientMutationId }' % (field, arg)
    return [
        "mutation { %s }" % call,
        "mutation M { m1: %s }" % call,
        "mutation($i: %sInput!) { %s(input: $i) { clientMutationId } }" % (field[0].upper() + field[1:], field),
        "mutation { ...F } fragment F on Mutation { %s }" % call,
        "mutation { ...A } fragment A on Mutation { ...B } fragment B on Mutation { %s }" % call,
        "mutation { ... on Mutation { %s } }" % call,
        "# mutation { addComment }\nmutation {\n  %s\n}" % call,
        'mutation { addComment(input: {subjectId: "x", body: "a ( } { ) b"}) { clientMutationId } %s }' % call,
        'mutation { addComment(input: {subjectId: "x", body: """ ) } " { """}) { clientMutationId } %s }' % call,
        "mutation { %s @include(if: false) }" % call,
        "mutation,{,%s,}" % call,
        "mutation\t{\r\n%s\n}" % call,
        "query Q { viewer { login } } mutation M { %s }" % call,
    ]


GQL = []
for field, arg, aid in MUT:
    for d in gql_forms(field, arg):
        GQL.append((d, aid))

rows = []   # (kind, intended, command)


def mut(intended, cmd):
    rows.append(("mutating", intended, cmd))


def ben(cmd):
    rows.append(("benign", "-", cmd))


NOISE_CURL = ["", "-s", "-sS", "-f", "-sSf", "-L", "-i", "-v", "--compressed", "-H 'Accept: application/vnd.github+json'",
              "-H 'Authorization: token x'", "-o /dev/null", "-w '%{http_code}'", "--retry 2", "-m 30",
              "--connect-timeout 5", "-A ua", "--fail-with-body"]
# ("time" "out": the static check reads every .sh line for an unguarded call of that program; these only are judged)
WRAP = ["", "env A=1 ", "command ", "time" "out 30 ", "nohup ", "/usr/bin/", "true && ", "echo go; ", "A=1 B=2 "]


def curl_method_forms(m):
    return ["-X %s" % m, "-X%s" % m, "--request %s" % m, "--request=%s" % m, "-sX %s" % m, "-sSX%s" % m,
            "--expand-request %s" % m, "-X %s" % m.lower()]


def curl_body_forms(body):
    b = js(body)
    half = len(b) // 2
    return [
        ("-d %s" % sq(b), "inline"), ("-d%s" % sq(b), "inline"), ("--data %s" % sq(b), "inline"),
        ("--data=%s" % sq(b), "inline"), ("--data-raw %s" % sq(b), "inline"), ("--data-binary %s" % sq(b), "inline"),
        ("--json %s" % sq(b), "inline"), ("-sd %s" % sq(b), "inline"), ("--data-ascii %s" % sq(b), "inline"),
        ("--json %s --json %s" % (sq(b[:half]), sq(b[half:])), "inline"),
        ("-d @body.json", "file"), ("--data-binary @-", "file"), ("--json @body.json", "file"),
        ("--variable b=%s --expand-data '{{b}}'" % sq(b), "file"), ("--expand-json %s" % sq(b), "inline"),
        ("-T body.json", "file"),
        ("-d %s -d %s" % (sq(b[:half]), sq(b[half:])), "split"),
        ("--data-urlencode %s" % sq("p=" + b), "form"),
        ("-F %s" % sq("payload=" + b), "form"),
    ]


def curl_url_forms(path):
    u = "%s/%s" % (API, path)
    return [u, sq(u), "--url %s" % u, "--url=%s" % u, u.replace("api.github.com", "API.GITHUB.COM"),
            u + "?per_page=1", u.replace("https://", "http://"), "api.github.com/" + path,
            "%s/repos/%s/%s %s" % (API, O, R, u)]


# ---- curl, REST
for t in REST:
    m, path, body, aid = t[0], path_of(t), t[2], t[3]
    nb = ("-d %s " % sq(js(body))) if needs_body(t) else ""
    for mf, uf in itertools.product(curl_method_forms(m), curl_url_forms(path)):
        mut(aid, "curl %s %s %s%s" % (rng.choice(NOISE_CURL), mf, nb, uf))
    if body is not None:
        for (bf, kind), uf in itertools.product(curl_body_forms(body), curl_url_forms(path)[:4]):
            mf = "" if m == "POST" and kind != "file" and rng.random() < 0.5 else rng.choice(curl_method_forms(m))
            if bf.startswith("-T") and m == "PUT":
                mf = ""
            mut(aid, "curl %s %s %s %s" % (rng.choice(NOISE_CURL), mf, bf, uf))
    u = "%s/%s" % (API, path)
    b = "-d %s " % sq(js(body)) if body is not None else ""
    xm = "-X %s " % m
    for extra in ["--next %s%s%s" % (xm, b, u), "%s --next %s%s%s" % (API + "/user", xm, b, u)]:
        mut(aid, "curl %s" % extra)
    for ro in ["--request-target /%s %s/repos/%s/%s/issues" % (path, API, O, R),
               "--connect-to example.com:443:api.github.com:443 https://example.com/%s" % path,
               "-H 'Host: api.github.com' https://203.0.113.5/%s" % path,
               "--header='host: api.github.com' https://203.0.113.5/%s" % path,
               "--unix-socket /tmp/gh.sock %s" % u, "--resolve api.github.com:443:127.0.0.1 %s" % u,
               "-H @hdrs.txt https://203.0.113.5/%s" % path, "--variable h=x --expand-header '{{h}}' %s" % u]:
        mut(aid, "curl %s%s%s" % (xm, b, ro))
    for cfg in ["-K cfg.txt %s" % u, "--config=cfg.txt %s" % u, "-sK cfg.txt %s" % u,
                "--variable u=%s --expand-url '{{u}}'" % u, "--url @urls.txt"]:
        mut(aid, "curl %s%s%s" % (xm, b, cfg))
    for w in WRAP:
        mut(aid, "%scurl %s%s%s" % (w, xm, b, u))


# ---- wget, REST
def wget_method_forms(m):
    return ["--method=%s" % m, "--method %s" % m, "-e method=%s" % m, "-qe method=%s" % m, "--execute=method=%s" % m]


for t in REST:
    m, path, body, aid = t[0], path_of(t), t[2], t[3]
    u = "%s/%s" % (API, path)
    b = js(body) if body is not None else ""
    noise = ["", "-q", "-qO-", "-O /dev/null", "-S", "--no-check-certificate", "-nv", "--header='Accept: x'"]
    for mf in wget_method_forms(m):
        bodies = ["--body-data=%s" % sq(b), "--body-data %s" % sq(b), "-e body_data=%s" % sq(b),
                  "--body-file=body.json"] if body is not None else [""]
        for bf in bodies:
            mut(aid, "wget %s %s %s %s" % (rng.choice(noise), mf, bf, u))
    if m == "POST" and body is not None:
        for bf in ["--post-data=%s" % sq(b), "--post-data %s" % sq(b), "-e post_data=%s" % sq(b),
                   "-qe post_data=%s" % sq(b), "--post-file=body.json", "--post-file body.json"]:
            mut(aid, "wget %s %s %s" % (rng.choice(noise), bf, u))
    for ro in ["--header='Host: api.github.com' https://203.0.113.5/%s" % path, "-i urls.txt",
               "--input-file=urls.txt", "--config=wgetrc %s" % u, "-e input=urls.txt"]:
        mut(aid, "wget --method=%s %s" % (m, ro))


# ---- httpie and xh, REST
def items_of(body):
    out = []
    for k, v in (body or {}).items():
        out.append("%s=%s" % (k, sq(v)) if isinstance(v, str) else "%s:=%s" % (k, js(v)))
    return " ".join(out)


for prog in ("http", "https", "xh", "xhs"):
    for t in REST:
        m, path, body, aid = t[0], path_of(t), t[2], t[3]
        host_path = "api.github.com/" + path
        it = items_of(body)
        forms = [
            "%s %s %s %s" % (prog, m, host_path, it), "%s %s %s/%s %s" % (prog, m.lower(), API, path, it),
            "%s --ignore-stdin %s %s %s" % (prog, m, host_path, it), "%s -I %s %s %s" % (prog, m, host_path, it),
            "%s %s %s %s Accept:application/json" % (prog, m, host_path, it),
            "%s --timeout 5 %s %s %s" % (prog, m, host_path, it), "%s -v %s %s %s" % (prog, m, host_path, it),
            "%s %s %s %s" % (prog, m, host_path, " ".join(x + "=@f.txt" for x in (body or {"a": 1}))),
            "%s %s %s --raw %s" % (prog, m, host_path, sq(js(body or {}))),
            "%s %s https://203.0.113.5/%s Host:api.github.com %s" % (prog, m, path, it),
            "%s --session=s %s https://203.0.113.5/%s %s" % (prog, m, path, it),
            "%s %s %s" % (prog, host_path, it if it else "a=b"),
            "%s -f %s %s %s" % (prog, m, host_path, it), "%s --form %s %s %s" % (prog, m, host_path, it),
        ] + ([] if needs_body(t) else ["%s %s %s" % (prog, m, host_path)])
        for f in forms:
            mut(aid if body is not None or "=@" not in f else aid, f)


# ---- gh api, REST
def gh_method_forms(m):
    return ["-X %s" % m, "-X%s" % m, "--method %s" % m, "--method=%s" % m, "-iX %s" % m, "-iX%s" % m, "-X=%s" % m]


def gh_field_forms(body):
    out = []
    for k, v in body.items():
        val = v if isinstance(v, str) else json.dumps(v)
        out.append(rng.choice(["-f %s=%s", "-f%s=%s", "-F %s=%s", "-F%s=%s", "--field %s=%s", "--field=%s=%s",
                               "--raw-field %s=%s", "-f=%s=%s"]) % (k, sq(val) if " " in val else val))
    return " ".join(out)


for t in REST:
    m, path, body, aid = t[0], path_of(t), t[2], t[3]
    ph = t[1].replace("{n}", N).replace("{o}/{r}", "{owner}/{repo}")
    for mf, ep in itertools.product(gh_method_forms(m), [path, "/" + path, ph, "%s/%s" % (API, path)]):
        fields = gh_field_forms(body) if body else ""
        mut(aid, "gh api %s %s %s %s" % (rng.choice(["", "-H 'Accept: x'", "-HAccept:x", "--silent", "-i", "--jq .x"]),
                                        mf, ep, fields))
    if body:
        if m == "POST":
            mut(aid, "gh api %s %s" % (path, gh_field_forms(body)))
        for extra in ["--input body.json", "--input=body.json", "--input -", "-F %s=@v.txt" % list(body)[0]]:
            mut(aid, "gh api -X %s %s %s" % (m, path, extra))
    nf = gh_field_forms(body) if needs_body(t) else ""
    for w in WRAP:
        mut(aid, "%sgh api -X %s %s %s" % (w, m, path, nf))
    mut(aid, "gh -R me/other api -X %s %s %s" % (m, path, nf))


# ---- GraphQL in every client
for doc, aid in GQL:
    body = js({"query": doc})
    escaped = body.replace("mutation", "mu\\u0074ation", 1)
    mut(aid, "gh api graphql -f query=%s" % sq(doc))
    mut(aid, "gh api graphql -F query=%s" % sq(doc))
    mut(aid, "gh api graphql --raw-field=query=%s" % sq(doc))
    mut(aid, "gh api graphql -fquery=%s -f v=1" % sq(doc))
    mut(aid, "gh api -X POST graphql --field query=%s" % sq(doc))
    for bf in ["-d %s" % sq(body), "--json %s" % sq(body), "--data-raw %s" % sq(body), "-d %s" % sq(escaped),
               "--data-binary %s" % sq(escaped), "-sd %s" % sq(body)]:
        mut(aid, "curl -H 'Authorization: bearer x' %s %s/graphql" % (bf, API))
    mut(aid, "wget --post-data=%s %s/graphql" % (sq(body), API))
    mut(aid, "http POST api.github.com/graphql query=%s" % sq(doc))
    mut(aid, "xh POST api.github.com/graphql query:=%s" % sq(json.dumps(doc)))
    mut(aid, "curl --json %s --json %s %s/graphql" % (sq(body[:9]), sq(body[9:]), API))
GQL_FILE = ["gh api graphql -F query=@q.graphql", "gh api graphql --input q.json", "curl -d @q.json %s/graphql" % API,
            "curl --data-binary @- %s/graphql" % API, "gh api graphql -f query=\"$Q\"",
            "curl -d 'query=mutation{mergePullRequest}' %s/graphql" % API,
            "curl --variable m=mutation --expand-json '{\"query\":\"{{m}}{x}\"}' %s/graphql" % API,
            "curl -G -d 'query=mutation{x}' %s/graphql" % API,
            "curl -d '{\"query\":\"mutation{a}\",\"query\":\"mutation{b}\"}' %s/graphql" % API,
            "curl -d '[{\"query\":\"mutation{mergePullRequest}\"}]' %s/graphql" % API]
for c in GQL_FILE:
    mut("UNCLASSIFIED", c)
# A # comment ends at a newline, which the shell tokeniser hands PG as a space: the mutation after it must not hide.
for prog in ("gh api graphql -f operationName=M -f query=%s", "http --ignore-stdin POST api.github.com/graphql query=%s"):
    for field, arg, aid in MUT:
        doc = 'query Q { viewer { login } } # x\nmutation M { %s(input: {%s: "x"}) { clientMutationId } }' % (field, arg)
        mut(aid, prog % sq(doc))

# ---- benign: reads and other hosts
READS = ["repos/me/app", "repos/me/app/pulls?state=open", "repos/me/app/issues/5/comments", "user", "rate_limit",
         "repos/me/app/actions/runs", "search/issues?q=repo:me/app", "repos/me/app/contents/README.md"]
for p in READS:
    u = "%s/%s" % (API, p)
    for f in ["curl %s" % sq(u), "curl -s %s" % sq(u), "curl -fsSL -H 'Accept: x' %s" % sq(u),
              "curl -X GET %s" % sq(u), "curl -G -d per_page=1 %s" % sq(u), "curl --url %s -o out.json" % sq(u),
              "curl -sS --request=GET %s" % sq(u),
              "wget -qO- %s" % sq(u), "wget --method=GET %s" % sq(u),
              "http GET %s" % sq(u), "https --ignore-stdin %s" % sq(u), "xh get %s" % sq(u), "xhs -I %s" % sq(u),
              "gh api %s" % sq(p), "gh api --paginate %s" % sq(p), "gh api %s --jq .x" % sq(p),
              "gh api -X GET %s -f per_page=1" % sq(p.split("?")[0]), "gh api -H 'Accept: x' %s" % sq(p),
              "command gh api %s" % sq(p), "time" "out 10 curl -s %s" % sq(u)]:
        ben(f)
QUERIES = ["query { viewer { login } }", "{ viewer { login } }", "query Q($o: String!) { repository(owner: $o, name: \"app\") { id } }",
           "query { ...F } fragment F on Query { viewer { login } }", "query { a: viewer { login } }",
           "query { viewer { login } } # mutation { mergePullRequest }",
           "query { repository(owner: \"me\", name: \"app\") { issue(number: 1) { body } } }",
           'query { search(query: "mutation { x }", type: ISSUE, first: 1) { issueCount } }',
           "query { viewer { mergePullRequest: login } }", "{ ... on Query { viewer { login } } }"]
for q in QUERIES:
    body = js({"query": q})
    for f in ["gh api graphql -f query=%s" % sq(q), "gh api graphql --raw-field=query=%s" % sq(q),
              "curl -d %s %s/graphql" % (sq(body), API), "curl --json %s %s/graphql" % (sq(body), API),
              "http --ignore-stdin POST api.github.com/graphql query=%s" % sq(q),
              "xh POST api.github.com/graphql query=%s" % sq(q),
              "wget -qO- --post-data=%s %s/graphql" % (sq(body), API)]:
        ben(f)
OTHER = ["https://example.com/x", "http://localhost/api", "http://127.0.0.1:3000/hook", "https://registry.npmjs.org/x"]
for u in OTHER:
    for f in ["curl %s" % u, "curl -X POST -d '{\"a\":1}' %s" % u, "curl --json '{\"a\":1}' %s" % u,
              "curl -F f=@a.txt %s" % u, "curl -T a.txt %s" % u, "wget -q %s" % u, "wget --post-data=a=1 %s" % u,
              "http POST %s a=1" % u, "xh PUT %s a=1" % u, "https --ignore-stdin DELETE %s" % u,
              "curl -X DELETE %s" % u, "curl -d @body.json %s" % u]:
        ben(f)
for f in ["curl --unix-socket /var/run/docker.sock http://localhost/containers/json",
          "curl -X POST --unix-socket /var/run/docker.sock http://localhost/containers/x/stop",
          "curl --connect-to example.com:443:localhost:8443 https://example.com/x",
          "curl -X POST -d x --connect-to example.com:443:127.0.0.1:8443 https://example.com/x",
          "curl --resolve example.com:443:127.0.0.1 -X PUT -d x https://example.com/x",
          "curl -H 'Host: dev.local' -X POST -d x http://127.0.0.1:8080/x",
          "curl --request-target /other -X DELETE http://localhost/x",
          "xh --unix-socket /tmp/app.sock POST http://localhost/x a=1",
          "http POST http://localhost/x Host:dev.local a=1"]:
    ben(f)

seen, uniq = set(), []
for r in rows:
    key = r[2].strip()
    if key not in seen:
        seen.add(key)
        uniq.append((r[0], r[1], key))


def client(cmd):
    for c in ("gh api", "curl", "wget", "xhs", "xh", "https", "http"):
        if (" %s " % c) in (" %s " % cmd).replace("/usr/bin/", " "):
            return c
    return "?"


# The full product is several times what the suite needs: a stratified sample keeps every (client, intended id)
# group, round-robin in a seeded order, until `want` mutating calls are drawn (0 = all of them). Benign calls are
# all kept.
muts = [r for r in uniq if r[0] == "mutating"]
if want and len(muts) > want:
    groups = {}
    for r in muts:
        groups.setdefault((client(r[2]), r[1]), []).append(r)
    order = sorted(groups)
    for g in order:
        rng.shuffle(groups[g])
    rng.shuffle(order)
    picked = []
    while len(picked) < want:
        for g in order:
            if groups[g] and len(picked) < want:
                picked.append(groups[g].pop())
    muts = picked
uniq = muts + [r for r in uniq if r[0] == "benign"]
with open(out_path, "w", encoding="utf-8") as f:
    for kind, aid, cmd in uniq:   # JSON lines: a GraphQL document keeps its newlines (a # comment ends at one)
        f.write(json.dumps({"kind": kind, "id": aid, "cmd": cmd}, sort_keys=True) + "\n")
GEN
python3 "$T/gen.py" "$CORPUS" "${FUZZ_SEED:-349}" "${FUZZ_MUTATING:-2200}"
python3 "$T/gen.py" "$T/corpus-again.jsonl" "${FUZZ_SEED:-349}" "${FUZZ_MUTATING:-2200}"
NMUT="$(jq -r 'select(.kind=="mutating") | .kind' "$CORPUS" | wc -l | tr -d ' ')"
NBEN="$(jq -r 'select(.kind=="benign") | .kind' "$CORPUS" | wc -l | tr -d ' ')"
judge "at least 2,000 mutating calls (got $NMUT)" yes "$([ "$NMUT" -ge 2000 ] && echo yes || echo no)"
judge "at least 200 benign calls (got $NBEN)" yes "$([ "$NBEN" -ge 200 ] && echo yes || echo no)"
judge "the corpus is the same on a second build (deterministic)" yes \
  "$([ -s "$CORPUS" ] && cmp -s "$CORPUS" "$T/corpus-again.jsonl" && echo yes || echo no)"

PG="$ROOT/hooks/permission-guard.sh"
JOBS_N="$(pg_batch_jobs)"

section "the agreement check bites: a planted divergence is caught (tests/lib/pg-batch.sh)"
PLANT="$T/plant.ndjson"
{
  printf '{"cmd":"ls -la","cwd":"%s","host":"claude"}\n' "$WORK"
  printf '{"cmd":"gh pr merge 5 --squash","cwd":"%s","host":"claude"}\n' "$WORK"
  printf '{"cmd":"gh pr merge 5 --squash","cwd":"%s","host":"codex"}\n' "$WORK"
  printf '{"cmd":"git push --force origin feat","cwd":"%s","host":"cursor"}\n' "$WORK"
  printf '{"cmd":"curl -X DELETE https://api.github.com/repos/me/app","cwd":"%s","host":"opencode"}\n' "$WORK"
  printf '{"cmd":"git status","cwd":"%s","host":"codex"}\n' "$WORK"
} > "$PLANT"
# A batch entry that has drifted: its third answer is an allow where the hook asks. The runner is given this
# stub as the batch side; the agreement check keeps the real hook as the single-call side.
STUB="$T/stub-guard.sh"
cat > "$STUB" <<SH
#!/usr/bin/env bash
bash "$PG" "\$@" | awk 'NR == 3 { print "{}"; next } { print }'
SH
pg_batch_run "$STUB" judge "$PLANT" "$T/plant.out" 1; rc=$?
judge "the stubbed batch runs: one line per input, exit 0" "0 6" "$rc $(wc -l < "$T/plant.out" | tr -d ' ')"
judge "  ... and its third answer is the planted allow" '{}' "$(sed -n 3p "$T/plant.out")"
pg_batch_agree "$PG" judge "$PLANT" "$T/plant.out" all 1 "$T/plant.report" "$JOBS_N" >/dev/null; rc=$?
judge "the agreement check fails on it (exit 1)" 1 "$rc"
judge "  ... naming line 3 and no other" 3 "$(grep '^DIFF' "$T/plant.report" | cut -f2 | tr '\n' ' ' | sed 's/ $//')"
judge "  ... the real hook denied what the stub allowed" "deny allow" \
  "$(grep '^DIFF' "$T/plant.report" | cut -f3,4 | jq -r '.decision' 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
judge "  ... checked 6, 1 diverged" "6 1" "$(grep '^AGREE' "$T/plant.report" | cut -f2,3 | tr '\t' ' ')"
pg_batch_run "$PG" judge "$PLANT" "$T/plant.ok" 2; rc=$?
judge "control: the real batch entry over 2 shards: one line per input, exit 0" "0 6" "$rc $(wc -l < "$T/plant.ok" | tr -d ' ')"
pg_batch_agree "$PG" judge "$PLANT" "$T/plant.ok" all 1 "$T/plant.ok.report" "$JOBS_N" >/dev/null; rc=$?
judge "  ... agrees with the real hook on all 6 (exit 0)" "0 6 0" "$rc $(grep '^AGREE' "$T/plant.ok.report" | cut -f2,3 | tr '\t' ' ')"
pg_batch_agree "$PG" judge "$PLANT" "$T/plant.ok" 2 7 "$T/plant.two.report" "$JOBS_N" >/dev/null
judge "a sample of 2 checks 2" "2 0" "$(grep '^AGREE' "$T/plant.two.report" | cut -f2,3 | tr '\t' ' ')"
pg_batch_run "$PG" classify "$PLANT" "$T/plant.cls" 2; rc=$?
judge "classify-batch over 2 shards: one line per input, exit 0" "0 6" "$rc $(wc -l < "$T/plant.cls" | tr -d ' ')"
pg_batch_agree "$PG" classify "$PLANT" "$T/plant.cls" all 1 "$T/plant.cls.report" "$JOBS_N" >/dev/null; rc=$?
judge "  ... agrees with --classify on all 6" "0 6 0" "$rc $(grep '^AGREE' "$T/plant.cls.report" | cut -f2,3 | tr '\t' ' ')"
cat > "$STUB" <<SH
#!/usr/bin/env bash
bash "$PG" "\$@" | awk 'NR == 2 { next } { print }'
SH
pg_batch_run "$STUB" judge "$PLANT" "$T/plant.short" 1 2>/dev/null; rc=$?
judge "a shard that prints fewer lines than it read is a runner failure (exit 1)" 1 "$rc"
# Security review F4 (task-005): a batch whose every answer is a fail-closed deny ("its engine exited 1") must
# not pass for the lines the hook denies, and two lines of the same decision must not pass swapped.
cat > "$STUB" <<SH
#!/usr/bin/env bash
bash "$PG" "\$@" | awk '{ print "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"tamirs-superpowers permission guard: its engine exited 1 without a verdict, so the call is denied (fail closed, ADR 004 D4).\"}}" }'
SH
pg_batch_run "$STUB" judge "$PLANT" "$T/plant.ec" 1; rc=$?
judge "a batch answering every line with an engine-exited-1 deny still prints one line per input" "0 6" "$rc $(wc -l < "$T/plant.ec" | tr -d ' ')"
pg_batch_agree "$PG" judge "$PLANT" "$T/plant.ec" all 1 "$T/plant.ec.report" "$JOBS_N" >/dev/null; rc=$?
judge "  ... and the agreement check fails on every one of the 6, the hook's own denies included (exit 1)" "1 6 6" "$rc $(grep '^AGREE' "$T/plant.ec.report" | cut -f2,3 | tr '\t' ' ')"
judge "  ... because a judged deny carries its own reason, which the stub's generic one does not match" yes \
  "$(grep '^DIFF' "$T/plant.ec.report" | cut -f3,4 | jq -R -r 'split("\t") | (.[0] | fromjson) as $s | (.[1] | fromjson) as $b | select($s.decision == "deny") | ($s.reason != $b.reason)' 2>/dev/null | sort -u | grep -qx true && echo yes || echo no)"
# lines 3 (gh pr merge, codex) and 5 (curl -X DELETE, opencode) are both denies: swapped, each quotes the other's command
awk 'NR == 3 { l3 = $0; next } NR == 4 { l4 = $0; next } NR == 5 { print; print l4; print l3; next } { print }' "$T/plant.ok" > "$T/plant.swap"
judge "two same-decision lines swapped: both still denies" "deny deny" "$(sed -n '3p;5p' "$T/plant.swap" | jq -r '.hookSpecificOutput.permissionDecision' | tr '\n' ' ' | sed 's/ $//')"
pg_batch_agree "$PG" judge "$PLANT" "$T/plant.swap" all 1 "$T/plant.swap.report" "$JOBS_N" >/dev/null; rc=$?
judge "  ... the agreement check fails on exactly lines 3 and 5 (exit 1)" "1 3 5" "$rc $(grep '^DIFF' "$T/plant.swap.report" | cut -f2 | tr '\n' ' ' | sed 's/ $//')"

section "every call, judged by the real guard in batch ($JOBS_N shards)"
python3 - "$CORPUS" "$WORK" "$T/b-classify.in" "$T/b-claude.in" "$T/b-codex.in" <<'MK'
import json, sys
corpus, cwd, f_cls, f_cl, f_cx = sys.argv[1:6]
rows = [json.loads(l) for l in open(corpus, encoding="utf-8") if l.strip()]


def payload(cmd, codex):
    p = {"cwd": cwd, "hook_event_name": "PreToolUse", "permission_mode": "default", "tool_name": "Bash",
         "tool_use_id": "call-1", "tool_input": {"command": cmd, "description": "fuzz"}}
    if codex:
        p["turn_id"] = "01a1480e-39dc-7131-8dd0-5becbd825a5e"
    return json.dumps(p)


with open(f_cls, "w", encoding="utf-8") as a, open(f_cl, "w", encoding="utf-8") as b, open(f_cx, "w", encoding="utf-8") as c:
    for d in rows:
        a.write(json.dumps({"cmd": d["cmd"], "cwd": cwd, "host": "claude"}) + "\n")
        b.write(payload(d["cmd"], False) + "\n")
        c.write(payload(d["cmd"], True) + "\n")
MK
NROWS="$(wc -l < "$CORPUS" | tr -d ' ')"
T_BATCH="$SECONDS"
# The three batches side by side, each over JOBS_N shards: a judge line costs the resolver as well as the
# tokeniser, a classify line the tokeniser alone, so one after the other would leave cores idle.
{ pg_batch_run "$PG" classify "$T/b-classify.in" "$T/b-classify.out" "$JOBS_N" 2> "$T/b-classify.err"; echo $? > "$T/b-classify.rc"; } &
{ pg_batch_run "$PG" judge "$T/b-claude.in" "$T/b-claude.out" "$JOBS_N" 2> "$T/b-claude.err"; echo $? > "$T/b-claude.rc"; } &
{ pg_batch_run "$PG" judge "$T/b-codex.in" "$T/b-codex.out" "$JOBS_N" 2> "$T/b-codex.err"; echo $? > "$T/b-codex.rc"; } &
wait
for what in classify claude codex; do
  case "$what" in
    classify) label="--classify-batch" ;;
    claude) label="--judge-batch, Claude payloads" ;;
    codex) label="--judge-batch, Codex payloads" ;;
  esac
  judge "$label: $NROWS calls, one line each, every shard exit 0" "0 $NROWS" "$(cat "$T/b-$what.rc" 2>/dev/null || echo none) $(wc -l < "$T/b-$what.out" | tr -d ' ')"
  [ -s "$T/b-$what.err" ] && head -3 "$T/b-$what.err" | sed 's/^/    /'
done
T_BATCH=$((SECONDS - T_BATCH))
printf '  info batch: %s lines in %ss, three batches side by side over %s shards each\n' "$((NROWS * 3))" "$T_BATCH" "$JOBS_N"

python3 - "$CORPUS" "$T/b-classify.out" "$T/b-claude.out" "$T/b-codex.out" > "$T/results.txt" <<'RUN'
import json, sys

corpus, f_cls, f_cl, f_cx = sys.argv[1:5]
rows = [(d["kind"], d["id"], d["cmd"]) for d in (json.loads(l) for l in open(corpus, encoding="utf-8") if l.strip())]


def lines_of(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    if text.endswith("\n"):
        text = text[:-1]
    return text.split("\n") if text else []


cls, cl, cx = lines_of(f_cls), lines_of(f_cl), lines_of(f_cx)
if not (len(rows) == len(cls) == len(cl) == len(cx)):
    print("FAIL\tbatch\t-\t%d rows but %d classify, %d claude, %d codex lines\t\"\"" % (len(rows), len(cls), len(cl), len(cx)))
    rows = []


def verdict(line):
    try:
        d = json.loads(line)
    except ValueError:
        return "invalid"
    if not isinstance(d, dict):
        return "invalid"
    return (d.get("hookSpecificOutput") or {}).get("permissionDecision") or "allow"


def judge(i):
    kind, aid, cmd = rows[i]
    c, denied = None, None
    try:
        c = json.loads(cls[i])
    except ValueError:
        c = None
    if isinstance(c, dict) and "verdict" in c:   # the batch's deny line where --classify would print no object
        denied, c = c.get("reason", ""), None
    v_cl, v_cx = verdict(cl[i]), verdict(cx[i])
    why = []
    if c is None:
        why.append("classify denied: %s" % (denied or "not JSON: %r" % cls[i][:200]))
    elif kind == "mutating":
        if not c["unclassified"] and aid not in c["ids"]:
            why.append("read as %s, not %s and not UNCLASSIFIED" % (",".join(c["ids"]) or "no id", aid))
        if aid == "UNCLASSIFIED" and not c["unclassified"]:
            why.append("expected UNCLASSIFIED, got %s" % (",".join(c["ids"]) or "no id"))
        if not c["resolver_calls"] and not c["pg_deny"]:
            why.append("nothing put to the resolver")
        if v_cl not in ("ask", "deny"):
            why.append("claude %s" % v_cl)
        if v_cx != "deny":
            why.append("codex %s" % v_cx)
    else:
        if c["unclassified"]:
            why.append("UNCLASSIFIED: %s" % "; ".join(c["unclassified_from"])[:160])
        if c["resolver_calls"]:
            why.append("put to the resolver: %s" % ",".join(j["id"] for j in c["resolver_calls"]))
        if v_cl != "allow" or v_cx != "allow":
            why.append("claude %s, codex %s" % (v_cl, v_cx))
    return kind, aid, cmd, v_cl, v_cx, why


res = [judge(i) for i in range(len(rows))]
tally = {}
for kind, aid, cmd, cl, cx, why in res:
    t = tally.setdefault(kind, {"n": 0, "fail": 0, "claude": {}, "codex": {}})
    t["n"] += 1
    t["claude"][cl] = t["claude"].get(cl, 0) + 1
    t["codex"][cx] = t["codex"].get(cx, 0) + 1
    if why:
        t["fail"] += 1
        print("FAIL\t%s\t%s\t%s\t%s" % (kind, aid, " | ".join(why), json.dumps(cmd)))
for kind, t in sorted(tally.items()):
    print("TALLY\t%s\t%d\t%d\t%s\t%s" % (kind, t["n"], t["fail"], json.dumps(t["claude"], sort_keys=True),
                                         json.dumps(t["codex"], sort_keys=True)))
RUN
while IFS="$(printf '\t')" read -r tag kind n fails cl cx; do
  [ "$tag" = TALLY ] || continue
  printf '  %s: %s calls; claude %s; codex %s\n' "$kind" "$n" "$cl" "$cx"
  if [ "$kind" = mutating ]; then
    judge "every mutating call asks or denies on Claude, denies on Codex, and reaches its id or UNCLASSIFIED" 0 "$fails"
  else
    judge "every benign call is allowed on Claude and Codex, unclassified by nothing, put to no resolver" 0 "$fails"
  fi
done < "$T/results.txt"
judge "both kinds were judged" 2 "$(grep -c '^TALLY' "$T/results.txt")"
for kind in mutating benign; do
  if grep -q "^FAIL	$kind" "$T/results.txt"; then
    printf '  first %s failures (of %s):\n' "$kind" "$(grep -c "^FAIL	$kind" "$T/results.txt")"
    grep "^FAIL	$kind" "$T/results.txt" | head -15 | cut -c1-400 | sed 's/^/    /'
  fi
done

# The divergence detector: the same seeded rows of the corpus (one seed, one line count, so one pick across the
# three files) through the real single-call path, against their batch lines.
SAMPLE="${FUZZ_SAMPLE:-150}"
case "$SAMPLE" in all|[1-9]*) ;; *) echo "FATAL: FUZZ_SAMPLE must be a count or 'all', not '$SAMPLE'" >&2; exit 1 ;; esac
section "a seeded sample of $SAMPLE calls through the real hook agrees with the batch, line for line (seed ${FUZZ_SEED:-349})"
T_SAMPLE="$SECONDS"
for what in classify claude codex; do
  mode=judge; [ "$what" = classify ] && mode=classify
  pg_batch_agree "$PG" "$mode" "$T/b-$what.in" "$T/b-$what.out" "$SAMPLE" "${FUZZ_SEED:-349}" "$T/agree-$what.txt" "$JOBS_N" > "$T/agree-$what.sum" 2>&1
  checked="$(grep '^AGREE' "$T/agree-$what.txt" 2>/dev/null | cut -f2)"
  diffs="$(grep '^AGREE' "$T/agree-$what.txt" 2>/dev/null | cut -f3)"
  case "$what" in
    classify) label="--classify on the sample agrees with --classify-batch (${checked:-0} checked)" ;;
    claude) label="the hook on the sample's Claude payloads agrees with --judge-batch (${checked:-0} checked)" ;;
    codex) label="the hook on the sample's Codex payloads agrees with --judge-batch (${checked:-0} checked)" ;;
  esac
  judge "$label" 0 "${diffs:-no AGREE line: $(head -c 200 "$T/agree-$what.sum")}"
  if [ "${diffs:-1}" != 0 ] && grep -q '^DIFF' "$T/agree-$what.txt" 2>/dev/null; then
    printf '  first divergences (%s, line: single-call | batch):\n' "$what"
    grep '^DIFF' "$T/agree-$what.txt" | head -5 | cut -f2- | cut -c1-500 | sed 's/^/    /'
  fi
done
if [ "$SAMPLE" != all ]; then
  judge "the sample is the size asked for (or the corpus, if smaller)" yes \
    "$([ "$(grep '^AGREE' "$T/agree-claude.txt" | cut -f2)" = "$SAMPLE" ] || [ "$NROWS" -lt "$SAMPLE" ] && echo yes || echo no)"
fi
T_SAMPLE=$((SECONDS - T_SAMPLE))
printf '  info sample: %s single calls in %ss\n' "$(( ${checked:-0} * 3 ))" "$T_SAMPLE"

section "the real config and state dirs were never touched"
judge "real-home witness unchanged" "$REAL_BEFORE" "$(witness)"

printf '\n  info wall time: %ss (corpus + batch %ss + sample %ss + the rest)\n' "$((SECONDS - T_START))" "$T_BATCH" "$T_SAMPLE"
harness_summary
