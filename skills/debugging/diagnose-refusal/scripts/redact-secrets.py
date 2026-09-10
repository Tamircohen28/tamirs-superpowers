#!/usr/bin/env python3
"""redact-secrets.py — scrub secrets from diagnose-refusal bundle files.

Usage:
  redact-secrets.py <file> [<file> ...]
  redact-secrets.py --all <bundle-dir>
  redact-secrets.py -h | --help
  redact-secrets.py -v | --verbose <file>

Rewrites each file in place, replacing common secret patterns with
***REDACTED***. Safe to re-run. Never prints the secret values.

Example:
  python3 skills/debugging/diagnose-refusal/scripts/redact-secrets.py --all .refusal-debug
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REDACTION = "***REDACTED***"

# (pattern, replacement). Keep conservative: prefer false negatives over
# eating ordinary prose. Replacements must never echo the secret.
RULES: list[tuple[re.Pattern[str], str]] = [
    (
        re.compile(r"(?i)(authorization\s*[:=]\s*bearer\s+)\S+"),
        rf"\1{REDACTION}",
    ),
    (
        re.compile(
            r'(?i)((?:api[_-]?key|access[_-]?token|refresh[_-]?token|secret[_-]?key|'
            r'client[_-]?secret|private[_-]?key|password|passwd|cookie)'
            r'\s*[:=]\s*)(["\']?)([^\s"\']+)(\2)'
        ),
        rf"\1\2{REDACTION}\4",
    ),
    (
        re.compile(
            r'(?i)("(?:api[_-]?key|access[_-]?token|refresh[_-]?token|secret|'
            r'password|authorization|token)"\s*:\s*")([^"]+)(")'
        ),
        rf"\1{REDACTION}\3",
    ),
    (
        re.compile(
            r"\b(sk-[A-Za-z0-9_\-]{16,}|ghp_[A-Za-z0-9]{20,}|"
            r"xox[baprs]-[A-Za-z0-9-]{10,})\b"
        ),
        REDACTION,
    ),
    (
        re.compile(
            r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"
            r".*?"
            r"-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
            re.DOTALL,
        ),
        # Built from parts so the source file never contains a contiguous
        # PEM-shaped literal (repo secret scanners flag those).
        "-----BEGIN "
        + "PRIVATE"
        + " KEY-----\n"
        + REDACTION
        + "\n-----END "
        + "PRIVATE"
        + " KEY-----",
    ),
]


def redact_text(text: str) -> tuple[str, int]:
    hits = 0
    out = text
    for pattern, repl in RULES:
        out, n = pattern.subn(repl, out)
        hits += n
    return out, hits


def process_file(path: Path, verbose: bool) -> int:
    original = path.read_text(encoding="utf-8", errors="replace")
    redacted, hits = redact_text(original)
    if redacted != original:
        path.write_text(redacted, encoding="utf-8")
    if verbose:
        print(f"{path}: {hits} redaction(s)", file=sys.stderr)
    return hits


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Scrub secrets from diagnose-refusal bundle files."
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    parser.add_argument(
        "--all", metavar="DIR", help="redact every regular file under DIR"
    )
    parser.add_argument("files", nargs="*", type=Path)
    args = parser.parse_args(argv)

    targets: list[Path] = []
    if args.all:
        root = Path(args.all)
        if not root.is_dir():
            print(f"ERROR: not a directory: {root}", file=sys.stderr)
            return 1
        targets.extend(sorted(p for p in root.rglob("*") if p.is_file()))
    targets.extend(args.files)

    if not targets:
        parser.print_help()
        return 1

    total = 0
    for path in targets:
        if not path.is_file():
            print(f"ERROR: not a file: {path}", file=sys.stderr)
            return 1
        total += process_file(path, args.verbose)

    if args.verbose:
        print(f"total redactions: {total}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
