#!/usr/bin/env python3
"""PreToolUse guard: require confirmation before Docker commands that leave
durable state on this Mac (containers, images, volumes, networks) or prune it.

Replaces the autoMode `soft_deny` Docker rule, which went inert when
permissions.defaultMode was switched to "bypassPermissions" (2026-08-15).
Hooks run in every permission mode, so this survives bypass.

Rationale: a test Postgres container created by an agent ran unnoticed for a
month. Read-only inspection and `docker stop`/`rm` stay unprompted.

Blocks with `deny` rather than `ask`: deny sets a hard blockingError that applies
in every permission mode, including bypassPermissions.

Approve one command by prefixing it: PM_ALLOW_DOCKER=1 docker compose up -d
Or suppress for a whole session: export PM_ALLOW_DOCKER=1

Delivered by the plugin and wired from hooks/hooks.json as
`PreToolUse:Bash` -> `python3 "${CLAUDE_PLUGIN_ROOT}/hooks/docker-guard.py"`.
The name used in the block message comes from DOCKER_GUARD_OWNER (default
"the user"), so nothing here is machine-specific.

Hook-safe: stdin is read with a bounded wait. No payload within
DOCKER_GUARD_STDIN_TIMEOUT seconds (default 2) means "allow and exit", so an
interactive or absent stdin can never hang the tool call.
"""
import json
import os
import re
import select
import sys

# Split a shell line into separately-judged segments.
SEPARATORS = re.compile(r"&&|\|\||;|\||\n")

# Explicit per-command approval, e.g. `PM_ALLOW_DOCKER=1 docker compose up -d`.
OVERRIDE = re.compile(r"\bPM_ALLOW_DOCKER=1\b")

# Leading noise to strip before matching the actual argv0.
LEADING = re.compile(r"^(?:\s*(?:sudo|command|time|env|nohup)\s+|\s*[A-Za-z_][A-Za-z0-9_]*=\S*\s+)+")

ENGINE = r"(?:docker|podman|docker-compose|podman-compose)"

# Read-only / cleanup — never prompt. Checked before the create patterns.
SAFE = re.compile(
    rf"^{ENGINE}\s+(?:"
    r"(?:container|image|volume|network|system|compose)\s+)?"
    r"(?:ps|ls|images|inspect|logs|stats|df|version|info|port|top|events|config|"
    r"stop|kill|rm|rmi|down|history|diff|wait|exec)\b",
    re.I,
)

# Commands that create durable state or destroy it wholesale.
RISKY = [
    (re.compile(rf"^{ENGINE}\s+(?:compose\s+)?up\b", re.I),
     "starts containers that keep running after this session ends"),
    (re.compile(rf"^{ENGINE}\s+(?:container\s+)?(?:run|create|start)\b", re.I),
     "creates or starts a container that outlives this session"),
    (re.compile(rf"^{ENGINE}\s+volume\s+create\b", re.I),
     "creates a named volume that persists until removed by hand"),
    (re.compile(rf"^{ENGINE}\s+network\s+create\b", re.I),
     "creates a network that persists until removed by hand"),
    (re.compile(rf"^{ENGINE}\s+(?:image\s+|buildx\s+)?(?:build|pull)\b", re.I),
     "writes a new image to local disk"),
    (re.compile(rf"^{ENGINE}\s+.*\bprune\b", re.I),
     "bulk-deletes Docker state and is not reversible"),
]

# Wrappers that have historically shelled out to docker (make e2e-db, make test:ui).
WRAPPER = re.compile(
    r"^(?:make|npm\s+run|yarn|pnpm\s+run|just|task)\s+\S*"
    r"(?:e2e|test:ui|integration|docker|compose|\bdb\b)",
    re.I,
)


def segments(command):
    for raw in SEPARATORS.split(command):
        seg = LEADING.sub("", raw.strip())
        if seg:
            yield seg


def verdict(command):
    for seg in segments(command):
        if SAFE.match(seg):
            continue
        for pattern, why in RISKY:
            if pattern.match(seg):
                return seg, why
        if WRAPPER.match(seg):
            return seg, "may wrap docker and start containers indirectly"
    return None, None


def read_payload():
    """Read the hook JSON from stdin without ever blocking indefinitely.

    select() on a terminal/empty stdin returns not-ready, so a hook run by hand
    or with no payload attached exits immediately instead of waiting on input.
    """
    try:
        timeout = float(os.environ.get("DOCKER_GUARD_STDIN_TIMEOUT", "2"))
    except ValueError:
        timeout = 2.0
    try:
        if sys.stdin is None or sys.stdin.closed:
            return None
        if sys.stdin.isatty():
            return None
        ready, _, _ = select.select([sys.stdin], [], [], timeout)
        if not ready:
            return None
        return json.loads(sys.stdin.read() or "")
    except Exception:
        return None


def main():
    data = read_payload()
    if not isinstance(data, dict):
        sys.exit(0)

    if data.get("tool_name") != "Bash":
        sys.exit(0)
    if os.environ.get("PM_ALLOW_DOCKER") == "1":
        sys.exit(0)

    command = (data.get("tool_input") or {}).get("command") or ""
    # Inline `PM_ALLOW_DOCKER=1 docker run ...` is the documented approval path.
    # It must be checked against the raw command: segments() strips leading env
    # assignments, and an inline assignment never reaches this process's environ.
    if OVERRIDE.search(command):
        sys.exit(0)

    seg, why = verdict(command)
    if not seg:
        sys.exit(0)

    owner = os.environ.get("DOCKER_GUARD_OWNER") or "the user"
    reason = (
        f"BLOCKED by docker-guard: `{seg}` {why}.\n\n"
        f"Do not retry this command. Stop and ask {owner} to approve it, stating: "
        "what will still be running on this machine afterwards, and the exact command "
        "to stop and remove it (e.g. `docker compose down -v`, `docker rm -f <name>`)."
        "\n\nIf approved, re-run with PM_ALLOW_DOCKER=1 prefixed on the command."
    )
    # `deny` reads the blocking message from top-level `reason`; the nested field is
    # emitted too so the text survives either code path.
    print(json.dumps({
        "reason": reason,
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


if __name__ == "__main__":
    main()
