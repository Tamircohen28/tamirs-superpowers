#!/usr/bin/env bash
# permission-guard.sh — PreToolUse permission guard (PG) for Bash/Shell and the
# bundled GitHub MCP server's tools (ADR 004 item 4; D1, D2, D7, D8).
#
# WHAT IT DECIDES
#   Every shell command and GitHub MCP call is mapped onto the action ids of
#   core/permissions/actions.json (D1) — the argv forms, the REST paths, GraphQL
#   mutations, refspecs and HTTP clients the catalog lists as equivalents — and
#   each id is put to scripts/resolve-permission.sh (D4), the one implementation
#   of levels and precedence. The answer is the strictest verdict of every id the
#   call reaches (deny > ask > allow; a tie reports the highest R). A command that
#   maps to no id but carries one of the catalog's mutation markers
#   (unclassified.mutation_markers: `git push`, api.github.com, graphql, ...; and
#   unclassified.mutation_marker_patterns, the token command and variables, kept
#   as patterns so no shipped file spells a credential name) or runs `gh` is
#   UNCLASSIFIED, which is R4: never automatic.
#
#   R0/R1 ids with no context raise and the "L1 only" ids (notify.send,
#   net.post.external, deps.install, daemon.*) need no resolver call: D8 puts L2
#   shell enforcement at R2-R4, and D1 gives those ids no L2 point.
#
# FAST PATH
#   A command none of whose words can reach a guarded id (no gh, no curl, no git
#   push/reset/commit/..., no agent CLI, no tty driver, no package manager, no
#   marker) AND every segment of which starts with a known-inert command (ls,
#   cat, echo, grep, git status/log/diff, ...) is allowed by a bash-only
#   pre-filter: no python, no resolver. It strips quotes and backslashes and
#   matches in any case, so `g"i"t push`, `GIT push` and `GH pr merge` cannot
#   hide; a first word holding $ { [ * ? ~ or split by a backslash-newline is not
#   inert. Measured: about 38 ms per `git status` call (37 ms before the
#   allow-list, the suite's mean of 10).
#   Everything else is tokenised by lib/command-tokens.sh (shared with the
#   concurrency guard) in a bash started with LC_ALL=C, under a 4 s deadline,
#   and matched by the engine below. A command longer than 8 KB that reaches
#   the engine is denied before it is tokenised (it could outlast the hook's
#   deadline, F5), with the remedy: put long text in a file.
#
# WHAT THE ENGINE READS AS A SHELL WOULD (task-017)
#   The program word in lower case, through ${IFS}, brace expansion and a glob
#   (`/usr/bin/gi[t]`); a program still built at runtime is UNCLASSIFIED. The
#   wrappers of the catalog's prefix_commands with their value options
#   (caffeinate, arch, setsid, gtimeout, xargs, watch, exec -a, ...), env -S,
#   su -c, find -exec, here-documents and herestrings fed to a shell, comments,
#   process substitution. Any construct the tokeniser flags as an anomaly
#   ($'...', ((...)), case in a substitution, nested backticks, an unterminated
#   quote or here-document, nesting past 4, a shell reading a pipe) is
#   UNCLASSIFIED (R4). `gh` as a word in a segment that is not an inert command
#   is the D1 `gh ` marker. git long options are read through their unique
#   prefixes; hosts, markers and REST paths in any case; httpie/xh methods;
#   every curl body form.
#
# CONDITIONS (D4: unknown never holds; a raise or deny applies unless false)
#   Read locally: default_branch and tag_ref for git push and the GitHub MCP/REST
#   branch writes (refs/remotes/<remote>/HEAD; main and master always count as
#   default), uncommitted_changes, drops_unpushed_commits, discards_work,
#   unmerged_no_remote_copy, unmerged_commits (only "fully merged" is shown) and
#   workflow_hook_or_policy_path.
#   Read from GitHub, through lib/permission-conditions.sh, under ONE deadline of
#   3 s for the whole call (D8: well under the host timeout): the default branch
#   when refs/remotes/<remote>/HEAD does not resolve (gh repo view of the
#   remote's push URL), and required_check_failing_or_pending for
#   `gh pr merge --admin` (gh pr checks --required). An error, a timeout or an
#   answer PG cannot read leaves the condition unknown, so its raise or deny
#   applies exactly as with no lookup at all.
#   Still unknown, so their raise or deny applies: protected_default_branch, PR
#   state, thread authorship, claims, lockfiles. A command whose working
#   directory or target environment PG cannot pin (more than one `cd`, a `cd` not
#   of the form `cd <dir> && …`, `export`/`source`/`unset`, GIT_DIR=…,
#   git -c/--git-dir, GH_REPO=… or --hostname on the merge) gets no repository
#   condition at all.
#
# PER HOST (D8)
#   claude  allow | ask | deny (hookSpecificOutput.permissionDecision). The ask
#           is the D5 host prompt and the only route for R4; headless it denies.
#   codex   deny only: a hook ask fails OPEN there (X1), so an ask is delivered
#           as a deny naming the out-of-session route. Every internal error is
#           trapped to a deny and the script always exits 0, because Codex lets
#           a call through on any other exit or on malformed output.
#   cursor  deny only: preToolUse drops ask and beforeShellExecution's forced
#           prompt stays unused until spike S1 is measured (D5, D8).
#   gemini  (gemini_tool_name in the payload, which hooks/gemini-wrap.sh adds)
#           deny only: a hook ask hangs headless (G1). gemini-wrap.sh also turns
#           any ask into a deny and maps the bundled GitHub MCP server's
#           mcp_github_<tool> calls onto the Claude names below.
#   opencode  ("host": "opencode" in the payload, which platforms/opencode/plugin/
#           guard.ts builds) ask for R2 only, deny for everything that must survive
#           `opencode --auto`: every R3/R4 id, never_auto, UNCLASSIFIED (D8 "R2: hook
#           ask (A under --auto); R3/R4: deny", O1b/O1c). The answer has Claude's
#           shape; guard.ts maps ask -> OpenCode ask, deny -> deny.
#   The host is read from the payload's SHAPE (Cursor's keys, gemini_tool_name,
#   Codex's turn_id, "host": "opencode", else Claude Code), never from the
#   environment alone (F7): a repository can set CODEX_HOME, GEMINI_SESSION_ID or
#   GEMINI_PROJECT_DIR. Where the environment names another host, the STRICTER
#   dialect answers (deny-only > OpenCode's R2 ask > Claude's ask) and every id
#   is resolved under both hosts, the strictest answer kept. The resolver is told
#   the host (--host) so the option store and the "setting that would allow it"
#   are that host's.
#
# D5-D7 DUTIES
#   The call stamp (D8): a resolve-permission.sh call carrying --call <token> in
#   a command PG does not deny (as delivered: an ask a host cannot carry is a
#   deny) gets <state>/seen/<token> (dirs 0700), which the resolver consumes as
#   proof that PG ran. <state> is <passwd home>/.local/state/tamirs-superpowers,
#   read with pwd.getpwuid unless the test override is in the environment, when
#   scripts/lib/permission-common.sh decides (D3). policy.edit forms that must never run
#   from agent Bash are denied outright: plugin-config.sh provision (D6) and the
#   host config CLIs `claude plugin configure`, `gemini extensions config` (D7).
#   Every other policy.edit form the catalog lists (plugin-config.sh writes,
#   confirm, setup.sh --permission-level) is R4: the Claude dialog asks, every
#   other host denies.
#   plugin-config.sh confirm <nonce> (D5): the dialog must name what it approves,
#   so PG reads <state>/pending/<nonce>.json (0600, its own hash checked, not
#   expired) and puts its skill, level, target and expiry (a --perms= request) or
#   its widened rows (a config change) in the ask; a nonce with no usable record is
#   a deny. Before it answers that ask, PG writes <state>/asked/<nonce>.json
#   {version, nonce, file_sha256 (the bytes it showed), body_sha256, kind,
#   session_id, agent, tool_use_id (the payload's: the very call the prompt was
#   shown for, which the writer's PostToolUse hook matches before it promotes a
#   staged widening), host, at, expires}, 0600 in a 0700 dir: the call-stamp
#   pattern of D8 applied to the confirm, so the writer can require proof that
#   this very confirm, these very bytes, went to the host prompt.
#   The writer itself is recognised however it is named (F1): as any argument of
#   an interpreter (past -o/-O/--rcfile values), in any case, through a glob, a
#   link or a byte-identical copy; and any other command naming it (cp, ln, mv,
#   cat, ...) is policy.edit unless it only inspects it with no redirect or pipe.
#   The active skill (D8 "per-skill levels at L2"): <state>/intent/<sid>.json
#   (the main thread) and <sid>.agent-<agent_id>.json (a subagent), written by
#   hooks/permission-intent.sh (format in its header). The skill is passed to the
#   resolver as --skill and the objective as --objective (D4 row 3, tighten
#   only). A per-skill level from the user's own verified, locked file may widen
#   only when the host recorded the skill as active for THIS agent: a
#   UserPromptExpansion paired with its UserPromptSubmit (one prompt_id, M2), or a
#   PreToolUse on the Skill tool (host_recorded). It no longer needs `source ==
#   "user"`, which Claude Code never sends (M3). Otherwise each id is resolved
#   with and without the skill and the stricter answer stands (a lowering needs no
#   provenance, SR S-09). A subagent's call is also resolved under the main
#   thread's context, the strictest answer kept, so it runs at most at the main
#   thread's level (D1 agent.spawn) and a main-thread skill never raises it (M5);
#   a subagent's context never touches a main-thread call. Project-file per-skill
#   levels only tighten (the resolver). A missing, unsafe, stale or malformed
#   context is no skill: the global level decides; it never errors into an allow.
#   --perms= tickets (D4 row 1, D5): every resolver call carries --session and
#   --agent (the payload's session_id and agent_id; Claude Code sends agent_id on
#   every subagent call and on no main-thread call, measured M5, so no agent_id
#   is the main thread) and, for the R2/R3 actions of the
#   pr, issue and repo target kinds, --target: the selector of `gh pr|issue <verb>
#   <n|url>` (with -R/GH_REPO=), the MCP call's owner/repo and number, or "." for
#   the repository gh would use. The resolver reads and matches the tickets itself.
#   A target PG cannot pin (a branch selector, --hostname, GH_HOST=, an unpinned
#   cd, a bare number or "." in a checkout whose remotes name more than one
#   repository) is not passed, and no ticket matches a call without one.
#
# FAIL CLOSED (D4, SR S-12)
#   Unparseable payload, no jq, no python3, a missing or corrupt catalog, a
#   resolver that is missing, exits non-zero, times out or prints no verdict, an
#   engine crash, an unexpected exit of this script: all deny, with the reason.
#   An empty payload (nothing to judge) is allowed, as every guard here does.
#
# NOT SEEN (D1 residual, ADR Open risks): aliases, eval, make, scripts and
# interpreters this catalog does not name (their file contents), a modified copy
# of the writer, and anything assembled at runtime that is not the program word.
#
# INSPECTION (tests, debugging; read-only, never reached from a hook payload)
#   permission-guard.sh --classify '<command>' [cwd]
#   permission-guard.sh --classify-mcp <tool> '<args-json>' [cwd]
#       print, as JSON, the ids the call maps to, whether it is UNCLASSIFIED, the
#       resolver calls PG would make (id, --cond values, --target), the forms PG
#       denies outright, what the GitHub lookups found (notes) and whether the fast
#       path would have let it through. No resolver runs and nothing is written;
#       the GitHub lookups (reads, under the same deadline) do. A hook is never
#       given arguments.
#
# Bash 3.2 compatible. Needs jq (payload) and python3 (stdlib, -I -S).
set -uo pipefail

_PG_DONE=0

# Builtins-only deny for the paths where jq (or this script) cannot be trusted.
_pg_lit_deny() {
  local r="$1"
  r="${r//\\/\\\\}"; r="${r//\"/\\\"}"; r="${r//$'\n'/ }"; r="${r//$'\t'/ }"; r="${r//$'\r'/ }"
  if [ "${HOOK_PLATFORM:-claude}" = cursor ]; then
    printf '{"permission":"deny","user_message":"%s","agent_message":"%s"}\n' "$r" "$r"
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$r"
  fi
}

_pg_on_exit() {
  local rc=$?
  [ "$_PG_DONE" = 1 ] && return 0
  _PG_DONE=1
  _pg_lit_deny "tamirs-superpowers permission guard stopped before it could decide (exit $rc), so the call is denied (fail closed, ADR 004 D4, D8)."
  exit 0
}
trap _pg_on_exit EXIT
trap 'exit 1' INT TERM HUP

case "${BASH_SOURCE[0]}" in
  */*) _pg_here="${BASH_SOURCE[0]%/*}" ;;
  *) _pg_here=. ;;
esac
SCRIPT_DIR="$(CDPATH='' cd -- "$_pg_here" 2>/dev/null && pwd -P)" || exit 1
PG_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/.." 2>/dev/null && pwd -P)" || exit 1
unset _pg_here
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh" || exit 1
# shellcheck source=lib/command-tokens.sh
source "${SCRIPT_DIR}/lib/command-tokens.sh" || exit 1
# shellcheck source=lib/platform-tools.sh
source "${SCRIPT_DIR}/lib/platform-tools.sh" || exit 1

PG_MCP_PREFIX='mcp__plugin_tamirs-superpowers_github__'
PG_BUDGET="${PG_BUDGET_SECONDS:-20}"
case "$PG_BUDGET" in ''|*[!0-9]*) PG_BUDGET=20 ;; esac
[ "$PG_BUDGET" -gt 20 ] && PG_BUDGET=20

# _pg_blank <text> — 0 when the text holds nothing but white space. A case pattern, not
# ${text//[[:space:]]/}: under macOS's /bin/bash 3.2 that substitution is quadratic (4 s for a
# 4 KB payload, twice per call), which alone outlasted the hook timeout on a long command (F5).
_pg_blank() {
  case "$1" in *[![:space:]]*) return 1 ;; esac
  return 0
}

# _pg_finish <allow|ask|deny> <reason> — answer once, in the host's dialect.
_pg_finish() {
  local verdict="$1" reason="${2:-}"
  _PG_DONE=1
  case "$verdict" in
    allow) hook_allow ;;
    ask)
      printf '%s\n' "$reason" >&2
      # Belt: only the two dialects whose host carries a hook ask may answer one (the engine
      # already turns every other host's ask into a deny, D8).
      case "${PG_HOST:-}" in
        claude|opencode) hook_ask "$reason" ;;
        *) hook_deny "$reason" ;;
      esac ;;
    *)
      printf '%s\n' "$reason" >&2
      hook_deny "$reason" ;;
  esac
  exit 0
}

# _pg_candidate <command> — 0 when the command could reach a guarded id.
#
# Two filters, both case-insensitive (a case-insensitive file system runs `GIT`
# and `GH`), on the text with its quotes and backslashes stripped:
#   1. markers and program words anywhere (api.github.com, a token variable,
#      plugin-config, gh, curl, git + a mutating verb, ...);
#   2. an allow-list of first words: every segment (split at ; & | ( ) ` and
#      newlines) must start with a known-inert command, or `git` with a
#      read-only verb. Anything else (a wrapper, an interpreter, a word holding
#      $ { [ * ? ~, a word split by a backslash-newline) goes to the engine. A
#      reader of files (cat, grep, ...) is inert only with no glob, brace or
#      expansion in its segment, which could name the writer.
_pg_candidate() {
  local t="$1" b='(^|[[:space:];&|()`/!{])' e='([[:space:];&|)`]|$)' hit=0 nc=0 line w w2 rest
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  while :; do
    case "$t" in *\\$'\n'*) hit=1; break ;; esac
    t="${t//[\'\"\\]/}"
    case "$t" in
      # Any *_TOKEN variable (wider than the catalog's two token names, which the engine reads from the catalog).
      *api.github.com*|*uploads.github.com*|*graphql*|*_TOKEN*|*'gh auth'*) hit=1; break ;;
      *resolve-permission*|*plugin*config*|*setup.sh*|*install.sh*|*enable.sh*|*SETUP_PERMISSION_LEVEL*) hit=1; break ;;
      *cleanup-after-merge.sh*|*cleanup.sh*|*resolve-thread.sh*|*update-issue-resume.sh*|*notify-pushover.sh*) hit=1; break ;;
      *collector.py*|*handoff.sh*|*enable-repo-merge-settings.sh*|*github-policy.sh*|*ensure-branch-protection.sh*|*capture-config.sh*) hit=1; break ;;
      *claude-code*|*gemini-cli*|*opencode-ai*|*@openai/codex*|*node-pty*) hit=1; break ;;
    esac
    if [ -n "${GH_HOST:-}" ]; then
      case "$t" in *"$GH_HOST"*) hit=1; break ;; esac
    fi
    if [[ "$t" =~ $b(gh|curl|wget|http|https|xh|xhs|claude|codex|gemini|opencode|cursor-agent|agy|script|expect|unbuffer|tmux|cmux|screen|osascript|xdotool|ydotool|wtype|cliclick|wezterm|kitty|kitten|zellij|npm|npx|pnpm|yarn|bun|bunx|uv|uvx|pip|pip3|pipx|cargo|bundle|gem|brew|docker|docker-compose|podman|kill|pkill|killall)$e ]]; then hit=1; break; fi
    if [[ "$t" =~ ${b}git$e ]]; then
      if [[ "$t" =~ (^|[^[:alnum:]_-])(push|send-pack|http-push|remote|symbolic-ref|update-ref|reset|clean|checkout|restore|switch|stash|branch|tag|config|worktree|commit|merge|rebase|am|pull|fetch)([^[:alnum:]_-]|$) ]]; then hit=1; break; fi
      case "$t" in *alias*|*hooksPath*|*HUSKY*|*SKIP=*|*GIT_CONFIG*) hit=1; break ;; esac
    fi
    if [[ "$t" =~ ${b}(python|python3|node)$e ]]; then
      case "$t" in *pty*|*pip*|*cli.js*) hit=1; break ;; esac
    fi
    if [[ "$t" =~ ${b}go$e ]] && [[ "$t" =~ ${b}install$e ]]; then hit=1; break; fi
    # The allow-list of first words.
    while IFS= read -r line; do
      line="${line#"${line%%[![:space:]]*}"}"
      while :; do
        w="${line%%[[:space:]]*}"
        case "$w" in
          '!'|'{'|'}'|if|then|elif|else|fi|do|done|while|until) line="${line#"$w"}"; line="${line#"${line%%[![:space:]]*}"}" ;;
          *) break ;;
        esac
      done
      [ -n "$line" ] || continue
      w="${line%%[[:space:]]*}"
      case "$w" in
        echo|printf|pwd|true|false|test|'['|date|sleep|which|type|whoami|id|uname|hostname|basename|dirname|seq|cd|expr) continue ;;
        ls|cat|head|tail|wc|grep|egrep|fgrep|rg|sort|uniq|cut|tr|diff|cmp|stat|file|du|df|tree|less|more|jq|yq|mkdir|touch|column|nl|shasum|sha256sum|md5|md5sum|cksum|realpath|readlink)
          case "$line" in *[\*\?\[\{\$]*) hit=1; break ;; esac
          continue ;;
        git)
          rest="${line#"$w"}"; rest="${rest#"${rest%%[![:space:]]*}"}"; w2="${rest%%[[:space:]]*}"
          case "$w2" in
            status|log|diff|show|rev-parse|ls-files|blame|describe|shortlog|rev-list|cat-file|for-each-ref|show-ref|merge-base|grep|ls-tree|version|help|--version) continue ;;
          esac
          hit=1; break ;;
        *) hit=1; break ;;
      esac
    done <<< "${t//[;&|()\`]/$'\n'}"
    break
  done
  [ "$nc" = 1 ] || shopt -u nocasematch
  [ "$hit" = 1 ]
}

IFS= read -r -d '' _PG_ENGINE <<'PY' || true
import fnmatch, glob, hashlib, itertools, json, os, re, signal, stat, subprocess, sys, time

ROOT, HOST, MODE = sys.argv[1], sys.argv[2], sys.argv[3]
BUDGET = float(sys.argv[4]) if len(sys.argv) > 4 else 20.0
FAST = len(sys.argv) > 5 and sys.argv[5] == "1"
BASH = sys.argv[6] if len(sys.argv) > 6 and sys.argv[6] else "bash"
# The hosts the resolver is asked under (F7): the payload's, and the environment's when it names another. Every
# id is resolved under each and the strictest answer stands; HOST (the dialect) is already the stricter one.
RES_HOSTS = [h for h in (sys.argv[7].split(",") if len(sys.argv) > 7 else []) if h] or [HOST]
T0 = time.time()
ASK_HOSTS = ("claude",)       # carry every ask (the D5 dialog)
R2_ASK_HOSTS = ("opencode",)  # carry an R2 ask only; --auto approves it (D8, O1c)
UNCL = "UNCLASSIFIED"
SEP, NESTED = "\x1f", "\x1e"
CALL_RE = re.compile(r"\A[A-Za-z0-9_-]{8,128}\Z")
NONCE_RE = re.compile(r"\A[0-9a-f]{32}\Z")
SID_RE = re.compile(r"\A[A-Za-z0-9_-]{1,128}\Z")
SKILL_ID_RE = re.compile(r"\A[a-z0-9]+(-[a-z0-9]+)*\Z")
OBJ_ID_RE = re.compile(r"\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\Z")
UTC_RE = re.compile(r"\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\Z")
RANK = {"allow": 0, "ask": 1, "deny": 2}
RESOLVER = os.path.join(ROOT, "scripts", "resolve-permission.sh")
COND_LIB = os.path.join(ROOT, "hooks", "lib", "permission-conditions.sh")
NET_BUDGET = 3.0   # seconds, for every GitHub lookup of this call together (D8)
TOK_LIB = os.path.join(ROOT, "hooks", "lib", "command-tokens.sh")
TOK_DEADLINE = 4.0   # seconds for the shell tokeniser (F5); past it the call is denied
MAX_CMD = 8192       # bytes: a longer command that reaches the engine is denied before it is tokenised (F5)
ANOM, HERESTR, PIPED = "\x1d", "\x1c", "\x1a"


def answer(verdict, reason):
    sys.stdout.write(verdict + "\n" + " ".join(str(reason).split()) + "\n")
    sys.stdout.flush()
    sys.exit(0)


def left():
    return BUDGET - (time.time() - T0)


raw = sys.stdin.buffer.read().decode("utf-8", "surrogateescape")
try:
    PAY = json.loads(raw)
    if not isinstance(PAY, dict):
        raise ValueError("not an object")
except ValueError:
    answer("deny", "tamirs-superpowers permission guard: the hook payload is not a JSON object, so the call "
           "cannot be judged (fail closed, ADR 004 D4).")
try:
    with open(os.path.join(ROOT, "core", "permissions", "actions.json"), encoding="utf-8") as f:
        CAT = json.load(f)
    ACTS = CAT["actions"]
    BYID = {a["id"]: a for a in ACTS}
    M = CAT["matching"]
    MARKERS = [m.strip() for m in CAT["unclassified"]["mutation_markers"] if m.strip()]
    MARKER_RX = [re.compile(x) for x in CAT["unclassified"]["mutation_marker_patterns"]]
    PFX = CAT["mcp"]["claude_prefix"]
    for a in ACTS:
        a["equivalents"], a["r"]
except Exception as e:  # noqa: BLE001 - any catalog defect is a deny
    answer("deny", "tamirs-superpowers permission guard: the action catalog core/permissions/actions.json is "
           "missing or corrupt (%s), so no call can be classified (fail closed, ADR 004 D4)." % e.__class__.__name__)

PREFIX = set(M["prefix_commands"])
PREFIX_VALUE_OPTS = {k: set(v) for k, v in M.get("prefix_value_options", {}).items() if not k.startswith("_")}
DURATION_PREFIX = {"timeout", "gtimeout"}
SHELLS = {"bash", "sh", "zsh", "ksh", "dash", "mksh", "yash", "ash", "posh", "rbash", "fish"}
INTERP = SHELLS | {"source", ".", "python", "python2", "python3", "pypy", "pypy3", "node", "nodejs", "bun", "deno",
                   "perl", "ruby"}
INTERP_RX = re.compile(r"\A(python|pypy)[0-9.]*\Z")
# Option values of a shell or python (a word after one is not the script).
INTERP_VALUE_OPTS = {"-o", "+o", "-O", "+O", "--rcfile", "--init-file", "-m", "-W", "-X", "-r", "--require",
                     "--import", "--loader", "-I"}
HTTP = set(M["http_clients"])
HTTPIE = {"http", "https", "xh", "xhs"}
API_HOSTS = ["api.github.com", "uploads.github.com"]
if os.environ.get("GH_HOST"):
    API_HOSTS.append(os.environ["GH_HOST"].lower())
STD_DEFAULTS = ["main", "master"]
ENV_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
TARGET_ENV = re.compile(r"^(GH_REPO|GH_HOST|GH_ENTERPRISE_TOKEN|GIT_DIR|GIT_WORK_TREE|GIT_CONFIG_[A-Za-z0-9_]*|"
                        r"GIT_CONFIG_PARAMETERS|GIT_NAMESPACE|GIT_INDEX_FILE|GIT_OBJECT_DIRECTORY)=")
KNOWN_MCP = set(e["tool"][len(PFX):] for a in ACTS for e in a["equivalents"].get("mcp", []))


# --------------------------------------------------------------- tokens

CMD_TEXT = ""
_ti = PAY.get("tool_input")
if isinstance(_ti, dict) and isinstance(_ti.get("command"), str):
    CMD_TEXT = _ti["command"]
elif isinstance(PAY.get("command"), str):
    CMD_TEXT = PAY["command"]

SEGS, ANOMALIES, TOO_LONG = [], [], len(CMD_TEXT.encode("utf-8", "surrogateescape")) > MAX_CMD


def tokenise(cmd):
    """lib/command-tokens.sh's cmdtok_argv_segments, in a bash started with LC_ALL=C (character indexing is
    linear there), under TOK_DEADLINE: a tokeniser that does not answer in time is a deny (F5)."""
    env = dict(os.environ)
    env["LC_ALL"] = "C"
    try:
        pr = subprocess.Popen([BASH, "-c", '. "$1" || exit 3; cmdtok_argv_segments "$2"', "_", TOK_LIB, cmd],
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, env=env,
                              start_new_session=True)
    except OSError as e:
        answer("deny", "tamirs-superpowers permission guard: the shell tokeniser could not start (%s), so the call "
               "cannot be judged (fail closed, ADR 004 D4)." % e.__class__.__name__)
    try:
        out, _ = pr.communicate(timeout=min(TOK_DEADLINE, max(0.5, left() - 2.0)))
    except subprocess.TimeoutExpired:
        try:
            os.killpg(pr.pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            pr.communicate(timeout=1.0)
        except (OSError, subprocess.SubprocessError):
            pass
        answer("deny", "tamirs-superpowers permission guard: the command could not be tokenised within %d s, so it "
               "is denied (fail closed, ADR 004 D4). Split it, or put long text in a file and pass the file." %
               TOK_DEADLINE)
    if pr.returncode != 0:
        answer("deny", "tamirs-superpowers permission guard: the shell tokeniser exited %d, so the call cannot be "
               "judged (fail closed, ADR 004 D4)." % pr.returncode)
    return out.decode("utf-8", "surrogateescape")


if MODE in ("shell", "classify-shell") and not TOO_LONG:
    for line in tokenise(CMD_TEXT).split("\n"):
        if not line:
            continue
        if line.startswith(ANOM):
            if line[1:] not in ANOMALIES:
                ANOMALIES.append(line[1:])
            continue
        nested = line.startswith(NESTED)
        if nested:
            line = line[1:]
        toks = [t.replace(HERESTR, "") for t in line.split(SEP) if t != PIPED]
        if any(toks):
            SEGS.append({"nested": nested, "toks": toks})


def is_interp(name):
    return name in INTERP or bool(INTERP_RX.match(name or ""))


# git accepts any unique prefix of a long option (`--no-verif`, `--har`, `--delet`): the long options the catalog
# and PG read for each git verb, so such a prefix is read as its option before anything matches (F8).
GIT_LONG = {}
for _a in ACTS:
    for _e in _a["equivalents"].get("argv", []):
        if _e.get("cmd", [None])[0] == "git" and len(_e["cmd"]) > 1 and _e["cmd"][1] != "*":
            for _k in ("any", "all", "none"):
                for _g in _e.get(_k, []):
                    if _g.startswith("--") and not any(ch in _g for ch in "*?[="):
                        GIT_LONG.setdefault(_e["cmd"][1], set()).add(_g)
for _key, _vals in M["value_options"].items():
    if _key.startswith("git "):
        GIT_LONG.setdefault(_key.split()[1], set()).update(v for v in _vals if v.startswith("--"))
for _verb, _opts in (("push", ("--all", "--branches", "--mirror", "--tags", "--follow-tags", "--prune", "--delete",
                               "--force", "--force-with-lease", "--force-if-includes", "--no-verify", "--dry-run",
                               "--set-upstream", "--atomic", "--porcelain", "--quiet", "--verbose", "--progress",
                               "--signed", "--no-signed", "--thin", "--no-thin", "--recurse-submodules", "--ipv4",
                               "--ipv6", "--no-force-with-lease", "--no-force-if-includes")),
                     ("send-pack", ("--all", "--mirror", "--force", "--dry-run", "--atomic", "--remote",
                                    "--receive-pack", "--signed", "--stdin", "--thin", "--quiet", "--verbose",
                                    "--force-with-lease")),
                     ("pull", ("--ff-only", "--rebase", "--no-rebase", "--force")),
                     ("merge", ("--ff-only", "--no-verify", "--squash", "--abort")),
                     ("reset", ("--hard", "--merge", "--soft", "--mixed", "--keep")),
                     ("branch", ("--delete", "--force", "--set-upstream-to", "--move", "--copy"))):
    GIT_LONG.setdefault(_verb, set()).update(_opts)


def git_long(verb, tok):
    """The long option a git option word stands for: itself, or the one catalog option it is a prefix of (git
    takes a unique prefix). An ambiguous prefix stays as written: git refuses it, so nothing runs."""
    if not tok.startswith("--") or len(tok) < 3:
        return tok
    key, eq, val = tok.partition("=")
    opts = GIT_LONG.get(verb, ())
    if key in opts:
        return tok
    cands = [o for o in opts if o.startswith(key)]
    if len(cands) != 1:
        return tok
    return cands[0] + eq + val


IFS_RX = re.compile(r"\$\{?IFS\}?")
BRACE_RX = re.compile(r"\A([^{}]*)\{([^{}]*,[^{}]*)\}([^{}]*)\Z")
DYNAMIC_CH = "$`{}*?["


def expand_prog(toks, i):
    """The words a shell makes of the program word toks[i] (F2), or None when it is plain: `git${IFS}push` splits,
    `{git,push,-f}` brace-expands, `/usr/bin/gi[t]` globs against the files there."""
    t = toks[i]
    if IFS_RX.search(t):
        words = [w for w in IFS_RX.split(t) if w]
    elif BRACE_RX.match(t):
        m = BRACE_RX.match(t)
        words = [m.group(1) + x + m.group(3) for x in m.group(2).split(",")]
        words = [w for w in words if w]
    elif any(ch in os.path.basename(t) for ch in "*?[") and t not in ("[", "[["):
        words = sorted(tok_paths(t))[:16]
    else:
        return None
    return toks[:i] + words + toks[i + 1:] if words else None


def parse(toks, depth=0):
    env, i = [], 0
    while i < len(toks):
        t = toks[i]
        if ENV_RE.match(t):
            env.append(t)
            i += 1
            continue
        name = os.path.basename(t).lower()
        if name in PREFIX:
            i += 1
            vo = PREFIX_VALUE_OPTS.get(name, set())
            while i < len(toks) and (toks[i].startswith("-") or toks[i].isdigit()):
                i += 2 if toks[i] in vo else 1
            if name in DURATION_PREFIX and i < len(toks) and re.fullmatch(r"\d+(\.\d+)?[smhd]?", toks[i]):
                i += 1
            continue
        break
    if i >= len(toks):
        return {"env": env, "argv0": None, "raw0": None, "all": [], "sub": [], "gopts": []}
    if depth < 3:
        exp = expand_prog(toks, i)
        if exp is not None:
            return parse(exp, depth + 1)
    # A case-insensitive file system runs `GIT` and `/usr/bin/GH` (F2): the program is matched in lower case.
    argv0, raw0, rest = os.path.basename(toks[i]).lower(), toks[i], toks[i + 1:]
    g = M["global_options"].get(argv0, {"value": [], "flag": []})
    longv = [v for v in g["value"] if v.startswith("--")]
    gopts, j = [], 0
    while j < len(rest):
        t = rest[j]
        if t in g["value"]:
            gopts.append((t, rest[j + 1] if j + 1 < len(rest) else None))
            j += 2
        elif any(t.startswith(v + "=") for v in longv):
            gopts.append(tuple(t.split("=", 1)))
            j += 1
        elif t in g["flag"]:
            j += 1
        else:
            break
    sub = rest[j:]
    if argv0 == "git" and sub:
        sub = sub[:1] + [git_long(sub[0], t) for t in sub[1:]]
        rest = rest[:j] + sub
    if argv0 == "gh":
        clean, k = [], 0
        while k < len(sub):
            if sub[k] in g["value"]:
                gopts.append((sub[k], sub[k + 1] if k + 1 < len(sub) else None))
                k += 2
                continue
            if any(sub[k].startswith(v + "=") for v in longv):
                gopts.append(tuple(sub[k].split("=", 1)))
                k += 1
                continue
            if sub[k].startswith("-R") and len(sub[k]) > 2:
                # pflag's attached shorthand: -Racme/app and -R=acme/app are -R acme/app (Codex P1, round 2).
                v = sub[k][2:]
                gopts.append(("-R", v[1:] if v.startswith("=") and len(v) > 1 else v))
                k += 1
                continue
            if re.fullmatch(r"-[A-Za-z]+R.*", sub[k]):
                gopts.append(("-R", None))   # -dR x: a repository PG cannot pin (the cluster is kept)
            clean.append(sub[k])
            k += 1
        sub = clean
    if argv0 == "git" and sub[:1] == ["push"]:
        # -uf is -u -f: a cluster of git push's boolean short flags is split so a force cannot hide in it.
        out_ = []
        for t in sub:
            if re.fullmatch(r"-[ufnvqd46]{2,}", t):
                out_ += ["-" + c for c in t[1:]]
            else:
                out_.append(t)
        sub = out_
        rest = rest[:j] + sub
    # A program name still built at runtime ($X, ${X:-gh}, $(…), a glob that matched nothing here) cannot be read:
    # with no id it is UNCLASSIFIED (F2), whatever its words.
    dynamic = argv0 not in ("[", "[[") and any(ch in argv0 for ch in DYNAMIC_CH)
    return {"env": env, "argv0": argv0, "raw0": raw0, "all": rest, "sub": sub, "gopts": gopts, "dynamic": dynamic}


CONFIG_KEY_GLOB = re.compile(r"\A[A-Za-z*][A-Za-z0-9*-]*\.")


def gmatch(glob, tok):
    if fnmatch.fnmatchcase(tok, glob):
        return True
    # A git config key (core.hooksPath, remote.*.url, alias.*): git reads section and key in any case (F8).
    if CONFIG_KEY_GLOB.match(glob) and fnmatch.fnmatchcase(tok.lower(), glob.lower()):
        return True
    return glob.startswith("--") and not any(c in glob for c in "*?[") and tok.startswith(glob + "=")


def expand_default(globs, defaults):
    out = []
    for g in globs:
        out += [g.replace("{default}", d) for d in defaults] if "{default}" in g else [g]
    return out


def positionals(toks, vopts):
    out, k = [], 0
    while k < len(toks):
        t = toks[k]
        if t == "--":
            out += toks[k + 1:]
            break
        if t.startswith("-") and len(t) > 1:
            k += 2 if t in vopts else 1
            continue
        out.append(t)
        k += 1
    return out


def vopts_for(words):
    for n in range(len(words), 0, -1):
        key = " ".join(words[:n])
        if key in M["value_options"]:
            return set(M["value_options"][key])
    return set()


# The scripts whose real file PG also recognises through a link or a byte-identical copy (F1): the D6 writer and
# the installers that take --permission-level.
POLICY_SCRIPTS = {"plugin-config.sh": os.path.join(ROOT, "scripts", "plugin-config.sh"),
                  "setup.sh": os.path.join(ROOT, "scripts", "setup.sh"),
                  "scripts/setup.sh": os.path.join(ROOT, "scripts", "setup.sh"),
                  "install.sh": os.path.join(ROOT, "scripts", "install.sh"),
                  "scripts/install.sh": os.path.join(ROOT, "scripts", "install.sh"),
                  "permission-approved.sh": os.path.join(ROOT, "hooks", "permission-approved.sh")}
GLOB_CH = "*?["
_FILEID, _NAMES, _EXPAND = {}, {}, {}


def file_id(path):
    """(realpath, size, sha256) of a regular file, or None."""
    if path in _FILEID:
        return _FILEID[path]
    res = None
    try:
        rp = os.path.realpath(path)
        st = os.stat(rp)
        if stat.S_ISREG(st.st_mode):
            res = (rp, st.st_size, None)
    except OSError:
        res = None
    _FILEID[path] = res
    return res


def file_sha(path):
    fid = file_id(path)
    if not fid:
        return None
    if fid[2] is None:
        try:
            with open(fid[0], "rb") as f:
                fid = (fid[0], fid[1], hashlib.sha256(f.read()).hexdigest())
        except OSError:
            return None
        _FILEID[path] = fid
    return fid[2]


def same_file(path, real):
    """Is <path> the real script <real>: the same file (through any link), or a byte-identical copy?"""
    a, b = file_id(path), file_id(real)
    if not a or not b:
        return False
    if a[0] == b[0]:
        return True
    if a[1] != b[1] or a[1] > 4 * 1024 * 1024:
        return False
    h = file_sha(path)
    return h is not None and h == file_sha(real)


def tok_paths(tok):
    """The existing files a word names, relative to the command's directory: itself, or its glob expansion."""
    if tok in _EXPAND:
        return _EXPAND[tok]
    base = CTX["cwd"] if CTX.get("cwd") else (payload_cwd() or os.getcwd())
    t = os.path.expanduser(tok)
    path = t if os.path.isabs(t) else os.path.join(base, t)
    out = []
    if "$" not in tok and "`" not in tok:
        if any(ch in tok for ch in GLOB_CH):
            try:
                out = [x for x in itertools.islice(glob.iglob(path), 64) if os.path.isfile(x)]
            except (OSError, re.error, ValueError):
                out = []
        elif os.path.isfile(path):
            out = [path]
    _EXPAND[tok] = out
    return out


def literal_chars(pattern):
    return len(re.sub(r"\[[^]]*\]|[*?]", "", pattern))


def tok_names(tok, script):
    """Does the word <tok> name the catalog script <script> (a path suffix)? In any case (APFS runs
    PLUGIN-CONFIG.SH), through a glob a shell would expand to it, a link to it or, for POLICY_SCRIPTS, a
    byte-identical copy of the real file (F1)."""
    key = (tok, script)
    if key in _NAMES:
        return _NAMES[key]
    tl, sl = tok.lower(), script.lower()
    hit = tl == sl or tl.endswith("/" + sl)
    if not hit and any(ch in tok for ch in GLOB_CH):
        ts, ss = tl.split("/"), sl.split("/")
        n = min(len(ts), len(ss))
        hit = literal_chars(ts[-1]) >= 4 and all(fnmatch.fnmatchcase(ss[-1 - k], ts[-1 - k]) for k in range(n))
    if not hit and (any(ch in tok for ch in GLOB_CH) or script in POLICY_SCRIPTS):
        for path in tok_paths(tok):
            pl = path.lower()
            if pl == sl or pl.endswith("/" + sl) or (script in POLICY_SCRIPTS and same_file(path, POLICY_SCRIPTS[script])):
                hit = True
                break
    _NAMES[key] = hit
    return hit


def script_hit(p, script):
    """The words after <script> when the segment runs it: as the program, or as any argument of an interpreter
    (bash -o pipefail <script>, sh --rcfile f <script>, env -i /bin/bash <glob>): an interpreter's options and
    their values are skipped, and every later word is looked at too, so no option PG does not know can hide it."""
    if p["raw0"] is None:
        return None
    if tok_names(p["raw0"], script):
        return p["all"]
    if is_interp(p["argv0"]):
        for k, t in enumerate(p["all"]):
            if k > 0 and p["all"][k - 1] in INTERP_VALUE_OPTS:
                continue
            if tok_names(t, script):
                return p["all"][k + 1:]
    return None


# Read-only inspections that may name the writer without being policy.edit (F1): nothing they print is a
# runnable copy, provided no output is redirected or piped.
WRITER_INSPECT = {"ls", "stat", "file", "wc", "shellcheck", "diff", "cmp", "test", "["}
WRITER_INSPECT_GIT = {"status", "diff", "log", "add", "blame", "ls-files", "commit"}


def names_writer(s):
    """policy.edit for a segment that names scripts/plugin-config.sh (any case, a glob, a link or a copy of it)
    other than to run its read-only show/help or to inspect it (F1): cp/ln/mv/cat/install/... of the writer make a
    runnable copy, and an interpreter running it under an option PG does not know is the writer itself."""
    p = s["p"]
    words = ([p["raw0"]] if p["raw0"] else []) + p["all"]
    if not any(tok_names(t, "plugin-config.sh") or os.path.basename(t.lower()) == "plugin-config" for t in words):
        return False
    run = script_hit(p, "plugin-config.sh")
    if run is not None:
        pos = positionals(run, set())
        return not (pos and pos[0] in ("show", "help", "--help", "-h"))
    quiet = ">" not in CMD_TEXT and "|" not in CMD_TEXT
    if quiet and (p["argv0"] in WRITER_INSPECT or (p["argv0"] == "git" and p["sub"][:1] and
                                                    p["sub"][0] in WRITER_INSPECT_GIT)):
        return False
    return True


def entry_matches(e, p, defaults):
    if "script" in e:
        toks = script_hit(p, e["script"])
        if toks is None:
            return False
        posn = positionals(toks, set())
    else:
        cmd = e["cmd"]
        if cmd[0] != p["argv0"] or len(p["sub"]) < len(cmd) - 1:
            return False
        if not all(c == "*" or c == t for c, t in zip(cmd[1:], p["sub"])):
            return False
        toks = p["all"]
        posn = positionals(p["sub"][len(cmd) - 1:], vopts_for(cmd))
    if "any" in e and not any(gmatch(g, t) for g in e["any"] for t in toks):
        return False
    if "all" in e and not all(any(gmatch(g, t) for t in toks) for g in e["all"]):
        return False
    if "none" in e and any(gmatch(g, t) for g in e["none"] for t in toks):
        return False
    if "args" in e and not any(fnmatch.fnmatchcase(t, g) for g in expand_default(e["args"], defaults) for t in posn):
        return False
    if "args_none" in e and any(fnmatch.fnmatchcase(t, g) for g in expand_default(e["args_none"], defaults) for t in posn):
        return False
    if "first_arg_none" in e and posn and any(fnmatch.fnmatchcase(posn[0], g) for g in e["first_arg_none"]):
        return False
    if "min_args" in e and len(posn) < e["min_args"]:
        return False
    if "env_any" in e and not any(fnmatch.fnmatchcase(v, g) for g in e["env_any"] for v in p["env"]):
        return False
    return True


_RX = {}


def path_regex(pattern, defaults):
    key = (pattern, tuple(defaults))
    if key in _RX:
        return _RX[key]
    segs, out, i = pattern.split("/"), [], 0
    while i < len(segs):
        s = segs[i]
        if s == "{owner}" and i + 1 < len(segs) and segs[i + 1] == "{repo}":
            out.append(("/", r"(?:[^/]+/[^/]+|[^/]*\$[^/]*)"))
            i += 2
            continue
        if s == "**":
            out.append(("", r"(?:/.*)?" if out else r".*"))
        elif s == "{default}":
            out.append(("/", "(?:%s)" % "|".join(re.escape(d) for d in defaults)))
        elif s == "*" or re.fullmatch(r"\{[a-z_]+\}", s):
            out.append(("/", r"[^/]+"))
        else:
            out.append(("/", re.escape(s)))
        i += 1
    body = "".join((sep if n else "") + rx for n, (sep, rx) in enumerate(out))
    # GitHub's REST paths are matched in any case (F8): stricter than GitHub, never looser.
    _RX[key] = re.compile("^" + body + "/?$", re.I)
    return _RX[key]


def api_host(word):
    """Does a URL word aim at a GitHub API host (any case, with or without a scheme)?"""
    w = word.lower()
    return any(h in w for h in API_HOSTS)


def norm_path(path):
    p = path.strip().strip("\"'")
    if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", p):
        p = re.sub(r"^[A-Za-z][A-Za-z0-9+.-]*://[^/]*", "", p)
    else:
        # `http api.github.com/repos/...` (httpie, xh): a host with no scheme.
        first = p.split("/", 1)[0]
        if first.lower().split(":", 1)[0] in API_HOSTS or first.lower() in API_HOSTS:
            p = p[len(first):]
    p = re.sub(r"^/api/(v3|uploads)(?=/)", "", p, flags=re.I)
    p = re.sub(r"^/api/graphql$", "/graphql", p, flags=re.I)
    p = p.split("?", 1)[0].lstrip("/")
    return "graphql" if p.lower() == "graphql" else p


def rest_ids(method, path, kv, defaults):
    got = set()
    for a in ACTS:
        for e in a["equivalents"].get("rest", []):
            methods = e["method"] if isinstance(e["method"], list) else [e["method"]]
            if method not in methods or not path_regex(e["path"], defaults).match(path):
                continue
            if "fields_all" in e and not all(any(fnmatch.fnmatchcase(x, g) for x in kv) for g in e["fields_all"]):
                continue
            if "fields_none" in e and any(fnmatch.fnmatchcase(x, g) for x in kv for g in e["fields_none"]):
                continue
            got.add(a["id"])
    return got


def mutation_names(doc):
    names = []
    for m in re.finditer(r"\bmutation\b[^{]*\{", doc):
        depth, paren, k = 1, 0, m.end()
        while k < len(doc) and depth:
            ch = doc[k]
            if ch == "(":
                paren += 1
            elif ch == ")":
                paren -= 1
            elif ch == "{" and not paren:
                depth += 1
            elif ch == "}" and not paren:
                depth -= 1
            elif depth == 1 and not paren and (ch.isalpha() or ch == "_"):
                w = re.match(r"[A-Za-z_]\w*", doc[k:]).group(0)
                after = doc[k + len(w):].lstrip()
                if after[:1] in ("(", "{"):
                    names.append(w)
                k += len(w)
                continue
            k += 1
    return names


GRAPHQL = {}
for _a in ACTS:
    for _g in _a["equivalents"].get("graphql", []):
        GRAPHQL.setdefault(_g, set()).add(_a["id"])


def graphql_ids(doc, file_sourced):
    """(ids, unclassified). A document PG cannot read (a file, a variable) is UNCLASSIFIED."""
    if file_sourced or "{" not in doc:
        return set(), True
    names = mutation_names(doc)
    if not names:
        return ({"repo.read"}, False) if "mutation" not in doc else (set(), True)
    got = set()
    for n in names:
        got |= GRAPHQL.get(n, set())
    return got, any(n not in GRAPHQL for n in names)


# gh api's value shorthands; -i (--include) is its one boolean shorthand, so -iXPOST is -i -X POST.
GH_API_SHORT = {"X": "--method", "f": "--raw-field", "F": "--field", "H": "--header", "q": "--jq", "t": "--template",
                "p": "--preview"}


def gh_api_words(toks):
    """(options, positionals) of `gh api`'s words, read as pflag reads them (Codex P1, round 2): each option is
    (long name, value) whether attached (-ftag_name=v1, -XPOST, -f=k=v, --field=k=v, --input=f), separate, or
    inside a cluster (-iXPOST); the value is None for a flag, or for a value option with no word left."""
    vopts = set(M["value_options"]["gh api"])
    opts, pos, k = [], [], 0
    while k < len(toks):
        t, nxt = toks[k], (toks[k + 1] if k + 1 < len(toks) else None)
        k += 1
        if t == "--":
            pos += toks[k:]
            break
        if t.startswith("--"):
            key, eq, val = t.partition("=")
            if not eq and key in vopts:
                val, k = nxt, k + 1
            opts.append((key, val if eq or key in vopts else None))
        elif t.startswith("-") and len(t) > 1:
            for j in range(1, len(t)):
                if t[j] not in GH_API_SHORT:
                    continue   # -i, or a shorthand gh refuses (then nothing runs)
                val = t[j + 1:]
                val = val[1:] if val.startswith("=") and len(val) > 1 else val
                if not val:
                    val, k = nxt, k + 1
                opts.append((GH_API_SHORT[t[j]], val))
                break
        else:
            pos.append(t)
    return opts, pos


def gh_api(sub):
    """(method, paths, fields, has_input): -X/--method, else POST when a request parameter (-f/-F/--field/
    --raw-field) or --input is given ("adding request parameters will automatically switch the request method to
    POST", gh api --help), else GET. Every positional is a path: gh takes one and refuses more, so classifying
    each can only be stricter."""
    opts, paths = gh_api_words(sub[1:])
    method, fields, has_input = None, [], False
    for key, val in opts:
        if key == "--method":
            method = val.upper() if val else method
        elif key in ("--field", "--raw-field") and val is not None:
            fields.append(("-F" if key == "--field" else "-f", val))
        elif key == "--input":
            has_input = True
    if method is None:
        method = "POST" if fields or has_input else "GET"
    return method, paths, fields, has_input


HTTP_METHODS = {"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"}
DATA_LONG = {"--data", "--data-raw", "--data-binary", "--data-urlencode", "--data-ascii", "--form", "--form-string",
             "--json", "--post-data", "--body-data"}
UPLOAD_LONG = {"--upload-file", "--post-file", "--body-file"}
# curl's short options that take a value: in a cluster (-sSd'{..}') the rest of the word, else the next word, is it.
CURL_SHORT_VALUE = set("AbcCdDeEFHKmoPQrtTuUwxXyYz")
# wget's (getopt): -i reads URLs from a file, -e runs a .wgetrc command.
WGET_SHORT_VALUE = set("aABCDeiIlnoOPQRtTUwXY")
HTTPIE_ITEM = re.compile(r"\A([^=:@]+)(:=@|:=|==|=@|=|@|:)")
HTTPIE_DATA = {"=", ":=", "@", "=@", ":=@"}


def wget_execute(cmd, call):
    """A wget -e/--execute .wgetrc command (names in any case, '_' and '-' ignored): method, post_data, body_data,
    post_file and body_file act as their options; input names a URL file PG cannot read."""
    key, eq, val = cmd.partition("=")
    key = re.sub(r"[-_\s]", "", key).lower()
    val = val.strip()
    if not eq:
        return
    if key == "method":
        call["methods"].append(val.upper())
    elif key in ("postdata", "bodydata"):
        call["data"].append(val)
    elif key in ("postfile", "bodyfile"):
        call["data"].append("@" + val)
    elif key == "input":
        call["unread"] = True


def http_call(p):
    """(methods, paths, kv, data, unread) of an HTTP client call, or None when it aims at no GitHub API host and
    reads nothing PG cannot see. A body in any form (-d/--data*/-F/--form/--json/-T/--upload-file, attached or
    separate, in a cluster, curl's --expand-<option>) implies POST (PUT for an upload) unless -X/--request says
    otherwise (Codex P1); httpie and xh take the method as their first word and imply POST from a data item (F8).
    curl and wget send every URL they are given (curl's --url too), so every GitHub API URL is a path to classify
    (Codex P1-b, round 2); a curl --next group may carry its own method, so then every method named, and the
    implied ones, apply to every URL. unread: the call takes URLs or options from a file PG cannot read (curl
    -K/--config, wget -i/--input-file, --config, -e input=) or from a curl --expand-url variable."""
    prog = p["argv0"]
    toks, k, get, nxt_group, pos = p["all"], 0, False, False, []
    call = {"methods": [], "data": [], "urls": [], "unread": False}
    data, upload = call["data"], False
    vopts = set(M["value_options"].get(prog, []))
    while k < len(toks):
        t = toks[k]
        nxt = toks[k + 1] if k + 1 < len(toks) else ""
        if prog == "curl" and t.startswith("--expand-") and len(t) > 9:
            t = "--" + t[9:]   # curl 8.3+: --expand-data is --data with {{variables}} expanded
            if t.partition("=")[0] == "--url" and "{{" in (t.partition("=")[2] or nxt):
                call["unread"] = True
        if t in ("-X", "--request") or (prog == "wget" and t == "--method"):
            call["methods"].append(nxt.upper())
            k += 2
            continue
        if t.startswith("--method=") or t.startswith("--request="):
            call["methods"].append(t.split("=", 1)[1].upper())
            k += 1
            continue
        if t in ("-G", "--get") and prog == "curl":
            get, k = True, k + 1
            continue
        if t in ("-:", "--next") and prog == "curl":
            nxt_group, k = True, k + 1
            continue
        if t.startswith("--"):
            key, eq, val = t.partition("=")
            val = val if eq else nxt
            if key in DATA_LONG:
                data.append(val)
            elif key in UPLOAD_LONG:
                upload = upload or key == "--upload-file"
                data.append("@" + val)
            elif key == "--url" and prog == "curl":
                call["urls"].append(val)
            elif key == "--config" or (key == "--input-file" and prog == "wget"):
                call["unread"] = True
            elif key == "--execute" and prog == "wget":
                wget_execute(val, call)
            elif key not in vopts:
                eq = "flag"   # a flag, or an option PG does not know: its own word only
            k += 1 if eq else 2
            continue
        if prog in ("curl", "wget") and len(t) > 1 and t[0] == "-":
            j, took_next = 1, False
            while j < len(t):
                ch = t[j]
                if ch in (CURL_SHORT_VALUE if prog == "curl" else WGET_SHORT_VALUE):
                    val = t[j + 1:]
                    if not val:
                        val, took_next = nxt, True
                    if prog == "wget":
                        if ch == "i":
                            call["unread"] = True
                        elif ch == "e":
                            wget_execute(val, call)
                    elif ch == "X":
                        call["methods"].append(val.upper())
                    elif ch in "dF":
                        data.append(val)
                    elif ch == "T":
                        upload = True
                        data.append("@" + val)
                    elif ch == "K":
                        call["unread"] = True
                    break
                if ch == "G" and prog == "curl":
                    get = True
                if ch == ":" and prog == "curl":
                    nxt_group = True
                j += 1
            k += 2 if took_next else 1
            continue
        if t.startswith("-") and len(t) > 1:
            k += 2 if t in vopts else 1
            continue
        pos.append(t)
        k += 1
    if prog in HTTPIE and pos and pos[0].upper() in HTTP_METHODS and not call["methods"]:
        call["methods"].append(pos.pop(0).upper())
    for n, t in enumerate(pos):
        if api_host(t):
            call["urls"].append(t)
            if prog in HTTPIE:
                # httpie/xh take one URL; its request items key=v and key:=json are a body, key@file a form file.
                data += [it for it in pos[n + 1:] if HTTPIE_ITEM.match(it) and HTTPIE_ITEM.match(it).group(2) in HTTPIE_DATA]
                break
    urls = [u for u in call["urls"] if api_host(u)]
    if not urls and not call["unread"]:
        return None
    implied = "PUT" if upload else ("POST" if data and not get else "GET")
    if nxt_group:
        methods = set(call["methods"]) | {"GET"} | ({"POST"} if data else set()) | ({"PUT"} if upload else set())
    else:
        methods = {call["methods"][-1]} if call["methods"] else {implied}
    kv = []
    for d in data:
        m = HTTPIE_ITEM.match(d) if prog in HTTPIE else None
        if m and m.group(2) in ("=", ":="):
            kv.append("%s=%s" % (m.group(1), d[m.end():]))
    for d in data:
        try:
            body = json.loads(d)
        except ValueError:
            continue
        if isinstance(body, dict):
            kv += ["%s=%s" % (k2, v if isinstance(v, str) else json.dumps(v)) for k2, v in body.items()]
    return sorted(methods), [norm_path(u) for u in urls], kv, data, call["unread"]


# Commands whose words are text or file names, never a program they run: a `gh` among their words is prose.
INERT = {"echo", "printf", "cat", "ls", "grep", "egrep", "fgrep", "rg", "head", "tail", "wc", "sort", "uniq", "cut",
         "tr", "diff", "cmp", "stat", "file", "less", "more", "jq", "yq", "which", "type", "test", "[", "true",
         "false", "pwd", "basename", "dirname", "realpath", "readlink", "date", "sleep", "mkdir", "touch", "column",
         "nl", "seq", "cd", "man", "shellcheck"}
GH_WORD = re.compile(r"(?<![A-Za-z0-9_])gh(?![A-Za-z0-9_-])", re.I)
MARKERS_L = [mk.lower() for mk in MARKERS if mk != "gh"]


def has_marker(text, argv0=None):
    """A D1 mutation marker, in any case (F8: `API.GITHUB.COM` reaches the same host). `gh` (the ADR's `gh `
    marker) counts as a word anywhere in a segment that is not an inert command (F3: `$(which gh) pr merge`,
    `${GH:-gh} pr merge`), and as prose in `echo gh ...`."""
    tl = text.lower()
    if any(mk in tl for mk in MARKERS_L) or any(rx.search(text) for rx in MARKER_RX):
        return True
    return argv0 not in INERT and bool(GH_WORD.search(text))


# --------------------------------------------------------------- local facts (git, offline, deadline)

_GIT = {}


def git(d, *args):
    key = (d,) + args
    if key in _GIT:
        return _GIT[key]
    res = None
    if d and left() > 1.5:
        env = dict(os.environ)
        env.update({"GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"})
        try:
            r = subprocess.run(["git", "-C", d] + list(args), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               timeout=min(3.0, max(0.5, left() - 1.0)), env=env)
            res = (r.returncode, r.stdout.decode("utf-8", "replace"))
        except (OSError, subprocess.SubprocessError):
            res = None
    _GIT[key] = res
    return res


def git_out(d, *args):
    r = git(d, *args)
    return r[1].strip() if r and r[0] == 0 else None


def git_rc(d, *args):
    r = git(d, *args)
    return r[0] if r else None


# --------------------------------------------------------------- GitHub facts (lib/permission-conditions.sh)

NET = {"t0": None}
NOTES = []         # what a lookup found, for the reason (counts only: names are PR-author text)
_LIB = {}


def net_left():
    used = 0.0 if NET["t0"] is None else time.time() - NET["t0"]
    return min(NET_BUDGET - used, left() - 1.0)


def conditions_lib(cmd, *args):
    """The one line lib/permission-conditions.sh prints, or None: no budget left, no lib, a non-zero
    exit or the deadline. The lib bounds itself (timeout/gtimeout, else a watchdog); this is the backstop,
    and it kills the lib's whole process group so a stray gh cannot keep the pipe open."""
    key = (cmd,) + args
    if key in _LIB:
        return _LIB[key]
    res, budget = None, net_left()
    if budget >= 0.3 and os.path.isfile(COND_LIB):
        if NET["t0"] is None:
            NET["t0"] = time.time()
        argv = ["bash", COND_LIB, cmd, "--deadline", "%.1f" % budget] + list(args)
        try:
            pr = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                                  start_new_session=True)
        except OSError:
            pr = None
        if pr is not None:
            try:
                out, _ = pr.communicate(timeout=budget + 1.0)
                if pr.returncode == 0:
                    res = out.decode("utf-8", "replace").strip().split("\n")[0][:300]
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(pr.pid, signal.SIGKILL)
                except OSError:
                    pass
                try:
                    pr.communicate(timeout=1.0)
                except (OSError, subprocess.SubprocessError):
                    pass
    _LIB[key] = res
    return res


def remote_default_branch(d, remote):
    """GitHub's default branch for the repository <remote>'s push URL names, or None."""
    out = conditions_lib("default-branch", d, remote)
    if out and safe(out) and not out.startswith("refs/"):
        return out
    note = "the default branch of `%s` could not be read from GitHub either" % remote
    if note not in NOTES:
        NOTES.append(note)
    return None


SAFE_REF = re.compile(r"\A[A-Za-z0-9._/@+-]{1,200}\Z")


def safe(ref):
    return bool(ref) and SAFE_REF.match(ref) is not None and ".." not in ref and not ref.startswith("-")


def default_branch(d, remote):
    if not safe(remote) or "/" in remote:
        return None
    out = git_out(d, "symbolic-ref", "--quiet", "refs/remotes/%s/HEAD" % remote)
    pre = "refs/remotes/%s/" % remote
    if out and out.startswith(pre):
        return out[len(pre):]
    # No local answer: ask GitHub, under the call's network deadline (an error leaves it unknown).
    return remote_default_branch(d, remote) if d else None


def defaults_set(d, remote):
    """{D, main, master} when D resolves, else None."""
    dflt = default_branch(d, remote) if d else None
    return sorted({dflt, "main", "master"}) if dflt else None


def origin_slug(d):
    url = git_out(d, "config", "--get", "remote.origin.url") if d else None
    if not url:
        return None
    m = re.match(r"^(?:[a-z+]+://)?(?:[^@/]+@)?([^/:]+)[:/]+([^/]+)/([^/]+?)(?:\.git)?/?$", url.strip())
    return ("%s/%s" % (m.group(2), m.group(3))).lower() if m else None


def head_branch(d):
    return git_out(d, "symbolic-ref", "--quiet", "--short", "HEAD")


def norm_remote(url, d=None):
    """host[:port]/owner/name of a git remote URL (scheme, user, .git and case dropped), or the realpath of a
    local repository path; None when it is neither."""
    u = (url or "").strip()
    if not u or "$" in u or "`" in u:
        return None
    m = re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://(?:[^@/]+@)?([^/]+)/+(.+?)(?:\.git)?/*$", u)
    if not m:
        m = re.match(r"^(?:[^@/]+@)?([^/:]+):(?!/)(.+?)(?:\.git)?/*$", u)
    if m:
        host = m.group(1).lower()
        if host.endswith(":443") or host.endswith(":22"):
            host = host.rsplit(":", 1)[0]
        return "%s/%s" % (host, m.group(2).lower())
    base = d or (CTX["cwd"] if CTX.get("cwd") else None)
    if not base:
        return None
    return "file:" + os.path.realpath(os.path.join(base, os.path.expanduser(u)))


def remote_push_urls(d, name):
    """The normalised push URLs of a named remote (pushurl, else url, rewrites applied), or None."""
    out = git_out(d, "remote", "get-url", "--push", "--all", name)
    if not out:
        return None
    urls = [norm_remote(x, d) for x in out.splitlines() if x.strip()]
    return None if not urls or any(x is None for x in urls) else set(urls)


def push_foreign(info):
    """push_remote_not_origin for a git push (F9): False when every push URL of the push remote is one of origin's
    push URLs, True when one is not, None when PG cannot tell. Only origin's URL is the repository the user
    cloned; a branch push to any other remote, named or a URL, is a push of local commits elsewhere."""
    d, rem = info["d"], info["remote"]
    if not d or not rem:
        return None
    if rem == "origin":
        return False
    origin = remote_push_urls(d, "origin")
    if not origin:
        return None
    if info["remote_named"]:
        theirs = remote_push_urls(d, rem)
    else:
        x = norm_remote(git_out(d, "ls-remote", "--get-url", rem) or rem, d)
        theirs = {x} if x else None
    if not theirs:
        return None
    return not theirs <= origin


def api_foreign(owner_repo):
    """push_remote_not_origin for an API branch write: is <owner>/<repo> another repository than origin's?"""
    d = CTX["cwd"] if CTX["ok"] else None
    if not d or not owner_repo or "$" in owner_repo:
        return None
    slug = origin_slug(d)
    return None if not slug else slug != owner_repo.lower()


def has_ref(d, ref):
    """True / False (git says missing) / None (no repository, an error, the deadline)."""
    rc = git_rc(d, "show-ref", "--verify", "--quiet", ref)
    return {0: True, 1: False}.get(rc)


def clean_tree(d):
    out = git(d, "status", "--porcelain", "--untracked-files=normal")
    if not out or out[0] != 0:
        return None
    return out[1].strip() == ""


def unpushed(d, rev="HEAD", base=None):
    """True when <rev> (minus <base>) holds commits no remote ref contains; None when unknown."""
    args = ["rev-list", "--max-count=1", rev, "--not", "--remotes"]
    if base:
        args = ["rev-list", "--max-count=1", "%s..%s" % (base, rev), "--not", "--remotes"]
    out = git(d, *args)
    if not out or out[0] != 0:
        return None
    return out[1].strip() != ""


# --------------------------------------------------------------- the command's context

def payload_cwd():
    c = PAY.get("cwd")
    if not isinstance(c, str) or not c:
        roots = PAY.get("workspace_roots")
        c = roots[0] if isinstance(roots, list) and roots and isinstance(roots[0], str) else ""
    return os.path.realpath(c) if c and os.path.isabs(c) and os.path.isdir(c) else None


CTX = {"ok": True, "cwd": payload_cwd(), "why": []}
if CTX["cwd"] is None:
    CTX["ok"] = False
    CTX["why"].append("the payload names no usable cwd")
for s in SEGS:
    s["p"] = parse(s["toks"])
_cds = [s for s in SEGS if s["p"]["argv0"] in ("cd", "pushd", "popd")]
for s in SEGS:
    p = s["p"]
    if p["argv0"] in ("export", "declare", "typeset", "readonly", "unset", "source", ".", "set", "eval", "alias"):
        CTX["ok"] = False
        CTX["why"].append("`%s` can change the environment the command runs in" % p["argv0"])
    if p["argv0"] is None and any(TARGET_ENV.match(v) for v in p["env"]):
        CTX["ok"] = False
        CTX["why"].append("a bare assignment changes the git/gh target")
if _cds and CTX["ok"]:
    first = _cds[0]
    lead = re.match(r"^\s*cd\s+(?:\"[^\"]*\"|'[^']*'|[^\s;&|()<>]+)\s*&&", CMD_TEXT)
    target = first["p"]["all"][0] if first["p"]["all"] else ""
    if len(_cds) == 1 and first is SEGS[0] and not first["nested"] and lead and first["p"]["argv0"] == "cd" \
            and len(first["p"]["all"]) == 1 and target and not re.search(r"[$`*?]", target) and target != "-":
        nd = os.path.realpath(os.path.join(CTX["cwd"], os.path.expanduser(target)))
        if os.path.isdir(nd):
            CTX["cwd"] = nd
        else:
            CTX["ok"] = False
            CTX["why"].append("the leading cd names no directory")
    else:
        CTX["ok"] = False
        CTX["why"].append("the command changes directory in a way PG does not follow")


def seg_dir(p):
    """The repository directory a git segment runs in, or None when it cannot be pinned."""
    if not CTX["ok"]:
        return None
    if any(TARGET_ENV.match(v) for v in p["env"]):
        return None
    d = CTX["cwd"]
    for k, v in p["gopts"]:
        if p["argv0"] != "git":
            continue
        if k == "-C":
            if not v or re.search(r"[$`*?]", v):
                return None
            d = os.path.realpath(os.path.join(d, os.path.expanduser(v)))
        elif k in ("-c", "--git-dir", "--work-tree", "--namespace", "--config-env", "--exec-path"):
            return None
    return d if d and os.path.isdir(d) else None


# --------------------------------------------------------------- git push

PUSH_VOPTS = set(M["value_options"]["git push"])
# The idioms that name the current branch: PG reads them as HEAD instead of an unresolvable word.
CURRENT_BRANCH_SUBST = re.compile(r"^(\$\(|`)\s*git\s+(branch\s+--show-current|rev-parse\s+--abbrev-ref\s+HEAD|"
                                  r"symbolic-ref\s+(-q\s+|--quiet\s+)?--short\s+(-q\s+|--quiet\s+)?HEAD)\s*(\)|`)$")
URLISH = re.compile(r"^([a-z+]+://|[^/]*@[^/]*:|/|\.\.?/|~)")


def push_info(p, d):
    toks, pos, flags, k = p["sub"][1:], [], set(), 0
    while k < len(toks):
        t = toks[k]
        if t == "--":
            pos += toks[k + 1:]
            break
        if t.startswith("-") and len(t) > 1:
            flags.add(t.split("=", 1)[0])
            k += 2 if t in PUSH_VOPTS else 1
            continue
        pos.append(t)
        k += 1
    info = {"flags": flags, "delete": bool(flags & {"--delete", "-d"}),
            "broad": bool(flags & {"--all", "--branches", "--mirror", "--tags", "--follow-tags", "--prune"}),
            "remote": pos[0] if pos else None, "specs": pos[1:], "d": d}
    cur = head_branch(d) if d else None
    if info["remote"] is None and d:
        info["remote"] = (git_out(d, "config", "--get", "branch.%s.pushRemote" % cur) if cur else None) or \
            git_out(d, "config", "--get", "remote.pushDefault") or \
            (git_out(d, "config", "--get", "branch.%s.remote" % cur) if cur else None) or "origin"
    rem = info["remote"]
    info["remote_named"] = bool(rem) and not URLISH.match(rem) and safe(rem) and "/" not in rem
    dsts = []  # (src, dst) with dst a short branch/tag name, "refs/tags/x", or None when unresolvable
    if info["delete"]:
        dsts = [("", s) for s in info["specs"]]
    elif not info["specs"]:
        mode = git_out(d, "config", "--get", "push.default") if d else None
        configured = git_out(d, "config", "--get-all", "remote.%s.push" % rem) if d and info["remote_named"] else None
        if configured or mode not in (None, "simple", "current") or not cur:
            dsts = [(None, None)]
        else:
            dsts = [("HEAD", cur)]
    else:
        for spec in info["specs"]:
            s = spec[1:] if spec.startswith("+") else spec
            if ":" in s:
                src, dst = s.split(":", 1)
            else:
                src, dst = s, s
            if dst == "HEAD" or (":" not in s and s == "HEAD") or CURRENT_BRANCH_SUBST.match(dst):
                dst = cur
            if CURRENT_BRANCH_SUBST.match(src):
                src = "HEAD"
            if dst is not None and (not dst or re.search(r"[$`*?]", dst)):
                dst = None
            dsts.append((src, dst))
    info["dsts"] = dsts
    return info


def short(dst):
    if dst is None:
        return None
    if dst.startswith("refs/heads/"):
        return dst[len("refs/heads/"):]
    if dst.startswith("refs/"):
        return None
    return dst


def push_default_branch(info):
    if info["broad"] or not info["remote_named"]:
        return None
    names = defaults_set(info["d"], info["remote"])
    if names is None:
        return None
    vals = [short(dst) for _, dst in info["dsts"] if not (dst or "").startswith("refs/tags/")]
    if any(v in names for v in vals if v):
        return True
    return None if any(v is None for v in vals) else False


def is_tag(d, name):
    if name.startswith("refs/tags/"):
        return True
    if name.startswith("refs/heads/") or name == "HEAD":
        return False
    if name.startswith("refs/"):
        return None
    tag, branch = has_ref(d, "refs/tags/" + name), has_ref(d, "refs/heads/" + name)
    if tag is None or branch is None:
        return None
    if tag and branch:
        return None
    return tag


def push_tag_ref(info):
    d = info["d"]
    if info["flags"] & {"--tags", "--follow-tags"}:
        return True
    if info["broad"] or not d:
        return None
    seen_none = False
    for src, dst in info["dsts"]:
        if dst is None and src is None:
            return None
        if info["delete"] or src == "":
            if dst is None:
                return None
            if dst.startswith("refs/tags/"):
                return True
            if dst.startswith("refs/heads/"):
                continue
            remote_branch = has_ref(d, "refs/remotes/%s/%s" % (info["remote"], dst)) if info["remote_named"] else None
            local_tag = has_ref(d, "refs/tags/" + dst)
            if local_tag:
                return True
            if remote_branch:
                continue
            seen_none = True
            continue
        if (dst or "").startswith("refs/tags/"):
            return True
        if (dst or "").startswith("refs/heads/"):
            continue
        t = is_tag(d, src) if src else None
        if t:
            return True
        if t is None:
            seen_none = True
    return None if seen_none else False


def push_unmerged(info):
    gone = [(src, dst) for src, dst in info["dsts"] if info["delete"] or src == ""]
    if not gone or not info["remote_named"] or not info["d"]:
        return None
    dflt = default_branch(info["d"], info["remote"])
    if not dflt:
        return None
    for _, dst in gone:
        b = short(dst)
        if not b or not safe(b):
            return None
        ref = "refs/remotes/%s/%s" % (info["remote"], b)
        if not has_ref(info["d"], ref):
            return None
        if unpushed_vs(info["d"], ref, "refs/remotes/%s/%s" % (info["remote"], dflt)) is not False:
            return None
    return False


def unpushed_vs(d, ref, base):
    out = git(d, "rev-list", "--max-count=1", ref, "--not", base)
    if not out or out[0] != 0:
        return None
    return out[1].strip() != ""


# --------------------------------------------------------------- conditions per hit

WORKFLOW_PATHS = [".github/workflows/*", ".github/actions/*", "CODEOWNERS", ".github/CODEOWNERS", "docs/CODEOWNERS",
                  ".tamirs-superpowers/*", ".husky/*", ".githooks/*", "hooks/*", "core/permissions/*"]


def protected_paths(paths):
    if not paths or any(not isinstance(x, str) or not x for x in paths):
        return None
    for x in paths:
        x = x.lstrip("/")
        if any(fnmatch.fnmatchcase(x, g) for g in WORKFLOW_PATHS):
            return True
    return False


def remote_branch_default(owner_repo, branch):
    """default_branch for a GitHub API or MCP write naming owner/repo and a branch."""
    d = CTX["cwd"] if CTX["ok"] else None
    if not d or not owner_repo or not branch or "$" in owner_repo or "$" in branch:
        return None
    slug = origin_slug(d)
    if not slug or slug != owner_repo.lower():
        return None
    names = defaults_set(d, "origin")
    return None if names is None else branch in names


MERGE_VOPTS = {"-t", "--subject", "-b", "--body", "-F", "--body-file", "-A", "--author-email", "--match-head-commit"}
REPO_ARG = re.compile(r"\A[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\Z")
PR_URL = re.compile(r"\Ahttps://[A-Za-z0-9.-]+/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+/?\Z")


def required_checks(p):
    """required_check_failing_or_pending for `gh pr merge … --admin` (safety invariant 2), from
    gh pr checks --required on the same PR, in the same directory, against the same -R repo.
    True / False / None (anything PG cannot pin or read)."""
    if not CTX["ok"] or p["argv0"] != "gh" or p["sub"][:2] != ["pr", "merge"]:
        return None
    if any(TARGET_ENV.match(v) for v in p["env"]):
        return None
    repo = None
    for k, v in p["gopts"]:
        if k == "--hostname" or (k in ("-R", "--repo") and (not v or not REPO_ARG.match(v) or repo not in (None, v))):
            return None
        if k in ("-R", "--repo"):
            repo = v
    pos = positionals(p["sub"][2:], MERGE_VOPTS)
    if len(pos) > 1:
        return None
    if pos and not (pos[0].isdigit() or PR_URL.match(pos[0]) or safe(pos[0])):
        return None
    sel = pos[0] if pos else "-"
    out = conditions_lib("required-checks", CTX["cwd"], sel, repo or "-")
    word, _, summary = (out or "unknown the lookup did not answer").partition(" ")
    what = "PR %s%s" % (sel if sel != "-" else "of the current branch", (" in %s" % repo) if repo else "")
    note = "required checks on %s: %s (gh pr checks --required)" % (what, summary or word)
    if note not in NOTES:
        NOTES.append(note)
    return {"true": True, "false": False}.get(word)


def establish(name, hit):
    p, kind = hit.get("p"), hit["kind"]
    if name == "required_check_failing_or_pending":
        return required_checks(p) if kind == "argv" and p else None
    if kind == "mcp":
        args = hit["args"]
        if name == "workflow_hook_or_policy_path":
            if "files" in args:
                f = args.get("files")
                return protected_paths([x.get("path") if isinstance(x, dict) else None for x in f]) \
                    if isinstance(f, list) else None
            return protected_paths([args.get("path")]) if "path" in args else None
        if name == "default_branch":
            if "owner" in args and "repo" in args and "branch" in args:
                return remote_branch_default("%s/%s" % (args["owner"], args["repo"]), args["branch"])
            return None
        if name == "push_remote_not_origin":
            o, r = args.get("owner"), args.get("repo")
            return api_foreign("%s/%s" % (o, r)) if isinstance(o, str) and isinstance(r, str) else None
        if name == "tag_ref" and hit["tool"] == "create_branch":
            return False
        return None
    if kind == "rest":
        method, path, fields = hit["rest"]
        m = re.match(r"^repos/([^/]+/[^/]+)/(.*)$", path, re.I)
        if not m:
            return None
        repo, tail = m.group(1), m.group(2)
        kv = dict(f.split("=", 1) for f in fields if "=" in f)
        if name == "push_remote_not_origin":
            return api_foreign(repo)
        if name == "workflow_hook_or_policy_path" and tail.lower().startswith("contents/"):
            return protected_paths([tail[len("contents/"):]])
        branch = None
        if tail.startswith("git/refs/heads/"):
            branch = tail[len("git/refs/heads/"):]
        elif kv.get("ref", "").startswith("refs/heads/"):
            branch = kv["ref"][len("refs/heads/"):]
        elif "branch" in kv:
            branch = kv["branch"]
        if name == "default_branch":
            return remote_branch_default(repo, branch)
        if name == "tag_ref":
            if tail.startswith("git/refs/heads/") or kv.get("ref", "").startswith("refs/heads/"):
                return False
            return None
        return None
    if kind != "argv" or p["argv0"] != "git":
        return None
    d = seg_dir(p)
    if d is None:
        return None
    sub = p["sub"]
    verb = sub[0] if sub else ""
    if verb == "push":
        info = hit.setdefault("push", push_info(p, d))
        if name == "default_branch":
            return push_default_branch(info)
        if name == "tag_ref":
            return push_tag_ref(info)
        if name == "unmerged_commits":
            return push_unmerged(info)
        if name == "push_remote_not_origin":
            return push_foreign(info)
        return None
    if name == "uncommitted_changes":
        c = clean_tree(d)
        return None if c is None else not c
    if name == "drops_unpushed_commits":
        if verb in ("clean", "checkout", "restore", "switch"):
            return False
        if verb == "stash":
            out = git(d, "stash", "list")
            return None if not out or out[0] != 0 else out[1].strip() != ""
        if verb == "reset":
            pos = positionals(sub[1:], set())
            target = pos[0] if pos else "HEAD"
            if not safe(target.replace("~", "-").replace("^", "-")):
                return None
            sha = git_out(d, "rev-parse", "--verify", "--quiet", target + "^{commit}")
            return None if not sha else unpushed(d, "HEAD", sha)
        return None
    if name == "discards_work":
        if verb in ("pull", "merge") and "--ff-only" in sub:
            return False
        if verb == "reset":
            c, u = clean_tree(d), unpushed(d)
            if c is None or u is None:
                return None
            return (not c) or u
        if verb == "worktree" and sub[1:2] == ["remove"]:
            pos = positionals(sub[2:], set())
            if len(pos) != 1 or re.search(r"[$`*?]", pos[0]):
                return None
            wt = os.path.realpath(os.path.join(d, os.path.expanduser(pos[0])))
            if not os.path.isdir(wt):
                return None
            c, u = clean_tree(wt), unpushed(wt)
            if c is None or u is None:
                return None
            return (not c) or u
        return None
    if name == "unmerged_no_remote_copy" and verb == "branch":
        names = positionals(sub[1:], set(M["value_options"]["git branch"]))
        if not names:
            return None
        for b in names:
            if not safe(b) or not has_ref(d, "refs/heads/" + b):
                return None
            u = unpushed(d, "refs/heads/" + b)
            if u is None:
                return None
            if u:
                return True
        return False
    return None


def cond_names(aid, depth=0):
    a = BYID.get(aid)
    names = []
    if not a or depth > 4:
        return names
    for r in a.get("raises") or []:
        names.append(r["when"])
        if r.get("becomes"):
            names += cond_names(r["becomes"], depth + 1)
    for dn in a.get("denies") or []:
        names.append(dn["when"])
    if a.get("unattended_precondition"):
        names.append(a["unattended_precondition"])
    out = []
    for n in names:
        if n not in out:
            out.append(n)
    return out


# --------------------------------------------------------------- classify

HITS = []          # {"id", "kind", "p"/"args", "seg", ...}
UNCL_FROM = []     # texts that made the call UNCLASSIFIED
PG_DENY = []       # (id, reason) forms PG denies outright
STAMPS = []        # call-stamp tokens
CONFIRMS = []      # nonces of plugin-config.sh confirm <nonce>


def seg_text(toks):
    t = " ".join(toks)
    return t if len(t) <= 160 else t[:157] + "..."


def add(aid, kind, seg, **kw):
    h = {"id": aid, "kind": kind, "seg": seg}
    h.update(kw)
    HITS.append(h)


def classify_segment(s):
    """Adds the segment's hits; returns True when it is UNCLASSIFIED (a marker, no id)."""
    p, toks = s["p"], s["toks"]
    text = " ".join(toks)
    got_any, opaque, uncl = False, False, False
    if p["argv0"] is None:
        return has_marker(text)
    if names_writer(s):
        add("policy.edit", "argv", s, p=p)
        got_any = True
        note = ("the command names scripts/plugin-config.sh, a glob, link or copy of it, other than to run its "
                "read-only show: that is the D6 writer itself, or a runnable copy of it (ADR 004 D10)")
        if note not in NOTES:
            NOTES.append(note)
    if p["argv0"] == "git" and p["sub"][:1] == ["push"]:
        d = seg_dir(p)
        remote = None
        pos = positionals(p["sub"][1:], PUSH_VOPTS)
        if pos:
            remote = pos[0]
        elif d:
            remote = "origin"
        defaults = (defaults_set(d, remote) if (d and remote and not URLISH.match(remote)) else None) or STD_DEFAULTS
    else:
        defaults = STD_DEFAULTS
    for a in ACTS:
        if any(entry_matches(e, p, defaults) for e in a["equivalents"].get("argv", [])):
            add(a["id"], "argv", s, p=p)
            got_any = True
    writer = script_hit(p, "plugin-config.sh")
    if writer is not None:
        pos = positionals(writer, set())
        if pos and pos[0] == "provision":
            PG_DENY.append(("policy.edit", "plugin-config.sh provision writes the permission file and lock for CI "
                            "before the agent starts; it never runs from agent Bash (ADR 004 D6)"))
        if pos and pos[0] == "confirm":
            CONFIRMS.append(pos[1] if len(pos) > 1 else "")
    if p["argv0"] == "claude" and p["sub"][:2] == ["plugin", "configure"]:
        PG_DENY.append(("policy.edit", "`claude plugin configure` writes the plugin's option store; run it in your "
                        "own terminal, never from agent Bash (ADR 004 D7, D10.3)"))
    if p["argv0"] == "gemini" and p["sub"][:2] == ["extensions", "config"]:
        PG_DENY.append(("policy.edit", "`gemini extensions config` writes the extension's settings; run it in your "
                        "own terminal, never from agent Bash (ADR 004 D7, D10.3)"))
    rp = script_hit(p, "resolve-permission.sh")
    if rp is not None:
        for k, t in enumerate(rp):
            if t == "--call" and k + 1 < len(rp):
                STAMPS.append(rp[k + 1])
            elif t.startswith("--call="):
                STAMPS.append(t[len("--call="):])
    # Every path of the call is classified, and one that maps to no id is UNCLASSIFIED even when another maps
    # (Codex P1-b, round 2): the call is the strictest of its transfers.
    if p["argv0"] == "gh" and p["sub"][:1] == ["api"]:
        method, paths, fields, has_input = gh_api(p["sub"])
        for path in paths or [None]:
            hit = False
            if path is None or re.fullmatch(r"\$[@*]|\$\{?[A-Za-z_]\w*\}?", path):
                opaque = True
                if method == "GET" and not fields:
                    add("repo.read", "argv", s, p=p)
                    hit = True
            elif norm_path(path) == "graphql":
                doc = " ".join(v.split("=", 1)[1] for _, v in fields if v.startswith("query="))
                file_sourced = has_input or any(f in ("-F", "--field") and v.startswith("query=@") for f, v in fields)
                g, u = graphql_ids(doc, file_sourced)
                for aid in g:
                    add(aid, "graphql", s, p=p)
                hit, uncl = bool(g), uncl or u
            else:
                kv = [v for _, v in fields]
                npath = norm_path(path)
                for aid in rest_ids(method, npath, kv, STD_DEFAULTS):
                    add(aid, "rest", s, p=p, rest=(method, npath, kv))
                    hit = True
            got_any, uncl = got_any or hit, uncl or not hit
    if p["argv0"] in HTTP:
        call = http_call(p)
        if call:
            methods, paths, kv, data, unread = call
            uncl = uncl or unread
            for path in paths:
                hit = False
                if path == "graphql":
                    g, u = graphql_ids(" ".join(data), any(x.startswith("@") for x in data))
                    for aid in g:
                        add(aid, "graphql", s, p=p)
                    hit, uncl = bool(g), uncl or u
                else:
                    for method in methods:
                        ids = rest_ids(method, path, kv, STD_DEFAULTS)
                        for aid in ids:
                            add(aid, "rest", s, p=p, rest=(method, path, kv))
                        hit, uncl = hit or bool(ids), uncl or not ids
                got_any, uncl = got_any or hit, uncl or not hit
    s["hit"] = got_any
    if not got_any and (p["argv0"] == "gh" or p.get("dynamic") or
                        has_marker(" ".join([p["raw0"]] + p["all"]), p["argv0"])):
        uncl = True
    return uncl


def classify_mcp():
    tool = PAY.get("tool_name") if isinstance(PAY.get("tool_name"), str) else ""
    if tool.startswith(PFX):
        bare, ours = tool[len(PFX):], True
    elif tool.startswith("MCP:"):
        bare = tool[4:].strip()
        ours = bare in KNOWN_MCP
    else:
        bare, ours = "", False
    if not ours:
        answer("allow", "")
    args = PAY.get("tool_input")
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except ValueError:
            args = None
    if not isinstance(args, dict):
        args = {}

    def render(v):
        return v if isinstance(v, str) else json.dumps(v)

    full, got = PFX + bare, set()
    for a in ACTS:
        for e in a["equivalents"].get("mcp", []):
            if e["tool"] != full:
                continue
            if any(k not in args or not fnmatch.fnmatchcase(render(args[k]), g) for k, g in e.get("args_all", {}).items()):
                continue
            if any(k in args and fnmatch.fnmatchcase(render(args[k]), g) for k, g in e.get("args_none", {}).items()):
                continue
            got.add(a["id"])
    desc = "GitHub MCP %s" % bare
    bits = []
    if args.get("owner") and args.get("repo"):
        bits.append("%s/%s" % (args["owner"], args["repo"]))
    for k in ("pullNumber", "pull_number", "issue_number", "branch", "path", "method", "state", "event"):
        if k in args and isinstance(args[k], (str, int)):
            bits.append("%s=%s" % (k, args[k]))
    if bits:
        desc += " (" + ", ".join(bits) + ")"
    for aid in sorted(got):
        add(aid, "mcp", None, args=args, tool=bare, desc=desc)
    if not got:
        UNCL_FROM.append(desc)
    return desc


MCP_DESC = None
try:
    if MODE in ("mcp", "classify-mcp"):
        MCP_DESC = classify_mcp()
    else:
        if TOO_LONG:
            PG_DENY.append((UNCL, "the command is longer than %d bytes and carries a form PG must read, so it is "
                            "denied before it is tokenised (a long command could outlast the hook's deadline, F5): "
                            "put long text in a file and pass the file (--body-file, -F, git commit -F)" % MAX_CMD))
        for a_ in ANOMALIES:
            UNCL_FROM.append("the shell tokeniser cannot read this command as a shell does: %s" % a_)
        for s in SEGS:
            s["uncl"] = classify_segment(s)
        # A command inside a substitution is UNCLASSIFIED only when the segment that holds it is not
        # classified itself: in `curl -H "token $(<gh token lookup>)" …/merge` the curl call is pr.merge, and
        # the token lookup is part of it, as in the reference matcher (which never looks inside $(…)).
        for s in SEGS:
            if not s["uncl"]:
                continue
            if s["nested"]:
                inner = " ".join(s["toks"])
                if any(o.get("hit") and not o["nested"] and inner in " ".join(o["toks"]) for o in SEGS):
                    continue
            UNCL_FROM.append(seg_text(s["toks"]))
except SystemExit:
    raise
except Exception as e:  # noqa: BLE001
    answer("deny", "tamirs-superpowers permission guard: classifying the call failed (%s: %s), so it is denied "
           "(fail closed, ADR 004 D4)." % (e.__class__.__name__, str(e)[:120]))

# --------------------------------------------------------------- D3 state (intent, pending, stamps)

_STATE = {}


def state_dir():
    """<home>/.local/state/tamirs-superpowers, <home> from the passwd entry (D3), or None. Without the test
    override in the environment that is pwd.getpwuid, exactly what the resolver's library answers then; with it,
    the library itself decides whether the override holds (scripts/lib/permission-common.sh)."""
    if "d" in _STATE:
        return _STATE["d"]
    d = None
    if not os.environ.get("TAMIRS_PERMISSION_TEST_ROOT"):
        try:
            import pwd
            d = os.path.join(pwd.getpwuid(os.getuid()).pw_dir, ".local", "state", "tamirs-superpowers")
        except (ImportError, KeyError):
            d = None
    if d is None:
        try:
            r = subprocess.run(["bash", "-c", '. "$1/scripts/lib/permission-common.sh" && perm_state_dir', "_", ROOT],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               timeout=max(0.5, min(5.0, left())))
            d = r.stdout.decode("utf-8", "replace").strip() if r.returncode == 0 else None
        except (OSError, subprocess.SubprocessError):
            d = None
    _STATE["d"] = d if d and os.path.isabs(d) else None
    return _STATE["d"]


def private_dir_ok(d):
    try:
        st = os.lstat(d)
    except OSError:
        return False
    return stat.S_ISDIR(st.st_mode) and st.st_uid == os.getuid() and not st.st_mode & 0o077


def read_private(path, limit=262144):
    """The bytes of a D3 state file, read once, or None: its directory and the file owned by this uid with no
    group/other bits, a regular file, not followed through a link, at most `limit` bytes."""
    if not private_dir_ok(os.path.dirname(path)):
        return None
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | getattr(os, "O_NOFOLLOW", 0))
    except OSError:
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077 or st.st_size > limit:
            return None
        chunks, size = [], 0
        while True:
            b = os.read(fd, 65536)
            if not b:
                break
            size += len(b)
            if size > limit:
                return None
            chunks.append(b)
        return b"".join(chunks)
    except OSError:
        return None
    finally:
        os.close(fd)


def private_subdir(name):
    """<state>/<name>, created 0700 (and <state>), or (None, why)."""
    state = state_dir()
    if not state:
        return None, "the state dir could not be resolved"
    sub = os.path.join(state, name)
    try:
        old = os.umask(0o077)
        try:
            os.makedirs(sub, mode=0o700, exist_ok=True)
        finally:
            os.umask(old)
        for d in (state, sub):
            st = os.lstat(d)
            if st.st_uid != os.getuid() or not stat.S_ISDIR(st.st_mode):
                return None, "%s is not a directory owned by this user" % d
            if st.st_mode & 0o077:
                os.chmod(d, 0o700)
    except OSError as e:
        return None, "%s could not be created (%s)" % (sub, e.__class__.__name__)
    return sub, None


def now_utc():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def canon(doc):
    """The serialisation scripts/plugin-config.sh and hooks/permission-intent.sh hash (sorted keys, indent 2)."""
    return (json.dumps(doc, indent=2, sort_keys=True, ensure_ascii=True) + "\n").encode("ascii")


def session_ids():
    """(raw session id, file key) as hooks/permission-intent.sh names intent/<key>.json; (None, None) without one."""
    raw = str(PAY.get("session_id") or PAY.get("conversation_id") or "")
    if not raw:
        return None, None
    return raw, (raw if SID_RE.match(raw) else "h-" + hashlib.sha256(raw.encode("utf-8")).hexdigest()[:32])


def shipped_skill(sk):
    base = os.path.join(ROOT, "skills")
    try:
        cats = os.listdir(base)
    except OSError:
        return False
    return any(os.path.isfile(os.path.join(base, c, sk, "SKILL.md")) for c in cats)


AGENT_KEY_RE = re.compile(r"\A[A-Za-z0-9_-]{1,64}\Z")


def call_agent():
    """The agent this call belongs to: the payload's agent_id, which Claude Code sends on a subagent's calls and
    never on the main thread's (measured M5), so no agent_id is the main thread."""
    return str(PAY.get("agent_id") or "main")[:128]


def context_name(key, agent):
    """intent/ file of one agent's active-skill context, as hooks/permission-intent.sh names it: <sid>.json for the
    main thread, <sid>.agent-<agent>.json for a subagent (a hash when the id is not a plain token)."""
    if agent == "main":
        return key + ".json"
    ak = agent if AGENT_KEY_RE.match(agent) else "h-" + hashlib.sha256(agent.encode("utf-8")).hexdigest()[:32]
    return "%s.agent-%s.json" % (key, ak)


def read_context(state, raw, key, agent):
    """One agent's context, {skill, objective, host_recorded}, or None when it is missing, unsafe, stale,
    malformed, another session's or another agent's. host_recorded: the host itself recorded the skill as active
    for this agent (a UserPromptExpansion paired with its UserPromptSubmit, or a PreToolUse on the Skill tool)."""
    data = read_private(os.path.join(state, "intent", context_name(key, agent)), 65536)
    if data is None:
        return None
    try:
        doc = json.loads(data.decode("ascii"))
    except (UnicodeDecodeError, ValueError):
        return None
    if not isinstance(doc, dict) or doc.get("version") != 1 or doc.get("session_id") != raw:
        return None
    if doc.get("agent") != agent:
        return None
    exp = doc.get("expires")
    if not isinstance(exp, str) or not UTC_RE.match(exp) or exp <= now_utc():
        return None
    sk = doc.get("skill")
    if not (isinstance(sk, str) and SKILL_ID_RE.match(sk) and shipped_skill(sk)):
        sk = None
    obj = doc.get("objective")
    obj = obj if isinstance(obj, str) and OBJ_ID_RE.match(obj) else None
    return {"skill": sk, "objective": obj,
            "host_recorded": doc.get("host_recorded") is True or doc.get("user_typed") is True}


def ctx_variants(c):
    """The --skill values one context contributes: the skill alone when the host recorded it (its per-skill level
    from the user file may widen), the skill and none when it did not (it counts only where stricter), none
    without one."""
    if not c or not c["skill"]:
        return [None]
    return [c["skill"]] if c["host_recorded"] else [c["skill"], None]


def intent_context():
    """The active-skill contexts hooks/permission-intent.sh keeps in intent/ (its header has the format), as
    {skill, objective, variants, raise_ok, why}. Every resolver call runs once per variant (a skill id or None)
    and the strictest answer stands. A per-skill level may widen only on the calls of the agent the host
    recorded the skill for (D8; M5): the main thread's own context for a main-thread call; for a subagent's call,
    its own context, bounded by the main thread's (D1 agent.spawn: the child runs at the caller's ceiling, never
    higher), so a skill recorded on the main thread never raises a subagent's call and a subagent's skill never
    touches the main thread's. A lowering needs no provenance (SR S-09). Anything missing, unsafe, stale or
    malformed is no skill at all: the global level decides."""
    none = {"skill": None, "objective": None, "variants": [None], "raise_ok": False, "why": None}
    raw, key = session_ids()
    state = state_dir()
    if not raw or not state:
        return none
    agent = call_agent()
    own = read_context(state, raw, key, agent)
    main = read_context(state, raw, key, "main") if agent != "main" else None
    variants = ctx_variants(own)
    if agent != "main":
        for v in ctx_variants(main):
            if v not in variants:
                variants.append(v)
    sk = (own or {}).get("skill") or (main or {}).get("skill")
    if not sk:
        variants = [None]
    obj = (own or {}).get("objective") or (main or {}).get("objective")
    raise_ok = variants == [sk] and bool(sk)
    why = None
    if sk and not raise_ok:
        if agent != "main":
            why = ("this call is from another agent (subagent %s) than the main thread, so it runs at most at the "
                   "main thread's level (D1 agent.spawn; a skill is bound to the agent the host recorded it for)"
                   % agent[:64])
        else:
            why = ("the /%s context counts only where it is stricter than the global level: the host did not record "
                   "the skill as active (an expansion that never paired with its prompt, hooks/permission-intent.sh)"
                   % sk)
    return {"skill": sk, "objective": obj, "variants": variants, "raise_ok": raise_ok, "why": why}


# --------------------------------------------------------------- resolve

def needs_resolver(aid):
    a = BYID.get(aid)
    if a is None:
        return True
    if (a.get("l2") or []) == ["L1"]:
        return False
    return a["r"] >= 2 or bool(a.get("raises")) or bool(a.get("denies"))


def pr_target(hit):
    """--target for pr.merge.auto (trust widening needs it); None means no widening."""
    if hit["id"] != "pr.merge.auto" or hit["kind"] != "argv" or not CTX["ok"]:
        return None
    p = hit["p"]
    if p["argv0"] != "gh" or p["sub"][:2] != ["pr", "merge"]:
        return None
    pos = positionals(p["sub"][2:], {"-t", "--subject", "-b", "--body", "-F", "--body-file", "-A", "--author-email",
                                     "--match-head-commit"})
    if len(pos) != 1:
        return None
    ref = pos[0]
    pinned, repo = gh_repo_of(p)
    if not pinned or "$" in ref:
        return None
    if re.fullmatch(r"https://[^/]+/[^/]+/[^/]+/pull/\d+/?", ref):
        return ref
    if not ref.isdigit():
        return None
    return "%s#%s" % (repo, ref) if repo else ref


GH_SLUG_RE = re.compile(r"\A[A-Za-z0-9._-]{1,100}\Z")


def gh_repo_of(p):
    """(pinned, repo): the -R/--repo or GH_REPO= repository of a gh call, None for gh's default (GH_REPO, else
    origin); pinned is False when PG cannot tell (--hostname, GH_HOST=, an expansion, two different -R)."""
    repo = None
    for k, v in p["gopts"]:
        if k == "--hostname":
            return False, None
        if k in ("-R", "--repo"):
            if not v or (repo is not None and v != repo):
                return False, None
            repo = v
    for v in p["env"]:
        if v.startswith("GH_HOST="):
            return False, None
        if v.startswith("GH_REPO=") and repo is None:
            repo = v.split("=", 1)[1]
    if repo is not None and (not repo or re.search(r"[$`\s]", repo)):
        return False, None
    return True, repo


def one_remote_repo(d):
    """True when every remote of the checkout names one repository. Only then does a bare number or "." mean
    the same repository to gh (which, with several remotes, may prefer upstream or a `gh repo set-default`
    one) as to the resolver (origin). False when PG cannot tell."""
    out = git(d, "config", "--get-regexp", r"^remote\..*\.url$") if d else None
    if not out or out[0] != 0:
        return False
    repos = set()
    for line in out[1].splitlines():
        parts = line.split(None, 1)
        m = re.match(r"^(?:[a-z+]+://)?(?:[^@/]+@)?([^/:]+)(?::\d+)?[:/]+([^/]+)/([^/]+?)(?:\.git)?/?$",
                     parts[1].strip()) if len(parts) == 2 else None
        if not m:
            return False
        repos.add("/".join(g.lower() for g in m.groups()))
    return len(repos) == 1


def call_target(hit):
    """--target: what the call acts on, so a --perms= ticket (D5) can match it, in a form the resolver reads (a
    PR or issue number, <owner>/<repo>[#n], a PR/issue URL, or "." for the repository gh would use). Only for the
    R2/R3 pr, issue and repo kinds a ticket can name; None when PG cannot pin it, which no ticket matches."""
    t = raw_call_target(hit)
    if t and (t == "." or re.fullmatch(r"#?\d+", t)) and not one_remote_repo(CTX["cwd"] if CTX["ok"] else None):
        return None   # several remotes: gh may not act on origin, so a relative target is not pinned
    return t


def raw_call_target(hit):
    if hit["id"] == "pr.merge.auto":
        return pr_target(hit)
    a = BYID.get(hit["id"]) or {}
    kind = a.get("target")
    if a.get("r") not in (2, 3) or kind not in ("pr", "issue", "repo"):
        return None
    if hit["kind"] == "mcp":
        args = hit.get("args") or {}
        o, r = args.get("owner"), args.get("repo")
        if not (isinstance(o, str) and isinstance(r, str) and GH_SLUG_RE.match(o) and GH_SLUG_RE.match(r)):
            return None
        if kind == "repo":
            return "%s/%s" % (o, r)
        for k in ("pullNumber", "pull_number", "issue_number", "issueNumber"):
            n = args.get(k)
            if (isinstance(n, int) and not isinstance(n, bool) and n > 0) or (isinstance(n, str) and n.isdigit()):
                return "%s/%s#%d" % (o, r, int(n))
        return None
    if hit["kind"] != "argv" or not CTX["ok"] or hit["p"]["argv0"] != "gh":
        return None
    p = hit["p"]
    pinned, repo = gh_repo_of(p)
    if not pinned:
        return None
    if kind == "repo":
        # gh issue create, gh label create/edit, gh run rerun act on the repository itself
        return (repo or ".") if p["sub"][:1] in (["issue"], ["label"], ["run"]) else None
    if p["sub"][:1] not in (["pr"], ["issue"]) or len(p["sub"]) < 3:
        return None
    sel = p["sub"][2]   # the selector is the first word after the verb, or none (the current branch's PR)
    if re.fullmatch(r"https://[^/\s]+/[^/\s]+/[^/\s]+/(?:pull|issues)/\d+/?", sel):
        return sel
    if not re.fullmatch(r"#?\d{1,12}", sel):
        return None
    return "%s#%s" % (repo, sel.lstrip("#")) if repo else sel.lstrip("#")


JOBS, JOB_KEYS = [], {}
for h in HITS:
    if not needs_resolver(h["id"]):
        continue
    conds = []
    for n in cond_names(h["id"]):
        v = establish(n, h)
        if v is not None:
            conds.append("%s=%s" % (n, "true" if v else "false"))
    target = call_target(h)
    key = (h["id"], tuple(sorted(conds)), target)
    if key in JOB_KEYS:
        JOB_KEYS[key]["hits"].append(h)
        continue
    job = {"id": h["id"], "conds": conds, "target": target, "hits": [h]}
    JOB_KEYS[key] = job
    JOBS.append(job)
if UNCL_FROM:
    JOBS.append({"id": UNCL, "conds": [], "target": None, "hits": [], "uncl": UNCL_FROM})

if MODE.startswith("classify"):
    sys.stdout.write(json.dumps({
        "ids": sorted(set(h["id"] for h in HITS)), "unclassified": bool(UNCL_FROM), "unclassified_from": UNCL_FROM,
        "resolver_calls": [{"id": j["id"], "conds": j["conds"], "target": j["target"]} for j in JOBS],
        "pg_deny": [r for _, r in PG_DENY], "stamps": STAMPS, "confirms": CONFIRMS, "notes": NOTES, "context_ok": CTX["ok"], "context_why": CTX["why"],
        "anomalies": ANOMALIES, "hosts": RES_HOSTS, "dialect": HOST, "fast_path_allows": FAST}, sort_keys=True) + "\n")
    sys.exit(0)


def resolver_failed(job, why):
    job["res"] = {"verdict": "deny", "effective_action": job["id"], "r": 4,
                  "reason": "denied: resolver error: %s (fail closed, D4, SR S-12)" % why, "setting_that_would_allow": None}


INTENT = intent_context() if JOBS else {"skill": None, "objective": None, "variants": [None], "raise_ok": False,
                                       "why": None}
# The --skill values each job is resolved under (intent_context): a skill whose level may widen alone; a skill
# that may only lower beside None, the stricter answer kept (D5 SR S-09: a lowering needs no provenance).
VARIANTS = INTENT["variants"]


def resolver_answer(pr, aid):
    """One resolver process's answer as a result dict (a resolver failure is a deny, D4)."""
    j = {"id": aid}
    try:
        outb, _ = pr.communicate(timeout=max(0.5, left() - 0.5))
    except subprocess.TimeoutExpired:
        pr.kill()
        pr.communicate()
        resolver_failed(j, "it did not answer before the guard's deadline")
        return j["res"]
    if pr.returncode != 0:
        resolver_failed(j, "it exited %d" % pr.returncode)
        try:
            d = json.loads(outb.decode("utf-8", "replace"))
            if isinstance(d, dict) and d.get("reason"):
                j["res"]["reason"] = "denied: resolver exit %d: %s" % (pr.returncode, d["reason"])
        except ValueError:
            pass
        return j["res"]
    try:
        d = json.loads(outb.decode("utf-8", "replace"))
    except ValueError:
        resolver_failed(j, "it printed no JSON")
        return j["res"]
    if not isinstance(d, dict) or d.get("verdict") not in RANK:
        resolver_failed(j, "its answer has no verdict")
        return j["res"]
    return d


def res_rank(d):
    try:
        r = int(d.get("r") if d.get("r") is not None else 4)
    except (TypeError, ValueError):
        r = 4
    return (RANK[d["verdict"]], r)


if JOBS and not os.path.isfile(RESOLVER):
    for j in JOBS:
        resolver_failed(j, "scripts/resolve-permission.sh is missing")
else:
    repo = CTX["cwd"] or payload_cwd() or os.getcwd()
    # D4 row 1: the session and agent a --perms= ticket binds (D5, SR S-11). Claude Code sends agent_id on a
    # subagent's calls and on no main-thread call (M5), so an absent one is the main thread and a main-thread
    # ticket never reaches a subagent.
    _sid = session_ids()[0]
    _agent = call_agent()
    SESSION_ARGV = ["--session", _sid, "--agent", _agent] if (
        _sid and len(_sid) <= 256 and not re.search(r"[\x00-\x1f\x7f]", _sid + _agent)) else []
    procs = []
    for j in JOBS:
        for hi, rhost in enumerate(RES_HOSTS):
          for vi, with_skill in enumerate(VARIANTS):
            argv = ["bash", RESOLVER, j["id"], "--host", rhost, "--repo", repo, "--json"] + SESSION_ARGV
            for c in j["conds"]:
                argv += ["--cond", c]
            if j["target"]:
                argv += ["--target", j["target"]]
            if INTENT["objective"]:
                argv += ["--objective", INTENT["objective"]]   # D4 row 3: tightens only
            if with_skill:
                argv += ["--skill", with_skill]
            try:
                pr = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                      stdin=subprocess.DEVNULL)
            except OSError as e:
                resolver_failed(j, "could not start (%s)" % e.__class__.__name__)
                break
            # On a tie the dialect's own host first, then the answer under a skill (it names its level).
            procs.append((j, (1 if rhost == HOST else 0, (len(VARIANTS) - vi) if with_skill else 0), pr))
    got = {}
    for j, prio, pr in procs:
        got.setdefault(id(j), []).append((prio, resolver_answer(pr, j["id"])))
    for j in JOBS:
        answers = got.get(id(j), [])
        if "res" in j:   # a variant could not start: that deny stands
            continue
        if len(answers) != len(VARIANTS) * len(RES_HOSTS):
            resolver_failed(j, "not every resolver call answered")
            continue
        # The strictest answer wins; on a tie the one under a skill (the call's own first: it names its level).
        j["res"] = max(answers, key=lambda a: (res_rank(a[1]), a[0]))[1]

for reason_id, why in PG_DENY:
    JOBS.append({"id": reason_id, "conds": [], "target": None, "hits": [],
                 "res": {"verdict": "deny", "effective_action": reason_id, "r": 4, "reason": "denied: " + why,
                         "setting_that_would_allow": None}})

def rnum(j):
    try:
        return int(j["res"].get("r") if j["res"].get("r") is not None else 4)
    except (TypeError, ValueError):
        return 4


final = max(JOBS, key=lambda j: (RANK[j["res"]["verdict"]], rnum(j))) if JOBS else None
verdict = final["res"]["verdict"] if final else "allow"
stamp_err = None


def ask_carried():
    """Can this host carry the ask as an ask (D8)? Claude: always (the D5 dialog). OpenCode: only when every
    asking id is an R2 that is not never_auto and not UNCLASSIFIED, since `opencode --auto` approves a plugin ask
    (O1c) and D8 accepts that for R2 alone. Everyone else: never."""
    if HOST in ASK_HOSTS:
        return True
    if HOST not in R2_ASK_HOSTS:
        return False
    asks = [j for j in JOBS if j["res"]["verdict"] == "ask"]
    return bool(asks) and all(j["id"] != UNCL and rnum(j) <= 2 and not j["res"].get("never_auto")
                              and not j["res"].get("unclassified") for j in asks)


ASK_AS_DENY = verdict == "ask" and not ask_carried()
delivered = "deny" if ASK_AS_DENY else verdict

# --------------------------------------------------------------- plugin-config.sh confirm <nonce> (D5)


def row_text(r):
    if not isinstance(r, dict):
        return "?"
    sk = r.get("skills")
    who = (" for %s" % ", ".join(str(x)[:64] for x in sk[:6])) if isinstance(sk, list) and sk else " for every skill"
    when = " when its preconditions hold" if r.get("context") not in (None, "any") else ""
    return "%s (R%s): %s -> %s%s%s" % (str(r.get("action"))[:80], r.get("r"), r.get("from"), r.get("to"), who, when)


def pending_record(nonce):
    """(record, file sha256, None) for a usable pending/<nonce>.json, else (None, None, why)."""
    if not NONCE_RE.match(nonce or ""):
        return None, None, "`%s` is not a nonce (32 hex characters)" % (nonce or "")[:40]
    state = state_dir()
    if not state:
        return None, None, "the state dir could not be resolved"
    data = read_private(os.path.join(state, "pending", nonce + ".json"))
    if data is None:
        return None, None, "there is no pending request %s (expired, already used, never made, or unsafe)" % nonce
    try:
        rec = json.loads(data.decode("ascii"))
    except (UnicodeDecodeError, ValueError):
        return None, None, "the pending record %s is unreadable" % nonce
    if not isinstance(rec, dict) or rec.get("nonce") != nonce or rec.get("kind") not in ("perms", "config"):
        return None, None, "the pending record %s is malformed" % nonce
    if rec.get("body_sha256") != hashlib.sha256(canon(dict((k, v) for k, v in rec.items()
                                                             if k != "body_sha256"))).hexdigest():
        return None, None, "the pending record %s does not match its hash (SR S-17)" % nonce
    exp = rec.get("expires")
    if not isinstance(exp, str) or not UTC_RE.match(exp) or exp <= now_utc():
        return None, None, "the pending request %s has expired" % nonce
    return rec, hashlib.sha256(data).hexdigest(), None


def render_pending(nonce, rec):
    """What the D5 host prompt must name: skill, level, target and expiry (or the rows a config change widens)."""
    if rec["kind"] == "perms":
        tg = rec.get("target") if isinstance(rec.get("target"), dict) else {}
        where = "/".join(str(x)[:120] for x in (tg.get("repo"), tg.get("arg")) if x) or "no resolvable target"
        return ("Approving runs `plugin-config.sh confirm %s`, which grants --perms=%s for %s on %s: a ticket valid 15 "
                "minutes from approval, for R2/R3 calls only, never R4 (request made %s, expires %s)." % (
                    nonce, str(rec.get("level"))[:20], ("skill " + str(rec["skill"])[:64]) if rec.get("skill")
                    else "this whole session", where, rec.get("created"), rec.get("expires")))
    rows = rec.get("rows") if isinstance(rec.get("rows"), list) else []
    shown = "; ".join(row_text(r) for r in rows[:8]) + ("; and %d more" % (len(rows) - 8) if len(rows) > 8 else "")
    return ("Approving runs `plugin-config.sh confirm %s`, which writes `%s` to the permission file, widening: %s "
            "(request made %s, expires %s)." % (nonce, str(rec.get("op"))[:160], shown or "nothing listed",
                                                rec.get("created"), rec.get("expires")))


TUID_RE = re.compile(r"\A[A-Za-z0-9_.:-]{1,256}\Z")


def call_tool_use_id():
    """The payload's tool_use_id (Claude PreToolUse), or None when it has none PG can bind an approval to."""
    t = PAY.get("tool_use_id")
    return t if isinstance(t, str) and TUID_RE.match(t) else None


def write_asked(nonce, rec, file_sha):
    """<state>/asked/<nonce>.json: PG put this confirm, these bytes, to the host prompt (for the writer to require)."""
    d, why = private_subdir("asked")
    if d is None:
        return why
    raw, _ = session_ids()
    tuid = call_tool_use_id()
    if not tuid:
        return "the hook payload names no tool_use_id, so the approval cannot be bound to this call"
    doc = {"version": 1, "nonce": nonce, "file_sha256": file_sha, "body_sha256": rec.get("body_sha256"),
           "kind": rec.get("kind"), "session_id": raw, "agent": str(PAY.get("agent_id") or "main")[:128],
           # The very call the host prompt was shown for: hooks/permission-approved.sh (PostToolUse) promotes a
           # staged widening only for this tool_use_id (task-019 contract).
           "tool_use_id": tuid,
           "host": HOST, "at": now_utc(), "expires": rec.get("expires")}
    tmp = os.path.join(d, ".%s.tmp-%d" % (nonce, os.getpid()))
    try:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
        try:
            os.write(fd, canon(doc))
        finally:
            os.close(fd)
        os.rename(tmp, os.path.join(d, nonce + ".json"))
    except OSError as e:
        return "the confirm stamp could not be written (%s)" % e.__class__.__name__
    return None


CONFIRM_LINES = []
if delivered == "ask" and CONFIRMS:
    # The confirm is R4 policy.edit, so this is the Claude dialog (D5). It must name what it approves; a nonce
    # with no usable record has nothing to name, so it is a deny. Each record is read once: the bytes shown are
    # the bytes stamped.
    seen_recs, refused = [], []
    for n in CONFIRMS:
        rec, fsha, why = pending_record(n)
        if rec is None:
            refused.append(why)
        elif not call_tool_use_id():
            # No id to bind the approval to: no stamp, so the writer would refuse the confirm anyway (fail closed).
            refused.append("the hook payload names no tool_use_id, so an approval of %s could not be bound to this "
                           "call and no confirm stamp is written" % n)
        else:
            seen_recs.append((n, rec, fsha))
    if refused:
        for why in refused:
            JOBS.append({"id": "policy.edit", "conds": [], "target": None, "hits": [],
                         "res": {"verdict": "deny", "effective_action": "policy.edit", "r": 4,
                                 "reason": "denied: plugin-config.sh confirm has nothing for the user to approve: %s "
                                           "(ADR 004 D5: the host prompt names the request's skill, level, target "
                                           "and expiry)" % why, "setting_that_would_allow": None}})
        final = max(JOBS, key=lambda j: (RANK[j["res"]["verdict"]], rnum(j)))
        verdict = delivered = "deny"
    else:
        for n, rec, fsha in seen_recs:
            CONFIRM_LINES.append(render_pending(n, rec))
            err_ = write_asked(n, rec, fsha)
            if err_:
                CONFIRM_LINES.append("Confirm stamp not written: %s." % err_)

# --------------------------------------------------------------- the call stamp (D8)


def write_stamps():
    good = [t for t in STAMPS if CALL_RE.match(t)]
    if not good:
        return None
    seen, why = private_subdir("seen")
    if seen is None:
        return why
    try:
        for t in good:
            try:
                fd = os.open(os.path.join(seen, t), os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
                             0o600)
            except FileExistsError:
                continue
            os.write(fd, ("%d\n" % int(time.time())).encode())
            os.close(fd)
    except OSError as e:
        return "the stamp could not be written (%s)" % e.__class__.__name__
    return None


# Only a call PG does not deny AS DELIVERED is stamped: on a deny-only host an ask leaves as a deny, and the
# command never runs.
if delivered != "deny" and STAMPS:
    stamp_err = write_stamps()

if verdict == "allow":
    answer("allow", "")

# --------------------------------------------------------------- the reason


def describe(j):
    res = j["res"]
    eff = res.get("effective_action") or j["id"]
    r = res.get("r")
    if j["id"] == UNCL and j.get("uncl") and j["uncl"][0].startswith("the shell tokeniser"):
        what = "UNCLASSIFIED (R4): %s" % j["uncl"][0]
    elif j["id"] == UNCL and j.get("uncl"):
        what = "UNCLASSIFIED (R4): `%s` carries a mutation marker but maps to no action id in core/permissions/" \
               "actions.json" % j["uncl"][0]
    else:
        tgt = None
        for h in j["hits"]:
            tgt = h.get("desc") or (seg_text(h["seg"]["toks"]) if h.get("seg") else None)
            if tgt:
                break
        what = "%s%s (R%s)%s" % (eff, (" (raised from %s)" % j["id"]) if eff != j["id"] else "", r,
                                 (" on `%s`" % tgt) if tgt else "")
    return what


def settings(j):
    s = j["res"].get("setting_that_would_allow") or {}
    parts = []
    if s.get("note"):
        parts.append(s["note"])
    if s.get("once") and HOST in ASK_HOSTS:
        parts.append("once: %s in your prompt" % s["once"])
    dur = [x for x in (s.get("durable") or []) if isinstance(x, str)]
    if dur:
        if HOST in ASK_HOSTS:
            parts.append("durable: " + " or ".join("`%s`" % x for x in dur))
        else:
            parts.append("durable, in your own terminal outside the agent session: " +
                         " or ".join("`bash scripts/plugin-config.sh %s`" % x[len("/plugin-config "):]
                                     if x.startswith("/plugin-config ") else "`%s`" % x for x in dur))
    return "; ".join(parts)


lines = []
head = "tamirs-superpowers permission guard (ADR 004)"
res = final["res"]
why = str(res.get("reason") or "").strip()
if ASK_AS_DENY and HOST in R2_ASK_HOSTS:
    verdict = "deny"
    lines.append("%s: denied %s. %s; %s carries only an R2 ask (`opencode --auto` approves a plugin ask, measured "
                 "O1c), so an R3/R4, never-automatic or UNCLASSIFIED ask is delivered as a deny (D8)." % (
                     head, describe(final), why, HOST))
elif ASK_AS_DENY:
    verdict = "deny"
    lines.append("%s: denied %s. %s; %s cannot carry a hook ask (it would %s), so the ask is delivered as a deny "
                 "(D8)." % (head, describe(final), why, HOST,
                            {"codex": "run the call unchecked", "cursor": "be dropped",
                             "gemini": "hang a headless run"}.get(HOST, "not reach a human")))
elif verdict == "ask":
    lines.append("%s: asks before %s. %s." % (head, describe(final), why))
    if HOST in R2_ASK_HOSTS:
        lines.append("An R2 ask: under `opencode --auto` it is approved without a prompt (O1c), which D8 accepts for "
                     "R2 only.")
    lines.extend(CONFIRM_LINES)
else:
    lines.append("%s: denied %s. %s." % (head, describe(final), why))
if INTENT["skill"]:
    lines.append("Active skill (hooks/permission-intent.sh): %s%s." % (
        INTENT["skill"], "" if INTENT["raise_ok"] else "; " + INTENT["why"]))
unknown = [rb.get("when") for rb in (res.get("raised_by") or []) if isinstance(rb, dict) and rb.get("condition") == "unknown"]
if unknown:
    lines.append("Not established, so the raise applied: %s." % ", ".join(sorted(set(x for x in unknown if x))))
    if "default_branch" in unknown:
        lines.append("PG reads the default branch from refs/remotes/<remote>/HEAD (`git remote set-head origin --auto` "
                     "sets it), else from GitHub (gh repo view, under a 3 s deadline), and needs a named remote and a "
                     "resolvable destination.")
if NOTES:
    lines.append(" ".join(n[:1].upper() + n[1:] + "." for n in NOTES))
if not CTX["ok"] and CTX["why"] and MODE == "shell":
    lines.append("Repository conditions were not read: %s." % "; ".join(sorted(set(CTX["why"]))))
st = settings(final)
if st:
    lines.append("To allow it: %s." % st)
others = sorted(set(j["id"] for j in JOBS if j is not final))
if others:
    lines.append("The call also reaches: %s." % ", ".join(others))
if stamp_err:
    lines.append("Call stamp not written: %s." % stamp_err)
answer(verdict, " ".join(lines))
PY

# ------------------------------------------------------------------ inspection CLI

if [ "$#" -gt 0 ]; then
  _PG_DONE=1
  trap - EXIT
  case "$1" in
    --classify|--classify-mcp)
      command -v jq >/dev/null 2>&1 || { echo "permission-guard: jq is required" >&2; exit 2; }
      command -v python3 >/dev/null 2>&1 || { echo "permission-guard: python3 is required" >&2; exit 2; }
      if [ "$1" = --classify ]; then
        [ "$#" -ge 2 ] || { echo "usage: permission-guard.sh --classify '<command>' [cwd]" >&2; exit 2; }
        _pg_cwd="${3:-$PWD}"
        input="$(jq -n --arg c "$2" --arg d "$_pg_cwd" '{session_id:"classify",cwd:$d,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}')"
        _pg_fast=0
        _pg_candidate "$2" || _pg_fast=1
        _pg_mode=classify-shell
      else
        [ "$#" -ge 3 ] || { echo "usage: permission-guard.sh --classify-mcp <tool> '<args-json>' [cwd]" >&2; exit 2; }
        _pg_cwd="${4:-$PWD}"
        input="$(jq -n --arg t "${PG_MCP_PREFIX}$2" --argjson a "$3" --arg d "$_pg_cwd" '{session_id:"classify",cwd:$d,hook_event_name:"PreToolUse",tool_name:$t,tool_input:$a}')" || exit 2
        _pg_fast=0 _pg_mode=classify-mcp
      fi
      printf '%s' "$input" |
        python3 -I -S -c "$_PG_ENGINE" "$PG_ROOT" "${PG_HOST:-claude}" "$_pg_mode" "$PG_BUDGET" "$_pg_fast" \
          "${BASH:-bash}" "${PG_HOST:-claude}"
      exit $? ;;
    -h|--help)
      sed -n '2,/^set -uo pipefail/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "permission-guard.sh: unknown argument '$1' (a hook takes none; see --help)" >&2
      exit 2 ;;
  esac
fi

# ------------------------------------------------------------------ main

input="$(hook_read_stdin)"

if ! command -v jq >/dev/null 2>&1; then
  # hook_detect_platform reads the payload with jq; without it, a Cursor payload is
  # still recognisable by its keys, and the deny must be in Cursor's shape.
  case "$input" in
    *'"conversation_id"'*|*'"cursor_version"'*|*'"workspace_roots"'*) HOOK_PLATFORM=cursor ;;
    *) HOOK_PLATFORM=claude ;;
  esac
  if _pg_blank "$input"; then _pg_finish allow ""; fi
  _PG_DONE=1
  _pg_lit_deny "tamirs-superpowers permission guard cannot run: jq is not installed, so the hook payload cannot be read. Refusing to assume the call is safe (fail closed, ADR 004 D4)."
  exit 0
fi

hook_detect_platform "$input"
_pg_blank "$input" && _pg_finish allow ""

_pg_tool="" _pg_event="" _pg_cmd="" _pg_nul="" _pg_phost=""
{
  IFS= read -r -d '' _pg_nul
  IFS= read -r -d '' _pg_tool
  IFS= read -r -d '' _pg_event
  IFS= read -r -d '' _pg_cmd
  IFS= read -r -d '' _pg_phost
} < <(printf '%s' "$input" | jq -j '
  def s: if type == "string" then . elif . == null then "" else tostring end;
  (.tool_name | s) as $t | (.hook_event_name | s) as $e
  | ((if (.tool_input | type) == "object" then .tool_input.command else null end) // .command | s) as $c
  | (if ($t + $e + $c | contains("\u0000")) then "nul" else "ok" end) + "\u0000" + $t + "\u0000" + $e + "\u0000" + $c + "\u0000"
    + (if (.conversation_id // .cursor_version // .workspace_roots) != null then "cursor"
       elif has("gemini_tool_name") then "gemini"
       elif .turn_id != null then "codex"
       elif .host == "opencode" then "opencode"
       else "claude" end) + "\u0000"
' 2>/dev/null)

# The host (F7). The payload's SHAPE names it: Cursor's own keys, the gemini_tool_name hooks/gemini-wrap.sh
# adds, Codex's turn_id, the "host": "opencode" platforms/opencode/plugin/guard.ts sends, else Claude Code. The
# environment (CODEX_HOME, GEMINI_SESSION_ID, GEMINI_PROJECT_DIR) can be set by a repository, so it never
# loosens: where it names another host, the STRICTER dialect answers (deny-only > OpenCode's R2-only ask >
# Claude's ask) and the resolver is asked under both hosts, the strictest answer kept.
_pg_rank() { case "$1" in codex|cursor|gemini) echo 2 ;; opencode) echo 1 ;; *) echo 0 ;; esac; }
[ -n "$_pg_phost" ] || _pg_phost=claude
PG_HOST="$_pg_phost" PG_RES_HOSTS="$_pg_phost"
for _pg_eh in ${CODEX_HOME:+codex} ${GEMINI_SESSION_ID:+gemini} ${GEMINI_PROJECT_DIR:+gemini}; do
  case ",$PG_RES_HOSTS," in *",$_pg_eh,"*) continue ;; esac
  PG_RES_HOSTS="$PG_RES_HOSTS,$_pg_eh"
  [ "$(_pg_rank "$_pg_eh")" -gt "$(_pg_rank "$PG_HOST")" ] && PG_HOST="$_pg_eh"
done
unset _pg_eh

case "$_pg_nul" in
  ok) : ;;
  nul) _pg_finish deny "tamirs-superpowers permission guard: the call carries a NUL byte, which a shell would read differently from this guard; denied (fail closed, ADR 004 D4)." ;;
  *) _pg_finish deny "tamirs-superpowers permission guard: the hook payload is not valid JSON, so the call cannot be judged (fail closed, ADR 004 D4)." ;;
esac

_pg_mode=""
case "$(normalize_tool_name "$_pg_tool")" in
  Bash|Shell) _pg_mode=shell ;;
  "${PG_MCP_PREFIX}"*|MCP:*) _pg_mode=mcp ;;
esac
[ -z "$_pg_mode" ] && [ "$_pg_event" = beforeShellExecution ] && _pg_mode=shell
[ -n "$_pg_mode" ] || _pg_finish allow ""

if [ "$_pg_mode" = shell ]; then
  _pg_blank "$_pg_cmd" && _pg_finish allow ""
  # FAST PATH: nothing in the command can reach a guarded id. The engine tokenises the rest itself, under a
  # deadline (F5).
  _pg_candidate "$_pg_cmd" || _pg_finish allow ""
fi

if ! command -v python3 >/dev/null 2>&1; then
  _pg_finish deny "tamirs-superpowers permission guard cannot run: python3 is not installed, so the call cannot be classified (fail closed, ADR 004 D4)."
fi

_pg_out="$(
  printf '%s' "$input" |
    python3 -I -S -c "$_PG_ENGINE" "$PG_ROOT" "$PG_HOST" "$_pg_mode" "$PG_BUDGET" 0 "${BASH:-bash}" "$PG_RES_HOSTS" 2>/dev/null
)"
_pg_rc=$?
_pg_verdict="${_pg_out%%$'\n'*}"
_pg_reason="${_pg_out#*$'\n'}"
_pg_reason="${_pg_reason%$'\n'}"
if [ "$_pg_rc" -ne 0 ]; then
  _pg_finish deny "tamirs-superpowers permission guard: its engine exited $_pg_rc without a verdict, so the call is denied (fail closed, ADR 004 D4)."
fi
case "$_pg_verdict" in
  allow|ask|deny) _pg_finish "$_pg_verdict" "$_pg_reason" ;;
  *) _pg_finish deny "tamirs-superpowers permission guard: its engine gave no verdict, so the call is denied (fail closed, ADR 004 D4)." ;;
esac
