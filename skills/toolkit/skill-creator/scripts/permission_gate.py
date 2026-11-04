"""L1 permission gate for skill-creator scripts (ADR 004 D1, D2, D4).

`run_eval.py`, `improve_description.py` and `run_loop.py` start nested
`claude -p` sessions. A nested agent host is `process.spawn.agent_host`, R4:
no level allows it automatically (D2), because the child delivers model text
as a typed prompt and could answer a host prompt itself (D5). So before the
first spawn each entry point calls `require()`:

    allow  -> proceed
    ask    -> the action, the target and the number of sessions are shown on
              /dev/tty and only a typed "yes" proceeds
    deny, a resolver that is missing, exits non-zero or prints something that
    is not a JSON verdict -> exit 3 naming the setting that would allow it

No controlling terminal (an agent's shell, CI) is headless: the resolver is
asked with --headless, so ask becomes deny and the script stops with the
command for the user to run in their own terminal. No flag skips the gate.

The resolver is found from this file's location
(<plugin root>/skills/toolkit/skill-creator/scripts/), never from the
environment: a variable that can name it can name a fake one that says allow.

When the gate passes, the child runs with `CHILD_PERMISSION_FLAGS`: an
explicit `--permission-mode dontAsk`, so a user whose default mode is bypass
does not hand that to the child, and only tools the user pre-approved can run.
"""

from __future__ import annotations

import json
import shlex
import subprocess
import sys
from pathlib import Path

RESOLVER = Path(__file__).resolve().parents[4] / "scripts" / "resolve-permission.sh"
SKILL = "skill-creator"
ACTION = "process.spawn.agent_host"

# Never bypass, never auto: anything not pre-approved is refused without a prompt.
CHILD_PERMISSION_FLAGS = ["--permission-mode", "dontAsk"]


class _Tty:
    """The controlling terminal, as separate read and write handles.

    A tty is not seekable, so Python's "r+" mode on /dev/tty raises; opening it
    once per direction is the portable way to prompt on it.
    """

    def __init__(self):
        self.rd = open("/dev/tty", "r", encoding="utf-8")
        try:
            self.wr = open("/dev/tty", "w", encoding="utf-8")
        except OSError:
            self.rd.close()
            raise

    def ask(self, text: str) -> str:
        self.wr.write(text)
        self.wr.flush()
        return self.rd.readline().strip()

    def close(self) -> None:
        self.rd.close()
        self.wr.close()


def _tty():
    try:
        return _Tty()
    except OSError:
        return None


def _text(value) -> str:
    if isinstance(value, dict):
        parts = ([value["once"]] if value.get("once") else []) + list(value.get("durable") or [])
        if value.get("note"):
            parts.append(value["note"])
        return "; ".join(parts)
    return "" if value is None else str(value)


def resolve(action: str, target: str, headless: bool) -> dict | None:
    """The resolver's verdict object, or None when it cannot be trusted."""
    if not RESOLVER.is_file():
        return None
    cmd = ["bash", str(RESOLVER), "--action", action, "--skill", SKILL, "--target", target, "--json"]
    if headless:
        cmd.append("--headless")
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    try:
        verdict = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None
    if not isinstance(verdict, dict) or verdict.get("verdict") not in ("allow", "ask", "deny"):
        return None
    return verdict


def require(what: str, target: str = "claude -p", action: str = ACTION) -> None:
    """Return when the step may run; otherwise print why and exit 3."""
    tty = _tty()
    verdict = resolve(action, target, headless=tty is None)
    if verdict is not None and verdict["verdict"] == "allow":
        if tty:
            tty.close()
        return
    if verdict is not None and verdict["verdict"] == "ask" and tty is not None:
        answer = tty.ask(
            f"\nskill-creator wants to: {what}\n"
            f"  action {action} (R4) · target {target}\n"
            f"  {_text(verdict.get('reason'))}\n"
            'Type "yes" to allow this run (anything else refuses): '
        )
        tty.close()
        if answer == "yes":
            return
        print(f"blocked: {action} — not confirmed; nothing was started", file=sys.stderr)
        sys.exit(3)
    if tty:
        tty.close()
    if verdict is None:
        print(
            f"blocked: {action} — the permission resolver is missing or failed "
            "(fail closed, ADR 004 D4); nothing was started",
            file=sys.stderr,
        )
    else:
        print(
            f"blocked: {action} on {target} — {_text(verdict.get('reason'))} — "
            f"allow with: {_text(verdict.get('setting_that_would_allow'))}",
            file=sys.stderr,
        )
    if tty is None:
        skill_dir = Path(__file__).resolve().parents[1]
        module = Path(sys.argv[0]).stem if sys.argv and sys.argv[0] else "run_loop"
        print(
            "No terminal, so nothing can be confirmed here. Run it yourself in a terminal:\n  "
            + f"PYTHONPATH={shlex.quote(str(skill_dir))} {shlex.quote(sys.executable)} -m scripts.{module} "
            + " ".join(shlex.quote(a) for a in sys.argv[1:]),
            file=sys.stderr,
        )
    sys.exit(3)
