#!/usr/bin/env bash
# build-gemini-hooks.sh — generate the Gemini CLI hooks file and deny policies.
#
# Usage:
#   bash scripts/build-gemini-hooks.sh [repo-root] [--check] [--verbose]
#   bash scripts/build-gemini-hooks.sh -h | --help
#
# Generates:
#   platforms/gemini/hooks.json                      — from hooks/hooks.json
#   platforms/gemini/policies/tamirs-superpowers.toml — from platforms/gemini/policies.source.json
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
#   Any other Claude event, matcher token or per-hook key is an error (exit 2),
#   so a new canonical entry cannot ship to Gemini half-translated.
#
# THE MAPPING (policies)
#   Every rule in policies.source.json becomes a `[[rule]]` with
#   `decision = "deny"` and the shared priority; toolName, commandRegex and
#   argsPattern are written as TOML literal strings so no regex needs escaping
#   twice. A rule naming any other decision, or a regex that does not compile,
#   is an error.
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
DEST="$ROOT"
if [[ "$CHECK" == true ]]; then
  DEST="$(mktemp -d)"
  trap 'rm -rf "$DEST"' EXIT
fi

python3 - "$ROOT" "$DEST" "$HOOKS_OUT" "$POLICY_OUT" "$VERBOSE" <<'PY' || exit 2
import json, os, re, sys

root, dest, hooks_out, policy_out, verbose = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] == "true"

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

errors = []
def err(msg): errors.append(msg)

if not os.path.isfile(os.path.join(root, WRAPPER)):
    err("%s is missing; every generated command runs through it" % WRAPPER)

hooks_in = canon.get("hooks")
if not isinstance(hooks_in, dict):
    sys.exit("error: hooks/hooks.json has no `hooks` object")

def translate_matcher(event, matcher):
    """Claude tool matcher -> anchored Gemini regex, or None for match-all."""
    if matcher is None or matcher.strip() in ("", "*"):
        return None
    tools = []
    for tok in matcher.split("|"):
        tok = tok.strip()
        if tok not in TOOL_MAP:
            err("%s: matcher token %r has no Gemini tool mapping; add it to TOOL_MAP or drop it" % (event, tok))
            continue
        if TOOL_MAP[tok] not in tools:
            tools.append(TOOL_MAP[tok])
    return "^(%s)$" % "|".join(tools) if tools else None

def slug_for(tools_regex):
    return "shell" if "run_shell_command" in (tools_regex or "") else "write"

hooks_out_obj = {}
dropped = []
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
    "lets the action through."
)

# --- policies ------------------------------------------------------------------
rules = policy_src.get("rules")
if not isinstance(rules, list) or not rules:
    err("policies.source.json has no non-empty `rules` list")
    rules = []
priority = policy_src.get("priority", 100)
if not isinstance(priority, int) or not (0 <= priority <= 999):
    err("policies.source.json priority must be an integer 0-999, not %r" % (priority,))

def toml_literal(s, where):
    if "'" in s or "\n" in s:
        err("%s: a TOML literal string cannot contain a single quote or a newline: %r" % (where, s))
    return "'" + s + "'"

def toml_basic(s):
    return json.dumps(s, ensure_ascii=False)

seen_ids = set()
rule_blocks = []
for r in rules:
    rid = r.get("id") or "<no id>"
    if rid in seen_ids:
        err("policy rule id %r appears twice" % rid)
    seen_ids.add(rid)
    if r.get("decision", "deny") != "deny":
        err("policy rule %s: decision must be deny (Gemini ignores allow in extension policies, and ask_user is not what a guard means)" % rid)
    tool = r.get("toolName")
    if isinstance(tool, str):
        tool_toml = toml_basic(tool)
    elif isinstance(tool, list) and tool and all(isinstance(t, str) for t in tool):
        tool_toml = "[" + ", ".join(toml_basic(t) for t in tool) + "]"
    else:
        err("policy rule %s: toolName must be a string or a list of strings" % rid); continue
    has_cmd = "commandRegex" in r
    has_args = "argsPattern" in r
    if has_cmd == has_args:
        err("policy rule %s: exactly one of commandRegex or argsPattern is required" % rid); continue
    pattern = r["commandRegex"] if has_cmd else r["argsPattern"]
    try:
        re.compile(pattern)
    except re.error as e:
        err("policy rule %s: pattern does not compile: %s" % (rid, e)); continue
    if has_cmd and not ("run_shell_command" == tool or tool == ["run_shell_command"]):
        err("policy rule %s: commandRegex only applies to run_shell_command" % rid)
    msg = r.get("denyMessage")
    if not isinstance(msg, str) or not msg.strip():
        err("policy rule %s: denyMessage is required" % rid); continue
    lines = ["[[rule]]", "# %s" % rid]
    for mline in (r.get("mirrors") or "").split("\n"):
        if mline.strip():
            lines.append("# mirrors: %s" % mline.strip())
    lines.append("toolName = %s" % tool_toml)
    lines.append("%s = %s" % ("commandRegex" if has_cmd else "argsPattern", toml_literal(pattern, rid)))
    lines.append('decision = "deny"')
    lines.append("priority = %d" % priority)
    lines.append("denyMessage = %s" % toml_basic(msg))
    rule_blocks.append("\n".join(lines))

if errors:
    sys.exit("\n".join("error: " + e for e in errors))

policy_text = "\n".join([
    "# GENERATED FILE — DO NOT EDIT.",
    "#   Source:     platforms/gemini/policies.source.json",
    "#   Generator:  scripts/build-gemini-hooks.sh",
    "#   Regenerate: bash scripts/build-gemini-hooks.sh .",
    "#",
    "# Gemini CLI loads every policies/*.toml at the extension root as tier-2 rules.",
    "# Only deny (and ask_user) are honoured in an extension policy; every rule",
    "# below is a deny, so this file can narrow what the model may do and never",
    "# widen it. A user-tier rule (~/.gemini/policies/*.toml) outranks these.",
    "#",
    "# Not expressible statically (left to the hooks in hooks/hooks.json):",
] + ["#   - " + n for n in policy_src.get("not_expressible", [])] + ["", "\n\n".join(rule_blocks)]) + "\n"

for rel, text in ((hooks_out, json.dumps({"description": DESCRIPTION, "hooks": hooks_out_obj}, indent=2, ensure_ascii=False) + "\n"),
                  (policy_out, policy_text)):
    path = os.path.join(dest, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
if verbose:
    print("kept events: " + ", ".join(hooks_out_obj))
    print("dropped events: " + (", ".join(dropped) or "none"))
    print("hook names: " + ", ".join(sorted(names)))
    print("policy rules: %d" % len(rule_blocks))
PY

if [[ "$CHECK" == true ]]; then
  drift=0
  for f in "$HOOKS_OUT" "$POLICY_OUT"; do
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
  printf 'gemini hooks: %s and %s match their sources\n' "$HOOKS_OUT" "$POLICY_OUT"
  exit 0
fi
printf 'gemini hooks: wrote %s and %s\n' "$HOOKS_OUT" "$POLICY_OUT"
