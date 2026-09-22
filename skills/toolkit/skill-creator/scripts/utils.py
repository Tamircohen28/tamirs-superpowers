"""Shared utilities for skill-creator scripts."""

from pathlib import Path

try:  # pyyaml is declared in scripts/requirements-validate.txt
    import yaml
except ImportError:  # pragma: no cover - degrade to the line reader below
    yaml = None



def parse_skill_md(skill_path: Path) -> tuple[str, str, str]:
    """Parse a SKILL.md file, returning (name, description, full_content)."""
    content = (skill_path / "SKILL.md").read_text()
    lines = content.split("\n")

    if lines[0].strip() != "---":
        raise ValueError("SKILL.md missing frontmatter (no opening ---)")

    end_idx = None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            end_idx = i
            break

    if end_idx is None:
        raise ValueError("SKILL.md missing frontmatter (no closing ---)")

    # Prefer a real YAML parse of the frontmatter.
    #
    # The hand-rolled reader below gathers continuation lines only for BLOCK
    # scalars (>, |, >-, |-). A multi-line QUOTED scalar is equally valid YAML,
    # and several skills here use one — for those the reader stops at the first
    # physical line and silently truncates the description.
    #
    # That is not cosmetic. run_eval.py and run_loop.py score triggering
    # against this string and then rewrite it, so a truncated read benchmarks
    # and optimises a description the model never sees in full. Measured on
    # this repo before the fix: targeted-debug returned 92 of 568 characters,
    # diagnose-refusal 99 of 590, changelog-review 93 of 517, docs-review 96 of
    # 297 — roughly 17% of the text, with every trigger phrase and exclusion
    # clause beyond line one invisible.
    #
    # The line reader is kept as a fallback so these scripts still run where
    # pyyaml is not installed, or on a frontmatter block yaml refuses.
    frontmatter = "\n".join(lines[1:end_idx])
    if yaml is not None:
        try:
            data = yaml.safe_load(frontmatter)
        except yaml.YAMLError:
            data = None
        if isinstance(data, dict):
            return (
                str(data.get("name") or ""),
                str(data.get("description") or ""),
                content,
            )

    name = ""
    description = ""
    frontmatter_lines = lines[1:end_idx]
    i = 0
    while i < len(frontmatter_lines):
        line = frontmatter_lines[i]
        if line.startswith("name:"):
            name = line[len("name:"):].strip().strip('"').strip("'")
        elif line.startswith("description:"):
            value = line[len("description:"):].strip()
            # Handle YAML multiline indicators (>, |, >-, |-)
            if value in (">", "|", ">-", "|-"):
                continuation_lines: list[str] = []
                i += 1
                while i < len(frontmatter_lines) and (frontmatter_lines[i].startswith("  ") or frontmatter_lines[i].startswith("\t")):
                    continuation_lines.append(frontmatter_lines[i].strip())
                    i += 1
                description = " ".join(continuation_lines)
                continue
            else:
                description = value.strip('"').strip("'")
        i += 1

    return name, description, content
