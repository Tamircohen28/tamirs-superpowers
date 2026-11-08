#!/usr/bin/env python3
"""PreToolUse guard: require confirmation before Docker commands that leave
durable state on this Mac (containers, images, volumes, networks) or prune it.

Replaces the autoMode `soft_deny` Docker rule, which went inert when
permissions.defaultMode was switched to "bypassPermissions" (2026-08-15).
Hooks run in every permission mode, so this survives bypass.

Rationale: a test Postgres container created by an agent ran unnoticed for a
month. Read-only inspection and `docker stop`/`rm` stay unprompted.

Blocks with `deny` rather than `ask`: deny sets a hard blockingError that applies
in every permission mode, and no plugin hook asks (ADR 006). The only answers
this file prints are `{}` (no decision) and deny: it never grants a tool call.

To run one command anyway, prefix it: PM_ALLOW_DOCKER=1 docker compose up -d
Or suppress for a whole session: export PM_ALLOW_DOCKER=1

Under Claude Code's bypassPermissions mode (5.6.7) everything that can be
stopped and removed passes; a prune, which cannot be undone, is still denied
(and the same PM_ALLOW_DOCKER=1 prefix approves it). The mode is read from the
host's payload, Claude only.

Delivered by the plugin and wired from the hook manifest as
`PreToolUse:Bash|Shell` -> python3 on this file, by its path inside the plugin.
The name used in the block message comes from DOCKER_GUARD_OWNER (default
"the user"), so nothing here is machine-specific.

Hook-safe: stdin is read with a bounded wait. No payload within
DOCKER_GUARD_STDIN_TIMEOUT seconds (default 2) means "pass and exit", so an
interactive or absent stdin can never hang the tool call.

WHY THE TOOL SET IS A CONSTANT AND NOT A LITERAL
  Until 2026-08-31 this guard read `tool_name != "Bash"` and dropped everything
  else, while the manifest wired it on `Bash|Shell`. The rule was therefore
  enforceable through Bash and unenforceable through Shell — the same
  bypass-by-sibling-tool shape closed in guard-sensitive-files.sh, one file
  over, and worse for sitting inside a matcher that *claims* to cover Shell.
  TOOLS below must stay in step with that matcher; the docker-guard suite
  asserts a matched pass/deny pair for every name in it.

WHY EVERY EXIT PRINTS JSON
  The pass paths used to be a bare `sys.exit(0)` — empty stdout. Claude Code
  reads that as no objection, but Cursor fail-closes on empty stdout, so the
  same verdict meant "run" on one host and "deny" on the other. Per the shared
  hook-output helper, a pass is `{}` on every host, Cursor included: an object
  with no decision in it. no_decision() prints it, so no path here is silent.
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

# Must match the PreToolUse matcher in the hook manifest ("Bash|Shell").
TOOLS = ("Bash", "Shell")

# Payload keys only Cursor sends; mirrors hook_detect_platform in
# the shared hook-output helper.
CURSOR_KEYS = ("conversation_id", "cursor_version", "workspace_roots")

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


def no_decision():
    """Print `{}` (no decision, on every host) and exit 0.

    Never a bare `sys.exit(0)` instead: empty stdout is a portable
    ambiguity, not a portable pass (see the module docstring).
    """
    print("{}")
    sys.exit(0)


def emit_deny(reason, data):
    """Print one PreToolUse deny in this host's shape and exit 0."""
    if isinstance(data, dict) and any(data.get(key) is not None for key in CURSOR_KEYS):
        print(json.dumps({"permission": "deny", "user_message": reason, "agent_message": reason}))
        sys.exit(0)
    # `deny` reads the blocking message from top-level `reason`; the nested field is
    # emitted too so the text survives either code path.
    print(json.dumps({
        "reason": reason,
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        },
    }))
    sys.exit(0)


def main():
    data = read_payload()
    if not isinstance(data, dict):
        no_decision()

    if data.get("tool_name") not in TOOLS:
        no_decision()
    if os.environ.get("PM_ALLOW_DOCKER") == "1":
        no_decision()

    command = (data.get("tool_input") or {}).get("command") or ""
    # Inline `PM_ALLOW_DOCKER=1 docker run ...` is the documented approval path.
    # It must be checked against the raw command: segments() strips leading env
    # assignments, and an inline assignment never reaches this process's environ.
    if OVERRIDE.search(command):
        no_decision()

    seg, why = verdict(command)
    if not seg:
        no_decision()

    # Claude Code's bypass mode (5.6.7): what can be stopped and removed runs; a prune, which cannot be
    # undone, is still denied. The mode comes from the host's payload, Claude only.
    claude = not any(data.get(key) is not None for key in CURSOR_KEYS) and "gemini_tool_name" not in data \
        and data.get("turn_id") is None and data.get("host") != "opencode"
    if claude and data.get("permission_mode") == "bypassPermissions":
        # Every segment, not the first risky one: `docker compose up -d; docker system prune -af` holds a prune.
        prune = next(((s, w) for s in segments(command) if not SAFE.match(s)
                      for p, w in RISKY if "not reversible" in w and p.match(s)), None)
        if prune is None:
            no_decision()
        seg, why = prune

    owner = os.environ.get("DOCKER_GUARD_OWNER") or "the user"
    reason = (
        f"BLOCKED by docker-guard: `{seg}` {why}.\n\n"
        f"Do not retry this command. Stop and ask {owner} whether it should run, stating: "
        "what will still be running on this machine afterwards, and the exact command "
        "to stop and remove it (e.g. `docker compose down -v`, `docker rm -f <name>`)."
        "\n\nIf they say yes, re-run with PM_ALLOW_DOCKER=1 prefixed on the command."
    )
    emit_deny(reason, data)


if __name__ == "__main__":
    main()
