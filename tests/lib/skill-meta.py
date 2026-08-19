#!/usr/bin/env python3
"""skill-meta.py — one JSON array describing every SKILL.md in the repo.

Written for tests/test-skill-contract.sh. The contract test is bash, but the
facts it asserts on (YAML frontmatter, markdown link targets) are not things
bash should be parsing by hand — a regex frontmatter reader is exactly the kind
of "test" that passes on a file it silently misread.

Emitted per skill:
  file, dir, domain, name, description_len, when_to_use, visibility,
  user_invocable, disable_model_invocation, validation_tier,
  capabilities_required[], capabilities_optional[],
  refs[]     local paths referenced from frontmatter or the body
  scripts[]  referenced paths under scripts/ or ending in .sh/.py

Usage: skill-meta.py [repo-root]
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover - reported by the caller, not crashed on
    print(json.dumps({"error": "pyyaml-missing"}))
    sys.exit(3)

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()

# Markdown links and bare backticked paths that look like repo-relative files.
LINK = re.compile(r"\[[^\]]*\]\(([^)#\s]+)\)")
FENCED = re.compile(r"```.*?```", re.S)


def frontmatter(text: str):
    if not text.startswith("---"):
        return None, text
    end = text.find("\n---", 3)
    if end == -1:
        return None, text
    raw = text[3:end]
    try:
        return yaml.safe_load(raw) or {}, text[end + 4:]
    except yaml.YAMLError:
        return {}, text[end + 4:]


def local_refs(body: str, skill_dir: pathlib.Path):
    """Repo-relative paths a reader is told to open. External URLs are skipped:
    they are the docs tests' problem, not the skill contract's."""
    out = []
    for target in LINK.findall(FENCED.sub("", body)):
        if target.startswith(("http://", "https://", "mailto:")):
            continue
        target = target.split("#", 1)[0]
        if not target:
            continue
        candidate = (skill_dir / target).resolve()
        try:
            rel = candidate.relative_to(ROOT)
        except ValueError:
            rel = None
        out.append({
            "target": target,
            "resolved": str(rel) if rel else str(candidate),
            "exists": candidate.exists(),
            "escapes_repo": rel is None,
        })
    return out


skills = []
for path in sorted(ROOT.glob("skills/*/*/SKILL.md")):
    text = path.read_text(encoding="utf-8", errors="replace")
    fm, body = frontmatter(text)
    fm = fm if isinstance(fm, dict) else {}
    meta = fm.get("metadata") or {}
    tam = (meta.get("tamirs") or {}) if isinstance(meta, dict) else {}
    caps = tam.get("capabilities") or {}
    refs = local_refs(body, path.parent)
    skills.append({
        "file": str(path.relative_to(ROOT)),
        "dir": path.parent.name,
        "domain": path.parent.parent.name,
        "has_frontmatter": bool(fm),
        "name": fm.get("name"),
        "description": fm.get("description") or "",
        "description_len": len(fm.get("description") or ""),
        "when_to_use": bool(fm.get("when_to_use")),
        "visibility": tam.get("visibility"),
        "user_invocable": fm.get("user-invocable"),
        "disable_model_invocation": fm.get("disable-model-invocation"),
        "validation_tier": tam.get("validation-tier"),
        "capabilities_required": caps.get("required") or [],
        "capabilities_optional": caps.get("optional") or [],
        "refs": refs,
        "scripts": [r for r in refs if r["target"].endswith((".sh", ".py"))],
    })

json.dump(skills, sys.stdout, indent=2)
sys.stdout.write("\n")
