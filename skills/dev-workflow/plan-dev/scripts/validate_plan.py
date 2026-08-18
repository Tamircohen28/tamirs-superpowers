#!/usr/bin/env python3
"""
validate_plan.py — Static validator for plan-dev output.

Two input shapes, auto-detected:

  1. An objective directory (the primary output since the DAG refactor):

         python3 scripts/validate_plan.py .dev-files/objectives/auth-system

     Checks objective.json + tasks/*.json against the shapes in
     core/workflow/{objective,task}-schema.json, and — the part a JSON Schema
     cannot express — the graph itself:
       - every depends_on target exists;
       - the graph is acyclic;
       - tasks the plan calls parallel really are independent (no shared
         write scope, no dependency path between them);
       - every task declares role, scope, validation_tier;
       - objective.tasks matches the task files on disk.

  2. A markdown phase plan (the pre-DAG format, still accepted so an older
     plan.md keeps validating):

         python3 scripts/validate_plan.py plan.md

Exit code 0 = valid, 1 = validation errors found. Reads no stdin.
"""

from __future__ import annotations

import fnmatch
import json
import re
import sys
from pathlib import Path

ROLES = {
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
}

TIERS = {"edit", "worker", "integration", "delivery"}
TASK_ID = re.compile(r"^task-\d{3}$")
OBJECTIVE_ID = re.compile(r"^[a-z0-9][a-z0-9-]*$")


# ---------------------------------------------------------------------------
# Objective + task DAG
# ---------------------------------------------------------------------------


def _scopes_overlap(a: list[str], b: list[str]) -> bool:
    """Conservative glob overlap test.

    Two scopes overlap when either pattern matches the other's literal prefix.
    It is deliberately eager: a false 'these overlap' costs a plan revision,
    a false 'these are independent' costs a merge conflict between workers.
    """
    for pa in a:
        for pb in b:
            if pa == pb:
                return True
            la, lb = pa.split("*", 1)[0], pb.split("*", 1)[0]
            if la and lb and (la.startswith(lb) or lb.startswith(la)):
                return True
            if fnmatch.fnmatch(lb.rstrip("/"), pa) or fnmatch.fnmatch(la.rstrip("/"), pb):
                return True
    return False


def _reachable(graph: dict[str, list[str]], start: str) -> set[str]:
    seen: set[str] = set()
    stack = list(graph.get(start, []))
    while stack:
        node = stack.pop()
        if node in seen:
            continue
        seen.add(node)
        stack.extend(graph.get(node, []))
    return seen


def validate_objective(obj_dir: Path) -> list[str]:
    errors: list[str] = []

    obj_file = obj_dir / "objective.json"
    if not obj_file.is_file():
        return [f"{obj_dir}: no objective.json"]

    try:
        objective = json.loads(obj_file.read_text())
    except json.JSONDecodeError as exc:
        return [f"objective.json: not valid JSON — {exc}"]

    for field in ("id", "title", "base_branch", "integration_branch", "status", "tasks"):
        if field not in objective:
            errors.append(f"objective.json: missing required field '{field}'")

    obj_id = objective.get("id", "")
    if obj_id and not OBJECTIVE_ID.match(obj_id):
        errors.append(f"objective.json: id '{obj_id}' is not a lowercase slug")

    delivery = objective.get("delivery") or {}
    strategy = delivery.get("strategy", "single-pr")
    if strategy != "single-pr" and not delivery.get("exception_reason"):
        errors.append(
            f"objective.json: delivery.strategy '{strategy}' requires an "
            "exception_reason naming an exception from core/policies/delivery.md"
        )

    task_files = sorted((obj_dir / "tasks").glob("task-*.json")) if (obj_dir / "tasks").is_dir() else []
    if not task_files:
        errors.append(f"{obj_dir}/tasks/: no task-NNN.json files found")
        return errors

    tasks: dict[str, dict] = {}
    for tf in task_files:
        try:
            task = json.loads(tf.read_text())
        except json.JSONDecodeError as exc:
            errors.append(f"{tf.name}: not valid JSON — {exc}")
            continue

        tid = task.get("id", "")
        if not TASK_ID.match(tid):
            errors.append(f"{tf.name}: id '{tid}' must match task-NNN")
            continue
        if tid != tf.stem:
            errors.append(f"{tf.name}: id '{tid}' does not match the filename")
        tasks[tid] = task

        for field in ("role", "depends_on", "scope", "validation_tier", "status"):
            if field not in task:
                errors.append(f"{tid}: missing required field '{field}'")

        role = task.get("role")
        if role is not None and role not in ROLES:
            errors.append(f"{tid}: role '{role}' is not a canonical role (core/roles/)")

        tier = task.get("validation_tier")
        if tier is not None and tier not in TIERS:
            errors.append(f"{tid}: validation_tier '{tier}' must be one of {sorted(TIERS)}")

        scope = task.get("scope")
        if not isinstance(scope, list) or not scope:
            errors.append(f"{tid}: scope must be a non-empty list of glob paths")

    declared = objective.get("tasks") or []
    if isinstance(declared, list):
        missing = [t for t in declared if t not in tasks]
        extra = [t for t in tasks if t not in declared]
        for t in missing:
            errors.append(f"objective.json lists {t} but tasks/{t}.json does not exist")
        for t in extra:
            errors.append(f"tasks/{t}.json exists but objective.json does not list it")

    # Graph checks
    graph = {tid: list(t.get("depends_on") or []) for tid, t in tasks.items()}
    for tid, deps in graph.items():
        for dep in deps:
            if dep not in tasks:
                errors.append(f"{tid}: depends_on '{dep}' which is not a task in this objective")
            if dep == tid:
                errors.append(f"{tid}: depends on itself")

    # Cycle detection (iterative DFS with colouring)
    color: dict[str, int] = {}

    def visit(node: str) -> None:
        color[node] = 1
        for dep in graph.get(node, []):
            if dep not in tasks:
                continue
            if color.get(dep) == 1:
                errors.append(f"dependency cycle detected involving {node} -> {dep}")
            elif color.get(dep, 0) == 0:
                visit(dep)
        color[node] = 2

    for tid in tasks:
        if color.get(tid, 0) == 0:
            visit(tid)

    # Parallel-safety: any two tasks with no dependency path between them must
    # not share write scope, or two workers will fight over the same files.
    ids = sorted(tasks)
    for i, a in enumerate(ids):
        for b in ids[i + 1 :]:
            if b in _reachable(graph, a) or a in _reachable(graph, b):
                continue
            sa, sb = tasks[a].get("scope") or [], tasks[b].get("scope") or []
            if _scopes_overlap(sa, sb):
                errors.append(
                    f"{a} and {b} can run in parallel but share write scope "
                    f"({sa} vs {sb}) — add a dependency or narrow the scopes"
                )

    return errors


# ---------------------------------------------------------------------------
# Legacy markdown phase plan
# ---------------------------------------------------------------------------


def validate_markdown_plan(text: str) -> list[str]:
    errors: list[str] = []
    phases = re.findall(r"## Phase (\d+):(.*?)(?=\n## Phase \d+:|\Z)", text, re.DOTALL)

    if not phases:
        errors.append("No phases found. Expected at least one '## Phase N: <title>' section.")
        return errors

    phase_numbers = {int(n) for n, _ in phases}

    for num_str, body in phases:
        prefix = f"Phase {int(num_str)}"

        for field in ["**Issue title**", "**Type**", "**Area**", "**Depends on**", "**Parallel-safe**"]:
            if field not in body:
                errors.append(f"{prefix}: missing field {field}")

        tasks = re.findall(r"- \[ \]", body)
        if len(tasks) > 10:
            errors.append(f"{prefix}: {len(tasks)} tasks exceeds the 10-task limit — split this phase.")
        if len(tasks) == 0:
            errors.append(f"{prefix}: no tasks found (expected '- [ ] ...' items under ### Tasks)")

        if "### Verification" not in body:
            errors.append(f"{prefix}: missing '### Verification' section")

        depends_match = re.search(r"\*\*Depends on\*\*:\s*(.+)", body)
        if depends_match:
            dep_text = depends_match.group(1).strip()
            if dep_text.lower() not in ("none", "–", "-", "n/a"):
                for ref in re.findall(r"Phase (\d+)", dep_text):
                    if int(ref) not in phase_numbers:
                        errors.append(f"{prefix}: depends on Phase {ref} which does not exist in the plan")

    return errors


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/validate_plan.py <objective-dir | plan.md>")
        sys.exit(1)

    target = Path(sys.argv[1])
    if not target.exists():
        print(f"Error: not found: {target}")
        sys.exit(1)

    if target.is_dir():
        errors = validate_objective(target)
        label = f"objective {target}"
    else:
        errors = validate_markdown_plan(target.read_text())
        label = f"plan {target}"

    if errors:
        print(f"Validation FAILED for {label} ({len(errors)} error(s)):\n")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)

    print(f"Valid — {label} passed all checks.")
    sys.exit(0)


if __name__ == "__main__":
    main()
