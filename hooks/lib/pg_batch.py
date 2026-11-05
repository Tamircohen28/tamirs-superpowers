"""pg_batch.py - hooks/permission-guard.sh's engine, started once and run over many calls.

Started by `permission-guard.sh --classify-batch` and `--judge-batch` only (the tests' entries;
no hook manifest names them), as `python3 -I -S hooks/lib/pg_batch.py <plugin root>`, with the
protocol on two descriptors the guard opens on named pipes, never on stdin or stdout: a child the
engine starts (the resolver, git, the tokeniser, the state-dir lookup) could inherit those two and
read or write the protocol, and no child inherits 3 or 4 (subprocess closes them).

  fd 3  NUL-terminated fields. The first is the engine's source, the guard's _PG_ENGINE heredoc.
        Then one request per call, eight fields: host, mode, budget, fast, bash, res_hosts,
        cursor_ask, payload - the engine's argv 2..8 and its stdin, exactly what the guard's
        single-call path passes.
  fd 4  one answer per request: a header line "<rc>\\t<n>\\n", then n lines: what the engine
        wrote to its stdout with every trailing newline removed (as the guard's $(...) capture
        does), rc its exit status (0 from answer() and the classify print; 1 for any crash,
        which is what python3 itself exits).

The source is compiled once and executed once per request in fresh module globals, with the
sys.argv, sys.stdin and sys.stdout of that request, so a request sees exactly what a fresh
`python3 -c` would: its own T0 and budget, its own catalog read, its own caches. The two parser
modules hooks/lib/pg_http.py and pg_graphql.py are imported by the first shell request and stay
in sys.modules, which is the whole saving: every later request's `import` is a dictionary lookup.
Nothing the engine does reaches the next request: it sets no signal handler, changes no
directory and writes no environment variable (read when this driver was written; a change there
would show in the batch-vs-single-call agreement the suites keep), and its globals are discarded.

An engine that raises is answered rc 1 with whatever it had printed, as the single-call guard
sees a crashed engine (and denies). An incomplete request (EOF mid-record) ends the process:
the guard reads EOF on fd 4 and denies the line.
"""
import io
import os
import sys

REQ_FIELDS = 8
IN_FD, OUT_FD = 3, 4


class Fields(object):
    """NUL-terminated fields from a descriptor, read in chunks; None at EOF."""

    def __init__(self, fd):
        self.fd = fd
        self.buf = bytearray()

    def next(self):
        while True:
            i = self.buf.find(b"\0")
            if i >= 0:
                field = bytes(self.buf[:i])
                del self.buf[:i + 1]
                return field
            chunk = os.read(self.fd, 65536)
            if not chunk:
                return None
            self.buf += chunk


def write_all(fd, data):
    view = memoryview(data)
    while view:
        n = os.write(fd, view)
        view = view[n:]


def run_one(code, root, req):
    """One engine run; (rc, captured stdout as text)."""
    argv = ["-c", root] + [os.fsdecode(f) for f in req[:-1]]
    payload = req[-1]
    cap = io.StringIO()
    saved_argv, saved_in, saved_out = sys.argv, sys.stdin, sys.stdout
    sys.argv = argv
    sys.stdin = io.TextIOWrapper(io.BytesIO(payload), encoding="utf-8", errors="surrogateescape")
    sys.stdout = cap
    rc = 0
    try:
        exec(code, {"__name__": "__main__"})
    except SystemExit as e:
        c = e.code
        rc = 0 if c is None else (c if isinstance(c, int) else 1)
    except KeyboardInterrupt:
        raise
    except BaseException:  # noqa: BLE001 - a crashed engine is rc 1, which the guard denies
        rc = 1
    finally:
        sys.argv, sys.stdin, sys.stdout = saved_argv, saved_in, saved_out
    return rc, cap.getvalue()


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: pg_batch.py <plugin root> (fd 3 requests, fd 4 answers)\n")
        return 2
    root = sys.argv[1]
    fields = Fields(IN_FD)
    src = fields.next()
    if src is None:
        return 2
    code = compile(src.decode("utf-8", "surrogateescape"), "<permission-guard engine>", "exec")
    while True:
        req = []
        for _ in range(REQ_FIELDS):
            f = fields.next()
            if f is None:
                return 0
            req.append(f)
        rc, text = run_one(code, root, req)
        text = text.rstrip("\n")
        lines = text.split("\n") if text else []
        out = ("%d\t%d\n" % (rc, len(lines))).encode("ascii")
        if lines:
            out += ("\n".join(lines) + "\n").encode("utf-8", "surrogateescape")
        write_all(OUT_FD, out)


if __name__ == "__main__":
    sys.exit(main())
