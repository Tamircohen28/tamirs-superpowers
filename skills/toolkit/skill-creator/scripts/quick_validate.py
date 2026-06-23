#!/usr/bin/env python3
"""
quick_validate.py — validate a skill directory against tamirs-superpowers standards.

Delegates to scripts/validate-skill-frontmatter.py for frontmatter checks.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def validate_skill(skill_path: str) -> tuple[bool, str]:
    root = Path(skill_path)
    if not root.is_dir():
        return False, f"Not a directory: {skill_path}"

    skill_md = root / "SKILL.md"
    if not skill_md.exists():
        return False, "SKILL.md not found"

    repo_root = Path(__file__).resolve().parents[4]
    validator = repo_root / "scripts" / "validate-skill-frontmatter.py"
    if not validator.exists():
        return False, f"validator not found: {validator}"

    proc = subprocess.run(
        [sys.executable, str(validator), str(skill_md)],
        capture_output=True,
        text=True,
    )
    if proc.returncode == 0:
        return True, "Skill is valid!"
    output = (proc.stdout + proc.stderr).strip()
    return False, output or "frontmatter validation failed"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python quick_validate.py <skill_directory>")
        sys.exit(1)

    valid, message = validate_skill(sys.argv[1])
    print(message)
    sys.exit(0 if valid else 1)
