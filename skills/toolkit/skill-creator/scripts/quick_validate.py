#!/usr/bin/env python3
"""
quick_validate.py — validate a skill directory against the canonical frontmatter contract.

Delegates to scripts/validate-skill-frontmatter.py, the executable form of
core/schemas/skill-frontmatter.json. This file deliberately contains NO field list of its
own: a second copy of the contract is a second source of truth, and the two would drift.

Usage:
  python3 quick_validate.py <skill_directory> [--require-tamirs]
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

VALIDATOR_REL = Path("scripts") / "validate-skill-frontmatter.py"


def find_validator(start: Path) -> Path | None:
    """Walk up from this file looking for the canonical validator.

    Walking beats a fixed parents[N] index: the skill is copied into plugin caches,
    packaged artifacts and worktrees at varying depths, and a hardcoded depth turns a
    relocated skill into a hard failure instead of a graceful one.
    """
    for parent in [start, *start.parents]:
        candidate = parent / VALIDATOR_REL
        if candidate.is_file():
            return candidate
    return None


def validate_skill(skill_path: str, extra_args: list[str] | None = None) -> tuple[bool, str]:
    root = Path(skill_path)
    if not root.is_dir():
        return False, f"Not a directory: {skill_path}"

    skill_md = root / "SKILL.md"
    if not skill_md.exists():
        return False, "SKILL.md not found"

    validator = find_validator(Path(__file__).resolve().parent)
    if validator is None:
        return False, (
            f"validator not found: no {VALIDATOR_REL} in any parent of {Path(__file__).resolve().parent}. "
            "Run scripts/validate-skill-frontmatter.py from the repo root instead."
        )

    proc = subprocess.run(
        [sys.executable, str(validator), *(extra_args or []), str(skill_md)],
        capture_output=True,
        text=True,
    )
    if proc.returncode == 0:
        return True, "Skill is valid!"
    output = (proc.stdout + proc.stderr).strip()
    return False, output or "frontmatter validation failed"


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        print("Usage: python3 quick_validate.py <skill_directory> [--require-tamirs]")
        sys.exit(1)

    positional = [a for a in args if not a.startswith("-")]
    passthrough = [a for a in args if a.startswith("-")]

    if len(positional) != 1:
        print("Usage: python3 quick_validate.py <skill_directory> [--require-tamirs]")
        sys.exit(1)

    valid, message = validate_skill(positional[0], passthrough)
    print(message)
    sys.exit(0 if valid else 1)
