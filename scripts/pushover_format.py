#!/usr/bin/env python3
"""Format a Claude Code Notification hook event for notify-pushover.sh.

Reads the hook JSON on stdin and prints shell-quoted MESSAGE=, PRIORITY= and
PROJECT= assignments on stdout, for the caller to eval.

Any transcript snippet is converted from Markdown to plain text first: Pushover
renders notifications as plain text, so raw Markdown (headings, tables, fences,
**bold**) shows up as unreadable literal syntax on the phone.

Self-test:  python3 pushover_format.py --selftest < some.md
"""

import json
import os
import re
import shlex
import sys

SNIPPET_LIMIT = 300


def markdown_to_text(text):
    """Flatten Markdown into a single plain-text line."""
    t = text

    # Fenced code blocks: closed pairs first, then any unterminated trailing fence.
    t = re.sub(r"```[^\n`]*\n?.*?```", " [code] ", t, flags=re.S)
    t = re.sub(r"~~~[^\n~]*\n?.*?~~~", " [code] ", t, flags=re.S)
    t = re.sub(r"```[^\n`]*\n?.*\Z", " [code] ", t, flags=re.S)

    # HTML comments and tags.
    t = re.sub(r"<!--.*?-->", " ", t, flags=re.S)
    t = re.sub(r"</?[A-Za-z][^>\n]{0,200}>", " ", t)

    # Images before links, so alt/link text survives but URLs do not.
    t = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", t)
    t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)
    t = re.sub(r"\[([^\]]*)\]\[[^\]]*\]", r"\1", t)

    # ATX headings and blockquote markers.
    t = re.sub(r"(?m)^\s{0,3}#{1,6}\s*", "", t)
    t = re.sub(r"(?m)^\s{0,3}>+\s?", "", t)

    # Horizontal rules, then box-drawing rules (the long dash separators).
    # NB: these are line-anchored, so the whitespace classes must exclude \n --
    # a bare \s*$ in multiline mode swallows the newline and fuses adjacent rows.
    t = re.sub(r"(?m)^[ \t]*([-*_=][ \t]*){3,}$", "\n", t)
    t = re.sub(r"[─-▟]{2,}", " ", t)

    # Table separator rows, then table rows flattened to middot-joined cells.
    t = re.sub(r"(?m)^[ \t]*\|?[ \t:|-]{5,}\|?[ \t]*$", "\n", t)
    t = re.sub(
        r"(?m)^[ \t]*\|(.+?)\|?[ \t]*$",
        lambda m: " · ".join(
            c.strip() for c in m.group(1).split("|") if c.strip()
        ),
        t,
    )

    # List markers (task lists before plain bullets).
    t = re.sub(r"(?m)^\s{0,8}[-*+]\s+\[[ xX]\]\s*", "• ", t)
    t = re.sub(r"(?m)^\s{0,8}[-*+]\s+", "• ", t)
    t = re.sub(r"(?m)^\s{0,8}(\d+)[.)]\s+", r"\1. ", t)

    # Emphasis and strikethrough.
    t = re.sub(r"\*\*\*(.+?)\*\*\*", r"\1", t, flags=re.S)
    t = re.sub(r"\*\*(.+?)\*\*", r"\1", t, flags=re.S)
    t = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"\1", t, flags=re.S)
    t = re.sub(r"(?<![\w_])__(?!\s)(.+?)(?<!\s)__(?![\w_])", r"\1", t, flags=re.S)
    t = re.sub(r"(?<![\w_])_(?!\s)(.+?)(?<!\s)_(?![\w_])", r"\1", t, flags=re.S)
    t = re.sub(r"~~(.+?)~~", r"\1", t, flags=re.S)

    # Inline code.
    t = re.sub(r"`+([^`\n]+)`+", r"\1", t)

    # Collapse to a single line, then tidy separator runs.
    t = re.sub(r"\s+", " ", t)
    t = re.sub(r"(?:\s*·\s*)+", " · ", t)
    t = re.sub(r"(?:\s*•\s*){2,}", " • ", t)
    return t.strip(" ·•\t\n")


def truncate(text, limit=SNIPPET_LIMIT):
    """Cut to limit chars on a word boundary, adding an ellipsis."""
    if len(text) <= limit:
        return text
    cut = text[:limit].rsplit(" ", 1)[0].rstrip(" ,;:.·•")
    return (cut or text[:limit]) + "…"


def last_assistant_snippet(path):
    """Return the newest assistant message from a transcript, as plain text."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except OSError:
        return ""

    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue

        message = entry.get("message", entry)
        if not isinstance(message, dict):
            continue
        if entry.get("type") != "assistant" and message.get("role") != "assistant":
            continue

        content = message.get("content")
        if isinstance(content, list):
            content = " ".join(
                block.get("text", "")
                for block in content
                if isinstance(block, dict) and block.get("type") == "text"
            )

        # Strip first, then test: a message that is pure Markdown chrome
        # flattens to nothing, so fall through to the previous message.
        plain = markdown_to_text((content or "").strip())
        if plain:
            return truncate(plain)
    return ""


def main():
    if "--selftest" in sys.argv:
        sys.stdout.write(markdown_to_text(sys.stdin.read()) + "\n")
        return 0

    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 1

    msg = data.get("message") or "Claude Code needs you"
    ntype = data.get("notification_type", "")
    project = os.path.basename(data.get("cwd") or "") or "claude"

    snippet = ""
    if os.environ.get("INCLUDE_SNIPPET") == "1" and ntype == "idle_prompt":
        transcript = data.get("transcript_path")
        if transcript:
            snippet = last_assistant_snippet(transcript)

    body = markdown_to_text(msg) or msg
    if snippet:
        body = "{0}\n\n“{1}”".format(body, snippet)

    # Pushover priority: -2 lowest, -1 low, 0 normal, 1 high, 2 emergency.
    # Priority 1 bypasses quiet hours, so idle defaults to 0 to avoid 3am pings.
    if ntype == "permission_prompt":
        priority = os.environ.get("PUSHOVER_PERMISSION_PRIORITY", "1")
    else:
        priority = os.environ.get("PUSHOVER_IDLE_PRIORITY", "0")

    print("MESSAGE=" + shlex.quote(body))
    print("PRIORITY=" + shlex.quote(priority))
    print("PROJECT=" + shlex.quote(project))
    return 0


if __name__ == "__main__":
    sys.exit(main())
