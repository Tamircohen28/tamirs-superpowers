#!/usr/bin/env bash
# permission-guard.sh — PreToolUse permission guard (PG) for Bash/Shell and the
# bundled GitHub MCP server's tools (ADR 004 item 4; D1, D2, D7, D8).
#
# WHAT IT DECIDES
#   Every shell command and GitHub MCP call is mapped onto the action ids of
#   core/permissions/actions.json (D1) — the argv forms, the REST paths, GraphQL
#   mutations, refspecs and HTTP clients the catalog lists as equivalents — and
#   each id is put to scripts/resolve-permission.sh (D4), the one implementation
#   of levels and precedence. The answer is the strictest verdict of every id the
#   call reaches (deny > ask > allow; a tie reports the highest R). A command that
#   maps to no id but carries one of the catalog's mutation markers
#   (unclassified.mutation_markers: `git push`, api.github.com, graphql, ...; and
#   unclassified.mutation_marker_patterns, the token command and variables, kept
#   as patterns so no shipped file spells a credential name) or runs `gh` is
#   UNCLASSIFIED, which is R4: never automatic.
#
#   R0/R1 ids with no context raise and the "L1 only" ids (notify.send,
#   net.post.external, deps.install, daemon.*) need no resolver call: D8 puts L2
#   shell enforcement at R2-R4, and D1 gives those ids no L2 point.
#
# FAST PATH
#   A command none of whose words can reach a guarded id (no gh, no curl, no git
#   push/reset/commit/..., no agent CLI, no tty driver, no package manager, no
#   marker) is allowed by a bash-only pre-filter: no python, no resolver. The
#   pre-filter strips quotes and backslashes first, so `g"i"t push` cannot hide.
#   Everything else is tokenised by lib/command-tokens.sh (shared with the
#   concurrency guard) and matched by the engine below.
#
# CONDITIONS (D4: unknown never holds; a raise or deny applies unless false)
#   Read locally: default_branch and tag_ref for git push and the GitHub MCP/REST
#   branch writes (refs/remotes/<remote>/HEAD; main and master always count as
#   default), uncommitted_changes, drops_unpushed_commits, discards_work,
#   unmerged_no_remote_copy, unmerged_commits (only "fully merged" is shown) and
#   workflow_hook_or_policy_path.
#   Read from GitHub, through lib/permission-conditions.sh, under ONE deadline of
#   3 s for the whole call (D8: well under the host timeout): the default branch
#   when refs/remotes/<remote>/HEAD does not resolve (gh repo view of the
#   remote's push URL), and required_check_failing_or_pending for
#   `gh pr merge --admin` (gh pr checks --required). An error, a timeout or an
#   answer PG cannot read leaves the condition unknown, so its raise or deny
#   applies exactly as with no lookup at all.
#   Still unknown, so their raise or deny applies: protected_default_branch, PR
#   state, thread authorship, claims, lockfiles. A command whose working
#   directory or target environment PG cannot pin (more than one `cd`, a `cd` not
#   of the form `cd <dir> && …`, `export`/`source`/`unset`, GIT_DIR=…,
#   git -c/--git-dir, GH_REPO=… or --hostname on the merge) gets no repository
#   condition at all.
#
# PER HOST (D8)
#   claude  allow | ask | deny (hookSpecificOutput.permissionDecision). The ask
#           is the D5 host prompt and the only route for R4; headless it denies.
#   codex   deny only: a hook ask fails OPEN there (X1), so an ask is delivered
#           as a deny naming the out-of-session route. Every internal error is
#           trapped to a deny and the script always exits 0, because Codex lets
#           a call through on any other exit or on malformed output.
#   cursor  deny only: preToolUse drops ask and beforeShellExecution's forced
#           prompt stays unused until spike S1 is measured (D5, D8).
#   gemini  (GEMINI_SESSION_ID / GEMINI_PROJECT_DIR in env) deny only: a hook ask
#           hangs headless (G1). Wiring is task-005's.
#   The resolver is told the host (--host) so the option store and the "setting
#   that would allow it" are that host's.
#
# D5-D7 DUTIES
#   The call stamp (D8): a resolve-permission.sh call carrying --call <token> in
#   a command PG does not deny gets <state>/seen/<token> (dirs 0700), which the
#   resolver consumes as proof that PG ran. policy.edit forms that must never run
#   from agent Bash are denied outright: plugin-config.sh provision (D6) and the
#   host config CLIs `claude plugin configure`, `gemini extensions config` (D7).
#   Every other policy.edit form the catalog lists (plugin-config.sh writes,
#   confirm, setup.sh --permission-level) is R4: the Claude dialog asks, every
#   other host denies.
#
# FAIL CLOSED (D4, SR S-12)
#   Unparseable payload, no jq, no python3, a missing or corrupt catalog, a
#   resolver that is missing, exits non-zero, times out or prints no verdict, an
#   engine crash, an unexpected exit of this script: all deny, with the reason.
#   An empty payload (nothing to judge) is allowed, as every guard here does.
#
# NOT SEEN (D1 residual, ADR Open risks): aliases, eval, xargs, make, scripts and
# interpreters this catalog does not name, and anything assembled at runtime.
#
# INSPECTION (tests, debugging; read-only, never reached from a hook payload)
#   permission-guard.sh --classify '<command>' [cwd]
#   permission-guard.sh --classify-mcp <tool> '<args-json>' [cwd]
#       print, as JSON, the ids the call maps to, whether it is UNCLASSIFIED, the
#       resolver calls PG would make (id, --cond values, --target), the forms PG
#       denies outright, what the GitHub lookups found (notes) and whether the fast
#       path would have let it through. No resolver runs and nothing is written;
#       the GitHub lookups (reads, under the same deadline) do. A hook is never
#       given arguments.
#
# Bash 3.2 compatible. Needs jq (payload) and python3 (stdlib, -I -S).
set -uo pipefail

_PG_DONE=0

# Builtins-only deny for the paths where jq (or this script) cannot be trusted.
_pg_lit_deny() {
  local r="$1"
  r="${r//\\/\\\\}"; r="${r//\"/\\\"}"; r="${r//$'\n'/ }"; r="${r//$'\t'/ }"; r="${r//$'\r'/ }"
  if [ "${HOOK_PLATFORM:-claude}" = cursor ]; then
    printf '{"permission":"deny","user_message":"%s","agent_message":"%s"}\n' "$r" "$r"
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$r"
  fi
}

_pg_on_exit() {
  local rc=$?
  [ "$_PG_DONE" = 1 ] && return 0
  _PG_DONE=1
  _pg_lit_deny "tamirs-superpowers permission guard stopped before it could decide (exit $rc), so the call is denied (fail closed, ADR 004 D4, D8)."
  exit 0
}
trap _pg_on_exit EXIT
trap 'exit 1' INT TERM HUP

case "${BASH_SOURCE[0]}" in
  */*) _pg_here="${BASH_SOURCE[0]%/*}" ;;
  *) _pg_here=. ;;
esac
SCRIPT_DIR="$(CDPATH='' cd -- "$_pg_here" 2>/dev/null && pwd -P)" || exit 1
PG_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/.." 2>/dev/null && pwd -P)" || exit 1
unset _pg_here
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh" || exit 1
# shellcheck source=lib/command-tokens.sh
source "${SCRIPT_DIR}/lib/command-tokens.sh" || exit 1
# shellcheck source=lib/platform-tools.sh
source "${SCRIPT_DIR}/lib/platform-tools.sh" || exit 1

PG_MCP_PREFIX='mcp__plugin_tamirs-superpowers_github__'
PG_BUDGET="${PG_BUDGET_SECONDS:-20}"
case "$PG_BUDGET" in ''|*[!0-9]*) PG_BUDGET=20 ;; esac
[ "$PG_BUDGET" -gt 20 ] && PG_BUDGET=20

# _pg_finish <allow|ask|deny> <reason> — answer once, in the host's dialect.
_pg_finish() {
  local verdict="$1" reason="${2:-}"
  _PG_DONE=1
  case "$verdict" in
    allow) hook_allow ;;
    ask)
      printf '%s\n' "$reason" >&2
      hook_ask "$reason" ;;
    *)
      printf '%s\n' "$reason" >&2
      hook_deny "$reason" ;;
  esac
  exit 0
}

# _pg_candidate <command> — 0 when the command could reach a guarded id.
_pg_candidate() {
  local t="$1" b='(^|[[:space:];&|()`/!{])' e='([[:space:];&|)`]|$)'
  t="${t//[\'\"\\]/}"
  case "$t" in
    # Any *_TOKEN variable (wider than the catalog's two token names, which the engine reads from the catalog).
    *api.github.com*|*uploads.github.com*|*graphql*|*_TOKEN*|*'gh auth'*) return 0 ;;
    *resolve-permission.sh*|*plugin-config.sh*|*setup.sh*|*install.sh*|*enable.sh*|*SETUP_PERMISSION_LEVEL*) return 0 ;;
    *cleanup-after-merge.sh*|*cleanup.sh*|*resolve-thread.sh*|*update-issue-resume.sh*|*notify-pushover.sh*) return 0 ;;
    *collector.py*|*handoff.sh*|*enable-repo-merge-settings.sh*|*github-policy.sh*|*ensure-branch-protection.sh*|*capture-config.sh*) return 0 ;;
    *claude-code*|*gemini-cli*|*opencode-ai*|*@openai/codex*|*node-pty*) return 0 ;;
  esac
  if [ -n "${GH_HOST:-}" ]; then
    case "$t" in *"$GH_HOST"*) return 0 ;; esac
  fi
  [[ "$t" =~ $b(gh|curl|wget|http|https|xh|claude|codex|gemini|opencode|cursor-agent|agy|script|expect|unbuffer|tmux|screen|osascript|xdotool|npm|npx|pnpm|yarn|bun|bunx|uv|uvx|pip|pip3|pipx|cargo|bundle|gem|brew|docker|docker-compose|podman|kill|pkill|killall)$e ]] && return 0
  if [[ "$t" =~ ${b}git$e ]]; then
    [[ "$t" =~ (^|[^[:alnum:]_-])(push|reset|clean|checkout|restore|switch|stash|branch|tag|config|worktree|commit|merge|rebase|am|pull)([^[:alnum:]_-]|$) ]] && return 0
    case "$t" in *alias*|*hooksPath*|*hookspath*|*HUSKY*|*SKIP=*|*GIT_CONFIG*) return 0 ;; esac
  fi
  if [[ "$t" =~ ${b}(python|python3|node)$e ]]; then
    case "$t" in *pty*|*pip*|*cli.js*) return 0 ;; esac
  fi
  if [[ "$t" =~ ${b}go$e ]] && [[ "$t" =~ ${b}install$e ]]; then return 0; fi
  return 1
}

IFS= read -r -d '' _PG_ENGINE <<'PY' || true
import fnmatch, json, os, re, signal, subprocess, sys, time

ROOT, HOST, MODE = sys.argv[1], sys.argv[2], sys.argv[3]
BUDGET = float(sys.argv[4]) if len(sys.argv) > 4 else 20.0
T0 = time.time()
ASK_HOSTS = ("claude",)
UNCL = "UNCLASSIFIED"
SEP, NESTED = "\x1f", "\x1e"
CALL_RE = re.compile(r"\A[A-Za-z0-9_-]{8,128}\Z")
RANK = {"allow": 0, "ask": 1, "deny": 2}
RESOLVER = os.path.join(ROOT, "scripts", "resolve-permission.sh")
COND_LIB = os.path.join(ROOT, "hooks", "lib", "permission-conditions.sh")
NET_BUDGET = 3.0   # seconds, for every GitHub lookup of this call together (D8)


def answer(verdict, reason):
    sys.stdout.write(verdict + "\n" + " ".join(str(reason).split()) + "\n")
    sys.stdout.flush()
    sys.exit(0)


def left():
    return BUDGET - (time.time() - T0)


raw = sys.stdin.buffer.read().decode("utf-8", "surrogateescape")
ptext, _, segtext = raw.partition("\x1e\x1e\x1e\n")
try:
    PAY = json.loads(ptext)
    if not isinstance(PAY, dict):
        raise ValueError("not an object")
except ValueError:
    answer("deny", "tamirs-superpowers permission guard: the hook payload is not a JSON object, so the call "
           "cannot be judged (fail closed, ADR 004 D4).")
try:
    with open(os.path.join(ROOT, "core", "permissions", "actions.json"), encoding="utf-8") as f:
        CAT = json.load(f)
    ACTS = CAT["actions"]
    BYID = {a["id"]: a for a in ACTS}
    M = CAT["matching"]
    MARKERS = [m.strip() for m in CAT["unclassified"]["mutation_markers"] if m.strip()]
    MARKER_RX = [re.compile(x) for x in CAT["unclassified"]["mutation_marker_patterns"]]
    PFX = CAT["mcp"]["claude_prefix"]
    for a in ACTS:
        a["equivalents"], a["r"]
except Exception as e:  # noqa: BLE001 - any catalog defect is a deny
    answer("deny", "tamirs-superpowers permission guard: the action catalog core/permissions/actions.json is "
           "missing or corrupt (%s), so no call can be classified (fail closed, ADR 004 D4)." % e.__class__.__name__)

PREFIX = set(M["prefix_commands"]) | {"builtin", "stdbuf"}
PREFIX_VALUE_OPTS = {"sudo": {"-u", "-g", "-h", "-p", "-C", "-U", "-r", "-t"}, "env": {"-u", "-C", "-S"},
                     "timeout": {"-s", "-k", "--signal", "--kill-after"}, "nice": {"-n"}}
INTERP = {"bash", "sh", "zsh", "source", ".", "python", "python3", "node"}
HTTP = set(M["http_clients"])
API_HOSTS = ["api.github.com", "uploads.github.com"]
if os.environ.get("GH_HOST"):
    API_HOSTS.append(os.environ["GH_HOST"])
STD_DEFAULTS = ["main", "master"]
ENV_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
TARGET_ENV = re.compile(r"^(GH_REPO|GH_HOST|GH_ENTERPRISE_TOKEN|GIT_DIR|GIT_WORK_TREE|GIT_CONFIG_[A-Za-z0-9_]*|"
                        r"GIT_CONFIG_PARAMETERS|GIT_NAMESPACE|GIT_INDEX_FILE|GIT_OBJECT_DIRECTORY)=")
KNOWN_MCP = set(e["tool"][len(PFX):] for a in ACTS for e in a["equivalents"].get("mcp", []))


# --------------------------------------------------------------- tokens

SEGS = []
for line in segtext.split("\n"):
    if not line:
        continue
    nested = line.startswith(NESTED)
    if nested:
        line = line[1:]
    toks = line.split(SEP)
    if any(toks):
        SEGS.append({"nested": nested, "toks": toks})


def parse(toks):
    env, i = [], 0
    while i < len(toks):
        t = toks[i]
        if ENV_RE.match(t):
            env.append(t)
            i += 1
            continue
        name = os.path.basename(t)
        if name in PREFIX:
            i += 1
            vo = PREFIX_VALUE_OPTS.get(name, set())
            while i < len(toks) and (toks[i].startswith("-") or toks[i].isdigit()):
                i += 2 if toks[i] in vo else 1
            if name == "timeout" and i < len(toks) and re.fullmatch(r"\d+(\.\d+)?[smhd]?", toks[i]):
                i += 1
            continue
        break
    if i >= len(toks):
        return {"env": env, "argv0": None, "raw0": None, "all": [], "sub": [], "gopts": []}
    argv0, raw0, rest = os.path.basename(toks[i]), toks[i], toks[i + 1:]
    g = M["global_options"].get(argv0, {"value": [], "flag": []})
    longv = [v for v in g["value"] if v.startswith("--")]
    gopts, j = [], 0
    while j < len(rest):
        t = rest[j]
        if t in g["value"]:
            gopts.append((t, rest[j + 1] if j + 1 < len(rest) else None))
            j += 2
        elif any(t.startswith(v + "=") for v in longv):
            gopts.append(tuple(t.split("=", 1)))
            j += 1
        elif t in g["flag"]:
            j += 1
        else:
            break
    sub = rest[j:]
    if argv0 == "gh":
        clean, k = [], 0
        while k < len(sub):
            if sub[k] in g["value"]:
                gopts.append((sub[k], sub[k + 1] if k + 1 < len(sub) else None))
                k += 2
                continue
            if any(sub[k].startswith(v + "=") for v in longv):
                gopts.append(tuple(sub[k].split("=", 1)))
                k += 1
                continue
            clean.append(sub[k])
            k += 1
        sub = clean
    if argv0 == "git" and sub[:1] == ["push"]:
        # -uf is -u -f: a cluster of git push's boolean short flags is split so a force cannot hide in it.
        out_ = []
        for t in sub:
            if re.fullmatch(r"-[ufnvqd46]{2,}", t):
                out_ += ["-" + c for c in t[1:]]
            else:
                out_.append(t)
        sub = out_
        rest = rest[:j] + sub
    return {"env": env, "argv0": argv0, "raw0": raw0, "all": rest, "sub": sub, "gopts": gopts}


def gmatch(glob, tok):
    if fnmatch.fnmatchcase(tok, glob):
        return True
    return glob.startswith("--") and not any(c in glob for c in "*?[") and tok.startswith(glob + "=")


def expand_default(globs, defaults):
    out = []
    for g in globs:
        out += [g.replace("{default}", d) for d in defaults] if "{default}" in g else [g]
    return out


def positionals(toks, vopts):
    out, k = [], 0
    while k < len(toks):
        t = toks[k]
        if t == "--":
            out += toks[k + 1:]
            break
        if t.startswith("-") and len(t) > 1:
            k += 2 if t in vopts else 1
            continue
        out.append(t)
        k += 1
    return out


def vopts_for(words):
    for n in range(len(words), 0, -1):
        key = " ".join(words[:n])
        if key in M["value_options"]:
            return set(M["value_options"][key])
    return set()


def script_hit(p, script):
    cands = [(p["raw0"], p["all"])]
    if p["argv0"] in INTERP:
        pos = [k for k, t in enumerate(p["all"]) if not t.startswith("-")]
        if pos:
            cands.append((p["all"][pos[0]], p["all"][pos[0] + 1:]))
    hit = [args for tok, args in cands if tok == script or tok.endswith("/" + script)]
    return hit[0] if hit else None


def entry_matches(e, p, defaults):
    if "script" in e:
        toks = script_hit(p, e["script"])
        if toks is None:
            return False
        posn = positionals(toks, set())
    else:
        cmd = e["cmd"]
        if cmd[0] != p["argv0"] or len(p["sub"]) < len(cmd) - 1:
            return False
        if not all(c == "*" or c == t for c, t in zip(cmd[1:], p["sub"])):
            return False
        toks = p["all"]
        posn = positionals(p["sub"][len(cmd) - 1:], vopts_for(cmd))
    if "any" in e and not any(gmatch(g, t) for g in e["any"] for t in toks):
        return False
    if "all" in e and not all(any(gmatch(g, t) for t in toks) for g in e["all"]):
        return False
    if "none" in e and any(gmatch(g, t) for g in e["none"] for t in toks):
        return False
    if "args" in e and not any(fnmatch.fnmatchcase(t, g) for g in expand_default(e["args"], defaults) for t in posn):
        return False
    if "args_none" in e and any(fnmatch.fnmatchcase(t, g) for g in expand_default(e["args_none"], defaults) for t in posn):
        return False
    if "first_arg_none" in e and posn and any(fnmatch.fnmatchcase(posn[0], g) for g in e["first_arg_none"]):
        return False
    if "env_any" in e and not any(fnmatch.fnmatchcase(v, g) for g in e["env_any"] for v in p["env"]):
        return False
    return True


_RX = {}


def path_regex(pattern, defaults):
    key = (pattern, tuple(defaults))
    if key in _RX:
        return _RX[key]
    segs, out, i = pattern.split("/"), [], 0
    while i < len(segs):
        s = segs[i]
        if s == "{owner}" and i + 1 < len(segs) and segs[i + 1] == "{repo}":
            out.append(("/", r"(?:[^/]+/[^/]+|[^/]*\$[^/]*)"))
            i += 2
            continue
        if s == "**":
            out.append(("", r"(?:/.*)?" if out else r".*"))
        elif s == "{default}":
            out.append(("/", "(?:%s)" % "|".join(re.escape(d) for d in defaults)))
        elif s == "*" or re.fullmatch(r"\{[a-z_]+\}", s):
            out.append(("/", r"[^/]+"))
        else:
            out.append(("/", re.escape(s)))
        i += 1
    body = "".join((sep if n else "") + rx for n, (sep, rx) in enumerate(out))
    _RX[key] = re.compile("^" + body + "/?$")
    return _RX[key]


def norm_path(path):
    p = path.strip().strip("\"'")
    p = re.sub(r"^https?://[^/]+", "", p)
    p = re.sub(r"^/api/(v3|uploads)(?=/)", "", p)
    p = re.sub(r"^/api/graphql$", "/graphql", p)
    return p.split("?", 1)[0].lstrip("/")


def rest_ids(method, path, kv, defaults):
    got = set()
    for a in ACTS:
        for e in a["equivalents"].get("rest", []):
            methods = e["method"] if isinstance(e["method"], list) else [e["method"]]
            if method not in methods or not path_regex(e["path"], defaults).match(path):
                continue
            if "fields_all" in e and not all(any(fnmatch.fnmatchcase(x, g) for x in kv) for g in e["fields_all"]):
                continue
            if "fields_none" in e and any(fnmatch.fnmatchcase(x, g) for x in kv for g in e["fields_none"]):
                continue
            got.add(a["id"])
    return got


def mutation_names(doc):
    names = []
    for m in re.finditer(r"\bmutation\b[^{]*\{", doc):
        depth, paren, k = 1, 0, m.end()
        while k < len(doc) and depth:
            ch = doc[k]
            if ch == "(":
                paren += 1
            elif ch == ")":
                paren -= 1
            elif ch == "{" and not paren:
                depth += 1
            elif ch == "}" and not paren:
                depth -= 1
            elif depth == 1 and not paren and (ch.isalpha() or ch == "_"):
                w = re.match(r"[A-Za-z_]\w*", doc[k:]).group(0)
                after = doc[k + len(w):].lstrip()
                if after[:1] in ("(", "{"):
                    names.append(w)
                k += len(w)
                continue
            k += 1
    return names


GRAPHQL = {}
for _a in ACTS:
    for _g in _a["equivalents"].get("graphql", []):
        GRAPHQL.setdefault(_g, set()).add(_a["id"])


def graphql_ids(doc, file_sourced):
    """(ids, unclassified). A document PG cannot read (a file, a variable) is UNCLASSIFIED."""
    if file_sourced or "{" not in doc:
        return set(), True
    names = mutation_names(doc)
    if not names:
        return ({"repo.read"}, False) if "mutation" not in doc else (set(), True)
    got = set()
    for n in names:
        got |= GRAPHQL.get(n, set())
    return got, any(n not in GRAPHQL for n in names)


def gh_api(sub):
    toks, method, fields, path, has_input, k = sub[1:], None, [], None, False, 0
    vopts = set(M["value_options"]["gh api"])
    while k < len(toks):
        t = toks[k]
        if t in ("-X", "--method"):
            method = toks[k + 1].upper() if k + 1 < len(toks) else None
            k += 2
        elif t.startswith("--method=") or (t.startswith("-X") and len(t) > 2):
            method = t.split("=", 1)[1].upper() if "=" in t else t[2:].upper()
            k += 1
        elif t in ("-f", "-F", "--field", "--raw-field"):
            if k + 1 < len(toks):
                fields.append((t, toks[k + 1]))
            k += 2
        elif t == "--input":
            has_input = True
            k += 2
        elif t in vopts:
            k += 2
        elif t.startswith("-"):
            k += 1
        else:
            path = path if path is not None else t
            k += 1
    if method is None:
        method = "POST" if fields or has_input else "GET"
    return method, path, fields, has_input


def http_call(p):
    toks, method, data, upload, url, k = p["all"], None, [], False, None, 0
    vopts = set(M["value_options"].get(p["argv0"], []))
    while k < len(toks):
        t = toks[k]
        nxt = toks[k + 1] if k + 1 < len(toks) else ""
        if t in ("-X", "--request") or (p["argv0"] == "wget" and t == "--method"):
            method, k = nxt.upper(), k + 2
        elif t.startswith("--method=") or t.startswith("--request="):
            method, k = t.split("=", 1)[1].upper(), k + 1
        elif t.startswith("-X") and len(t) > 2:
            method, k = t[2:].upper(), k + 1
        elif t in ("-d", "--data", "--data-raw", "--data-binary", "--data-urlencode", "-F", "--form", "--json",
                   "--post-data", "--body-data"):
            data.append(nxt)
            k += 2
        elif t in ("-T", "--upload-file", "--post-file"):
            upload = upload or t != "--post-file"
            data.append("@" + nxt)
            k += 2
        elif t in vopts:
            k += 2
        elif t.startswith("-"):
            k += 1
        else:
            if url is None and any(h in t for h in API_HOSTS):
                url = t
            k += 1
    if url is None:
        return None
    if method is None:
        method = "PUT" if upload else ("POST" if data else "GET")
    kv = []
    for d in data:
        try:
            body = json.loads(d)
        except ValueError:
            continue
        if isinstance(body, dict):
            kv += ["%s=%s" % (k2, v if isinstance(v, str) else json.dumps(v)) for k2, v in body.items()]
    return method, norm_path(url), kv, data


def has_marker(text):
    # `gh ` counts only as the program (argv0), as in the reference matcher: as a substring it is prose.
    return any(mk in text for mk in MARKERS if mk != "gh") or any(rx.search(text) for rx in MARKER_RX)


# --------------------------------------------------------------- local facts (git, offline, deadline)

_GIT = {}


def git(d, *args):
    key = (d,) + args
    if key in _GIT:
        return _GIT[key]
    res = None
    if d and left() > 1.5:
        env = dict(os.environ)
        env.update({"GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"})
        try:
            r = subprocess.run(["git", "-C", d] + list(args), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               timeout=min(3.0, max(0.5, left() - 1.0)), env=env)
            res = (r.returncode, r.stdout.decode("utf-8", "replace"))
        except (OSError, subprocess.SubprocessError):
            res = None
    _GIT[key] = res
    return res


def git_out(d, *args):
    r = git(d, *args)
    return r[1].strip() if r and r[0] == 0 else None


def git_rc(d, *args):
    r = git(d, *args)
    return r[0] if r else None


# --------------------------------------------------------------- GitHub facts (lib/permission-conditions.sh)

NET = {"t0": None}
NOTES = []         # what a lookup found, for the reason (counts only: names are PR-author text)
_LIB = {}


def net_left():
    used = 0.0 if NET["t0"] is None else time.time() - NET["t0"]
    return min(NET_BUDGET - used, left() - 1.0)


def conditions_lib(cmd, *args):
    """The one line lib/permission-conditions.sh prints, or None: no budget left, no lib, a non-zero
    exit or the deadline. The lib bounds itself (timeout/gtimeout, else a watchdog); this is the backstop,
    and it kills the lib's whole process group so a stray gh cannot keep the pipe open."""
    key = (cmd,) + args
    if key in _LIB:
        return _LIB[key]
    res, budget = None, net_left()
    if budget >= 0.3 and os.path.isfile(COND_LIB):
        if NET["t0"] is None:
            NET["t0"] = time.time()
        argv = ["bash", COND_LIB, cmd, "--deadline", "%.1f" % budget] + list(args)
        try:
            pr = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                                  start_new_session=True)
        except OSError:
            pr = None
        if pr is not None:
            try:
                out, _ = pr.communicate(timeout=budget + 1.0)
                if pr.returncode == 0:
                    res = out.decode("utf-8", "replace").strip().split("\n")[0][:300]
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(pr.pid, signal.SIGKILL)
                except OSError:
                    pass
                try:
                    pr.communicate(timeout=1.0)
                except (OSError, subprocess.SubprocessError):
                    pass
    _LIB[key] = res
    return res


def remote_default_branch(d, remote):
    """GitHub's default branch for the repository <remote>'s push URL names, or None."""
    out = conditions_lib("default-branch", d, remote)
    if out and safe(out) and not out.startswith("refs/"):
        return out
    note = "the default branch of `%s` could not be read from GitHub either" % remote
    if note not in NOTES:
        NOTES.append(note)
    return None


SAFE_REF = re.compile(r"\A[A-Za-z0-9._/@+-]{1,200}\Z")


def safe(ref):
    return bool(ref) and SAFE_REF.match(ref) is not None and ".." not in ref and not ref.startswith("-")


def default_branch(d, remote):
    if not safe(remote) or "/" in remote:
        return None
    out = git_out(d, "symbolic-ref", "--quiet", "refs/remotes/%s/HEAD" % remote)
    pre = "refs/remotes/%s/" % remote
    if out and out.startswith(pre):
        return out[len(pre):]
    # No local answer: ask GitHub, under the call's network deadline (an error leaves it unknown).
    return remote_default_branch(d, remote) if d else None


def defaults_set(d, remote):
    """{D, main, master} when D resolves, else None."""
    dflt = default_branch(d, remote) if d else None
    return sorted({dflt, "main", "master"}) if dflt else None


def origin_slug(d):
    url = git_out(d, "config", "--get", "remote.origin.url") if d else None
    if not url:
        return None
    m = re.match(r"^(?:[a-z+]+://)?(?:[^@/]+@)?([^/:]+)[:/]+([^/]+)/([^/]+?)(?:\.git)?/?$", url.strip())
    return ("%s/%s" % (m.group(2), m.group(3))).lower() if m else None


def head_branch(d):
    return git_out(d, "symbolic-ref", "--quiet", "--short", "HEAD")


def has_ref(d, ref):
    """True / False (git says missing) / None (no repository, an error, the deadline)."""
    rc = git_rc(d, "show-ref", "--verify", "--quiet", ref)
    return {0: True, 1: False}.get(rc)


def clean_tree(d):
    out = git(d, "status", "--porcelain", "--untracked-files=normal")
    if not out or out[0] != 0:
        return None
    return out[1].strip() == ""


def unpushed(d, rev="HEAD", base=None):
    """True when <rev> (minus <base>) holds commits no remote ref contains; None when unknown."""
    args = ["rev-list", "--max-count=1", rev, "--not", "--remotes"]
    if base:
        args = ["rev-list", "--max-count=1", "%s..%s" % (base, rev), "--not", "--remotes"]
    out = git(d, *args)
    if not out or out[0] != 0:
        return None
    return out[1].strip() != ""


# --------------------------------------------------------------- the command's context

def payload_cwd():
    c = PAY.get("cwd")
    if not isinstance(c, str) or not c:
        roots = PAY.get("workspace_roots")
        c = roots[0] if isinstance(roots, list) and roots and isinstance(roots[0], str) else ""
    return os.path.realpath(c) if c and os.path.isabs(c) and os.path.isdir(c) else None


CMD_TEXT = ""
_ti = PAY.get("tool_input")
if isinstance(_ti, dict) and isinstance(_ti.get("command"), str):
    CMD_TEXT = _ti["command"]
elif isinstance(PAY.get("command"), str):
    CMD_TEXT = PAY["command"]

CTX = {"ok": True, "cwd": payload_cwd(), "why": []}
if CTX["cwd"] is None:
    CTX["ok"] = False
    CTX["why"].append("the payload names no usable cwd")
for s in SEGS:
    s["p"] = parse(s["toks"])
_cds = [s for s in SEGS if s["p"]["argv0"] in ("cd", "pushd", "popd")]
for s in SEGS:
    p = s["p"]
    if p["argv0"] in ("export", "declare", "typeset", "readonly", "unset", "source", ".", "set", "eval", "alias"):
        CTX["ok"] = False
        CTX["why"].append("`%s` can change the environment the command runs in" % p["argv0"])
    if p["argv0"] is None and any(TARGET_ENV.match(v) for v in p["env"]):
        CTX["ok"] = False
        CTX["why"].append("a bare assignment changes the git/gh target")
if _cds and CTX["ok"]:
    first = _cds[0]
    lead = re.match(r"^\s*cd\s+(?:\"[^\"]*\"|'[^']*'|[^\s;&|()<>]+)\s*&&", CMD_TEXT)
    target = first["p"]["all"][0] if first["p"]["all"] else ""
    if len(_cds) == 1 and first is SEGS[0] and not first["nested"] and lead and first["p"]["argv0"] == "cd" \
            and len(first["p"]["all"]) == 1 and target and not re.search(r"[$`*?]", target) and target != "-":
        nd = os.path.realpath(os.path.join(CTX["cwd"], os.path.expanduser(target)))
        if os.path.isdir(nd):
            CTX["cwd"] = nd
        else:
            CTX["ok"] = False
            CTX["why"].append("the leading cd names no directory")
    else:
        CTX["ok"] = False
        CTX["why"].append("the command changes directory in a way PG does not follow")


def seg_dir(p):
    """The repository directory a git segment runs in, or None when it cannot be pinned."""
    if not CTX["ok"]:
        return None
    if any(TARGET_ENV.match(v) for v in p["env"]):
        return None
    d = CTX["cwd"]
    for k, v in p["gopts"]:
        if p["argv0"] != "git":
            continue
        if k == "-C":
            if not v or re.search(r"[$`*?]", v):
                return None
            d = os.path.realpath(os.path.join(d, os.path.expanduser(v)))
        elif k in ("-c", "--git-dir", "--work-tree", "--namespace", "--config-env", "--exec-path"):
            return None
    return d if d and os.path.isdir(d) else None


# --------------------------------------------------------------- git push

PUSH_VOPTS = set(M["value_options"]["git push"])
# The idioms that name the current branch: PG reads them as HEAD instead of an unresolvable word.
CURRENT_BRANCH_SUBST = re.compile(r"^(\$\(|`)\s*git\s+(branch\s+--show-current|rev-parse\s+--abbrev-ref\s+HEAD|"
                                  r"symbolic-ref\s+(-q\s+|--quiet\s+)?--short\s+(-q\s+|--quiet\s+)?HEAD)\s*(\)|`)$")
URLISH = re.compile(r"^([a-z+]+://|[^/]*@[^/]*:|/|\.\.?/|~)")


def push_info(p, d):
    toks, pos, flags, k = p["sub"][1:], [], set(), 0
    while k < len(toks):
        t = toks[k]
        if t == "--":
            pos += toks[k + 1:]
            break
        if t.startswith("-") and len(t) > 1:
            flags.add(t.split("=", 1)[0])
            k += 2 if t in PUSH_VOPTS else 1
            continue
        pos.append(t)
        k += 1
    info = {"flags": flags, "delete": bool(flags & {"--delete", "-d"}),
            "broad": bool(flags & {"--all", "--branches", "--mirror", "--tags", "--follow-tags", "--prune"}),
            "remote": pos[0] if pos else None, "specs": pos[1:], "d": d}
    cur = head_branch(d) if d else None
    if info["remote"] is None and d:
        info["remote"] = (git_out(d, "config", "--get", "branch.%s.pushRemote" % cur) if cur else None) or \
            git_out(d, "config", "--get", "remote.pushDefault") or \
            (git_out(d, "config", "--get", "branch.%s.remote" % cur) if cur else None) or "origin"
    rem = info["remote"]
    info["remote_named"] = bool(rem) and not URLISH.match(rem) and safe(rem) and "/" not in rem
    dsts = []  # (src, dst) with dst a short branch/tag name, "refs/tags/x", or None when unresolvable
    if info["delete"]:
        dsts = [("", s) for s in info["specs"]]
    elif not info["specs"]:
        mode = git_out(d, "config", "--get", "push.default") if d else None
        configured = git_out(d, "config", "--get-all", "remote.%s.push" % rem) if d and info["remote_named"] else None
        if configured or mode not in (None, "simple", "current") or not cur:
            dsts = [(None, None)]
        else:
            dsts = [("HEAD", cur)]
    else:
        for spec in info["specs"]:
            s = spec[1:] if spec.startswith("+") else spec
            if ":" in s:
                src, dst = s.split(":", 1)
            else:
                src, dst = s, s
            if dst == "HEAD" or (":" not in s and s == "HEAD") or CURRENT_BRANCH_SUBST.match(dst):
                dst = cur
            if CURRENT_BRANCH_SUBST.match(src):
                src = "HEAD"
            if dst is not None and (not dst or re.search(r"[$`*?]", dst)):
                dst = None
            dsts.append((src, dst))
    info["dsts"] = dsts
    return info


def short(dst):
    if dst is None:
        return None
    if dst.startswith("refs/heads/"):
        return dst[len("refs/heads/"):]
    if dst.startswith("refs/"):
        return None
    return dst


def push_default_branch(info):
    if info["broad"] or not info["remote_named"]:
        return None
    names = defaults_set(info["d"], info["remote"])
    if names is None:
        return None
    vals = [short(dst) for _, dst in info["dsts"] if not (dst or "").startswith("refs/tags/")]
    if any(v in names for v in vals if v):
        return True
    return None if any(v is None for v in vals) else False


def is_tag(d, name):
    if name.startswith("refs/tags/"):
        return True
    if name.startswith("refs/heads/") or name == "HEAD":
        return False
    if name.startswith("refs/"):
        return None
    tag, branch = has_ref(d, "refs/tags/" + name), has_ref(d, "refs/heads/" + name)
    if tag is None or branch is None:
        return None
    if tag and branch:
        return None
    return tag


def push_tag_ref(info):
    d = info["d"]
    if info["flags"] & {"--tags", "--follow-tags"}:
        return True
    if info["broad"] or not d:
        return None
    seen_none = False
    for src, dst in info["dsts"]:
        if dst is None and src is None:
            return None
        if info["delete"] or src == "":
            if dst is None:
                return None
            if dst.startswith("refs/tags/"):
                return True
            if dst.startswith("refs/heads/"):
                continue
            remote_branch = has_ref(d, "refs/remotes/%s/%s" % (info["remote"], dst)) if info["remote_named"] else None
            local_tag = has_ref(d, "refs/tags/" + dst)
            if local_tag:
                return True
            if remote_branch:
                continue
            seen_none = True
            continue
        if (dst or "").startswith("refs/tags/"):
            return True
        if (dst or "").startswith("refs/heads/"):
            continue
        t = is_tag(d, src) if src else None
        if t:
            return True
        if t is None:
            seen_none = True
    return None if seen_none else False


def push_unmerged(info):
    gone = [(src, dst) for src, dst in info["dsts"] if info["delete"] or src == ""]
    if not gone or not info["remote_named"] or not info["d"]:
        return None
    dflt = default_branch(info["d"], info["remote"])
    if not dflt:
        return None
    for _, dst in gone:
        b = short(dst)
        if not b or not safe(b):
            return None
        ref = "refs/remotes/%s/%s" % (info["remote"], b)
        if not has_ref(info["d"], ref):
            return None
        if unpushed_vs(info["d"], ref, "refs/remotes/%s/%s" % (info["remote"], dflt)) is not False:
            return None
    return False


def unpushed_vs(d, ref, base):
    out = git(d, "rev-list", "--max-count=1", ref, "--not", base)
    if not out or out[0] != 0:
        return None
    return out[1].strip() != ""


# --------------------------------------------------------------- conditions per hit

WORKFLOW_PATHS = [".github/workflows/*", ".github/actions/*", "CODEOWNERS", ".github/CODEOWNERS", "docs/CODEOWNERS",
                  ".tamirs-superpowers/*", ".husky/*", ".githooks/*", "hooks/*", "core/permissions/*"]


def protected_paths(paths):
    if not paths or any(not isinstance(x, str) or not x for x in paths):
        return None
    for x in paths:
        x = x.lstrip("/")
        if any(fnmatch.fnmatchcase(x, g) for g in WORKFLOW_PATHS):
            return True
    return False


def remote_branch_default(owner_repo, branch):
    """default_branch for a GitHub API or MCP write naming owner/repo and a branch."""
    d = CTX["cwd"] if CTX["ok"] else None
    if not d or not owner_repo or not branch or "$" in owner_repo or "$" in branch:
        return None
    slug = origin_slug(d)
    if not slug or slug != owner_repo.lower():
        return None
    names = defaults_set(d, "origin")
    return None if names is None else branch in names


MERGE_VOPTS = {"-t", "--subject", "-b", "--body", "-F", "--body-file", "-A", "--author-email", "--match-head-commit"}
REPO_ARG = re.compile(r"\A[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\Z")
PR_URL = re.compile(r"\Ahttps://[A-Za-z0-9.-]+/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+/?\Z")


def required_checks(p):
    """required_check_failing_or_pending for `gh pr merge … --admin` (safety invariant 2), from
    gh pr checks --required on the same PR, in the same directory, against the same -R repo.
    True / False / None (anything PG cannot pin or read)."""
    if not CTX["ok"] or p["argv0"] != "gh" or p["sub"][:2] != ["pr", "merge"]:
        return None
    if any(TARGET_ENV.match(v) for v in p["env"]):
        return None
    repo = None
    for k, v in p["gopts"]:
        if k == "--hostname" or (k in ("-R", "--repo") and (not v or not REPO_ARG.match(v) or repo not in (None, v))):
            return None
        if k in ("-R", "--repo"):
            repo = v
    pos = positionals(p["sub"][2:], MERGE_VOPTS)
    if len(pos) > 1:
        return None
    if pos and not (pos[0].isdigit() or PR_URL.match(pos[0]) or safe(pos[0])):
        return None
    sel = pos[0] if pos else "-"
    out = conditions_lib("required-checks", CTX["cwd"], sel, repo or "-")
    word, _, summary = (out or "unknown the lookup did not answer").partition(" ")
    what = "PR %s%s" % (sel if sel != "-" else "of the current branch", (" in %s" % repo) if repo else "")
    note = "required checks on %s: %s (gh pr checks --required)" % (what, summary or word)
    if note not in NOTES:
        NOTES.append(note)
    return {"true": True, "false": False}.get(word)


def establish(name, hit):
    p, kind = hit.get("p"), hit["kind"]
    if name == "required_check_failing_or_pending":
        return required_checks(p) if kind == "argv" and p else None
    if kind == "mcp":
        args = hit["args"]
        if name == "workflow_hook_or_policy_path":
            if "files" in args:
                f = args.get("files")
                return protected_paths([x.get("path") if isinstance(x, dict) else None for x in f]) \
                    if isinstance(f, list) else None
            return protected_paths([args.get("path")]) if "path" in args else None
        if name == "default_branch":
            if "owner" in args and "repo" in args and "branch" in args:
                return remote_branch_default("%s/%s" % (args["owner"], args["repo"]), args["branch"])
            return None
        if name == "tag_ref" and hit["tool"] == "create_branch":
            return False
        return None
    if kind == "rest":
        method, path, fields = hit["rest"]
        m = re.match(r"^repos/([^/]+/[^/]+)/(.*)$", path)
        if not m:
            return None
        repo, tail = m.group(1), m.group(2)
        kv = dict(f.split("=", 1) for f in fields if "=" in f)
        if name == "workflow_hook_or_policy_path" and tail.startswith("contents/"):
            return protected_paths([tail[len("contents/"):]])
        branch = None
        if tail.startswith("git/refs/heads/"):
            branch = tail[len("git/refs/heads/"):]
        elif kv.get("ref", "").startswith("refs/heads/"):
            branch = kv["ref"][len("refs/heads/"):]
        elif "branch" in kv:
            branch = kv["branch"]
        if name == "default_branch":
            return remote_branch_default(repo, branch)
        if name == "tag_ref":
            if tail.startswith("git/refs/heads/") or kv.get("ref", "").startswith("refs/heads/"):
                return False
            return None
        return None
    if kind != "argv" or p["argv0"] != "git":
        return None
    d = seg_dir(p)
    if d is None:
        return None
    sub = p["sub"]
    verb = sub[0] if sub else ""
    if verb == "push":
        info = hit.setdefault("push", push_info(p, d))
        if name == "default_branch":
            return push_default_branch(info)
        if name == "tag_ref":
            return push_tag_ref(info)
        if name == "unmerged_commits":
            return push_unmerged(info)
        return None
    if name == "uncommitted_changes":
        c = clean_tree(d)
        return None if c is None else not c
    if name == "drops_unpushed_commits":
        if verb in ("clean", "checkout", "restore", "switch"):
            return False
        if verb == "stash":
            out = git(d, "stash", "list")
            return None if not out or out[0] != 0 else out[1].strip() != ""
        if verb == "reset":
            pos = positionals(sub[1:], set())
            target = pos[0] if pos else "HEAD"
            if not safe(target.replace("~", "-").replace("^", "-")):
                return None
            sha = git_out(d, "rev-parse", "--verify", "--quiet", target + "^{commit}")
            return None if not sha else unpushed(d, "HEAD", sha)
        return None
    if name == "discards_work":
        if verb in ("pull", "merge") and "--ff-only" in sub:
            return False
        if verb == "reset":
            c, u = clean_tree(d), unpushed(d)
            if c is None or u is None:
                return None
            return (not c) or u
        if verb == "worktree" and sub[1:2] == ["remove"]:
            pos = positionals(sub[2:], set())
            if len(pos) != 1 or re.search(r"[$`*?]", pos[0]):
                return None
            wt = os.path.realpath(os.path.join(d, os.path.expanduser(pos[0])))
            if not os.path.isdir(wt):
                return None
            c, u = clean_tree(wt), unpushed(wt)
            if c is None or u is None:
                return None
            return (not c) or u
        return None
    if name == "unmerged_no_remote_copy" and verb == "branch":
        names = positionals(sub[1:], set(M["value_options"]["git branch"]))
        if not names:
            return None
        for b in names:
            if not safe(b) or not has_ref(d, "refs/heads/" + b):
                return None
            u = unpushed(d, "refs/heads/" + b)
            if u is None:
                return None
            if u:
                return True
        return False
    return None


def cond_names(aid, depth=0):
    a = BYID.get(aid)
    names = []
    if not a or depth > 4:
        return names
    for r in a.get("raises") or []:
        names.append(r["when"])
        if r.get("becomes"):
            names += cond_names(r["becomes"], depth + 1)
    for dn in a.get("denies") or []:
        names.append(dn["when"])
    if a.get("unattended_precondition"):
        names.append(a["unattended_precondition"])
    out = []
    for n in names:
        if n not in out:
            out.append(n)
    return out


# --------------------------------------------------------------- classify

HITS = []          # {"id", "kind", "p"/"args", "seg", ...}
UNCL_FROM = []     # texts that made the call UNCLASSIFIED
PG_DENY = []       # (id, reason) forms PG denies outright
STAMPS = []        # call-stamp tokens


def seg_text(toks):
    t = " ".join(toks)
    return t if len(t) <= 160 else t[:157] + "..."


def add(aid, kind, seg, **kw):
    h = {"id": aid, "kind": kind, "seg": seg}
    h.update(kw)
    HITS.append(h)


def classify_segment(s):
    """Adds the segment's hits; returns True when it is UNCLASSIFIED (a marker, no id)."""
    p, toks = s["p"], s["toks"]
    text = " ".join(toks)
    got_any, opaque, uncl = False, False, False
    if p["argv0"] is None:
        return has_marker(text)
    if p["argv0"] == "git" and p["sub"][:1] == ["push"]:
        d = seg_dir(p)
        remote = None
        pos = positionals(p["sub"][1:], PUSH_VOPTS)
        if pos:
            remote = pos[0]
        elif d:
            remote = "origin"
        defaults = (defaults_set(d, remote) if (d and remote and not URLISH.match(remote)) else None) or STD_DEFAULTS
    else:
        defaults = STD_DEFAULTS
    for a in ACTS:
        if any(entry_matches(e, p, defaults) for e in a["equivalents"].get("argv", [])):
            add(a["id"], "argv", s, p=p)
            got_any = True
    writer = script_hit(p, "plugin-config.sh")
    if writer is not None:
        pos = positionals(writer, set())
        if pos and pos[0] == "provision":
            PG_DENY.append(("policy.edit", "plugin-config.sh provision writes the permission file and lock for CI "
                            "before the agent starts; it never runs from agent Bash (ADR 004 D6)"))
    if p["argv0"] == "claude" and p["sub"][:2] == ["plugin", "configure"]:
        PG_DENY.append(("policy.edit", "`claude plugin configure` writes the plugin's option store; run it in your "
                        "own terminal, never from agent Bash (ADR 004 D7, D10.3)"))
    if p["argv0"] == "gemini" and p["sub"][:2] == ["extensions", "config"]:
        PG_DENY.append(("policy.edit", "`gemini extensions config` writes the extension's settings; run it in your "
                        "own terminal, never from agent Bash (ADR 004 D7, D10.3)"))
    rp = script_hit(p, "resolve-permission.sh")
    if rp is not None:
        for k, t in enumerate(rp):
            if t == "--call" and k + 1 < len(rp):
                STAMPS.append(rp[k + 1])
            elif t.startswith("--call="):
                STAMPS.append(t[len("--call="):])
    if p["argv0"] == "gh" and p["sub"][:1] == ["api"]:
        method, path, fields, has_input = gh_api(p["sub"])
        if path is None or re.fullmatch(r"\$[@*]|\$\{?[A-Za-z_]\w*\}?", path):
            opaque = True
            if method == "GET" and not fields:
                add("repo.read", "argv", s, p=p)
                got_any = True
        elif norm_path(path) == "graphql":
            doc = " ".join(v.split("=", 1)[1] for _, v in fields if v.startswith("query="))
            file_sourced = has_input or any(f in ("-F", "--field") and v.startswith("query=@") for f, v in fields)
            g, u = graphql_ids(doc, file_sourced)
            for aid in g:
                add(aid, "graphql", s, p=p)
            got_any = got_any or bool(g)
            uncl = uncl or u
        else:
            kv = [v for _, v in fields]
            npath = norm_path(path)
            for aid in rest_ids(method, npath, kv, STD_DEFAULTS):
                add(aid, "rest", s, p=p, rest=(method, npath, kv))
                got_any = True
    if p["argv0"] in HTTP:
        call = http_call(p)
        if call:
            method, path, kv, data = call
            if path == "graphql":
                g, u = graphql_ids(" ".join(data), any(x.startswith("@") for x in data))
                for aid in g:
                    add(aid, "graphql", s, p=p)
                got_any = got_any or bool(g)
                uncl = uncl or u
            else:
                for aid in rest_ids(method, path, kv, STD_DEFAULTS):
                    add(aid, "rest", s, p=p, rest=(method, path, kv))
                    got_any = True
    s["hit"] = got_any
    if not got_any and (p["argv0"] == "gh" or has_marker(" ".join([p["argv0"]] + p["all"]))):
        uncl = True
    return uncl


def classify_mcp():
    tool = PAY.get("tool_name") if isinstance(PAY.get("tool_name"), str) else ""
    if tool.startswith(PFX):
        bare, ours = tool[len(PFX):], True
    elif tool.startswith("MCP:"):
        bare = tool[4:].strip()
        ours = bare in KNOWN_MCP
    else:
        bare, ours = "", False
    if not ours:
        answer("allow", "")
    args = PAY.get("tool_input")
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except ValueError:
            args = None
    if not isinstance(args, dict):
        args = {}

    def render(v):
        return v if isinstance(v, str) else json.dumps(v)

    full, got = PFX + bare, set()
    for a in ACTS:
        for e in a["equivalents"].get("mcp", []):
            if e["tool"] != full:
                continue
            if any(k not in args or not fnmatch.fnmatchcase(render(args[k]), g) for k, g in e.get("args_all", {}).items()):
                continue
            if any(k in args and fnmatch.fnmatchcase(render(args[k]), g) for k, g in e.get("args_none", {}).items()):
                continue
            got.add(a["id"])
    desc = "GitHub MCP %s" % bare
    bits = []
    if args.get("owner") and args.get("repo"):
        bits.append("%s/%s" % (args["owner"], args["repo"]))
    for k in ("pullNumber", "pull_number", "issue_number", "branch", "path", "method", "state", "event"):
        if k in args and isinstance(args[k], (str, int)):
            bits.append("%s=%s" % (k, args[k]))
    if bits:
        desc += " (" + ", ".join(bits) + ")"
    for aid in sorted(got):
        add(aid, "mcp", None, args=args, tool=bare, desc=desc)
    if not got:
        UNCL_FROM.append(desc)
    return desc


MCP_DESC = None
try:
    if MODE in ("mcp", "classify-mcp"):
        MCP_DESC = classify_mcp()
    else:
        for s in SEGS:
            s["uncl"] = classify_segment(s)
        # A command inside a substitution is UNCLASSIFIED only when the segment that holds it is not
        # classified itself: in `curl -H "token $(<gh token lookup>)" …/merge` the curl call is pr.merge, and
        # the token lookup is part of it, as in the reference matcher (which never looks inside $(…)).
        for s in SEGS:
            if not s["uncl"]:
                continue
            if s["nested"]:
                inner = " ".join(s["toks"])
                if any(o.get("hit") and not o["nested"] and inner in " ".join(o["toks"]) for o in SEGS):
                    continue
            UNCL_FROM.append(seg_text(s["toks"]))
except SystemExit:
    raise
except Exception as e:  # noqa: BLE001
    answer("deny", "tamirs-superpowers permission guard: classifying the call failed (%s: %s), so it is denied "
           "(fail closed, ADR 004 D4)." % (e.__class__.__name__, str(e)[:120]))

# --------------------------------------------------------------- resolve

def needs_resolver(aid):
    a = BYID.get(aid)
    if a is None:
        return True
    if (a.get("l2") or []) == ["L1"]:
        return False
    return a["r"] >= 2 or bool(a.get("raises")) or bool(a.get("denies"))


def pr_target(hit):
    """--target for pr.merge.auto (trust widening needs it); None means no widening."""
    if hit["id"] != "pr.merge.auto" or hit["kind"] != "argv" or not CTX["ok"]:
        return None
    p = hit["p"]
    if p["argv0"] != "gh" or p["sub"][:2] != ["pr", "merge"]:
        return None
    pos = positionals(p["sub"][2:], {"-t", "--subject", "-b", "--body", "-F", "--body-file", "-A", "--author-email",
                                     "--match-head-commit"})
    if len(pos) != 1:
        return None
    ref = pos[0]
    repo = None
    for k, v in p["gopts"]:
        if k in ("-R", "--repo"):
            repo = v
        if k == "--hostname":
            return None
    for v in p["env"]:
        if v.startswith("GH_REPO="):
            repo = repo or v.split("=", 1)[1]
        if v.startswith("GH_HOST="):
            return None
    if "$" in ref or (repo and "$" in repo):
        return None
    if re.fullmatch(r"https://[^/]+/[^/]+/[^/]+/pull/\d+/?", ref):
        return ref
    if not ref.isdigit():
        return None
    return "%s#%s" % (repo, ref) if repo else ref


JOBS, JOB_KEYS = [], {}
for h in HITS:
    if not needs_resolver(h["id"]):
        continue
    conds = []
    for n in cond_names(h["id"]):
        v = establish(n, h)
        if v is not None:
            conds.append("%s=%s" % (n, "true" if v else "false"))
    target = pr_target(h)
    key = (h["id"], tuple(sorted(conds)), target)
    if key in JOB_KEYS:
        JOB_KEYS[key]["hits"].append(h)
        continue
    job = {"id": h["id"], "conds": conds, "target": target, "hits": [h]}
    JOB_KEYS[key] = job
    JOBS.append(job)
if UNCL_FROM:
    JOBS.append({"id": UNCL, "conds": [], "target": None, "hits": [], "uncl": UNCL_FROM})

if MODE.startswith("classify"):
    sys.stdout.write(json.dumps({
        "ids": sorted(set(h["id"] for h in HITS)), "unclassified": bool(UNCL_FROM), "unclassified_from": UNCL_FROM,
        "resolver_calls": [{"id": j["id"], "conds": j["conds"], "target": j["target"]} for j in JOBS],
        "pg_deny": [r for _, r in PG_DENY], "stamps": STAMPS, "notes": NOTES, "context_ok": CTX["ok"], "context_why": CTX["why"],
        "fast_path_allows": (sys.argv[5] == "1") if len(sys.argv) > 5 else False}, sort_keys=True) + "\n")
    sys.exit(0)


def resolver_failed(job, why):
    job["res"] = {"verdict": "deny", "effective_action": job["id"], "r": 4,
                  "reason": "denied: resolver error: %s (fail closed, D4, SR S-12)" % why, "setting_that_would_allow": None}


if JOBS and not os.path.isfile(RESOLVER):
    for j in JOBS:
        resolver_failed(j, "scripts/resolve-permission.sh is missing")
else:
    repo = CTX["cwd"] or payload_cwd() or os.getcwd()
    procs = []
    for j in JOBS:
        argv = ["bash", RESOLVER, j["id"], "--host", HOST, "--repo", repo, "--json"]
        for c in j["conds"]:
            argv += ["--cond", c]
        if j["target"]:
            argv += ["--target", j["target"]]
        try:
            pr = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
        except OSError as e:
            resolver_failed(j, "could not start (%s)" % e.__class__.__name__)
            continue
        procs.append((j, pr))
    for j, pr in procs:
        try:
            outb, _ = pr.communicate(timeout=max(0.5, left() - 0.5))
        except subprocess.TimeoutExpired:
            pr.kill()
            pr.communicate()
            resolver_failed(j, "it did not answer before the guard's deadline")
            continue
        if pr.returncode != 0:
            resolver_failed(j, "it exited %d" % pr.returncode)
            try:
                d = json.loads(outb.decode("utf-8", "replace"))
                if isinstance(d, dict) and d.get("reason"):
                    j["res"]["reason"] = "denied: resolver exit %d: %s" % (pr.returncode, d["reason"])
            except ValueError:
                pass
            continue
        try:
            d = json.loads(outb.decode("utf-8", "replace"))
        except ValueError:
            resolver_failed(j, "it printed no JSON")
            continue
        if not isinstance(d, dict) or d.get("verdict") not in RANK:
            resolver_failed(j, "its answer has no verdict")
            continue
        j["res"] = d

for reason_id, why in PG_DENY:
    JOBS.append({"id": reason_id, "conds": [], "target": None, "hits": [],
                 "res": {"verdict": "deny", "effective_action": reason_id, "r": 4, "reason": "denied: " + why,
                         "setting_that_would_allow": None}})

def rnum(j):
    try:
        return int(j["res"].get("r") if j["res"].get("r") is not None else 4)
    except (TypeError, ValueError):
        return 4


final = max(JOBS, key=lambda j: (RANK[j["res"]["verdict"]], rnum(j))) if JOBS else None
verdict = final["res"]["verdict"] if final else "allow"
stamp_err = None

# --------------------------------------------------------------- the call stamp (D8)


def write_stamps():
    good = [t for t in STAMPS if CALL_RE.match(t)]
    if not good:
        return None
    try:
        r = subprocess.run(["bash", "-c", '. "$1/scripts/lib/permission-common.sh" && perm_state_dir', "_", ROOT],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=max(0.5, min(5.0, left())))
        state = r.stdout.decode("utf-8", "replace").strip() if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        state = ""
    if not state or not os.path.isabs(state):
        return "the state dir could not be resolved"
    seen = os.path.join(state, "seen")
    try:
        old = os.umask(0o077)
        try:
            os.makedirs(seen, mode=0o700, exist_ok=True)
        finally:
            os.umask(old)
        for d in (state, seen):
            st = os.lstat(d)
            if st.st_uid != os.getuid() or not os.path.isdir(d) or os.path.islink(d):
                return "%s is not a directory owned by this user" % d
            if st.st_mode & 0o077:
                os.chmod(d, 0o700)
        for t in good:
            try:
                fd = os.open(os.path.join(seen, t), os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
                             0o600)
            except FileExistsError:
                continue
            os.write(fd, ("%d\n" % int(time.time())).encode())
            os.close(fd)
    except OSError as e:
        return "the stamp could not be written (%s)" % e.__class__.__name__
    return None


if verdict != "deny" and STAMPS:
    stamp_err = write_stamps()

if verdict == "allow":
    answer("allow", "")

# --------------------------------------------------------------- the reason


def describe(j):
    res = j["res"]
    eff = res.get("effective_action") or j["id"]
    r = res.get("r")
    if j["id"] == UNCL:
        what = "UNCLASSIFIED (R4): `%s` carries a mutation marker but maps to no action id in core/permissions/" \
               "actions.json" % j["uncl"][0]
    else:
        tgt = None
        for h in j["hits"]:
            tgt = h.get("desc") or (seg_text(h["seg"]["toks"]) if h.get("seg") else None)
            if tgt:
                break
        what = "%s%s (R%s)%s" % (eff, (" (raised from %s)" % j["id"]) if eff != j["id"] else "", r,
                                 (" on `%s`" % tgt) if tgt else "")
    return what


def settings(j):
    s = j["res"].get("setting_that_would_allow") or {}
    parts = []
    if s.get("note"):
        parts.append(s["note"])
    if s.get("once") and HOST in ASK_HOSTS:
        parts.append("once: %s in your prompt" % s["once"])
    dur = [x for x in (s.get("durable") or []) if isinstance(x, str)]
    if dur:
        if HOST in ASK_HOSTS:
            parts.append("durable: " + " or ".join("`%s`" % x for x in dur))
        else:
            parts.append("durable, in your own terminal outside the agent session: " +
                         " or ".join("`bash scripts/plugin-config.sh %s`" % x[len("/plugin-config "):]
                                     if x.startswith("/plugin-config ") else "`%s`" % x for x in dur))
    return "; ".join(parts)


lines = []
head = "tamirs-superpowers permission guard (ADR 004)"
res = final["res"]
why = str(res.get("reason") or "").strip()
if verdict == "ask" and HOST not in ASK_HOSTS:
    verdict = "deny"
    lines.append("%s: denied %s. %s; %s cannot carry a hook ask (it would %s), so the ask is delivered as a deny "
                 "(D8)." % (head, describe(final), why, HOST,
                            {"codex": "run the call unchecked", "cursor": "be dropped",
                             "gemini": "hang a headless run"}.get(HOST, "not reach a human")))
elif verdict == "ask":
    lines.append("%s: asks before %s. %s." % (head, describe(final), why))
else:
    lines.append("%s: denied %s. %s." % (head, describe(final), why))
unknown = [rb.get("when") for rb in (res.get("raised_by") or []) if isinstance(rb, dict) and rb.get("condition") == "unknown"]
if unknown:
    lines.append("Not established, so the raise applied: %s." % ", ".join(sorted(set(x for x in unknown if x))))
    if "default_branch" in unknown:
        lines.append("PG reads the default branch from refs/remotes/<remote>/HEAD (`git remote set-head origin --auto` "
                     "sets it), else from GitHub (gh repo view, under a 3 s deadline), and needs a named remote and a "
                     "resolvable destination.")
if NOTES:
    lines.append(" ".join(n[:1].upper() + n[1:] + "." for n in NOTES))
if not CTX["ok"] and CTX["why"] and MODE == "shell":
    lines.append("Repository conditions were not read: %s." % "; ".join(sorted(set(CTX["why"]))))
st = settings(final)
if st:
    lines.append("To allow it: %s." % st)
others = sorted(set(j["id"] for j in JOBS if j is not final))
if others:
    lines.append("The call also reaches: %s." % ", ".join(others))
if stamp_err:
    lines.append("Call stamp not written: %s." % stamp_err)
answer(verdict, " ".join(lines))
PY

# ------------------------------------------------------------------ inspection CLI

if [ "$#" -gt 0 ]; then
  _PG_DONE=1
  trap - EXIT
  case "$1" in
    --classify|--classify-mcp)
      command -v jq >/dev/null 2>&1 || { echo "permission-guard: jq is required" >&2; exit 2; }
      command -v python3 >/dev/null 2>&1 || { echo "permission-guard: python3 is required" >&2; exit 2; }
      if [ "$1" = --classify ]; then
        [ "$#" -ge 2 ] || { echo "usage: permission-guard.sh --classify '<command>' [cwd]" >&2; exit 2; }
        _pg_cwd="${3:-$PWD}"
        input="$(jq -n --arg c "$2" --arg d "$_pg_cwd" '{session_id:"classify",cwd:$d,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}')"
        _pg_segs="$(LC_ALL=C cmdtok_argv_segments "$2")"
        _pg_fast=0
        _pg_candidate "$2" || _pg_fast=1
        _pg_mode=classify-shell
      else
        [ "$#" -ge 3 ] || { echo "usage: permission-guard.sh --classify-mcp <tool> '<args-json>' [cwd]" >&2; exit 2; }
        _pg_cwd="${4:-$PWD}"
        input="$(jq -n --arg t "${PG_MCP_PREFIX}$2" --argjson a "$3" --arg d "$_pg_cwd" '{session_id:"classify",cwd:$d,hook_event_name:"PreToolUse",tool_name:$t,tool_input:$a}')" || exit 2
        _pg_segs="" _pg_fast=0 _pg_mode=classify-mcp
      fi
      { printf '%s' "$input"; printf '\036\036\036\n'; printf '%s' "$_pg_segs"; } |
        python3 -I -S -c "$_PG_ENGINE" "$PG_ROOT" "${PG_HOST:-claude}" "$_pg_mode" "$PG_BUDGET" "$_pg_fast"
      exit $? ;;
    -h|--help)
      sed -n '2,/^set -uo pipefail/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "permission-guard.sh: unknown argument '$1' (a hook takes none; see --help)" >&2
      exit 2 ;;
  esac
fi

# ------------------------------------------------------------------ main

input="$(hook_read_stdin)"

if ! command -v jq >/dev/null 2>&1; then
  # hook_detect_platform reads the payload with jq; without it, a Cursor payload is
  # still recognisable by its keys, and the deny must be in Cursor's shape.
  case "$input" in
    *'"conversation_id"'*|*'"cursor_version"'*|*'"workspace_roots"'*) HOOK_PLATFORM=cursor ;;
    *) HOOK_PLATFORM=claude ;;
  esac
  if [ -z "${input//[[:space:]]/}" ]; then _pg_finish allow ""; fi
  _PG_DONE=1
  _pg_lit_deny "tamirs-superpowers permission guard cannot run: jq is not installed, so the hook payload cannot be read. Refusing to assume the call is safe (fail closed, ADR 004 D4)."
  exit 0
fi

hook_detect_platform "$input"
[ -n "${input//[[:space:]]/}" ] || _pg_finish allow ""

PG_HOST="${HOOK_PLATFORM:-claude}"
if [ -n "${GEMINI_SESSION_ID:-}" ] || [ -n "${GEMINI_PROJECT_DIR:-}" ]; then PG_HOST=gemini; fi

_pg_tool="" _pg_event="" _pg_cmd="" _pg_nul=""
{
  IFS= read -r -d '' _pg_nul
  IFS= read -r -d '' _pg_tool
  IFS= read -r -d '' _pg_event
  IFS= read -r -d '' _pg_cmd
} < <(printf '%s' "$input" | jq -j '
  def s: if type == "string" then . elif . == null then "" else tostring end;
  (.tool_name | s) as $t | (.hook_event_name | s) as $e
  | ((if (.tool_input | type) == "object" then .tool_input.command else null end) // .command | s) as $c
  | (if ($t + $e + $c | contains("\u0000")) then "nul" else "ok" end) + "\u0000" + $t + "\u0000" + $e + "\u0000" + $c + "\u0000"
' 2>/dev/null)

case "$_pg_nul" in
  ok) : ;;
  nul) _pg_finish deny "tamirs-superpowers permission guard: the call carries a NUL byte, which a shell would read differently from this guard; denied (fail closed, ADR 004 D4)." ;;
  *) _pg_finish deny "tamirs-superpowers permission guard: the hook payload is not valid JSON, so the call cannot be judged (fail closed, ADR 004 D4)." ;;
esac

_pg_mode=""
case "$(normalize_tool_name "$_pg_tool")" in
  Bash|Shell) _pg_mode=shell ;;
  "${PG_MCP_PREFIX}"*|MCP:*) _pg_mode=mcp ;;
esac
[ -z "$_pg_mode" ] && [ "$_pg_event" = beforeShellExecution ] && _pg_mode=shell
[ -n "$_pg_mode" ] || _pg_finish allow ""

_pg_segs=""
if [ "$_pg_mode" = shell ]; then
  [ -n "${_pg_cmd//[[:space:]]/}" ] || _pg_finish allow ""
  # FAST PATH: nothing in the command can reach a guarded id.
  _pg_candidate "$_pg_cmd" || _pg_finish allow ""
  _pg_segs="$(LC_ALL=C cmdtok_argv_segments "$_pg_cmd")"
fi

if ! command -v python3 >/dev/null 2>&1; then
  _pg_finish deny "tamirs-superpowers permission guard cannot run: python3 is not installed, so the call cannot be classified (fail closed, ADR 004 D4)."
fi

_pg_out="$(
  { printf '%s' "$input"; printf '\036\036\036\n'; printf '%s' "$_pg_segs"; } |
    python3 -I -S -c "$_PG_ENGINE" "$PG_ROOT" "$PG_HOST" "$_pg_mode" "$PG_BUDGET" 2>/dev/null
)"
_pg_rc=$?
_pg_verdict="${_pg_out%%$'\n'*}"
_pg_reason="${_pg_out#*$'\n'}"
_pg_reason="${_pg_reason%$'\n'}"
if [ "$_pg_rc" -ne 0 ]; then
  _pg_finish deny "tamirs-superpowers permission guard: its engine exited $_pg_rc without a verdict, so the call is denied (fail closed, ADR 004 D4)."
fi
case "$_pg_verdict" in
  allow|ask|deny) _pg_finish "$_pg_verdict" "$_pg_reason" ;;
  *) _pg_finish deny "tamirs-superpowers permission guard: its engine gave no verdict, so the call is denied (fail closed, ADR 004 D4)." ;;
esac
