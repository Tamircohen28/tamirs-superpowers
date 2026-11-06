#!/usr/bin/env python3
"""PreToolUse guard: require confirmation before Docker commands that leave
durable state on this Mac (containers, images, volumes, networks) or prune it.

Replaces the autoMode `soft_deny` Docker rule, which went inert when
permissions.defaultMode was switched to "bypassPermissions" (2026-08-15).
Hooks run in every permission mode, so this survives bypass.

Rationale: a test Postgres container created by an agent ran unnoticed for a
month. Read-only inspection and `docker stop`/`rm` stay unprompted.

WHO APPROVES (ADR 004 D1, D5, D8)
  Every command this guard flags is the catalog action `docker.state`
  (core/permissions/actions.json: R3, never automatic), and the decision is
  scripts/resolve-permission.sh's, found next to this file inside the plugin
  (never through an environment variable). The guard answers:
    the resolver's pass verdict
           -> `{}`, no decision: the host's own permission rules apply;
    ask    -> on Claude Code, a hook `ask`: the host's permission dialog names
              the command, and only the user's Yes runs it (headless, the host
              turns it into a deny). Every other host cannot carry an ask
              (Codex fails it open, Gemini hangs, Cursor drops it, OpenCode
              --auto lets it through), so there it is a deny;
    deny   -> deny, naming the setting that would let it run;
    a resolver that is missing, exits non-zero, times out or prints no verdict
           -> deny (fail closed, D4).
  The only answers this file can print are `{}`, ask and deny: it never grants
  a tool call. There is no confirmation token. The old `PM_ALLOW_DOCKER=1`
  command prefix was text the agent could type itself, which made the deny a
  suggestion (audit non-skill-surfaces D5); it, and the same variable exported
  into the hook's environment, now unlock nothing.

THE PASS VERDICT IS READ FROM THE RESOLVER'S CONTRACT
  The resolver answers in the vocabulary of core/schemas/permissions.schema.json:
  $defs/verdict lists every verdict, and $defs/verdict_r4 the two an R4 action
  may take, ask and deny. The pass verdict is the one member of the first that
  is not in the second. PASS_VERDICT is read from there once, on the path that
  calls the resolver, so this file names only the two verdicts it acts on. A
  schema that cannot be read, or that no longer has exactly that shape, leaves
  PASS_VERDICT unknown, and every resolver answer then reads as "no verdict":
  deny. The resolver itself loads the same file on every call, so this adds no
  dependency a working resolver does not already have.

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
import subprocess
import sys

# Split a shell line into separately-judged segments.
SEPARATORS = re.compile(r"&&|\|\||;|\||\n")

# Leading noise to strip before matching the actual argv0.
LEADING = re.compile(r"^(?:\s*(?:sudo|command|time|env|nohup)\s+|\s*[A-Za-z_][A-Za-z0-9_]*=\S*\s+)+")

ENGINE = r"(?:docker|podman|docker-compose|podman-compose)"

# Must match the PreToolUse matcher in the hook manifest ("Bash|Shell").
TOOLS = ("Bash", "Shell")

# Payload keys only Cursor sends; mirrors hook_detect_platform in
# the shared hook-output helper.
CURSOR_KEYS = ("conversation_id", "cursor_version", "workspace_roots")

# The catalog action every flagged command is (core/permissions/actions.json).
ACTION = "docker.state"

# The resolver, by this file's own location: <plugin>/hooks/ -> <plugin>/scripts/.
RESOLVER = os.path.join(
    os.path.dirname(os.path.dirname(os.path.realpath(__file__))),
    "scripts", "resolve-permission.sh",
)

# The schema whose verdict vocabulary the resolver answers in.
SCHEMA = os.path.join(
    os.path.dirname(os.path.dirname(os.path.realpath(__file__))),
    "core", "schemas", "permissions.schema.json",
)

# The two verdicts this guard acts on. The third, the resolver's pass, is not
# spelled here: verdict_vocabulary() reads it from SCHEMA (module docstring).
ASK, DENY = "ask", "deny"

# Well under the hook's 5 s timeout in the manifest; a resolver that has not
# answered by then is a deny.
RESOLVER_TIMEOUT = 3.5

# Hosts that carry a hook `ask` to a human (ADR 004 D8). docker.state is R3 and
# never automatic, so OpenCode's R2-only ask does not qualify.
ASK_HOSTS = ("claude",)

# Environment that names a deny-only host. A repository can set these, so they
# only ever make the answer stricter (the permission guard's rule F7).
DENY_ONLY_ENV = ("CODEX_HOME", "GEMINI_SESSION_ID", "GEMINI_PROJECT_DIR")

# The C0 controls and DEL, written with chr() so the class spells no escape.
CONTROL = re.compile("[" + chr(0) + "-" + chr(0x1f) + chr(0x7f) + "]")

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


def verdict_vocabulary():
    """(every verdict, PASS_VERDICT) from the resolver's schema.

    PASS_VERDICT is the one $defs/verdict member outside $defs/verdict_r4.
    When the file cannot be read or has another shape, the vocabulary is the
    two verdicts this guard acts on and PASS_VERDICT is None, so no resolver
    answer can pass (fail closed).
    """
    try:
        with open(SCHEMA, encoding="utf-8") as fh:
            defs = json.load(fh)["$defs"]
        every = tuple(defs["verdict"]["enum"])
        stricter = set(defs["verdict_r4"]["enum"])
    except (OSError, ValueError, KeyError, TypeError):
        return (ASK, DENY), None
    rest = [v for v in every if v not in stricter]
    if stricter != {ASK, DENY} or len(rest) != 1 or not isinstance(rest[0], str):
        return (ASK, DENY), None
    return every, rest[0]


def payload_host(data):
    """The host, read from the payload's shape the way permission-guard.sh does."""
    if any(data.get(key) is not None for key in CURSOR_KEYS):
        return "cursor"
    if "gemini_tool_name" in data:
        return "gemini"
    if data.get("turn_id") is not None:
        return "codex"
    if data.get("host") == "opencode":
        return "opencode"
    return "claude"


def resolve(data, host, verdicts):
    """The resolver's answer for docker.state as a dict with a verdict.

    Anything short of a parsed verdict from `verdicts` is a deny: no resolver,
    a non-zero exit, a timeout, no JSON, no verdict (ADR 004 D4, SR S-12).
    """
    def failed(why):
        return {"verdict": DENY, "reason": "the permission resolver " + why
                + ", so the call is denied (fail closed, ADR 004 D4)"}

    if not os.path.isfile(RESOLVER):
        return failed("(scripts/resolve-permission.sh) is missing")
    argv = ["bash", RESOLVER, ACTION, "--host", host, "--json"]
    cwd = data.get("cwd")
    if isinstance(cwd, str) and cwd and os.path.isdir(cwd):
        argv += ["--repo", cwd]
    sid = data.get("session_id")
    agent = str(data.get("agent_id") or "main")[:128]
    if isinstance(sid, str) and 0 < len(sid) <= 256 and not CONTROL.search(sid + agent):
        argv += ["--session", sid, "--agent", agent]
    try:
        # Its own process group, so a deadline kills everything it started.
        proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        return failed("could not start")
    try:
        out, _ = proc.communicate(timeout=RESOLVER_TIMEOUT)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, 9)
        except OSError:
            pass
        proc.wait()
        return failed("did not answer in time")
    if proc.returncode != 0:
        return failed("exited %d" % proc.returncode)
    try:
        answer = json.loads(out.decode("utf-8", "replace"))
    except ValueError:
        return failed("printed no JSON")
    if not isinstance(answer, dict) or answer.get("verdict") not in verdicts:
        return failed("gave no verdict")
    return answer


def setting_text(answer):
    """The resolver's setting_that_would_allow, as one sentence (or "")."""
    s = answer.get("setting_that_would_allow")
    if not isinstance(s, dict):
        return ""
    parts = []
    if s.get("once"):
        parts.append("once: %s" % s["once"])
    durable = [str(x) for x in (s.get("durable") or []) if x]
    if durable:
        parts.append("durable: %s" % "; ".join(durable))
    if s.get("note"):
        parts.append(str(s["note"]))
    return " ".join(parts)


def emit(decision, reason, data):
    """Print one PreToolUse decision (ask or deny) in this host's shape and exit 0."""
    if isinstance(data, dict) and any(data.get(key) is not None for key in CURSOR_KEYS):
        print(json.dumps({"permission": decision, "user_message": reason, "agent_message": reason}))
        sys.exit(0)
    out = {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
    }}
    if decision == DENY:
        # `deny` reads the blocking message from top-level `reason`; the nested field
        # is emitted too so the text survives either code path.
        out["reason"] = reason
    print(json.dumps(out))
    sys.exit(0)


def main():
    data = read_payload()
    if not isinstance(data, dict):
        no_decision()

    if data.get("tool_name") not in TOOLS:
        no_decision()

    # No approval token, inline or exported: segments() strips a leading
    # `PM_ALLOW_DOCKER=1` like any other assignment, and the command is judged.
    command = (data.get("tool_input") or {}).get("command") or ""
    seg, why = verdict(command)
    if not seg:
        no_decision()

    host = payload_host(data)
    # Claude Code's bypass mode (5.6.7): what can be stopped and removed runs; a prune, which cannot be
    # undone, is still put to the user as an ask. The mode comes from the host's payload, Claude only.
    if host == "claude" and data.get("permission_mode") == "bypassPermissions":
        if "not reversible" not in why:
            no_decision()
        emit(ASK, f"docker-guard ({ACTION}, R3): `{seg}` {why}. Bypass mode still asks before this one.", data)
    verdicts, pass_verdict = verdict_vocabulary()
    answer = resolve(data, host, verdicts)
    decision = answer["verdict"]
    # PASS_VERDICT: the resolver's automatic answer (None when unknown, which
    # resolve() has already turned into a deny). It earns `{}`, never a grant.
    if pass_verdict is not None and decision == pass_verdict:
        no_decision()

    owner = os.environ.get("DOCKER_GUARD_OWNER") or "the user"
    undo = "`docker compose down -v` or `docker rm -f <name>`"
    carried = host in ASK_HOSTS and not any(os.environ.get(k) for k in DENY_ONLY_ENV)
    if decision == ASK and carried:
        emit(ASK, (
            f"docker-guard ({ACTION}, R3): `{seg}` {why}. Confirm only if you want "
            f"this to run on this machine; afterwards stop and remove what it leaves "
            f"behind (e.g. {undo})."
        ), data)

    detail = str(answer.get("reason") or "")
    if decision == ASK:
        detail = (f"{detail}; this host cannot show a permission prompt for it, "
                  "so it is denied here").lstrip("; ")
    setting = setting_text(answer)
    reason = (
        f"BLOCKED by docker-guard: `{seg}` {why} ({ACTION}: {detail}).\n\n"
        f"Do not retry this command or reshape it to get past this guard. Stop and ask "
        f"{owner} to run it themselves, stating what will still be running on this "
        f"machine afterwards and the exact command to stop and remove it (e.g. {undo})."
        + (f"\n\nSetting that would let it run: {setting}" if setting else "")
    )
    emit(DENY, reason, data)


if __name__ == "__main__":
    main()
