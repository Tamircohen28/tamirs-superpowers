#!/usr/bin/env python3
"""
normalize-skill-frontmatter.py — rewrite SKILL.md frontmatter into the canonical
three-tier shape defined by core/schemas/skill-frontmatter.json.

Emitted order:
  1. portable core      name, description, license, compatibility
  2. platform extensions Claude Code fields, untouched and in official order
  3. metadata           metadata.tamirs (framework namespace) last

The normalizer never invents Claude extension fields that a skill does not
already carry — the portable tier no longer requires them. It only fills the
`metadata.tamirs` block, deriving what it safely can:

  visibility     internal when `user-invocable: false`, else public
  category       the skill's domain directory under skills/
  role           preserved if already set, else `none`
  updated-date   preserved from metadata.tamirs or legacy metadata.updated-date,
                 else today
  capabilities   preserved verbatim; never guessed

Usage:
  python3 scripts/normalize-skill-frontmatter.py --dry-run                 # whole tree
  python3 scripts/normalize-skill-frontmatter.py --dry-run path/to/SKILL.md
  python3 scripts/normalize-skill-frontmatter.py path/to/SKILL.md          # writes

Always inspect a --dry-run diff before writing. Verify afterwards with
`python3 scripts/validate-skill-frontmatter.py`.
"""

from __future__ import annotations

import argparse
import datetime as _datetime
import difflib
import sys
from pathlib import Path
from typing import Any

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent

# Tier 1 — portable core, first and in this order.
PORTABLE_ORDER = ["name", "description", "license", "compatibility"]

# Tier 3 — Claude Code / Claude Desktop extensions, preserved in official order.
CLAUDE_ORDER = [
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
    "background",
    "agent",
    "hooks",
    "paths",
    "shell",
]

# Tier 2 — metadata namespace, emitted last.
TAMIRS_ORDER = [
    "visibility",
    "category",
    "capabilities",
    "role",
    "updated-date",
    "validation-tier",
    "tags",
]


def parse_skill(path: Path) -> tuple[dict[str, Any], str]:
    text = path.read_text(encoding="utf-8")
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = normalized.split("\n")
    if not lines or lines[0].strip() != "---":
        raise ValueError(f"no frontmatter: {path}")
    end = None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            end = idx
            break
    if end is None:
        raise ValueError(f"no frontmatter: {path}")
    fm = yaml.safe_load("\n".join(lines[1 : end]))
    if not isinstance(fm, dict):
        raise ValueError(f"invalid frontmatter: {path}")
    body = "\n".join(lines[end + 1 :])
    if body and not body.startswith("\n"):
        body = "\n" + body
    return fm, body


def domain_of(path: Path) -> str | None:
    parts = path.resolve().parts
    if len(parts) >= 4 and parts[-4] == "skills":
        return parts[-3]
    return None


def as_iso(value: Any) -> str | None:
    if isinstance(value, _datetime.date) and not isinstance(value, bool):
        return value.isoformat()
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def build_tamirs(path: Path, fm: dict[str, Any]) -> dict[str, Any]:
    metadata = fm.get("metadata") if isinstance(fm.get("metadata"), dict) else {}
    existing = metadata.get("tamirs") if isinstance(metadata.get("tamirs"), dict) else {}

    tamirs: dict[str, Any] = dict(existing)

    tamirs.setdefault(
        "visibility", "internal" if fm.get("user-invocable") is False else "public"
    )
    domain = domain_of(path)
    if domain:
        tamirs.setdefault("category", domain)
    tamirs.setdefault("role", "none")

    updated = (
        as_iso(existing.get("updated-date"))
        or as_iso(metadata.get("updated-date"))
        or _datetime.date.today().isoformat()
    )
    tamirs["updated-date"] = updated

    ordered: dict[str, Any] = {}
    for key in TAMIRS_ORDER:
        if key in tamirs:
            ordered[key] = tamirs[key]
    for key in sorted(k for k in tamirs if k not in ordered):
        ordered[key] = tamirs[key]
    return ordered


def build_metadata(path: Path, fm: dict[str, Any]) -> dict[str, Any]:
    source = fm.get("metadata") if isinstance(fm.get("metadata"), dict) else {}
    metadata: dict[str, Any] = {}
    # Legacy metadata.updated-date is kept so --profile claude-strict stays green.
    legacy = as_iso(source.get("updated-date"))
    if legacy:
        metadata["updated-date"] = legacy
    for key, value in source.items():
        if key in ("tamirs", "updated-date"):
            continue
        metadata[key] = value
    metadata["tamirs"] = build_tamirs(path, fm)
    if not legacy:
        metadata["updated-date"] = metadata["tamirs"]["updated-date"]
        metadata = {"updated-date": metadata.pop("updated-date"), **metadata}
    return metadata


def normalize_frontmatter(path: Path, fm: dict[str, Any]) -> dict[str, Any]:
    ordered: dict[str, Any] = {}
    for key in PORTABLE_ORDER:
        if key in fm:
            ordered[key] = fm[key]
    for key in CLAUDE_ORDER:
        if key in fm:
            ordered[key] = fm[key]
    for key in sorted(k for k in fm if k not in ordered and k != "metadata"):
        ordered[key] = fm[key]
    ordered["metadata"] = build_metadata(path, fm)
    return ordered


def dump_frontmatter(fm: dict[str, Any]) -> str:
    return (
        yaml.safe_dump(
            fm,
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False,
            width=1000,
        ).rstrip()
        + "\n"
    )


def render(path: Path) -> tuple[str, str]:
    original = path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
    fm, body = parse_skill(path)
    updated = "---\n" + dump_frontmatter(normalize_frontmatter(path, fm)) + "---\n" + body
    return original, updated


def discover(raw_paths: list[str]) -> list[Path]:
    if not raw_paths:
        targets = sorted((REPO_ROOT / "skills").rglob("SKILL.md"))
        targets += sorted((REPO_ROOT / ".claude" / "skills").rglob("SKILL.md"))
        return targets
    targets: list[Path] = []
    for raw in raw_paths:
        p = Path(raw)
        if not p.is_absolute():
            p = REPO_ROOT / p
        targets.extend(sorted(p.rglob("SKILL.md")) if p.is_dir() else [p])
    return targets


def label(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT)) if path.is_relative_to(REPO_ROOT) else str(path)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Normalize SKILL.md frontmatter to the portable + metadata.tamirs shape"
    )
    parser.add_argument("paths", nargs="*", help="SKILL.md files or directories")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print a unified diff of what would change; write nothing",
    )
    args = parser.parse_args()

    targets = discover(args.paths)
    if not targets:
        print("No SKILL.md files found", file=sys.stderr)
        return 1

    changed = 0
    for path in targets:
        original, updated = render(path)
        if original == updated:
            continue
        changed += 1
        if args.dry_run:
            diff = difflib.unified_diff(
                original.splitlines(keepends=True),
                updated.splitlines(keepends=True),
                fromfile=f"a/{label(path)}",
                tofile=f"b/{label(path)}",
            )
            sys.stdout.writelines(diff)
        else:
            path.write_text(updated, encoding="utf-8")
            print(f"normalized {label(path)}")

    verb = "would change" if args.dry_run else "changed"
    print(f"\n{changed} of {len(targets)} SKILL.md file(s) {verb}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
