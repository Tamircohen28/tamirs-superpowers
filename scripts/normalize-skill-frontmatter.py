#!/usr/bin/env python3
"""One-shot normalizer: merge full official frontmatter into every SKILL.md."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent

FIELD_ORDER = [
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
    "license",
    "metadata",
]

DEFAULTS: dict[str, Any] = {
    "arguments": [],
    "disallowed-tools": [],
    "hooks": {},
    "paths": [],
    "shell": "bash",
    "context": "",
    "agent": "",
    "model": "claude-sonnet-4-6",
    "disable-model-invocation": False,
    "user-invocable": True,
    "effort": "medium",
}

OVERRIDES: dict[str, dict[str, Any]] = {
    "run-tamirs-superpowers": {
        "argument-hint": "[none — runs full plugin health check]",
        "effort": "low",
    },
    "targeted-debug": {
        "context": "fork",
        "agent": "Explore",
        "disable-model-invocation": True,
        "effort": "medium",
    },
    "plan-dev": {"disable-model-invocation": True, "effort": "high"},
    "start-dev": {"disable-model-invocation": True, "effort": "high"},
    "pr-dev": {"effort": "high"},
    "repo-scaffold": {"effort": "high"},
    "repo-polish": {"disable-model-invocation": True, "effort": "high"},
    "changelog-review": {
        "argument-hint": "[plugin project path or omit for current repo]",
        "disable-model-invocation": True,
        "user-invocable": False,
        "effort": "low",
    },
    "docs-review": {
        "disable-model-invocation": True,
        "user-invocable": False,
        "effort": "low",
    },
    "mcp-pagination": {
        "argument-hint": "[path to MCP tool schema or server source file]",
        "disable-model-invocation": True,
        "user-invocable": False,
        "effort": "low",
    },
    "repo-review": {
        "argument-hint": "[project directory path — defaults to repo root]",
        "disable-model-invocation": True,
        "user-invocable": False,
        "effort": "low",
    },
}


def parse_skill(path: Path) -> tuple[dict[str, Any], str]:
    text = path.read_text(encoding="utf-8")
    match = re.match(r"^(---\n.*?\n---\n)(.*)$", text, re.DOTALL)
    if not match:
        raise ValueError(f"no frontmatter: {path}")
    fm = yaml.safe_load(match.group(1)[4:-4])
    body = match.group(2)
    if not isinstance(fm, dict):
        raise ValueError(f"invalid frontmatter: {path}")
    return fm, body


def dump_frontmatter(fm: dict[str, Any]) -> str:
    ordered: dict[str, Any] = {}
    for key in FIELD_ORDER:
        if key in fm:
            ordered[key] = fm[key]
    for key in sorted(fm.keys()):
        if key not in ordered:
            ordered[key] = fm[key]
    return yaml.dump(
        ordered,
        default_flow_style=False,
        allow_unicode=True,
        sort_keys=False,
        width=1000,
    ).rstrip() + "\n"


def normalize_file(path: Path) -> None:
    fm, body = parse_skill(path)
    skill_name = fm.get("name") or path.parent.name
    merged = {**DEFAULTS, **fm, **OVERRIDES.get(skill_name, {})}
    # Preserve license only when already set.
    if "license" not in fm:
        merged.pop("license", None)
    new_text = "---\n" + dump_frontmatter(merged) + "---\n" + body
    path.write_text(new_text, encoding="utf-8")
    print(f"normalized {path.relative_to(REPO_ROOT)}")


def main() -> None:
    paths = sorted((REPO_ROOT / "skills").rglob("SKILL.md"))
    paths.extend(sorted((REPO_ROOT / ".claude" / "skills").rglob("SKILL.md")))
    for path in paths:
        normalize_file(path)


if __name__ == "__main__":
    main()
