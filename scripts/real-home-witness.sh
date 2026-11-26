#!/usr/bin/env bash
# real-home-witness.sh — did a test suite write to the plugin's config or state in the REAL home?
#
# Usage:
#   scripts/real-home-witness.sh [--home DIR] snapshot > FILE   record the plugin's real config and state dirs
#   scripts/real-home-witness.sh [--home DIR] check FILE        compare them now with FILE; exit 1 on a leak
#   scripts/real-home-witness.sh -h | --help
#
# `make test-hooks` snapshots before every suite and checks after it, and fails naming the suite and the
# paths on a leak: a suite that drives the real hooks must use the resolver's test root, never the user's
# own config or state. Two suites leaked there in the 5.2.0 run (an intent file, a confirm stamp) and
# nothing noticed until a human looked.
#
# The home comes from the passwd entry, not $HOME: suites set a fake HOME, and the leak is precisely a write
# that went past it. `--home DIR` exists for this script's own tests only. A missing directory records as
# "absent", so CI (where neither exists) compares equal.
#
# WHAT IS RECORDED
#   Every path under <home>/.config/tamirs-superpowers and <home>/.local/state/tamirs-superpowers: kind,
#   size, nanosecond mtime and a sha256 of a file's content (whole-second mtime missed a same-length
#   overwrite within the same second), a directory's mtime, a symlink's target.
#
# THE EXCUSED WRITERS: LIVE HOST SESSIONS (#400)
#   On a maintainer machine, host sessions running the installed plugin write to the same state while a
#   suite runs, and the old single-hash witness failed whichever suite was running. Two kinds of write are
#   excused, file by file, and only when the file is attributable to a live host session. A LIVE SESSION
#   is a UUID (the shape Claude Code, Codex, Gemini CLI and Cursor mint) that occurs in no file under
#   tests/: suites pass literal ids (sess-1, s-1, hv-1, pg-1, and a few fixed UUIDs).
#
#   Since 6.0.0 (ADR 006) nothing in this plugin writes there; sessions still running a 5.2-5.6 install
#   do, until they are upgraded, so their two writers stay excused:
#   hostver/  the host-version probe cache (the 5.x permission library's cached_probe), rewritten
#             per session every 10 minutes. An added or changed <host>.<16 hex>.json is excused when it
#             is a version-1 entry for that host, the 16 hex are the sha256 of its session, the session
#             is live, and its bin is an existing executable outside every temp directory and this
#             checkout (a suite's fake host CLI lives in its temp dir). An empty .lock is excused.
#   intent/   the active-skill contexts (the 5.x active-skill hook), rewritten on every slash command
#             and Skill call. An added or changed <sid>.json, <sid>.agent-<key>.json, <sid>.expansion.json
#             or <sid>.submit.json is excused when <sid> is live, the file is a JSON object and a context
#             names that same session_id. A deletion is excused when the file was already past the age
#             at which the 5.x writer prunes it (24 h; 10 min for the two halves).
#   In both: the directory's own mtime, and an atomic writer's temp file that has already been renamed
#   away. Everything else is a leak: a test session (sess-1) or no session, a fake bin, a fresh file
#   deleted, an unknown name, and every change anywhere else (a stamp, a ticket, a pending record, a
#   config file). A suite that wrote such a file under a runtime-random UUID would pass; no suite mints
#   one, and a probe entry of the real host CLI is indistinguishable from the host's own.
#
# Exit: 0 unchanged, or every change excused · 1 a leak (each path named on stdout) · 2 usage error
set -euo pipefail

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }

home=""
cmd=""
snap=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --home) [ $# -ge 2 ] || { echo "real-home-witness.sh: --home needs a directory" >&2; exit 2; }
            home="$2"; shift 2 ;;
    snapshot) cmd=snapshot; shift ;;
    check) [ $# -ge 2 ] || { echo "real-home-witness.sh: check needs the snapshot file" >&2; exit 2; }
           cmd=check; snap="$2"; shift 2 ;;
    *) echo "real-home-witness.sh: unknown argument $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -n "$cmd" ] || { echo "real-home-witness.sh: missing command (snapshot | check FILE)" >&2; usage >&2; exit 2; }
if [ "$cmd" = check ] && [ ! -f "$snap" ]; then
  echo "real-home-witness.sh: no snapshot file $snap" >&2; exit 2
fi
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec python3 -I -S - "$cmd" "$home" "$snap" "$repo" <<'PY'
import hashlib, json, os, pwd, re, stat, sys, tempfile, time

cmd, home, snap, repo = sys.argv[1:5]
if not home:
    home = pwd.getpwuid(os.getuid()).pw_dir
PLUGIN = "tamirs-superpowers"
TOPS = [os.path.join(home, ".config", PLUGIN), os.path.join(home, ".local", "state", PLUGIN)]
HOSTVER = os.path.join(TOPS[1], "hostver")
INTENT = os.path.join(TOPS[1], "intent")
UUID = r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
UUID_RE = re.compile(r"\A%s\Z" % UUID)
# hostver/: <host>.<sha256(session)[:16]>.json, written through <entry>.tmp-<pid> (a 5.x install)
ENTRY_RE = re.compile(r"\A([a-z][a-z0-9-]*)\.([0-9a-f]{16})\.json\Z")
PROBE_TMP_RE = re.compile(r"\A[a-z][a-z0-9-]*\.[0-9a-f]{16}\.json\.tmp-[0-9]+\Z")
# intent/: <sid>.json, <sid>.agent-<key>.json, <sid>.expansion.json, <sid>.submit.json, written through
# .<name>.tmp-<pid> and pruned past 24 h (10 min for the two halves) (a 5.x install)
INTENT_RE = re.compile(r"\A(%s)(\.agent-[A-Za-z0-9_-]{1,64}|\.expansion|\.submit)?\.json\Z" % UUID)
INTENT_TMP_RE = re.compile(r"\A\..+\.json\.tmp-[0-9]+\Z")
INTENT_TTL, INTENT_HALF_TTL = 24 * 3600, 600   # the 5.x writer's TTL_CONTEXT, HALF_TTL
SESSION_DIRS = (HOSTVER, INTENT)
BYTES = {}   # path -> content, for the files of the current walk in SESSION_DIRS


def entry(p):
    """One path's record, or None when it vanished between listing and reading (another process's temp)."""
    try:
        st = os.lstat(p)
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(st.st_mode):
        return ["link", os.readlink(p)]
    if stat.S_ISDIR(st.st_mode):
        return ["dir", st.st_mtime_ns]
    if not stat.S_ISREG(st.st_mode):
        return ["other", stat.S_IFMT(st.st_mode), st.st_mtime_ns]
    try:
        with open(p, "rb") as f:
            data = f.read()
    except FileNotFoundError:
        return None
    except OSError as e:
        return ["file", st.st_size, st.st_mtime_ns, "unreadable: %s" % e.__class__.__name__]
    if os.path.dirname(p) in SESSION_DIRS:
        BYTES[p] = data
    return ["file", st.st_size, st.st_mtime_ns, hashlib.sha256(data).hexdigest()]


def manifest():
    m = {}
    for top in TOPS:
        rec = entry(top)
        m[top] = rec or ["absent"]
        if not rec or rec[0] != "dir":
            continue
        for root, dirs, files in os.walk(top):
            dirs.sort()
            names = sorted(files) + sorted(d for d in dirs if os.path.islink(os.path.join(root, d)))
            for p in [root] + [os.path.join(root, n) for n in names]:
                rec = entry(p)
                if rec is not None:
                    m[p] = rec
    return m


TEST_TEXT = None


def in_tests(s):
    """Does the literal s occur in any file under the checkout's tests/?"""
    global TEST_TEXT
    if TEST_TEXT is None:
        chunks = []
        for root, dirs, files in os.walk(os.path.join(repo, "tests")):
            for n in files:
                try:
                    with open(os.path.join(root, n), "rb") as f:
                        chunks.append(f.read())
                except OSError:
                    pass
        TEST_TEXT = b"\0".join(chunks)
    return s.encode("utf-8", "replace") in TEST_TEXT


def temp_roots():
    roots = {"/tmp", "/private/tmp", "/var/tmp", "/private/var/tmp", "/var/folders", "/private/var/folders",
             tempfile.gettempdir(), os.environ.get("TMPDIR") or "/tmp", repo}
    return {os.path.realpath(r).rstrip("/") + "/" for r in roots if r}


def live_session_problem(sess):
    """None when sess is a live host session's id, else why it is not."""
    if not isinstance(sess, str) or not UUID_RE.match(sess):
        return "session %r is not a host-minted UUID" % (sess,)
    if in_tests(sess):
        return "session %s is a literal in tests/" % sess
    return None


def json_object(data):
    try:
        d = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        return None
    return d if isinstance(d, dict) else None


def probe_entry_problem(name, data):
    """None when <name> holding <data> is a live host session's probe-cache entry, else why it is not."""
    m = ENTRY_RE.match(name)
    if not m:
        return "not a probe-cache entry name"
    d = json_object(data)
    if d is None:
        return "not a JSON object"
    if d.get("version") != 1 or d.get("host") != m.group(1):
        return "not a version-1 %s probe entry" % m.group(1)
    sess = d.get("session")
    why = live_session_problem(sess)
    if why:
        return why
    if hashlib.sha256(sess.encode("utf-8")).hexdigest()[:16] != m.group(2):
        return "its name does not match its session"
    b = d.get("bin")
    if not isinstance(b, str) or not os.path.isabs(b):
        return "bin %r is not an absolute path" % (b,)
    real = os.path.realpath(b)
    if any((real + "/").startswith(r) for r in temp_roots()):
        return "bin %s is under a temp directory or this checkout" % real
    if not (os.path.isfile(real) and os.access(real, os.X_OK)):
        return "bin %s is not an existing executable" % real
    return None


def intent_problem(name, data):
    """None when <name> holding <data> is a live host session's intent file, else why it is not."""
    m = INTENT_RE.match(name)
    if not m:
        sid = name.split(".", 1)[0]
        return live_session_problem(sid) or "not an intent file name"
    why = live_session_problem(m.group(1))
    if why:
        return why
    d = json_object(data)
    if d is None:
        return "not a JSON object"
    if m.group(2) in (None, "") or m.group(2).startswith(".agent-"):
        if d.get("session_id") != m.group(1):
            return "its session_id %r is not the session its name carries" % (d.get("session_id"),)
    return None


def excuse(p, old, new):
    """None when the change at p is a live host session's write, else why it counts as a leak."""
    if p in SESSION_DIRS and old and new and old[0] == new[0] == "dir":
        return None
    d = os.path.dirname(p)
    if d not in SESSION_DIRS:
        return "not a file live sessions write"
    name = os.path.basename(p)
    is_tmp = (PROBE_TMP_RE if d == HOSTVER else INTENT_TMP_RE).match(name)
    if is_tmp and not os.path.lexists(p):
        return None    # an atomic write in flight, since renamed onto its file (which is judged on its own)
    if new is None:
        if d == INTENT and old and old[0] == "file":
            age = INTENT_HALF_TTL if name.endswith((".expansion.json", ".submit.json")) else INTENT_TTL
            if old[2] / 1e9 < time.time() - age:
                return None    # past its age: a live 5.x session's writer pruned it
        return "deleted"
    if d == HOSTVER and name == ".lock":
        return None if new[0] == "file" and new[1] == 0 else "a .lock that is not an empty file"
    if new[0] != "file":
        return "a %s, not a file" % new[0]
    if is_tmp:
        name = name.rsplit(".tmp-", 1)[0].lstrip(".") if d == INTENT else name.rsplit(".tmp-", 1)[0]
    data = BYTES.get(p, b"")
    return probe_entry_problem(name, data) if d == HOSTVER else intent_problem(name, data)


def tilde(p):
    return "~" + p[len(home):] if p.startswith(home.rstrip("/") + "/") else p


cur = manifest()
if cmd == "snapshot":
    json.dump(cur, sys.stdout, sort_keys=True)
    sys.stdout.write("\n")
    sys.exit(0)

try:
    with open(snap) as f:
        before = json.load(f)
    if not isinstance(before, dict):
        raise ValueError
except (OSError, ValueError):
    sys.stderr.write("real-home-witness.sh: %s is not a snapshot from this script\n" % snap)
    sys.exit(2)
leaks, excused = [], []
for p in sorted(set(before) | set(cur)):
    old, new = before.get(p), cur.get(p)
    if old == new:
        continue
    why = excuse(p, old, new)
    kind = "added" if old is None else "deleted" if new is None else "changed"
    (excused if why is None else leaks).append((p, kind, why))
for p, kind, _ in excused:
    print("  witness: ignored %s %s (a live host session's write, #400)" % (kind, tilde(p)))
for p, kind, why in leaks:
    print("  witness: LEAK %s %s (%s)" % (kind, tilde(p), why))
sys.exit(1 if leaks else 0)
PY
