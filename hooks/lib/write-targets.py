#!/usr/bin/env python3
"""Extract the files a PreToolUse tool call will WRITE.

Reads a PreToolUse hook payload on stdin, writes one tab-separated record per
line to stdout, and always exits 0 (a guard that crashes must not take the
user's tool call down with it — but see UNSURE, it does not go quiet either):

    TARGET <tab> <absolute path>  <tab> <the command fragment it came from>
    DELETE <tab> <absolute path>  <tab> <the command fragment it came from>
    UNSURE <tab> <why not>        <tab> <the command fragment it came from>

With `--protected` (guard-sensitive-files.sh only) the records above are
preceded by one line per protected subject, a path that a copy, move or
extraction fills is a TREE record instead of a TARGET, and every
TARGET/DELETE/TREE whose realpath (spelled on disk, on a case-insensitive
volume) differs is repeated under it — see "Protected paths" below:

    TREE      <tab> <absolute path> <tab> <the command fragment it came from>
    PROTECTED <tab> deny|ask <tab> <why, naming the path and the matched rule>

Without `--protected` a TREE is reported as the TARGET it always was.

DELETE is separated from TARGET because the two are not the same act. Removing
generated build output is a legitimate clean; authoring content into it is the
thing the build-output rule exists to stop. Removing a workflow or a lockfile is
still a modification, and is still judged.

WHY THIS EXISTS — the guard used to ask the wrong question
    `guard-sensitive-files.sh` decided what to block by looking at which TOOL
    was running: its hook matcher was `Edit|Write|MultiEdit|…`, so every path it
    protected stayed writable through `Bash` — `cat > f <<EOF`, `sed -i`, `tee`,
    `cp`. No deliberate circumvention was needed; an agent that simply prefers
    Bash for edits never saw the guard and never learned the file was protected.
    The control was enforced on exactly the actors that announced themselves.

WHY IT EXTRACTS TARGETS INSTEAD OF GREPPING THE COMMAND
    The tempting fix — search the command string for a protected path — is the
    defect this repo already has on record twice: `docker-guard.py` matches
    command TEXT, and has blocked a read-only `grep` whose pattern contained a
    matching literal, and a `git commit -m` whose message prose did. Text
    matching cannot tell "writes yarn.lock" from "mentions yarn.lock".

    So nothing here looks for protected paths. It parses the command, finds the
    constructs that WRITE (redirections, `tee`, in-place editors, `cp`/`mv`,
    a downloader's output flag, …) and reports only the operands those constructs write to. A
    path that appears anywhere else in the command — a `grep` pattern, a commit
    message, a `sed` script, a heredoc body — is never a target, because it is
    never in a target position. That is a property of the parse, not a list of
    exceptions.

WHAT IT CANNOT DECIDE, AND SAYS SO
    A shell command's write targets are not always statically knowable. Where
    the target is a variable, a command substitution or a glob, and where the
    command is an arbitrary-code evaluator handed inline code, this emits UNSURE
    rather than falling silent. One variable IS resolved: a name the same
    command assigned a literal to, unconditionally, earlier in the text
    (`S=/tmp/x; cp a "$S/b"` — see "Same-command literal assignments"), because
    the text answers the question and an advisory there is a silent allow of
    `"$S/package-lock.json"`. Silence would read as "no protected file
    touched" when the true answer is "could not determine" — the exact shape of
    failure this repo's `no silent or empty failure paths` rule forbids.

    UNSURE is deliberately NOT emitted for "any command could in principle
    write anything" (`make build`, `npm install`, `python3 script.py`). Taken
    that far the warning fires on everything and means nothing. The line drawn
    here is: the command is a write primitive whose target cannot be resolved,
    or it is an evaluator given code to run inline. Those are the shapes an
    agent reaches for when it edits a file through Bash; a build tool is not one
    of them, and the tool-level guard never claimed to cover it.

Usage:
    printf '%s' "$payload" | python3 write-targets.py
    printf '%s' "$payload" | python3 write-targets.py --protected
    python3 write-targets.py --help
"""
import json
import os
import re
import sys

# --------------------------------------------------------------------------
# Tokenizer
# --------------------------------------------------------------------------
# Quote-aware so that `grep '>' f`, `git commit -m "a > b"` and
# `sed 's|x|y|' f` cannot be mistaken for redirections or path operands.
#
# ONE PASS, THE WAY BASH READS IT
#   Heredoc bodies are consumed here, at the newline that ends the line which
#   introduced them, instead of by a separate line-by-line pre-pass. The pre-pass
#   tokenized each LINE on its own, so a `<<` that bash never sees as one — inside
#   `(( 1 << 2 ))`, inside a double-quoted string that spans two lines, inside a
#   `#` comment — swallowed every later line as a "heredoc body", and the write on
#   those lines was never parsed. The same three shapes, plus `$'\''` (an
#   ANSI-C quote whose escaped `'` flipped the quote parity of the rest of the
#   command), are modelled below rather than guessed at.
#
# PARSE ANOMALIES
#   What this tokenizer still cannot close — an unterminated quote or
#   substitution, a heredoc whose delimiter line never comes — is reported in
#   `anomalies`. analyze_command turns each into an ANOMALY record, and the
#   protected-path pass fails closed on it: a protected path named anywhere in
#   the command text is then treated as written (security review S-03).

# Longest first: `&>>` must win over `&>`, `<<<` over `<<-` over `<<`, `>>` over `>`.
OPERATORS = (
    "&>>", "<<<", "<<-", "&&", "||", ">>", "<<", "<>", "<&", ">|", ">&", "&>",
    ";", "|", "\n", ">", "<", "&", "(", ")",
)

SEGMENT_SEPARATORS = ("&&", "||", ";", "|", "\n", "&", "(", ")")

# `<>` opens its operand read-write: it creates the file, and `>&N` then writes it.
REDIRECT_OPS = (">", ">>", ">|", "&>", "&>>", ">&", "<>")

# Operators whose next word is an input operand, never an argument of the command.
INPUT_OPS = ("<", "<<", "<<-", "<<<", "<&")

ANSI_C_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b",
                  "f": "\f", "v": "\v", "e": "\x1b", "E": "\x1b"}
CLOSERS = {"(": ")", "[": "]", "{": "}"}


class Tok(object):
    __slots__ = ("kind", "value", "expands", "quoted")

    def __init__(self, kind, value, expands=False, quoted=False):
        self.kind = kind          # "word" | "op"
        self.value = value
        self.expands = expands    # contains an unquoted $ or ` — value is a guess
        self.quoted = quoted


def _balanced(text, start, open_ch="(", close_ch=")"):
    """(index just past the bracket matching the one at `start`, whether it closed).

    Quote-, comment- and heredoc-aware, so `$(echo ")")` closes at the right
    parenthesis and `"$(cat <<'EOF' … It's … EOF\n)"` (the usual commit-message
    idiom) does not read the apostrophe in the body as a quote. Should that scan
    run off the end anyway, the plain bracket count is the looser reading tried
    before calling the construct unterminated.
    """
    end, closed = _scan_balanced(text, start, open_ch, close_ch, True)
    if not closed:
        end2, closed2 = _scan_balanced(text, start, open_ch, close_ch, False)
        if closed2:
            return end2, True
    return end, closed


def _scan_balanced(text, start, open_ch, close_ch, aware):
    depth = 0
    i = start
    n = len(text)
    pending = []
    while i < n:
        c = text[i]
        if aware:
            if c == "\\":
                i += 2
                continue
            if c == "'":
                j = text.find("'", i + 1)
                i = n if j == -1 else j + 1
                continue
            if c == '"':
                j = i + 1
                while j < n and text[j] != '"':
                    j += 2 if text[j] == "\\" else 1
                i = j + 1
                continue
            if c == "#" and i > start and text[i - 1] in " \t\n;(|&":
                j = text.find("\n", i)
                i = n if j == -1 else j
                continue
            if text.startswith("<<", i) and not text.startswith("<<<", i):
                j = i + 2
                strip = j < n and text[j] == "-"
                j += 1 if strip else 0
                while j < n and text[j] in " \t":
                    j += 1
                k = j
                while k < n and text[k] not in " \t\n;&|()<>":
                    k += 1
                delim = re.sub(r"[\'\"\\\\]", "", text[j:k])
                if delim:
                    pending.append((delim, strip))
                i = k
                continue
            if c == "\n" and pending:
                i = _read_heredocs(text, i + 1, pending, None, lambda why: None)
                pending = []
                continue
        if c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return i + 1, True
        i += 1
    return n, False


def _read_heredocs(text, i, pending, heredocs, note):
    """Consume the bodies of the `pending` heredocs from text[i]; return the index after them."""
    n = len(text)
    for delim, strip_tabs in pending:
        lines = []
        closed = False
        while i < n:
            j = text.find("\n", i)
            line = text[i:] if j == -1 else text[i:j]
            i = n if j == -1 else j + 1
            body = line.lstrip("\t") if strip_tabs else line
            # bash ends the body only on an exact match; matching a whitespace
            # variant too can only end it EARLIER, which over-reports, never hides.
            if body.strip() == delim:
                closed = True
                break
            lines.append(body)
        if not closed:
            note("a heredoc whose closing `%s` line never comes" % delim)
        if heredocs is not None:
            heredocs.append("\n".join(lines))
    return i


def tokenize(text, anomalies=None, heredocs=None):
    """Split a shell fragment into word and operator tokens.

    Heredoc bodies are skipped, never tokenized, and appended to `heredocs`
    (when given) in the order of their `<<`/`<<-` operators, tab-stripped for
    `<<-`. Constructs this cannot close are appended to `anomalies`.
    """
    toks = []
    buf = []
    expands = False
    quoted = False
    started = False
    pending = []        # (delimiter, strip_tabs) whose bodies start at the next newline
    want = [None]       # strip_tabs of a `<<`/`<<-` still waiting for its delimiter word
    i = 0
    n = len(text)

    def note(why):
        if anomalies is not None and why not in anomalies:
            anomalies.append(why)

    def flush():
        if started:
            value = "".join(buf)
            toks.append(Tok("word", value, expands, quoted))
            if want[0] is not None:
                pending.append((value, want[0]))
                want[0] = None

    while i < n:
        ch = text[i]

        if ch == "\\":
            if i + 1 < n and text[i + 1] != "\n":
                buf.append(text[i + 1])
                started = True
                i += 2
            else:
                i += 2
            continue

        # A `#` that starts a word starts a comment: an apostrophe in it is prose.
        if ch == "#" and not started:
            j = text.find("\n", i)
            i = n if j == -1 else j
            continue

        if ch == "'":
            end = text.find("'", i + 1)
            if end == -1:
                end = n
                note("an unterminated single quote")
            buf.append(text[i + 1:end])
            quoted = True
            started = True
            i = end + 1
            continue

        # `$'…'` — ANSI-C quoting, where `\'` is a quote character, not the end.
        if ch == "$" and i + 1 < n and text[i + 1] == "'":
            j = i + 2
            while j < n and text[j] != "'":
                if text[j] == "\\" and j + 1 < n:
                    c = text[j + 1]
                    if c in "'\"\\?":
                        buf.append(c)
                    elif c in ANSI_C_ESCAPES:
                        buf.append(ANSI_C_ESCAPES[c])
                    else:
                        # \xHH, \0NNN, \uHHHH, \cX: a character this does not decode.
                        buf.append("\\" + c)
                        expands = True
                    j += 2
                    continue
                buf.append(text[j])
                j += 1
            if j >= n:
                note("an unterminated $'…' quote")
            quoted = True
            started = True
            i = j + 1
            continue

        if ch == '"':
            j = i + 1
            while j < n:
                c = text[j]
                if c == "\\" and j + 1 < n:
                    # Inside "…" a backslash escapes only $ ` " \ and a newline.
                    nx = text[j + 1]
                    if nx in '$`"\\':
                        buf.append(nx)
                        j += 2
                        continue
                    if nx == "\n":
                        j += 2
                        continue
                    buf.append(c)
                    j += 1
                    continue
                if c == '"':
                    break
                # A substitution inside "…" may hold quotes of its own.
                if c == "$" and j + 1 < n and text[j + 1] in CLOSERS:
                    end, closed = _balanced(text, j + 1, text[j + 1], CLOSERS[text[j + 1]])
                    if not closed:
                        note("an unterminated `$%s`" % text[j + 1])
                    buf.append(text[j:end])
                    expands = True
                    j = end
                    continue
                if c == "`":
                    end = text.find("`", j + 1)
                    if end == -1:
                        note("an unterminated backtick")
                    end = n if end == -1 else end + 1
                    buf.append(text[j:end])
                    expands = True
                    j = end
                    continue
                if c == "$":
                    expands = True
                buf.append(c)
                j += 1
            if j >= n:
                note("an unterminated double quote")
            quoted = True
            started = True
            i = j + 1
            continue

        if ch in " \t":
            flush()
            buf, expands, quoted, started = [], False, False, False
            i += 1
            continue

        # `$(…)`, `${…}`, `$[…]` and `` `…` `` are opaque: their contents are a
        # nested command or an expansion, not operators in this one. Left
        # un-consumed, `cp $(pick) yarn.lock` would split at the parenthesis and
        # lose the destination, and `$[ 1 << 2 ]` would open a heredoc.
        if ch == "$" and i + 1 < n and text[i + 1] in CLOSERS:
            end, closed = _balanced(text, i + 1, text[i + 1], CLOSERS[text[i + 1]])
            if not closed:
                note("an unterminated `$%s`" % text[i + 1])
            buf.append(text[i:end])
            expands = True
            started = True
            i = end
            continue
        if ch == "`":
            end = text.find("`", i + 1)
            if end == -1:
                note("an unterminated backtick")
            end = n if end == -1 else end + 1
            buf.append(text[i:end])
            expands = True
            started = True
            i = end
            continue
        # `(( … ))` is an arithmetic command, where `<<` is a shift and `>` a
        # comparison. bash commits to arithmetic here (it does not fall back to
        # running the contents), so the whole thing is one opaque word.
        if ch == "(" and not started and text.startswith("((", i):
            end, closed = _balanced(text, i)
            if closed and text[end - 2:end] == "))":
                toks.append(Tok("word", text[i:end], True))
                i = end
                continue
        # `>(…)` / `<(…)` — process substitution, a pipe rather than a file.
        if ch == "(" and toks and toks[-1].kind == "op" and toks[-1].value in ("<", ">", ">>"):
            end, closed = _balanced(text, i)
            if not closed:
                note("an unterminated process substitution")
            toks.append(Tok("word", text[i:end], True))
            i = end
            continue

        op = next((o for o in OPERATORS if text.startswith(o, i)), None)
        if op:
            flush()
            buf, expands, quoted, started = [], False, False, False
            if want[0] is not None:
                want[0] = None
                note("a `<<` with no delimiter word")
            toks.append(Tok("op", op))
            i += len(op)
            if op in ("<<", "<<-"):
                want[0] = op == "<<-"
            elif op == "\n" and pending:
                i = _read_heredocs(text, i, pending, heredocs, note)
                del pending[:]
            continue

        if ch in "$`":
            expands = True
        buf.append(ch)
        started = True
        i += 1

    flush()
    if want[0] is not None:
        note("a `<<` with no delimiter word")
    if pending:
        # A heredoc on the last line has no body at all.
        note("a heredoc with no body")
        if heredocs is not None:
            heredocs.extend("" for _ in pending)
    return toks


# --------------------------------------------------------------------------
# Per-command write-target extraction
# --------------------------------------------------------------------------

# Prefixes that wrap another command without changing what it writes.
WRAPPERS = ("sudo", "env", "command", "time", "nohup", "nice", "stdbuf", "exec", "builtin")

# A wrapper's OWN options, so they are consumed rather than mistaken for the
# command it wraps. Stripping only the wrapper's name leaves its first option
# sitting in argv0's place — `env -i tee yarn.lock` becomes `-i`, which matches
# no write primitive, so a real write is reported as no write at all.
#
# Options deliberately ABSENT are absent on purpose; an unlisted option is
# UNSURE, and for these three that is the only honest answer:
#   sudo -R/--chroot, sudo -D/--chdir, env -C/--chdir  move the frame every
#     relative target is resolved against, so consuming them as ordinary values
#     would resolve the target against the wrong directory and report a
#     confident wrong answer.
#   env -S/--split-string  hides a whole command line inside one argument, so
#     the wrapped command is not a token this parser ever sees.
#   sudo -e/--edit  (sudoedit) writes its operands itself; there is no wrapped
#     command to find.
WRAPPER_OPTS = {
    "sudo": {
        "value": ("-u", "--user", "-g", "--group", "-p", "--prompt",
                  "-C", "--close-from", "-h", "--host", "-r", "--role",
                  "-t", "--type", "-U", "--other-user"),
        "flag": ("-A", "--askpass", "-b", "--background", "-E", "--preserve-env",
                 "-H", "--set-home", "-i", "--login", "-K", "--remove-timestamp",
                 "-k", "--reset-timestamp", "-l", "--list", "-n", "--non-interactive",
                 "-P", "--preserve-groups", "-S", "--stdin", "-s", "--shell",
                 "-v", "--validate", "-N", "--no-update", "-B", "--bell"),
    },
    "env": {
        "value": ("-u", "--unset"),
        "flag": ("-i", "--ignore-environment", "-0", "--null", "-v", "--debug",
                 "--block-signal", "--default-signal", "--ignore-signal",
                 "--list-signal-handling"),
    },
    "nice": {"value": ("-n", "--adjustment"), "flag": ()},
    "stdbuf": {"value": ("-i", "--input", "-o", "--output", "-e", "--error"), "flag": ()},
    "nohup": {"value": (), "flag": ()},
    "command": {"value": (), "flag": ("-p", "-v", "-V")},
    "exec": {"value": ("-a",), "flag": ("-c", "-l")},
    "builtin": {"value": (), "flag": ()},
    "time": {"value": ("-f", "--format", "-o", "--output"),
             "flag": ("-p", "--portability", "-v", "--verbose", "-a", "--append")},
}

# Per-command options, so a value-taking option's VALUE is never counted as an
# operand. Getting this wrong is not cosmetic: in `install -m 0644 src yarn.lock`
# the mode `0644` reads as a second SOURCE, which makes the last operand look
# like a DIRECTORY — so the guard reports writes to `yarn.lock/0644` and
# `yarn.lock/src` and never reports the write to `yarn.lock` itself.
#
#   value     — takes the following word (or an attached `=`/short value)
#   flag      — takes nothing (a bare long form of an optional-argument option
#               belongs here: GNU only accepts its value via `=`)
#   attached  — an optional value glued to the option, never a separate word
#               (`sed -i`, `sed -i.bak`, `perl -0777`)
COMMAND_OPTS = {
    "cp": {
        "value": ("-t", "--target-directory", "-S", "--suffix"),
        "flag": ("-a", "-b", "-d", "-f", "-i", "-l", "-n", "-P", "-p", "-R", "-r",
                 "-s", "-T", "-u", "-v", "-x", "-H", "-L", "-Z",
                 "--archive", "--attributes-only", "--backup", "--copy-contents",
                 "--debug", "--dereference", "--force", "--interactive",
                 "--keep-directory-symlink", "--link", "--no-clobber",
                 "--no-dereference", "--no-preserve", "--no-target-directory",
                 "--one-file-system", "--parents", "--preserve", "--recursive",
                 "--reflink", "--remove-destination", "--sparse",
                 "--strip-trailing-slashes", "--symbolic-link", "--update",
                 "--verbose", "--context"),
    },
    "mv": {
        "value": ("-t", "--target-directory", "-S", "--suffix"),
        "flag": ("-b", "-f", "-i", "-n", "-u", "-v", "-T", "-Z",
                 "--backup", "--context", "--debug", "--exchange", "--force",
                 "--interactive", "--no-clobber", "--no-copy",
                 "--no-target-directory", "--strip-trailing-slashes", "--update",
                 "--verbose"),
    },
    "install": {
        "value": ("-m", "--mode", "-o", "--owner", "-g", "--group",
                  "-t", "--target-directory", "-S", "--suffix", "--strip-program"),
        "flag": ("-b", "-c", "-C", "-d", "-D", "-p", "-s", "-T", "-v", "-Z",
                 "--backup", "--compare", "--context", "--debug", "--directory",
                 "--no-target-directory", "--preserve-context",
                 "--preserve-timestamps", "--strip", "--verbose"),
    },
    "ln": {
        "value": ("-t", "--target-directory", "-S", "--suffix"),
        "flag": ("-b", "-d", "-f", "-F", "-i", "-L", "-n", "-P", "-r", "-s", "-T", "-v",
                 "--backup", "--debug", "--directory", "--force", "--interactive",
                 "--logical", "--no-dereference", "--no-target-directory",
                 "--physical", "--relative", "--symbolic", "--verbose"),
    },
    "rsync": {
        "value": ("-e", "--rsh", "-f", "--filter", "--exclude", "--include",
                  "--exclude-from", "--include-from", "--files-from", "--chmod",
                  "--chown", "--usermap", "--groupmap", "--log-file",
                  "--log-file-format", "--out-format", "--compare-dest",
                  "--copy-dest", "--link-dest", "--partial-dir", "-T", "--temp-dir",
                  "--backup-dir", "--suffix", "--max-size", "--min-size",
                  "--bwlimit", "--timeout", "--contimeout", "--port", "--sockopts",
                  "--password-file", "--address", "-B", "--block-size",
                  "--modify-window", "--checksum-seed", "--protocol", "--iconv",
                  "--skip-compress", "--compress-level", "--rsync-path",
                  "-M", "--remote-option", "--copy-as", "--info", "--debug",
                  "--outbuf", "--write-batch", "--read-batch", "--only-write-batch"),
        "flag": ("-a", "-b", "-c", "-C", "-d", "-D", "-E", "-g", "-h", "-H", "-i",
                 "-I", "-k", "-K", "-l", "-L", "-m", "-n", "-o", "-O", "-p", "-P",
                 "-q", "-r", "-R", "-S", "-t", "-u", "-U", "-v", "-W", "-x", "-X",
                 "-y", "-z", "-A", "-J", "-N", "-G", "-s", "-F",
                 "--archive", "--append", "--append-verify", "--backup",
                 "--checksum", "--compress", "--copy-links", "--copy-unsafe-links",
                 "--cvs-exclude", "--delete", "--delete-after", "--delete-before",
                 "--delete-delay", "--delete-during", "--delete-excluded",
                 "--delete-missing-args", "--devices", "--dirs", "--dry-run",
                 "--existing", "--fuzzy", "--group", "--hard-links",
                 "--human-readable", "--ignore-errors", "--ignore-existing",
                 "--ignore-times", "--inplace", "--itemize-changes",
                 "--keep-dirlinks", "--links", "--list-only", "--mkpath",
                 "--no-implied-dirs", "--no-perms", "--no-whole-file", "--numeric-ids",
                 "--omit-dir-times", "--omit-link-times", "--one-file-system",
                 "--open-noatime", "--owner", "--partial", "--perms", "--preallocate",
                 "--progress", "--prune-empty-dirs", "--quiet", "--recursive",
                 "--relative", "--remove-source-files", "--safe-links", "--sparse",
                 "--specials", "--stats", "--super", "--times", "--update",
                 "--verbose", "--whole-file", "--xattrs"),
    },
    "tee": {"value": (), "flag": ("-a", "-i", "-p", "--append", "--debug",
                                  "--ignore-interrupts", "--output-error")},
    "rm": {"value": (), "flag": ("-f", "-i", "-I", "-r", "-R", "-d", "-v",
                                 "--debug", "--dir", "--force", "--interactive",
                                 "--no-preserve-root", "--one-file-system",
                                 "--preserve-root", "--recursive", "--verbose")},
    "shred": {"value": ("-n", "--iterations", "-s", "--size", "--random-source"),
              "flag": ("-f", "-u", "-v", "-x", "-z", "--exact", "--force",
                       "--remove", "--verbose", "--zero")},
    "touch": {"value": ("-d", "--date", "-r", "--reference", "-t"),
              "flag": ("-a", "-c", "-f", "-h", "-m", "--no-create",
                       "--no-dereference", "--time")},
    "truncate": {"value": ("-s", "--size", "-r", "--reference"),
                 "flag": ("-c", "-o", "--io-blocks", "--no-create")},
    "sponge": {"value": (), "flag": ("-a",)},
    "sed": {
        "value": ("-e", "--expression", "-f", "--file", "-l", "--line-length"),
        "flag": ("-n", "-r", "-E", "-s", "-u", "-z", "--debug", "--follow-symlinks",
                 "--null-data", "--posix", "--quiet", "--regexp-extended",
                 "--sandbox", "--separate", "--silent", "--unbuffered"),
        "attached": ("-i",),
    },
    "awk": {
        "value": ("-v", "--assign", "-f", "--file", "-F", "--field-separator",
                  "-i", "--include", "-l", "--load", "-e", "--source", "-E",
                  "--exec", "-D", "--debug", "-o", "--pretty-print", "-p",
                  "--profile"),
        "flag": ("-c", "-g", "-h", "-M", "-n", "-N", "-P", "-r", "-s", "-S", "-t",
                 "-V", "--characters-as-bytes", "--copyright", "--gen-pot",
                 "--help", "--lint", "--no-optimize", "--non-decimal-data",
                 "--posix", "--re-interval", "--sandbox", "--traditional",
                 "--use-lc-numeric", "--version"),
    },
    "perl": {
        "value": ("-e", "-E", "-I", "-m", "-M"),
        "flag": ("-a", "-c", "-n", "-p", "-s", "-S", "-T", "-u", "-U", "-v", "-V",
                 "-w", "-W", "-X", "-h"),
        "attached": ("-i", "-l", "-0", "-F", "-x", "-d", "-D", "-C"),
    },
}
COMMAND_OPTS["gsed"] = COMMAND_OPTS["sed"]
COMMAND_OPTS["gawk"] = COMMAND_OPTS["awk"]
COMMAND_OPTS["mawk"] = COMMAND_OPTS["nawk"] = COMMAND_OPTS["awk"]

# Commands whose operand LAYOUT decides the answer — the last operand is the
# destination, so an option this parser cannot size makes every operand after it
# a guess. These say UNSURE rather than guessing. For every other command an
# unknown option only risks an extra target, never a missed one.
STRICT_LAYOUT = ("cp", "mv", "install", "rsync", "ln")

# Arbitrary-code evaluators. Handed inline code (or a heredoc) their write
# targets live in a language this parser does not read.
EVALUATORS = (
    "eval", "bash", "sh", "zsh", "dash", "ksh",
    "python", "python2", "python3", "node", "deno", "bun",
    "perl", "ruby", "php", "osascript", "tclsh",
)
INLINE_CODE_FLAGS = ("-c", "-e", "-r", "--eval", "--command", "-E")

# Commands that dispatch other commands built at runtime.
DISPATCHERS = ("xargs", "parallel", "watch", "timeout")

# `patch` and `git apply`/`git am` are no longer opaque: their write targets are
# read out of the patch itself (see "Patches and git" below), and a patch that
# cannot be read is still UNSURE.

# Directory-tree writers, judged by the DESTINATION DIRECTORY they fill: a
# protected path anywhere inside it is a protected path written (TREE records).
TARS = ("tar", "gtar", "bsdtar")
SEVENZIPS = ("7z", "7za", "7zz", "7zr")
AWKS = ("awk", "gawk", "mawk", "nawk")
ED_EDITORS = ("ed", "red")
VI_EDITORS = ("ex", "vi", "vim", "nvim")
COMPRESSORS = {
    "gzip": ".gz", "gunzip": ".gz", "pigz": ".gz", "unpigz": ".gz",
    "bzip2": ".bz2", "bunzip2": ".bz2", "xz": ".xz", "unxz": ".xz",
    "lzma": ".lzma", "unlzma": ".lzma", "lzip": ".lz", "zstd": ".zst", "unzstd": ".zst",
    "lz4": ".lz4", "unlz4": ".lz4", "brotli": ".br", "compress": ".Z", "uncompress": ".Z",
}
# These keep their input unless told otherwise; the rest replace it.
KEEPS_INPUT = ("zstd", "unzstd", "lz4", "unlz4", "brotli")
COMPRESSED_SUFFIXES = (".tgz", ".taz", ".tbz2", ".tbz", ".txz", ".gz", ".z", ".Z", ".bz2",
                       ".xz", ".lzma", ".lz", ".zst", ".lz4", ".br")
URL_SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*://")

# An awk program writes when a print/printf redirects or pipes, or when it runs a
# command. Matched with its string literals blanked, so `print $1" | "$2` is a
# print, not a pipe. (An unparenthesised `>` inside a print IS a redirection in
# awk — `print length($2)>100 ? "a" : "b"` writes a file — so that one stays.)
AWK_WRITES = re.compile(r"\b(?:print|printf)\b[^;{}\n]*?(?:>|\|)|\|\s*getline|\bsystem\s*\(")
AWK_STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')


def _awk_writes(program):
    return bool(AWK_WRITES.search(AWK_STRING.sub('""', program)))
# An ed command that names the file it writes or makes the default (w, W, wq, f, e, E).
ED_FILE_CMD = re.compile(
    r"^[\s0-9,.$;'+\-]*(?:/(?:[^/\\]|\\.)*/|\?(?:[^?\\]|\\.)*\?)?[\s0-9,.$;'+\-]*"
    r"(?:wq|[wWfeE])\s+(\S.*?)\s*$")
HOME_VAR = re.compile(r"^(?:\$HOME|\$\{HOME\})(?=/|$)")

EVAL_WHY = ("runs code supplied to it rather than named on the command line; its writes "
            "are not visible to a shell parse")
PROGRAM_WHY = ("runs a program whose output redirections or commands this parse does not "
               "follow (an awk `print >`, a sed `w` or `e`, an editor command)")

INPLACE_LONG = ("--in-place", "--inplace")


def _is_flag(word):
    return word.startswith("-") and word != "-"


def _consume_option(word, spec):
    """How many further WORDS this option eats: 0, 1, or None for "unknown".

    None is not a synonym for zero. An option whose size we cannot determine
    shifts every operand after it, so the caller decides whether that is
    survivable (an extra target) or fatal (the destination moves), rather than
    this function quietly assuming the harmless case.
    """
    value = spec.get("value", ())
    flag = spec.get("flag", ())
    attached = spec.get("attached", ())

    if word.startswith("--"):
        name = word.split("=", 1)[0]
        if "=" in word:
            # An optional-argument long option only ever takes it as `=VALUE`.
            return 0 if name in value or name in flag else None
        if name in value:
            return 1
        if name in flag:
            return 0
        return None

    # A short cluster: `-av`, `-m0644`, `-t dir`, `-i.bak`.
    body = word[1:]
    for pos, ch in enumerate(body):
        short = "-" + ch
        if short in attached:
            return 0        # the rest of the word is its value, if it has one
        if short in value:
            # `-m0644` carries its value; a trailing `-m` takes the next word.
            return 0 if pos + 1 < len(body) else 1
        if short in flag:
            continue
        return None
    return 0


def _split_operands(words, cmd=None):
    """(operands, unresolvable_reason) — non-flag arguments, stopping at `--`.

    With no entry in COMMAND_OPTS this is the old behaviour: drop anything that
    looks like a flag, keep everything else. With an entry, a value-taking
    option's value is dropped too — it is not an operand, and counting it as one
    is what let `install -m 0644 src yarn.lock` write the lockfile unchecked.
    """
    spec = COMMAND_OPTS.get(cmd) if cmd else None
    out = []
    i = 0
    seen_ddash = False
    while i < len(words):
        w = words[i]
        if seen_ddash or not _is_flag(w.value):
            out.append(w)
            i += 1
            continue
        if w.value == "--":
            seen_ddash = True
            i += 1
            continue
        eats = _consume_option(w.value, spec) if spec else 0
        if eats is None:
            if cmd in STRICT_LAYOUT:
                return [], ("`%s` is passed the option `%s`, which this parse cannot "
                            "size; the operands after it may not be the ones naming "
                            "the destination" % (cmd, w.value))
            eats = 0
        i += 1 + eats
    return out, None


def _operands(words, cmd=None):
    """Non-flag arguments, stopping at `--`."""
    return _split_operands(words, cmd)[0]


def _has_inplace(words):
    for w in words:
        v = w.value
        if v in INPLACE_LONG or v.startswith("--in-place=") or v.startswith("--inplace="):
            return True
        # `-i`, `-i.bak`, `-ri`, `-n -i` — a short cluster containing `i`.
        if v.startswith("-") and not v.startswith("--"):
            body = v[1:].split(".", 1)[0]
            if "i" in body and body.replace("i", "").isalpha() or body == "i":
                return True
    return False


def _flag_value(words, names):
    """Value of `--name V` / `--name=V` / `-nV`, or None."""
    for idx, w in enumerate(words):
        v = w.value
        for name in names:
            if v == name:
                return words[idx + 1] if idx + 1 < len(words) else None
            if v.startswith(name + "="):
                return Tok("word", v[len(name) + 1:], w.expands, w.quoted)
            if len(name) == 2 and name.startswith("-") and v.startswith(name) and len(v) > 2:
                return Tok("word", v[2:], w.expands, w.quoted)
    return None


def _script_then_files(words, script_flags, cmd=None):
    """sed/awk grammar: the first operand is the program unless -e/-f gave it."""
    ops = _operands(words, cmd)
    gave_script = any(
        w.value in script_flags or any(w.value.startswith(f + "=") for f in script_flags)
        for w in words
    )
    return ops if gave_script else ops[1:]


# --------------------------------------------------------------------------
# Same-command literal assignments (issue #336)
# --------------------------------------------------------------------------
# `S=/abs/scratch; cp a "$S/b"` names its target as plainly as
# `cp a /abs/scratch/b` does: the value is a literal in the SAME command
# string. Reporting that write as UNSURE answered "could not determine" to a
# question the text answers, and it was wrong in both directions at once — the
# advisory fired on every scratch write of a long session (about sixty times,
# measured), and a protected path spelled through the variable
# (`S=/tmp/x; cp a "$S/package-lock.json"`) walked past the generated-file
# rules, since an advisory is still an allow.
#
# So analyze_command keeps ASSIGNS, NAME -> literal value, for the assignments
# seen so far in the command, and _static_value substitutes `$NAME`/`${NAME}`
# from it. Resolving only ever turns an advisory into a checked path, and a
# checked path into a block; what the table cannot answer is UNSURE exactly as
# before. The table is deliberately narrow:
#   - only a value this parser reads as a literal: a word with no expansion in
#     it once the tokenizer has removed its quotes, or one whose only expansion
#     is `$HOME` or an earlier entry of the table (the same two things
#     _static_value already resolved);
#   - only an assignment that reaches the SHELL: a bare `NAME=value` statement,
#     or `export`/`declare`/`typeset`/`readonly NAME=value`, run
#     unconditionally — not in a pipeline component or a background job (a
#     subshell, where it dies), not after `&&`/`||` or under
#     `if`/`then`/`else`/`while`/`do` (it may never run), and never the
#     `NAME=value cmd` prefix form, which is the command's environment, not the
#     shell's. A `( … )` group's assignments are restored at the `)`, like cwd;
#   - anything that could change the variable afterwards forgets it rather
#     than guessing: a non-literal reassignment, `+=`, an array, `unset`,
#     `read`, `for`/`select NAME`, `local`, `printf -v`, `mapfile`/`readarray`,
#     `let` and `(( ))` arithmetic, a `${NAME=…}`/`${NAME:=…}` expansion; `eval`,
#     `source` and `.` can set anything, so they forget everything;
#   - an unquoted use whose value would word-split is not substituted, and one
#     that would glob is reported as a glob by _record_targets as before.
ASSIGNS = {}
_NAME = r"[A-Za-z_][A-Za-z0-9_]*"
ASSIGN_WORD = re.compile(r"^(%s)(\+?=)(.*)$" % _NAME, re.S)
VAR_REF = re.compile(r"\$(?:\{(%s)\}|(%s))" % (_NAME, _NAME))
PARAM_ASSIGN = re.compile(r"\$\{(%s):?=" % _NAME)
# `x=1`, `x+=1`, `x<<=1`, `x++`, `--x` inside `(( ))`, `$(( ))` or `let`; never `==`.
ARITH_MUTATE = re.compile(
    r"(?<![A-Za-z0-9_$])(%s)\s*(?:(?:[-+*/%%&|^]|<<|>>)?=(?!=)|\+\+|--)|(?:\+\+|--)\s*(%s)"
    % (_NAME, _NAME))
CONDITIONAL_KEYWORDS = ("if", "then", "elif", "else", "while", "until", "do")
NEUTRAL_KEYWORDS = ("{", "}", "!", "time")
FORGETS_ALL = ("eval", "source", ".")


def _assign_value(name, op, value, tok):
    """Record one `NAME=value` that reaches the shell; forget what cannot be read."""
    if op == "+=":
        ASSIGNS.pop(name, None)
        return
    lit = _static_value(Tok("word", value, tok.expands, tok.quoted))
    if lit is None:
        ASSIGNS.pop(name, None)
    else:
        ASSIGNS[name] = lit


def _forget_names(text):
    for m in ARITH_MUTATE.finditer(text):
        ASSIGNS.pop(m.group(1) or m.group(2), None)


def _track_assignments(words, piped_in, terminator, conditional):
    """Update ASSIGNS from one segment's words, before its writes are judged."""
    for w in words:
        # `${S=x}` assigns; `(( S=1 ))` and `$(( S++ ))` mutate.
        for m in PARAM_ASSIGN.finditer(w.value):
            ASSIGNS.pop(m.group(1), None)
        if w.value.startswith("((") or "$((" in w.value:
            _forget_names(w.value)
    if piped_in or terminator in ("|", "&"):
        return      # a subshell: nothing here reaches the parent shell
    rest = list(words)
    while rest and rest[0].value in NEUTRAL_KEYWORDS:
        rest.pop(0)
    if rest and rest[0].value in CONDITIONAL_KEYWORDS:
        conditional = True
        rest.pop(0)
    leading = []
    while rest and ASSIGN_WORD.match(rest[0].value):
        leading.append(rest.pop(0))
    if not rest:
        for tok in leading:
            name, op, value = ASSIGN_WORD.match(tok.value).groups()
            # `S=(a b)`: the tokenizer stops the word at the `(`, so the value
            # reads as empty; an array is not a path.
            if conditional or (terminator == "(" and tok is leading[-1] and value == ""):
                ASSIGNS.pop(name, None)
            else:
                _assign_value(name, op, value, tok)
        return
    # `NAME=value cmd`: the command's environment, not the shell's. The command
    # itself may still set or unset variables.
    while rest and os.path.basename(rest[0].value) in WRAPPERS:
        rest.pop(0)
        while rest and (rest[0].value.startswith("-") or ASSIGN_WORD.match(rest[0].value)):
            rest.pop(0)
    if not rest:
        return
    base = os.path.basename(rest[0].value)
    ops = [w for w in rest[1:] if not w.value.startswith("-")]
    if base in FORGETS_ALL:
        ASSIGNS.clear()
    elif base in ("export", "declare", "typeset", "readonly", "local"):
        for w in ops:
            m = ASSIGN_WORD.match(w.value)
            if m and not conditional:
                _assign_value(m.group(1), m.group(2), m.group(3), w)
            elif m:
                ASSIGNS.pop(m.group(1), None)
            elif base != "export" or conditional:
                ASSIGNS.pop(w.value, None)
    elif base in ("unset", "read", "mapfile", "readarray"):
        for w in ops:
            ASSIGNS.pop(w.value.split("[", 1)[0], None)
    elif base in ("for", "select") and rest[1:]:
        ASSIGNS.pop(rest[1].value, None)
        _forget_names(rest[1].value)
    elif base == "printf":
        for i, w in enumerate(rest[1:-1]):
            if w.value == "-v":
                ASSIGNS.pop(rest[i + 2].value, None)
    elif base == "let":
        for w in ops:
            _forget_names(w.value)


def _substitute_assigns(value, quoted):
    """`value` with every `$NAME`/`${NAME}` the table knows replaced; None if it would word-split."""
    def sub(m):
        return ASSIGNS.get(m.group(1) or m.group(2), m.group(0))
    out = VAR_REF.sub(sub, value)
    if out != value and not quoted and any(c.isspace() for c in out):
        return None
    return out


def _static_value(tok):
    """The literal text of a word, or None when it depends on a runtime expansion.

    Two expansions are resolved: `$HOME`/`${HOME}` at the start — the same
    session HOME `~` already expands to, and both are protected homes (D3) — and
    a variable the same command assigned a literal to (ASSIGNS, above).
    """
    v = tok.value
    if not (tok.expands or "$" in v or "`" in v):
        return v
    if tok.expands and ASSIGNS and "$" in v:
        sub = _substitute_assigns(v, tok.quoted)
        if sub is None:
            return None
        if sub != v:
            v = sub
            if "$" not in v and "`" not in v and "\\" not in v:
                return v
    m = HOME_VAR.match(v)
    home = os.environ.get("HOME")
    rest = v[m.end():] if m else ""
    if m and home and "$" not in rest and "`" not in rest and "\\" not in rest:
        return home + rest
    return None


def _resolve(value, cwd):
    """An operand as an absolute normalised path; None when it is relative and cwd is unknown."""
    path = os.path.expanduser(value)
    if not os.path.isabs(path):
        if not cwd:
            return None
        path = os.path.join(cwd, path)
    return os.path.normpath(path)


def _isdir(tok, cwd):
    value = _static_value(tok)
    path = _resolve(value, cwd) if value is not None else None
    return bool(path) and os.path.isdir(path)


def _word(value, *parts):
    """A synthetic word token, expanding if any token it was built from did."""
    return Tok("word", value, any(p.expands for p in parts if p is not None))


def _destinations(words, cmd=None, cwd=None):
    """(targets, unsure) — the last operand, expanded over sources if a dir.

    cp/mv/install/rsync/ln. The destination is decided by POSITION, so this is
    the family where an operand list off by one hides the real write. A source
    with a trailing slash (`cp -R src/ dest`) has no basename: its target is the
    destination directory itself, which is what BSD cp and rsync fill.
    """
    explicit_dir = _flag_value(words, ("-t", "--target-directory"))
    ops, unsure = _split_operands(words, cmd)
    if unsure:
        return [], unsure
    if explicit_dir is not None:
        return [_word(os.path.join(explicit_dir.value, os.path.basename(s.value)), explicit_dir, s)
                for s in ops], None
    if len(ops) < 2:
        return [], None
    dest, sources = ops[-1], ops[:-1]
    # `-T` / --no-target-directory: the destination IS the target, even when it
    # is an existing directory (`cp -rT src ~/.claude` fills ~/.claude itself).
    no_tdir = cmd != "rsync" and any(
        w.value == "--no-target-directory"
        or (w.value.startswith("-") and not w.value.startswith("--") and "T" in w.value[1:])
        for w in words)
    if not no_tdir and (len(sources) > 1 or dest.value.endswith("/") or _isdir(dest, cwd)):
        return [_word(os.path.join(dest.value, os.path.basename(s.value)), dest, s)
                for s in sources], None
    return [dest], None


def _walk_options(words, short_value="", long_value=()):
    """[(name, value-token or None)] for a getopt-style argument list; name None is an operand.

    A short cluster `-abc` yields -a, -b, -c; a letter in `short_value` takes
    the rest of its cluster, else the next word. A long option in `long_value`
    takes `=V` or the next word.
    """
    out = []
    i = 0
    ddash = False
    while i < len(words):
        w = words[i]
        v = w.value
        if ddash or not _is_flag(v):
            out.append((None, w))
            i += 1
            continue
        if v == "--":
            ddash = True
            i += 1
            continue
        if v.startswith("--"):
            name, eq, val = v.partition("=")
            if eq:
                out.append((name, Tok("word", val, w.expands, w.quoted)))
            elif name in long_value and i + 1 < len(words):
                out.append((name, words[i + 1]))
                i += 1
            else:
                out.append((name, None))
            i += 1
            continue
        body = v[1:]
        for k, c in enumerate(body):
            if c in short_value:
                rest = body[k + 1:]
                if rest:
                    out.append(("-" + c, Tok("word", rest, w.expands, w.quoted)))
                elif i + 1 < len(words):
                    out.append(("-" + c, words[i + 1]))
                    i += 1
                else:
                    out.append(("-" + c, None))
                break
            out.append(("-" + c, None))
        i += 1
    return out


def _url_names(url):
    """The local names a downloader gives `url`: its last path segment, with and without the query."""
    if any(c in url for c in "{}[]"):
        return []           # a curl URL glob: the names are built at runtime
    rest = URL_SCHEME.sub("", url, count=1)
    path = rest.split("/", 1)[1] if "/" in rest else ""
    path = path.split("#", 1)[0]
    names = []
    for p in (path.split("?", 1)[0], path):
        seg = p.rsplit("/", 1)[-1]
        if seg and seg not in (".", "..") and seg not in names:
            names.append(seg)
    return names


CURL_SHORT_VALUE = "AbcCdDeEFHKmoPQrtTuUwxXyYz"
CURL_LONG_VALUE = (
    "--output", "--output-dir", "--dump-header", "--cookie-jar", "--trace", "--trace-ascii",
    "--stderr", "--etag-save", "--etag-compare", "--hsts", "--alt-svc", "--libcurl", "--config",
    "--header", "--data", "--data-raw", "--data-binary", "--data-urlencode", "--data-ascii",
    "--json", "--user", "--user-agent", "--referer", "--request", "--proxy", "--cookie", "--form",
    "--form-string", "--upload-file", "--max-time", "--connect-timeout", "--retry", "--retry-delay",
    "--retry-max-time", "--write-out", "--url", "--range", "--cert", "--key", "--cacert", "--capath",
    "--resolve", "--connect-to", "--interface", "--limit-rate", "--max-filesize", "--oauth2-bearer",
    "--proto", "--proto-redir", "--variable", "--speed-time", "--speed-limit", "--time-cond",
    "--max-redirs", "--keepalive-time", "--proxy-user", "--netrc-file", "--aws-sigv4", "--dns-servers",
)
# Options whose value is a file curl writes (relative to the cwd, not --output-dir).
CURL_FILE_OPTS = ("-D", "--dump-header", "-c", "--cookie-jar", "--trace", "--trace-ascii",
                  "--stderr", "--etag-save", "--hsts", "--alt-svc", "--libcurl")


def _curl_targets(words):
    outdir = None
    outputs, files, urls = [], [], []
    remote = header_name = False
    unsure = None
    for name, val in _walk_options(words, CURL_SHORT_VALUE, CURL_LONG_VALUE):
        if name is None or name == "--url":
            if val is not None:
                urls.append(val)
        elif name in ("-o", "--output") and val is not None:
            outputs.append(val)
        elif name == "--output-dir" and val is not None:
            outdir = val
        elif name in ("-O", "--remote-name", "--remote-name-all"):
            remote = True
        elif name in ("-J", "--remote-header-name"):
            header_name = True
        elif name in CURL_FILE_OPTS and val is not None:
            files.append(val)
        elif name in ("-K", "--config"):
            unsure = "reads curl options from a config file, which can name an output file"

    def under(name, *parts):
        if outdir is None or os.path.isabs(os.path.expanduser(name)):
            return _word(name, *parts)
        return _word(outdir.value.rstrip("/") + "/" + name, outdir, *parts)

    out = [(under(o.value, o), "TARGET") for o in outputs if o.value != "-"]
    if remote or header_name:
        names = [n for u in urls for n in _url_names(u.value)]
        if header_name or not urls or any(not _url_names(u.value) for u in urls):
            # The server, or a runtime glob, picks the name: the whole directory is in reach.
            out.append((outdir if outdir is not None else Tok("word", "."), "TREE"))
        out.extend((under(n, *urls), "TARGET") for n in names)
    out.extend((f, "TARGET") for f in files if f.value != "-")
    return out, unsure


WGET_SHORT_VALUE = "eoaiBtOTwQlPDARIXU"
WGET_LONG_VALUE = (
    "--output-document", "--output-file", "--append-output", "--directory-prefix", "--input-file",
    "--execute", "--save-cookies", "--load-cookies", "--hsts-file", "--rejected-log", "--warc-file",
    "--tries", "--timeout", "--wait", "--quota", "--level", "--domains", "--accept", "--reject",
    "--include-directories", "--exclude-directories", "--user-agent", "--header", "--post-data",
    "--post-file", "--base", "--user", "--password", "--referer", "--limit-rate", "--cut-dirs",
)


def _wget_targets(words):
    # `-nc`, `-nd`, `-nH`, `-np`, `-nv`: -n takes the rest of its cluster.
    words = [w for w in words if not re.match(r"^-n[A-Za-z]+$", w.value)]
    document = prefix = None
    logs, urls = [], []
    tree = False
    unsure = None
    for name, val in _walk_options(words, WGET_SHORT_VALUE, WGET_LONG_VALUE):
        if name is None:
            urls.append(val)
        elif name in ("-O", "--output-document") and val is not None:
            document = val
        elif name in ("-P", "--directory-prefix") and val is not None:
            prefix = val
        elif name in ("-o", "--output-file", "-a", "--append-output", "--save-cookies",
                      "--hsts-file", "--rejected-log", "--warc-file") and val is not None:
            logs.append(val)
        elif name in ("-r", "--recursive", "-m", "--mirror", "-p", "--page-requisites",
                      "-x", "--force-directories", "-i", "--input-file", "--content-disposition"):
            tree = True
        elif name in ("-e", "--execute"):
            unsure = "runs a wgetrc command, which can name an output file"
    out = [(f, "TARGET") for f in logs if f.value != "-"]
    if document is not None:
        if document.value != "-":
            out.append((document, "TARGET"))
        return out, unsure
    base = prefix if prefix is not None else Tok("word", ".")
    if tree or not urls:
        out.append((base, "TREE"))
        return out, unsure
    for u in urls:
        names = _url_names(u.value) or ["index.html"]
        out.extend((_word(base.value.rstrip("/") + "/" + n, base, u), "TARGET") for n in names)
    return out, unsure


TAR_SHORT_VALUE = "bCfFgHIKLNsTVX"
TAR_LONG_VALUE = (
    "--file", "--directory", "--exclude", "--exclude-from", "--files-from", "--transform",
    "--xform", "--owner", "--group", "--mode", "--mtime", "--format", "--blocking-factor",
    "--record-size", "--newer", "--after-date", "--newer-mtime", "--label", "--suffix",
    "--strip-components", "--to-command", "--use-compress-program", "--rsh-command",
    "--info-script", "--new-volume-script", "--checkpoint-action", "--listed-incremental",
    "--volno-file", "--index-file", "--tape-length", "--starting-file", "--options",
)


def _tar_targets(words):
    entries = []
    rest = list(words)
    # Old-style `tar xzf archive -C dir`: a bundle whose value letters take the
    # following words in order.
    if rest and not rest[0].value.startswith("-") and rest[0].value.isalpha():
        bundle = rest.pop(0).value
        for c in bundle:
            entries.append(("-" + c, rest.pop(0) if (c in TAR_SHORT_VALUE and rest) else None))
    entries += _walk_options(rest, TAR_SHORT_VALUE, TAR_LONG_VALUE)
    mode = None
    files, dirs = [], []
    absolute = to_stdout = runs = False
    for name, val in entries:
        if name in ("-x", "--extract", "--get"):
            mode = "x"
        elif name in ("-c", "--create", "-r", "--append", "-u", "--update", "-A",
                      "--catenate", "--concatenate", "--delete"):
            mode = "c"          # creates or modifies the archive named by -f
        elif name in ("-f", "--file") and val is not None:
            files.append(val)
        elif name in ("-C", "--directory") and val is not None:
            dirs.append(val)
        elif name in ("-O", "--to-stdout"):
            to_stdout = True
        elif name in ("-P", "--absolute-names"):
            absolute = True
        elif name in ("--to-command", "--use-compress-program", "-I", "-F", "--rsh-command",
                      "--info-script", "--new-volume-script", "--checkpoint-action"):
            runs = True
    out = []
    unsure = "runs a program named in its options" if runs else None
    if mode == "x" and not to_stdout:
        if absolute:
            out.append((Tok("word", "/"), "TREE"))
        # GNU applies each -C relative to the one before it; judge both readings.
        cur = None
        for d in dirs:
            out.append((d, "TREE"))
            if cur is not None and not os.path.isabs(os.path.expanduser(d.value)):
                cur = _word(cur.value.rstrip("/") + "/" + d.value, cur, d)
                out.append((cur, "TREE"))
            else:
                cur = d
        if not dirs:
            out.append((Tok("word", "."), "TREE"))
    elif mode == "c":
        out.extend((f, "TARGET") for f in files if f.value != "-")
    return out, unsure


def _unzip_targets(words):
    dest = None
    listing = False
    i = 0
    while i < len(words):
        w = words[i]
        v = w.value
        if v == "-d" and i + 1 < len(words):
            dest = words[i + 1]
            i += 2
            continue
        if v.startswith("-d") and len(v) > 2:
            dest = Tok("word", v[2:], w.expands, w.quoted)
        elif v == "-P":
            i += 2          # a password, not a member
            continue
        elif v.startswith("-") and not v.startswith("--") and set(v[1:]) & set("lptvzZc"):
            listing = True  # list, test, pipe or print to stdout: nothing extracted
        i += 1
    if listing:
        return [], None
    return [(dest if dest is not None else Tok("word", "."), "TREE")], None


def _sevenzip_targets(words):
    ops = [w for w in words if not w.value.startswith("-")]
    if not ops:
        return [], None
    cmd = ops[0].value
    if cmd in ("x", "e"):
        if any(w.value == "-so" for w in words):
            return [], None
        outdir = next((Tok("word", w.value[2:], w.expands) for w in words
                       if w.value.startswith("-o") and len(w.value) > 2), None)
        return [(outdir if outdir is not None else Tok("word", "."), "TREE")], None
    if cmd in ("a", "u", "d", "rn") and len(ops) > 1:
        return [(ops[1], "TARGET")], None
    return [], None


def _cpio_targets(words):
    entries = _walk_options(words, "CDEFHIMORW", ("--directory", "--file", "--format", "--owner",
                                                   "--pattern-file", "--message", "--block-size"))
    names = set(n for n, _ in entries if n)
    ops = [v for n, v in entries if n is None]
    out = []
    unsure = None
    if names & set(("-i", "--extract")) and not names & set(("-t", "--list")):
        d = next((v for n, v in entries if n in ("-D", "--directory") and v is not None), None)
        out.append((d if d is not None else Tok("word", "."), "TREE"))
    elif names & set(("-p", "--pass-through")):
        out.extend((o, "TREE") for o in ops[:1])
        if names & set(("-l", "--link")):
            unsure = "links files named on standard input into place"
    elif names & set(("-o", "--create")):
        out.extend((v, "TARGET") for n, v in entries
                   if n in ("-O", "-F", "--file") and v is not None and v.value != "-")
    return out, unsure


PAX_SHORT_VALUE = "bfopsxBEGTU"


def _pax_targets(words):
    entries = _walk_options(words, PAX_SHORT_VALUE)
    names = set(n for n, _ in entries if n)
    ops = [v for n, v in entries if n is None]
    if "-r" in names and "-w" in names:
        return ([(ops[-1], "TREE")] if ops else []), None
    if "-r" in names:
        return [(Tok("word", "."), "TREE")], None
    if "-w" in names:
        return [(v, "TARGET") for n, v in entries
                if n == "-f" and v is not None and v.value != "-"], None
    return [], None


def _compress_targets(base, words):
    entries = _walk_options(words, "So", ("--suffix", "--output"))
    names = set(n for n, _ in entries if n)
    ops = [v for n, v in entries if n is None and v.value != "-"]
    decompress = (base.startswith("un") or base in ("gunzip", "bunzip2")
                  or bool(names & set(("-d", "--decompress", "--uncompress"))))
    to_stdout = bool(names & set(("-c", "--stdout", "--to-stdout")))
    keep = bool(names & set(("-k", "--keep"))) or (base in KEEPS_INPUT and "--rm" not in names)
    recursive = bool(names & set(("-r", "--recursive")))
    suffix = next((v.value for n, v in entries if n in ("-S", "--suffix") and v is not None),
                  COMPRESSORS[base])
    output = next((v for n, v in entries if n in ("-o", "--output") and v is not None), None)
    out = []
    if output is not None and output.value != "-":
        out.append((output, "TARGET"))
    if base in ("lz4", "unlz4") and len(ops) == 2 and output is None:
        out.append((ops[1], "TARGET"))      # lz4 IN OUT
        ops = ops[:1]
    if to_stdout:
        return out, None
    for op in ops:
        if recursive:
            out.append((op, "TREE"))
            continue
        if not keep:
            out.append((op, "DELETE"))
        if output is not None:
            continue
        if decompress:
            v = op.value
            for suf in (suffix,) + COMPRESSED_SUFFIXES:
                if v.endswith(suf) and len(v) > len(suf):
                    tail = ".tar" if suf in (".tgz", ".taz", ".tbz2", ".tbz", ".txz") else ""
                    out.append((_word(v[:-len(suf)] + tail, op), "TARGET"))
                    break
        else:
            out.append((_word(op.value + suffix, op), "TARGET"))
    return out, None


def _awk_programs(words):
    progs = []
    given = False
    for idx, w in enumerate(words):
        v = w.value
        for f in ("-e", "--source"):
            if v == f and idx + 1 < len(words):
                progs.append(words[idx + 1].value)
                given = True
            elif v.startswith(f + "="):
                progs.append(v[len(f) + 1:])
                given = True
        if v in ("-f", "--file") or v.startswith("--file="):
            given = True
    if not given:
        ops = _operands(words, "awk")
        if ops:
            progs.append(ops[0].value)
    return progs


def _sed_scripts(words):
    scripts = []
    given = False
    for idx, w in enumerate(words):
        v = w.value
        if v in ("-e", "--expression") and idx + 1 < len(words):
            scripts.append(words[idx + 1].value)
            given = True
        elif v.startswith("--expression="):
            scripts.append(v[len("--expression="):])
            given = True
        elif v in ("-f", "--file") or v.startswith("--file="):
            given = True
    if not given:
        ops = _operands(words, "sed")
        if ops:
            scripts.append(ops[0].value)
    return scripts


def _sed_writes(script):
    """True when a sed script writes a file (`w`, `W`, `s///w`) or runs one (`e`, `s///e`)."""
    i = 0
    n = len(script)

    def past(i, delim):
        while i < n:
            c = script[i]
            if c == "\\":
                i += 2
                continue
            if c == delim:
                return i + 1
            i += 1
        return n

    def to_eol(i):
        j = script.find("\n", i)
        return n if j == -1 else j

    while i < n:
        c = script[i]
        if c in " \t\n;{}!" or c.isdigit() or c in "$+~,":
            i += 1
        elif c == "/":
            i = past(i + 1, "/")
            while i < n and script[i] in "IM":
                i += 1
        elif c == "\\" and i + 1 < n:
            i = past(i + 2, script[i + 1])
        elif c in "wWe":
            return True
        elif c in "sy":
            if i + 1 >= n:
                return False
            d = script[i + 1]
            i = past(past(i + 2, d), d)
            if c == "s":
                while i < n and script[i] not in ";\n}":
                    if script[i] in "we":
                        return True
                    i += 1
        elif c in "aicrR#":
            i = to_eol(i)               # text or a file name, to the end of the line
        elif c in "btT:":
            j = i + 1
            while j < n and script[j] not in ";\n":
                j += 1
            i = j
        else:
            i += 1
    return False


def _ed_targets(words, fed_code, heredoc):
    out = [(w, "TARGET") for w in _operands(words) if not w.value.startswith("!")]
    unsure = None
    if heredoc is not None:
        for line in heredoc.splitlines():
            if "!" in line:
                unsure = PROGRAM_WHY
            m = ED_FILE_CMD.match(line)
            if m and not m.group(1).startswith("!"):
                out.append((Tok("word", m.group(1)), "TARGET"))
    elif fed_code:
        unsure = PROGRAM_WHY
    return out, unsure


def _vi_targets(words, fed_code):
    out = []
    unsure = PROGRAM_WHY if fed_code else None
    i = 0
    while i < len(words):
        v = words[i].value
        if v in ("-c", "--cmd", "-S"):
            unsure = PROGRAM_WHY
            i += 2
            continue
        if v in ("-u", "-U", "-i", "-T", "-t", "-q", "--startuptime", "--listen", "--server"):
            i += 2
            continue
        if v in ("-s", "-w", "-W"):
            if v == "-s":
                unsure = PROGRAM_WHY
            if i + 1 < len(words):
                out.append((words[i + 1], "TARGET"))
            i += 2
            continue
        if v.startswith("+"):
            unsure = PROGRAM_WHY
        elif not v.startswith("-"):
            out.append((words[i], "TARGET"))
        i += 1
    return out, unsure


def _split_targets(base, words):
    """PREFIX records: split/csplit write `<prefix><suffix>` files beside the prefix."""
    unsure = None
    if base == "split":
        entries = _walk_options(words, "abClnpt", (
            "--suffix-length", "--bytes", "--line-bytes", "--lines", "--number",
            "--separator", "--additional-suffix", "--filter"))
        if any(n == "--filter" for n, _ in entries):
            unsure = "runs a command per chunk"
        ops = [v for n, v in entries if n is None]
        prefix = ops[1] if len(ops) >= 2 else Tok("word", "x")
    else:
        entries = _walk_options(words, "fbn", ("--prefix", "--suffix-format", "--digits"))
        prefix = next((v for n, v in entries if n in ("-f", "--prefix") and v is not None),
                      Tok("word", "xx"))
        fmt = next((v for n, v in entries if n in ("-b", "--suffix-format") and v is not None), None)
        if fmt is not None and "/" in fmt.value:
            unsure = "names its output files with a suffix format that reaches another directory"
    return [(prefix, "PREFIX")], unsure


def segment_targets(argv0, words, fed_code, cwd=None, heredoc=None):
    """([(target token, kind)], unsure_reason) for one already-unwrapped command segment.

    `fed_code` is true when the segment could be receiving a program rather than
    only data — a heredoc, an inline `-c`/`-e`, a `<` redirect, or the receiving
    end of a pipe. Piping into an interpreter is how you hand it code, so an
    evaluator on the right of a `|` is exactly as opaque as `python3 -c`.

    kind is TARGET (a file written), DELETE (a file removed), TREE (a path that
    may receive a whole directory tree: a copy, a move, an extraction) or PREFIX
    (the stem split/csplit name their output files from).
    """
    base = os.path.basename(argv0)

    def T(toks, kind="TARGET"):
        return [(t, kind) for t in toks]

    if base == "eval" or (base in EVALUATORS and (
            fed_code or any(w.value in INLINE_CODE_FLAGS for w in words))):
        return [], EVAL_WHY
    if base in DISPATCHERS:
        return [], "builds and runs another command at runtime"
    if base == "find" and any(
            w.value in ("-exec", "-execdir", "-delete", "-fprint", "-fprintf") for w in words):
        return [], "runs an action per match; the affected paths are decided at runtime"

    if base in ("rm", "unlink", "shred"):
        return T(_operands(words, base), "DELETE"), None
    if base == "tee":
        return T(_operands(words, base)), None
    if base in ("sed", "gsed"):
        files = (_script_then_files(words, ("-e", "--expression", "-f", "--file"), base)
                 if _has_inplace(words) else [])
        return T(files), (PROGRAM_WHY if any(_sed_writes(s) for s in _sed_scripts(words)) else None)
    if base == "perl" and _has_inplace(words):
        # `-e`/`-E` take the program as their value (including inside a cluster,
        # `-pe 'CODE'`), so the operands left are the files it rewrites.
        return T(_operands(words, base)), None
    if base in AWKS:
        unsure = PROGRAM_WHY if any(_awk_writes(p) for p in _awk_programs(words)) else None
        if not (_has_inplace(words) and any(w.value == "inplace" for w in words)):
            return [], unsure
        # gawk spells it `-i inplace`, consumed as that option's value.
        return T(_script_then_files(words, ("-f", "--file", "-e", "--source"), base)), unsure
    if base in ("cp", "mv", "install", "rsync", "ln", "link"):
        # A copy, move or link can put a whole directory in place, so its
        # destination is judged as a tree: a protected path inside it counts.
        dests, unsure = _destinations(words, base, cwd)
        return T(dests, "TREE"), unsure
    if base == "ditto":
        ops = _operands(words)
        return T(ops[-1:] if len(ops) >= 2 else [], "TREE"), None
    if base in ("touch", "truncate", "sponge"):
        return T(_operands(words, base)), None
    if base == "dd":
        of = next((w for w in words if w.value.startswith("of=")), None)
        return ([(Tok("word", of.value[3:], of.expands), "TARGET")] if of else []), None
    if base == "curl":
        return _curl_targets(words)
    if base == "wget":
        return _wget_targets(words)
    if base in TARS:
        return _tar_targets(words)
    if base == "unzip":
        return _unzip_targets(words)
    if base in SEVENZIPS:
        return _sevenzip_targets(words)
    if base == "cpio":
        return _cpio_targets(words)
    if base == "pax":
        return _pax_targets(words)
    if base in COMPRESSORS:
        return _compress_targets(base, words)
    if base in ED_EDITORS:
        return _ed_targets(words, fed_code, heredoc)
    if base in VI_EDITORS:
        return _vi_targets(words, fed_code)
    if base in ("split", "csplit"):
        return _split_targets(base, words)
    return [], None


def _strip_wrapper_options(words, wrapper):
    """(remaining words, unsure) — drop a wrapper's OWN options.

    Stripping only the wrapper's name leaves its first option in argv0's place:
    `env -i tee yarn.lock` becomes `-i`, `nice -n 10 tee yarn.lock` becomes
    `-n`, `sudo -u root tee yarn.lock` becomes `-u`. None of those is a write
    primitive, so each returns no targets — the silent-allow this guard exists
    to remove, reached without any attempt to evade it.
    """
    spec = WRAPPER_OPTS.get(wrapper, {})
    i = 0
    while i < len(words):
        v = words[i].value
        if v == "--":
            i += 1
            break
        # `env -` and `env FOO=bar` / `sudo FOO=bar` still precede the command.
        if wrapper == "env" and v == "-":
            i += 1
            continue
        if wrapper in ("env", "sudo") and not v.startswith("-") \
                and "=" in v and not v.startswith("="):
            i += 1
            continue
        if not _is_flag(v):
            break
        eats = _consume_option(v, spec)
        if eats is None:
            return words, ("is run under `%s %s`, an option this parse does not know, "
                           "so the command it actually runs cannot be identified"
                           % (wrapper, v))
        i += 1 + eats
    return words[i:], None


def redirect_targets(toks):
    """Targets of output redirections in a token list — any fd: `>`, `3>`, `3<>`, `>&FILE`."""
    out = []
    for idx, tok in enumerate(toks):
        if tok.kind != "op" or tok.value not in REDIRECT_OPS:
            continue
        nxt = toks[idx + 1] if idx + 1 < len(toks) else None
        if nxt is None or nxt.kind != "word":
            continue
        # `2>&1`, `>&2`, `>&-`, `>&3-` duplicate, close or move a descriptor; no file.
        if tok.value == ">&" and re.match(r"^(?:\d+-?|-)$", nxt.value):
            continue
        out.append(nxt)
    return out


def analyze_command(command, cwd):
    """Yield (kind, detail, fragment) records for one Bash command string."""
    anomalies = []
    heredoc_bodies = []
    toks = tokenize(command, anomalies, heredoc_bodies)
    heredoc_iter = iter(heredoc_bodies)

    records = []
    segment = []
    segments = []       # (tokens, preceded_by_pipe, terminator)
    piped = False
    for tok in toks:
        if tok.kind == "op" and tok.value in SEGMENT_SEPARATORS:
            segments.append((segment, piped, tok.value))
            segment = []
            piped = tok.value == "|"
        else:
            segment.append(tok)
    segments.append((segment, piped, ""))

    # `( … )` runs in a subshell, so a `cd` inside it dies at the `)`. Tracked
    # with a stack because one global cwd that is never restored resolves
    # `(cd /tmp); echo x > src/components/ui/button.tsx` against /tmp — a
    # protected path reported as an unprotected one while Bash writes the
    # protected one. An unbalanced `)` leaves cwd unknown rather than wrong.
    # The same-command assignments (ASSIGNS) are scoped the same way, and an
    # unbalanced `)` forgets them all rather than keeping a subshell's.
    cwd_stack = []
    ASSIGNS.clear()
    prev_terminator = ""

    for seg, piped_in, terminator in segments:
        if seg:
            cwd = _segment_records(seg, piped_in, terminator, cwd, records, heredoc_iter,
                                   conditional=prev_terminator in ("&&", "||"))
        # The group boundary is the terminator of the segment just processed.
        if terminator == "(":
            cwd_stack.append((cwd, dict(ASSIGNS)))
        elif terminator == ")":
            cwd, saved = cwd_stack.pop() if cwd_stack else (None, {})
            ASSIGNS.clear()
            ASSIGNS.update(saved)
        prev_terminator = terminator
    records.extend(("ANOMALY", why, "") for why in anomalies)
    return records


def _record_targets(pairs, cwd, records, fragment):
    """Resolve (token, kind) pairs to absolute paths and append their records."""
    for t, kind in pairs:
        value = _static_value(t)
        if value is None:
            records.append(("UNSURE", "writes to a target built by shell expansion (%s)" % t.value, fragment))
            continue
        path = _resolve(value, cwd)
        if path is None:
            records.append(("UNSURE", "writes to a relative path after a `cd` this parse could not follow (%s)" % t.value, fragment))
            continue
        records.append((kind, path, fragment))
        if not t.quoted and any(c in value for c in "*?["):
            records.append(("UNSURE", "writes to a glob that may cover paths beyond the one checked (%s)" % t.value, fragment))


# Commands that write nothing themselves, so a patch file named after them in
# the same command is still the file on disk now. Anything else that ran first
# might have rewritten it — see _patch_inputs.
QUIET_COMMANDS = ("cd", "pushd", "popd", "true", ":", "echo", "printf", "test", "[", "set",
                  "export", "ls", "cat", "pwd", "head", "tail", "wc", "grep", "which", "type")


def _segment_records(seg, piped_in, terminator, cwd, records, heredoc_iter, conditional=False):
    """Append this segment's records; return the cwd the NEXT segment sees.

    `conditional` is true when the segment follows `&&`/`||`: it may never
    run, so an assignment in it is forgotten rather than trusted.
    """
    fragment = " ".join(t.value for t in seg if t.kind == "word")[:160]

    # This segment's own `<<`/`<<-` bodies, in order — pulled off the shared
    # iterator HERE, unconditionally, whether or not this segment's command
    # ends up using them. tokenize collected bodies in left-to-right source
    # order across the WHOLE command; every segment with a heredoc operator
    # must take its share in that same order, or a later apply_patch segment
    # reads an earlier command's heredoc body instead of its own.
    heredoc_bodies = [next(heredoc_iter, "") for t in seg
                      if t.kind == "op" and t.value in ("<<", "<<-")]

    # An interpreter is handed a PROGRAM, not just data, by any of these.
    fed_code = piped_in or bool(heredoc_bodies) or any(
        t.kind == "op" and t.value in ("<", "<<<", "<&") for t in seg)
    redirects = [(t, "TARGET") for t in redirect_targets(seg)]

    # Words only, minus redirect operands and the fd numbers glued to them.
    words = []
    stdin_file = None
    skip_next = False
    for idx, tok in enumerate(seg):
        if skip_next:
            skip_next = False
            continue
        if tok.kind == "op":
            if tok.value in REDIRECT_OPS or tok.value in INPUT_OPS:
                skip_next = True
                if words and re.match(r"^(?:\d+|\{[A-Za-z_][A-Za-z0-9_]*\})$", words[-1].value):
                    words.pop()
                if tok.value == "<" and idx + 1 < len(seg) and seg[idx + 1].kind == "word":
                    stdin_file = seg[idx + 1]
            continue
        words.append(tok)

    def finish(pairs=()):
        # A redirection writes even when the command is `exec`, a bare `> f`, or
        # a wrapper this parse gave up on — it is the shell's write, not theirs.
        _record_targets(redirects + list(pairs), cwd, records, fragment)

    # What this segment assigns is known before its writes are resolved
    # (`S=/x` and `cp a "$S/b"` are separate segments; `S=/x cp a "$S/b"`
    # expands `$S` before the prefix is applied, and the prefix never reaches
    # the shell, so recording it only now is also correct for that form).
    _track_assignments(words, piped_in, terminator, conditional)

    # Leading `VAR=value` assignments and transparent wrappers — including each
    # wrapper's OWN options, or the first of them lands in argv0's place.
    while words:
        head = words[0].value
        if "=" in head and not head.startswith("=") and head.split("=", 1)[0].replace("_", "a").isalnum():
            words.pop(0)
            continue
        name = os.path.basename(head)
        if name in WRAPPERS:
            words.pop(0)
            words, wrapper_unsure = _strip_wrapper_options(words, name)
            if wrapper_unsure:
                records.append(("UNSURE", wrapper_unsure, fragment))
                finish()
                return cwd
            continue
        break
    if not words:
        finish()
        return cwd

    argv0, rest = words[0].value, words[1:]
    base = os.path.basename(argv0)
    records.append(("RAN", base, fragment))

    # `cd` moves the frame every later relative path is resolved against —
    # unless it runs in a subshell, where the move dies with it. A pipeline
    # component is a subshell too, so `cd /tmp | true; echo x > yarn.lock`
    # writes the repo's lockfile, not /tmp's. `pushd` moves it the same way.
    if base in ("cd", "pushd", "popd"):
        finish()
        if piped_in or terminator == "|":
            return cwd
        if base == "popd":
            return None
        ops = _operands(rest)
        if not ops:
            return os.path.expanduser("~") if base == "cd" else None
        value = _static_value(ops[0])
        if value is None or value == "-" or value.startswith("+"):
            return None
        return _resolve(value, cwd)

    # Codex's apply_patch also arrives as a Bash heredoc, not only as its own
    # `tool_name: "apply_patch"` payload — `apply_patch <<'PATCH' … PATCH`.
    # tokenize already pulled the body off for us (heredoc_bodies, above);
    # read the patch envelope back out of it exactly the way records_for()
    # does for the tool-call form, so both paths agree. A heredoc that is not
    # a patch envelope — prose that merely mentions patch markers — yields no
    # records, same as the tool-call path.
    if base == "apply_patch":
        body = heredoc_bodies[0] if heredoc_bodies else None
        if body is not None and "*** Begin Patch" in body:
            records.extend(apply_patch_targets(body, cwd))
        finish()
        return cwd

    if base == "git":
        _git_records(rest, cwd, fragment, heredoc_bodies, stdin_file, records, piped_in)
        finish()
        return cwd
    if base == "patch":
        _patch_records(rest, cwd, fragment, heredoc_bodies, stdin_file, records, piped_in)
        finish()
        return cwd
    if base == "script":
        nested = _script_records(rest, fragment, records)
        finish(nested[0])
        if nested[1]:
            # BSD `script FILE COMMAND…` runs COMMAND: judge it as a segment of its own.
            _segment_records(nested[1], False, "", cwd, records, iter(()))
        return cwd

    pairs, unsure = segment_targets(argv0, rest, fed_code, cwd,
                                    heredoc_bodies[0] if heredoc_bodies else None)
    if unsure:
        records.append(("UNSURE", unsure, fragment))
    if PROTECTED_MODE and not unsure:
        records.extend(_source_records(argv0, rest, cwd, fragment))
    finish(pairs)
    return cwd


def _script_records(words, fragment, records):
    """([(token, kind)], nested command words) for `script`: its typescript and log files."""
    out = []
    ops = []
    playback = False
    for name, val in _walk_options(words, "cEIOBTmot", (
            "--command", "--echo", "--log-in", "--log-out", "--log-io", "--log-timing",
            "--logging-format", "--output-limit", "--timing")):
        if name is None:
            ops.append(val)
        elif name in ("-c", "--command"):
            records.append(("UNSURE", EVAL_WHY, fragment))
        elif name in ("-I", "-O", "-B", "-T", "-t", "--log-in", "--log-out", "--log-io",
                      "--log-timing", "--timing") and val is not None:
            out.append((val, "TARGET"))
        elif name == "-p":
            playback = True
    if ops:
        out.append((ops[0], "TARGET"))
    elif not playback:
        out.append((Tok("word", "typescript"), "TARGET"))
    return out, ops[1:]


# --------------------------------------------------------------------------
# Patches and git (security review S-03, F4c)
# --------------------------------------------------------------------------
# `patch` and `git apply` write the paths their patch NAMES, so the patch is
# read (from its file, the heredoc, or the `<` redirect) and every target header
# is a TARGET — judged by every rule, generated ones included, because applying
# a patch authors content exactly as an editor does. When the patch cannot be
# read now — piped in, missing, or possibly rewritten by an earlier command in
# the same call — it stays UNSURE.
#
# git commands that REPLAY committed content onto the working tree (checkout,
# switch, restore, reset --hard, merge, pull, rebase, cherry-pick, revert, am,
# stash pop/apply/push, clean) are judged by the files they would change, asked
# of git itself with cheap, local, read-only queries (`git diff --name-only`,
# `git log --name-only`, `git stash show`, `git clean -n`). Those are REPLAY
# records: judged against the protected paths only, never the generated-file
# rules, since a merge legitimately changes a lockfile, and a hit is an R4 ASK
# (hook_ask on Claude Code, a deny on every other host), never a silent allow:
# an integrator merging a branch legitimately brings a protected file in, and
# the user decides. When git cannot answer (an unknown ref, a fetch that has
# not happened, a timeout), the command is UNSURE and says so; an explicit
# pathspec that names a protected path is still judged, as the same ask.
#
# Every git query runs with core.fsmonitor off, no pager, no external diff or
# textconv, GIT_OPTIONAL_LOCKS=0 (no index refresh write) and a deadline, all
# inside one budget kept well under the hook's own 5 s timeout.

GIT_QUERY_TIMEOUT = 1.5
GIT_BUDGET = [2.5]


def _git(frame, args):
    """stdout of a read-only, local git query run in `frame`, or None when it fails."""
    import subprocess
    import time
    if GIT_BUDGET[0] <= 0 or not frame or not os.path.isdir(frame):
        return None
    env = dict(os.environ)
    env.update({"GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0", "GIT_PAGER": "cat",
                "PAGER": "cat", "LC_ALL": "C"})
    cmd = ["git", "-c", "core.fsmonitor=false", "-c", "diff.relative=false",
           "-c", "core.quotePath=false", "--no-pager", "-C", frame] + list(args)
    start = time.time()
    try:
        p = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, env=env,
                           timeout=min(GIT_QUERY_TIMEOUT, GIT_BUDGET[0]))
    except Exception:  # noqa: BLE001 - no git, a timeout: the answer is "unknown"
        return None
    finally:
        GIT_BUDGET[0] -= time.time() - start
    if p.returncode != 0:
        return None
    return p.stdout.decode("utf-8", "replace")


def _z(out):
    return None if out is None else [x for x in out.split("\0") if x.strip()]


def _git_top(frame):
    out = _git(frame, ["rev-parse", "--show-toplevel"])
    top = out.strip() if out else ""
    return top or None


def _git_rev(frame, rev, kind="commit"):
    return _git(frame, ["rev-parse", "--verify", "--quiet", "%s^{%s}" % (rev, kind)]) is not None


def _git_diff(frame, revs, pathspecs=()):
    return _z(_git(frame, ["diff", "--name-only", "-z", "--no-ext-diff", "--no-textconv",
                           "--no-renames"] + list(revs) + ["--"] + list(pathspecs)))


def _git_split(args, value_opts):
    """(options {name: value or True}, operands before `--`, operands after `--`, saw `--`)."""
    opts = {}
    ops, after = [], []
    ddash = False
    i = 0
    while i < len(args):
        w = args[i]
        v = w.value
        if ddash:
            after.append(w)
        elif v == "--":
            ddash = True
        elif v.startswith("--"):
            name, eq, val = v.partition("=")
            if eq:
                opts[name] = val
            elif name in value_opts and i + 1 < len(args):
                opts[name] = args[i + 1].value
                i += 1
            else:
                opts[name] = True
        elif v.startswith("-") and len(v) > 1:
            body = v[1:]
            for k, c in enumerate(body):
                if "-" + c in value_opts:
                    tail = body[k + 1:]
                    if tail:
                        opts["-" + c] = tail
                    elif i + 1 < len(args):
                        opts["-" + c] = args[i + 1].value
                        i += 1
                    else:
                        opts["-" + c] = True
                    break
                opts["-" + c] = True
        else:
            ops.append(w)
        i += 1
    return opts, ops, after, ddash


def _has(opts, *names):
    return any(n in opts for n in names)


class _GitCtx(object):
    """One git segment: where it runs, and where its records go."""

    def __init__(self, sub, frame, fragment, records):
        self.sub = sub
        self.frame = frame
        self.fragment = fragment
        self.records = records
        self._top = False

    @property
    def top(self):
        if self._top is False:
            self._top = _git_top(self.frame)
        return self._top

    def unsure(self, why):
        self.records.append(("UNSURE", "git %s %s" % (self.sub, why), self.fragment))

    def replay(self, names, base=None):
        base = base or self.top or self.frame
        for name in names:
            self.records.append(("REPLAY", os.path.normpath(os.path.join(base, name)), self.fragment))

    def values(self, toks):
        vals = [_static_value(t) for t in toks]
        if any(v is None for v in vals):
            self.unsure("is given a revision or path built by shell expansion, so the files it rewrites were not checked")
            return None
        return vals

    def pathspec_fallback(self, paths, why):
        """git could not answer: an explicit pathspec still counts, and the rest is said."""
        for p in paths:
            if not any(c in p for c in "*?[") and not p.startswith(":"):
                full = _resolve(p, self.frame)
                if full:
                    self.records.append(("REPLAY", full, self.fragment))
        self.unsure(why)

    def paths_from(self, source, paths):
        names = _git_diff(self.frame, [source] if source else [], paths)
        if names is None:
            self.pathspec_fallback(paths, "could not be asked which files `%s` differs in, so only its explicit "
                                          "paths were checked" % (source or "the index"))
        else:
            self.replay(names)

    def switch_to(self, target, force):
        names = _git_diff(self.frame, [target] if force else ["HEAD", target])
        if names is None and not force:
            names = _git_diff(self.frame, [target])
        if names is None:
            self.unsure("could not determine which files switching to `%s` rewrites, so they were not checked" % target)
        else:
            self.replay(names)

    def incoming(self, refs):
        for ref in refs:
            names = _git_diff(self.frame, ["HEAD..." + ref])
            if names is None:
                self.unsure("could not determine the incoming changes of `%s`, so the files it rewrites were "
                            "not checked" % ref)
            else:
                self.replay(names)

    def commits(self, revs):
        names = _z(_git(self.frame, ["log", "--no-walk=unsorted", "-m", "--format=", "--name-only",
                                     "-z", "--no-ext-diff"] + list(revs) + ["--"]))
        if names is None:
            self.unsure("could not determine the files those commits change, so they were not checked")
        else:
            self.replay(names)


def _git_checkout(g, args):
    opts, ops, after, ddash = _git_split(args, ("-b", "-B", "--orphan", "--conflict", "--pathspec-from-file"))
    if _has(opts, "-p", "--patch", "--pathspec-from-file"):
        return g.unsure("chooses its paths interactively or from a file, so the files it rewrites were not checked")
    vals = g.values(ops + after)
    if vals is None:
        return
    before, paths = vals[:len(ops)], vals[len(ops):]
    force = _has(opts, "-f", "--force", "-m", "--merge")
    if ddash:
        return g.paths_from(before[0] if before else None, paths)
    if _has(opts, "-b", "-B", "--orphan"):
        if before:
            g.switch_to(before[0], force)
        return
    if not before:
        return
    if len(before) == 1 and _git_rev(g.frame, before[0]):
        return g.switch_to(before[0], force)
    if _git_rev(g.frame, before[0], "tree"):
        return g.paths_from(before[0], before[1:])
    g.paths_from(None, before)


def _git_switch(g, args):
    opts, ops, after, ddash = _git_split(args, ("-c", "-C", "--create", "--force-create", "--orphan", "--conflict"))
    vals = g.values(ops)
    if vals is None:
        return
    if _has(opts, "--orphan"):
        # An orphan branch starts with no tracked files: every one of them goes.
        names = _z(_git(g.frame, ["ls-files", "-z", "--full-name"]))
        return g.replay(names) if names is not None else g.unsure("could not list the tracked files it removes")
    force = _has(opts, "-f", "--force", "--discard-changes", "-m", "--merge")
    if vals:
        g.switch_to(vals[0], force)


def _git_restore(g, args):
    opts, ops, after, ddash = _git_split(args, ("-s", "--source", "--pathspec-from-file", "--conflict"))
    if _has(opts, "-p", "--patch", "--pathspec-from-file"):
        return g.unsure("chooses its paths interactively or from a file, so the files it rewrites were not checked")
    staged = _has(opts, "-S", "--staged")
    if staged and not _has(opts, "-W", "--worktree"):
        return                  # the index only
    vals = g.values(ops + after)
    if vals is None:
        return
    source = opts.get("-s") or opts.get("--source")
    source = source if isinstance(source, str) else ("HEAD" if staged else None)
    g.paths_from(source, vals)


def _git_reset(g, args):
    opts, ops, after, ddash = _git_split(args, ("--pathspec-from-file",))
    if after or not _has(opts, "--hard", "--merge", "--keep"):
        return                  # the index and HEAD only
    vals = g.values(ops[:1])
    if vals is None:
        return
    commit = vals[0] if vals else "HEAD"
    names = _git_diff(g.frame, [commit] if "--hard" in opts else ["HEAD", commit])
    if names is None:
        return g.unsure("could not determine which files resetting to `%s` rewrites, so they were not checked" % commit)
    g.replay(names)


def _git_merge(g, args):
    opts, ops, after, ddash = _git_split(args, ("-m", "-F", "-s", "-X", "--strategy", "--strategy-option",
                                                "--file", "--into-name", "--cleanup", "--message"))
    if _has(opts, "--abort"):
        return g.unsure("restores the pre-merge working tree; the files it rewrites were not computed")
    if _has(opts, "--continue", "--quit"):
        return
    vals = g.values(ops)
    if vals is not None:
        g.incoming(vals or ["@{u}"])


def _git_pull(g, args):
    opts, ops, after, ddash = _git_split(args, (
        "-s", "-X", "--strategy", "--strategy-option", "--depth", "--deepen", "--shallow-since",
        "--shallow-exclude", "-j", "--jobs", "--upload-pack", "-o", "--server-option", "--negotiation-tip"))
    vals = g.values(ops)
    if vals is None:
        return
    if vals and vals[0] == ".":
        # A pull from this repository: every ref is local, so the answer is known.
        refs = [v.split(":", 1)[0] for v in vals[1:]]
        if refs:
            return g.incoming(refs)
        return g.unsure("merges a ref this parse cannot name, so the files it rewrites were not checked")
    if len(vals) > 1:
        refs = ["%s/%s" % (vals[0], v.split(":", 1)[0].replace("refs/heads/", "")) for v in vals[1:]]
    else:
        refs = ["@{u}"]
    seen = [r for r in refs if _git_rev(g.frame, r)]
    for r in seen:
        names = _git_diff(g.frame, ["HEAD..." + r])
        if names is not None:
            g.replay(names)
    g.unsure("fetches commits this check has not seen, so the files it rewrites could not be determined%s"
             % (" (only the already-fetched %s was checked)" % ", ".join(seen) if seen else ""))


def _git_rebase(g, args):
    opts, ops, after, ddash = _git_split(args, ("--onto", "-s", "-X", "--strategy", "--strategy-option",
                                                "-x", "--exec", "-C", "--whitespace", "--empty"))
    if _has(opts, "--continue", "--skip", "--abort"):
        return g.unsure("resumes or unwinds a rebase in progress; the files it rewrites were not computed")
    if _has(opts, "--quit", "--edit-todo", "--show-current-patch"):
        return
    if _has(opts, "-x", "--exec", "--root", "-i", "--interactive"):
        g.unsure("runs a todo list or commands this parse does not read")
    vals = g.values(ops)
    if vals is None:
        return
    onto = opts.get("--onto")
    upstream = vals[0] if vals else "@{u}"
    if len(vals) > 1:
        g.switch_to(vals[1], False)
    g.incoming([onto if isinstance(onto, str) else upstream])


def _git_pick(g, args):
    opts, ops, after, ddash = _git_split(args, ("-m", "--mainline", "-s", "--strategy", "-X",
                                                "--strategy-option", "--cleanup"))
    if _has(opts, "--continue", "--skip", "--abort"):
        return g.unsure("resumes or unwinds a sequence in progress; the files it rewrites were not computed")
    if _has(opts, "--quit"):
        return
    vals = g.values(ops)
    if vals:
        g.commits(vals)


def _git_stash(g, args):
    sub = args[0].value if args and not args[0].value.startswith("-") else "push"
    rest = args[1:] if args and not args[0].value.startswith("-") else args
    if sub in ("pop", "apply", "branch"):
        opts, ops, after, ddash = _git_split(rest, ())
        vals = g.values(ops)
        if vals is None:
            return
        if sub == "branch":
            vals = vals[1:]
        stash = vals[0] if vals else "stash@{0}"
        names = _z(_git(g.frame, ["stash", "show", "--name-only", "-z", "--include-untracked", stash]))
        if names is None:
            names = _git_diff(g.frame, [stash + "^1", stash])
            if names is not None:
                names += _z(_git(g.frame, ["ls-tree", "-r", "--name-only", "-z", stash + "^3"])) or []
        if names is None:
            return g.unsure("could not determine the files `%s` holds, so they were not checked" % stash)
        return g.replay(names)
    if sub in ("push", "save"):
        # The working tree goes back to HEAD: every changed file is rewritten.
        opts, ops, after, ddash = _git_split(rest, ("-m", "--message", "--pathspec-from-file"))
        if _has(opts, "-p", "--patch", "--pathspec-from-file"):
            return g.unsure("chooses its paths interactively or from a file, so the files it rewrites were not checked")
        paths = g.values(after if sub == "push" else [])
        if paths is None:
            return
        names = _git_diff(g.frame, ["HEAD"], paths)
        if _has(opts, "-u", "--include-untracked", "-a", "--all") and names is not None:
            extra = ["--exclude-standard"] if not _has(opts, "-a", "--all") else []
            untracked = _z(_git(g.frame, ["ls-files", "--others", "--full-name", "-z"] + extra + ["--"] + paths))
            names = None if untracked is None else names + untracked
        if names is None:
            return g.unsure("could not determine which files it rewrites, so they were not checked")
        g.replay(names)


def _git_clean(g, args):
    flags = []
    for a in args:
        v = a.value
        if v in ("-f", "--force", "-i", "--interactive", "-q", "--quiet", "-n", "--dry-run"):
            continue
        if v.startswith("-") and not v.startswith("--"):
            head, sep, tail = v[1:].partition("e")
            body = "".join(c for c in head if c not in "fiqn") + sep + tail
            if body:
                flags.append("-" + body)
            continue
        flags.append(v)
    out = _git(g.frame, ["clean", "-n"] + flags)
    if out is None:
        return g.unsure("could not determine which files it removes, so they were not checked")
    names = [line[len("Would remove "):] for line in out.splitlines() if line.startswith("Would remove ")]
    g.replay(names, base=g.frame)


def _git_rm(g, args):
    opts, ops, after, ddash = _git_split(args, ("--pathspec-from-file",))
    if _has(opts, "--cached", "-n", "--dry-run"):
        return
    if _has(opts, "--pathspec-from-file"):
        return g.unsure("reads its paths from a file, so the files it removes were not checked")
    for t in ops + after:
        if any(c in t.value for c in "*?[") or t.value.startswith(":"):
            g.unsure("expands the pathspec `%s` itself, so the files it removes were not checked" % t.value)
    _record_targets([(t, "DELETE") for t in ops + after], g.frame, g.records, g.fragment)


def _git_mv(g, args):
    opts, ops, after, ddash = _git_split(args, ())
    ops = ops + after
    if _has(opts, "-n", "--dry-run") or len(ops) < 2:
        return
    dest, sources = ops[-1], ops[:-1]
    if len(sources) > 1 or _isdir(dest, g.frame):
        dests = [_word(os.path.join(dest.value, os.path.basename(s.value)), dest, s) for s in sources]
    else:
        dests = [dest]
    _record_targets([(d, "TREE") for d in dests], g.frame, g.records, g.fragment)
    if PROTECTED_MODE:
        for s in sources:
            v = _static_value(s)
            path = _resolve(v, g.frame) if v is not None else None
            if path:
                g.records.append(("SOURCE", path, "mv:" + g.fragment))


def _git_apply(g, args, heredocs, stdin_file, piped_in):
    opts, ops, after, ddash = _git_split(args, ("-p", "-C", "--directory", "--exclude", "--include",
                                                "--whitespace", "--build-fake-ancestor"))
    if _has(opts, "--check", "--stat", "--numstat", "--summary") and "--apply" not in opts:
        return
    if _has(opts, "--cached") and "--index" not in opts:
        return                  # the index only
    _apply_patch_files(g, opts, ops + after, heredocs, stdin_file, piped_in, "TARGET")


def _git_am(g, args, heredocs, stdin_file, piped_in):
    opts, ops, after, ddash = _git_split(args, ("-p", "-C", "--directory", "--exclude", "--include",
                                                "--patch-format", "--whitespace", "--quoted-cr", "--empty"))
    if _has(opts, "--continue", "-r", "--resolved", "--skip", "--abort", "--retry"):
        return g.unsure("resumes or unwinds an am in progress; the files it rewrites were not computed")
    if _has(opts, "--quit", "--show-current-patch"):
        return
    _apply_patch_files(g, opts, ops + after, heredocs, stdin_file, piped_in, "REPLAY")


def _apply_patch_files(g, opts, files, heredocs, stdin_file, piped_in, kind):
    try:
        strip = int(opts.get("-p", 1))
    except (TypeError, ValueError):
        strip = 1
    texts = _patch_inputs(files, g.frame, heredocs, stdin_file, g.records)
    if texts is None:
        return g.unsure("applies a patch this parse could not read now, so the paths it writes were not checked")
    base = g.top or g.frame
    prefix = opts.get("--directory")
    if isinstance(prefix, str):
        base = os.path.join(base, prefix)
    for text in texts:
        for p in _patch_paths(text):
            q = _strip_path(p, strip)
            if q:
                g.records.append((kind, os.path.normpath(os.path.join(base, q)), g.fragment))


GIT_HANDLERS = {
    "checkout": _git_checkout, "switch": _git_switch, "restore": _git_restore, "reset": _git_reset,
    "merge": _git_merge, "pull": _git_pull, "rebase": _git_rebase, "cherry-pick": _git_pick,
    "revert": _git_pick, "stash": _git_stash, "clean": _git_clean, "rm": _git_rm, "mv": _git_mv,
}
GIT_PATCH_HANDLERS = {"apply": _git_apply, "am": _git_am}
GIT_OPAQUE = ("read-tree", "checkout-index", "bisect")
GIT_GLOBAL_VALUE = ("-c", "--namespace", "--exec-path", "--config-env", "--super-prefix",
                    "--attr-source", "--list-cmds")


def _git_records(words, cwd, fragment, heredocs, stdin_file, records, piped_in):
    """Records for one `git …` segment (see "Patches and git")."""
    frame = cwd
    lost = False
    i = 0
    while i < len(words):
        v = words[i].value
        if v == "-C":
            d = _static_value(words[i + 1]) if i + 1 < len(words) else None
            frame = _resolve(d, frame) if d is not None and frame is not None else None
            lost = lost or frame is None
            i += 2
            continue
        name = v.split("=", 1)[0]
        if name in ("--git-dir", "--work-tree"):
            lost = True
            i += 1 if "=" in v else 2
            continue
        if v in GIT_GLOBAL_VALUE:
            i += 2
            continue
        if v.startswith("-"):
            i += 1
            continue
        break
    if i >= len(words):
        return
    sub, args = words[i].value, words[i + 1:]
    known = sub in GIT_HANDLERS or sub in GIT_PATCH_HANDLERS or sub in GIT_OPAQUE
    if not known:
        return
    if not PROTECTED_MODE:
        # Only the protected-path pass asks git; every other caller keeps the old answer.
        if sub in GIT_PATCH_HANDLERS:
            records.append(("UNSURE", "applies a patch; the written paths are named inside the patch, not on the command line", fragment))
        return
    g = _GitCtx(sub, frame, fragment, records)
    if lost or frame is None:
        return g.unsure("runs against a repository this parse cannot locate (-C, --git-dir or --work-tree), so "
                        "the files it rewrites were not checked")
    if sub in GIT_OPAQUE:
        if sub != "read-tree" or any(a.value in ("-u", "--reset") for a in args):
            g.unsure("rewrites the working tree from the index or another commit; the files it changes were not computed")
        return
    if sub in GIT_PATCH_HANDLERS:
        return GIT_PATCH_HANDLERS[sub](g, args, heredocs, stdin_file, piped_in)
    GIT_HANDLERS[sub](g, args)


PATCH_VALUE = ("-p", "--strip", "-i", "--input", "-o", "--output", "-d", "--directory", "-r",
               "--reject-file", "-B", "--prefix", "-Y", "--basename-prefix", "-z", "--suffix",
               "-D", "--ifdef", "-F", "--fuzz", "-V", "--version-control", "-g", "--get",
               "--quoting-style")


def _patch_records(args, cwd, fragment, heredocs, stdin_file, records, piped_in):
    opts, ops, after, ddash = _git_split(args, PATCH_VALUE)
    if _has(opts, "--dry-run"):
        return
    d = opts.get("-d") or opts.get("--directory")
    base = _resolve(d, cwd) if isinstance(d, str) else cwd
    if base is None:
        records.append(("UNSURE", "patches files relative to a directory this parse could not follow", fragment))
        return
    pairs = []
    for key in ("-o", "--output", "-r", "--reject-file"):
        if isinstance(opts.get(key), str) and opts[key] != "-":
            pairs.append((Tok("word", opts[key]), "TARGET"))
    vals = ops + after
    if vals:
        pairs.append((vals[0], "TARGET"))       # the ORIGINALFILE operand is what it rewrites
    _record_targets(pairs, base, records, fragment)
    if vals:
        return
    given = opts.get("-i") or opts.get("--input")
    files = [Tok("word", given)] if isinstance(given, str) else []
    texts = _patch_inputs(files, cwd, heredocs, stdin_file, records)
    if texts is None:
        records.append(("UNSURE", "applies a patch this parse could not read now, so the paths it writes were not checked", fragment))
        return
    strip = opts.get("-p") or opts.get("--strip")
    try:
        strips = [int(strip)] if isinstance(strip, str) else [0, 1, None]
    except ValueError:
        strips = [0, 1, None]
    seen = set()
    for text in texts:
        for p in _patch_paths(text):
            for n in strips:
                q = os.path.basename(p) if n is None else _strip_path(p, n)
                full = os.path.normpath(os.path.join(base, q)) if q else None
                if full and full not in seen:
                    seen.add(full)
                    records.append(("TARGET", full, fragment))


def _patch_inputs(files, frame, heredocs, stdin_file, records):
    """The text of each patch input, or None when any of them cannot be read as it will be applied."""
    texts = []
    names = [f for f in files if f.value != "-"]
    if not names or any(f.value == "-" for f in files):
        if heredocs:
            texts.append(heredocs[0])
        elif stdin_file is not None:
            names.append(stdin_file)
        else:
            return None         # a pipe or a terminal: the patch is not on disk
    # Anything earlier in this command might have rewritten the file since:
    # a write to it (or to a tree holding it), an unresolved write, or any
    # program not known to write nothing. "Earlier" is everything before this
    # segment's own RAN record.
    here = max([i for i, r in enumerate(records) if r[0] == "RAN"] or [len(records)])
    prior = records[:here]
    written = [(k, d) for k, d, _ in prior if k in ("TARGET", "TREE", "DELETE")]
    if any(k == "UNSURE" or (k == "RAN" and d not in QUIET_COMMANDS) for k, d, _ in prior):
        return None
    for f in names:
        v = _static_value(f)
        path = _resolve(v, frame) if v is not None else None
        if not path:
            return None
        real = os.path.realpath(path)
        for k, d in written:
            if path == d or real == d or path.startswith(d.rstrip("/") + "/") or real.startswith(d.rstrip("/") + "/"):
                return None
        try:
            if not os.path.isfile(path) or os.path.getsize(path) > (8 << 20):
                return None
            with open(path, "rb") as fh:
                texts.append(fh.read().decode("utf-8", "replace"))
        except OSError:
            return None
    return texts


def _c_unquote(s):
    """git's C-style quoted path (core.quotePath), enough for the target headers."""
    try:
        return bytes(s, "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8", "replace")
    except Exception:  # noqa: BLE001
        return s


def _patch_paths(text):
    """Every path a unified, context or git diff names as a target or a source."""
    out = []

    def add(p):
        p = p.strip()
        if len(p) >= 2 and p[0] == '"' and p[-1] == '"':
            p = _c_unquote(p[1:-1])
        if p and p != "/dev/null" and p not in out:
            out.append(p)

    for line in text.splitlines():
        if line.startswith("diff --git "):
            rest = line[len("diff --git "):]
            m = re.match(r'^("(?:[^"\\]|\\.)*"|\S+) ("(?:[^"\\]|\\.)*"|\S+)$', rest)
            if m:
                add(m.group(1))
                add(m.group(2))
            elif " b/" in rest:
                k = rest.index(" b/")
                add(rest[:k])
                add(rest[k + 1:])
        elif line.startswith(("--- ", "+++ ")) or (line.startswith("*** ") and not re.match(r"^\*\*\* \d", line)):
            body = line[4:]
            add(body.split("\t", 1)[0])
            add(body.split(" ", 1)[0])
        elif line.startswith(("rename from ", "rename to ", "copy from ", "copy to ")):
            add(line.split(" ", 2)[2])
        elif line.startswith("Index: "):
            add(line[len("Index: "):])
    return out


def _strip_path(path, n):
    """`patch -pN`: drop the smallest prefix holding N slashes; None when nothing is left."""
    parts = path.split("/")
    if n >= len(parts):
        return None
    return "/".join(parts[n:]) or None


# --------------------------------------------------------------------------
# apply_patch (Codex CLI's editing tool)
# --------------------------------------------------------------------------
# Codex's editing tool is `apply_patch`, not Edit/Write/MultiEdit. Its
# `tool_input` is `{"command": "<patch envelope>"}` — text in the documented
# apply_patch/"V4A" envelope format, not a shell command to tokenize:
#
#   *** Begin Patch
#   *** Update File: path/to/file.py
#   *** Move to: path/to/renamed.py
#   @@ some context
#   -old line
#   +new line
#   *** Add File: path/to/new.py
#   +line
#   *** Delete File: path/to/old.py
#   *** End Patch
#
# Before this, `records_for` had no branch for `tool_name == "apply_patch"`,
# and its `tool_input` has no `file_path`/`path`/`notebook_path`/`filePath`
# key for the EDIT_PATH_KEYS fallback to find either — so every apply_patch
# write was invisible to the guard, exactly the silent-allow this module's
# own docstring says it exists to close.
#
# apply_patch ALSO arrives as a Bash heredoc — `apply_patch <<'PATCH' … PATCH`
# — with `tool_name: "Bash"`, not `"apply_patch"`. That form is handled in
# `_segment_records`, which reads the heredoc body `tokenize` pulled off and
# calls this same function on it. Both paths funnel through
# `apply_patch_targets` so a given patch envelope reports the same targets
# regardless of which shape it arrived in — see the comment there
# (tests/hooks/test-apply-patch-heredoc-bypass.sh holds the shell form).
#
# The markers are matched literally, not grepped for a protected path, for
# the same reason `analyze_command` parses instead of greps: a `-` line
# removing a reference to a protected filename is patch body, not a write
# target, and only appears as one in a position this parser does not scan.
#
# `Move to:` (a rename target inside an `Update File:` block) is included
# even though it was not one of the three literal markers asked for, because
# without it a rename into a protected path — `*** Update File: scratch.py`
# followed by `*** Move to: yarn.lock` — would report the write as the old
# path and miss the one that actually lands on the protected file.
PATCH_MARKER_KIND = (
    ("Add File", "TARGET"),
    ("Update File", "TARGET"),
    ("Move to", "TARGET"),
    ("Delete File", "DELETE"),
)


def apply_patch_targets(command, cwd):
    """(kind, absolute_path, fragment) records for an apply_patch envelope."""
    records = []
    for line in command.splitlines():
        stripped = line.strip()
        if not stripped.startswith("*** "):
            continue
        header = stripped[4:]
        for marker, kind in PATCH_MARKER_KIND:
            prefix = marker + ": "
            if not header.startswith(prefix):
                continue
            value = header[len(prefix):].strip()
            if value:
                path = os.path.expanduser(value)
                if not os.path.isabs(path):
                    path = os.path.join(cwd, path)
                records.append((kind, os.path.normpath(path), stripped[:160]))
            break
    return records


# `file_path` is also what Gemini CLI's write_file and replace tools carry, so
# no Gemini-specific branch is needed for them (tool names are mapped in
# hooks/lib/platform-tools.sh and by hooks/gemini-wrap.sh).
EDIT_PATH_KEYS = ("file_path", "path", "notebook_path", "filePath")


def records_for(payload):
    tool = payload.get("tool_name") or ""
    tool_input = payload.get("tool_input") or {}
    cwd = payload.get("cwd") or os.getcwd()

    if tool in ("Bash", "Shell", "BashOutput", "run_terminal_cmd", "run_shell_command"):
        command = tool_input.get("command") or ""
        if not command.strip():
            return []
        # Gemini's run_shell_command carries the directory the command runs in
        # as `dir_path` (absolute or workspace-relative); a relative write
        # target resolves against THAT, not the session cwd. (The Gemini
        # extension's wrapper, hooks/gemini-wrap.sh, already folds dir_path
        # into cwd before the hook runs; this is for a payload that arrives
        # untranslated.)
        dir_path = tool_input.get("dir_path")
        if isinstance(dir_path, str) and dir_path.strip():
            cwd = dir_path if os.path.isabs(dir_path) else os.path.join(cwd, dir_path)
        return analyze_command(command, cwd)

    if tool == "apply_patch":
        command = tool_input.get("command") or ""
        if "*** Begin Patch" in command:
            return apply_patch_targets(command, cwd)
        return []

    for key in EDIT_PATH_KEYS:
        value = tool_input.get(key)
        if value:
            path = os.path.expanduser(value)
            if not os.path.isabs(path):
                path = os.path.join(cwd, path)
            return [("TARGET", os.path.normpath(path), tool or "edit")]
    return []


# --------------------------------------------------------------------------
# Protected paths (`--protected`): ADR 004 D10.1, security review S-03
# --------------------------------------------------------------------------
# The plugin's own permission policy, its guard files and every host settings
# store that could widen what an agent may do are R4 `policy.edit`: the agent
# never writes them, and no environment switch unlocks them (D10.1, D10.3).
# Only guard-sensitive-files.sh passes `--protected`; every other consumer of
# this parser sees the output it always saw.
#
# Three things differ from the other protected categories:
#   - Both the lexical path and its realpath are judged. A symlink that points
#     into a protected directory, or a parent directory that is one, otherwise
#     carries an ordinary-looking target onto a protected file (S-03).
#   - `ln` sources (the file a new link points at) and `mv` sources (a file
#     moved away is a file deleted) are judged too, and deleting a directory
#     that CONTAINS a protected home or plugin-root path counts as deleting it.
#   - An UNSURE write whose command text names a protected path is a deny, not
#     an advisory: the parser cannot prove which file an interpreter writes, so
#     a mention is the only evidence there is, and for R4 it is enough.
#
# The table comes from core/permissions/actions.json (`equivalents.paths` of
# the ids below); FALLBACK_PROTECTED is used only when that file cannot be
# read, and tests/test-sensitive-protected-paths.sh holds the two equal.
PROTECTED_MODE = False
PROTECTED_IDS = ("policy.edit", "config.global.write")
FALLBACK_PROTECTED = {
    "policy.edit": [
        "{home}/.config/tamirs-superpowers/**",
        "{home}/.local/state/tamirs-superpowers/**",
        "{repo}/.tamirs-superpowers/**",
        "{plugin_root}/hooks/**",
        "{plugin_root}/core/permissions/**",
        "{plugin_root}/scripts/resolve-permission.sh",
        "{plugin_root}/scripts/plugin-config.sh",
        "{plugin_root}/scripts/lib/permission-common.sh",
        "{home}/.claude/plugins/cache/**",
        "{home}/.claude/settings*.json",
        "{repo}/.claude/settings*.json",
        "{home}/.gemini/settings.json",
        "{home}/.gemini/policies/**",
        "{home}/.gemini/extensions/tamirs-superpowers/**",
        "{repo}/.gemini/settings.json",
        "{repo}/.gemini/policies/**",
        "{repo}/.gemini/extensions/**",
        "{home}/.codex/config.toml",
        "{home}/.codex/hooks*",
        "{home}/.codex/rules/**",
        "{home}/.codex/plugins/**",
        "{home}/.cursor/hooks.json",
        "{home}/.cursor/cli-config.json",
        "{home}/.cursor/permissions.json",
        "{repo}/.cursor/hooks.json",
        "{home}/.config/opencode/**",
        "{repo}/opencode.json",
        "{repo}/opencode.jsonc",
        "{repo}/.opencode/opencode.json",
        "{repo}/.opencode/opencode.jsonc",
        "{repo}/.opencode/plugin/**",
        "{repo}/.opencode/plugins/**",
        "{repo}/.opencode/agent/**",
        "{repo}/.opencode/agents/**",
        "{home}/.config/gh/**",
        "{home}/.gitconfig",
    ],
    "config.global.write": [
        "{repo}/.git/hooks/**",
        "{repo}/.git/config",
    ],
}
GLOB_CHARS = "*?["


def _this_plugin_root():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def protected_table(root=None):
    """[(action id, pattern)] from actions.json, else the fallback table."""
    root = root or _this_plugin_root()
    try:
        with open(os.path.join(root, "core", "permissions", "actions.json")) as fh:
            data = json.load(fh)
        actions = data["actions"]
        by_id = actions if isinstance(actions, dict) else dict((a["id"], a) for a in actions)
        out = []
        for aid in PROTECTED_IDS:
            paths = by_id[aid]["equivalents"]["paths"]
            if not paths or not all(isinstance(p, str) for p in paths):
                raise ValueError(aid)
            out.extend((aid, p) for p in paths)
        return out
    except Exception:  # noqa: BLE001 - an unreadable catalog must not unprotect
        return [(aid, p) for aid in PROTECTED_IDS for p in FALLBACK_PROTECTED[aid]]


def _forms(path):
    """The lexical and resolved spellings of an absolute path."""
    out = []
    for p in (os.path.normpath(path), os.path.realpath(path)):
        if p not in out:
            out.append(p)
    return out


def passwd_home():
    """The real uid's home from the passwd entry, as scripts/lib/permission-common.sh reads it (D3)."""
    try:
        import pwd
        return pwd.getpwuid(os.getuid()).pw_dir
    except Exception:  # noqa: BLE001
        return None


def protected_roots():
    """{placeholder: [(root, mode)]} — mode is deny, or ask for a source checkout's guard files."""
    homes = []
    # The passwd home decides (S-04); a session HOME is added, never trusted
    # instead — protecting one more directory can only tighten.
    for h in (passwd_home(), os.environ.get("HOME")):
        if h and os.path.isabs(h):
            for f in _forms(h):
                if f not in homes and f != "/":
                    homes.append(f)
    plugin = []
    for r in (_this_plugin_root(), os.environ.get("CLAUDE_PLUGIN_ROOT")):
        if r and os.path.isabs(r) and os.path.isdir(r):
            # A source checkout carries its own `.git` at the root; an installed
            # copy never does, even when an ancestor (a dotfiles home) is a repo.
            mode = "ask" if os.path.lexists(os.path.join(os.path.realpath(r), ".git")) else "deny"
            for f in _forms(r):
                if f not in [p for p, _ in plugin]:
                    plugin.append((f, mode))
    return {"home": [(h, "deny") for h in homes], "plugin_root": plugin}


def _tail_regex(tail):
    """A path glob tail as a regex: `**` crosses directories, `*` does not."""
    dir_glob = tail.endswith("/**")
    if dir_glob:
        tail = tail[:-3]
    out = []
    i = 0
    while i < len(tail):
        if tail.startswith("**", i):
            out.append(".*")
            i += 2
        elif tail[i] == "*":
            out.append("[^/]*")
            i += 1
        elif tail[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(tail[i]))
            i += 1
    return "".join(out) + ("(?:/.*)?" if dir_glob else "")


def _fixed(tail):
    """The literal part of a tail, before its first glob character."""
    for i, ch in enumerate(tail):
        if ch in GLOB_CHARS:
            return tail[:i]
    return tail


# Case: on a case-insensitive volume (macOS APFS by default) `~/.CLAUDE/settings.json`
# IS `~/.claude/settings.json`, and realpath does not fold case, so every rule is
# compared case-folded wherever the volume folds — and wherever that cannot be
# shown either way, because folding can only protect one spelling more.
_FOLD_CACHE = {}


def _folds(path):
    """True when the volume holding `path` matches names case-insensitively, False when it
    provably does not, None when nothing on the way up has a cased letter to test with."""
    p = path
    while True:
        if p in _FOLD_CACHE:
            return _FOLD_CACHE[p]
        try:
            st = os.lstat(p)
        except OSError:
            st = None
        base = os.path.basename(p)
        if st is not None and base.lower() != base.upper():
            try:
                alt = os.lstat(os.path.join(os.path.dirname(p), base.swapcase()))
                answer = (alt.st_ino, alt.st_dev) == (st.st_ino, st.st_dev)
            except OSError:
                answer = False
            _FOLD_CACHE[p] = answer
            return answer
        parent = os.path.dirname(p)
        if parent == p:
            return None
        p = parent


def _ondisk_case(path):
    """`path` with each existing component spelled as its directory lists it.

    Only meaningful on a folding volume: it is how the generated-file rules in
    guard-sensitive-files.sh see `.GitHub/Workflows/ci.yml` as the workflow it is.
    """
    parts = [x for x in path.split("/") if x]
    cur = "/"
    out = []
    for idx, name in enumerate(parts):
        nxt = os.path.join(cur, name)
        if not os.path.lexists(nxt):
            out.extend(parts[idx:])
            break
        try:
            entries = os.listdir(cur)
        except OSError:
            out.extend(parts[idx:])
            break
        if name not in entries:
            same = [e for e in entries if e.casefold() == name.casefold()]
            if len(same) == 1:
                name = same[0]
        out.append(name)
        cur = os.path.join(cur, name)
    return "/" + "/".join(out)


def _canonical(path):
    """The realpath of a target, spelled on disk where the volume folds case."""
    real = os.path.realpath(path)
    return _ondisk_case(real) if _folds(real) else real


def _fold(s, fold):
    return s.casefold() if fold else s


class Protection(object):
    def __init__(self, cwd):
        self.table = protected_table()
        self.roots = protected_roots()
        self.cwd_forms = _forms(cwd) if cwd and os.path.isabs(cwd) else []
        # (regex, folded regex, id, pattern, mode, placeholder, literal) — the literal
        # is the rule's text before its first glob: absolute for a home or plugin-root
        # rule, repository-relative for a {repo} rule.
        self.rules = []
        self._repo_cache = {}
        for aid, pattern in self.table:
            m = re.match(r"^\{(home|repo|plugin_root|worktree)\}/(.+)$", pattern)
            if not m:
                continue
            ph, tail = m.group(1), m.group(2)
            tre = _tail_regex(tail)
            if ph == "repo":
                # Matched against the path below each ancestor that is a repo root.
                self._add("^" + tre + "$", aid, pattern, "deny", ph, _fixed(tail), tail)
                continue
            for root, mode in self.roots.get(ph, []):
                base = "" if root == "/" else root
                self._add("^" + re.escape(base) + "/" + tre + "$", aid, pattern, mode, ph,
                          base + "/" + _fixed(tail), base + "/" + tail)

    def _add(self, rx, aid, pattern, mode, ph, literal, full):
        self.rules.append((re.compile(rx), re.compile(rx, re.IGNORECASE), aid, pattern, mode, ph,
                           literal, literal == full))

    def _repo_root(self, root, fold):
        key = (root, fold)
        if key not in self._repo_cache:
            self._repo_cache[key] = os.path.lexists(os.path.join(root, ".git")) or any(
                _fold(root, fold) == _fold(c, fold) for c in self.cwd_forms)
        return self._repo_cache[key]

    def _bases(self, form, ph, literal, fold, tree):
        """(root, literal path) pairs a rule's literal can be compared against for `form`."""
        if ph != "repo":
            return [("", literal)]
        roots = [r for r in _ancestors(form) if self._repo_root(r, fold)]
        if tree and self._repo_root(form, fold):
            roots.append(form)
        return [(r, r + "/" + literal) for r in roots]

    def match(self, path, containing=False, tree=False):
        """[(mode, id, pattern, form, inside)] for a path; `inside` marks a hit on a path it holds.

        `containing` also matches a path that is an ANCESTOR of a protected one —
        deleting, moving away or replacing the directory removes what it holds.
        `tree` (a copy, move or extraction INTO the path) does too, and counts a
        repository root itself, which a delete does not (a temporary repository
        stays removable; an archive unpacked over one can rewrite its settings).
        """
        containing = containing or tree
        hits = []
        for form in _forms(path):
            fold = _folds(form) is not False
            ff = _fold(form, fold)
            below = ff.rstrip("/") + "/"
            for rx, rxi, aid, pattern, mode, ph, literal, exact in self.rules:
                r = rxi if fold else rx
                if ph == "repo":
                    hit = any(r.match(form[len(root) + 1:])
                              for root in _ancestors(form) if self._repo_root(root, fold))
                else:
                    hit = bool(r.match(form))
                inside = False
                if not hit and containing:
                    hit = inside = any(_fold(lit, fold).startswith(below)
                                       for _, lit in self._bases(form, ph, literal, fold, tree))
                if hit:
                    hits.append((mode, aid, pattern, form, inside))
        return hits

    def match_prefix(self, prefix):
        """Rules a file named `<prefix><anything without a slash>` could match (split, csplit)."""
        hits = []
        for form in _forms(prefix):
            fold = _folds(form) is not False
            ff = _fold(form, fold)
            for rx, rxi, aid, pattern, mode, ph, literal, exact in self.rules:
                for _, lit in self._bases(form, ph, literal, fold, True):
                    fl = _fold(lit, fold)
                    if exact:
                        hit = fl.startswith(ff) and len(fl) > len(ff) and "/" not in fl[len(ff):]
                    else:
                        hit = ff.startswith(fl) or (fl.startswith(ff) and "/" not in fl[len(ff):])
                    if hit:
                        hits.append((mode, aid, pattern, form, False))
                        break
        return hits

    def needles(self):
        """(regex, mode, pattern) — how a protected path can be NAMED in command text.

        Case-folded always: a name in text is evidence, not a path, and on a
        folding volume every spelling of it is the same file.
        """
        out = []
        seen = set()
        for aid, pattern in self.table:
            m = re.match(r"^\{(home|repo|plugin_root|worktree)\}/(.+)$", pattern)
            if not m:
                continue
            ph, tail = m.group(1), m.group(2)
            fixed = _fixed(tail).rstrip("/")
            if not fixed:
                continue
            if ph in ("home", "repo"):
                # `~/.claude/settings.json`, `$HOME/.gitconfig`, `/abs/home/.codex/config.toml`
                # and a repo-relative `.claude/settings.local.json` all carry the tail.
                key = (fixed, "deny")
                if key not in seen:
                    seen.add(key)
                    out.append((re.compile(r"(?<![A-Za-z0-9_.-])" + re.escape(fixed), re.IGNORECASE),
                                "deny", pattern))
            elif ph == "plugin_root":
                for root, mode in self.roots.get("plugin_root", []):
                    rx = re.compile(re.escape(root.rstrip("/") + "/" + fixed), re.IGNORECASE)
                    out.append((rx, mode, pattern))
                    # Relative to a cwd inside the plugin root: `hooks/lib/x`.
                    if any(c == root or c.startswith(root.rstrip("/") + "/") for c in self.cwd_forms):
                        suffix = "/" if tail.endswith("/**") else ""
                        out.append((re.compile(r"(?<![A-Za-z0-9_.-])" + re.escape(fixed + suffix),
                                               re.IGNORECASE), mode, pattern))
        return out


def _ancestors(form):
    """Every proper ancestor directory of an absolute path, `/` excluded."""
    parts = form.split("/")
    return ["/".join(parts[:i]) for i in range(2, len(parts))]


def _ln_symbolic(words):
    for w in words:
        v = w.value
        if v in ("--symbolic",):
            return True
        if v.startswith("-") and not v.startswith("--") and "s" in v[1:]:
            return True
    return False


def _cp_links(words):
    """cp -l/--link (hard) or -s/--symbolic-link: the copy is a link to its source."""
    for w in words:
        v = w.value
        if v in ("--link", "--symbolic-link"):
            return True
        if v.startswith("-") and not v.startswith("--") and ("l" in v[1:] or "s" in v[1:]):
            return True
    return False


def _source_records(argv0, words, cwd, fragment):
    """SOURCE records: the file a new link reaches (ln, link, cp -l/-s, pax -rwl,
    rsync --link-dest) and the file a move takes away (mv)."""
    base = os.path.basename(argv0)
    if base == "rsync":
        d = _flag_value(words, ("--link-dest",))
        if d is None:
            return []
        v = _static_value(d)
        path = _resolve(v, cwd) if v is not None else None
        return [("SOURCE", path, "ln:" + fragment)] if path else []
    if base == "pax":
        entries = _walk_options(words, PAX_SHORT_VALUE)
        names = set(n for n, _ in entries if n)
        ops = [v for n, v in entries if n is None]
        if not ("-r" in names and "-w" in names and "-l" in names) or len(ops) < 2:
            return []
        out = []
        for s in ops[:-1]:
            v = _static_value(s)
            path = _resolve(v, cwd) if v is not None else None
            out.append(("SOURCE", path, "ln:" + fragment) if path else
                       ("UNSURE", "pax -l of a source built by shell expansion (%s)" % s.value, fragment))
        return out
    if base == "cp" and _cp_links(words):
        kind = "ln"
    elif base in ("ln", "link", "mv"):
        kind = "ln" if base == "link" else base
    else:
        return []
    explicit_dir = _flag_value(words, ("-t", "--target-directory"))
    ops, unsure = _split_operands(words, base)
    if unsure or not ops:
        return []
    if explicit_dir is not None:
        sources, dest = ops, explicit_dir.value
    elif len(ops) >= 2:
        sources, dest = ops[:-1], ops[-1].value
    else:
        sources, dest = ops, "."
    out = []
    for s in sources:
        v = _static_value(s)
        if v is None:
            out.append(("UNSURE", "%s of a source built by shell expansion (%s)" % (base, s.value), fragment))
            continue
        p = os.path.expanduser(v)
        bases = [cwd] if cwd else []
        if base == "ln" and _ln_symbolic(words) and not os.path.isabs(p):
            # A relative symlink target resolves against the LINK's directory.
            d = os.path.expanduser(dest)
            if not os.path.isabs(d) and cwd:
                d = os.path.join(cwd, d)
            if os.path.isabs(d):
                bases.append(d if (len(sources) > 1 or os.path.isdir(d) or dest.endswith("/"))
                             else os.path.dirname(d))
        for b in ([None] if os.path.isabs(p) else bases):
            full = os.path.normpath(p if b is None else os.path.join(b, p))
            out.append(("SOURCE", full, "%s:%s" % (kind, fragment)))
    return out


# What an R4 ask adds to its reason, by why it is an ask and not a deny. A
# guard file of a plugin source checkout is editable with approval; a git
# replay (checkout, switch, restore, reset, merge, pull, rebase, cherry-pick,
# revert, am, stash) is how an integrator legitimately brings a branch's
# version of such a file in, so it is put to the user (hook_ask on Claude
# Code, a deny on every other host) rather than refused outright (D10.1).
SOURCE_CHECKOUT_ASK_TAIL = (" This plugin runs from a source checkout, so its guard files are editable, but only with "
                            "the user's explicit approval of this change.")
REPLAY_ASK_TAIL = (" A git branch operation brings in another commit's version of it, so it is put to the user "
                   "rather than refused: approve only if you meant this operation to change that file.")

# Kinds that never leave this module: they are consumed by protect().
INTERNAL_KINDS = ("SOURCE", "REPLAY", "PREFIX", "ANOMALY", "RAN")


def protect(records, payload):
    """The parse with PROTECTED <tab> deny|ask <tab> <why> records in front.

    One record per subject (a path, or a name found in unresolved command
    text): its deny if any rule denies it, else its ask. SOURCE, REPLAY, PREFIX,
    ANOMALY and RAN records are consumed here; every TARGET/DELETE/TREE whose
    realpath (spelled on disk) differs is repeated under it, so the other rules
    judge the file actually written too.
    """
    cwd = payload.get("cwd") or os.getcwd()
    prot = Protection(cwd)
    tool_input = payload.get("tool_input") or {}
    text = tool_input.get("command") if isinstance(tool_input.get("command"), str) else ""
    out = []
    verdicts = {}       # subject -> (mode, message), first deny wins over any ask
    order = []
    anomalies = []

    def flag(subject, mode, message):
        if subject not in verdicts:
            order.append(subject)
        elif verdicts[subject][0] == "deny" or mode != "deny":
            return
        verdicts[subject] = (mode, message)

    def flag_path(hits, path, why, fragment, replay=False):
        for mode, aid, pattern, form, inside in hits:
            resolved = "" if form == path else " (resolves to '%s')" % form
            via = " (via: %s)" % fragment if fragment else ""
            what = "it holds a path protected" if inside else "it is protected"
            # A git replay is an R4 ASK, never a silent allow: hook_ask puts it to
            # the user on Claude Code and is a deny on every other host (D8, D10.1).
            if replay:
                mode = "ask"
            tail = (REPLAY_ASK_TAIL if replay else SOURCE_CHECKOUT_ASK_TAIL) if mode == "ask" else ""
            flag(path, mode, "'%s'%s %s, and %s as %s (R4; matches %s).%s%s"
                 % (path, resolved, why, what, aid, pattern, via, tail))

    for kind, detail, fragment in records:
        if kind == "SOURCE":
            tool, _, via = fragment.partition(":")
            flag_path(prot.match(detail, containing=True), detail,
                      "would become reachable through a new link" if tool == "ln" else "would be moved away", via)
            continue
        if kind == "REPLAY":
            flag_path(prot.match(detail, containing=True), detail,
                      "would be rewritten from another commit, the index or a patch", fragment, replay=True)
            continue
        if kind == "PREFIX":
            flag_path(prot.match_prefix(detail), detail,
                      "names the files this command writes (prefix plus a suffix), and one of them can be a "
                      "protected path", fragment)
            continue
        if kind == "ANOMALY":
            anomalies.append(detail)
            continue
        if kind == "RAN":
            continue
        out.append((kind, detail, fragment))
        if kind in ("TARGET", "DELETE", "TREE"):
            why = {"TARGET": "would be written", "DELETE": "would be deleted",
                   "TREE": "would receive a whole directory tree (a copy, move or extraction), which can "
                           "land on a protected path inside it"}[kind]
            flag_path(prot.match(detail, containing=(kind != "TARGET"), tree=(kind == "TREE")),
                      detail, why, fragment)
            real = _canonical(detail)
            if real != detail:
                out.append((kind, real, fragment))
    unsure = any(k == "UNSURE" for k, _, _ in records)
    if text and (unsure or anomalies):
        for rx, mode, pattern in prot.needles():
            m = rx.search(text)
            if m:
                if anomalies and not unsure:
                    lead = ("this command uses shell syntax the parse does not follow (%s), and it names '%s'"
                            % ("; ".join(anomalies), m.group(0)))
                else:
                    lead = "a write this parse could not resolve names '%s'" % m.group(0)
                flag("name:" + m.group(0).casefold(), mode,
                     "%s, which matches %s; an unresolved write that names a protected path is treated as "
                     "a write to it.%s" % (lead, pattern, SOURCE_CHECKOUT_ASK_TAIL if mode == "ask" else ""))
    return [("PROTECTED",) + verdicts[s] for s in order] + out


def main():
    global PROTECTED_MODE
    args = sys.argv[1:]
    if args and args[0] in ("-h", "--help"):
        sys.stdout.write(__doc__)
        return 0
    PROTECTED_MODE = "--protected" in args
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except Exception:
        return 0
    if not isinstance(payload, dict):
        return 0
    try:
        records = records_for(payload)
    except Exception as exc:  # noqa: BLE001 - a parse failure must not go quiet
        records = [("UNSURE", "the write-target parser failed (%s: %s)" % (type(exc).__name__, exc), "")]
    if PROTECTED_MODE:
        try:
            records = protect(records, payload)
        except Exception as exc:  # noqa: BLE001 - fail closed: R4 paths cannot be cleared
            records = [("PROTECTED", "deny", "the protected-path check failed (%s: %s), so this "
                        "write cannot be cleared." % (type(exc).__name__, exc))] + \
                [r for r in records if r[0] not in INTERNAL_KINDS]
    else:
        # The records every other caller has always read: a tree is a target.
        records = [("TARGET" if k == "TREE" else k, d, f) for k, d, f in records
                   if k not in INTERNAL_KINDS]
    for kind, detail, fragment in records:
        sys.stdout.write("%s\t%s\t%s\n" % (kind, detail.replace("\t", " "), fragment.replace("\t", " ")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
