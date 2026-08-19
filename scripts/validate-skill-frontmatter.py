#!/usr/bin/env python3
"""
validate-skill-frontmatter.py — tiered CI gate for SKILL.md YAML frontmatter.

Canonical contract: core/schemas/skill-frontmatter.json (JSON Schema 2020-12).
This script is the executable form of that schema. It intentionally depends on
nothing beyond python3 + PyYAML (see scripts/requirements-validate.txt), so the
enum/role vocabularies are read out of the schema file at runtime rather than
duplicated here.

Three tiers are validated and reported independently:

  portable  Agent Skills standard core (name, description, optional license /
            compatibility). REQUIRED on every skill, every platform.
            Violations FAIL the build.
  tamirs    metadata.tamirs framework namespace. Validated when present;
            absence is a WARNING during migration. --require-tamirs promotes
            absence to a failure.
  claude    Claude Code / Claude Desktop extension fields. Validated when
            present, plus name<->directory match, listing-length cap, and
            existence of referenced references//scripts/ paths.

Usage:
  python3 scripts/validate-skill-frontmatter.py                 # skills/ + .claude/skills/
  python3 scripts/validate-skill-frontmatter.py path/to/SKILL.md
  python3 scripts/validate-skill-frontmatter.py --json
  python3 scripts/validate-skill-frontmatter.py --require-tamirs
"""

from __future__ import annotations

import argparse
import datetime as _datetime
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

REPO_ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = REPO_ROOT / "core" / "schemas" / "skill-frontmatter.json"
ROLES_DIR = REPO_ROOT / "core" / "roles"
# `none` is a sentinel meaning "outside the orchestration graph", not a role that
# core/roles/ defines. It is the only role id this script owns.
ROLE_SENTINEL = "none"

CAPABILITY_REGISTRY_DIR = REPO_ROOT / "core" / "capabilities"
# schema.json declares the canonical id vocabulary as an enum; platforms.json is
# the registry instance and keys its `capability_definitions` by the same ids.
# registry.json is accepted as an alternate instance name. All are optional —
# the capability check is skipped, and says so, when none is readable.
CAPABILITY_REGISTRY_PATHS = (
    CAPABILITY_REGISTRY_DIR / "schema.json",
    CAPABILITY_REGISTRY_DIR / "platforms.json",
    CAPABILITY_REGISTRY_DIR / "registry.json",
)

TIERS = ("portable", "tamirs", "claude")

# ---------------------------------------------------------------------------
# Vocabulary — sourced from the canonical schema, with fallbacks so the script
# still runs if the schema file is missing (e.g. a partial checkout).
# ---------------------------------------------------------------------------

FALLBACK_VOCAB: dict[str, Any] = {
    "roles": [
        "planner",
        "orchestrator",
        "implementer",
        "test-engineer",
        "reviewer",
        "security-reviewer",
        "performance-reviewer",
        "debugger",
        "integrator",
        "research-agent",
        "none",
    ],
    "visibility": ["public", "internal"],
    "effort": ["low", "medium", "high", "xhigh", "max"],
    "shell": ["bash", "powershell"],
    "context": ["", "fork"],
    "platforms": [
        "claude-code",
        "claude-desktop",
        "codex",
        "cursor",
        "gemini",
        "opencode",
    ],
    "support_levels": ["supported", "partial", "emulated", "unsupported"],
}

_SIBLING_SKILL_DIRS: list[Path] | None = None

KEBAB = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def is_iso_date(value: Any) -> bool:
    """YAML turns an unquoted 2026-08-19 into a date object; both forms are fine."""
    if isinstance(value, _datetime.date) and not isinstance(value, bool):
        return True
    return isinstance(value, str) and bool(ISO_DATE.match(value))
LISTING_CAP = 1536

# Skill-owned asset references in the body.
#
# Two forms are checked, and only two — repo-generating skills (repo-scaffold,
# multi-agent-repo, ...) legitimately name `scripts/`, `assets/` and
# `templates/` paths that belong to the TARGET repo they scaffold, not to the
# skill, so a bare mention of those directories is not evidence of a broken
# link. What is always skill-owned is `references/` and `evals/` prose, plus
# anything explicitly anchored to the skill directory variable.
SKILL_OWNED_REF = re.compile(
    r"(?<![\w./-])((?:references|evals)/[A-Za-z0-9._-]+"
    r"(?:/[A-Za-z0-9._-]+)*\.[A-Za-z0-9]{1,6})"
)
ANCHORED_REF = re.compile(
    r"\$(?:CLAUDE_)?SKILL_DIR/((?:[A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+\.[A-Za-z0-9]{1,6})"
)


def load_vocab() -> dict[str, Any]:
    vocab = dict(FALLBACK_VOCAB)
    try:
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return vocab
    defs = schema.get("$defs", {})
    tamirs = defs.get("tamirsMetadata", {}).get("properties", {})
    claude = defs.get("claude", {}).get("$defs", {})
    compat = defs.get("compatibility", {})

    def enum_of(node: Any) -> list[str] | None:
        if isinstance(node, dict) and isinstance(node.get("enum"), list):
            return [str(v) for v in node["enum"]]
        return None

    for key, node in (
        ("roles", tamirs.get("role")),
        ("visibility", tamirs.get("visibility")),
        ("effort", claude.get("effort")),
        ("shell", claude.get("shell")),
        ("context", claude.get("context")),
    ):
        found = enum_of(node)
        if found is not None:
            vocab[key] = found

    names = compat.get("propertyNames", {})
    if isinstance(names.get("enum"), list):
        vocab["platforms"] = [str(v) for v in names["enum"]]
    levels = enum_of(compat.get("additionalProperties"))
    if levels is not None:
        vocab["support_levels"] = levels

    # core/roles/ is canonical for the role list (see core/roles/README.md).
    # Deriving it means adding an eleventh role is a new .md file and nothing
    # else — no schema edit, no validator edit. The schema enum is kept as
    # documentation of record and cross-checked below, never as the source.
    derived_roles = discover_roles()
    if derived_roles is not None:
        vocab["schema_roles"] = list(vocab["roles"])
        vocab["roles"] = derived_roles
        vocab["roles_source"] = "core/roles/"
    else:
        vocab["schema_roles"] = list(vocab["roles"])
        vocab["roles_source"] = "core/schemas/skill-frontmatter.json"
    return vocab


def discover_roles() -> list[str] | None:
    """Canonical role ids: one core/roles/<role>.md per role, plus the sentinel."""
    if not ROLES_DIR.is_dir():
        return None
    ids = sorted(
        path.stem
        for path in ROLES_DIR.glob("*.md")
        if path.stem.lower() != "readme"
    )
    if not ids:
        return None
    return ids + [ROLE_SENTINEL]


VOCAB = load_vocab()


def _ids_from_capability_document(data: Any) -> set[str]:
    """Pull capability ids out of either the registry schema or the instance.

    Two shapes, per core-registry: `$defs.capabilityKey.enum` in schema.json is
    the authoritative vocabulary, and `capability_definitions` in platforms.json
    is keyed by the same ids. `scripts/check-capability-registry.sh` holds the
    two in agreement, so reading both and unioning them cannot introduce drift.
    """
    if not isinstance(data, dict):
        return set()
    ids: set[str] = set()

    # Authoritative: the registry schema declares the id vocabulary as an enum.
    defs = data.get("$defs")
    if isinstance(defs, dict):
        key_def = defs.get("capabilityKey")
        if isinstance(key_def, dict) and isinstance(key_def.get("enum"), list):
            ids |= {str(v) for v in key_def["enum"]}

    # Instance documents key their definitions by the same ids.
    definitions = data.get("capability_definitions")
    if isinstance(definitions, dict):
        ids |= set(definitions.keys())

    return ids


def role_vocabulary_drift() -> list[str]:
    """Report disagreement between core/roles/ and the schema's role enum.

    Never fatal: core/roles/ is authoritative, so a newly added role validates
    immediately and the build does not wait on a schema edit. But a silent
    disagreement is exactly the drift this project forbids, so it is surfaced
    by name.
    """
    if VOCAB.get("roles_source") != "core/roles/":
        return []
    canonical = set(VOCAB["roles"])
    documented = set(VOCAB.get("schema_roles") or [])
    notes: list[str] = []
    missing = sorted(canonical - documented)
    stale = sorted(documented - canonical)
    if missing:
        notes.append(
            "core/schemas/skill-frontmatter.json role enum is missing: "
            + ", ".join(missing)
            + " (defined in core/roles/; accepted anyway)"
        )
    if stale:
        notes.append(
            "core/schemas/skill-frontmatter.json role enum lists role(s) with no "
            "core/roles/ definition: " + ", ".join(stale) + " (rejected)"
        )
    return notes


def load_capability_ids() -> set[str] | None:
    """Canonical capability ids. None = registry unavailable, check is skipped.

    Reads the registry schema (which carries the id enum) and, when present,
    the registry data document beside it. Never guesses from unrelated keys —
    an unrecognisable registry is reported as absent rather than as an empty
    vocabulary that would fail every declaration.
    """
    ids: set[str] = set()
    for candidate in CAPABILITY_REGISTRY_PATHS:
        try:
            data = json.loads(candidate.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        ids |= _ids_from_capability_document(data)
    return ids or None


# ---------------------------------------------------------------------------
# Frontmatter parsing
# ---------------------------------------------------------------------------


def extract_frontmatter_text(text: str) -> tuple[str | None, str | None, str]:
    """Return (frontmatter, error, body); tolerates CRLF."""
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = normalized.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, "missing opening ---", ""
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            return "\n".join(lines[1:idx]), None, "\n".join(lines[idx + 1 :])
    return None, "missing closing ---", ""


def parse_frontmatter(path: Path) -> tuple[dict[str, Any] | None, str | None, str]:
    text = path.read_text(encoding="utf-8")
    fm_text, parse_error, body = extract_frontmatter_text(text)
    if parse_error:
        return None, parse_error, ""
    assert fm_text is not None
    try:
        data = yaml.safe_load(fm_text)
    except yaml.YAMLError as exc:
        return None, f"invalid YAML: {exc}", body
    if not isinstance(data, dict):
        return None, "frontmatter must be a YAML mapping", body
    return data, None, body


# ---------------------------------------------------------------------------
# Tier: portable
# ---------------------------------------------------------------------------


def check_portable(path: Path, fm: dict[str, Any]) -> list[str]:
    errors: list[str] = []

    name = fm.get("name")
    if not isinstance(name, str) or not name.strip():
        errors.append("name must be a non-empty string")
    else:
        name = name.strip()
        if not KEBAB.match(name):
            errors.append(f"name '{name}' must be kebab-case")
        if len(name) > 64:
            errors.append(f"name exceeds 64 characters ({len(name)})")

    description = fm.get("description")
    if not isinstance(description, str) or not description.strip():
        errors.append("description must be a non-empty string")
    elif len(description.strip()) > LISTING_CAP:
        errors.append(
            f"description length {len(description.strip())} exceeds {LISTING_CAP}-char cap"
        )

    if "license" in fm and (not isinstance(fm["license"], str) or not fm["license"].strip()):
        errors.append("license must be a non-empty string when present")

    compat = fm.get("compatibility")
    if compat is not None:
        if not isinstance(compat, dict):
            errors.append("compatibility must be a mapping of platform -> support level")
        else:
            for platform, level in compat.items():
                if platform not in VOCAB["platforms"]:
                    errors.append(
                        f"compatibility platform '{platform}' unknown "
                        f"(expected one of: {', '.join(VOCAB['platforms'])})"
                    )
                if level not in VOCAB["support_levels"]:
                    errors.append(
                        f"compatibility.{platform} must be one of: "
                        f"{', '.join(VOCAB['support_levels'])}"
                    )

    if "metadata" in fm and not isinstance(fm["metadata"], dict):
        errors.append("metadata must be a mapping when present")

    return errors


# ---------------------------------------------------------------------------
# Tier: tamirs
# ---------------------------------------------------------------------------


def domain_of(path: Path) -> str | None:
    """skills/<domain>/<skill>/SKILL.md -> <domain>."""
    parts = path.parts
    if len(parts) >= 4 and parts[-4] == "skills":
        return parts[-3]
    return None


def check_tamirs(
    path: Path, fm: dict[str, Any], capability_ids: set[str] | None
) -> tuple[list[str], list[str]]:
    """Return (errors, warnings) for the metadata.tamirs tier."""
    errors: list[str] = []
    warnings: list[str] = []

    metadata = fm.get("metadata")
    tamirs = metadata.get("tamirs") if isinstance(metadata, dict) else None

    if tamirs is None:
        warnings.append(
            "metadata.tamirs is absent — add the framework metadata block "
            "(see docs/engineering/architecture/skill-schema.md)"
        )
        return errors, warnings

    if not isinstance(tamirs, dict):
        errors.append("metadata.tamirs must be a mapping")
        return errors, warnings

    known = {
        "visibility",
        "category",
        "capabilities",
        "role",
        "updated-date",
        "validation-tier",
        "tags",
    }
    unexpected = sorted(set(tamirs) - known)
    if unexpected:
        errors.append(f"metadata.tamirs unexpected key(s): {', '.join(unexpected)}")

    for required in ("visibility", "category", "role", "updated-date"):
        if required not in tamirs:
            errors.append(f"metadata.tamirs.{required} is required")

    visibility = tamirs.get("visibility")
    if visibility is not None and visibility not in VOCAB["visibility"]:
        errors.append(
            f"metadata.tamirs.visibility must be one of: {', '.join(VOCAB['visibility'])}"
        )

    category = tamirs.get("category")
    if category is not None:
        if not isinstance(category, str) or not KEBAB.match(category):
            errors.append("metadata.tamirs.category must be a kebab-case domain name")
        else:
            domain = domain_of(path)
            if domain and category != domain:
                errors.append(
                    f"metadata.tamirs.category '{category}' must match domain directory '{domain}'"
                )

    role = tamirs.get("role")
    if role is not None and role not in VOCAB["roles"]:
        errors.append(f"metadata.tamirs.role must be one of: {', '.join(VOCAB['roles'])}")

    updated = tamirs.get("updated-date")
    if updated is not None and not is_iso_date(updated):
        errors.append("metadata.tamirs.updated-date must be YYYY-MM-DD")

    tier = tamirs.get("validation-tier")
    if tier is not None and (not isinstance(tier, int) or isinstance(tier, bool) or not 0 <= tier <= 3):
        errors.append("metadata.tamirs.validation-tier must be an integer 0-3")

    tags = tamirs.get("tags")
    if tags is not None and (
        not isinstance(tags, list) or not all(isinstance(t, str) and t for t in tags)
    ):
        errors.append("metadata.tamirs.tags must be a list of non-empty strings")

    caps = tamirs.get("capabilities")
    if caps is not None:
        if not isinstance(caps, dict):
            errors.append("metadata.tamirs.capabilities must be a mapping")
        else:
            extra = sorted(set(caps) - {"required", "optional"})
            if extra:
                errors.append(
                    f"metadata.tamirs.capabilities unexpected key(s): {', '.join(extra)}"
                )
            declared: list[str] = []
            for bucket in ("required", "optional"):
                value = caps.get(bucket)
                if value is None:
                    continue
                if not isinstance(value, list) or not all(
                    isinstance(c, str) and c for c in value
                ):
                    errors.append(
                        f"metadata.tamirs.capabilities.{bucket} must be a list of capability ids"
                    )
                    continue
                if len(set(value)) != len(value):
                    errors.append(
                        f"metadata.tamirs.capabilities.{bucket} contains duplicate ids"
                    )
                declared.extend(value)
            overlap = sorted(
                set(caps.get("required") or []) & set(caps.get("optional") or [])
            )
            if overlap:
                errors.append(
                    f"capability id(s) listed as both required and optional: {', '.join(overlap)}"
                )
            if capability_ids is None:
                if declared:
                    warnings.append(
                        "capability registry core/capabilities/ not found — "
                        "declared capability ids were not verified"
                    )
            else:
                unknown = sorted({c for c in declared if c not in capability_ids})
                if unknown:
                    errors.append(
                        "unknown capability id(s) not in the capability registry: "
                        + ", ".join(unknown)
                    )

    return errors, warnings


# ---------------------------------------------------------------------------
# Tier: claude
# ---------------------------------------------------------------------------


def check_claude(path: Path, fm: dict[str, Any], body: str) -> list[str]:
    errors: list[str] = []

    # name <-> directory
    name = fm.get("name")
    skill_dir = path.parent.name
    if isinstance(name, str) and name and path.parts[-4:-2] != (".claude", "skills"):
        if name != skill_dir:
            errors.append(f"name '{name}' must match directory '{skill_dir}'")

    # Combined listing length.
    description = fm.get("description")
    when_to_use = fm.get("when_to_use")
    if "when_to_use" in fm:
        if not isinstance(when_to_use, str) or not when_to_use.strip():
            errors.append("when_to_use must be a non-empty string when present")
        elif isinstance(description, str):
            combined = len(description.strip()) + len(when_to_use.strip())
            if combined > LISTING_CAP:
                errors.append(
                    f"description + when_to_use length {combined} exceeds "
                    f"{LISTING_CAP}-char listing cap"
                )

    if "argument-hint" in fm and (
        not isinstance(fm["argument-hint"], str) or not fm["argument-hint"].strip()
    ):
        errors.append("argument-hint must be a non-empty string when present")

    if "arguments" in fm and not isinstance(fm["arguments"], list):
        errors.append("arguments must be a YAML list (use [] when none)")

    for flag in ("disable-model-invocation", "user-invocable", "background"):
        if flag in fm and not isinstance(fm[flag], bool):
            errors.append(f"{flag} must be a boolean (true or false)")

    for list_field in ("allowed-tools", "disallowed-tools", "paths"):
        if list_field in fm:
            value = fm[list_field]
            if not isinstance(value, list):
                errors.append(f"{list_field} must be a YAML list")
            elif list_field == "allowed-tools" and not value:
                errors.append("allowed-tools must list at least one tool")

    if "model" in fm and (not isinstance(fm["model"], str) or not fm["model"].strip()):
        errors.append("model must be a non-empty string when present")

    if "effort" in fm and fm["effort"] not in VOCAB["effort"]:
        errors.append(f"effort must be one of: {', '.join(VOCAB['effort'])}")

    if "shell" in fm and fm["shell"] not in VOCAB["shell"]:
        errors.append(f"shell must be one of: {', '.join(VOCAB['shell'])}")

    if "hooks" in fm and not isinstance(fm["hooks"], dict):
        errors.append("hooks must be a YAML mapping (use {} when none)")

    if "context" in fm or "agent" in fm:
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

    if fm.get("user-invocable") is False and fm.get("disable-model-invocation") is not True:
        errors.append("user-invocable: false requires disable-model-invocation: true")

    errors.extend(check_asset_references(path, body))
    return errors


def _sibling_skill_dirs() -> list[Path]:
    """All skill directories — a skill may cite another skill's reference doc."""
    global _SIBLING_SKILL_DIRS
    if _SIBLING_SKILL_DIRS is None:
        dirs = [p.parent for p in discover_skill_files(REPO_ROOT / "skills")]
        dirs += [p.parent for p in discover_skill_files(REPO_ROOT / ".claude" / "skills")]
        _SIBLING_SKILL_DIRS = dirs
    return _SIBLING_SKILL_DIRS


def check_asset_references(path: Path, body: str) -> list[str]:
    """Every skill-owned path named in the body must resolve to a real file."""
    skill_dir = path.parent
    candidates = set(SKILL_OWNED_REF.findall(body))
    anchored = set(ANCHORED_REF.findall(body))
    missing: list[str] = []

    for ref in sorted(anchored):
        if not (skill_dir / ref).exists():
            missing.append(f"$CLAUDE_SKILL_DIR/{ref}")

    for ref in sorted(candidates - anchored):
        if (skill_dir / ref).exists() or (REPO_ROOT / ref).exists():
            continue
        if any((other / ref).exists() for other in _sibling_skill_dirs()):
            continue
        missing.append(ref)

    if missing:
        return [f"referenced path(s) do not exist: {', '.join(missing)}"]
    return []


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------


def validate_file(
    path: Path,
    *,
    require_tamirs: bool,
    capability_ids: set[str] | None,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "file": str(path),
        "passed": False,
        "tiers": {tier: {"errors": [], "warnings": []} for tier in TIERS},
        "errors": [],
        "warnings": [],
    }

    fm, parse_error, body = parse_frontmatter(path)
    if parse_error:
        result["tiers"]["portable"]["errors"] = [parse_error]
        result["errors"] = [parse_error]
        return result
    assert fm is not None

    result["tiers"]["portable"]["errors"] = check_portable(path, fm)

    tamirs_errors, tamirs_warnings = check_tamirs(path, fm, capability_ids)
    if require_tamirs:
        tamirs_errors = tamirs_errors + tamirs_warnings
        tamirs_warnings = []
    result["tiers"]["tamirs"]["errors"] = tamirs_errors
    result["tiers"]["tamirs"]["warnings"] = tamirs_warnings

    result["tiers"]["claude"]["errors"] = check_claude(path, fm, body)

    result["errors"] = [
        f"[{tier}] {msg}" for tier in TIERS for msg in result["tiers"][tier]["errors"]
    ]
    result["warnings"] = [
        f"[{tier}] {msg}" for tier in TIERS for msg in result["tiers"][tier]["warnings"]
    ]
    result["passed"] = not result["errors"]
    return result


def discover_skill_files(root: Path) -> list[Path]:
    return sorted(root.rglob("SKILL.md")) if root.exists() else []


def resolve_targets(raw_paths: list[str]) -> list[Path]:
    if not raw_paths:
        return discover_skill_files(REPO_ROOT / "skills") + discover_skill_files(
            REPO_ROOT / ".claude" / "skills"
        )
    targets: list[Path] = []
    for raw in raw_paths:
        p = Path(raw)
        if not p.is_absolute():
            p = REPO_ROOT / p
        targets.extend(sorted(p.rglob("SKILL.md")) if p.is_dir() else [p])
    return targets


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate SKILL.md frontmatter in tiers")
    parser.add_argument(
        "paths",
        nargs="*",
        help="SKILL.md files or directories (default: skills/ and .claude/skills/)",
    )
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON")
    parser.add_argument(
        "--require-tamirs",
        action="store_true",
        help="Promote a missing metadata.tamirs block from warning to failure",
    )
    args = parser.parse_args()

    capability_ids = load_capability_ids()
    targets = resolve_targets(args.paths)

    if not targets:
        print("No SKILL.md files found", file=sys.stderr)
        return 1

    results: list[dict[str, Any]] = []
    failed = 0
    warned = 0
    tier_failures = {tier: 0 for tier in TIERS}

    for path in targets:
        result = validate_file(
            path,
            require_tamirs=args.require_tamirs,
            capability_ids=capability_ids,
        )
        rel = path.relative_to(REPO_ROOT) if path.is_relative_to(REPO_ROOT) else path
        result["file"] = str(rel)
        results.append(result)
        if not result["passed"]:
            failed += 1
        if result["warnings"]:
            warned += 1
        for tier in TIERS:
            if result["tiers"][tier]["errors"]:
                tier_failures[tier] += 1

    if args.json:
        print(
            json.dumps(
                {
                    "require_tamirs": args.require_tamirs,
                    "capability_registry": (
                        sorted(
                            str(p.relative_to(REPO_ROOT))
                            for p in CAPABILITY_REGISTRY_PATHS
                            if p.exists()
                        )
                        if capability_ids is not None
                        else None
                    ),
                    "roles_source": VOCAB.get("roles_source"),
                    "roles": VOCAB["roles"],
                    "role_vocabulary_drift": role_vocabulary_drift(),
                    "total": len(results),
                    "failed": failed,
                    "warned": warned,
                    "tier_failures": tier_failures,
                    "results": results,
                },
                indent=2,
            )
        )
        return 1 if failed else 0

    for result in results:
        if result["errors"]:
            print(f"  FAIL {result['file']}")
        elif result["warnings"]:
            print(f"  WARN {result['file']}")
        else:
            print(f"  OK   {result['file']}")
        for err in result["errors"]:
            print(f"       - {err}")
        for warn in result["warnings"]:
            print(f"       ~ {warn}")

    print(f"\nfiles={len(results)}  failed={failed}  with-warnings={warned}")
    print(
        "tier failures: "
        + "  ".join(f"{tier}={tier_failures[tier]}" for tier in TIERS)
    )
    if capability_ids is None:
        print("capability registry: core/capabilities/ absent — capability check skipped")
    else:
        print(f"capability registry: {len(capability_ids)} id(s) loaded")
    print(
        f"role vocabulary: {len(VOCAB['roles'])} role(s) from {VOCAB['roles_source']}"
    )
    for note in role_vocabulary_drift():
        print(f"  ~ drift: {note}")

    if failed:
        print(
            f"\n{failed} SKILL.md file(s) failed frontmatter validation",
            file=sys.stderr,
        )
        return 1
    print(f"All {len(results)} SKILL.md file(s) passed frontmatter validation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
