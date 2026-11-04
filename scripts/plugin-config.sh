#!/usr/bin/env bash
# plugin-config.sh — the ONE writer of the permission user file, its lock and the
# D5 tickets (ADR 004 D3, D5, D6, D10). The /plugin-config skill, the OpenCode
# /plugin-config command and setup.sh all call it; nothing else writes those files.
#
# Usage:
#   plugin-config.sh show [<skill|group|action-id>] [--host <h>] [--repo <path>] [--json]
#   plugin-config.sh [set] <level>                       the global level
#   plugin-config.sh [set] <skill|group> <level>         a per-skill or per-group level
#   plugin-config.sh [set] <action-id> [<skill>] allow|ask|deny
#   plugin-config.sh reset [<skill|group|action-id>|level|all]   (no argument = all)
#   plugin-config.sh trust [--repo <path>]               trust this repo's project file
#   plugin-config.sh confirm <nonce>                     apply a pending widening or --perms= request
#   plugin-config.sh provision (--level <l> | --file <path>)     CI only, before the agent starts
#   plugin-config.sh help
#   Every subcommand takes --json for a machine-readable result.
#   levels: supervised | standard | unattended
#
# Exit: 0 done (written, nothing to do, or shown); 1 failed; 2 usage error;
#       3 refused (no host-attested channel, provision inside a session, R4 allow);
#       4 recorded pending: run the `confirm <nonce>` it prints.
#
# WHERE IT WRITES (D3, SR S-04)
#   The paths come from scripts/lib/permission-common.sh, the resolver's own
#   library: <home> is the passwd entry's, never HOME or XDG_*. User file
#   <home>/.config/tamirs-superpowers/permissions.json (0600, dir 0700), its lock
#   permissions.lock {sha256, by, at} and permissions.json.bak (the bytes it
#   replaced). State in <home>/.local/state/tamirs-superpowers/ (dirs 0700, files
#   0600): pending/<nonce>.json and tickets/<id>.json, formats below. When
#   TAMIRS_PERMISSION_TEST_ROOT is set but the library refused it, nothing is
#   written: a test that meant a temp root never lands in the real home.
#
# HOW IT WRITES (D6)
#   The new document is validated against core/schemas/permissions.schema.json
#   by the resolver's own validator, serialised deterministically (sorted keys,
#   2-space indent, ASCII, trailing newline), written to a 0600 temp file in the
#   same directory and renamed over the old one; then the lock, hashed with the
#   resolver's sha256 over the exact bytes, the same way. A crash between the two
#   leaves a lock mismatch, which the resolver reads tighten-only (fail safe).
#   After writing it reads the file back through the resolver and reports its state.
#
# ANTI-ESCALATION (D5, D6, D10.3)
#   Before any write it computes the effective decision of every catalog action,
#   for every shipped skill the change can reach, before and after, with the
#   resolver's own functions (the one implementation, D4) on the file's own effect
#   (no option store, no project file), under two contexts: nothing established,
#   and every unattended precondition established with every raise and invariant
#   condition false. Before is what the resolver honours TODAY (a file that does
#   not match its lock counts tighten-only, D10.2), so re-locking a hand edit is a
#   widening. trust and a reset that drops a deny are widenings too.
#     * Widens nothing: written at once, from anywhere (D7: it tightens in session).
#     * Widens something: recorded pending with its rows and a nonce, written only
#       by `confirm <nonce>` under a human proof, or at once when the writer runs
#       outside any agent session (the user's own terminal, make setup).
#   It never writes R4 `allow` and never writes a host option store: a Claude or
#   Gemini level is also capped by the host's own setting, and it prints that
#   host's route (/config or /plugin configure; gemini extensions config).
#
# THE HUMAN PROOF FOR confirm (D5; SR S-01, S-02)
#   A TTY is no proof (the agent drives one with pty.fork()), so this script never
#   reads one. The session it runs in is found from its process ANCESTRY (read
#   with /bin/ps, never through PATH) plus environment markers, which only ever
#   make the answer stricter:
#     none      no agent host above it: the user's own terminal or CI. Proof.
#     claude    the Claude Code CLI. The proof is the host permission dialog that
#               hooks/permission-guard.sh raises with a PreToolUse `ask` on this
#               very Bash call (policy.edit is R4: it asks at every level, and a
#               headless run turns that ask into a deny). D5's Claude row.
#     gemini    Gemini CLI: the static extension ask_user rule on `confirm`.
#     codex, cursor, opencode, claude-desktop, agy, agent, nested
#               no host-attested channel (D5 table): confirm is refused, the
#               raise path is disabled, and the message names the command to run
#               in the user's own terminal. Two agent hosts in the ancestry
#               (`claude -p` under an agent, a host on a pty) are `nested`.
#   Markers (tighten only): CLAUDECODE, GEMINI_CLI, CODEX_SANDBOX,
#   CODEX_SANDBOX_NETWORK_DISABLED, CODEX_THREAD_ID, OPENCODE, CURSOR_AGENT,
#   AI_AGENT, TS_NESTED. Residual (ADR Open risks): a same-UID process that leaves
#   the ancestry and scrubs its environment, or bypasses this writer entirely.
#
# provision (D6, SR S-18)
#   For a CI step that runs BEFORE the agent: writes the whole file and a lock
#   marked by: provision. Refused inside any agent session (and the permission
#   guard denies it from agent Bash).
#
# STATE FORMATS (shared with hooks/permission-intent.sh; read by the guard)
#   pending/<nonce>.json  nonce = 32 hex chars (128 bits from os.urandom)
#     {"version": 1, "kind": "config", "nonce", "created", "expires" (+15 min),
#      "op", "base_sha256" (the user file's sha256, or "absent"), "doc" (the new
#      user file), "rows" [{"action", "r", "from", "to", "skills" ([] = every
#      skill), "context" ("any" | "when its preconditions hold")}], "host",
#      "body_sha256"}
#     {"version": 1, "kind": "perms", "nonce", "created", "expires", "skill",
#      "level", "target" {"arg", "repo"}, "session_id", "agent", "host",
#      "command_name", "body_sha256"}  -- written by the prompt hook (D5)
#     body_sha256 = sha256 of the record serialised as above without that key.
#     confirm consumes a record by atomic rename (single use), reads it once and
#     hashes and parses the same bytes (SR S-17); a stale, altered or expired
#     record is refused.
#   tickets/<id>.json  id = 32 hex chars
#     {"version": 1, "kind": "raise" | "lower", "id", "skill" (null = the whole
#      session), "level", "target" {"arg", "repo"}, "session_id", "agent",
#      "host", "created", "expires", "source"}
#     A raise ticket lives 15 minutes and satisfies R2/R3 only, never R4 (D5,
#     SR S-05). Lowering tickets come from the prompt hook (SR S-09).
#
# Bash 3.2 compatible. Needs python3 (stdlib only, run with -I -S).
set -uo pipefail

case "${BASH_SOURCE[0]}" in
  */*) _pc_here="${BASH_SOURCE[0]%/*}" ;;
  *) _pc_here=. ;;
esac
PC_ROOT="$(CDPATH='' cd -- "$_pc_here/.." 2>/dev/null && pwd -P)" || { echo "plugin-config: cannot resolve the plugin root" >&2; exit 1; }
unset _pc_here

pc_usage() {
  local line n=0
  while IFS= read -r line; do
    n=$((n + 1))
    [ "$n" -le 2 ] && continue
    case "$line" in
      '#'*) line="${line#\#}"; printf '%s\n' "${line# }" ;;
      *) break ;;
    esac
    [ "$n" -ge 22 ] && break
  done < "${BASH_SOURCE[0]}"
}

case "${1:-}" in
  ''|help|-h|--help) pc_usage; exit 0 ;;
esac

command -v python3 >/dev/null 2>&1 || { echo "plugin-config: python3 is required" >&2; exit 1; }
# shellcheck source=scripts/lib/permission-common.sh
. "$PC_ROOT/scripts/lib/permission-common.sh" 2>/dev/null || { echo "plugin-config: scripts/lib/permission-common.sh is missing" >&2; exit 1; }
[ -n "${_PERM_ENGINE:-}" ] || { echo "plugin-config: the permission engine did not load" >&2; exit 1; }

IFS= read -r -d '' _PC_PY <<'PY' || true
import hashlib, json, os, re, stat, sys, time

ROOT = sys.argv[1]
ARGV = sys.argv[2:]
ENGINE = os.fdopen(3).read()
cut = ENGINE.rfind("\nsys.exit(main())")
if cut < 0:
    sys.stderr.write("plugin-config: the permission engine has an unexpected shape\n")
    sys.exit(1)
E = {"__name__": "permission_engine"}
_saved = sys.argv
sys.argv = ["permission-engine", ROOT]
exec(compile(ENGINE[:cut], "permission-common.sh", "exec"), E)
sys.argv = _saved

LEVELS = E["LEVELS"]
RANK = E["RANK"]
VERDICTS = ("allow", "ask", "deny")
CHANNEL = {"none": "you ran it outside any agent session",
           "claude": "the Claude Code permission dialog on this call",
           "gemini": "the Gemini CLI ask_user prompt on this call"}
NO_CHANNEL = ("codex", "cursor", "opencode", "claude-desktop", "agy", "agent", "nested")
SESSIONS = ("none", "claude", "gemini") + NO_CHANNEL
TEST_SESSION_ENV = "TAMIRS_PERMISSION_TEST_SESSION"
NONCE_RE = re.compile(r"\A[0-9a-f]{32}\Z")
TTL = 15 * 60


class Fail(Exception):
    def __init__(self, msg, code=1):
        Exception.__init__(self, msg)
        self.code = code


def now_utc(t=None):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() if t is None else t))


def parse_utc(s):
    try:
        return int(time.mktime(time.strptime(s, "%Y-%m-%dT%H:%M:%SZ")) - time.timezone)
    except (TypeError, ValueError):
        return None


def render(doc):
    return (json.dumps(doc, indent=2, sort_keys=True, ensure_ascii=True) + "\n").encode("ascii")


def body_sha(rec):
    return hashlib.sha256(render(dict((k, v) for k, v in rec.items() if k != "body_sha256"))).hexdigest()


def cmd_line(*words):
    p = os.path.join(ROOT, "scripts", "plugin-config.sh")
    if re.search(r"[^A-Za-z0-9_./-]", p):
        p = "'" + p.replace("'", "'\\''") + "'"
    return " ".join(("bash", p) + words)


# ------------------------------------------------------------------ the tree

def skill_tree():
    base = os.path.join(ROOT, "skills")
    groups = {}
    for g in sorted(os.listdir(base)):
        gd = os.path.join(base, g)
        if g.startswith((".", "_")) or not os.path.isdir(gd):
            continue
        members = [s for s in sorted(os.listdir(gd))
                   if not s.startswith((".", "_")) and os.path.isfile(os.path.join(gd, s, "SKILL.md"))]
        if members:
            groups[g] = members
    skills = {}
    for g, ms in groups.items():
        for s in ms:
            skills[s] = g
    return groups, skills


# ------------------------------------------------------------------ context

class Ctx(object):
    pass


def load():
    c = Ctx()
    c.cat = E["load_catalog"]()
    c.schema = E["load_schema"]()
    c.home, c.home_source = E["passwd_home"]()
    c.cfg, c.state = E["dirs"](c.home)
    c.file = os.path.join(c.cfg, "permissions.json")
    c.lock = os.path.join(c.cfg, "permissions.lock")
    c.groups, c.skills = skill_tree()
    c.user = E["load_user"](c.home, c.schema)
    return c


def writable(c):
    if os.environ.get("TAMIRS_PERMISSION_TEST_ROOT") and c.home_source != "test-root":
        raise Fail("TAMIRS_PERMISSION_TEST_ROOT is set but the permission library refused it, so the path is the "
                   "real home (%s); refusing to write there" % c.cfg)


# ------------------------------------------------------------------ the session (D5)

def ancestry():
    out, pid = [], os.getppid()
    for _ in range(64):
        if pid <= 1:
            break
        got = E["ps_line"](pid)
        if got is None:
            break
        ppid, args = got
        out.append(args)
        pid = ppid
    return out


def host_of(args):
    toks = args.split()
    if not toks:
        return None
    if "/Claude.app/" in args:
        return "claude-desktop"
    if "/Cursor.app/" in args or "Cursor Helper" in args:
        return "cursor"
    if "/Antigravity.app/" in args:
        return "agy"
    progs = [os.path.basename(toks[0]).lstrip("-")]
    if progs[0] in ("node", "nodejs", "bun", "deno") and len(toks) > 1:
        progs.append(toks[1])
    for p in progs:
        b = os.path.basename(p)
        if b in ("claude", "claude-code") or "/@anthropic-ai/claude-code/" in p:
            return "claude"
        if b == "codex" or "/@openai/codex/" in p:
            return "codex"
        if b == "gemini" or "/@google/gemini-cli/" in p:
            return "gemini"
        if b == "opencode" or "/opencode-ai/" in p or "/@opencode/" in p:
            return "opencode"
        if b in ("cursor-agent", "cursor"):
            return "cursor"
        if b == "agy":
            return "agy"
    return None


def env_hints():
    env, out = os.environ, []
    if env.get("CLAUDECODE"):
        out.append("claude")
    if env.get("GEMINI_CLI"):
        out.append("gemini")
    if env.get("CODEX_SANDBOX") or env.get("CODEX_SANDBOX_NETWORK_DISABLED") or env.get("CODEX_THREAD_ID"):
        out.append("codex")
    if env.get("OPENCODE"):
        out.append("opencode")
    if env.get("CURSOR_AGENT"):
        out.append("cursor")
    if env.get("TS_NESTED"):
        out.append("nested")
    a = env.get("AI_AGENT") or ""
    if a:
        out.append("claude" if a.startswith("claude-code") else "agent")
    return out


def strictness(s):
    return 0 if s == "none" else (1 if s in CHANNEL else 2)


def session(c):
    t = os.environ.get(TEST_SESSION_ENV)
    if t and c.home_source == "test-root":
        if t not in SESSIONS:
            raise Fail("%s=%r is not one of %s" % (TEST_SESSION_ENV, t, ", ".join(SESSIONS)), 2)
        return t, "test override (%s, honoured only under the test root)" % TEST_SESSION_ENV
    found = [h for h in (host_of(a) for a in ancestry()) if h]
    gui = [h for h in found if h in ("claude-desktop",)]
    agents = [h for h in found if h not in ("claude-desktop",)]
    if len(agents) >= 2:
        res, why = "nested", "agent hosts in the process ancestry: %s" % " under ".join(agents)
    elif agents and gui and agents[0] == "claude":
        res, why = "claude-desktop", "Claude Code under the Claude desktop app"
    elif agents:
        res, why = agents[0], "process ancestry"
    elif gui:
        res, why = gui[0], "process ancestry"
    else:
        res, why = "none", "no agent host in the process ancestry"
    for h in env_hints():
        sh, sr = strictness(h), strictness(res)
        if sh > sr:
            res, why = h, "environment marker %s" % h
        elif sh == sr == 1 and h != res:
            res, why = "agent", "conflicting host markers (%s, %s)" % (res, h)
    return res, why


# ------------------------------------------------------------------ verdicts and the diff

def ctx_for(c):
    o = E["parse_resolve_args"](["--level"])
    x = E["build_ctx"](o)
    x["stores"], x["envs"] = [], []
    x["project"] = {"source": "project_file", "path": None, "state": "absent", "doc": None}
    x["trust"] = (False, "not consulted")
    x["stamp"], x["auto_merge_inputs"], x["env_auto_merge"] = None, [], None
    x["headless"], x["target"] = False, None
    return x


def cond_views(c):
    pres = set()
    for a in c.cat["by"].values():
        if a.get("unattended_precondition"):
            pres.add(a["unattended_precondition"])
    perm = dict((k, False) for k in c.cat["conds"])
    for p in pres:
        perm[p] = True
    return [("any", {}), ("when its preconditions hold", perm)]


def verdict(x, cat, aid, skill, cache):
    x["skill"] = skill
    if skill not in cache:
        cache[skill] = E["skill_category"](skill)
    x["category"] = cache[skill]
    cands = E["candidates"](cat["by"][aid], x["conds"], cat, [])
    final = None
    for name, doc, force in E["views"](x):
        lv, _ = E["view_level"](x, doc, force)
        got = E["pick"]([(cd, E["eval_candidate"](cd, {"level": lv, "user_doc": doc}, x)) for cd in cands])
        if final is None or RANK[got[1]["v"]] > RANK[final[1]["v"]]:
            final = got
    return final[1]["v"]


def touches_skills(doc):
    return bool(doc and (doc.get("skills") or doc.get("groups") or doc.get("skill_actions")))


def widening_rows(c, new_doc):
    x = ctx_for(c)
    before_user = c.user
    after_user = {"state": "verified", "doc": new_doc, "level": new_doc.get("level")}
    skills = [None]
    if touches_skills(c.user.get("doc")) or touches_skills(new_doc):
        skills += sorted(c.skills)
    cat, cache, rows = c.cat, {}, {}
    for cname, conds in cond_views(c):
        x["conds"] = conds
        for aid in sorted(cat["by"]):
            for sk in skills:
                x["user"] = before_user
                b = verdict(x, cat, aid, sk, cache)
                x["user"] = after_user
                a = verdict(x, cat, aid, sk, cache)
                if RANK[a] < RANK[b]:
                    key = (aid, b, a)
                    r = rows.setdefault(key, {"action": aid, "r": cat["by"][aid]["r"], "from": b, "to": a,
                                              "skills": set(), "all": False, "context": cname})
                    if sk is None:
                        r["all"] = True
                    else:
                        r["skills"].add(sk)
                    if cname == "any":
                        r["context"] = "any"
    out = []
    for key in sorted(rows):
        r = rows[key]
        out.append({"action": r["action"], "r": r["r"], "from": r["from"], "to": r["to"],
                    "skills": [] if r["all"] else sorted(r["skills"]), "context": r["context"]})
    return out


def row_text(r):
    who = "every skill" if not r["skills"] else ", ".join(r["skills"][:6]) + (
        " and %d more" % (len(r["skills"]) - 6) if len(r["skills"]) > 6 else "")
    return "%s (R%d): %s -> %s, for %s%s" % (r["action"], r["r"], r["from"], r["to"], who,
                                           "" if r["context"] == "any" else " (" + r["context"] + ")")


# ------------------------------------------------------------------ files

def ensure_dir(path):
    old = os.umask(0o077)
    try:
        os.makedirs(path, mode=0o700, exist_ok=True)
    finally:
        os.umask(old)
    st = os.lstat(path)
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
        raise Fail("%s is not a directory owned by this user" % path)
    if st.st_mode & 0o077:
        os.chmod(path, 0o700)


def atomic_write(path, data):
    d = os.path.dirname(path)
    tmp = os.path.join(d, ".%s.tmp-%d" % (os.path.basename(path), os.getpid()))
    try:
        os.unlink(tmp)
    except OSError:
        pass
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
    try:
        os.write(fd, data)
        os.fsync(fd)
    finally:
        os.close(fd)
    os.chmod(tmp, 0o600)
    os.rename(tmp, path)


def check_doc(c, doc):
    errs = E["validate"](doc, c.schema["$defs"]["user_file"], c.schema)
    if errs:
        raise Fail("refusing to write a file the schema rejects: %s" % "; ".join(errs[:3]))
    for k in (doc.get("skills") or {}):
        if k not in c.skills:
            raise Fail("skills.%s names no shipped skill" % k)
    for k in (doc.get("skill_actions") or {}):
        if k not in c.skills:
            raise Fail("skill_actions.%s names no shipped skill" % k)
    for g in (doc.get("groups") or {}):
        if g not in c.groups:
            raise Fail("groups.%s names no skill category" % g)


def write_user(c, doc, by):
    writable(c)
    check_doc(c, doc)
    ensure_dir(c.cfg)
    probs = E["dir_problems"](c.cfg)
    if probs:
        raise Fail("refusing to write: %s (the resolver would read the file tighten-only, D3)" % "; ".join(probs))
    data = render(doc)
    if os.path.lexists(c.file):
        st = os.lstat(c.file)
        if stat.S_ISREG(st.st_mode) and st.st_uid == os.getuid():
            with open(c.file, "rb") as f:
                old = f.read(E["MAX_BYTES"] + 1)
            atomic_write(c.file + ".bak", old)
    atomic_write(c.file, data)
    lock = {"at": now_utc(), "by": by, "sha256": E["sha256"](data)}
    if E["validate"](lock, c.schema["$defs"]["lock_file"], c.schema):
        raise Fail("internal error: the lock does not validate")
    atomic_write(c.lock, render(lock))
    E["WARN"][:] = []
    u = E["load_user"](c.home, c.schema)
    c.user = u
    return u


def state_dir(c, sub):
    writable(c)
    ensure_dir(c.state)
    d = os.path.join(c.state, sub)
    ensure_dir(d)
    return d


def prune_pending(c):
    d = os.path.join(c.state, "pending")
    try:
        names = os.listdir(d)
    except OSError:
        return
    cutoff = time.time() - TTL - 3600
    for n in names:
        p = os.path.join(d, n)
        try:
            if os.lstat(p).st_mtime < cutoff:
                os.unlink(p)
        except OSError:
            pass


def new_nonce():
    return os.urandom(16).hex()


# ------------------------------------------------------------------ option-store notes (D3, D6)

def store_notes(c, level):
    notes = []
    for host, route in (("claude", "/config or /plugin configure (permission_level)"),
                        ("gemini", "gemini extensions config tamirs-superpowers TS_PERMISSION_LEVEL")):
        for s in E["option_stores"](c.home, host):
            if s.get("level") and E["is_lower"](s["level"], level):
                notes.append("on %s the host's own setting is %s, and the lower of the two applies (D3): raise it "
                             "with %s" % ("Claude Code" if host == "claude" else "Gemini CLI", s["level"], route))
    return notes


# ------------------------------------------------------------------ results

RESULT = {"ok": True}
LINES = []


def say(s):
    LINES.append(s)


def finish(code):
    if "--json" in ARGV:
        RESULT["messages"] = LINES
        RESULT["exit"] = code
        sys.stdout.write(json.dumps(RESULT, indent=2, sort_keys=True) + "\n")
    else:
        for s in LINES:
            sys.stdout.write(s + "\n")
    return code


# ------------------------------------------------------------------ apply a change

def apply_change(c, new_doc, op, extra_rows=None, by="plugin-config"):
    cur = c.user
    if cur["state"] == "invalid" and op != "reset all":
        raise Fail("%s is invalid (%s): it is read as supervised with every override ignored. Fix or delete it, or "
                   "run `%s`" % (c.file, cur.get("reason"), cmd_line("reset", "all")))
    if cur.get("doc") == new_doc and cur["state"] == "verified":
        RESULT.update({"result": "nothing", "path": c.file})
        say("nothing to do: %s already says that (%s)" % (c.file, op))
        return 0
    rows = widening_rows(c, new_doc) + list(extra_rows or [])
    sess, why = session(c)
    RESULT.update({"session": sess, "session_reason": why, "rows": rows, "op": op})
    if rows and sess != "none":
        return record_pending(c, new_doc, op, rows, sess)
    u = write_user(c, new_doc, by)
    RESULT.update({"result": "written", "path": c.file, "state": u["state"], "lock": u.get("lock")})
    say("written: %s (%s) -> %s (0600, lock %s; the resolver reads it %s)" % (
        op, "widens %d row(s)" % len(rows) if rows else "widens nothing", c.file, u.get("lock"), u["state"]))
    for r in rows:
        say("  widened: " + row_text(r))
    if u["state"] != "verified":
        say("warning: the resolver does not read it as verified: %s" % u.get("reason"))
    if new_doc.get("level"):
        for n in store_notes(c, new_doc["level"]):
            say("note: " + n)
    return 0


def record_pending(c, new_doc, op, rows, sess):
    d = state_dir(c, "pending")
    prune_pending(c)
    nonce = new_nonce()
    t = int(time.time())
    rec = {"version": 1, "kind": "config", "nonce": nonce, "created": now_utc(t), "expires": now_utc(t + TTL),
           "op": op, "base_sha256": c.user.get("sha256") or "absent", "doc": new_doc, "rows": rows, "host": sess}
    rec["body_sha256"] = body_sha(rec)
    atomic_write(os.path.join(d, nonce + ".json"), render(rec))
    RESULT.update({"result": "pending", "nonce": nonce, "expires": rec["expires"]})
    say("pending: `%s` widens what runs without asking, so it is not written yet (ADR 004 D6):" % op)
    for r in rows:
        say("  " + row_text(r))
    if sess in CHANNEL:
        say("To apply it, run (expires %s): %s" % (rec["expires"], cmd_line("confirm", nonce)))
        say("Proof on this host: %s (D5)." % CHANNEL[sess])
    else:
        say("This session (%s) has no host-attested channel, so it cannot be confirmed here (D5). "
            "Run this in your own terminal, outside any agent session (expires %s): %s" % (
                sess, rec["expires"], cmd_line("confirm", nonce)))
    return 4


# ------------------------------------------------------------------ subcommands

def resolve_action(c, tok):
    aid = c.cat["alias"].get(tok, tok)
    return aid if aid in c.cat["by"] else None


def kind_of(c, tok):
    kinds = []
    if tok in LEVELS:
        kinds.append("level")
    if resolve_action(c, tok):
        kinds.append("action")
    if tok in c.skills:
        kinds.append("skill")
    if tok in c.groups:
        kinds.append("group")
    if len(kinds) > 1:
        raise Fail("%r is ambiguous (%s)" % (tok, " and ".join(kinds)), 2)
    return kinds[0] if kinds else None


def base_doc(c):
    d = c.user.get("doc") if c.user["state"] != "invalid" else None
    return json.loads(json.dumps(d)) if d else {"version": 1}


def prune_empty(doc):
    for k in ("skills", "groups", "actions", "skill_actions", "trust"):
        if k in doc and not doc[k]:
            del doc[k]
    for s in list((doc.get("skill_actions") or {}).keys()):
        if not doc["skill_actions"][s]:
            del doc["skill_actions"][s]
    if "skill_actions" in doc and not doc["skill_actions"]:
        del doc["skill_actions"]
    return doc


def cmd_set(c, a):
    if not a:
        raise Fail("set needs a level, <skill|group> <level> or <action-id> [<skill>] allow|ask|deny", 2)
    doc = base_doc(c)
    k0 = kind_of(c, a[0])
    if len(a) == 1:
        if k0 != "level":
            raise Fail("%r is not a level (%s)" % (a[0], " | ".join(LEVELS)), 2)
        doc["level"] = a[0]
        return apply_change(c, doc, "level %s" % a[0])
    if k0 in ("skill", "group"):
        if len(a) != 2 or a[1] not in LEVELS:
            raise Fail("%s %s takes one level (%s)" % (k0, a[0], " | ".join(LEVELS)), 2)
        if k0 == "skill":
            doc.setdefault("skills", {})[a[0]] = a[1]
        else:
            doc.setdefault("groups", {})[a[0]] = {"level": a[1], "skills": list(c.groups[a[0]])}
        return apply_change(c, doc, "%s %s %s" % (k0, a[0], a[1]))
    if k0 == "action":
        aid = resolve_action(c, a[0])
        if aid != a[0]:
            say("note: %s is an alias of %s" % (a[0], aid))
        if len(a) == 2:
            skill, v = None, a[1]
        elif len(a) == 3:
            skill, v = a[1], a[2]
            if skill not in c.skills:
                raise Fail("%r is not a shipped skill" % skill, 2)
        else:
            raise Fail("usage: <action-id> [<skill>] allow|ask|deny", 2)
        if v not in VERDICTS:
            raise Fail("an action takes allow | ask | deny, not %r" % v, 2)
        if v == "allow" and c.cat["by"][aid]["r"] >= 4:
            raise Fail("%s is R4: nothing allows it automatically, so the writer never stores allow for it; only "
                       "the host prompt on that very call passes it (ADR 004 D1, D5, D6)" % aid, 3)
        if skill:
            doc.setdefault("skill_actions", {}).setdefault(skill, {})[aid] = v
        else:
            doc.setdefault("actions", {})[aid] = v
        return apply_change(c, doc, "%s%s %s" % (aid, " for " + skill if skill else "", v))
    raise Fail("%r is neither a level, a skill, a group nor an action id" % a[0], 2)


def cmd_reset(c, a):
    what = a[0] if a else "all"
    if len(a) > 1:
        raise Fail("reset takes at most one target", 2)
    doc = base_doc(c)
    if what == "all":
        new = {"version": 1}
        if doc.get("trust"):
            new["trust"] = doc["trust"]
            say("note: trust entries are kept; remove one with `reset trust`")
        return apply_change(c, new, "reset all")
    if what == "trust":
        doc.pop("trust", None)
        return apply_change(c, prune_empty(doc), "reset trust")
    if what == "level":
        doc.pop("level", None)
        return apply_change(c, doc, "reset level")
    k = kind_of(c, what)
    if k == "skill":
        (doc.get("skills") or {}).pop(what, None)
        (doc.get("skill_actions") or {}).pop(what, None)
    elif k == "group":
        (doc.get("groups") or {}).pop(what, None)
    elif k == "action":
        aid = resolve_action(c, what)
        (doc.get("actions") or {}).pop(aid, None)
        for s in list((doc.get("skill_actions") or {}).keys()):
            doc["skill_actions"][s].pop(aid, None)
    else:
        raise Fail("reset takes a skill, a group, an action id, level, trust or all; not %r" % what, 2)
    return apply_change(c, prune_empty(doc), "reset %s" % what)


def opt(a, name):
    for i, x in enumerate(a):
        if x == name and i + 1 < len(a):
            return a[i + 1]
        if x.startswith(name + "="):
            return x.split("=", 1)[1]
    return None


def strip_opts(a, names):
    out, skip = [], False
    for x in a:
        if skip:
            skip = False
            continue
        if x in names:
            skip = True
            continue
        if any(x.startswith(n + "=") for n in names) or x == "--json":
            continue
        out.append(x)
    return out


def project_allows_auto_merge(doc):
    if (doc.get("actions") or {}).get("pr.merge.auto") == "allow":
        return True
    return any((v or {}).get("pr.merge.auto") == "allow" for v in (doc.get("skill_actions") or {}).values())


def cmd_trust(c, a):
    repo = E["repo_info"](opt(a, "--repo"))
    if repo is None:
        raise Fail("not inside a git repository (pass --repo <path>)")
    pf = E["load_project"](repo, c.schema)
    if pf["state"] != "valid":
        raise Fail("%s is %s%s: nothing to trust" % (pf.get("path"), pf["state"],
                                                      " (%s)" % pf["reason"] if pf.get("reason") else ""))
    if not project_allows_auto_merge(pf["doc"]):
        raise Fail("%s does not allow pr.merge.auto, the one action a trusted project file may widen (D3): "
                   "nothing to trust" % pf["path"])
    if not repo.get("origin"):
        raise Fail("the checkout's origin is unresolved: a trust entry binds the remote it may act on (D3, SR S-15)")
    entry = {"repo": repo["key"], "remote": repo["origin"], "file": ".tamirs-superpowers/permissions.json",
             "sha256": pf["sha256"], "widens": ["pr.merge.auto"], "at": now_utc()}
    doc = base_doc(c)
    doc["trust"] = [e for e in (doc.get("trust") or []) if os.path.realpath(e.get("repo", "")) != repo["key"]] + [entry]
    row = {"action": "pr.merge.auto", "r": 3, "from": "ask", "to": "allow (project file)", "skills": [],
           "context": "when the project file allows it and the target is %s" % repo["origin"]}
    return apply_change(c, doc, "trust %s (%s, sha256 %s)" % (repo["key"], repo["origin"], pf["sha256"][:12]),
                        extra_rows=[row])


def claim(path):
    claimed = "%s.claimed-%d" % (path, os.getpid())
    try:
        os.rename(path, claimed)
    except OSError:
        return None
    return claimed


def cmd_confirm(c, a):
    a = strip_opts(a, ())
    if len(a) != 1 or not NONCE_RE.match(a[0]):
        raise Fail("confirm takes the 32-character nonce a pending request printed", 2)
    nonce = a[0]
    sess, why = session(c)
    RESULT.update({"session": sess, "session_reason": why})
    if sess not in CHANNEL:
        raise Fail("confirm is disabled in this session (%s: %s): it has no host-attested channel, so a widening "
                   "can only be confirmed outside any agent session (ADR 004 D5). Run this in your own terminal: %s"
                   % (sess, why, cmd_line("confirm", nonce)), 3)
    writable(c)
    path = os.path.join(c.state, "pending", nonce + ".json")
    held = claim(path)
    if held is None:
        raise Fail("no pending request %s (it expired, was already used, or never existed)" % nonce)
    try:
        r = E["read_guarded"](held, "private")
        if r["state"] != "ok":
            raise Fail("the pending record is unsafe: %s" % "; ".join(r["problems"] or [r.get("error") or r["state"]]))
        rec, err = E["parse_json"](r["data"], True)
        if err or not isinstance(rec, dict):
            raise Fail("the pending record is unreadable (%s)" % err)
        if rec.get("nonce") != nonce or rec.get("body_sha256") != body_sha(rec):
            raise Fail("the pending record does not match its nonce or its hash: refused (SR S-17)")
        exp = parse_utc(rec.get("expires"))
        if exp is None or exp < time.time():
            raise Fail("the pending request %s expired at %s" % (nonce, rec.get("expires")))
        if rec.get("kind") == "config":
            return confirm_config(c, rec, sess)
        if rec.get("kind") == "perms":
            return confirm_perms(c, rec, sess)
        raise Fail("unknown pending record kind %r" % rec.get("kind"))
    finally:
        try:
            os.unlink(held)
        except OSError:
            pass


def confirm_config(c, rec, sess):
    cur = c.user.get("sha256") or "absent"
    if cur != rec.get("base_sha256"):
        raise Fail("%s changed since this request was made: run the change again" % c.file)
    doc = rec.get("doc")
    if not isinstance(doc, dict):
        raise Fail("the pending record carries no document")
    u = write_user(c, doc, "plugin-config")
    RESULT.update({"result": "written", "path": c.file, "state": u["state"], "lock": u.get("lock"),
                   "rows": rec.get("rows"), "op": rec.get("op")})
    say("confirmed (%s): %s -> %s (lock %s; the resolver reads it %s)" % (CHANNEL[sess], rec.get("op"), c.file,
                                                                        u.get("lock"), u["state"]))
    for r in rec.get("rows") or []:
        say("  widened: " + row_text(r))
    if doc.get("level"):
        for n in store_notes(c, doc["level"]):
            say("note: " + n)
    return 0


def confirm_perms(c, rec, sess):
    if rec.get("level") not in LEVELS or not rec.get("session_id"):
        raise Fail("the pending --perms= request is malformed")
    d = state_dir(c, "tickets")
    t = int(time.time())
    tid = new_nonce()
    ticket = {"version": 1, "kind": "raise", "id": tid, "skill": rec.get("skill"), "level": rec["level"],
              "target": rec.get("target") or {"arg": None, "repo": None}, "session_id": rec["session_id"],
              "agent": rec.get("agent") or "main", "host": rec.get("host"), "created": now_utc(t),
              "expires": now_utc(t + TTL), "source": "plugin-config confirm %s" % rec["nonce"]}
    atomic_write(os.path.join(d, tid + ".json"), render(ticket))
    RESULT.update({"result": "ticket", "ticket": ticket})
    tg = ticket["target"]
    say("confirmed (%s): --perms=%s for %s on %s, until %s (ticket %s; R2/R3 only, never R4)" % (
        CHANNEL[sess], ticket["level"], ticket["skill"] or "this session",
        "/".join(x for x in (tg.get("repo"), tg.get("arg")) if x) or "no resolvable target (it matches nothing)",
        ticket["expires"], tid))
    return 0


def cmd_provision(c, a):
    sess, why = session(c)
    if sess != "none":
        raise Fail("provision is for a CI step that runs before the agent starts; refused inside an agent session "
                   "(%s: %s, ADR 004 D6)" % (sess, why), 3)
    path, level = opt(a, "--file"), opt(a, "--level")
    if path:
        r = E["read_guarded"](path, "any")
        if r["state"] != "ok":
            raise Fail("cannot read %s (%s)" % (path, r.get("error") or r["state"]))
        doc, err = E["parse_json"](r["data"], True)
        if err:
            raise Fail("%s is %s" % (path, err))
    elif level:
        doc = {"version": 1}
    else:
        raise Fail("provision needs --level <level> or --file <path>", 2)
    if level:
        if level not in LEVELS:
            raise Fail("--level must be one of %s" % " | ".join(LEVELS), 2)
        doc["level"] = level
    u = write_user(c, doc, "provision")
    RESULT.update({"result": "written", "path": c.file, "state": u["state"], "lock": u.get("lock"), "by": "provision"})
    say("provisioned: %s (lock by: provision; the resolver reads it %s)" % (c.file, u["state"]))
    return 0


def lock_doc(c):
    r = E["read_guarded"](c.lock, "private")
    if r["state"] != "ok":
        return None
    d, err = E["parse_json"](r["data"], True)
    return d if not err and isinstance(d, dict) else None


def cmd_show(c, a):
    host = opt(a, "--host")
    rest = strip_opts(a, ("--host", "--repo"))
    repo = opt(a, "--repo")
    base = ["--level"] + (["--host", host] if host else []) + (["--repo", repo] if repo else [])
    u, lk = c.user, lock_doc(c)
    RESULT.update({"user_file": {"path": c.file, "state": u["state"], "lock": u.get("lock"),
                                 "lock_by": (lk or {}).get("by"), "lock_at": (lk or {}).get("at"),
                                 "sha256": u.get("sha256"), "reason": u.get("reason")},
                   "home_source": c.home_source})
    say("user file  %s" % c.file)
    say("  state    %s%s" % (u["state"], " (%s)" % u["reason"] if u.get("reason") else ""))
    if u["state"] != "absent":
        say("  lock     %s%s" % (u.get("lock") or "-", " (by %s, %s)" % (lk["by"], lk["at"]) if lk else ""))
        if lk and lk.get("by") == "provision":
            say("           written by CI provision before the agent started (D6)")
        if u.get("sha256"):
            say("  sha256   %s" % u["sha256"])
    doc = u.get("doc") or {}
    say("entries (source: user file%s)" % ("" if u["state"] == "verified" else ", read %s" % u["state"]))
    if doc.get("level"):
        say("  level = %s" % doc["level"])
    for k, v in sorted((doc.get("skills") or {}).items()):
        say("  skills.%s = %s" % (k, v))
    for k, v in sorted((doc.get("groups") or {}).items()):
        say("  groups.%s = %s (snapshot of %d skills)" % (k, v["level"], len(v["skills"])))
    for k, v in sorted((doc.get("actions") or {}).items()):
        say("  actions.%s = %s" % (k, v))
    for s, m in sorted((doc.get("skill_actions") or {}).items()):
        for k, v in sorted(m.items()):
            say("  skill_actions.%s.%s = %s" % (s, k, v))
    for e in doc.get("trust") or []:
        say("  trust %s -> %s (sha256 %s, %s)" % (e["repo"], e["remote"], e["sha256"][:12], e["at"]))
    if not any(doc.get(k) for k in ("level", "skills", "groups", "actions", "skill_actions", "trust")):
        say("  (none: every host runs supervised unless its own setting lowers it)")
    target = rest[0] if rest else None
    k = kind_of(c, target) if target else None
    E["WARN"][:] = []
    if k == "action":
        argv = [resolve_action(c, target)] + (["--host", host] if host else []) + (["--repo", repo] if repo else [])
        if len(rest) > 1:
            argv += ["--skill", rest[1]]
        d = E["resolve"](E["parse_resolve_args"](argv))
        RESULT["action"] = d
        say("action %s (R%s): %s -- %s" % (d["action"], d["r"], d["verdict"], d["reason"]))
        aw = d.get("setting_that_would_allow") or {}
        for x in aw.get("durable") or []:
            say("  durable: %s" % x)
        if aw.get("once"):
            say("  once: %s" % aw["once"])
        if aw.get("note"):
            say("  note: %s" % aw["note"])
    elif k in ("skill", "group", None, "level"):
        sk = target if k == "skill" else None
        rep = E["level_report"](E["parse_resolve_args"](base + (["--skill", sk] if sk else [])))
        RESULT["level"] = rep
        say("effective level%s: %s (from %s)%s" % (" for " + sk if sk else "", rep["level"], rep["level_source"],
                                                   "" if host else "  [no --host: a host option store only lowers]"))
        for s in rep["level_sources"]:
            say("  source %s: %s%s" % (s.get("source"), s.get("state", "-"), " = %s" % s["level"] if s.get("level") else ""))
        if k == "group":
            say("group %s: %s" % (target, ", ".join(c.groups[target])))
    else:
        raise Fail("show takes a skill, a group or an action id; not %r" % target, 2)
    for w in E["WARN"]:
        say("warning: %s" % w)
    d = os.path.join(c.state, "pending")
    pend = []
    try:
        names = sorted(os.listdir(d))
    except OSError:
        names = []
    for n in names:
        if not n.endswith(".json"):
            continue
        try:
            with open(os.path.join(d, n), "rb") as f:
                rec = json.loads(f.read(E["MAX_BYTES"]).decode("ascii"))
            exp = parse_utc(rec.get("expires"))
            if exp and exp > time.time():
                pend.append({"nonce": rec.get("nonce"), "kind": rec.get("kind"), "expires": rec.get("expires"),
                             "what": rec.get("op") or "--perms=%s for %s" % (rec.get("level"), rec.get("skill"))})
        except (OSError, ValueError, AttributeError):
            continue
    RESULT["pending"] = pend
    for p in pend:
        say("pending %s (%s, expires %s): %s" % (p["nonce"], p["kind"], p["expires"], p["what"]))
    return 0


def main():
    a = list(ARGV)
    if not a:
        raise Fail("no subcommand (see --help)", 2)
    c = load()
    sub, rest = a[0], a[1:]
    if sub == "show":
        return cmd_show(c, rest)
    rest = strip_opts(rest, ("--repo", "--file", "--level")) if sub not in ("trust", "provision") else rest
    if sub == "set":
        return cmd_set(c, rest)
    if sub == "reset":
        return cmd_reset(c, rest)
    if sub == "trust":
        return cmd_trust(c, rest)
    if sub == "confirm":
        return cmd_confirm(c, rest)
    if sub == "provision":
        return cmd_provision(c, rest)
    return cmd_set(c, strip_opts(a, ()))


try:
    code = main()
except Fail as e:
    RESULT["ok"] = False
    RESULT.setdefault("result", "refused" if e.code == 3 else "error")
    say("plugin-config: %s" % e)
    code = e.code
except (E["Internal"], E["Usage"]) as e:
    RESULT["ok"] = False
    RESULT["result"] = "error"
    say("plugin-config: %s" % e)
    code = 1
except OSError as e:
    RESULT["ok"] = False
    RESULT["result"] = "error"
    say("plugin-config: %s" % e)
    code = 1
sys.exit(finish(code))
PY

python3 -I -S -c "$_PC_PY" "$PC_ROOT" "$@" 3<<<"$_PERM_ENGINE"
exit $?
