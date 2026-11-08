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
    command assigned a literal to in one bare top-level statement and otherwise
    only expands (`S=/tmp/x; cp a "$S/b"` — the whitelist under "Same-command
    literal assignments"), because the text answers the question and an
    advisory there is a silent pass of `"$S/package-lock.json"`. Silence would read as "no protected file
    touched" when the true answer is "could not determine" — the exact shape of
    failure this repo's `no silent or empty failure paths` rule forbids.

    UNSURE is deliberately NOT emitted for "any command could in principle
    write anything" (`make build`, `npm install`, `python3 script.py`). Taken
    that far the warning fires on everything and means nothing. The line drawn
    here is: the command is a write primitive whose target cannot be resolved,
    or it is an evaluator given code to run inline. Those are the shapes an
    agent reaches for when it edits a file through Bash; a build tool is not one
    of them, and the tool-level guard never claimed to cover it.

    Issue #405 adds the shapes that are the same thing one step removed, each
    UNSURE too: a command whose NAME is an unresolved expansion (`$CMD x f`),
    a runner this parse does not unwrap (`strace`, `ssh`, `docker run`, …), an
    environment variable whose value is a command (`GIT_EXTERNAL_DIFF=…`), and
    a file this same command writes and then runs (a heredoc Makefile and
    `make`, a script and `bash`/`source`/`./s.sh`, a conftest.py and `pytest`).
    The commands a `$(…)`, a backtick or a `<(…)`/`>(…)` runs are parsed as
    commands of their own, and write forms of otherwise read-only commands
    (`sort -o`, `git diff --output`, `git archive -o`, `git bundle create`,
    `git format-patch -o`, `git config --file`) are targets.

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

# ESC (0x1b) by chr(), so the table spells no numeric escape.
ANSI_C_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b",
                  "f": "\f", "v": "\v", "e": chr(0x1b), "E": chr(0x1b)}
CLOSERS = {"(": ")", "[": "]", "{": "}"}


class Tok(object):
    __slots__ = ("kind", "value", "expands", "quoted", "subs")

    def __init__(self, kind, value, expands=False, quoted=False, subs=None):
        self.kind = kind          # "word" | "op"
        self.value = value
        self.expands = expands    # contains an unquoted $ or ` — value is a guess
        self.quoted = quoted
        self.subs = subs or []    # the commands its substitutions run (issue #405)


# --------------------------------------------------------------------------
# Command substitutions (issue #405)
# --------------------------------------------------------------------------
# `$(…)`, backticks and `<(…)`/`>(…)` run commands of their own, before or
# beside the command that holds them. They used to be one opaque word, so
# `echo $(rm ~/.gitconfig)` wrote a protected file with no record at all. The
# tokenizer now keeps the TEXT of every command a word's substitutions run
# (Tok.subs), and analyze_command parses each one as a command in its own
# right. `${…}`, `$((…))`, `$[…]` and `((…))` are not commands, but their
# insides are expanded, so a substitution nested in one (`${X:-$(rm f)}`) is
# found too.

def _unbacktick(body, dquoted=False):
    """The command inside `…`: a backslash before \\, ` or $ (and " when the backtick is
    inside "…") stands for that character; anywhere else it stays, as bash keeps it."""
    return re.sub(r'\\([\\`$"])' if dquoted else r'\\([\\`$])', r"\1", body)


def _expansion_subs(text, note=None):
    """The command texts run by the substitutions in `text`: an expansion's inside, or an unquoted heredoc body.

    Quotes are not honoured here. Inside "…" or a heredoc an apostrophe is a
    literal, and reading one as a quote would hide `"it's $(rm f)"`; reading a
    quoted `'$(x)'` inside `${…}` as a command only over-reports.
    """
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == "$" and i + 1 < n and text[i + 1] in CLOSERS:
            end, closed = _balanced(text, i + 1, text[i + 1], CLOSERS[text[i + 1]])
            if not closed and note:
                note("an unterminated `$%s`" % text[i + 1])
            out.extend(_raw_subs(text[i:end], note))
            i = end
            continue
        if c == "`":
            j = i + 1
            while j < n and text[j] != "`":
                j += 2 if text[j] == "\\" else 1
            if j >= n and note:
                note("an unterminated backtick")
            out.append(_unbacktick(text[i + 1:j]))
            i = j + 1
            continue
        i += 1
    return out


def _is_arithmetic(text, start):
    """True when the `((` at text[start] is one arithmetic group: its inner `(` closes
    directly before the outer `)` (`$(( (1+2) * 3 ))`), not `((a);(b))`, a subshell."""
    if not text.startswith("((", start):
        return False
    outer, closed = _balanced(text, start)
    inner, closed_inner = _balanced(text, start + 1)
    return closed and closed_inner and inner == outer - 1


def _raw_subs(raw, note=None):
    """The command texts a raw `$(…)`, `$((…))`, `${…}` or `$[…]` runs."""
    if raw.startswith("$((") and raw.endswith("))") and _is_arithmetic(raw, 1):
        # One arithmetic group: bash commits to arithmetic here (`$((echo hi))` is
        # an arithmetic error, not a command), so only what is nested inside runs.
        # `$((a);(b))` is not one group, and bash runs it as a command.
        return _expansion_subs(raw[3:-2], note)
    if raw.startswith("$("):
        return [raw[2:-1] if raw.endswith(")") else raw[2:]]
    if raw[:2] in ("${", "$["):
        return _expansion_subs(raw[2:-1] if raw[-1:] in "}]" else raw[2:], note)
    return []


def _backtick_close(text, start):
    """The index of the ` closing the one at `start` (a backslash escapes one inside), or -1."""
    j = start + 1
    while j < len(text):
        if text[j] == "\\":
            j += 2
            continue
        if text[j] == "`":
            return j
        j += 1
    return -1


def _backtick_body(text, start, end, dquoted=False):
    """The command inside the backtick span text[start:end] (its closing ` may be missing)."""
    closed = end - start >= 2 and text[end - 1] == "`"
    return _unbacktick(text[start + 1:end - 1] if closed else text[start + 1:end], dquoted)


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


CASE_DELIMS = " \t\n;&|()<>"


def _scan_balanced(text, start, open_ch, close_ch, aware):
    depth = 0
    i = start
    n = len(text)
    pending = []
    # `case … in PAT) …;; esac` inside `$( … )`: the pattern's `)` is not a closer
    # (issue #405 review). One state per open case: "word" until `in`, then
    # "pattern" until its `)`, then "body" until `;;`/`;&`/`;;&` or `esac`.
    cases = []
    while i < n:
        c = text[i]
        if aware and open_ch == "(" and c.isalpha() and (i == start or text[i - 1] in CASE_DELIMS):
            j = i
            while j < n and (text[j].isalnum() or text[j] == "_"):
                j += 1
            word = text[i:j]
            if j >= n or text[j] in CASE_DELIMS:
                if word == "case":
                    cases.append("word")
                elif word == "in" and cases and cases[-1] == "word":
                    cases[-1] = "pattern"
                elif word == "esac" and cases and cases[-1] in ("pattern", "body"):
                    cases.pop()
            i = j
            continue
        if aware and cases and cases[-1] == "pattern" and c in "()":
            if c == ")":
                cases[-1] = "body"
            i += 1          # a pattern's own `(` opener and `)` closer
            continue
        if aware and cases and cases[-1] == "body" and text.startswith(";;", i):
            cases[-1] = "pattern"
            i += 3 if text.startswith(";;&", i) else 2
            continue
        if aware and cases and cases[-1] == "body" and text.startswith(";&", i):
            cases[-1] = "pattern"
            i += 2
            continue
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
                delim = re.sub(r"""['"\\]""", "", text[j:k])  # drop quotes and backslashes
                if delim:
                    pending.append((delim, strip, False))
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


def _read_heredocs(text, i, pending, heredocs, note, meta=None):
    """Consume the bodies of the `pending` heredocs from text[i]; return the index after them.

    `pending` holds (delimiter, strip_tabs, quoted). `meta`, when given, gets one
    (quoted, start, end) per body: whether its delimiter was quoted (a literal
    body, never expanded by the shell) and the span of the body in `text`.
    """
    n = len(text)
    for delim, strip_tabs, quoted in pending:
        lines = []
        closed = False
        start = end = i
        while i < n:
            end = i
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
            end = n
        if heredocs is not None:
            heredocs.append("\n".join(lines))
        if meta is not None:
            meta.append((quoted, start, end))
    return i


def tokenize(text, anomalies=None, heredocs=None, heredoc_meta=None):
    """Split a shell fragment into word and operator tokens.

    Heredoc bodies are skipped, never tokenized, and appended to `heredocs`
    (when given) in the order of their `<<`/`<<-` operators, tab-stripped for
    `<<-`; `heredoc_meta` (when given) gets their (quoted, start, end), see
    _read_heredocs. Constructs this cannot close are appended to `anomalies`.
    """
    toks = []
    buf = []
    subs = []           # the commands this word's substitutions run (issue #405)
    expands = False
    quoted = False
    started = False
    pending = []        # (delimiter, strip_tabs, quoted) whose bodies start at the next newline
    want = [None]       # strip_tabs of a `<<`/`<<-` still waiting for its delimiter word
    i = 0
    n = len(text)

    def note(why):
        if anomalies is not None and why not in anomalies:
            anomalies.append(why)

    def flush():
        if started:
            value = "".join(buf)
            toks.append(Tok("word", value, expands, quoted, list(subs)))
            if want[0] is not None:
                # A delimiter with any quoting (`'EOF'`, `"EOF"`) makes the body literal.
                # Only a plainly spelled one counts as such here: `$"X"` or `$'\x58'`
                # is X to bash but not to this tokenizer, so its "body" may be shell
                # code that bash runs (review of #402, round 7).
                plain = quoted and not expands and bool(re.match(r"^[A-Za-z0-9_.-]+$", value))
                pending.append((value, want[0], plain))
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
                    if nx in "$`\"\\":
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
                    subs.extend(_raw_subs(text[j:end], note))
                    expands = True
                    j = end
                    continue
                if c == "`":
                    end = _backtick_close(text, j)
                    if end == -1:
                        note("an unterminated backtick")
                    end = n if end == -1 else end + 1
                    buf.append(text[j:end])
                    subs.append(_backtick_body(text, j, end, True))
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
            del subs[:]
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
            subs.extend(_raw_subs(text[i:end], note))
            expands = True
            started = True
            i = end
            continue
        if ch == "`":
            end = _backtick_close(text, i)
            if end == -1:
                note("an unterminated backtick")
            end = n if end == -1 else end + 1
            buf.append(text[i:end])
            subs.append(_backtick_body(text, i, end))
            expands = True
            started = True
            i = end
            continue
        # `(( … ))` is an arithmetic command, where `<<` is a shift and `>` a
        # comparison. bash commits to arithmetic here (it does not fall back to
        # running the contents), so the whole thing is one opaque word.
        if ch == "(" and not started and _is_arithmetic(text, i):
            end, closed = _balanced(text, i)
            if closed and text[end - 2:end] == "))":
                toks.append(Tok("word", text[i:end], True, subs=_expansion_subs(text[i + 2:end - 2], note)))
                i = end
                continue
        # `>(…)` / `<(…)` — process substitution, a pipe rather than a file.
        if ch == "(" and toks and toks[-1].kind == "op" and toks[-1].value in ("<", ">", ">>"):
            end, closed = _balanced(text, i)
            if not closed:
                note("an unterminated process substitution")
            toks.append(Tok("word", text[i:end], True,
                            subs=[text[i + 1:end - 1] if closed else text[i + 1:end]]))
            i = end
            continue

        op = next((o for o in OPERATORS if text.startswith(o, i)), None)
        if op:
            flush()
            buf, expands, quoted, started = [], False, False, False
            del subs[:]
            if want[0] is not None:
                want[0] = None
                note("a `<<` with no delimiter word")
            toks.append(Tok("op", op))
            i += len(op)
            if op in ("<<", "<<-"):
                want[0] = op == "<<-"
            elif op == "\n" and pending:
                i = _read_heredocs(text, i, pending, heredocs, note, heredoc_meta)
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
        if heredoc_meta is not None:
            heredoc_meta.extend((q, n, n) for _, _, q in pending)
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
    # issue #405 review: more interpreters that take inline code or a program on stdin
    "fish", "csh", "tcsh", "xonsh", "nu", "elvish", "pwsh", "powershell", "lua", "luajit",
    "Rscript", "R", "julia", "groovy", "guile", "racket", "bb", "jshell", "ash", "mksh", "yash",
)
INLINE_CODE_FLAGS = ("-c", "-e", "-r", "--eval", "--command", "-E")

# Commands that run the command after them, which this parser does not unwrap.
UNMODELLED_RUNNERS = ("setsid", "ionice", "flock", "chrt", "taskset", "unbuffer", "caffeinate",
                      "doas", "su", "runuser", "chroot", "systemd-run", "sg", "prlimit",
                      "firejail", "sandbox-exec", "arch", "gtimeout", "busybox", "nsenter",
                      "unshare", "faketime", "torsocks", "proxychains", "proxychains4")

# Issue #405: more commands that run the command after them, found by the
# security reviews of #402 (`numactl cp x PROT`, `gdb -batch -ex 'shell …'`,
# `ssh h …`), and their close relatives. None of them is unwrapped: what they
# run is UNSURE, so a protected path named in the command fails closed.
UNMODELLED_RUNNERS += ("numactl", "fakeroot", "fakechroot", "strace", "ltrace", "valgrind",
                       "setpriv", "gdb", "lldb", "ssh", "pkexec", "xcrun", "dtruss", "catchsegv",
                       "xvfb-run", "dbus-run-session", "schroot", "bwrap", "proot", "nsjail",
                       "systemd-nspawn", "cgexec", "trickle", "rlwrap", "entr", "chpst",
                       "envdir", "setuidgid", "daemonize", "start-stop-daemon", "tmux", "screen",
                       "nix-shell", "npx", "bunx", "pnpx", "uvx", "pipx", "expect", "sshpass",
                       "dotenv", "with-contenv", "op", "aws-vault", "doppler", "infisical",
                       "chamber", "sops", "vagrant", "lima", "wsl", "gosu", "su-exec", "tini",
                       "dumb-init", "chronic", "ts", "tsp", "torify", "cpulimit", "taskpolicy",
                       "toybox", "socat", "s6-setuidgid", "s6-envdir", "setlock", "run0",
                       "machinectl", "flatpak-spawn", "env-cmd", "cross-env", "dotenvx",
                       "concurrently", "npm-run-all", "run-p", "run-s", "nodemon", "watchexec",
                       "reflex", "hyperfine", "perf", "dtrace", "heaptrack", "rr", "uftrace",
                       "bpftrace", "xterm", "nohup.exe", "winpty", "runuser")
# Commands that run another command only through one of these subcommands
# (`docker run img cp x PROT`); any word equal to one of them counts, since
# their own options come first and are not sized here.
SUBCOMMAND_RUNNERS = {
    "docker": ("run", "exec", "compose", "build", "buildx", "cp", "container", "debug"),
    "podman": ("run", "exec", "compose", "build", "cp", "container"),
    "nerdctl": ("run", "exec", "compose", "build", "cp"),
    "kubectl": ("exec", "run", "debug", "cp", "attach"),
    "nix": ("run", "shell", "develop"),
    "uv": ("run", "tool"), "poetry": ("run",), "pipenv": ("run",), "conda": ("run",),
    "mamba": ("run",), "micromamba": ("run",), "pixi": ("run", "exec"), "hatch": ("run",),
    "pdm": ("run",), "rye": ("run",), "bundle": ("exec",), "rbenv": ("exec",),
    "pyenv": ("exec",), "nodenv": ("exec",), "mise": ("exec", "x", "run"), "rtx": ("exec", "x"),
    "asdf": ("exec",), "direnv": ("exec",), "npm": ("exec", "x"), "pnpm": ("exec", "dlx"),
    "yarn": ("exec", "dlx"), "bun": ("x", "exec"), "deno": ("eval",), "launchctl": ("asuser", "submit", "bsexec"),
    "flatpak": ("run",), "snap": ("run",), "devcontainer": ("exec",), "limactl": ("shell",),
    "colima": ("ssh",), "multipass": ("exec",), "gcloud": ("ssh",), "heroku": ("run",),
    "ip": ("exec",),
}
RUNNER_WHY = "runs another command (`%s …`) whose writes this parse does not follow"

# Variables whose VALUE is a command line some program runs (`GIT_EXTERNAL_DIFF=tee
# git diff a PROT`, `PAGER='cp x PROT' git log`). Assigned in a prefix, through
# `env`, or by export/declare/typeset/local/readonly or a plain statement, the
# command it names is code this parse never reads. A value on HARMLESS_COMMANDS
# (`GIT_PAGER=cat`, `GIT_EDITOR=true`) runs nothing that writes.
CODE_VALUED_ENV = re.compile(
    r"^(?:GIT_EXTERNAL_DIFF|GIT_SSH|GIT_SSH_COMMAND|GIT_PAGER|PAGER|MANPAGER|SYSTEMD_PAGER|"
    r"GIT_EDITOR|EDITOR|VISUAL|GIT_SEQUENCE_EDITOR|GIT_ASKPASS|SSH_ASKPASS|SUDO_ASKPASS|"
    r"GIT_PROXY_COMMAND|LESSOPEN|LESSCLOSE|PROMPT_COMMAND|GIT_CONFIG_PARAMETERS|GIT_CONFIG_COUNT|"
    r"GIT_CONFIG_KEY_\d+|GIT_CONFIG_VALUE_\d+|BROWSER|GH_BROWSER|GH_PAGER|GH_EDITOR|"
    r"KUBE_EDITOR|DIFF_COMMAND|RSYNC_RSH|RSYNC_CONNECT_PROG|CVS_RSH)\+?=(.*)$", re.S)
HARMLESS_COMMANDS = ("", "cat", "less", "more", "true", "false", ":", "/bin/cat", "/usr/bin/cat",
                     "/bin/true", "/usr/bin/true", "/bin/false", "/usr/bin/false", "less -R",
                     "less -FRX", "less -FX", "less -r", "head", "tail", "0", "1")
CODE_ENV_WHY = ("runs under %s, a variable whose value is a command some program runs; that "
                "command's writes are not parsed")
# Variables that make a program load code from a FILE or a directory (PATH,
# LD_PRELOAD, PYTHONPATH, BASH_ENV, git's config and exec paths, HOME for the
# config files read from it). Set beside a write in the same command, the
# written file can be the code that runs: see "Write, then run" below.
FILE_LOADING_ENV = re.compile(
    r"^(?:PATH|LD_PRELOAD|LD_LIBRARY_PATH|LD_AUDIT|DYLD_INSERT_LIBRARIES|DYLD_LIBRARY_PATH|"
    r"DYLD_FRAMEWORK_PATH|DYLD_FALLBACK_LIBRARY_PATH|PYTHONPATH|PYTHONSTARTUP|PYTHONHOME|"
    r"PYTHONUSERBASE|PYTHONSAFEPATH|NODE_PATH|NODE_OPTIONS|PERL5LIB|PERLLIB|PERL5OPT|RUBYLIB|"
    r"RUBYOPT|GEM_HOME|GEM_PATH|BASH_ENV|ENV|ZDOTDIR|GIT_CONFIG|GIT_CONFIG_GLOBAL|"
    r"GIT_CONFIG_SYSTEM|GIT_EXEC_PATH|GIT_TEMPLATE_DIR|GIT_DIR|GIT_WORK_TREE|HOME|"
    r"XDG_CONFIG_HOME|npm_config_\w+|NPM_CONFIG_\w+|PIP_\w+)\+?=", re.I)
ASSIGNING_BUILTINS = ("export", "declare", "typeset", "local", "readonly")
ASSIGNMENT_WORD = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\+?=")


def _code_env(word):
    """CODE_ENV_WHY for an assignment word naming a command a program runs, else None."""
    m = CODE_VALUED_ENV.match(word)
    if not m:
        return None
    if word.startswith(("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_", "GIT_CONFIG_COUNT",
                        "GIT_CONFIG_PARAMETERS")):
        return CODE_ENV_WHY % word.split("=", 1)[0].rstrip("+")
    if m.group(1).strip() in HARMLESS_COMMANDS:
        return None
    return CODE_ENV_WHY % word.split("=", 1)[0].rstrip("+")


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
FIND_ACTION_WHY = "runs an action per match; the affected paths are decided at runtime"
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


def _sed_inplace(words):
    """`_has_inplace`, plus BSD/macOS sed's `-I` (in place, without `-s`), e.g. `-I ''`, `-I.bak`,
    and GNU's abbreviations of `--in-place` (`--in`, `--in-pl=.bak`)."""
    if _has_inplace(words):
        return True
    for w in words:
        v = w.value
        name = v.split("=", 1)[0]
        if name.startswith("--") and len(name) > 2 and "--in-place".startswith(name):
            return True
        if v.startswith("-") and not v.startswith("--"):
            body = v[1:].split(".", 1)[0]
            if "I" in body and body.replace("I", "").isalpha() or body == "I":
                return True
    return False


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
# So analyze_command keeps ASSIGNS, NAME -> literal value, and _static_value
# substitutes `$NAME`/`${NAME}` from it. Resolving only ever turns an advisory
# into a checked path, and a checked path into a block; what the table cannot
# answer is UNSURE exactly as before.
#
# WHICH NAMES MAY RESOLVE — a whitelist, not a list of mutations
#   Three review rounds on PR #359 each found a form that changed a variable
#   behind the table's back (`if false; then :; S=/tmp; fi`,
#   `export S=/tmp > "$S/w"`, `export S=/tmp T="$S"`, `S[0]=.github`), and a
#   table that forgets the forms it knows is only as safe as that list. So the
#   rule is stated the other way round, as what MUST hold of the whole command
#   text for a name to resolve at all (_resolvable_names):
#     - the identifier NAME occurs exactly once as `NAME=`: followed by `=`
#       and not `==`, and the FIRST word of its statement — preceded only by
#       the start of the text, a `;` or a newline, and whitespace
#       (_statement_start). A backslash (`\S=/tmp` runs a command named
#       S=/tmp), a quote, `{`, `(`, `&&`, a reserved word or any other word
#       before it disqualifies the name (issue #363);
#     - every other occurrence of NAME on a word boundary, anywhere in the raw
#       text — quotes, heredoc bodies and comments included — is a plain
#       `$NAME` (not followed by `[`) or `${NAME}` expansion;
#     - the text names no evaluator that can assign anything: `eval`,
#       `source`, `.`, `exec`, or a shell handed `-c`.
#   A `NAME[`, `NAME+=`, a second `NAME=`, `${NAME:=…}`, `${NAME[`, `${!NAME}`,
#   `${#NAME}`, NAME as an argument to anything (`read`, `for`, `unset`,
#   `declare -n R=`, `printf -v`, `mapfile`, `getopts`, `let`) and NAME inside
#   `(( ))` each put a bare occurrence in the text, so none of them has to be
#   known by name. A name that could change is never admitted, so nothing is
#   ever forgotten or restored.
#
#   The one `NAME=` must then be a statement of the shell's own
#   (_track_assignments): a bare `NAME=<literal>` at compound depth 0 — an
#   `if`…`fi`, a loop, `case`…`esac`, `{`…`}`, `(`…`)` and a function body
#   all count, across the whole command (_scope_update) — not in a pipeline
#   component or a background job, not after `&&`/`||`, not led by a
#   reserved word, with no command after it (the `NAME=value cmd` prefix is
#   the command's environment, not the shell's) and under no builtin
#   (`export`, `declare`, … expand all their operands before assigning any).
#   The value is a literal in the tokenizer's sense, or one whose only
#   expansions are `$HOME` and names already admitted.
#
#   A redirection is opened before its command runs, so it resolves under the
#   table as it stood before that command's own assignments
#   (_segment_records' `before`). An unquoted use whose value would word-split
#   is not substituted, and one that would glob is reported as a glob by
#   _record_targets as before.
ASSIGNS = {}
RESOLVABLE = set()
# Issue #405: a NAME=literal that follows `&&` holds for the rest of that
# and-list only (`cd d && H=/x/h.sh && $H emit …`: the run cannot happen
# unless the assignment did). Kept apart from ASSIGNS, which never forgets,
# and read only to name the command a segment runs (_segment_records).
CHAIN_ASSIGNS = {}
CHAIN_NAMES = set()
_NAME = r"[A-Za-z_][A-Za-z0-9_]*"
ASSIGN_WORD = re.compile(r"^(%s)(\+?=)(.*)$" % _NAME, re.S)
VAR_REF = re.compile(r"\$(?:\{(%s)\}|(%s))" % (_NAME, _NAME))
ASSIGN_SITE = re.compile(r"(?<![A-Za-z0-9_${])(%s)=(?!=)" % _NAME)
# An evaluator the text could hand an assignment to, in any position at all.
FORBIDS_RESOLUTION = re.compile(
    r"(?<![A-Za-z0-9_.-])(?:eval|source|exec)(?![A-Za-z0-9_.-])"
    r"|(?:^|[\s;&|(){}])\.(?=\s)"
    r"|(?<![A-Za-z0-9_.-])(?:bash|sh|zsh|dash|ksh)\s+(?:-\S+\s+)*-[A-Za-z]*c(?![A-Za-z0-9])",
    re.M)
# Reserved words in command position. Openers and closers move the compound
# depth; the rest are passed over to reach the command they introduce.
SCOPE_OPENERS = ("if", "while", "until", "for", "select", "case", "{")
SCOPE_CLOSERS = ("fi", "done", "esac", "}")
NEUTRAL_KEYWORDS = ("then", "elif", "else", "do", "in", "!", "time", "function", "coproc")
ALL_KEYWORDS = SCOPE_OPENERS + SCOPE_CLOSERS + NEUTRAL_KEYWORDS
# The reserved words a command can directly follow in one segment. `for`,
# `select`, `case` and `function` are followed by a name, not a command.
COMMAND_INTRODUCERS = ("if", "then", "elif", "else", "while", "until", "do", "{", "!", "coproc")


# Names bash sets or reads on its own, with no assignment in the text — so the
# whitelist's "exactly one `NAME=`" proves nothing about them: `read` with no
# operand sets REPLY, `cd` sets PWD and OLDPWD, `getopts` sets OPTARG/OPTIND,
# `mapfile` with no operand fills MAPFILE, a pipeline sets PIPESTATUS, and
# RANDOM, SECONDS, LINENO and the like change on every reference (Codex,
# PR #359). The closed list is the Bash Reference Manual, section 5 "Shell
# Variables" (5.1 "Bourne Shell Variables", 5.2 "Bash Variables"), as read at
# bash 5.2: every variable there that the shell assigns, updates or special-
# cases, plus the prefixes it reserves (BASH*, COMP*, READLINE*, HIST*, LC_*)
# and `_`. A user who shadows one of these gets UNSURE, as before this table.
SHELL_MANAGED_NAMES = frozenset((
    "REPLY", "PWD", "OLDPWD", "RANDOM", "SRANDOM", "SECONDS", "LINENO", "HISTCMD",
    "OPTARG", "OPTIND", "OPTERR", "PIPESTATUS", "SHLVL", "UID", "EUID", "PPID",
    "BASHPID", "FUNCNAME", "GROUPS", "DIRSTACK", "MAPFILE", "COPROC",
    "EPOCHSECONDS", "EPOCHREALTIME", "HOSTNAME", "HOSTTYPE", "MACHTYPE", "OSTYPE",
    "IFS", "PATH", "HOME", "CDPATH", "PS0", "PS1", "PS2", "PS3", "PS4",
    "PROMPT_COMMAND", "PROMPT_DIRTRIM", "TMPDIR", "MAIL", "MAILPATH", "MAILCHECK",
    "ENV", "EXECIGNORE", "FIGNORE", "GLOBIGNORE", "GLOBSORT", "IGNOREEOF",
    "INPUTRC", "INSIDE_EMACS", "EMACS", "LANG", "LINES", "COLUMNS", "POSIXLY_CORRECT",
    "SHELL", "SHELLOPTS", "TIMEFORMAT", "TMOUT", "auto_resume", "histchars", "CHILD_MAX",
    "_",
))
SHELL_MANAGED_PREFIXES = ("BASH", "COMP", "READLINE", "HIST", "LC_")


def _shell_managed(name):
    return name in SHELL_MANAGED_NAMES or name.startswith(SHELL_MANAGED_PREFIXES)


def _statement_start(text, pos):
    """True when text[pos] begins a statement: only whitespace since the start, a `;` or a newline.

    The one admitted `NAME=` must be the FIRST word of its statement. Anything
    else before it on the line — a backslash (`\\S=/tmp` runs a command named
    S=/tmp), a quote, `{`, `(`, `&&`, `|`, a reserved word (`if`, `then`,
    `do`, `coproc`, `time`, `!`), another word — means bash does not read it
    as the shell's own assignment, or runs it somewhere the parent never
    sees (issue #363). Whether that statement is also at compound depth 0 is
    _track_assignments' half of the rule.
    """
    i = pos
    while i > 0 and text[i - 1] in " \t":
        i -= 1
    return i == 0 or text[i - 1] in ";\n"


def _after_and(text, pos):
    """True when text[pos] directly follows `&&` (whitespace aside): `cd d && H=/x/h.sh && $H …`."""
    i = pos
    while i > 0 and text[i - 1] in " \t":
        i -= 1
    return text[i - 2:i] == "&&" and text[i - 3:i - 2] != "&"


def _resolvable_names(text, shell_text=None, after_and=False):
    """The names the whole command text allows to resolve (the rule above).

    `shell_text` is the text with its quoted heredoc bodies cut out: such a body
    is literal data the parent shell never parses, so a `D` or a `). ` in an
    issue body does not make `D=/tmp/x` unresolvable (issue #402). The only
    ways this shell could run a body — `source`, `.`, `eval` — are commands,
    so they are in `shell_text` and still forbid resolution; and
    `read D <<'EOF'` names `D` outside the body. A heredoc inside `$( … )` is
    not cut (the tokenizer never sees it as a body).
    """
    if shell_text is not None:
        text = shell_text
    if FORBIDS_RESOLUTION.search(text):
        return set()
    out = set()
    for name in set(m.group(1) for m in ASSIGN_SITE.finditer(text)):
        if _shell_managed(name):
            continue
        sites = 0
        clean = True
        for m in re.finditer(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(name), text):
            s, e = m.start(), m.end()
            before = text[s - 1] if s else ""
            before2 = text[s - 2:s] if s >= 2 else ""
            after = text[e] if e < len(text) else ""
            if before == "$" and after != "[":
                continue                                    # $NAME
            if before2 == "${" and after == "}":
                continue                                    # ${NAME}
            if after == "=" and text[e:e + 2] != "==" and (
                    _after_and(text, s) if after_and else _statement_start(text, s)):
                sites += 1                                  # NAME=, first word of its statement
                continue
            clean = False
            break
        if clean and sites == 1:
            out.add(name)
    return out


def _scope_update(seg, scope, cwd, terminator):
    """Apply a segment's leading reserved words to the open compound frames.

    Returns (depth, own, cwd): the compound depth this segment's own commands
    run at, 1 when they are a `coproc` statement's own command, and the cwd
    after any body closed here was accounted for. `{ S=/tmp` opens before
    the assignment is read and `fi` closes before the next command. A quoted
    word is never reserved. Unbalanced closers stop at zero.

    Each frame remembers the cwd it opened with and whether its body is a
    SUBSHELL (a coproc body, or a `{ … }`/`if`/loop that `}`/`fi`/`done`
    turns out to end with `&` or `|`): a `cd` inside such a body never moved
    the parent, so the cwd is restored at the closer (Codex, PR #364). A body
    that ran in the parent keeps whatever its `cd`s produced — the cwd a
    conditional body leaves is already None, see analyze_command.
    """
    words = [t for t in seg if t.kind == "word"]
    frames = scope["frames"]
    i = 0
    own = 0
    subshell_next = False
    fn_next = scope.pop("fn_pending", False)
    while i < len(words):
        w = words[i].value
        if words[i].quoted:
            break
        if w in SCOPE_OPENERS:
            kind = "function" if fn_next else w
            frames.append({"kind": kind, "cwd": cwd, "subshell": subshell_next})
            if subshell_next:
                own = 0     # `coproc { … }`: the body frame governs, not the statement
            subshell_next = fn_next = False
        elif w in SCOPE_CLOSERS:
            frame = frames.pop() if frames else None
            if frame and (frame["subshell"] or terminator in ("&", "|")):
                cwd = frame["cwd"]
        elif w == "function":
            fn_next = True
            i += 1      # `function NAME` — the name is not a command
        elif w == "coproc":
            # `coproc cmd`, `coproc { … }`, `coproc NAME { … }`: the coprocess
            # is a subshell, so the rest of this statement runs at depth > 0
            # and a `{`/compound body that follows opens on top of that
            # (issue #363). The optional NAME is the word before a `{` or an
            # opener keyword; `(` is a separator, so it is never a word here.
            own = 1
            subshell_next = True
            if (i + 2 < len(words) and not words[i + 1].quoted
                    and words[i + 1].value not in ALL_KEYWORDS
                    and words[i + 2].value in SCOPE_OPENERS):
                i += 1
        elif w not in NEUTRAL_KEYWORDS:
            break
        i += 1
    if fn_next:
        scope["fn_pending"] = True      # `function NAME` with its `{` on the next line
    return len(frames) + own, own, cwd


def _cd_mode(scope, own, terminator, prev_terminator):
    """How a `cd`/`pushd`/`popd` in this segment reaches the parent shell's cwd.

    "ignore"  — it runs in a subshell the parent never sees: a coproc
                statement, a background job (`cd /tmp &`), a pipeline
                component (judged in _segment_records), a `( … )` group
                (restored by analyze_command's cwd stack);
    "unknown" — it runs in the parent but maybe not, or later: an `if`,
                loop or case body, a function body, after `&&`/`||`. The
                tracked cwd becomes None, so every later relative write is
                UNSURE rather than judged against a directory that may be
                wrong in either direction;
    "apply"   — bash itself would move the parent's cwd: top level, or a
                brace group that runs in the parent.
    """
    if own or terminator == "&":
        return "ignore"
    if prev_terminator in ("&&", "||") or any(f["kind"] != "{" for f in scope["frames"]):
        return "unknown"
    return "apply"


def _track_assignments(words, piped_in, terminator, conditional):
    """Admit this segment's bare top-level literal assignments to ASSIGNS.

    `conditional` is true at compound depth > 0 or after `&&`/`||`. Only a
    name in RESOLVABLE is ever admitted, and nothing is ever removed.
    """
    if conditional or piped_in or terminator in ("|", "&") or not words:
        return
    # A quoted reserved word is a command, not a keyword. (A quoted NAME,
    # `"S=/x"`, is a command too, not an assignment; the tokenizer flags both
    # `"S=/x"` and `S="/x"` as quoted, so _resolvable_names tells them apart
    # on the raw text: a name preceded by a quote is never admitted.)
    if not words[0].quoted and words[0].value in ALL_KEYWORDS:
        return
    rest = list(words)
    leading = []
    while rest and ASSIGN_WORD.match(rest[0].value):
        leading.append(rest.pop(0))
    if rest:
        return      # `NAME=value cmd`, or a builtin's operands: not the shell's own statement
    for tok in leading:
        name, op, value = ASSIGN_WORD.match(tok.value).groups()
        if op != "=" or name not in RESOLVABLE:
            continue
        # `S=(a b)`: the tokenizer stops the word at the `(`, so the value
        # reads as empty; an array is not a path.
        if terminator == "(" and tok is leading[-1] and value == "":
            continue
        lit = _static_value(Tok("word", value, tok.expands, tok.quoted))
        if lit is not None:
            ASSIGNS[name] = lit


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
    session HOME `~` already expands to, and both are protected homes — and
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
        nxt = words[idx + 1].value if idx + 1 < len(words) else None
        name, eq, val = v.partition("=")
        if v == "--":
            break
        if name.startswith("--") and len(name) > 2 and "--expression".startswith(name):
            # `--expression`, and the abbreviations getopt_long accepts (`--exp=`)
            if eq:
                scripts.append(val)
            elif nxt is not None:
                scripts.append(nxt)
            given = True
        elif name.startswith("--") and len(name) > 2 and "--file".startswith(name):
            given = True
        elif v.startswith("-") and not v.startswith("--") and len(v) > 1:
            # A short cluster: `-e S`, `-ne S`, `-nes S`… `-e` takes the rest of the
            # word or the next one; `-f` likewise; `-i`/`-I`/`-l` end the cluster.
            for k, ch in enumerate(v[1:], 1):
                if ch == "e":
                    rest = v[k + 1:]
                    if rest:
                        scripts.append(rest)
                    elif nxt is not None:
                        scripts.append(nxt)
                    given = True
                    break
                if ch == "f":
                    given = True
                    break
                if ch in "iIl":
                    break
    if not given:
        ops = _operands(words, "sed")
        if ops:
            scripts.append(ops[0].value)
    return scripts


def _sed_writes(script):
    """True when a sed script writes a file (`w`, `W`, `s///w`) or runs one (`e`, `s///e`)."""
    i = 0
    n = len(script)

    def past(i, delim, regex=True):
        """Index just past the closing `delim`. Only in a REGEX field (an address,
        an `s` pattern) is `[` a bracket expression; in an `s` replacement or a
        `y` string it is a literal character (Codex review of PR #408)."""
        while i < n:
            c = script[i]
            if c == "\\":
                i += 2
                continue
            if c == "[" and regex:
                # A bracket expression: its `]` closes it, and a `/` inside it is
                # a character, not the end of the regex (`/[/]/w f`).
                j = i + 1
                if j < n and script[j] == "^":
                    j += 1
                if j < n and script[j] == "]":
                    j += 1
                while j < n and script[j] != "]":
                    if script[j:j + 2] in ("[:", "[.", "[="):
                        # a class `[:alpha:]`, collating `[.x.]` or equivalence `[=e=]`
                        close = script.find(script[j + 1] + "]", j + 2)
                        j = n if close == -1 else close + 2
                        continue
                    j += 1
                i = j + 1
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
            # `s`: regex pattern, literal replacement; `y`: two literal strings.
            i = past(past(i + 2, d, regex=(c == "s")), d, regex=False)
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


# find's own write actions, and the commands an -exec/-execdir may run without
# making the find a write (issue #402: `find <dir> -exec ls -l {} \;`).
FIND_WRITES = ("-delete", "-fprint", "-fprint0", "-fprintf", "-fls")
FIND_PRINTS = ("-fprint", "-fprint0", "-fprintf", "-fls")
FIND_EXECS = ("-exec", "-execdir", "-ok", "-okdir")
FIND_EXEC_READ_ONLY = ("ls", "stat", "wc", "head", "tail", "cat", "grep", "egrep", "fgrep",
                       "md5", "md5sum", "shasum", "sha1sum", "sha256sum", "sha512sum", "cksum",
                       "du", "readlink", "realpath", "basename", "dirname", "echo", "test", "[",
                       "diff", "cmp", "jq")


def _find_unsure(words):
    """FIND_ACTION_WHY unless every action of this find only reads."""
    i = 0
    while i < len(words):
        v = words[i].value
        if v in FIND_WRITES or v in ("-ok", "-okdir"):
            return FIND_ACTION_WHY
        if v in FIND_EXECS:
            j = i + 1
            while j < len(words) and words[j].value not in (";", "+"):
                j += 1
            argv = words[i + 1:j]
            if j >= len(words) or not argv or any(w.expands for w in argv):
                return FIND_ACTION_WHY
            base = argv[0].value
            rest = [w.value for w in argv[1:] if w.value != "{}"]
            if base not in FIND_EXEC_READ_ONLY:
                return FIND_ACTION_WHY      # a path (`/tmp/x/ls`) is not the command listed
            i = j + 1
            continue
        i += 1
    return None


# Options that take the NEXT word. GNU's -e/-l/-i and --eof/--replace/--max-lines
# take an OPTIONAL value, attached only (`-l1`, `--replace={}`): bare, they take
# nothing, so they are flags here (reading `xargs -l rm ls` as `-l rm` would
# judge `ls` and miss the `rm` — review of #402).
XARGS_VALUE = ("-I", "-n", "-L", "-P", "-s", "-d", "-a", "-E", "--max-args", "--max-procs",
               "--delimiter", "--arg-file", "--max-chars", "--process-slot-var")
XARGS_FLAG = ("-0", "-r", "-t", "-p", "-x", "-o", "-e", "-l", "-i", "--null",
              "--no-run-if-empty", "--verbose", "--interactive", "--exit", "--open-tty",
              "--eof", "--replace", "--max-lines")


def _xargs_read_only(words):
    """True for `xargs [opts] CMD …` whose CMD is one find -exec may run (issue #402).

    The items xargs reads become CMD's arguments, so CMD must stay read-only
    whatever they are: every command on FIND_EXEC_READ_ONLY does. An option
    this does not know, or a CMD built by expansion, keeps xargs a dispatcher.
    """
    i = 0
    while i < len(words):
        v = words[i].value
        if v == "--":
            i += 1
            break
        if not v.startswith("-") or v == "-":
            break
        name = v.split("=", 1)[0]
        if v in XARGS_FLAG or (name in ("--eof", "--replace", "--max-lines") and "=" in v):
            i += 1
        elif v in XARGS_VALUE:
            i += 2
        elif name in XARGS_VALUE and name.startswith("--") and "=" in v:
            i += 1
        elif v[:2] in ("-I", "-n", "-L", "-P", "-s", "-d", "-a", "-E", "-e", "-l", "-i") \
                and len(v) > 2:
            i += 1          # an attached short value: -n1, -I{}, -P4, -l1
        else:
            return False
    if i >= len(words) or any(w.expands for w in words[i:]):
        return False
    base = os.path.basename(words[i].value)
    if "/" in words[i].value or base not in FIND_EXEC_READ_ONLY:
        return False
    return True


def _find_roots(words, cwd):
    """The starting points of a find (before its first expression), resolved; None if unknown."""
    i = 0
    while i < len(words) and words[i].value in ("-H", "-L", "-P", "-E", "-X", "-d", "-s", "-x"):
        i += 1
    roots = []
    while i < len(words):
        v = words[i].value
        if v.startswith("-") or v in ("(", "!", ")"):
            break
        roots.append(words[i])
        i += 1
    if not roots:
        return [cwd] if cwd else None
    out = []
    for t in roots:
        value = _static_value(t)
        path = _resolve(value, cwd) if value is not None else None
        if path is None:
            return None
        out.append(path)
    return out


# sort's options that take a value (issue #405: `sort -o PROT f` is a write).
SORT_SHORT_VALUE = "ktSTo"
SORT_LONG_VALUE = ("batch-size", "compress-program", "files0-from", "key", "output",
                   "random-source", "sort", "buffer-size", "field-separator",
                   "temporary-directory", "parallel")
SORT_LONG_FLAG = ("ignore-leading-blanks", "debug", "dictionary-order", "ignore-case",
                  "general-numeric-sort", "ignore-nonprinting", "human-numeric-sort", "month-sort",
                  "numeric-sort", "random-sort", "reverse", "version-sort", "check", "merge",
                  "stable", "unique", "zero-terminated", "help", "version")


def _sort_targets(words):
    """([(token, "TARGET")], unsure) for sort: -o/--output (any unambiguous prefix), and
    --compress-program, which runs a program."""
    out = []
    unsure = None
    i = 0
    while i < len(words):
        w = words[i]
        v = w.value
        if v == "--":
            break
        if v.startswith("--") and len(v) > 2:
            name, eq, val = v.partition("=")
            stem = name[2:]
            values = [o for o in SORT_LONG_VALUE if o.startswith(stem)]
            flags = [o for o in SORT_LONG_FLAG if o.startswith(stem)]
            if "output".startswith(stem):
                # A prefix of --output, even an ambiguous one: reporting it costs nothing.
                tok = Tok("word", val, w.expands, w.quoted) if eq else (
                    words[i + 1] if i + 1 < len(words) else None)
                if tok is not None:
                    out.append((tok, "TARGET"))
            if len(stem) >= 2 and "compress-program".startswith(stem):
                unsure = PROGRAM_WHY
            # The next word is this option's value only when the prefix names
            # value options and no flag (getopt_long; an ambiguous one is an error).
            i += 2 if (not eq and values and not flags) else 1
            continue
        if v.startswith("-") and len(v) > 1:
            body = v[1:]
            for k, c in enumerate(body):
                if c in SORT_SHORT_VALUE:
                    tail = body[k + 1:]
                    tok = Tok("word", tail, w.expands, w.quoted) if tail else (
                        words[i + 1] if i + 1 < len(words) else None)
                    if c == "o" and tok is not None:
                        out.append((tok, "TARGET"))
                    if not tail:
                        i += 1
                    break
        i += 1
    return out, unsure


def _make_unsure(words, fed_code):
    """Why a make runs code this parse does not read: --eval/-E, a makefile fed on
    stdin, or a NAME=value its recipes expand (issue #405). None otherwise."""
    i = 0
    while i < len(words):
        v = words[i].value
        if v == "--":
            break
        if v in ("--eval", "-E") or v.startswith(("--eval=", "--ev")) or (
                v.startswith("-E") and not v.startswith("--")):
            return EVAL_WHY
        if v in ("-f", "--file", "--makefile") or v.startswith(("--file=", "--makefile=")) or (
                v.startswith("-f") and not v.startswith("--") and len(v) > 2):
            val = v.split("=", 1)[1] if "=" in v and v.startswith("--") else (
                v[2:] if len(v) > 2 and not v.startswith("--") else
                (words[i + 1].value if i + 1 < len(words) else ""))
            if val in ("-", "/dev/stdin", "/dev/fd/0") or val.startswith(("/dev/fd/", "/proc/")):
                if fed_code or val != "-":
                    return EVAL_WHY
        if ASSIGNMENT_WORD.match(v):
            return ("passes make a variable (%s) that its recipes expand as part of the commands "
                    "they run" % v.split("=", 1)[0])
        i += 1
    return None


CC_FAMILY = ("cc", "gcc", "g++", "c++", "clang", "clang++", "ld", "rustc", "swiftc", "tcc", "zig")
SSH_KEYGEN_READS = "lyFeiBLQD"


def _more_write_forms(base, words):
    """([(token, kind)], unsure) for other commands' write options (issue #405 review), or None."""
    if base == "uniq":
        ops = [t for f, t in _walk_options(words, "fsw", ("--skip-fields", "--skip-chars", "--check-chars",
                                                            "--group", "--all-repeated")) if f is None]
        return [(t, "TARGET") for t in ops[1:2]], None
    if base in ("shuf", "gpg", "gpg2"):
        out = _flag_value(words, ("-o", "--output"))
        return ([(out, "TARGET")] if out is not None else []), None
    if base == "openssl":
        return [(words[i + 1], "TARGET") for i, w in enumerate(words[:-1])
                if w.value in ("-out", "-keyout")], None
    if base in CC_FAMILY or (base == "go" and any(w.value == "build" for w in words)):
        out = _flag_value(words, ("-o",))
        return ([(out, "TARGET")] if out is not None else []), None
    if base == "mkfifo":
        return [(t, "TARGET") for t in _operands(words)], None
    if base == "mknod":
        return [(t, "TARGET") for t in _operands(words)[:1]], None
    if base in ("trash", "trash-put", "rmtrash"):
        return [(t, "DELETE") for t in _operands(words)], None
    if base == "scp":
        ops = []
        unsure = None
        for f, t in _walk_options(words, "cFiJlLoPSX", ()):
            if f is None:
                ops.append(t)
            elif f == "-S":
                unsure = RUNNER_WHY % "scp -S"
        dest = ops[-1:] if len(ops) >= 2 else []
        local = [t for t in dest if not re.match(r"^[^/]*:", t.value)]
        return [(t, "TREE") for t in local], unsure
    if base == "ssh-keygen":
        flags = "".join(w.value[1:] for w in words if w.value.startswith("-") and not w.value.startswith("--"))
        out = _flag_value(words, ("-f",))
        if out is None or any(c in flags for c in SSH_KEYGEN_READS):
            return [], None
        return [(out, "TARGET"), (Tok("word", out.value + ".pub", out.expands, out.quoted), "TARGET")], None
    return None


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
    # `source`/`.` run a file in THIS shell. Fed a heredoc, a pipe, a `<` or a
    # process substitution (`. <(…)`), or pointed at /dev or /proc, they run
    # code this parse never sees; a named file is a named script, as `bash f` is.
    if base in ("source", "."):
        ops = _operands(words)
        first = _static_value(ops[0]) if ops else None
        if fed_code or not ops or ops[0].value.startswith("(") or first == "-" or (
                first and re.match(r"^/(?:dev|proc)(?:/|$)", os.path.normpath(first))):
            return [], EVAL_WHY
    if base in DISPATCHERS and not (base == "xargs" and _xargs_read_only(words)):
        return [], "builds and runs another command at runtime"
    if base in UNMODELLED_RUNNERS:
        return [], RUNNER_WHY % base
    if base in SUBCOMMAND_RUNNERS and any(
            w.value in SUBCOMMAND_RUNNERS[base] for w in words):
        return [], RUNNER_WHY % base
    if base in ("at", "batch"):
        return [], EVAL_WHY     # schedules the commands it reads from stdin or -f
    if base in ("alias", "hash", "enable") and any(
            "=" in w.value or w.value.startswith(("-p", "-f")) for w in words):
        # `alias x='cp a PROT'; x`, `hash -p /tmp/w ls`, `enable -f lib.so x`: a
        # command name now runs code this parse never reads (issue #405).
        return [], EVAL_WHY
    if base in ("make", "gmake", "bmake"):
        why = _make_unsure(words, fed_code)
        if why:
            return [], why
    if base in ("sort", "gsort"):
        return _sort_targets(words)
    if base == "find":
        why = _find_unsure(words)
        if why:
            return [], why

    if base in ("rm", "unlink", "shred"):
        return T(_operands(words, base), "DELETE"), None
    if base == "tee":
        return T(_operands(words, base)), None
    if base in ("sed", "gsed"):
        files = (_script_then_files(words, ("-e", "--expression", "-f", "--file"), base)
                 if _sed_inplace(words) else [])
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
    other = _more_write_forms(base, words)
    if other is not None:
        return other
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
    primitive, so each returns no targets — the silent pass this guard exists
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


# --------------------------------------------------------------------------
# Write, then run (issue #405)
# --------------------------------------------------------------------------
# A command that writes a file and then runs it — a heredoc Makefile and
# `make`, a conftest.py and `pytest`, a script and `bash`/`source`/`./s.sh`, a
# package.json and `npm run`, a hook and `git commit`, a PATH entry and a bare
# name — runs code it authored itself, which this parse does not read. That is
# the evaluator case written to disk first, so it is UNSURE the same way, and
# the protected-path pass judges the text that could steer it (the written
# content, the run's arguments). A build tool running code that was already
# there stays the residual it always was (module docstring).
#
# Each run is noted while the segments are parsed (EXECS) and matched, once the
# whole command (substitutions included) is parsed, against every write it
# makes, in any order: a loop or a function can run before it writes.
#   file  a named script or makefile, or a path run directly: that file, or a
#         code file beside it (an import, a sourced sibling)
#   tree  a runner of files by convention (make, pytest, npm, …): anything in
#         its repository, or its directory outside one, but data files; a
#         `python -m` imports only Python files
#   git   any git reads .git/ and the hook tools' config files; one whose hooks
#         conventionally run the project's checks (commit, merge, push, …) runs
#         its tree too
#   dirs  a load path set in this command (PATH=, LD_PRELOAD=, HOME=, …): what
#         is written under one of its entries
#   any   a command name the parse cannot follow
# A file with a data extension, or one that is not code beside a named script,
# runs only through code that already reads it, so it is not code authored
# here, except where it is the very file run.
EXECS = []
NEST_LIMIT = 12
TREE_RUNNERS = ("pip", "pip3", "terraform", "tofu", "ansible-playbook", "ansible", "eslint", "webpack",
                "vite", "rollup", "rspec", "phpunit", "docker-compose", "gem", "brew", "gradlew", "mvnw",
                "conan", "helm", "pulumi", "cdk", "serverless", "sls", "prettier", "stylelint", "babel",
                "playwright", "cypress", "next", "nuxt", "astro", "rails", "ctest", "flutter", "dart",
                "rebar3", "stack", "cabal", "dune", "buck", "buck2", "pants", "earthly", "dagger",
                "skaffold", "tilt", "packer", "nix-build", "home-manager", "darwin-rebuild", "direnv",
                "make", "gmake", "bmake", "pytest", "py.test", "tox", "nox", "npm", "yarn", "pnpm",
                "bun", "deno", "cargo", "go", "mvn", "gradle", "rake", "bundle", "just", "ninja",
                "cmake", "pre-commit", "jest", "vitest", "mocha", "ava", "poetry", "uv", "pipenv",
                "hatch", "pdm", "composer", "mix", "dotnet", "swift", "xcodebuild", "ant", "sbt",
                "lein", "meson", "bazel", "bazelisk", "tsx", "ts-node", "lefthook", "husky",
                "turbo", "nx", "lerna", "invoke", "task", "scons", "waf", "julia")
FILE_RUNNERS = tuple(e for e in EVALUATORS if e != "eval") + ("source", ".")
# Options whose value is a file the interpreter runs as well as its script.
RUN_FILE_OPTS = ("--rcfile", "--init-file", "-r", "--require", "--import", "--loader",
                 "--experimental-loader", "--env-file")
# Options of a tree runner that point it at another directory or file.
TREE_DIR_OPTS = ("-C", "--directory", "--prefix", "--cwd", "--dir", "--manifest-path", "--rootdir",
                 "--chdir", "--working-directory", "--root", "--project", "--config", "-c", "--file",
                 "-f", "--modfile", "--gemfile", "-p", "--path", "--target", "--chart")
# A .txt that is code to the tool that reads it.
CODE_DATA_NAMES = re.compile(r"^(?:cmakelists\.txt|.*\.cmake|(?:requirements|constraints)[^/]*\.txt)$")
PYTHONS = ("python", "python2", "python3")
# Interpreter options whose value is the next word, never the script.
RUNNER_VALUE_OPTS = ("-o", "+o", "-O", "+O", "--rcfile", "--init-file", "-W", "-X", "-r",
                     "--require", "--import", "--loader", "--experimental-loader", "-I", "-M",
                     "--input-type", "--env-file", "-C", "--cwd", "--config", "-A")
DATA_EXTENSIONS = (".md", ".markdown", ".txt", ".log", ".csv", ".tsv", ".patch", ".diff", ".rst",
                   ".html", ".htm", ".svg", ".png", ".jpg", ".jpeg", ".gif", ".pdf")
# What a script can import or source from beside itself: code, or a file with no extension.
CODE_EXTENSIONS = ("", ".sh", ".bash", ".zsh", ".ksh", ".fish", ".py", ".pyc", ".pth", ".so",
                   ".dylib", ".js", ".mjs", ".cjs", ".ts", ".mts", ".cts", ".jsx", ".tsx", ".node",
                   ".rb", ".pl", ".pm", ".php", ".lua", ".tcl", ".r", ".jl", ".mk", ".awk", ".sed",
                   ".env", ".rc", ".profile")
PYTHON_EXTENSIONS = (".py", ".pyc", ".pth", ".so", "")
# Hooks' own files: .git/ (hooks, config) and what the hook managers read.
GIT_HOOK_NAMES = (".pre-commit-config.yaml", ".pre-commit-config.yml", "lefthook.yml",
                  "lefthook.yaml", ".lefthook.yml", "lefthook-local.yml", "package.json",
                  ".lintstagedrc", ".lintstagedrc.json", ".lintstagedrc.yaml", ".lintstagedrc.yml",
                  ".lintstagedrc.js", ".lintstagedrc.cjs", ".lintstagedrc.mjs", "lint-staged.config.js",
                  "lint-staged.config.cjs", "lint-staged.config.mjs", ".huskyrc", ".huskyrc.json",
                  ".simple-git-hooks.json", ".simple-git-hooks.js", ".gitattributes", ".gitmodules")
GIT_HOOK_DIRS = (".husky", ".githooks", ".hooks", "git-hooks", "githooks")
# Subcommands whose hooks (pre-commit, commit-msg, pre-push, post-rewrite, …)
# conventionally run the project's own checks over its tree.
GIT_TREE_HOOKS = ("commit", "merge", "pull", "push", "rebase", "am", "cherry-pick", "revert")
# Subcommands that only read (no hook runs; .git/ config still applies).
GIT_READ_ONLY = ("status", "diff", "log", "show", "ls-files", "ls-tree", "rev-parse", "blame",
                 "cat-file", "describe", "shortlog", "grep", "rev-list", "show-ref",
                 "for-each-ref", "merge-base", "name-rev")
# Subcommands that run other hooks (post-checkout, reference-transaction, post-index-change, …).
GIT_LIGHT_HOOKS = ("checkout", "switch", "worktree", "clone", "fetch", "gc", "reset", "branch", "tag",
                   "stash", "update-ref", "add", "mv", "rm", "restore", "notes", "maintenance",
                   "update-index", "apply", "symbolic-ref", "replace")
UNRESOLVED_TARGET_WHYS = ("writes to a target built by shell expansion",
                          "writes to a relative path after a `cd`")
RUNS_WRITTEN_WHY = ("runs %s after this same command writes %s: code written and run in one command "
                    "is not read by this parse")


def _repo_top(path):
    """The nearest ancestor of `path` (itself included) holding a .git entry; `path` when none."""
    d = path
    while d and d != "/":
        if os.path.lexists(os.path.join(d, ".git")):
            return d
        d = os.path.dirname(d)
    return path


def _exec_file(tok, cwd):
    """(absolute path or None, literal basename or None) of a file a run names."""
    value = _static_value(tok)
    path = _resolve(value, cwd) if value is not None else None
    tail = tok.value.rstrip("/").rsplit("/", 1)[-1]
    literal = tail if tail and not any(c in tail for c in "$`*?[{~\\") else None
    return path, literal


def _note_load_path(assignment, cwd, fragment):
    """A load path set in this command (FILE_LOADING_ENV): a run reads code from under its entries."""
    name, _, value = assignment.partition("=")
    name = name.rstrip("+")
    dirs = []
    for entry in value.split(":"):
        if not entry or re.match(r"^\$\{?%s\}?$" % re.escape(name), entry):
            continue        # the inherited value: code that was already there
        path = _exec_file(Tok("word", entry, "$" in entry or "`" in entry), cwd)[0]
        if path is None:
            dirs = None
            break
        dirs.append(path)
    if dirs == []:
        return
    EXECS.append({"kind": "dirs" if dirs else "any", "fragment": fragment, "dirs": dirs or [],
                  "what": "a program found through %s" % name})


def _split_command_variable(head):
    """The words of an unquoted `$NAME`/`${NAME}` whose same-command literal value
    word-splits with nothing else to expand (no glob, quote or escape); [] otherwise."""
    m = re.match(r"^\$(?:\{(%s)\}|(%s))$" % (_NAME, _NAME), head.value)
    if not m or head.quoted:
        return []
    value = ASSIGNS.get(m.group(1) or m.group(2))
    if value is None or any(c in value for c in "$`*?[{}'\"\\~=") or not value.split():
        return []
    first = os.path.basename(value.split()[0])
    if first in WRAPPERS or first in COMMAND_INTRODUCERS or first in ALL_KEYWORDS:
        return []           # `T="sudo cp"`: a wrapper or keyword would need the full head parse
    return [Tok("word", v) for v in value.split()]


def _note_exec(base, argv0, rest, cwd, fragment):
    """Note what this segment runs, for the write-then-run check (see the block comment)."""
    values = [w.value for w in rest]

    def files(kind, what, toks, d=cwd):
        EXECS.append({"kind": kind, "fragment": fragment, "what": what,
                      "files": [_exec_file(t, d) for t in toks]})

    if "/" in argv0:
        files("file", argv0, [Tok("word", argv0)])
        if base in TREE_RUNNERS:     # `./gradlew build` reads the build files around it
            EXECS.append({"kind": "tree", "fragment": fragment, "what": argv0,
                          "dirs": [_repo_top(cwd) if cwd else None]})
        return
    if base in PYTHONS and any(v == "-m" or (v.startswith("-") and not v.startswith("--")
                                              and v.endswith("m")) for v in values):
        k = next(k for k, v in enumerate(values) if v == "-m" or (
            v.startswith("-") and not v.startswith("--") and v.endswith("m")))
        module = values[k + 1] if k + 1 < len(values) else ""
        if module in TREE_RUNNERS:
            # `python -m pip install .`, `python -m pytest d`: the tool reads the project's files.
            return _note_exec(module, module, rest[k + 2:], cwd, fragment)
        ex = {"kind": "tree", "fragment": fragment, "what": "`%s -m %s`" % (base, module),
              "dirs": [_repo_top(cwd) if cwd else None]}
        if module not in ("build", "unittest", "setuptools", "twine", "flit", "black", "ruff", "mypy"):
            ex["exts"] = PYTHON_EXTENSIONS      # any other module only imports Python files
        EXECS.append(ex)
        return
    if base in FILE_RUNNERS:
        # The script is the first operand that is not an option's value
        # (`bash -o pipefail s.sh`, `python3 -W ignore s.py`); a file an option
        # loads (`node -r ./e.js`, `bash --init-file rc.sh`) runs too.
        toks = [w for k, w in enumerate(rest) if not w.value.startswith(("-", "+"))
                and not (k and rest[k - 1].value in RUNNER_VALUE_OPTS)]
        loads = [rest[k + 1] for k, w in enumerate(rest[:-1]) if w.value in RUN_FILE_OPTS]
        loads += [Tok("word", w.value.split("=", 1)[1], w.expands, w.quoted) for w in rest
                  if "=" in w.value and w.value.split("=", 1)[0] in RUN_FILE_OPTS]
        if toks[:1] + loads:
            files("file", "`%s`" % base, toks[:1] + loads)
        return
    if base in ("sed", "gsed"):
        progs = [t for f, t in _walk_options(rest, "efl", ("--expression", "--file", "--line-length"))
                 if f in ("-f", "--file") and t is not None]
        if progs:
            files("file", "`%s -f`" % base, progs)
        return
    if base in AWKS:
        progs = [t for f, t in _walk_options(rest, "fvF", ("--file", "--assign", "--field-separator"))
                 if f in ("-f", "--file") and t is not None]
        if progs:
            files("file", "`%s -f`" % base, progs)
        return
    if base in TREE_RUNNERS:
        d = cwd
        if base in ("make", "gmake", "bmake"):
            given = _flag_value(rest, ("-C", "--directory"))
            if given is not None:
                d = _exec_file(given, cwd)[0]
            mk = _flag_value(rest, ("-f", "--file", "--makefile"))
            if mk is not None:
                files("file", "`%s -f`" % base, [mk], d)
        dirs = [_repo_top(d) if d else None]
        # Another directory it is pointed at (`pytest /tmp/zz`, `npm --prefix d`,
        # `cargo build --manifest-path d/Cargo.toml`): its tree runs as well.
        for k, w in enumerate(rest):
            v = w.value
            given = None
            if v in TREE_DIR_OPTS and k + 1 < len(rest):
                given = rest[k + 1]
            elif v.startswith("--") and "=" in v and v.split("=", 1)[0] in TREE_DIR_OPTS:
                given = Tok("word", v.split("=", 1)[1], w.expands, w.quoted)
            elif not v.startswith("-") and ("/" in v or v.startswith(".") or "$" in v):
                given = w
            if given is None:
                continue
            path = _exec_file(given, cwd)[0]
            if path is None:
                dirs.append(None)
                continue
            if os.path.splitext(path)[1] or os.path.isfile(path):
                path = os.path.dirname(path)
            dirs.append(_repo_top(path))
        EXECS.append({"kind": "tree", "fragment": fragment, "what": "`%s`" % base,
                      "dirs": dirs})
        return
    if base == "git":
        frame = cwd
        i = 0
        while i < len(rest):
            v = rest[i].value
            if v == "-C":
                frame = _exec_file(rest[i + 1], frame)[0] if i + 1 < len(rest) and frame else None
                i += 2
                continue
            if v in GIT_GLOBAL_VALUE or v in ("--git-dir", "--work-tree"):
                if v in ("--git-dir", "--work-tree"):
                    frame = None
                i += 2
                continue
            if v.startswith(("--git-dir=", "--work-tree=")):
                frame = None
            if not v.startswith("-"):
                break
            i += 1
        sub = values[i] if i < len(values) else ""
        msg = None
        if sub == "commit":
            given = _flag_value(rest[i + 1:], ("-F", "--file"))
            if given is not None:
                msg = _exec_file(given, cwd)[0]
        EXECS.append({"kind": "git", "fragment": fragment, "what": "`git %s`" % sub,
                      "dir": _repo_top(frame) if frame else None,
                      "hooks": "tree" if sub in GIT_TREE_HOOKS else (
                          "light" if sub in GIT_LIGHT_HOOKS or sub not in GIT_READ_ONLY else None),
                      "msg": msg})


def _under(path, d):
    return path == d or path.startswith(d.rstrip("/") + "/")


def _runs_written(ex, path):
    """True when the run `ex` (an EXECS entry) may run the written `path` (None: unresolved)."""
    if path is None:
        return True
    p = path.casefold()
    ext = os.path.splitext(p)[1]
    data = ext in DATA_EXTENSIONS and not CODE_DATA_NAMES.match(os.path.basename(p))
    kind = ex["kind"]
    if kind == "any":
        return not data
    if kind == "dirs":
        return any(_under(p, d.casefold()) for d in ex["dirs"])
    if kind == "file":
        # Only the scripts run (the script, a file an option loads); the
        # operands after the script are its arguments, data to it.
        for c, literal in ex["files"]:
            if c is not None:
                c = c.casefold()
                if p == c or (ext in CODE_EXTENSIONS and _under(p, os.path.dirname(c))):
                    return True
            elif literal is not None:
                # Named by expansion: the very file when its literal name matches,
                # or a code file beside it, wherever that is.
                if literal.casefold() == os.path.basename(p) or ext in CODE_EXTENSIONS:
                    return True
            elif not data:
                return True
        return False
    if kind == "tree":
        if "exts" in ex and ext not in ex["exts"]:
            return False
        return not data and any(d is None or _under(p, d.casefold()) for d in ex["dirs"])
    d = ex.get("dir")
    # git
    if ex.get("msg") and p == ex["msg"].casefold():
        return False        # the message file of `git commit -F` is the message, not code
    parts = p.split("/")
    if ".git" in parts:
        return True         # its config (an fsmonitor, a pager, an alias) and hooks: any git
    if not ex["hooks"]:
        return False
    if os.path.basename(p) in GIT_HOOK_NAMES or any(x in GIT_HOOK_DIRS for x in parts[:-1]):
        return True         # the hook managers' own files
    return ex["hooks"] == "tree" and not data and (d is None or _under(p, d.casefold()))


def _write_then_run(records):
    """UNSURE records for every noted run that may run a file this command writes."""
    if not EXECS:
        return []
    writes = []
    for kind, detail, frag in records:
        if kind in ("TARGET", "TREE", "PREFIX"):
            if not detail.startswith("/dev/"):
                writes.append((os.path.normpath(detail), frag))
        elif kind == "UNSURE" and detail.startswith(UNRESOLVED_TARGET_WHYS):
            writes.append((None, frag))
    out = []
    for ex in EXECS:
        for path, frag in writes:
            if frag == ex["fragment"]:
                continue    # its own output (`make > build.log`)
            if _runs_written(ex, path):
                out.append(("UNSURE", RUNS_WRITTEN_WHY % (
                    ex["what"], "'%s'" % path if path else "a target this parse could not resolve"),
                    ex["fragment"]))
                break
    return out


def _join_continuations(body):
    """An unquoted heredoc body with its line continuations joined: a backslash-newline
    whose backslash is not itself escaped (`\\<newline>` is a backslash, then a newline)."""
    return re.sub(r"(?<!\\)((?:\\\\)*)\\\n", r"\1", body)


def _nested_records(command, cwd, depth, inherit=None):
    """The records of a command a substitution runs, parsed as a command of its own (#405)."""
    if depth >= NEST_LIMIT:
        return [("ANOMALY", "command substitutions nested more than %d deep" % NEST_LIMIT, "")]
    saved = (dict(ASSIGNS), set(RESOLVABLE), dict(CHAIN_ASSIGNS), set(CHAIN_NAMES))
    try:
        # A substitution runs in a subshell: it sees the cwd and the literal
        # assignments here, and nothing it assigns or changes reaches the
        # command around it.
        return analyze_command(command, cwd, depth + 1, inherit)
    finally:
        ASSIGNS.clear()
        ASSIGNS.update(saved[0])
        RESOLVABLE.clear()
        RESOLVABLE.update(saved[1])
        CHAIN_ASSIGNS.clear()
        CHAIN_ASSIGNS.update(saved[2])
        CHAIN_NAMES.clear()
        CHAIN_NAMES.update(saved[3])


def _chain_update(seg, depth, piped_in, terminator, prev_terminator):
    """Admit a `&& NAME=literal &&` statement to CHAIN_ASSIGNS; end the chain on any other list operator."""
    if terminator != "&&":
        CHAIN_ASSIGNS.clear()
        return
    words = [t for t in seg if t.kind == "word"]
    if depth or piped_in or prev_terminator != "&&" or not words \
            or len(words) != len(seg) or not all(ASSIGN_WORD.match(w.value) for w in words):
        return
    for tok in words:
        name, op, value = ASSIGN_WORD.match(tok.value).groups()
        if op != "=" or name not in CHAIN_NAMES:
            continue
        lit = _static_value(Tok("word", value, tok.expands, tok.quoted))
        if lit is not None:
            CHAIN_ASSIGNS[name] = lit


def analyze_command(command, cwd, nest=0, inherit=None):
    """Yield (kind, detail, fragment) records for one Bash command string.

    `nest` counts the command substitutions this command is nested in; only
    the outermost call matches runs against writes (_write_then_run).
    `inherit` is the parent's ASSIGNS as the substitution starts: a name the
    whole parent text assigns once is assigned nowhere inside it either.
    """
    if nest == 0:
        del EXECS[:]
    anomalies = []

    def note(why):
        if why not in anomalies:
            anomalies.append(why)

    heredoc_bodies = []
    heredoc_meta = []
    toks = tokenize(command, anomalies, heredoc_bodies, heredoc_meta)
    heredoc_iter = iter(heredoc_bodies)
    # The text the shell itself parses: the command minus its quoted heredoc
    # bodies, which are literal data (spans cut from the end so earlier ones hold).
    shell_text = command
    for quoted, start, end in reversed(heredoc_meta):
        if quoted and end > start:
            shell_text = shell_text[:start] + shell_text[end:]

    records = []
    segment = []
    segments = []       # (tokens, preceded_by_pipe, terminator)
    piped = False
    for tok in toks:
        if tok.kind == "op" and tok.value in SEGMENT_SEPARATORS:
            segments.append((segment, piped, tok.value))
            # A newline right after `|` (a continuation line, a comment line)
            # closes an EMPTY segment; the pipe still feeds the next command,
            # so "piped" carries over instead of being reset (Codex, PR #359;
            # the `&&`/`||` counterpart is prev_terminator, below).
            if segment or tok.value == "|":
                piped = tok.value == "|"
            segment = []
        else:
            segment.append(tok)
    segments.append((segment, piped, ""))

    # `( … )` runs in a subshell, so a `cd` inside it dies at the `)`. Tracked
    # with a stack because one global cwd that is never restored resolves
    # `(cd /tmp); echo x > src/components/ui/button.tsx` against /tmp — a
    # protected path reported as an unprotected one while Bash writes the
    # protected one. An unbalanced `)` leaves cwd unknown rather than wrong.
    # The same-command assignments (ASSIGNS) are admitted only at depth zero —
    # the open `(` groups plus the open compound commands (_scope_update) —
    # and only for the names the whole text allows (RESOLVABLE, see
    # "Same-command literal assignments"); nothing is ever forgotten or
    # restored, because a name that could change is never admitted.
    cwd_stack = []
    ASSIGNS.clear()
    ASSIGNS.update(inherit or {})
    RESOLVABLE.clear()
    RESOLVABLE.update(_resolvable_names(command, shell_text))
    CHAIN_ASSIGNS.clear()
    CHAIN_NAMES.clear()
    CHAIN_NAMES.update(_resolvable_names(command, shell_text, after_and=True))
    scope = {"frames": []}
    prev_terminator = ""
    hd = 0              # heredoc bodies taken by the segments so far

    for seg, piped_in, terminator in segments:
        if seg:
            depth, own, cwd = _scope_update(seg, scope, cwd, terminator)
            depth += len(cwd_stack)
            n_hd = sum(1 for t in seg if t.kind == "op" and t.value in ("<<", "<<-"))
            hd += n_hd
            seg_cwd = cwd
            seg_assigns = dict(ASSIGNS)     # what this segment's substitutions see
            cwd = _segment_records(seg, piped_in, terminator, cwd, records, heredoc_iter,
                                   conditional=depth > 0 or prev_terminator in ("&&", "||"),
                                   cd_mode=_cd_mode(scope, own, terminator, prev_terminator))
            # The commands its substitutions run (issue #405): in its words,
            # redirection targets and assignments, and in its unquoted heredoc bodies.
            nested = [c for t in seg if t.kind == "word" for c in t.subs]
            for k in range(hd - n_hd, min(hd, len(heredoc_bodies))):
                if not heredoc_meta[k][0]:
                    nested.extend(_expansion_subs(_join_continuations(heredoc_bodies[k]), note))
            for inner in nested:
                records.extend(_nested_records(inner, seg_cwd, nest, seg_assigns))
            _chain_update(seg, depth, piped_in, terminator, prev_terminator)
        elif terminator not in ("&&", "\n"):
            CHAIN_ASSIGNS.clear()
        if terminator == ")" and prev_terminator == "(" and not seg:
            # `NAME() {`: the body that follows is a function's, run later
            # if at all, so a `cd` inside it leaves the cwd unknown.
            scope["fn_pending"] = True
        # The group boundary is the terminator of the segment just processed.
        if terminator == "(":
            cwd_stack.append(cwd)
        elif terminator == ")":
            cwd = cwd_stack.pop() if cwd_stack else None
        # `false &&` followed by a newline, or by a comment line, closes an
        # EMPTY segment whose `\n` must not overwrite the `&&` still governing
        # the next command (Codex, PR #359): an empty segment changes the
        # conditional state only when its own terminator is a list operator.
        if seg or terminator in ("&&", "||", "|", "&"):
            prev_terminator = terminator
    records.extend(("ANOMALY", why, "") for why in anomalies)
    if nest == 0:
        records.extend(_write_then_run(records))
    return records


BRACE_EXPANSION = re.compile(r"(?<!\$)\{[^{}\s]*(?:,|\.\.)[^{}\s]*\}")


def _brace_expand(value, limit=64):
    """Every word `value` brace-expands to (`a{b,c}d` -> abd, acd); None past `limit` or for a range."""
    m = None
    depth = 0
    start = -1
    for i, c in enumerate(value):
        if c == "{":
            if depth == 0:
                start = i
            depth += 1
        elif c == "}" and depth:
            depth -= 1
            if depth == 0:
                body = value[start + 1:i]
                if "," in body or ".." in body:
                    m = (start, i, body)
                    break
    if m is None:
        return [value]
    start, end, body = m
    if ".." in body and "," not in body:
        return None         # `{1..9}`, `{a..z}`: a range, not expanded here
    parts, depth, cur = [], 0, ""
    for c in body:
        if c == "," and depth == 0:
            parts.append(cur)
            cur = ""
            continue
        depth += {"{": 1, "}": -1}.get(c, 0)
        cur += c
    parts.append(cur)
    out = []
    for part in parts:
        sub = _brace_expand(value[:start] + part + value[end + 1:], limit)
        if sub is None:
            return None
        out.extend(sub)
        if len(out) > limit:
            return None
    return out


def _record_targets(pairs, cwd, records, fragment):
    """Resolve (token, kind) pairs to absolute paths and append their records."""
    expanded = []
    for t, kind in pairs:
        if "{" in t.value and BRACE_EXPANSION.search(t.value):
            # `tee {/tmp/a,~/.gitconfig}` writes both words (#405 review). A quoted
            # brace does not expand, but checking its words too only over-reports.
            words = _brace_expand(t.value)
            if words is None:
                records.append(("UNSURE", "writes to a brace expansion this parse does not expand (%s)"
                                % t.value, fragment))
                continue
            expanded.extend((Tok("word", w, t.expands, t.quoted), kind) for w in words if w != t.value)
    for t, kind in list(pairs) + expanded:
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


def _time_output(words):
    """GNU time's output file: `-o F`, `-oF`, a cluster ending in `o` (`-po F`), `--output[=]F`."""
    for idx, w in enumerate(words):
        v = w.value
        nxt = words[idx + 1] if idx + 1 < len(words) else None
        if v.startswith("--"):
            name, eq, val = v.partition("=")
            if len(name) > 3 and "--output".startswith(name):
                return Tok("word", val, w.expands, w.quoted) if eq else nxt
            continue
        if v.startswith("-"):
            for k, ch in enumerate(v[1:], 1):
                if ch == "f":
                    break           # -f FORMAT: the rest is its value
                if ch == "o":
                    rest = v[k + 1:]
                    return Tok("word", rest, w.expands, w.quoted) if rest else nxt
    return None


def _stdin_fed(seg):
    """True when a redirection hands this command's stdin something that can be a program.

    `< /dev/null` cannot: it is empty, so `bash x.sh </dev/null` runs x.sh and
    nothing else (issue #402). Any other `<`, `<&`, `<<<`, or a `<>` on stdin
    can (`bash <> f` reads its program from f).
    """
    for idx, t in enumerate(seg):
        nxt = seg[idx + 1] if idx + 1 < len(seg) else None
        prev = seg[idx - 1] if idx else None
        if t.kind == "op" and t.value == ">&" and prev is not None and prev.kind == "word" \
                and prev.value == "0":
            return True         # `0>&3` re-points stdin at another descriptor
        if t.kind != "op" or t.value not in ("<", "<<<", "<&", "<>"):
            continue
        if t.value == "<>" and prev is not None and prev.kind == "word" \
                and prev.value.isdigit() and prev.value != "0":
            continue            # `3<>f` opens fd 3, not stdin
        if t.value == "<" and nxt is not None and nxt.kind == "word" and not nxt.expands \
                and nxt.value == "/dev/null" and not (
                    prev is not None and prev.kind == "word" and prev.value.isdigit()
                    and prev.value != "0"):
            continue            # (`3</dev/null` is not stdin: it does not empty it)
        return True
    return False


def _segment_records(seg, piped_in, terminator, cwd, records, heredoc_iter, conditional=False,
                     cd_mode="apply"):
    """Append this segment's records; return the cwd the NEXT segment sees.

    `conditional` is true when the segment follows `&&`/`||` or sits inside
    a compound command: it may never run, so no assignment in it is admitted.
    `cd_mode` (see _cd_mode) says whether a `cd` here moves the parent's cwd.
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
    fed_code = piped_in or bool(heredoc_bodies) or _stdin_fed(seg)
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

    # The table as it stands BEFORE this segment's own assignments: bash opens
    # a command's redirections before it runs the command, so `S=.github;
    # export S=/tmp > "$S/w"` writes .github/w, whatever `export` then sets.
    before = dict(ASSIGNS)

    wrapper_targets = []

    def finish(pairs=()):
        # A redirection writes even when the command is `exec`, a bare `> f`, or
        # a wrapper this parse gave up on — it is the shell's write, not theirs.
        pairs = list(pairs) + wrapper_targets
        after = dict(ASSIGNS)
        ASSIGNS.clear()
        ASSIGNS.update(before)
        _record_targets(redirects, cwd, records, fragment)
        ASSIGNS.clear()
        ASSIGNS.update(after)
        _record_targets(list(pairs), cwd, records, fragment)

    # What this segment assigns is known before its operands are resolved
    # (`S=/x` and `cp a "$S/b"` are separate segments; `S=/x cp a "$S/b"`
    # expands `$S` before the prefix is applied, and the prefix never reaches
    # the shell, so recording it only now is also correct for that form).
    _track_assignments(words, piped_in, terminator, conditional)

    # Leading `VAR=value` assignments and transparent wrappers — including each
    # wrapper's OWN options, or the first of them lands in argv0's place. A
    # reserved word that INTRODUCES a command (`then cp a yarn.lock`,
    # `do tee yarn.lock`, `{ cp …`, `if cp …`) is stripped the same way: left
    # in place it was argv0, matched no write primitive, and the write after it
    # was reported as no write at all (a redirection was still caught, being
    # the shell's; a `cp`, `tee` or `sed -i` was not).
    assigned = []       # every NAME=value this segment hands its command's environment
    lookup = False      # `command -v NAME`: a lookup, so NAME's own run is not judged
    while words:
        head = words[0].value
        if not words[0].quoted and head in COMMAND_INTRODUCERS:
            words.pop(0)
            continue
        if "=" in head and not head.startswith("=") and head.split("=", 1)[0].replace("_", "a").isalnum():
            assigned.append(head)
            words.pop(0)
            continue
        name = os.path.basename(head)
        if name in WRAPPERS:
            words.pop(0)
            before_strip = list(words)
            words, wrapper_unsure = _strip_wrapper_options(words, name)
            own = before_strip[:len(before_strip) - len(words)]
            assigned.extend(w.value for w in own if ASSIGNMENT_WORD.match(w.value))
            lookup = lookup or (name == "command" and any(w.value in ("-v", "-V") for w in own))
            if name == "time" and not wrapper_unsure:
                # GNU `time -o FILE` / `--output=FILE` writes FILE (issue #402 review).
                out = _time_output(own)
                if out is not None:
                    wrapper_targets.append((out, "TARGET"))
            if wrapper_unsure:
                records.append(("UNSURE", wrapper_unsure, fragment))
                finish()
                return cwd
            continue
        break
    if words and os.path.basename(words[0].value) in ASSIGNING_BUILTINS:
        assigned.extend(w.value for w in words[1:] if ASSIGNMENT_WORD.match(w.value))
    # Issue #405: an environment that names a command (`GIT_EXTERNAL_DIFF=…`) runs
    # it; one that names where code is loaded from (`PATH=…`) runs a file a write
    # in this command may have put there.
    for a in assigned:
        why = _code_env(a)
        if why:
            records.append(("UNSURE", why, fragment))
        if FILE_LOADING_ENV.match(a):
            _note_load_path(a, cwd, fragment)
    if not words:
        finish()
        return cwd

    head = words[0]
    if head.expands and head.value.startswith("((") and head.value.endswith("))"):
        finish()            # `(( … ))` is arithmetic, not a command; its substitutions are parsed
        return cwd
    argv0, rest = head.value, words[1:]
    case_pattern = terminator == ")" and len(words) == 1   # `*)`, `R*)` in a case statement
    if argv0 not in ("[", "[[") and not case_pattern and (
            any(c in argv0 for c in "*?[") or BRACE_EXPANSION.search(argv0)):
        # `{tee,x} f`, `/usr/bin/te[e] f`: the shell picks the command (#405 review).
        records.append(("UNSURE", "runs a command whose name is built by brace or glob expansion (%s), "
                        "so what it writes is unknown" % argv0, fragment))
        EXECS.append({"kind": "any", "fragment": fragment, "what": "a command named by expansion (%s)" % argv0})
        finish()
        return cwd
    if head.expands or "$" in argv0 or "`" in argv0:
        # Issue #405: `$CMD x PROT`, `${X} …`, `$(echo cp) …`. A name the same
        # command assigned a literal to is resolved; anything else runs a command
        # this parse cannot name, so what it writes is UNSURE.
        table = dict(ASSIGNS)
        ASSIGNS.update(CHAIN_ASSIGNS)
        try:
            static = _static_value(head)
            split = _split_command_variable(head)
        finally:
            ASSIGNS.clear()
            ASSIGNS.update(table)
        if static is None and split:
            # `OS="bash /x/state.sh"; $OS init`: a literal that word-splits into a
            # command line is that command line.
            words = split + list(rest)
            head = words[0]
            argv0, rest = head.value, words[1:]
            static = argv0
        if static is None:
            records.append(("UNSURE", "runs a command whose name is built by shell expansion (%s), so "
                            "what it writes is unknown" % argv0, fragment))
            EXECS.append({"kind": "any", "fragment": fragment,
                          "what": "a command named by expansion (%s)" % argv0})
            finish()
            return cwd
        argv0 = static
    base = os.path.basename(argv0)
    records.append(("RAN", base, fragment))
    if not lookup:
        _note_exec(base, argv0, rest, cwd, fragment)

    # `cd` moves the frame every later relative path is resolved against —
    # unless it runs in a subshell, where the move dies with it. A pipeline
    # component is a subshell too, so `cd /tmp | true; echo x > yarn.lock`
    # writes the repo's lockfile, not /tmp's. `pushd` moves it the same way.
    if base in ("cd", "pushd", "popd"):
        finish()
        if piped_in or terminator == "|" or cd_mode == "ignore":
            return cwd          # a subshell's cd: the parent never moved
        if cd_mode == "unknown":
            return None         # a cd that may not run, or runs later
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
    if unsure and lookup and unsure.startswith("runs another command"):
        # `command -v tmux` runs nothing, so it is not a runner (its operand targets
        # are still reported as before: no weakening versus the base).
        unsure = None
    if unsure:
        records.append(("UNSURE", unsure, fragment))
    if PROTECTED_MODE and not unsure:
        records.extend(_source_records(argv0, rest, cwd, fragment))
    if PROTECTED_MODE and base == "find" and unsure == FIND_ACTION_WHY and any(
            w.value in FIND_WRITES + FIND_EXECS and w.value not in FIND_PRINTS for w in rest):
        # A find that deletes or runs a writer acts on everything under its
        # starting points, so one that HOLDS a protected path reaches it, as
        # `rm -rf` of that directory would (SCOPE, judged in protect()).
        for root in _find_roots(rest, cwd) or []:
            records.append(("SCOPE", root, fragment))
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
# In the protected-path pass, `git rm` and `git mv` are judged by their
# operands. git commands that REPLAY committed content onto the working tree
# (checkout, switch, restore, reset, merge, pull, rebase, cherry-pick, revert,
# am, stash, clean) are not judged: an integrator merging a branch legitimately
# brings any file in, and git undoes it (6.0.0 dropped the ask they used to be).
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


def _git_top(frame):
    out = _git(frame, ["rev-parse", "--show-toplevel"])
    top = out.strip() if out else ""
    return top or None


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


GIT_HANDLERS = {"rm": _git_rm, "mv": _git_mv}
GIT_PATCH_HANDLERS = {"apply": _git_apply}
GIT_GLOBAL_VALUE = ("-c", "--namespace", "--exec-path", "--config-env", "--super-prefix",
                    "--attr-source", "--list-cmds")
# `git -c KEY=…` keys whose value is (or loads) a program git runs (issue #405).
GIT_EXEC_CONFIG = re.compile(
    r"^(?:alias\.|pager\.|core\.(?:pager|editor|sshcommand|fsmonitor|hookspath|askpass|gitproxy|"
    r"worktree|attributesfile|excludesfile)|sequence\.editor|diff\.|merge\.|filter\.|credential|gpg\.|"
    r"include|uploadpack\.|receive\.|remote\.[^=]*\.(?:uploadpack|receivepack|proxy|vcs)|"
    r"interactive\.difffilter|init\.templatedir|difftool\.|mergetool\.|man\.|browser\.|"
    r"web\.browser|sendemail\.|protocol\.|submodule\.|url\.|instaweb\.|trailer\.)", re.I)
# Subcommands whose options hand git a command line to run (issue #405).
GIT_EXEC_OPTS = {
    "rebase": ("-x", "--exec"), "difftool": ("-x", "--extcmd"),
    "fetch": ("--upload-pack",), "pull": ("--upload-pack",), "clone": ("-u", "--upload-pack", "--template"),
    "ls-remote": ("--upload-pack",), "push": ("--receive-pack", "--exec"), "archive": ("--exec",),
    "send-email": ("--to-cmd", "--cc-cmd", "--header-cmd", "--sendmail-cmd", "--smtp-server"),
    "commit": ("--template",), "init": ("--template",),
}
GIT_ALWAYS_EXEC = ("filter-branch", "filter-repo", "instaweb", "web--browse", "mergetool")
# The diff-option family takes --output=FILE (git diff, log, show, range-diff, …).
GIT_CONFIG_READS = ("--get", "--get-all", "--get-regexp", "--get-urlmatch", "--get-color",
                    "--get-colorbool", "-l", "--list", "--blob")
GIT_CONFIG_WRITES = ("--add", "--unset", "--unset-all", "--replace-all", "--rename-section",
                     "--remove-section", "-e", "--edit", "--comment", "--append")


def _git_opt_value(args, i, short, longs):
    """(token, words used) when args[i] is `short V`, `shortV`, `--long V` or `--long=V` (any
    unambiguous prefix of a long name of at least 3 letters counts); (None, 0) otherwise."""
    w = args[i]
    v = w.value
    nxt = args[i + 1] if i + 1 < len(args) else None
    if short and v == short:
        return nxt, 2
    if short and v.startswith(short) and not v.startswith("--") and len(v) > 2:
        return Tok("word", v[2:], w.expands, w.quoted), 1
    if short and v.startswith("-") and not v.startswith("--") and short[1] in v[2:] \
            and v[1:v.index(short[1], 1)].isalpha():
        # A cluster of flags ending in it: `-No DIR`, `-koDIR`.
        tail = v[v.index(short[1], 1) + 1:]
        return (Tok("word", tail, w.expands, w.quoted), 1) if tail else (nxt, 2)
    if v.startswith("--") and len(v) > 4:
        name, eq, val = v.partition("=")
        stem = name[2:]
        if any(l[2:].startswith(stem) for l in longs):
            return (Tok("word", val, w.expands, w.quoted), 1) if eq else (nxt, 2)
    return None, 0


def _git_write_forms(sub, args):
    """([(token, kind)], unsure) for the files a git subcommand writes through an option
    (--output, archive -o, format-patch -o, bundle create, config --file) and for an
    option that hands it a command to run."""
    out = []
    why = None
    ops = []
    i = 0
    if sub in GIT_ALWAYS_EXEC or (sub == "submodule" and any(a.value == "foreach" for a in args)):
        why = "`git %s` runs commands given to it or configured for it; their writes are not parsed" % sub
    exec_opts = GIT_EXEC_OPTS.get(sub, ())
    outdir = None
    file_tok = None
    stdout = False
    while i < len(args):
        w = args[i]
        v = w.value
        if v == "--":
            break
        if exec_opts and any(v == o or (o.startswith("--") and v.startswith(o + "="))
                             or (len(o) == 2 and v.startswith(o) and not v.startswith("--"))
                             for o in exec_opts):
            why = "`git %s %s` runs a command given on the command line; its writes are not parsed" % (
                sub, v.split("=", 1)[0])
        if sub == "format-patch" and v != "--output" and not v.startswith("--output="):
            tok, used = _git_opt_value(args, i, "-o", ("--output-directory",))
            if used:
                outdir = tok
                i += used
                continue
            if v == "--stdout":
                stdout = True
        if sub == "archive":
            tok, used = _git_opt_value(args, i, "-o", ("--output",))
            if used:
                if tok is not None:
                    out.append((tok, "TARGET"))
                i += used
                continue
        if sub == "config":
            tok, used = _git_opt_value(args, i, "-f", ("--file",))
            if used:
                file_tok = tok
                i += used
                continue
        if sub not in ("archive", "config", "bundle", "commit", "notes", "tag", "merge"):
            # The diff-option family: --output=FILE (git diff, log, show, format-patch, …).
            tok, used = _git_opt_value(args, i, None, ("--output",))
            if used and not v.startswith("--output-"):
                if tok is not None:
                    out.append((tok, "TARGET"))
                i += used
                continue
        if not v.startswith("-") or v == "-":
            ops.append(w)
        i += 1
    if sub == "format-patch" and not stdout and not any(k == "TARGET" for _, k in out):
        # The patches are 0001-….patch (or a --start-number) in the output directory.
        base = outdir.value if outdir is not None else "."
        expands = outdir.expands if outdir is not None else False
        for digit in "0123456789":
            out.append((Tok("word", os.path.join(base, digit), expands), "PREFIX"))
    if sub == "bundle" and ops and ops[0].value == "create" and len(ops) >= 2:
        out.append((ops[1], "TARGET"))
    if sub in ("init", "clone"):
        given = _flag_value(args, ("--separate-git-dir",))
        if given is not None:
            out.append((given, "TREE"))
        plain = [t for f, t in _walk_options(args, "bocju", GIT_CLONE_VALUE) if f is None]
        for f, t in _walk_options(args, "bocju", GIT_CLONE_VALUE):
            if f in ("-c", "--config") and t is not None and GIT_EXEC_CONFIG.match(t.value):
                why = ("runs git with configuration (%s) that names a program git runs; that program's "
                       "writes are not parsed" % t.value.split("=", 1)[0])
        d = plain[0] if sub == "init" and plain else (plain[1] if sub == "clone" and len(plain) >= 2 else None)
        if d is not None and d.value.rstrip("/") not in (".", ""):
            # A new repository writes its .git (hooks, config) and, for a clone, a whole tree.
            out.append((d, "TREE") if sub == "clone" else (_word(os.path.join(d.value, ".git"), d), "TARGET"))
    if sub == "credential-store":
        given = _flag_value(args, ("--file",))
        if given is not None:
            out.append((given, "TARGET"))
    if sub == "fast-export":
        given = _flag_value(args, ("--export-marks",))
        if given is not None:
            out.append((given, "TARGET"))
    if sub == "pack-objects" and ops:
        out.append((_word(ops[0].value + "-", ops[0]), "PREFIX"))
    if sub == "config" and file_tok is not None and _git_config_writes(args, ops):
        out.append((file_tok, "TARGET"))
    return out, why


GIT_CLONE_VALUE = ("--branch", "--depth", "--origin", "--reference", "--reference-if-able", "--template",
                   "--config", "--jobs", "--filter", "--separate-git-dir", "--upload-pack",
                   "--server-option", "--shallow-since", "--shallow-exclude", "--bundle-uri",
                   "--ref-format", "--revision", "--initial-branch", "--object-format")


def _git_config_writes(args, ops):
    """False only for a git config that reads: --get…/--list, `get`/`list`, or one NAME."""
    values = [a.value for a in args]
    if any(v in GIT_CONFIG_WRITES or v.startswith(tuple(o + "=" for o in GIT_CONFIG_WRITES))
           for v in values):
        return True
    if any(v in GIT_CONFIG_READS or v.startswith("--blob=") for v in values):
        return False
    names = [o.value for o in ops]
    if names and names[0] in ("get", "list"):
        return False
    return not (len(names) == 1 and names[0] not in ("set", "unset", "edit", "rename-section",
                                                       "remove-section"))


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
        if v in ("-c", "--config-env") or v.startswith("--config-env="):
            # Issue #405: `git -c alias.x='!cp a PROT' x`, `-c core.pager=…`.
            val = v.split("=", 1)[1] if "=" in v else (words[i + 1].value if i + 1 < len(words) else "")
            if GIT_EXEC_CONFIG.match(val):
                records.append(("UNSURE", "runs git with configuration (%s) that names a program git runs; "
                                "that program's writes are not parsed" % val.split("=", 1)[0], fragment))
            i += 1 if "=" in v and v.startswith("--") else 2
            continue
        if v.startswith("--exec-path="):
            records.append(("UNSURE", "runs git's own programs from another directory (%s)" % v, fragment))
            i += 1
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
    if sub == "grep" and any(
            a.value.startswith("-O") or (a.value.split("=", 1)[0].startswith("--op")
                                         and "--open-files-in-pager".startswith(a.value.split("=", 1)[0]))
            for a in args):
        records.append(("UNSURE", "runs the pager command given to `git grep --open-files-in-pager`; "
                                  "its writes are not visible to a shell parse", fragment))
        return
    # Issue #405: write forms of otherwise read-only subcommands, and options that
    # hand git a command to run. A relative output path is resolved where git
    # runs; behind --git-dir/--work-tree that is not known here.
    pairs, why = _git_write_forms(sub, args)
    if pairs:
        _record_targets(pairs, None if lost else frame, records, fragment)
    if why:
        records.append(("UNSURE", why, fragment))
    if sub not in GIT_HANDLERS and sub not in GIT_PATCH_HANDLERS and sub != "am":
        return
    if not PROTECTED_MODE or sub == "am":
        # Only the protected-path pass reads `git rm`, `git mv` and a `git apply` patch; every
        # other caller, and `git am` (commits replayed from a mailbox), keeps the old answer.
        if sub in GIT_PATCH_HANDLERS or sub == "am":
            records.append(("UNSURE", "applies a patch; the written paths are named inside the patch, not on the command line", fragment))
        return
    g = _GitCtx(sub, frame, fragment, records)
    if lost or frame is None:
        return g.unsure("runs against a repository this parse cannot locate (-C, --git-dir or --work-tree), so "
                        "the files it writes were not checked")
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
# Protected paths (`--protected`): security review S-03
# --------------------------------------------------------------------------
# The installed plugin's guard files and every host settings store that could
# widen what an agent may do: the agent never writes them, and no environment
# switch unlocks them. Only guard-sensitive-files.sh passes `--protected`;
# every other consumer of this parser sees the output it always saw.
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
#     a mention is the only evidence there is, and for these paths it is enough. (Issue
#     #402 tried narrowing which text counts; six review rounds each found a
#     write that the narrowing let through, so the whole text still counts.
#     #402 instead cut the false UNSUREs at the parse: a find/xargs running
#     only read-only commands, an interpreter whose stdin is /dev/null.)
#   - A find that deletes or runs a writer is judged by its starting points
#     (SCOPE), as `rm -rf` of that directory would be.
#
# platforms/opencode/plugin/rules.ts carries the same list, and its test holds
# the two equal.
PROTECTED_MODE = False
PROTECTED_PATHS = [
    "{plugin_root}/hooks/**",
    # An installed copy carries no `.git`; one planted there would make it read as a
    # source checkout, which is not protected (protected_roots), so it is protected too.
    "{plugin_root}/.git/**",
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
    "{repo}/.git/hooks/**",
    "{repo}/.git/config",
]
GLOB_CHARS = "*?["


def _this_plugin_root():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def protected_table(root=None):
    """[(label, pattern)] — every protected path, under one label."""
    return [("protected", p) for p in PROTECTED_PATHS]


def _forms(path):
    """The lexical and resolved spellings of an absolute path."""
    out = []
    for p in (os.path.normpath(path), os.path.realpath(path)):
        if p not in out:
            out.append(p)
    return out


def passwd_home():
    """The real uid's home from the passwd entry, never HOME alone."""
    try:
        import pwd
        return pwd.getpwuid(os.getuid()).pw_dir
    except Exception:  # noqa: BLE001
        return None


def protected_roots():
    """{placeholder: [(root, mode)]} — every mode is deny."""
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
            # A source checkout is the contributor's own work tree, so its guard
            # files are not protected (they never were before 5.2.0).
            if os.path.lexists(os.path.join(os.path.realpath(r), ".git")):
                continue
            for f in _forms(r):
                if f not in [p for p, _ in plugin]:
                    plugin.append((f, "deny"))
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


# Kinds that never leave this module: they are consumed by protect().
INTERNAL_KINDS = ("SOURCE", "REPLAY", "PREFIX", "ANOMALY", "RAN", "SCOPE")


def protect(records, payload):
    """The parse with PROTECTED <tab> deny <tab> <why> records in front.

    One record per subject (a path, or a name found in unresolved command
    text). REPLAY records are dropped (a git replay is not judged). SOURCE, REPLAY, PREFIX,
    ANOMALY and RAN records are consumed here; every TARGET/DELETE/TREE whose
    realpath (spelled on disk) differs is repeated under it, so the other rules
    judge the file actually written too.
    """
    cwd = payload.get("cwd") or os.getcwd()
    prot = Protection(cwd)
    tool_input = payload.get("tool_input") or {}
    text = tool_input.get("command") if isinstance(tool_input.get("command"), str) else ""
    out = []
    verdicts = {}       # subject -> (mode, message), the first one wins
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
            what = "it holds a protected path" if inside else "it is protected"
            # A git replay (checkout, merge, pull, rebase, ...) is how an integrator
            # legitimately brings a branch's version of a file in: not judged here.
            if replay:
                return
            flag(path, mode, "'%s'%s %s, and %s (matches %s).%s"
                 % (path, resolved, why, what, pattern, via))

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
        if kind == "SCOPE":
            flag_path(prot.match(detail, containing=True), detail,
                      "is searched by a find that deletes or runs a writer on what it matches", fragment)
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
    if unsure and os.path.isabs(cwd):
        # A shell's cwd persists between calls: `cd ~/.config/gh` in one, then
        # `python3 -c "open('hosts.yml','w')"` in the next names nothing. An
        # unresolved write run INSIDE a protected directory is judged as a write
        # into it. ("Inside" is a child of a protected tree: a cwd that merely
        # holds a protected file, like a repository root, is not judged so.)
        for mode, aid, pattern, form, inside in prot.match(os.path.join(cwd, "x")):
            flag("cwd:" + form, mode, "this command runs inside '%s', which is protected "
                 "(matches %s), and it writes somewhere this parse could not resolve; an "
                 "unresolved write there is treated as a write to it." % (cwd, pattern))
            break
    if text and (unsure or anomalies):
        evidence = text
        opaque = any(k == "UNSURE" and (d == EVAL_WHY or d.endswith("is not read by this parse"))
                     for k, d, _ in records)
        for rx, mode, pattern in prot.needles():
            m = rx.search(evidence)
            if m:
                if anomalies and not unsure:
                    lead = ("this command uses shell syntax the parse does not follow (%s), and it names '%s'"
                            % ("; ".join(anomalies), m.group(0)))
                elif opaque:
                    lead = ("code this parse cannot read (inline interpreter code, eval, a program fed "
                            "on stdin, or a file the same command writes and then runs) runs in a command "
                            "that names '%s'" % m.group(0))
                else:
                    lead = "a write this parse could not resolve names '%s'" % m.group(0)
                flag("name:" + m.group(0).casefold(), mode,
                     "%s, which matches %s; an unresolved write that names a protected path is treated as "
                     "a write to it." % (lead, pattern))
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
        except Exception as exc:  # noqa: BLE001 - fail closed: protected paths cannot be cleared
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
