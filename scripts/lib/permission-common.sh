#!/usr/bin/env bash
# shellcheck shell=bash
# permission-common.sh — the permission resolver's library (ADR 004 D3, D4, D10).
#
# Sourced, never executed. scripts/resolve-permission.sh is the CLI; hooks, the
# D6 writer and github-mcp.sh source this file for the same answers. Every
# function is a thin wrapper over ONE embedded python3 engine (stdlib only, run
# with -I -S so a planted json.py in the working directory is never imported),
# so the whole resolution is one process and one reading of each file.
#
# FUNCTIONS (each prints to stdout; JSON unless noted)
#   perm_passwd_home              home dir from the passwd entry (text)
#   perm_dirs                     {home, home_source, config_dir, state_dir}
#   perm_user_config_dir          <home>/.config/tamirs-superpowers (text)
#   perm_state_dir                <home>/.local/state/tamirs-superpowers (text)
#   perm_check_file <path> [private|store|dir]
#                                 {state, real, problems[]}; returns 1 when unsafe
#   perm_option_store_level <host>
#                                 the preset the host's option store holds
#   perm_sha256 <file>            hex sha256 of the bytes (text)
#   perm_load_user_file           state of the user file, its lock and its level
#   perm_load_project_file [repo] state and sha256 of <repo>/.tamirs-superpowers/permissions.json
#   perm_lock_check               match | mismatch | absent | invalid | unsafe (text)
#   perm_trust_check <repo> <target>
#                                 {trusted, reason}: may the project file widen pr.merge.auto
#   perm_map_verdict <action-id> <level> [--cond name=true|false]...
#                                 the catalog's level table alone: allow | ask | deny (text)
#   perm_normalize_remote <url>   host[:port]/owner/name, lower case (text)
#   perm_repo_key <path>          realpath of the main work tree, shared by worktrees (text)
#   perm_resolve <resolve-permission.sh arguments>
#                                 the full D4 resolution; see scripts/resolve-permission.sh
#
# WHERE THE FILES ARE (D3, SR S-04)
#   <home> comes from the passwd entry of the real uid (python pwd.getpwuid; the
#   bash fallback uses getent on Linux and dscl on macOS), NEVER from HOME or
#   XDG_*: a repo's .claude/settings.json env, a Gemini workspace .env or a Cursor
#   sessionStart hook can set those. User file <home>/.config/tamirs-superpowers/
#   permissions.json beside permissions.lock; state <home>/.local/state/
#   tamirs-superpowers/. A D3 file must be owned by the uid with no group or other
#   bits (0600), its dir likewise (0700), every parent owned by the uid or root and
#   not group/world-writable (a root-owned sticky dir such as /tmp is allowed), and
#   its realpath outside every git work tree. A file that fails is read
#   TIGHTEN-ONLY with a warning: its entries count only where they are stricter
#   than the no-file result (D10.2's rule, measured against the no-file defaults).
#   A file that cannot be read or parsed, or fails the schema, means supervised
#   with every override ignored (D3 fail closed).
#
# THE TEST OVERRIDE AND ITS GUARD
#   The permission suites need a fake passwd home. TAMIRS_PERMISSION_TEST_ROOT
#   names one, and it is honoured only when ALL of these hold:
#     1. it is an absolute path to a real directory (not a symlink) owned by the
#        uid with mode 0700, as mktemp -d makes;
#     2. its realpath is under a system temp root (/tmp, /var/tmp, /var/folders,
#        and their /private forms) -- fixed paths, not TMPDIR;
#     3. it is outside every git work tree;
#     4. a process ANCESTOR of the engine is a shell RUNNING one of the suites
#        that need it, by exact basename -- the resolver, guard, setup-level and
#        merge-policy suites under tests/ (TEST_SCRIPTS below) -- as its script:
#        the file is the shell's first operand, or the process itself (read with
#        /bin/ps, never through PATH). A name anywhere else in an ancestor's
#        arguments does not count: `claude -p "run <suite>"` is no test run, and
#        neither is a shell given -c or -s.
#   Rules 1-3 stop a cloned repo that only ships files and env (it can point the
#   variable at itself, but its own tree is a git work tree and not under a temp
#   root). Rule 4 is the one that matters: a hook is a child of the host process,
#   whose ancestry the agent cannot rewrite, so a project env that sets the
#   variable and an agent that writes a forged home under /tmp still get the real
#   passwd home in every hook. An L1 call from agent Bash can satisfy rule 4 by
#   running a script so named, but L1 is advisory by design (D8) -- the agent can
#   skip the call outright. A refused override is ignored with a warning; the
#   passwd entry decides. No other input (catalog, schema, plugin root) can be
#   redirected: the root is this file's own location.
#
# FAILURE IS A DENY (D4, SR S-12)
#   perm_resolve exits 0 with a decided verdict, 2 on a usage error and 3 on an
#   internal error (missing or corrupt catalog or schema, no python3, a crash).
#   On 2 and 3 it still prints a JSON object whose verdict is deny.
#
# Bash 3.2 compatible; needs python3 (stdlib only). No jq, no gh, no git: the
# origin is read from the repository's config file by the engine.

# This file's directory, then the plugin root. CDPATH is cleared so a relative
# path cannot be redirected by the environment.
case "${BASH_SOURCE[0]}" in
  */*) _perm_lib_dir="${BASH_SOURCE[0]%/*}" ;;
  *) _perm_lib_dir=. ;;
esac
PERM_ROOT="$(CDPATH='' cd -- "$_perm_lib_dir/../.." 2>/dev/null && pwd -P)" || PERM_ROOT=""
unset _perm_lib_dir

IFS= read -r -d '' _PERM_ENGINE <<'PY' || true
import hashlib, json, os, pwd, re, stat, subprocess, sys

ROOT = sys.argv[1]
ARGS = sys.argv[2:]
LEVELS = ("supervised", "standard", "unattended")
RANK = {"allow": 0, "ask": 1, "deny": 2}
HOSTS = ("claude", "codex", "cursor", "gemini", "opencode")
PROMPT_HOSTS = ("claude", "gemini")
PLUGIN = "tamirs-superpowers"
MAX_BYTES = 262144
TEST_ENV = "TAMIRS_PERMISSION_TEST_ROOT"
# Spelled in parts so that no ancestor's argument list (an engine passed with -c) ever holds a whole name.
TEST_SCRIPTS = tuple("test-" + n for n in ("resolve-permission.sh", "permission-guard.sh",
                                             "setup-permission-level.sh", "merge-policy.sh"))
SHELLS = ("bash", "sh", "zsh", "dash", "ksh")
TEMP_ROOTS = ("/tmp", "/private/tmp", "/var/tmp", "/private/var/tmp", "/var/folders", "/private/var/folders")
ENV_LEVELS = ("TS_PERMISSION_LEVEL", "CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL")
ID_RE = re.compile(r"\A[A-Za-z0-9._-]{1,128}\Z")
SKILL_RE = re.compile(r"\A[a-z0-9]+(-[a-z0-9]+)*\Z")
CALL_RE = re.compile(r"\A[A-Za-z0-9_-]{8,128}\Z")
OBJ_RE = re.compile(r"\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\Z")
SLUG = r"[A-Za-z0-9._-]+"
UNCLASSIFIED = "UNCLASSIFIED"


class Usage(Exception):
    pass


class Internal(Exception):
    pass


WARN = []
TRACE = []


def warn(msg):
    if msg not in WARN:
        WARN.append(msg)


def trace(msg):
    TRACE.append(msg)


def lowest(*lv):
    return min(lv, key=LEVELS.index)


def is_lower(a, b):
    return LEVELS.index(a) < LEVELS.index(b)


def stricter(a, b):
    return a if RANK[a] >= RANK[b] else b


# ------------------------------------------------------------------ files

def in_work_tree(path):
    d = path if os.path.isdir(path) else os.path.dirname(path)
    while True:
        if os.path.lexists(os.path.join(d, ".git")):
            return d
        up = os.path.dirname(d)
        if up == d:
            return None
        d = up


def parent_problem(real):
    uid = os.getuid()
    d = os.path.dirname(real)
    while True:
        try:
            st = os.stat(d)
        except OSError:
            return "cannot stat %s" % d
        if st.st_uid not in (uid, 0):
            return "%s is owned by uid %d" % (d, st.st_uid)
        if st.st_mode & 0o022 and not (st.st_mode & stat.S_ISVTX and st.st_uid == 0):
            return "%s is group- or world-writable" % d
        up = os.path.dirname(d)
        if up == d:
            return None
        d = up


def dir_problems(path):
    real = os.path.realpath(path)
    try:
        st = os.stat(real)
    except OSError:
        return ["cannot stat %s" % path]
    out = []
    if not stat.S_ISDIR(st.st_mode):
        out.append("%s is not a directory" % path)
    if st.st_uid != os.getuid():
        out.append("%s is owned by uid %d, not %d" % (path, st.st_uid, os.getuid()))
    if st.st_mode & 0o077:
        out.append("%s has mode %04o, needs 0700" % (path, stat.S_IMODE(st.st_mode)))
    p = parent_problem(real)
    if p:
        out.append(p)
    wt = in_work_tree(real)
    if wt:
        out.append("%s is inside the git work tree %s" % (path, wt))
    return out


def read_guarded(path, kind):
    """Read a file once, checking the bytes it returns. kind: private (a D3 file:
    owner uid, no group/other bits, safe parents, outside git work trees), store
    (a host option store: owner uid, not group/world-writable, safe parents) or
    any (content only, e.g. a committable project file)."""
    r = {"path": path, "real": None, "data": None, "problems": [], "state": None}
    if not os.path.lexists(path):
        r["state"] = "absent"
        return r
    real = os.path.realpath(path)
    r["real"] = real
    try:
        fd = os.open(real, os.O_RDONLY | os.O_NONBLOCK | getattr(os, "O_NOFOLLOW", 0))
    except OSError as e:
        r["state"] = "unreadable"
        r["error"] = e.strerror or str(e)
        return r
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            r["state"] = "unreadable"
            r["error"] = "not a regular file"
            return r
        if kind != "any":
            if st.st_uid != os.getuid():
                r["problems"].append("%s is owned by uid %d, not %d" % (path, st.st_uid, os.getuid()))
            mask = 0o077 if kind == "private" else 0o022
            if st.st_mode & mask:
                r["problems"].append("%s has mode %04o, %s" % (
                    path, stat.S_IMODE(st.st_mode),
                    "needs 0600" if kind == "private" else "is group- or world-writable"))
        chunks = []
        size = 0
        while True:
            b = os.read(fd, 65536)
            if not b:
                break
            chunks.append(b)
            size += len(b)
            if size > MAX_BYTES:
                r["state"] = "unreadable"
                r["error"] = "larger than %d bytes" % MAX_BYTES
                return r
        r["data"] = b"".join(chunks)
    finally:
        os.close(fd)
    if kind != "any":
        p = parent_problem(real)
        if p:
            r["problems"].append(p)
    if kind == "private":
        wt = in_work_tree(real)
        if wt:
            r["problems"].append("%s is inside the git work tree %s" % (path, wt))
    r["state"] = "unsafe" if r["problems"] else "ok"
    return r


def _no_dups(pairs):
    d = {}
    for k, v in pairs:
        if k in d:
            raise ValueError("duplicate key %r" % k)
        d[k] = v
    return d


def _no_const(c):
    raise ValueError("non-finite number %s" % c)


def parse_json(data, ascii_only):
    try:
        text = data.decode("ascii" if ascii_only else "utf-8")
    except UnicodeDecodeError:
        return None, "not ASCII" if ascii_only else "not UTF-8"
    try:
        return json.loads(text, object_pairs_hook=_no_dups, parse_constant=_no_const), None
    except ValueError as e:
        return None, "not valid JSON (%s)" % e


def sha256(data):
    return hashlib.sha256(data).hexdigest()


# ------------------------------------------------------------------ schema
# A JSON Schema 2020-12 subset: exactly the keywords permissions.schema.json uses.
# An unknown keyword is an internal error, so the schema cannot outgrow this.
SCHEMA_KEYS = {"$schema", "$id", "title", "description", "$comment", "$ref", "$defs", "type",
               "required", "additionalProperties", "properties", "propertyNames", "enum",
               "const", "pattern", "items", "minItems", "uniqueItems", "default", "examples"}
TYPES = {"object": dict, "array": list, "string": str, "boolean": bool}


def _same(a, b):
    return a == b and type(a) is type(b)


def validate(inst, sch, root, path="$"):
    errs = []
    for k in sch:
        if k not in SCHEMA_KEYS:
            raise Internal("permissions schema uses unsupported keyword %s" % k)
    if "$ref" in sch:
        ref = sch["$ref"]
        if not ref.startswith("#/"):
            raise Internal("permissions schema has a non-local $ref %s" % ref)
        node = root
        for part in ref[2:].split("/"):
            node = node[part]
        errs += validate(inst, node, root, path)
    t = sch.get("type")
    if t is not None:
        if t == "integer":
            ok = isinstance(inst, int) and not isinstance(inst, bool)
        else:
            ok = isinstance(inst, TYPES[t]) and not (t != "boolean" and isinstance(inst, bool))
        if not ok:
            return errs + ["%s is not %s" % (path, t)]
    if "enum" in sch and not any(_same(inst, e) for e in sch["enum"]):
        errs.append("%s is not one of %s" % (path, sch["enum"]))
    if "const" in sch and not _same(inst, sch["const"]):
        errs.append("%s must be %r" % (path, sch["const"]))
    if "pattern" in sch and isinstance(inst, str):
        pat = sch["pattern"]
        if pat.endswith("$") and not pat.endswith("\\$"):
            pat = pat[:-1] + r"\Z"
        if not re.search(pat, inst):
            errs.append("%s does not match %s" % (path, sch["pattern"]))
    if isinstance(inst, dict):
        props = sch.get("properties", {})
        for req in sch.get("required", []):
            if req not in inst:
                errs.append("%s lacks %s" % (path, req))
        ap = sch.get("additionalProperties", True)
        for k, v in inst.items():
            if "propertyNames" in sch:
                errs += validate(k, sch["propertyNames"], root, "%s key %r" % (path, k))
            if k in props:
                errs += validate(v, props[k], root, "%s.%s" % (path, k))
            elif ap is False:
                errs.append("%s has unknown key %r" % (path, k))
            elif isinstance(ap, dict):
                errs += validate(v, ap, root, "%s.%s" % (path, k))
    if isinstance(inst, list):
        if "items" in sch:
            for i, v in enumerate(inst):
                errs += validate(v, sch["items"], root, "%s[%d]" % (path, i))
        if len(inst) < sch.get("minItems", 0):
            errs.append("%s has fewer than %d items" % (path, sch["minItems"]))
        if sch.get("uniqueItems"):
            seen = []
            for v in inst:
                if any(_same(v, s) for s in seen):
                    errs.append("%s has duplicate items" % path)
                    break
                seen.append(v)
    return errs


# ------------------------------------------------------------------ plugin data

def read_plugin_json(rel, what):
    p = os.path.join(ROOT, rel)
    try:
        with open(p, "rb") as f:
            data = f.read(4 * MAX_BYTES + 1)
    except OSError as e:
        raise Internal("%s unreadable: %s (%s)" % (what, p, e.strerror))
    doc, err = parse_json(data, False)
    if err:
        raise Internal("%s %s is %s" % (what, p, err))
    return doc


def load_catalog():
    doc = read_plugin_json(os.path.join("core", "permissions", "actions.json"), "action catalog")
    try:
        by, alias = {}, {}
        conds = set(k for k in doc["conditions"] if not k.startswith("_"))
        for a in doc["actions"]:
            i = a["id"]
            if i in by or not isinstance(a["r"], int) or not 0 <= a["r"] <= 4:
                raise ValueError("bad or duplicate id %r" % i)
            by[i] = a
            for al in a.get("aliases") or []:
                alias[al] = i
        for a in by.values():
            for rz in a.get("raises") or []:
                if rz["when"] not in conds or ("becomes" in rz and rz["becomes"] not in by):
                    raise ValueError("raise of %s names an unknown condition or id" % a["id"])
            for dn in a.get("denies") or []:
                if dn["when"] not in conds:
                    raise ValueError("deny of %s names an unknown condition" % a["id"])
            pre = a.get("unattended_precondition")
            if pre is not None and pre not in conds:
                raise ValueError("precondition of %s is unknown" % a["id"])
        ceil = doc["levels"]["ceilings"]
        for lv in LEVELS:
            for r in range(5):
                if ceil[lv]["R%d" % r] not in ("allow", "ask", "allow_if_precondition"):
                    raise ValueError("ceiling %s R%d" % (lv, r))
        over = {}
        for i, cells in (doc["levels"].get("overrides") or {}).items():
            if i not in by:
                raise ValueError("override for unknown id %s" % i)
            over[i] = dict((lv, cells[lv]) for lv in LEVELS)
    except (KeyError, TypeError, ValueError, AttributeError) as e:
        raise Internal("action catalog is malformed (%s)" % e)
    return {"by": by, "alias": alias, "ceil": ceil, "over": over, "conds": conds,
            "over_raw": doc["levels"].get("overrides") or {}}


def load_schema():
    doc = read_plugin_json(os.path.join("core", "schemas", "permissions.schema.json"), "permissions schema")
    for d in ("user_file", "project_file", "lock_file"):
        if d not in doc.get("$defs", {}):
            raise Internal("permissions schema lacks $defs/%s" % d)
    return doc


def skill_category(skill):
    if not skill:
        return None
    base = os.path.join(ROOT, "skills")
    try:
        cats = sorted(os.listdir(base))
    except OSError:
        return None
    for c in cats:
        if os.path.isfile(os.path.join(base, c, skill, "SKILL.md")):
            return c
    return None


# ------------------------------------------------------------------ home (D3, SR S-04)

def ps_line(pid):
    ps = "/bin/ps" if os.path.exists("/bin/ps") else "/usr/bin/ps"
    try:
        out = subprocess.run([ps, "-ww", "-o", "ppid=", "-o", "args=", "-p", str(pid)],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             timeout=3, env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"})
    except (OSError, subprocess.SubprocessError):
        return None
    line = out.stdout.decode("utf-8", "replace").strip()
    if not line:
        return None
    parts = line.split(None, 1)
    try:
        return int(parts[0]), (parts[1] if len(parts) > 1 else "")
    except ValueError:
        return None


def runs_test_script(args):
    """True when a process's argument list is one of TEST_SCRIPTS being run: the program itself, or a shell
    whose first operand it is. A shell given -c or -s runs no script file. The value of a long option that
    takes one is read as the operand, which can only refuse, never accept."""
    toks = args.split()
    if not toks:
        return False
    prog = os.path.basename(toks[0]).lstrip("-")
    if prog in TEST_SCRIPTS:
        return True
    if prog not in SHELLS:
        return False
    k = 1
    while k < len(toks):
        t = toks[k]
        if t == "--":
            k += 1
            break
        if t in ("-o", "+o", "-O", "+O"):
            k += 2
            continue
        if t[:1] in ("-", "+") and len(t) > 1:
            if not t.startswith("--") and ("c" in t[1:] or "s" in t[1:]):
                return False
            k += 1
            continue
        break
    return k < len(toks) and os.path.basename(toks[k]) in TEST_SCRIPTS


def under_test_harness():
    pid = os.getppid()
    for _ in range(32):
        if pid <= 1:
            return False
        got = ps_line(pid)
        if got is None:
            return False
        ppid, args = got
        if runs_test_script(args):
            return True
        pid = ppid
    return False


def test_root_refusal(t):
    if not os.path.isabs(t):
        return "not an absolute path"
    try:
        st = os.lstat(t)
    except OSError:
        return "does not exist"
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode):
        return "not a directory (or a symlink)"
    if st.st_uid != os.getuid():
        return "not owned by uid %d" % os.getuid()
    if st.st_mode & 0o077:
        return "mode %04o, not 0700" % stat.S_IMODE(st.st_mode)
    real = os.path.realpath(t)
    roots = set(os.path.realpath(r) for r in TEMP_ROOTS if os.path.isdir(r))
    if not any(real.startswith(r.rstrip("/") + "/") for r in roots):
        return "not under a system temp directory"
    if in_work_tree(real):
        return "inside a git work tree"
    if not under_test_harness():
        return "the process is not running under one of the permission suites (%s)" % ", ".join(TEST_SCRIPTS)
    return None


def passwd_home():
    t = os.environ.get(TEST_ENV)
    if t:
        why = test_root_refusal(t)
        if why is None:
            return os.path.realpath(t), "test-root"
        warn("%s ignored (%s): the passwd entry decides" % (TEST_ENV, why))
    try:
        return pwd.getpwuid(os.getuid()).pw_dir, "passwd"
    except KeyError:
        raise Internal("no passwd entry for uid %d" % os.getuid())


def dirs(home):
    return (os.path.join(home, ".config", PLUGIN), os.path.join(home, ".local", "state", PLUGIN))


# ------------------------------------------------------------------ level sources

def store_bad(s, why):
    s["state"] = "invalid"
    s["level"] = "supervised"
    s["reason"] = why
    warn("option store %s is unusable (%s): it counts as supervised" % (s["path"], why))
    return s


def store_level_value(s, where, v, vals):
    if v in LEVELS:
        vals.append(v)
    else:
        warn("%s %s=%r is not a level: supervised (D7)" % (s["path"], where, v))
        vals.append("supervised")


def store_claude(home):
    p = os.path.join(home, ".claude", "settings.json")
    s = {"source": "option_store:claude", "path": p, "level": None}
    r = read_guarded(p, "store")
    if r["state"] == "absent":
        s["state"] = "absent"
        return s
    if r["state"] != "ok":
        return store_bad(s, r.get("error") or "; ".join(r["problems"]))
    doc, err = parse_json(r["data"], False)
    if err:
        return store_bad(s, err)
    vals = []
    pc = doc.get("pluginConfigs") if isinstance(doc, dict) else None
    if isinstance(pc, dict):
        for k in sorted(pc):
            if k != PLUGIN and not k.startswith(PLUGIN + "@"):
                continue
            ent = pc[k]
            opts = ent.get("options") if isinstance(ent, dict) else None
            if isinstance(opts, dict) and "permission_level" in opts:
                store_level_value(s, "pluginConfigs[%s].options.permission_level" % k, opts["permission_level"], vals)
    if not vals:
        s["state"] = "absent"
        return s
    s["state"] = "present"
    s["level"] = lowest(*vals)
    return s


def store_gemini(home):
    p = os.path.join(home, ".gemini", "extensions", PLUGIN, ".env")
    s = {"source": "option_store:gemini", "path": p, "level": None}
    r = read_guarded(p, "store")
    if r["state"] == "absent":
        s["state"] = "absent"
        return s
    if r["state"] != "ok":
        return store_bad(s, r.get("error") or "; ".join(r["problems"]))
    try:
        text = r["data"].decode("utf-8")
    except UnicodeDecodeError:
        return store_bad(s, "not UTF-8")
    val = None
    for line in text.splitlines():
        t = line.strip()
        if not t or t.startswith("#"):
            continue
        if t.startswith("export "):
            t = t[7:].lstrip()
        k, sep, v = t.partition("=")
        if not sep or k.strip() != "TS_PERMISSION_LEVEL":
            continue
        v = v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        val = v
    if val is None:
        s["state"] = "absent"
        return s
    vals = []
    store_level_value(s, "TS_PERMISSION_LEVEL", val, vals)
    s["state"] = "present"
    s["level"] = vals[0]
    return s


def option_stores(home, host):
    """The host's store raises and lowers. With no --host every store may only
    lower: an unknown host is read as one with no store (D3: absent is skipped)."""
    if host == "claude":
        return [store_claude(home)]
    if host == "gemini":
        return [store_gemini(home)]
    if host is None:
        return [store_claude(home), store_gemini(home)]
    return []


def env_levels():
    out = []
    for n in ENV_LEVELS:
        v = os.environ.get(n)
        if not v:
            continue
        if v not in LEVELS:
            warn("%s=%r is not a level: read as supervised (env only tightens, D3)" % (n, v))
            v = "supervised"
        out.append({"source": "env:" + n, "state": "tighten-only", "level": v})
    return out


def lock_state(cfg, digest, schema):
    r = read_guarded(os.path.join(cfg, "permissions.lock"), "private")
    if r["state"] == "absent":
        return "absent"
    if r["state"] != "ok":
        return "unsafe"
    doc, err = parse_json(r["data"], True)
    if err or validate(doc, schema["$defs"]["lock_file"], schema):
        return "invalid"
    return "match" if doc["sha256"] == digest else "mismatch"


def load_user(home, schema):
    cfg = dirs(home)[0]
    p = os.path.join(cfg, "permissions.json")
    u = {"source": "user_file", "path": p, "level": None, "doc": None, "lock": None, "sha256": None}
    r = read_guarded(p, "private")
    if r["state"] == "absent":
        u["state"] = "absent"
        return u

    def invalid(why):
        u["state"] = "invalid"
        u["reason"] = why
        warn("user file %s is invalid (%s): supervised, its overrides ignored (D3 fail closed)" % (p, why))
        return u

    if r["state"] == "unreadable":
        return invalid(r["error"])
    problems = list(r["problems"]) + dir_problems(cfg)
    doc, err = parse_json(r["data"], True)
    if err:
        return invalid(err)
    errs = validate(doc, schema["$defs"]["user_file"], schema)
    if errs:
        return invalid("; ".join(errs[:3]))
    u["doc"] = doc
    u["level"] = doc.get("level")
    u["sha256"] = sha256(r["data"])
    u["lock"] = lock_state(cfg, u["sha256"], schema)
    if problems:
        u["state"] = "tighten-only"
        u["reason"] = "; ".join(problems)
        warn("user file %s fails the owner/mode checks (%s): only its tightening entries count (D3, SR S-04)"
             % (p, u["reason"]))
    elif u["lock"] != "match":
        u["state"] = "tighten-only"
        u["reason"] = "permissions.lock is %s" % u["lock"]
        warn("user file %s does not match its lock (%s): only its tightening entries count until "
             "/plugin-config re-locks it (D10.2)" % (p, u["lock"]))
    else:
        u["state"] = "verified"
    return u


# ------------------------------------------------------------------ repository

def read_origin(cfg):
    try:
        with open(cfg, "rb") as f:
            text = f.read(MAX_BYTES).decode("utf-8", "replace")
    except OSError:
        return None
    section, url = None, None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line[0] in "#;":
            continue
        m = re.match(r'\A\[\s*([A-Za-z0-9.-]+)(?:\s+"((?:[^"\\]|\\.)*)")?\s*\]\s*(.*)\Z', line)
        if m:
            name = m.group(1).lower()
            if name == "include" or name.startswith("includeif"):
                warn("%s uses an include: its origin is unresolved" % cfg)
                return None
            if name == "remote.origin":
                section = ("remote", "origin")
            else:
                section = (name, m.group(2))
            line = m.group(3)
            if not line:
                continue
        if section == ("remote", "origin") and url is None:
            k, sep, v = line.partition("=")
            if sep and k.strip().lower() == "url":
                v = re.sub(r"\s[#;].*\Z", "", v).strip()
                if len(v) >= 2 and v[0] == v[-1] == '"':
                    v = v[1:-1]
                url = v
    return url


def normalize_remote(u):
    if not u:
        return None
    u = u.strip()
    m = re.match(r"\A([A-Za-z][A-Za-z0-9+.-]*)://(?:[^@/]*@)?([A-Za-z0-9.-]+)(:[0-9]+)?/+(%s)/(%s?)(?:\.git)?/*\Z"
                 % (SLUG, SLUG), u)
    if m:
        scheme, host, port, owner, name = m.groups()
        if (port == ":22" and "ssh" in scheme) or (port == ":443" and scheme == "https"):
            port = None
    else:
        m = re.match(r"\A(?:[^@/:]+@)?([A-Za-z0-9.-]+):/*(%s)/(%s?)(?:\.git)?/*\Z" % (SLUG, SLUG), u)
        if not m:
            return None
        host, owner, name = m.groups()
        port = None
    if name.endswith(".git"):
        name = name[:-4]
    return ("%s%s/%s/%s" % (host, port or "", owner, name)).lower()


def normalize_slug(s):
    s = re.sub(r"#[0-9]+\Z", "", s.strip())
    parts = s.split("/")
    if not all(re.match(r"\A%s\Z" % SLUG, x) for x in parts):
        return None
    if len(parts) == 3 and re.match(r"\A[A-Za-z0-9.-]+(:[0-9]+)?\Z", parts[0]) and "." in parts[0]:
        return "/".join(parts).lower()
    if len(parts) == 2:
        return ("%s/%s/%s" % (os.environ.get("GH_HOST") or "github.com", parts[0], parts[1])).lower()
    return None


def target_repo(t, origin):
    """The repository a target names, as host/owner/name; None when unresolvable.
    A bare PR number names the repository gh would use: GH_REPO, else origin."""
    if not t:
        return None
    t = t.strip()
    if re.match(r"\A#?[0-9]+\Z", t):
        gr = os.environ.get("GH_REPO")
        return normalize_slug(gr) if gr else origin
    if "://" in t:
        t2 = re.sub(r"/(?:pull|pulls|issues)/[0-9]+/*\Z", "", t)
        return normalize_remote(t2)
    return normalize_slug(t)


def repo_info(path):
    try:
        start = os.path.realpath(path or os.getcwd())
    except OSError:
        return None
    d = start if os.path.isdir(start) else os.path.dirname(start)
    while True:
        g = os.path.join(d, ".git")
        if os.path.lexists(g):
            break
        up = os.path.dirname(d)
        if up == d:
            return None
        d = up
    common = None
    if os.path.isdir(g):
        common = g
    else:
        try:
            with open(g) as f:
                txt = f.read(4096)
        except OSError:
            txt = ""
        m = re.match(r"\Agitdir:\s*(.+)", txt.strip())
        if m:
            gd = m.group(1).strip()
            if not os.path.isabs(gd):
                gd = os.path.join(d, gd)
            gd = os.path.realpath(gd)
            try:
                with open(os.path.join(gd, "commondir")) as f:
                    common = os.path.realpath(os.path.join(gd, f.read(4096).strip()))
            except OSError:
                common = gd
    if common is None:
        key = os.path.realpath(d)
    elif os.path.basename(common) == ".git":
        key = os.path.realpath(os.path.dirname(common))
    else:
        key = os.path.realpath(common)
    origin = normalize_remote(read_origin(os.path.join(common, "config"))) if common else None
    return {"top": d, "key": key, "origin": origin}


def load_project(repo, schema):
    if repo is None:
        return {"source": "project_file", "path": None, "state": "absent", "doc": None}
    p = os.path.join(repo["top"], ".tamirs-superpowers", "permissions.json")
    pf = {"source": "project_file", "path": p, "doc": None, "sha256": None}
    r = read_guarded(p, "any")
    if r["state"] == "absent":
        pf["state"] = "absent"
        return pf

    def invalid(why):
        pf["state"] = "invalid"
        pf["reason"] = why
        warn("project file %s is invalid (%s): supervised, its overrides ignored (D3 fail closed)" % (p, why))
        return pf

    if r["state"] == "unreadable":
        return invalid(r["error"])
    doc, err = parse_json(r["data"], True)
    if err:
        return invalid(err)
    errs = validate(doc, schema["$defs"]["project_file"], schema)
    if errs:
        return invalid("; ".join(errs[:3]))
    pf["doc"] = doc
    pf["sha256"] = sha256(r["data"])
    pf["state"] = "valid"
    return pf


def trust_state(user, pf, repo, target):
    """D3 and SR S-15: a project file widens pr.merge.auto only with a trust entry
    in a VERIFIED user file whose repo is this checkout's main work tree, whose
    sha256 is the file's, and whose remote equals both the origin and the target."""
    if pf is None or pf.get("state") != "valid":
        return False, "no valid project file"
    if user["state"] != "verified":
        return False, "the user file is %s, so its trust entries do not count" % user["state"]
    entries = user["doc"].get("trust") or []
    if not entries:
        return False, "the user file has no trust entry"
    origin = repo.get("origin") if repo else None
    if not origin:
        return False, "the checkout's origin is unresolved"
    tr = target_repo(target, origin)
    if tr is None:
        return False, "the target repository is unresolved (pass --target <n>, <owner>/<repo>#<n> or a PR URL)"
    why = "no trust entry for %s" % repo["key"]
    for e in entries:
        if os.path.realpath(e["repo"]) != repo["key"]:
            continue
        if e["sha256"] != pf["sha256"]:
            why = "the project file changed since it was trusted (sha256 differs)"
            continue
        rem = e["remote"].lower()
        if rem != origin:
            why = "the trust entry's remote %s is not the checkout's origin %s" % (rem, origin)
            continue
        if tr != rem:
            why = "the target %s is not the trusted remote %s" % (tr, rem)
            continue
        if "pr.merge.auto" in e["widens"]:
            return True, "trusted for %s at %s" % (rem, e["at"])
    return False, why


def call_stamp(home, token):
    state = dirs(home)[1]
    seen = os.path.join(state, "seen")
    stamp = os.path.join(seen, token)
    if not os.path.lexists(stamp):
        return "missing"
    probs = dir_problems(state) + dir_problems(seen)
    st = os.lstat(stamp)
    if probs or not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid():
        return "unsafe"
    claimed = "%s.consumed-%d" % (stamp, os.getpid())
    try:
        os.rename(stamp, claimed)
    except OSError:
        return "missing"
    try:
        os.unlink(claimed)
    except OSError:
        pass
    return "consumed"


def read_plain_json(p):
    r = read_guarded(p, "any")
    if r["state"] == "absent":
        return "absent", None
    if r["state"] != "ok":
        return "invalid", None
    doc, err = parse_json(r["data"], False)
    if err or not isinstance(doc, dict):
        return "invalid", None
    return "ok", doc


def auto_merge_flag(doc):
    d = doc.get("delivery") if isinstance(doc, dict) else None
    return d.get("auto_merge") if isinstance(d, dict) else None


# ------------------------------------------------------------------ the D4 chain

def candidate(a, r, raised, via):
    return {"id": a["id"], "r": r, "raised": raised, "via": via,
            "never_auto": bool(a.get("never_auto")), "pre": a.get("unattended_precondition"),
            "denies": a.get("denies") or [], "unclassified": False}


def candidates(act, conds, cat, raised_by):
    """The action and every id a context raise reaches. A raise applies when its
    condition holds OR is unknown (catalog conditions; D4: unknown never holds).
    The call is judged by the strictest of them (task-001's matcher rule)."""
    out, seen = [], set()

    def visit(a, via, depth):
        seen.add(a["id"])
        r, raised, becomes = a["r"], False, []
        for rz in a.get("raises") or []:
            st = conds.get(rz["when"])
            if st is False:
                trace("raise %s -> %s skipped: %s established false" % (
                    a["id"], rz.get("becomes") or "R%s" % rz.get("r"), rz["when"]))
                continue
            how = "holds" if st else "unknown"
            if "becomes" in rz:
                becomes.append((rz["becomes"], rz["when"], how))
            elif rz.get("r", 0) > r:
                r, raised = rz["r"], True
                raised_by.append({"from": a["id"], "when": rz["when"], "condition": how, "to": "R%d" % r})
                trace("raise %s to R%d: %s %s" % (a["id"], r, rz["when"], how))
        out.append(candidate(a, r, raised, via))
        for b, when, how in becomes:
            raised_by.append({"from": a["id"], "when": when, "condition": how, "to": b})
            trace("raise %s -> %s: %s %s" % (a["id"], b, when, how))
            if b not in seen and depth < 4:
                visit(cat["by"][b], via + [a["id"]], depth + 1)

    visit(act, [], 0)
    return out


def ceiling(c, level, cat, conds):
    if c["unclassified"]:
        cell = cat["ceil"][level]["R4"]
    elif not c["raised"] and c["id"] in cat["over"]:
        cell = cat["over"][c["id"]][level]
    else:
        cell = cat["ceil"][level]["R%d" % c["r"]]
    if cell == "allow_if_precondition":
        if c["never_auto"]:
            return "ask", "never_auto", "%s at %s: never automatic (D1 'none')" % (c["id"], level)
        if c["pre"] and conds.get(c["pre"]) is True:
            return "allow", "precondition", "%s at %s: precondition %s holds" % (c["id"], level, c["pre"])
        return "ask", "precondition", "%s at %s: precondition %s %s" % (
            c["id"], level, c["pre"] or "(none)", "not established" if c["pre"] else "absent")
    return cell, "ceiling", "level %s ceiling for R%d" % (level, c["r"])


def user_key(doc, cid, skill):
    """Row 5's action keys. A deny anywhere is final; otherwise the most specific
    key present (skill_actions > actions) decides."""
    sa = ((doc.get("skill_actions") or {}).get(skill) or {}) if skill else {}
    ac = doc.get("actions") or {}
    keys = []
    if cid in sa:
        keys.append((sa[cid], "user.skill_actions[%s][%s]" % (skill, cid)))
    if cid in ac:
        keys.append((ac[cid], "user.actions[%s]" % cid))
    for v, src in keys:
        if v == "deny":
            return [(v, src)]
    return keys


def group_level(doc, skill, category, base, who):
    """skills[s] > groups. A group's level applies to a skill in its snapshot and in
    its category (raise or lower); a category member missing from the snapshot,
    or a snapshot member outside the category, gets only a lowering (D3 groups)."""
    sk = doc.get("skills") or {}
    if skill in sk:
        return sk[skill], "%s.skills[%s]" % (who, skill)
    full, lower_only = [], []
    for g, ent in sorted((doc.get("groups") or {}).items()):
        snap = skill in (ent.get("skills") or [])
        incat = category is not None and g == category
        if snap and incat:
            full.append((ent["level"], "%s.groups[%s]" % (who, g)))
        elif snap or incat:
            lower_only.append((ent["level"], "%s.groups[%s] (lowering only)" % (who, g)))
    if full:
        lv = lowest(*[x for x, _ in full])
        res = (lv, next(s for x, s in full if x == lv))
    else:
        res = (None, None)
    for lv, src in lower_only:
        cur = res[0] if res[0] is not None else base
        if cur is None or is_lower(lv, cur):
            res = (lv, src)
    return res


def view_level(ctx, user_doc, force_supervised):
    if force_supervised:
        return "supervised", "user_file invalid (D3 fail closed)"
    present = []
    if ctx["host"] is not None:
        present += [(s["source"], s["level"]) for s in ctx["stores"] if s["level"]]
    if user_doc is not None and user_doc.get("level"):
        present.append(("user_file.level", user_doc["level"]))
    if present:
        lv = lowest(*[x for _, x in present])
        src = next(n for n, x in present if x == lv)
    else:
        lv, src = "supervised", "default"
    if ctx["host"] is None:
        for s in ctx["stores"]:
            if s["level"] and is_lower(s["level"], lv):
                lv, src = s["level"], s["source"] + " (no --host: lowering only)"
    for e in ctx["envs"]:
        if is_lower(e["level"], lv):
            lv, src = e["level"], e["source"]
    if user_doc is not None and ctx["skill"]:
        glv, gsrc = group_level(user_doc, ctx["skill"], ctx["category"], lv, "user")
        if gsrc:
            lv, src = glv, gsrc
    return lv, src


def project_opinion(ctx, c):
    pf = ctx["project"]
    if pf["state"] == "invalid":
        return ("level", "supervised"), "project file invalid (D3 fail closed)"
    if pf["state"] != "valid":
        return None, None
    doc, skill, cid = pf["doc"], ctx["skill"], c["id"]
    keys = user_key(doc, cid, skill)
    for v, src in keys:
        src = src.replace("user.", "project.", 1)
        if v == "allow":
            if cid == "pr.merge.auto" and ctx["trust"][0]:
                return "allow", src + " (trusted: %s)" % ctx["trust"][1]
            warn("the project file's %s allow is ignored: %s (D3, SR S-15)" % (cid, ctx["trust"][1]))
            continue
        return v, src
    if skill:
        glv, gsrc = group_level(doc, skill, ctx["category"], None, "project")
        if gsrc:
            return ("level", glv), gsrc
    if doc.get("level"):
        return ("level", doc["level"]), "project.level"
    return None, None


def widened_at(c, level, st, cat):
    """D2's pr.merge.auto row: at standard it is ask UNLESS the user file or a
    trusted project file allows it. So a tightening to standard leaves such an
    allow standing; a tightening to supervised does not."""
    return (st["v"] == "allow" and st["cause"] in ("user", "project") and level == "standard"
            and not c["raised"] and "widen" in (cat["over_raw"].get(c["id"]) or {}))


def eval_candidate(c, view, ctx):
    cat, conds = ctx["cat"], ctx["conds"]
    st = {"v": None, "by": None, "cause": None}

    def setv(v, by, cause):
        st["v"], st["by"], st["cause"] = v, by, cause
        trace("  %s: %s <- %s" % (c["id"], v, by))

    def tighten(v, by, cause):
        if RANK[v] > RANK[st["v"]]:
            setv(v, by, cause)

    v, cause, by = ceiling(c, view["level"], cat, conds)
    setv(v, by, cause)
    # row 5: the user file (skill_actions > actions; skills and groups set the level)
    if view["user_doc"] is not None and not c["unclassified"]:
        for key, src in user_key(view["user_doc"], c["id"], ctx["skill"]):
            if key == "allow" and c["raised"]:
                trace("  %s: %s allow ignored: context raised it to R%d" % (c["id"], src, c["r"]))
                continue
            setv(key, src, "user-deny" if key == "deny" else "user")
            break
    # row 4: the project file; tighten always, widen pr.merge.auto only when trusted
    if not c["unclassified"]:
        op, src = project_opinion(ctx, c)
        if op == "allow":
            if st["v"] != "deny":
                setv("allow", src, "project")
        elif op in ("ask", "deny"):
            tighten(op, src, "project-deny" if op == "deny" else "project")
        elif op is not None:
            pv, _, _ = ceiling(c, op[1], cat, conds)
            if widened_at(c, op[1], st, cat):
                trace("  %s: %s=%s keeps the configured allow (D2 %s row)" % (c["id"], src, op[1], c["id"]))
            else:
                tighten(pv, "%s=%s ceiling for R%d" % (src, op[1], c["r"]), "project")
    # rows 4 (legacy), 3 and 2: pr.merge.auto only, tighten-only
    if c["id"] == "pr.merge.auto":
        for kind, path, flag in ctx["auto_merge_inputs"]:
            if flag is False:
                tighten("deny", "%s %s delivery.auto_merge false" % (kind, path), "legacy-deny")
        if ctx["env_auto_merge"] == "never":
            tighten("deny", "env TAMIRS_AUTO_MERGE=never (D4 row 2)", "env-deny")
    # the call stamp (D8): no stamp from PG means this call is answered as supervised
    if ctx["stamp"] in ("missing", "unsafe"):
        pv, _, _ = ceiling(c, "supervised", cat, conds)
        tighten(pv, "call stamp %s: answered as supervised (D8)" % ctx["stamp"], "call-stamp")
    # row 0: safety invariants, R4 never automatic, never_auto
    for d in c["denies"]:
        s = conds.get(d["when"])
        if s is not False:
            tighten("deny", "safety invariant %s: %s %s" % (
                d.get("source", "?"), d["when"], "holds" if s else "not established false"), "invariant")
    if st["v"] == "allow" and c["r"] >= 4:
        setv("ask", "R4 is never automatic (D1, D4)", "r4")
    if st["v"] == "allow" and c["never_auto"]:
        setv("ask", "%s is never automatic (D1 'none'; D2 R3 row)" % c["id"], "never_auto")
    return st


def pick(results):
    best = None
    for c, st in results:
        if best is None or RANK[st["v"]] > RANK[best[1]["v"]] or (
                RANK[st["v"]] == RANK[best[1]["v"]] and c["r"] > best[0]["r"]):
            best = (c, st)
    return best


def allow_with(c, st, ctx, verdict, level):
    if verdict == "allow":
        return None
    out = {"once": None, "durable": [], "note": None}
    host = ctx["host"]
    if st["cause"] in ("user-deny", "project-deny", "legacy-deny", "env-deny"):
        out["note"] = "a deny is final (D4): remove it at its source, %s" % st["by"]
        if c["id"] == "pr.merge.auto" and st["cause"] == "legacy-deny":
            out["note"] += "; the durable route is /plugin-config pr.merge.auto allow"
        return out
    if st["cause"] == "invariant":
        out["note"] = "a safety invariant denies it at every level; no setting lifts it (D4 row 0)"
        return out
    if c["r"] >= 4:
        out["note"] = ("R4: no setting allows it automatically; only the host prompt on that very call passes it "
                       "(D2, D5)" + ("; with no human present, run it yourself outside the agent session"
                                     if ctx["headless"] else ""))
        return out
    if c["never_auto"]:
        out["note"] = "%s is never automatic at any level (D1 'none'): approve it per call" % c["id"]
        return out
    if c["raised"]:
        out["note"] = ("context raised it to R%d (%s): establish the condition false with --cond, or approve it "
                       "per call" % (c["r"], ", ".join(x["when"] for x in ctx["raised_by"] if x["from"] == c["id"])))
        return out
    if st["cause"] == "call-stamp":
        out["note"] = "the permission guard did not stamp this call (--call): it is answered as supervised (D8)"
        return out
    if st["cause"] == "precondition" and level == "unattended":
        out["durable"] = ["/plugin-config %s allow" % c["id"]] if c["r"] < 4 else []
        out["note"] = ("unattended allows it only while %s holds, and that is not established: the guard checks it "
                       "(--cond %s=true); otherwise approve it per call" % (c["pre"], c["pre"]))
        return out
    need ="standard" if c["r"] == 2 else ("unattended" if c["r"] == 3 and c["pre"] else None)
    if c["id"] == "pr.merge.auto":
        out["durable"] = ["/plugin-config pr.merge.auto allow",
                          "/plugin-config trust (a project file that allows pr.merge.auto, D3)"]
    elif need:
        out["durable"] = ["/plugin-config %s" % need]
        if ctx["skill"]:
            out["durable"].append("/plugin-config %s %s" % (ctx["skill"], need))
        out["durable"].append("/plugin-config %s allow" % c["id"])
    if need and (host in PROMPT_HOSTS or host is None):
        out["once"] = "--perms=%s%s" % (need, "" if host else " (Claude Code and Gemini CLI only: D5)")
    elif need:
        out["once"] = None
        out["note"] = ("%s has no host-attested channel: change the level outside the session "
                       "(scripts/plugin-config.sh in your own terminal, make setup, or CI provision; D5, D7)" % host)
    if c["r"] == 3 and c["pre"] and c["id"] != "pr.merge.auto":
        out["note"] = ((out["note"] + "; ") if out["note"] else "") + \
            "unattended allows it only while %s holds" % c["pre"]
    if st["cause"] in ("user", "project"):
        out["note"] = ((out["note"] + "; ") if out["note"] else "") + "set to ask by %s" % st["by"]
    return out


def build_ctx(o):
    cat = load_catalog()
    schema = load_schema()
    for n in o["conds"]:
        if n not in cat["conds"]:
            raise Usage("unknown condition %r (see core/permissions/actions.json conditions)" % n)
    home, home_src = passwd_home()
    ctx = {"cat": cat, "schema": schema, "home": home, "home_source": home_src, "host": o["host"],
           "skill": o["skill"], "category": skill_category(o["skill"]), "conds": o["conds"],
           "headless": o["headless"], "target": o["target"], "raised_by": []}
    ctx["stores"] = option_stores(home, o["host"])
    ctx["envs"] = env_levels()
    ctx["user"] = load_user(home, schema)
    ctx["repo"] = repo_info(o["repo"])
    ctx["project"] = load_project(ctx["repo"], schema)
    ctx["trust"] = trust_state(ctx["user"], ctx["project"], ctx["repo"], o["target"])
    ctx["stamp"] = call_stamp(home, o["call"]) if o["call"] else None
    if ctx["stamp"] in ("missing", "unsafe"):
        warn("call stamp %s is %s: the call is answered as supervised (D8)" % (o["call"], ctx["stamp"]))
    am = []
    if ctx["repo"]:
        p = os.path.join(ctx["repo"]["top"], ".dev-files", "policy.json")
        state, doc = read_plain_json(p)
        if state == "ok":
            am.append(("legacy", p, auto_merge_flag(doc)))
    if o["objective"]:
        paths = []
        if os.environ.get("OBJECTIVES_ROOT"):
            paths.append(os.path.join(os.environ["OBJECTIVES_ROOT"], o["objective"], "objective.json"))
        base = ctx["repo"]["top"] if ctx["repo"] else os.getcwd()
        paths.append(os.path.join(base, ".dev-files", "objectives", o["objective"], "objective.json"))
        found = False
        for p in sorted(set(paths), key=paths.index):
            state, doc = read_plain_json(p)
            if state == "ok":
                found = True
                am.append(("objective", p, auto_merge_flag(doc)))
            elif state == "invalid":
                warn("objective file %s is unreadable or invalid: ignored" % p)
        if not found:
            warn("objective %s has no readable objective.json: row 3 contributes nothing" % o["objective"])
    ctx["auto_merge_inputs"] = am
    ctx["env_auto_merge"] = os.environ.get("TAMIRS_AUTO_MERGE") or None
    return ctx


def level_sources(ctx):
    out = []
    for s in ctx["stores"]:
        out.append(dict((k, s.get(k)) for k in ("source", "path", "state", "level", "reason") if s.get(k) is not None))
    if ctx["host"] in ("codex", "cursor", "opencode"):
        out.append({"source": "option_store:%s" % ctx["host"], "state": "none on this host (D3)"})
    u = ctx["user"]
    out.append(dict((k, u.get(k)) for k in ("source", "path", "state", "level", "lock", "reason")
                    if u.get(k) is not None))
    out += ctx["envs"]
    pf = ctx["project"]
    if pf.get("path"):
        e = {"source": "project_file", "path": pf["path"], "state": pf["state"]}
        if pf.get("doc") and pf["doc"].get("level"):
            e["level"] = pf["doc"]["level"]
        if pf["state"] == "valid":
            e["trusted"] = ctx["trust"][0]
            e["trust"] = ctx["trust"][1]
        out.append(e)
    if ctx["stamp"]:
        out.append({"source": "call_stamp", "state": ctx["stamp"]})
    return out


def views(ctx):
    u = ctx["user"]
    if u["state"] == "verified":
        return [("user_file", u["doc"], False)]
    if u["state"] == "tighten-only":
        return [("user_file (tighten-only)", u["doc"], False), ("no user file", None, False)]
    if u["state"] == "invalid":
        return [("user_file invalid", None, True)]
    return [("no user file", None, False)]


def effective_level(ctx):
    best = None
    for name, doc, force in views(ctx):
        lv, src = view_level(ctx, doc, force)
        if best is None or is_lower(lv, best[0]):
            best = (lv, src)
    lv, src = best
    if ctx["project"]["state"] == "invalid":
        if is_lower("supervised", lv):
            lv, src = "supervised", "project file invalid (D3 fail closed)"
    elif ctx["project"]["state"] == "valid":
        doc = ctx["project"]["doc"]
        glv, gsrc = group_level(doc, ctx["skill"], ctx["category"], None, "project") if ctx["skill"] else (None, None)
        plv, psrc = (glv, gsrc) if gsrc else (doc.get("level"), "project.level")
        if plv and is_lower(plv, lv):
            lv, src = plv, psrc
    if ctx["stamp"] in ("missing", "unsafe") and is_lower("supervised", lv):
        lv, src = "supervised", "call stamp %s (D8)" % ctx["stamp"]
    return lv, src


def resolve(o):
    ctx = build_ctx(o)
    cat = ctx["cat"]
    requested = o["action"]
    aid = cat["alias"].get(requested, requested)
    if aid != requested:
        warn("%s is an alias of %s" % (requested, aid))
    if aid in cat["by"]:
        cands = candidates(cat["by"][aid], ctx["conds"], cat, ctx["raised_by"])
    else:
        warn("unknown action id %s: UNCLASSIFIED, treated as R4 (D1)" % requested)
        cands = [{"id": requested, "r": 4, "raised": False, "via": [], "never_auto": True, "pre": None,
                  "denies": [], "unclassified": True}]
    # one pass per view; a tighten-only user file is the stricter of with and without it
    final = None
    for name, doc, force in views(ctx):
        lv, lsrc = view_level(ctx, doc, force)
        trace("view %s: level %s (%s)" % (name, lv, lsrc))
        view = {"level": lv, "user_doc": doc}
        got = pick([(c, eval_candidate(c, view, ctx)) for c in cands])
        if final is None or RANK[got[1]["v"]] > RANK[final[1]["v"]]:
            final = got
    c, st = final
    verdict, by = st["v"], st["by"]
    deny_from = by if verdict == "deny" else None
    h2d = False
    if verdict == "ask" and ctx["headless"]:
        verdict, h2d = "deny", True
        deny_from = "headless: no human present, so ask becomes deny (D2)"
        trace("headless: ask -> deny")
    if c["id"] == "pr.merge.auto" or aid == "pr.merge.auto":
        for kind, path, flag in ctx["auto_merge_inputs"]:
            if flag is True:
                warn("%s %s delivery.auto_merge true grants nothing: the durable route is "
                     "/plugin-config pr.merge.auto allow or a trusted project file (D4 rows 3-4)" % (kind, path))
        eam = ctx["env_auto_merge"]
        if eam == "always":
            warn("TAMIRS_AUTO_MERGE=always is ignored: run /plugin-config pr.merge.auto allow (D4 row 2)")
        elif eam and eam != "never":
            warn("TAMIRS_AUTO_MERGE=%r is not never or always: ignored" % eam)
    lv, lsrc = effective_level(ctx)
    pre = None
    if c["pre"]:
        s = ctx["conds"].get(c["pre"])
        pre = {"name": c["pre"], "state": "holds" if s else ("does-not-hold" if s is False else "unknown")}
    aw = allow_with(c, st, ctx, verdict, lv)
    word = {"allow": "allowed", "ask": "asks", "deny": "denied"}[verdict]
    doc = {
        "action": aid, "requested": requested, "effective_action": c["id"], "r": c["r"],
        "level": lv, "level_source": lsrc, "level_sources": level_sources(ctx),
        "verdict": verdict, "decision": verdict,
        "reason": "%s: %s" % (word, deny_from if verdict == "deny" else by),
        "decided_by": "headless" if h2d else by, "deny_wins_from": deny_from,
        "never_auto": c["never_auto"], "precondition": pre, "raised_by": ctx["raised_by"],
        "unclassified": c["unclassified"], "headless": ctx["headless"], "headless_ask_to_deny": h2d,
        "setting_that_would_allow": aw, "allow_with": aw,
        "skill": ctx["skill"], "host": ctx["host"], "target": ctx["target"], "home_source": ctx["home_source"],
        "warnings": WARN,
    }
    if o["explain"]:
        doc["trace"] = TRACE
    return doc


def level_report(o):
    ctx = build_ctx(o)
    lv, src = effective_level(ctx)
    return {"level": lv, "level_source": src, "level_sources": level_sources(ctx), "skill": ctx["skill"],
            "host": ctx["host"], "home_source": ctx["home_source"], "warnings": WARN}


# ------------------------------------------------------------------ CLI

def parse_resolve_args(a):
    o = {"action": None, "skill": None, "target": None, "repo": None, "host": None, "objective": None,
         "call": None, "conds": {}, "headless": False, "json": False, "level_mode": False, "explain": False}
    val = {"--action": "action", "--skill": "skill", "--target": "target", "--repo": "repo", "--host": "host",
           "--objective": "objective", "--call": "call", "--cond": "cond"}
    flag = {"--headless": "headless", "--json": "json", "--level": "level_mode", "--explain": "explain"}
    i = 0
    while i < len(a):
        x = a[i]
        k, v, inline = x, None, False
        if x.startswith("--") and "=" in x:
            k, v = x.split("=", 1)
            inline = True
        if k in val:
            if not inline:
                i += 1
                if i >= len(a):
                    raise Usage("%s needs a value" % k)
                v = a[i]
            if k == "--cond":
                m = re.match(r"\A([a-z][a-z0-9_]*)=(true|false)\Z", v)
                if not m:
                    raise Usage("--cond expects <condition>=true|false, got %r" % v)
                o["conds"][m.group(1)] = m.group(2) == "true"
            elif o[val[k]] is not None:
                raise Usage("%s given twice" % k)
            else:
                o[val[k]] = v
        elif k in flag and not inline:
            o[flag[k]] = True
        elif not x.startswith("-") and o["action"] is None:
            o["action"] = x
        else:
            raise Usage("unknown argument %r" % x)
        i += 1
    if o["host"] is not None and o["host"] not in HOSTS:
        raise Usage("--host must be one of %s" % ", ".join(HOSTS))
    if o["skill"] is not None and not SKILL_RE.match(o["skill"]):
        raise Usage("--skill %r is not a skill id" % o["skill"])
    if o["objective"] is not None and not OBJ_RE.match(o["objective"]):
        raise Usage("--objective %r is not an objective id" % o["objective"])
    if o["call"] is not None and not CALL_RE.match(o["call"]):
        raise Usage("--call expects 8-128 characters of [A-Za-z0-9_-]")
    if not o["level_mode"]:
        if o["action"] is None:
            raise Usage("missing the action id (--action <id>)")
        if not ID_RE.match(o["action"]):
            raise Usage("%r is not an action id" % o["action"])
    return o


def error_doc(action, msg, kind):
    return {"action": action if action and ID_RE.match(action) else None, "r": 4, "level": None,
            "level_source": None, "level_sources": [], "verdict": "deny", "decision": "deny",
            "reason": "denied: %s (fail closed, D4, SR S-12)" % msg, "decided_by": kind, "deny_wins_from": kind,
            "never_auto": True, "precondition": None, "headless_ask_to_deny": False,
            "setting_that_would_allow": None, "allow_with": None, "warnings": WARN + [msg], "error": msg}


def explain_text(doc):
    lines = ["action: %s (R%s)%s" % (doc.get("action"), doc.get("r"),
                                      "" if doc.get("effective_action") in (None, doc.get("action"))
                                      else " judged as %s" % doc["effective_action"]),
             "level: %s  (from %s)" % (doc.get("level"), doc.get("level_source"))]
    for s in doc.get("level_sources", []):
        lines.append("  source %s: %s%s" % (s.get("source"), s.get("state", "-"),
                                            " = %s" % s["level"] if s.get("level") else ""))
    for t in doc.get("trace", []):
        lines.append("trace " + t)
    for w in doc.get("warnings", []):
        lines.append("warning " + w)
    lines.append("verdict: %s  (%s)" % (doc.get("verdict"), doc.get("reason")))
    aw = doc.get("setting_that_would_allow")
    if aw:
        if aw.get("once"):
            lines.append("allow once with: " + aw["once"])
        for d in aw.get("durable") or []:
            lines.append("allow durably with: " + d)
        if aw.get("note"):
            lines.append("note: " + aw["note"])
    return "\n".join(lines)


def out(doc, text):
    sys.stdout.write((explain_text(doc) if text else json.dumps(doc, indent=2)) + "\n")


def cmd_resolve(a):
    action, text = (a[0] if a and not a[0].startswith("-") else None), False
    try:
        for i, x in enumerate(a):
            if x == "--action" and i + 1 < len(a):
                action = a[i + 1]
            elif x.startswith("--action="):
                action = x.split("=", 1)[1]
        o = parse_resolve_args(a)
        action = o["action"]
        text = o["explain"] and not o["json"]
        doc = level_report(o) if o["level_mode"] else resolve(o)
        if o["level_mode"] and text:
            sys.stdout.write("level: %s  (from %s)\n" % (doc["level"], doc["level_source"]))
            for s in doc["level_sources"]:
                sys.stdout.write("  source %s: %s%s\n" % (s.get("source"), s.get("state", "-"),
                                                          " = %s" % s["level"] if s.get("level") else ""))
            return 0
        out(doc, text)
        return 0
    except Usage as e:
        out(error_doc(action, "usage: %s" % e, "usage-error"), text)
        return 2
    except Internal as e:
        out(error_doc(action, "resolver error: %s" % e, "resolver-error"), text)
        return 3
    except Exception as e:  # any crash is a deny
        out(error_doc(action, "resolver crashed: %s: %s" % (type(e).__name__, e), "resolver-error"), text)
        return 3


def main():
    if not ARGS:
        sys.stderr.write("permission engine: no subcommand\n")
        return 3
    cmd, a = ARGS[0], ARGS[1:]
    if cmd == "resolve":
        return cmd_resolve(a)
    try:
        if cmd == "home":
            print(passwd_home()[0])
        elif cmd == "dirs":
            home, src = passwd_home()
            cfg, state = dirs(home)
            print(json.dumps({"home": home, "home_source": src, "config_dir": cfg, "state_dir": state,
                              "warnings": WARN}))
        elif cmd == "check-file":
            kind = a[1] if len(a) > 1 else "private"
            if kind == "dir":
                probs = dir_problems(a[0])
                st = "ok" if not probs else "unsafe"
                real = os.path.realpath(a[0])
            else:
                if kind not in ("private", "store", "any"):
                    raise Internal("check-file kind must be private, store, any or dir")
                r = read_guarded(a[0], kind)
                st, probs, real = r["state"], r["problems"] + ([r["error"]] if r.get("error") else []), r["real"]
            print(json.dumps({"path": a[0], "real": real, "state": st, "problems": probs}))
            return 0 if st == "ok" else 1
        elif cmd == "store-level":
            host = a[0] if a else None
            if host not in HOSTS:
                raise Internal("store-level needs a host: %s" % ", ".join(HOSTS))
            ss = option_stores(passwd_home()[0], host)
            got = [s["level"] for s in ss if s["level"]]
            print(json.dumps({"host": host, "stores": ss, "level": lowest(*got) if got else None,
                              "warnings": WARN}))
        elif cmd == "sha256":
            with open(a[0], "rb") as f:
                print(sha256(f.read()))
        elif cmd == "load-user":
            u = load_user(passwd_home()[0], load_schema())
            u.pop("doc", None)
            u["warnings"] = WARN
            print(json.dumps(u))
        elif cmd == "lock-check":
            u = load_user(passwd_home()[0], load_schema())
            print(u["lock"] or u["state"])
        elif cmd == "load-project":
            pf = load_project(repo_info(a[0] if a else None), load_schema())
            pf.pop("doc", None)
            pf["warnings"] = WARN
            print(json.dumps(pf))
        elif cmd == "trust":
            repo = repo_info(a[0] if a else None)
            schema = load_schema()
            ok, why = trust_state(load_user(passwd_home()[0], schema), load_project(repo, schema), repo,
                                  a[1] if len(a) > 1 else None)
            print(json.dumps({"trusted": ok, "reason": why, "warnings": WARN}))
        elif cmd == "map":
            cat = load_catalog()
            if len(a) < 2 or a[1] not in LEVELS:
                raise Internal("map needs <action-id> <level>")
            conds = {}
            for x in a[2:]:
                if x.startswith("--cond="):
                    x = x[7:]
                m = re.match(r"\A([a-z][a-z0-9_]*)=(true|false)\Z", x)
                if m:
                    conds[m.group(1)] = m.group(2) == "true"
            aid = cat["alias"].get(a[0], a[0])
            if aid in cat["by"]:
                cs = candidates(cat["by"][aid], conds, cat, [])
            else:
                cs = [{"id": aid, "r": 4, "raised": False, "via": [], "never_auto": True, "pre": None,
                       "denies": [], "unclassified": True}]
            best = "allow"
            for c in cs:
                v = ceiling(c, a[1], cat, conds)[0]
                if any(conds.get(d["when"]) is not False for d in c["denies"]):
                    v = "deny"
                if v == "allow" and (c["r"] >= 4 or c["never_auto"]):
                    v = "ask"
                best = stricter(best, v)
            print(best)
        elif cmd == "normalize-remote":
            print(normalize_remote(a[0] if a else "") or "")
        elif cmd == "repo-key":
            r = repo_info(a[0] if a else None)
            print(r["key"] if r else "")
        else:
            raise Internal("unknown subcommand %s" % cmd)
        return 0
    except (Internal, IndexError, OSError) as e:
        sys.stderr.write("permission engine: %s\n" % e)
        return 3


sys.exit(main())
PY

# perm_python <subcommand> [args...] — run the engine. Returns 127 without python3.
perm_python() {
  command -v python3 >/dev/null 2>&1 || return 127
  [ -n "$PERM_ROOT" ] || return 3
  python3 -I -S -c "$_PERM_ENGINE" "$PERM_ROOT" "$@"
}

# perm_json_string <text> — a JSON string literal, builtins only (no python3).
perm_json_string() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  s="${s//$'\t'/ }"
  printf '"%s"' "$s"
}

# perm_deny_json <action-id> <message> — the fail-closed answer, builtins only.
perm_deny_json() {
  local action="$1" msg="$2" a='null' m
  case "$action" in
    ''|*[!A-Za-z0-9._-]*) a='null' ;;
    *) a="\"$action\"" ;;
  esac
  m="$(perm_json_string "resolver error: $msg")"
  printf '{"action": %s, "r": 4, "level": null, "level_source": null, "level_sources": [], ' "$a"
  printf '"verdict": "deny", "decision": "deny", "reason": "denied: %s (fail closed, D4, SR S-12)", ' "${m:1:${#m}-2}"
  printf '"decided_by": "resolver-error", "deny_wins_from": "resolver-error", "never_auto": true, '
  printf '"precondition": null, "headless_ask_to_deny": false, "setting_that_would_allow": null, '
  printf '"allow_with": null, "warnings": [%s], "error": %s}\n' "$m" "$m"
}

# perm_resolve <args...> — the D4 resolution as JSON (or --explain text).
# Exit 0 = decided; 2 = usage error; 3 = internal error. 2 and 3 print a deny.
perm_resolve() {
  local out rc action="" prev="" arg
  # The action id, only for the fallback answer below: a leading positional
  # (the D4 form) or --action.
  case "${1:-}" in -*|'') ;; *) action="$1" ;; esac
  for arg in "$@"; do
    [ "$prev" = "--action" ] && action="$arg"
    case "$arg" in --action=*) action="${arg#--action=}" ;; esac
    prev="$arg"
  done
  out="$(perm_python resolve "$@")" && rc=0 || rc=$?
  if [ -n "$out" ] && { [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ] || [ "$rc" -eq 3 ]; }; then
    printf '%s\n' "$out"
    return "$rc"
  fi
  if [ "$rc" -eq 127 ]; then
    perm_deny_json "$action" "python3 is not available"
  else
    perm_deny_json "$action" "the engine exited $rc without an answer"
  fi
  return 3
}

# perm_passwd_home — the passwd home of the real uid. python3 first (it also
# applies the guarded test override); without it getent (Linux) or dscl (macOS),
# by absolute path, and never the test override.
perm_passwd_home() {
  local h="" uid name
  if h="$(perm_python home 2>/dev/null)" && [ -n "$h" ]; then
    printf '%s\n' "$h"
    return 0
  fi
  uid="$(/usr/bin/id -u 2>/dev/null)" || return 1
  if [ -x /usr/bin/getent ]; then
    h="$(/usr/bin/getent passwd "$uid" 2>/dev/null)"
    h="${h#*:*:*:*:*:}"
    h="${h%%:*}"
  elif [ -x /usr/bin/dscl ]; then
    name="$(/usr/bin/id -un 2>/dev/null)" || return 1
    h="$(/usr/bin/dscl . -read "/Users/$name" NFSHomeDirectory 2>/dev/null)"
    h="${h#NFSHomeDirectory: }"
  fi
  case "$h" in
    /*) printf '%s\n' "$h" ;;
    *) return 1 ;;
  esac
}

perm_dirs() { perm_python dirs; }
perm_user_config_dir() { local h; h="$(perm_passwd_home)" || return 1; printf '%s/.config/tamirs-superpowers\n' "$h"; }
perm_state_dir() { local h; h="$(perm_passwd_home)" || return 1; printf '%s/.local/state/tamirs-superpowers\n' "$h"; }
perm_check_file() { perm_python check-file "$@"; }
perm_option_store_level() { perm_python store-level "$@"; }
perm_sha256() { perm_python sha256 "$@"; }
perm_load_user_file() { perm_python load-user; }
perm_load_project_file() { perm_python load-project "$@"; }
perm_lock_check() { perm_python lock-check; }
perm_trust_check() { perm_python trust "$@"; }
perm_map_verdict() { perm_python map "$@"; }
perm_normalize_remote() { perm_python normalize-remote "$@"; }
perm_repo_key() { perm_python repo-key "$@"; }
