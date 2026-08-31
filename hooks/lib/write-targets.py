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

# Commands whose write targets are inside a patch we are not reading.
PATCHERS = ("patch",)

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


def _destinations(words, cmd=None):
    """(targets, unsure) — the last operand, expanded over sources if a dir.

    cp/mv/install/rsync/ln. The destination is decided by POSITION, so this is
    the family where an operand list off by one hides the real write.
    """
    explicit_dir = _flag_value(words, ("-t", "--target-directory"))
    ops, unsure = _split_operands(words, cmd)
    if unsure:
        return [], unsure
    if explicit_dir is not None:
        return [Tok("word", os.path.join(explicit_dir.value, os.path.basename(s.value)),
                    explicit_dir.expands or s.expands) for s in ops], None
    if len(ops) < 2:
        return [], None
    dest, sources = ops[-1], ops[:-1]
    if len(sources) > 1 or dest.value.endswith("/") or os.path.isdir(dest.value):
        return [Tok("word", os.path.join(dest.value, os.path.basename(s.value)),
                    dest.expands or s.expands) for s in sources], None
    return [dest], None


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
        return _operands(words, base), "DELETE", None
    if base == "tee":
        return _operands(words, base), "TARGET", None
    if base in ("sed", "gsed"):
        return (_script_then_files(words, ("-e", "--expression", "-f", "--file"), base)
                if _has_inplace(words) else []), "TARGET", None
    if base == "perl" and _has_inplace(words):
        # `-e`/`-E` take the program as their value (including inside a cluster,
        # `-pe 'CODE'`), so the operands left are the files it rewrites.
        return _operands(words, base), "TARGET", None
    if base in ("awk", "gawk"):
        if not (_has_inplace(words) and any(w.value == "inplace" for w in words)):
            return [], "TARGET", None
        # gawk spells it `-i inplace`, consumed as that option's value.
        return _script_then_files(words, ("-f", "--file", "-e", "--source"), base), "TARGET", None
    if base in ("cp", "mv", "install", "rsync", "ln"):
        dests, unsure = _destinations(words, base)
        return dests, "TARGET", unsure
    if base in ("touch", "truncate", "sponge"):
        return _operands(words, base), "TARGET", None
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
    cwd_stack = []

    for seg, piped_in, terminator in segments:
        if seg:
            cwd = _segment_records(seg, piped_in, terminator, cwd, records)
        # The group boundary is the terminator of the segment just processed.
        if terminator == "(":
            cwd_stack.append(cwd)
        elif terminator == ")":
            cwd = cwd_stack.pop() if cwd_stack else None
    return records


def _segment_records(seg, piped_in, terminator, cwd, records):
    """Append this segment's records; return the cwd the NEXT segment sees."""
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
                return cwd
            continue
        break
    if not words:
        return cwd

    argv0, rest = words[0].value, words[1:]

    # `cd` moves the frame every later relative path is resolved against —
    # unless it runs in a subshell, where the move dies with it. A pipeline
    # component is a subshell too, so `cd /tmp | true; echo x > yarn.lock`
    # writes the repo's lockfile, not /tmp's.
    if argv0 == "cd":
        if piped_in or terminator == "|":
            return cwd
        ops = _operands(rest)
        if not ops:
            cwd = os.path.expanduser("~")
        elif ops[0].expands:
            cwd = None
        else:
            cwd = os.path.normpath(os.path.join(cwd, os.path.expanduser(ops[0].value))) \
                if cwd else None
        return cwd

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
    return cwd


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
