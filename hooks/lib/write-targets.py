#!/usr/bin/env python3
"""Extract the files a PreToolUse tool call will WRITE.

Reads a PreToolUse hook payload on stdin, writes one tab-separated record per
line to stdout, and always exits 0 (a guard that crashes must not take the
user's tool call down with it — but see UNSURE, it does not go quiet either):

    TARGET <tab> <absolute path>  <tab> <the command fragment it came from>
    DELETE <tab> <absolute path>  <tab> <the command fragment it came from>
    UNSURE <tab> <why not>        <tab> <the command fragment it came from>

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
    `curl -o`, …) and reports only the operands those constructs write to. A
    path that appears anywhere else in the command — a `grep` pattern, a commit
    message, a `sed` script, a heredoc body — is never a target, because it is
    never in a target position. That is a property of the parse, not a list of
    exceptions.

WHAT IT CANNOT DECIDE, AND SAYS SO
    A shell command's write targets are not always statically knowable. Where
    the target is a variable, a command substitution or a glob, and where the
    command is an arbitrary-code evaluator handed inline code, this emits UNSURE
    rather than falling silent. Silence would read as "no protected file
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
    python3 write-targets.py --help
"""
import json
import os
import sys

# --------------------------------------------------------------------------
# Tokenizer
# --------------------------------------------------------------------------
# Quote-aware so that `grep '>' f`, `git commit -m "a > b"` and
# `sed 's|x|y|' f` cannot be mistaken for redirections or path operands.

# Longest first: `&>>` must win over `&>`, `<<-` over `<<`, `>>` over `>`.
OPERATORS = (
    "&>>", "<<-", "&&", "||", ">>", "<<", ">|", ">&", "&>",
    ";", "|", "\n", ">", "<", "&", "(", ")",
)

SEGMENT_SEPARATORS = ("&&", "||", ";", "|", "\n", "&", "(", ")")

REDIRECT_OPS = (">", ">>", ">|", "&>", "&>>", ">&")


class Tok(object):
    __slots__ = ("kind", "value", "expands", "quoted")

    def __init__(self, kind, value, expands=False, quoted=False):
        self.kind = kind          # "word" | "op"
        self.value = value
        self.expands = expands    # contains an unquoted $ or ` — value is a guess
        self.quoted = quoted


def _balanced(text, start):
    """Index just past the `)` matching the `(` at `start`."""
    depth = 0
    i = start
    while i < len(text):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(text)


def tokenize(text):
    """Split a shell fragment into word and operator tokens."""
    toks = []
    buf = []
    expands = False
    quoted = False
    started = False
    i = 0
    n = len(text)

    def flush():
        if started:
            toks.append(Tok("word", "".join(buf), expands, quoted))

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

        if ch == "'":
            end = text.find("'", i + 1)
            if end == -1:
                end = n
            buf.append(text[i + 1:end])
            quoted = True
            started = True
            i = end + 1
            continue

        if ch == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\" and j + 1 < n:
                    buf.append(text[j + 1])
                    j += 2
                    continue
                if text[j] == '"':
                    break
                if text[j] in "$`":
                    expands = True
                buf.append(text[j])
                j += 1
            quoted = True
            started = True
            i = j + 1
            continue

        if ch in " \t":
            flush()
            buf, expands, quoted, started = [], False, False, False
            i += 1
            continue

        # `$(…)` and `` `…` `` are opaque: their contents are a nested command,
        # not operators in this one. Left un-consumed, `cp $(pick) yarn.lock`
        # would split at the parenthesis and lose the destination entirely.
        if ch == "$" and i + 1 < n and text[i + 1] == "(":
            end = _balanced(text, i + 1)
            buf.append(text[i:end])
            expands = True
            started = True
            i = end
            continue
        if ch == "`":
            end = text.find("`", i + 1)
            end = n if end == -1 else end + 1
            buf.append(text[i:end])
            expands = True
            started = True
            i = end
            continue
        # `>(…)` / `<(…)` — process substitution, a pipe rather than a file.
        if ch == "(" and toks and toks[-1].kind == "op" and toks[-1].value in ("<", ">", ">>"):
            end = _balanced(text, i)
            toks.append(Tok("word", text[i:end], True))
            i = end
            continue

        op = next((o for o in OPERATORS if text.startswith(o, i)), None)
        if op:
            flush()
            buf, expands, quoted, started = [], False, False, False
            toks.append(Tok("op", op))
            i += len(op)
            continue

        if ch in "$`":
            expands = True
        buf.append(ch)
        started = True
        i += 1

    flush()
    return toks


def strip_heredocs(command):
    """Remove heredoc BODIES, keeping the command lines that introduce them.

    `cat > f <<'EOF' … EOF` must still be seen as a write to `f`, but the body
    must not be parsed as shell — otherwise prose inside a heredoc becomes
    commands, and a document that merely mentions `yarn.lock` becomes a write to
    it. Returns (command_without_bodies, saw_heredoc).
    """
    lines = command.split("\n")
    kept = []
    i = 0
    saw = False
    while i < len(lines):
        line = lines[i]
        kept.append(line)
        i += 1

        delims = []
        toks = tokenize(line)
        for idx, tok in enumerate(toks):
            if tok.kind == "op" and tok.value in ("<<", "<<-"):
                nxt = toks[idx + 1] if idx + 1 < len(toks) else None
                if nxt is not None and nxt.kind == "word":
                    delims.append((nxt.value, tok.value == "<<-"))
        if not delims:
            continue

        saw = True
        for delim, strip_tabs in delims:
            while i < len(lines):
                body = lines[i]
                i += 1
                if (body.lstrip("\t") if strip_tabs else body).strip() == delim:
                    break
    return "\n".join(kept), saw


# --------------------------------------------------------------------------
# Per-command write-target extraction
# --------------------------------------------------------------------------

# Prefixes that wrap another command without changing what it writes.
WRAPPERS = ("sudo", "env", "command", "time", "nohup", "nice", "stdbuf", "exec", "builtin")

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

# Commands whose write targets are inside a patch we are not reading.
PATCHERS = ("patch",)

INPLACE_LONG = ("--in-place", "--inplace")


def _is_flag(word):
    return word.startswith("-") and word != "-"


def _operands(words):
    """Non-flag arguments, stopping at `--`."""
    out = []
    seen_ddash = False
    for w in words:
        if not seen_ddash and w.value == "--":
            seen_ddash = True
            continue
        if not seen_ddash and _is_flag(w.value):
            continue
        out.append(w)
    return out


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


def _script_then_files(words, script_flags):
    """sed/awk grammar: the first operand is the program unless -e/-f gave it."""
    ops = _operands(words)
    gave_script = any(
        w.value in script_flags or any(w.value.startswith(f + "=") for f in script_flags)
        for w in words
    )
    return ops if gave_script else ops[1:]


def _destinations(words):
    """cp/mv/install/rsync/ln: the last operand, expanded over sources if a dir."""
    explicit_dir = _flag_value(words, ("-t", "--target-directory"))
    ops = _operands(words)
    if explicit_dir is not None:
        return [Tok("word", os.path.join(explicit_dir.value, os.path.basename(s.value)),
                    explicit_dir.expands or s.expands) for s in ops]
    if len(ops) < 2:
        return []
    dest, sources = ops[-1], ops[:-1]
    if len(sources) > 1 or dest.value.endswith("/") or os.path.isdir(dest.value):
        return [Tok("word", os.path.join(dest.value, os.path.basename(s.value)),
                    dest.expands or s.expands) for s in sources]
    return [dest]


def segment_targets(argv0, words, fed_code):
    """(targets, kind, unsure_reason) for one already-unwrapped command segment.

    `fed_code` is true when the segment could be receiving a program rather than
    only data — a heredoc, an inline `-c`/`-e`, a `<` redirect, or the receiving
    end of a pipe. Piping into an interpreter is how you hand it code, so an
    evaluator on the right of a `|` is exactly as opaque as `python3 -c`.
    """
    base = os.path.basename(argv0)

    if base == "eval" or (base in EVALUATORS and (
            fed_code or any(w.value in INLINE_CODE_FLAGS for w in words))):
        return [], "TARGET", "runs code supplied to it rather than named on the command line; its writes are not visible to a shell parse"
    if base in DISPATCHERS:
        return [], "TARGET", "builds and runs another command at runtime"
    if base == "find" and any(
            w.value in ("-exec", "-execdir", "-delete", "-fprint", "-fprintf") for w in words):
        return [], "TARGET", "runs an action per match; the affected paths are decided at runtime"
    if base in PATCHERS or (base == "git" and words and words[0].value in ("apply", "am")):
        return [], "TARGET", "applies a patch; the written paths are named inside the patch, not on the command line"

    if base in ("rm", "unlink", "shred"):
        return _operands(words), "DELETE", None
    if base == "tee":
        return _operands(words), "TARGET", None
    if base in ("sed", "gsed"):
        return (_script_then_files(words, ("-e", "--expression", "-f", "--file"))
                if _has_inplace(words) else []), "TARGET", None
    if base == "perl" and _has_inplace(words):
        # `perl -i -pe 'CODE' file` — the code is an operand whenever a short
        # cluster ends in `e`; without that rule the program becomes a "target".
        ops = _operands(words)
        code_is_operand = any(
            w.value.startswith("-") and not w.value.startswith("--") and w.value.endswith("e")
            for w in words
        )
        return (ops[1:] if code_is_operand else ops), "TARGET", None
    if base in ("awk", "gawk"):
        if not (_has_inplace(words) and any(w.value == "inplace" for w in words)):
            return [], "TARGET", None
        # gawk spells it `-i inplace`; drop that operand before the program.
        rest = [w for w in words if w.value != "inplace"]
        return _script_then_files(rest, ("-f", "--file")), "TARGET", None
    if base in ("cp", "mv", "install", "rsync", "ln"):
        return _destinations(words), "TARGET", None
    if base in ("touch", "truncate", "sponge"):
        return _operands(words), "TARGET", None
    if base == "dd":
        of = next((w for w in words if w.value.startswith("of=")), None)
        return ([Tok("word", of.value[3:], of.expands)] if of else []), "TARGET", None
    if base == "curl":
        # `-O` takes no value (it reuses the remote name); only `-o` names a file.
        out = _flag_value(words, ("-o", "--output"))
        return ([out] if out is not None else []), "TARGET", None
    if base == "wget":
        out = _flag_value(words, ("-O", "--output-document"))
        return ([out] if out is not None else []), "TARGET", None
    return [], "TARGET", None


def redirect_targets(toks):
    """Targets of output redirections in a token list."""
    out = []
    for idx, tok in enumerate(toks):
        if tok.kind != "op" or tok.value not in REDIRECT_OPS:
            continue
        nxt = toks[idx + 1] if idx + 1 < len(toks) else None
        if nxt is None or nxt.kind != "word":
            continue
        # `2>&1`, `>&2` duplicate a descriptor; they write no file.
        if tok.value == ">&" and nxt.value.isdigit():
            continue
        out.append(nxt)
    return out


def analyze_command(command, cwd):
    """Yield (kind, detail, fragment) records for one Bash command string."""
    command, _ = strip_heredocs(command)
    toks = tokenize(command)

    records = []
    segment = []
    segments = []       # (tokens, preceded_by_pipe)
    piped = False
    for tok in toks:
        if tok.kind == "op" and tok.value in SEGMENT_SEPARATORS:
            segments.append((segment, piped))
            segment = []
            piped = tok.value == "|"
        else:
            segment.append(tok)
    segments.append((segment, piped))

    for seg, piped_in in segments:
        if not seg:
            continue
        fragment = " ".join(t.value for t in seg if t.kind == "word")[:160]

        # An interpreter is handed a PROGRAM, not just data, by any of these.
        fed_code = piped_in or any(
            t.kind == "op" and t.value in ("<<", "<<-", "<") for t in seg)
        targets = list(redirect_targets(seg))

        # Words only, minus redirect operands and the fd numbers glued to them.
        words = []
        skip_next = False
        for idx, tok in enumerate(seg):
            if skip_next:
                skip_next = False
                continue
            if tok.kind == "op":
                if tok.value in REDIRECT_OPS or tok.value in ("<", "<<", "<<-"):
                    skip_next = True
                    if words and words[-1].value.isdigit():
                        words.pop()
                continue
            words.append(tok)

        # Leading `VAR=value` assignments and transparent wrappers.
        while words:
            head = words[0].value
            if "=" in head and not head.startswith("=") and head.split("=", 1)[0].replace("_", "a").isalnum():
                words.pop(0)
                continue
            if os.path.basename(head) in WRAPPERS:
                words.pop(0)
                continue
            break
        if not words:
            continue

        argv0, rest = words[0].value, words[1:]

        # `cd` moves the frame every later relative path is resolved against.
        if argv0 == "cd":
            ops = _operands(rest)
            if not ops:
                cwd = os.path.expanduser("~")
            elif ops[0].expands:
                cwd = None
            else:
                cwd = os.path.normpath(os.path.join(cwd, os.path.expanduser(ops[0].value))) \
                    if cwd else None
            continue

        cmd_targets, kind, unsure = segment_targets(argv0, rest, fed_code)
        if unsure:
            records.append(("UNSURE", unsure, fragment))
        # A redirection always creates content; only the command's own operands
        # can be a deletion.
        targets = [(t, "TARGET") for t in targets] + [(t, kind) for t in cmd_targets]

        for t, t_kind in targets:
            if t.expands or "$" in t.value or "`" in t.value:
                records.append(("UNSURE", "writes to a target built by shell expansion (%s)" % t.value, fragment))
                continue
            path = os.path.expanduser(t.value)
            if not os.path.isabs(path):
                if cwd is None:
                    records.append(("UNSURE", "writes to a relative path after a `cd` this parse could not follow (%s)" % t.value, fragment))
                    continue
                path = os.path.join(cwd, path)
            path = os.path.normpath(path)
            records.append((t_kind, path, fragment))
            if not t.quoted and any(c in t.value for c in "*?["):
                records.append(("UNSURE", "writes to a glob that may cover paths beyond the one checked (%s)" % t.value, fragment))
    return records


# --------------------------------------------------------------------------

EDIT_PATH_KEYS = ("file_path", "path", "notebook_path", "filePath")


def records_for(payload):
    tool = payload.get("tool_name") or ""
    tool_input = payload.get("tool_input") or {}
    cwd = payload.get("cwd") or os.getcwd()

    if tool in ("Bash", "Shell", "BashOutput", "run_terminal_cmd"):
        command = tool_input.get("command") or ""
        if not command.strip():
            return []
        return analyze_command(command, cwd)

    for key in EDIT_PATH_KEYS:
        value = tool_input.get(key)
        if value:
            path = os.path.expanduser(value)
            if not os.path.isabs(path):
                path = os.path.join(cwd, path)
            return [("TARGET", os.path.normpath(path), tool or "edit")]
    return []


def main():
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        sys.stdout.write(__doc__)
        return 0
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
    for kind, detail, fragment in records:
        sys.stdout.write("%s\t%s\t%s\n" % (kind, detail.replace("\t", " "), fragment.replace("\t", " ")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
