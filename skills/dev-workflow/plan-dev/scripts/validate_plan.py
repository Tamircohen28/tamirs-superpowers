#!/usr/bin/env python3
"""
validate_plan.py — Static validator for plan-dev phase plans.

Usage:
    python scripts/validate_plan.py <plan.md>

Reads a plan markdown file and checks:
  - Each phase has a title, issue title, type, area, depends-on
  - No phase has more than 10 tasks (hard rule)
  - Dependency references are valid (e.g. "Phase 2" exists if referenced)
  - Parallel-safe field is set

Exit code 0 = valid, 1 = validation errors found.
"""

import sys
import re
from pathlib import Path


def validate_plan(text: str) -> list[str]:
    errors = []
    phases = re.findall(r"## Phase (\d+):(.*?)(?=\n## Phase \d+:|\Z)", text, re.DOTALL)

    if not phases:
        errors.append("No phases found. Expected at least one '## Phase N: <title>' section.")
        return errors

    phase_numbers = {int(n) for n, _ in phases}

    for num_str, body in phases:
        num = int(num_str)
        prefix = f"Phase {num}"

        # Required fields
        for field in ["**Issue title**", "**Type**", "**Area**", "**Depends on**", "**Parallel-safe**"]:
            if field not in body:
                errors.append(f"{prefix}: missing field {field}")

        # Task count
        tasks = re.findall(r"- \[ \]", body)
        if len(tasks) > 10:
            errors.append(
                f"{prefix}: {len(tasks)} tasks exceeds the 10-task limit — split this phase."
            )
        if len(tasks) == 0:
            errors.append(f"{prefix}: no tasks found (expected '- [ ] ...' items under ### Tasks)")

        # Verification section
        if "### Verification" not in body:
            errors.append(f"{prefix}: missing '### Verification' section")

        # Dependency reference validation
        depends_match = re.search(r"\*\*Depends on\*\*:\s*(.+)", body)
        if depends_match:
            dep_text = depends_match.group(1).strip()
            if dep_text.lower() not in ("none", "–", "-", "n/a"):
                ref_nums = re.findall(r"Phase (\d+)", dep_text)
                for ref in ref_nums:
                    if int(ref) not in phase_numbers:
                        errors.append(
                            f"{prefix}: depends on Phase {ref} which does not exist in the plan"
                        )

    return errors


def main():
    if len(sys.argv) < 2:
        print("Usage: python scripts/validate_plan.py <plan.md>")
        sys.exit(1)

    plan_path = Path(sys.argv[1])
    if not plan_path.exists():
        print(f"Error: file not found: {plan_path}")
        sys.exit(1)

    text = plan_path.read_text()
    errors = validate_plan(text)

    if errors:
        print(f"Plan validation FAILED ({len(errors)} error(s)):\n")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)
    else:
        phase_count = len(re.findall(r"## Phase \d+:", text))
        print(f"Plan valid — {phase_count} phase(s), all checks passed.")
        sys.exit(0)


if __name__ == "__main__":
    main()
