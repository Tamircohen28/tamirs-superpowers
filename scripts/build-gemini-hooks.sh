#!/usr/bin/env bash
# build-gemini-hooks.sh — generate the Gemini CLI hooks file and deny policies.
#
# Usage:
#   bash scripts/build-gemini-hooks.sh [repo-root] [--check] [--verbose]
#   bash scripts/build-gemini-hooks.sh -h | --help
#
# Generates:
#   platforms/gemini/hooks.json                      — from hooks/hooks.json
#   platforms/gemini/policies/tamirs-superpowers.toml — `rules` of platforms/gemini/policies.source.json
#   platforms/gemini/policies/tamirs-superpowers-permissions.toml — its `permission_rules`
#
# --check regenerates into a temp dir and diffs, so CI can fail on drift without
# writing to the working tree.
#
# WHY THIS EXISTS
#   Gemini CLI runs an extension's hooks from `hooks/hooks.json` at the extension
#   root — the same path as the Claude Code file — and reads only its `hooks`
#   object (measured on 0.64.0: loadExtensionHooks ignores every other top-level
#   key, so `modules` is harmless but `${CLAUDE_PLUGIN_ROOT}` is not: Gemini never
#   exports it, the shell expands it to nothing, and every command would run
#   `/hooks/x.sh`). Gemini's event names and tool names also differ, its timeout
#   is in milliseconds, and its exit-code table treats every non-zero exit except
#   1 as a deny. So the Gemini distribution gets a GENERATED hooks file: the same
#   hooks, routed through hooks/gemini-wrap.sh, which translates the payload in
#   and the answer out so each canonical hook stays byte-identical. In the
#   repository the file lives at platforms/gemini/hooks.json; build-dist.sh's
#   gemini target places it at hooks/hooks.json in the shipped tree.
#
# THE MAPPING (hooks)
#   PreToolUse        -> BeforeTool, matcher rewritten onto Gemini tool names:
#                        Bash|Shell -> run_shell_command; Edit|MultiEdit|
#                        NotebookEdit|StrReplace -> replace; Write -> write_file.
#                        Anchored (`^(…)$`): Gemini's matcher is an UNANCHORED
#                        regex (hookPlanner: new RegExp(matcher).test(toolName)),
#                        so a bare `replace|edit` would also fire on any MCP tool
#                        whose name merely contains those letters, and a guard
#                        fired on a tool with no file_path judges the cwd.
#   PostToolUse       -> AfterTool, same matcher rewrite
#   UserPromptSubmit  -> BeforeAgent
#   Stop              -> AfterAgent (Claude's `*` matcher dropped: a lifecycle
#                        matcher on Gemini is an exact-string compare)
#   PreCompact        -> PreCompress
#   SessionStart, SessionEnd, Notification -> same name
#   dropped           WorktreeCreate, WorktreeRemove, DirectoryAdded, StopFailure,
#                     SubagentStop — Gemini has no such event (its migrate table
#                     folds SubAgentStop into AfterAgent; this repo's
#                     subagent-handoff-check reads a subagent transcript that
#                     AfterAgent never has, so it is dropped, not misrouted).
#   per hook          command  `bash "${extensionPath}/hooks/gemini-wrap.sh" "${extensionPath}/<script>"`
#                     timeout  seconds -> milliseconds (Gemini's unit; `gemini
#                              hooks migrate` copies the number unchanged, which
#                              would make a 10-second guard a 10-millisecond one)
#                     name     the script stem, plus -write/-shell on a tool event
#                              (a hook wired under two matchers needs two names
#                              for `/hooks enable|disable <name>`)
#                     description  from Claude's statusMessage
#                     onFailure    dropped — Gemini has no such field. The guards
#                              are therefore fail-open on Gemini the same way
#                              they are on Codex; the install doc says so.
#   skipped matcher   mcp__plugin_tamirs-superpowers_github__.* (permission-guard.sh
#                     on the bundled GitHub MCP server's tools). Gemini names an MCP
#                     tool mcp_<server>_<tool> (source-cited, gemini-cli 0.60.0
#                     bundle, mcp-tool.ts generateValidName/formatMcpToolName), and
#                     gemini-wrap.sh passes that name through untranslated, so the
#                     guard would see no GitHub MCP tool and allow every call: a
#                     wired hook that can only say yes. The group is dropped, never
#                     turned into a match-all; the GitHub MCP layer on Gemini is the
#                     static policy (permission_rules on mcpName = "github") plus the
#                     server flags (ADR 004 D8). A group with a skipped token and a
#                     mapped one keeps the mapped one.
#   Any other Claude event, matcher token or per-hook key is an error (exit 2),
#   so a new canonical entry cannot ship to Gemini half-translated.
#
# THE MAPPING (policies)
#   `rules` (the guard mirrors) -> tamirs-superpowers.toml, every rule
#   `decision = "deny"` at the shared `priority`. `permission_rules` (ADR 004
#   D8, the static half of the Gemini permission layer) ->
#   tamirs-superpowers-permissions.toml, each rule `deny` (at `priority`) or
#   `ask_user` (at `ask_user_priority`, which must be lower, so every deny
#   outranks every ask). Never `allow` (loadExtensionPolicies drops it, and a
#   rule that could widen is a bug here), never `modes` (a mode-scoped rule
#   does not hold in every mode, and one naming yolo is dropped), and
#   `ask_user` only for an R4 action: a static ask is level-independent, which
#   only "never automatic at any level" is. `%NAME%` in a regex expands from
#   `regex_macros`. toolName, mcpName, commandRegex and argsPattern are written
#   as TOML literal strings so no regex needs escaping twice. Any other key,
#   decision or a regex that does not compile is an error.
#
# Exit 0 on success; 1 if --check finds drift; 2 on a malformed source or a
# command whose script is missing.
set -euo pipefail

usage() { sed -n '2,14p' "$0" | sed 's/^#[[:space:]]\{0,1\}//'; exit "${1:-0}"; }

ROOT="."
CHECK=false
VERBOSE=false
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage 0 ;;
    --check) CHECK=true ;;
    -v|--verbose) VERBOSE=true ;;
    -*) printf 'Unknown flag: %s\n' "$arg" >&2; usage 1 ;;
    *) ROOT="$arg" ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"

command -v python3 >/dev/null 2>&1 || { printf 'error: python3 is required (it renders the JSON and TOML)\n' >&2; exit 2; }
[[ -f "$ROOT/hooks/hooks.json" ]] || { printf 'error: no hooks/hooks.json under %s\n' "$ROOT" >&2; exit 2; }
[[ -f "$ROOT/platforms/gemini/policies.source.json" ]] || { printf 'error: no platforms/gemini/policies.source.json under %s\n' "$ROOT" >&2; exit 2; }

HOOKS_OUT=platforms/gemini/hooks.json
POLICY_OUT=platforms/gemini/policies/tamirs-superpowers.toml
PERM_OUT=platforms/gemini/policies/tamirs-superpowers-permissions.toml
DEST="$ROOT"
if [[ "$CHECK" == true ]]; then
  DEST="$(mktemp -d)"
  trap 'rm -rf "$DEST"' EXIT
fi

python3 - "$ROOT" "$DEST" "$HOOKS_OUT" "$POLICY_OUT" "$PERM_OUT" "$VERBOSE" <<'PY' || exit 2
import json, os, re, sys

root, dest, hooks_out, policy_out, perm_out = sys.argv[1:6]
verbose = sys.argv[6] == "true"

def load(rel):
    with open(os.path.join(root, rel), encoding="utf-8") as f:
        try:
            return json.load(f)
        except ValueError as e:
            sys.exit("error: %s is not valid JSON: %s" % (rel, e))

canon = load("hooks/hooks.json")
policy_src = load("platforms/gemini/policies.source.json")

EVENT_MAP = {
    "PreToolUse": "BeforeTool", "PostToolUse": "AfterTool", "UserPromptSubmit": "BeforeAgent",
    "Stop": "AfterAgent", "PreCompact": "PreCompress",
    "SessionStart": "SessionStart", "SessionEnd": "SessionEnd", "Notification": "Notification",
}
DROPPED_EVENTS = ["WorktreeCreate", "WorktreeRemove", "DirectoryAdded", "StopFailure", "SubagentStop", "TaskCompleted", "TeammateIdle"]
TOOL_EVENTS = {"BeforeTool", "AfterTool"}
TOOL_MAP = {
    "Bash": "run_shell_command", "Shell": "run_shell_command",
    "Edit": "replace", "MultiEdit": "replace", "NotebookEdit": "replace", "StrReplace": "replace",
    "Write": "write_file",
}
HOOK_KEYS = {"type", "command", "timeout", "statusMessage", "onFailure"}
GROUP_KEYS = {"matcher", "hooks", "sequential"}
WRAPPER = "hooks/gemini-wrap.sh"
CMD_RE = re.compile(r'^(bash|python3)\s+"\$\{CLAUDE_PLUGIN_ROOT\}"?/?([^"\s]+)"?\s*$')
# Claude matcher tokens with no runnable Gemini counterpart that are left out ON
# PURPOSE (see THE MAPPING above). A group made only of these is dropped whole:
# turning it into a matcher-less group would fire its hooks on every tool.
SKIPPED_MATCHERS = {
    "mcp__plugin_tamirs-superpowers_github__.*":
        "Gemini names these tools mcp_github_<tool> and gemini-wrap.sh passes the name through, so "
        "permission-guard.sh would see no GitHub MCP tool and allow every call; the static policy "
        "(tamirs-superpowers-permissions.toml, mcpName = github) and the server flags are the layer (ADR 004 D8)",
}

errors = []
def err(msg): errors.append(msg)

if not os.path.isfile(os.path.join(root, WRAPPER)):
    err("%s is missing; every generated command runs through it" % WRAPPER)

hooks_in = canon.get("hooks")
if not isinstance(hooks_in, dict):
    sys.exit("error: hooks/hooks.json has no `hooks` object")

SKIP = object()

def translate_matcher(event, matcher):
    """Claude tool matcher -> anchored Gemini regex, None for match-all, SKIP to drop the group."""
    if matcher is None or matcher.strip() in ("", "*"):
        return None
    tools = []
    skipped = []
    for tok in matcher.split("|"):
        tok = tok.strip()
        if tok in SKIPPED_MATCHERS:
            skipped.append(tok)
            continue
        if tok not in TOOL_MAP:
            err("%s: matcher token %r has no Gemini tool mapping; add it to TOOL_MAP or drop it" % (event, tok))
            continue
        if TOOL_MAP[tok] not in tools:
            tools.append(TOOL_MAP[tok])
    if tools:
        return "^(%s)$" % "|".join(tools)
    return SKIP if skipped else None

def slug_for(tools_regex):
    return "shell" if "run_shell_command" in (tools_regex or "") else "write"

hooks_out_obj = {}
dropped = []
skipped_groups = []
names = {}
for event, groups in hooks_in.items():
    if event in DROPPED_EVENTS:
        dropped.append(event); continue
    if event not in EVENT_MAP:
        err("hooks/hooks.json wires %s, an event neither the Gemini map nor the known-dropped list names; add it to one in this script" % event)
        continue
    gev = EVENT_MAP[event]
    out_groups = []
    for g in groups:
        extra = set(g) - GROUP_KEYS
        if extra:
            err("%s: group key(s) %s are not understood by this generator" % (event, sorted(extra)))
        og = {}
        matcher = None
        if gev in TOOL_EVENTS:
            matcher = translate_matcher(event, g.get("matcher"))
            if matcher is SKIP:
                toks = [t.strip() for t in g.get("matcher").split("|")]
                skipped_groups.append(("%s %s (%s)" % (event, g.get("matcher"), ", ".join(
                    os.path.basename(str(h.get("command", "")).rstrip('"')) for h in g.get("hooks", []))),
                    "; ".join(SKIPPED_MATCHERS[t] for t in toks if t in SKIPPED_MATCHERS)))
                continue
            if matcher:
                og["matcher"] = matcher
        # A lifecycle matcher on Gemini is an exact-string compare against the
        # event's trigger; Claude's `*` is dropped so the group matches everything.
        if "sequential" in g:
            og["sequential"] = bool(g["sequential"])
        og["hooks"] = []
        for h in g.get("hooks", []):
            extra = set(h) - HOOK_KEYS
            if extra:
                err("%s: hook key(s) %s are not understood by this generator" % (event, sorted(extra)))
            if h.get("type") != "command":
                err("%s: hook type %r is not a command; Gemini runs command hooks only" % (event, h.get("type")))
                continue
            m = CMD_RE.match(h.get("command", ""))
            if not m:
                err("%s: command %r is not `<bash|python3> \"${CLAUDE_PLUGIN_ROOT}\"/<script>`" % (event, h.get("command")))
                continue
            interp, rel = m.group(1), m.group(2)
            if not os.path.isfile(os.path.join(root, rel)):
                err("%s: command names %s, which does not exist in this tree" % (event, rel))
            if (interp == "python3") != rel.endswith(".py"):
                err("%s: %s is run with %s but gemini-wrap.sh picks the interpreter by extension" % (event, rel, interp))
            stem = os.path.splitext(os.path.basename(rel))[0]
            name = stem + ("-" + slug_for(matcher) if gev in TOOL_EVENTS else "")
            if name in names:
                err("%s: hook name %r collides with %s; names must be unique for /hooks enable|disable" % (event, name, names[name]))
            names[name] = "%s (%s)" % (rel, gev)
            oh = {
                "name": name,
                "type": "command",
                "command": 'bash "${extensionPath}/%s" "${extensionPath}/%s"' % (WRAPPER, rel),
            }
            if "timeout" in h:
                if not isinstance(h["timeout"], (int, float)) or h["timeout"] <= 0:
                    err("%s: timeout %r is not a positive number of seconds" % (event, h["timeout"]))
                else:
                    oh["timeout"] = int(round(h["timeout"] * 1000))
            if h.get("statusMessage"):
                oh["description"] = h["statusMessage"]
            og["hooks"].append(oh)
        if og["hooks"]:
            out_groups.append(og)
    if out_groups:
        hooks_out_obj.setdefault(gev, []).extend(out_groups)

DESCRIPTION = (
    "GENERATED by scripts/build-gemini-hooks.sh from hooks/hooks.json - do not edit; regenerate with "
    "`bash scripts/build-gemini-hooks.sh .`. Gemini CLI reads only the `hooks` object of an extension's "
    "hooks/hooks.json (this key is ignored). Events: PreToolUse->BeforeTool, PostToolUse->AfterTool, "
    "UserPromptSubmit->BeforeAgent, Stop->AfterAgent, PreCompact->PreCompress; SessionStart, SessionEnd "
    "and Notification by name; " + ", ".join(DROPPED_EVENTS) + " have no Gemini event and are left out. "
    "Every command runs the canonical hook through hooks/gemini-wrap.sh, which translates the payload "
    "(write_file->Write, replace->Edit, run_shell_command->Bash) and the answer ({decision:deny,reason} / "
    "{} / hookSpecificOutput.additionalContext or systemMessage). Timeouts are milliseconds. Claude's "
    "onFailure has no Gemini field, so every guard is fail-open here: a guard that crashes or times out "
    "lets the action through; policies/*.toml are the hook-free layer. permission-guard.sh answers deny, "
    "never ask, on Gemini (a hook ask hangs a headless run, ADR 004 D8)."
    + "".join(" Left out on purpose: %s - %s." % g for g in skipped_groups)
)

# --- policies ------------------------------------------------------------------
priority = policy_src.get("priority", 100)
if not isinstance(priority, int) or not (0 <= priority <= 999):
    err("policies.source.json priority must be an integer 0-999, not %r" % (priority,))
    priority = 100
ask_priority = policy_src.get("ask_user_priority", 90)
if not isinstance(ask_priority, int) or not (0 <= ask_priority <= 999):
    err("policies.source.json ask_user_priority must be an integer 0-999, not %r" % (ask_priority,))
    ask_priority = 90
elif ask_priority >= priority:
    err("policies.source.json ask_user_priority (%d) must be lower than priority (%d): a deny must outrank "
        "every ask_user, or an ask would open what a deny closes" % (ask_priority, priority))
macros = policy_src.get("regex_macros", {})
if not isinstance(macros, dict) or not all(isinstance(k, str) and re.match(r"^[A-Z]+$", k) and isinstance(v, str)
                                           for k, v in macros.items()):
    err("policies.source.json regex_macros must map UPPERCASE names to regex strings")
    macros = {}

def toml_literal(s, where):
    if "'" in s or "\n" in s:
        err("%s: a TOML literal string cannot contain a single quote or a newline: %r" % (where, s))
    return "'" + s + "'"

def toml_basic(s):
    return json.dumps(s, ensure_ascii=False)

def expand(pattern, rid):
    def sub(m):
        if m.group(1) not in macros:
            err("policy rule %s: unknown regex macro %%%s%%" % (rid, m.group(1)))
            return ""
        return macros[m.group(1)]
    return re.sub(r"%([A-Z]+)%", sub, pattern)

NESTED_QUANTIFIER = re.compile(r"\([^)]*[*+?{].*\)[*+?{]")
LEGACY_KEYS = {"id", "mirrors", "decision", "toolName", "commandRegex", "argsPattern", "denyMessage"}
PERM_KEYS = LEGACY_KEYS | {"action", "r", "mcpName"}
seen_ids = set()

def render(rule_list, perm):
    blocks = []
    for r in rule_list:
        if not isinstance(r, dict):
            err("policy rule %r is not an object" % (r,)); continue
        rid = r.get("id") or "<no id>"
        if rid in seen_ids:
            err("policy rule id %r appears twice" % rid)
        seen_ids.add(rid)
        extra = set(r) - (PERM_KEYS if perm else LEGACY_KEYS)
        if "modes" in extra:
            err("policy rule %s: `modes` is not allowed - a mode-scoped rule does not hold in every approval "
                "mode, and Gemini drops an extension rule whose modes name yolo" % rid); continue
        if extra:
            err("policy rule %s: key(s) %s are not understood by this generator" % (rid, sorted(extra))); continue
        decision = r.get("decision", "deny")
        if not perm and decision != "deny":
            err("policy rule %s: decision must be deny (Gemini ignores allow in extension policies, and ask_user is not what a guard means)" % rid); continue
        if perm and decision not in ("deny", "ask_user"):
            err("policy rule %s: decision must be deny or ask_user, never %r (an extension cannot allow, "
                "and a rule that could widen is a bug)" % (rid, decision)); continue
        actions = r.get("action")
        if perm:
            if isinstance(actions, str):
                actions = [actions]
            if not (isinstance(actions, list) and actions and all(isinstance(a, str) and a for a in actions)):
                err("policy rule %s: action must name the catalog id(s) the rule stands for" % rid); continue
            if not isinstance(r.get("r"), int) or not (0 <= r["r"] <= 4):
                err("policy rule %s: r must be the action's rubric level 0-4" % rid); continue
            if decision == "ask_user" and r["r"] != 4:
                err("policy rule %s: a static ask_user holds at every level, which only an R4 action (never "
                    "automatic) may do; R%d is decided by permission-guard.sh per level" % (rid, r["r"])); continue
        tool = r.get("toolName")
        if isinstance(tool, str):
            tools = [tool]
            tool_toml = toml_basic(tool)
        elif isinstance(tool, list) and tool and all(isinstance(t, str) for t in tool):
            tools = tool
            tool_toml = "[" + ", ".join(toml_basic(t) for t in tool) + "]"
        else:
            err("policy rule %s: toolName must be a string or a list of strings" % rid); continue
        mcp = r.get("mcpName")
        if mcp is not None and not (isinstance(mcp, str) and re.match(r"^[A-Za-z0-9_-]+$", mcp)):
            err("policy rule %s: mcpName must be a server name" % rid); continue
        if mcp is not None and any(t.startswith("mcp_") or t == "*" for t in tools):
            err("policy rule %s: with mcpName, toolName is the server's own tool name (Gemini prefixes it)" % rid); continue
        has_cmd = "commandRegex" in r
        has_args = "argsPattern" in r
        if has_cmd and has_args:
            err("policy rule %s: commandRegex and argsPattern are mutually exclusive" % rid); continue
        if not has_cmd and not has_args and mcp is None:
            err("policy rule %s: exactly one of commandRegex or argsPattern is required" % rid); continue
        pattern = None
        if has_cmd or has_args:
            pattern = expand(r["commandRegex"] if has_cmd else r["argsPattern"], rid)
            try:
                re.compile(pattern)
            except re.error as e:
                err("policy rule %s: pattern does not compile: %s" % (rid, e)); continue
            # Gemini builds commandRegex into `"command":"<regex>` and DROPS, with only a
            # warning, any pattern its isSafeRegExp rejects (source-cited, gemini-cli 0.60.0
            # packages/core/src/policy/utils.ts: longer than 2048, or NESTED_QUANTIFIER below - which any
            # group holding a quantifier, `(?:` included, followed later by `)` + a
            # quantifier trips). A dropped rule is a must-hold rule that silently is not.
            built = ('"command":"' + pattern) if has_cmd else pattern
            if len(built) > 2048 or NESTED_QUANTIFIER.search(built):
                err("policy rule %s: Gemini would drop this pattern as a potential ReDoS (isSafeRegExp): no quantifier "
                    "may follow a closing parenthesis - write an optional group as (?:x|) and spell a repeat out" % rid)
                continue
        if has_cmd and (tools != ["run_shell_command"] or mcp is not None):
            err("policy rule %s: commandRegex only applies to run_shell_command" % rid)
        msg = r.get("denyMessage")
        if not isinstance(msg, str) or not msg.strip():
            err("policy rule %s: denyMessage is required" % rid); continue
        prio = ask_priority if decision == "ask_user" else priority
        lines = ["[[rule]]", "# %s" % rid]
        if perm:
            lines.append("# action: %s (R%d)" % (", ".join(actions), r["r"]))
        for mline in (r.get("mirrors") or "").split("\n"):
            if mline.strip():
                lines.append("# mirrors: %s" % mline.strip())
        lines.append("toolName = %s" % tool_toml)
        if mcp is not None:
            lines.append("mcpName = %s" % toml_basic(mcp))
        if pattern is not None:
            lines.append("%s = %s" % ("commandRegex" if has_cmd else "argsPattern", toml_literal(pattern, rid)))
        lines.append("decision = %s" % toml_basic(decision))
        lines.append("priority = %d" % prio)
        lines.append("denyMessage = %s" % toml_basic(msg))
        blocks.append("\n".join(lines))
    return blocks

rules = policy_src.get("rules")
if not isinstance(rules, list) or not rules:
    err("policies.source.json has no non-empty `rules` list")
    rules = []
perm_rules = policy_src.get("permission_rules")
if not isinstance(perm_rules, list) or not perm_rules:
    err("policies.source.json has no non-empty `permission_rules` list")
    perm_rules = []
rule_blocks = render(rules, False)
perm_blocks = render(perm_rules, True)

if errors:
    sys.exit("\n".join("error: " + e for e in errors))

HEADER = [
    "# GENERATED FILE — DO NOT EDIT.",
    "#   Source:     platforms/gemini/policies.source.json (%s)",
    "#   Generator:  scripts/build-gemini-hooks.sh",
    "#   Regenerate: bash scripts/build-gemini-hooks.sh .",
    "#",
    "# Gemini CLI loads every policies/*.toml at the extension root as tier-2 rules",
    "# (tier + priority/1000; the YOLO allow-all is 1.998, so a mode-less rule here",
    "# holds under --yolo). An extension may contribute only deny and ask_user:",
    "# loadExtensionPolicies drops allow rules and rules whose modes name yolo, so",
    "# these files can narrow what the model may do and never widen it. A user-tier",
    "# rule (~/.gemini/policies/*.toml) or an \"Always allow\" outranks them.",
    "#",
]
policy_text = "\n".join([HEADER[1] % "rules" if i == 1 else h for i, h in enumerate(HEADER)] + [
    "# Every rule below is a deny at priority %d, mirroring a hook or policy this" % priority,
    "# plugin already enforces. The ADR 004 permission rules (ask_user for R4) are",
    "# in tamirs-superpowers-permissions.toml beside this file.",
    "#",
    "# Not expressible statically (left to the hooks in hooks/hooks.json):",
] + ["#   - " + n for n in policy_src.get("not_expressible", [])] + ["", "\n\n".join(rule_blocks)]) + "\n"

perm_text = "\n".join([HEADER[1] % "permission_rules" if i == 1 else h for i, h in enumerate(HEADER)] + [
    "# ADR 004 D8, the static half of the Gemini permission layer:",
    "#   ask_user (priority %d): the R4 command forms. Interactive, Gemini asks;" % ask_priority,
    "#     with no TTY it denies (measured G3, also under --yolo). Never automatic.",
    "#   deny (priority %d): what ADR 004 denies outright - the host config CLIs," % priority,
    "#     plugin-config.sh provision, writes to protected paths (D10.1) and the",
    "#     GitHub MCP tools the server excludes on Gemini (D8 flags table).",
    "# Every deny outranks every ask_user. The level-dependent R2/R3 decisions are",
    "# hooks/permission-guard.sh's (BeforeTool), which answers deny, never ask: a",
    "# hook ask hangs a headless run (measured G1).",
    "#",
    "# Not expressible statically (left to hooks/permission-guard.sh and guard-sensitive-files.sh):",
] + ["#   - " + n for n in policy_src.get("permission_not_expressible", [])] + ["", "\n\n".join(perm_blocks)]) + "\n"

for rel, text in ((hooks_out, json.dumps({"description": DESCRIPTION, "hooks": hooks_out_obj}, indent=2, ensure_ascii=False) + "\n"),
                  (policy_out, policy_text), (perm_out, perm_text)):
    path = os.path.join(dest, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
if verbose:
    print("kept events: " + ", ".join(hooks_out_obj))
    print("dropped events: " + (", ".join(dropped) or "none"))
    print("skipped matcher groups: " + (", ".join(g for g, _ in skipped_groups) or "none"))
    print("hook names: " + ", ".join(sorted(names)))
    print("policy rules: %d" % len(rule_blocks))
    print("permission rules: %d (ask_user %d, deny %d)" % (
        len(perm_blocks), sum('decision = "ask_user"' in b for b in perm_blocks),
        sum('decision = "deny"' in b for b in perm_blocks)))
PY

if [[ "$CHECK" == true ]]; then
  drift=0
  for f in "$HOOKS_OUT" "$POLICY_OUT" "$PERM_OUT"; do
    if [[ ! -f "$ROOT/$f" ]]; then
      printf 'DRIFT: %s is missing from the tree\n' "$f" >&2; drift=1
    elif ! diff -u "$ROOT/$f" "$DEST/$f" >&2; then
      printf 'DRIFT: %s differs from what its source generates\n' "$f" >&2; drift=1
    fi
  done
  if (( drift )); then
    printf 'Regenerate: bash scripts/build-gemini-hooks.sh .\n' >&2
    exit 1
  fi
  printf 'gemini hooks: %s, %s and %s match their sources\n' "$HOOKS_OUT" "$POLICY_OUT" "$PERM_OUT"
  exit 0
fi
printf 'gemini hooks: wrote %s, %s and %s\n' "$HOOKS_OUT" "$POLICY_OUT" "$PERM_OUT"
