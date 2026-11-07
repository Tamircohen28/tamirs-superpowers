#!/usr/bin/env python3
"""always-on-cost.py — the plugin's always-on context cost, computed from a checkout.

WHY THIS EXISTS
  `claude plugin details` reports the always-on cost (name + description + when_to_use
  of every skill and agent) by sending that text to the count_tokens API. With no API
  credentials, as on a CI runner, it silently falls back to characters / 4, which for
  this plugin's prose reads about 30% low: CI printed ~5,945 while a signed-in machine
  printed ~8,668 for the same tree, so an overrun of the ceiling was invisible to CI
  (issue #401). This script rebuilds the exact text the CLI measures, from the checkout,
  with no CLI and no network, and converts its length to tokens with a characters-per-
  token ratio calibrated against a real tokenizer measurement (evals/budget.json).

WHAT IT REBUILDS (mirrors Claude Code 2.1.319's plugin-details code)
  skill  "<plugin>:<name> <description> <when_to_use>", where description and
         when_to_use have each whitespace run collapsed to one space and `<` / `>`
         escaped to `&lt;` / `&gt;` (the skill listing's sanitizer)
  agent  "<name> <description>", the description trimmed and otherwise verbatim
  Entries are joined with "\\n". Length is counted in UTF-16 code units, as JS does.
  Skills come from the directories in .claude-plugin/plugin.json `skills`, agents from
  `agents` (default agents/), commands from `commands` (default commands/).

Usage:
  always-on-cost.py [repo-root] [--chars-per-token R] [--json]

  Without --chars-per-token the ratio is read from evals/budget.json (`chars_per_token`).
  Plain output is one line:  always-on: <chars> chars, ~<tokens> tok (ratio R)
  --json prints {"chars", "cli_fallback_tokens", "chars_per_token", "tokens", "components"}
  where components carries each skill/agent's own character count, largest first.

Exit 0 on success; 1 on a missing manifest, unparseable frontmatter or missing ratio.
"""
from __future__ import annotations

import argparse
import json
import math
import pathlib
import re
import sys

try:
    import yaml
except ImportError:  # reported, not crashed on
    print("ERROR: PyYAML is required (pip install -r scripts/requirements-validate.txt)", file=sys.stderr)
    sys.exit(1)

WS_RUN = re.compile(r"\s+")


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def frontmatter(path: pathlib.Path) -> dict:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        die(f"{path}: frontmatter is not closed")
    try:
        data = yaml.safe_load(text[3:end]) or {}
    except yaml.YAMLError as exc:
        die(f"{path}: frontmatter does not parse: {exc}")
    if not isinstance(data, dict):
        die(f"{path}: frontmatter is not a mapping")
    return data


def as_text(value) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def listing_clean(value: str) -> str:
    """The skill-listing sanitizer: whitespace runs to one space, angle brackets escaped."""
    return WS_RUN.sub(" ", value).replace("<", "&lt;").replace(">", "&gt;")


def utf16_len(value: str) -> int:
    return len(value.encode("utf-16-le")) // 2


def entry(name: str, description: str, when_to_use: str) -> str:
    return " ".join(part for part in (name, description, when_to_use) if part)


def as_list(value, default: str) -> list[str]:
    if value is None:
        return [default]
    if isinstance(value, str):
        return [value]
    return [v for v in value if isinstance(v, str)]


def main() -> int:
    ap = argparse.ArgumentParser(description="Always-on context cost of the plugin, from the checkout")
    ap.add_argument("root", nargs="?", default=".")
    ap.add_argument("--chars-per-token", type=float, default=None)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    root = pathlib.Path(args.root).resolve()
    manifest_path = root / ".claude-plugin" / "plugin.json"
    if not manifest_path.is_file():
        die(f"missing {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    plugin = manifest.get("name") or die("plugin.json has no name")

    ratio = args.chars_per_token
    if ratio is None:
        budget = root / "evals" / "budget.json"
        if budget.is_file():
            ratio = json.loads(budget.read_text(encoding="utf-8")).get("chars_per_token")
    if not isinstance(ratio, (int, float)) or ratio <= 0:
        die("no chars_per_token: pass --chars-per-token or set it in evals/budget.json")

    components: list[dict] = []

    for rel in as_list(manifest.get("skills"), "./skills"):
        base = (root / rel).resolve()
        candidates = [base / "SKILL.md"] if (base / "SKILL.md").is_file() else sorted(base.glob("*/SKILL.md"))
        for skill_md in candidates:
            fm = frontmatter(skill_md)
            name = as_text(fm.get("name")) or skill_md.parent.name
            description = listing_clean(as_text(fm.get("description")).strip())
            when = listing_clean(as_text(fm.get("when_to_use"))) if fm.get("when_to_use") is not None else ""
            text = entry(f"{plugin}:{name}", description, when)
            components.append({"kind": "skill", "name": name, "chars": utf16_len(text), "text": text})

    for kind, key, default in (("agent", "agents", "./agents"), ("command", "commands", "./commands")):
        for rel in as_list(manifest.get(key), default):
            base = (root / rel).resolve()
            files = [base] if base.is_file() else sorted(base.glob("*.md")) if base.is_dir() else []
            for md in files:
                fm = frontmatter(md)
                name = as_text(fm.get("name")) or md.stem
                description = as_text(fm.get("description")).strip()
                when = as_text(fm.get("when_to_use")) if fm.get("when_to_use") is not None else ""
                if kind == "command":
                    name = f"{plugin}:{name}"
                    description = listing_clean(description)
                    when = listing_clean(when) if when else ""
                text = entry(name, description, when)
                components.append({"kind": kind, "name": name, "chars": utf16_len(text), "text": text})

    if not components:
        die(f"no skills, agents or commands found under {root}")

    total = utf16_len("\n".join(c["text"] for c in components))
    tokens = math.ceil(total / ratio)
    # The CLI's no-credentials fallback: the per-component lengths summed (no joiners),
    # as ceil(chars / 4). A live figure equal to this one was not a tokenizer count.
    fallback = math.ceil(sum(c["chars"] for c in components) / 4)
    if args.json:
        out = {
            "chars": total,
            "cli_fallback_tokens": fallback,
            "chars_per_token": ratio,
            "tokens": tokens,
            "components": [
                {k: c[k] for k in ("kind", "name", "chars")}
                for c in sorted(components, key=lambda c: -c["chars"])
            ],
        }
        print(json.dumps(out, indent=2))
    else:
        print(f"always-on: {total} chars, ~{tokens} tok (ratio {ratio}); cli no-credentials fallback would print ~{fallback}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
