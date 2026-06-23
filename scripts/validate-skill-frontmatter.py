#!/usr/bin/env python3
"""
validate-skill-frontmatter.py — CI gate for SKILL.md YAML frontmatter.

Enforces every official Claude Code frontmatter field (see
https://code.claude.com/docs/en/skills) plus repo conventions (metadata.updated-date).

Usage:
  python3 scripts/validate-skill-frontmatter.py              # all skills/
  python3 scripts/validate-skill-frontmatter.py path/to/SKILL.md
  python3 scripts/validate-skill-frontmatter.py --json path/to/SKILL.md
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML required (pip install pyyaml)", file=sys.stderr)
    sys.exit(1)

# Official Claude Code SKILL.md frontmatter fields (docs table, 2026-06).
OFFICIAL_FIELDS = frozenset(
    {
        "name",
        "description",
        "when_to_use",
        "argument-hint",
        "arguments",
        "disable-model-invocation",
        "user-invocable",
        "allowed-tools",
        "disallowed-tools",
        "model",
        "effort",
        "context",
        "agent",
        "hooks",
        "paths",
        "shell",
    }
)

# Repo-specific optional extensions (allowed but not required by Claude Code).
REPO_OPTIONAL_FIELDS = frozenset({"metadata", "license"})

EFFORT_LEVELS = frozenset({"low", "medium", "high", "xhigh", "max"})
SHELL_VALUES = frozenset({"bash", "powershell"})
KEBAB_NAME = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def extract_frontmatter_text(text: str) -> tuple[str | None, str | None]:
    """Extract YAML between first two --- delimiters; tolerates CRLF."""
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    if not normalized.startswith("---"):
        return None, "missing opening ---"
    lines = normalized.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, "missing opening ---"
    end = None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            end = idx
            break
    if end is None:
        return None, "missing closing ---"
    return "\n".join(lines[1:end]), None


def parse_frontmatter(path: Path) -> tuple[dict[str, Any] | None, str | None]:
    text = path.read_text(encoding="utf-8")
    frontmatter_text, parse_error = extract_frontmatter_text(text)
    if parse_error:
        return None, parse_error
    assert frontmatter_text is not None
    try:
        data = yaml.safe_load(frontmatter_text)
    except yaml.YAMLError as exc:
        return None, f"invalid YAML: {exc}"
    if not isinstance(data, dict):
        return None, "frontmatter must be a YAML mapping"
    return data, None


def validate_frontmatter(path: Path, fm: dict[str, Any]) -> list[str]:
    errors: list[str] = []

    # All official fields must be present.
    missing = sorted(OFFICIAL_FIELDS - set(fm.keys()))
    if missing:
        errors.append(f"missing official field(s): {', '.join(missing)}")

    unexpected = sorted(set(fm.keys()) - OFFICIAL_FIELDS - REPO_OPTIONAL_FIELDS)
    if unexpected:
        errors.append(f"unexpected field(s): {', '.join(unexpected)}")

    name = fm.get("name")
    if not isinstance(name, str) or not name.strip():
        errors.append("name must be a non-empty string")
    elif not KEBAB_NAME.match(name.strip()):
        errors.append(f"name '{name}' must be kebab-case")
    elif len(name) > 64:
        errors.append(f"name exceeds 64 characters ({len(name)})")

    # Directory name should match name (plugin-root .claude/skills exempt).
    skill_dir = path.parent.name
    if path.parts[-4:-2] != (".claude", "skills") and name and name != skill_dir:
        errors.append(f"name '{name}' must match directory '{skill_dir}'")

    description = fm.get("description")
    if not isinstance(description, str) or not description.strip():
        errors.append("description must be a non-empty string")

    when_to_use = fm.get("when_to_use")
    if not isinstance(when_to_use, str) or not when_to_use.strip():
        errors.append("when_to_use must be a non-empty string")
    elif isinstance(description, str):
        combined_len = len(description.strip()) + len(when_to_use.strip())
        if combined_len > 1536:
            errors.append(
                f"description + when_to_use length {combined_len} exceeds 1536-char listing cap"
            )

    argument_hint = fm.get("argument-hint")
    if not isinstance(argument_hint, str) or not argument_hint.strip():
        errors.append("argument-hint must be a non-empty string")

    arguments = fm.get("arguments")
    if not isinstance(arguments, list):
        errors.append("arguments must be a YAML list (use [] when none)")

    for bool_field in ("disable-model-invocation", "user-invocable"):
        value = fm.get(bool_field)
        if not isinstance(value, bool):
            errors.append(f"{bool_field} must be a boolean (true or false)")

    for list_field in ("allowed-tools", "disallowed-tools", "paths"):
        value = fm.get(list_field)
        if not isinstance(value, list):
            errors.append(f"{list_field} must be a YAML list")
        elif list_field == "allowed-tools" and not value:
            errors.append("allowed-tools must list at least one tool")

    model = fm.get("model")
    if not isinstance(model, str) or not model.strip():
        errors.append("model must be a non-empty string")

    effort = fm.get("effort")
    if not isinstance(effort, str) or effort not in EFFORT_LEVELS:
        errors.append(f"effort must be one of: {', '.join(sorted(EFFORT_LEVELS))}")

    context = fm.get("context")
    agent = fm.get("agent")
    if context == "fork":
        if not isinstance(agent, str) or not agent.strip():
            errors.append("agent must be set when context is fork")
    else:
        if context not in (None, ""):
            errors.append("context must be empty or 'fork'")
        if agent not in (None, ""):
            errors.append("agent must be empty when context is not fork")

    hooks = fm.get("hooks")
    if not isinstance(hooks, dict):
        errors.append("hooks must be a YAML mapping (use {} when none)")

    shell = fm.get("shell")
    if shell not in SHELL_VALUES:
        errors.append(f"shell must be one of: {', '.join(sorted(SHELL_VALUES))}")

    user_invocable = fm.get("user-invocable")
    disable_model = fm.get("disable-model-invocation")
    if user_invocable is False and disable_model is not True:
        errors.append("user-invocable: false requires disable-model-invocation: true")

    metadata = fm.get("metadata")
    if not isinstance(metadata, dict):
        errors.append("metadata must be a mapping with updated-date")
    else:
        updated = metadata.get("updated-date")
        if not isinstance(updated, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", updated):
            errors.append("metadata.updated-date must be YYYY-MM-DD")

    return errors


def validate_file(path: Path) -> dict[str, Any]:
    fm, parse_error = parse_frontmatter(path)
    if parse_error:
        return {"file": str(path), "passed": False, "errors": [parse_error]}
    assert fm is not None
    errors = validate_frontmatter(path, fm)
    return {"file": str(path), "passed": not errors, "errors": errors}


def discover_skill_files(root: Path) -> list[Path]:
    files = sorted(root.rglob("SKILL.md"))
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate SKILL.md frontmatter")
    parser.add_argument(
        "paths",
        nargs="*",
        help="SKILL.md files or directories (default: skills/ and .claude/skills/)",
    )
    parser.add_argument("--json", action="store_true", help="Emit JSON per file")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    if args.paths:
        targets: list[Path] = []
        for raw in args.paths:
            p = Path(raw)
            if not p.is_absolute():
                p = repo_root / p
            if p.is_dir():
                targets.extend(sorted(p.rglob("SKILL.md")))
            else:
                targets.append(p)
    else:
        targets = discover_skill_files(repo_root / "skills")
        targets.extend(discover_skill_files(repo_root / ".claude" / "skills"))

    if not targets:
        print("No SKILL.md files found", file=sys.stderr)
        return 1

    failed = 0
    for path in targets:
        result = validate_file(path)
        rel = path.relative_to(repo_root) if path.is_relative_to(repo_root) else path
        if not result["passed"]:
            failed += 1
        if args.json:
            print(json.dumps({**result, "file": str(rel)}))
        elif result["passed"]:
            print(f"  OK  {rel}")
        else:
            print(f"  FAIL {rel}")
            for err in result["errors"]:
                print(f"       - {err}")

    if failed:
        print(f"\n{failed} SKILL.md file(s) failed frontmatter validation", file=sys.stderr)
        return 1
    if not args.json:
        print(f"All {len(targets)} SKILL.md file(s) passed frontmatter validation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
