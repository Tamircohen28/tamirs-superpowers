#!/usr/bin/env bash
# enable.sh — opt-in local usage capture for Claude Code.
#
# Writes Claude Code user settings so native OTEL logs/traces go to the local
# collector on 127.0.0.1. Does not commit anything. Does not send telemetry
# off-machine. Full API bodies stay off unless --bodies is passed.
#
# PERMISSION GATES (ADR 004 D1, D2, D4; audit other-skills F1)
#   Every step that changes the machine asks scripts/resolve-permission.sh
#   first, and every gate runs BEFORE the first write, so a refused gate leaves
#   nothing half-done:
#     config.global.write     R4  rewriting ~/.claude/settings.json (enable and
#                                 --disable; --force names the endpoint it replaces)
#     secrets.capture.bodies  R4  --bodies, its own confirmation
#     daemon.start            R2  starting the collector
#     daemon.stop             R2  --disable stopping it
#   allow => proceed; ask => the exact action and target are shown on /dev/tty
#   and only a typed "yes" proceeds; deny, a resolver that is missing, fails or
#   prints something unparseable => exit 3 naming the setting that would allow
#   it. No terminal (an agent's shell, CI) is headless: ask becomes deny, so an
#   R4 step never runs unattended — run this yourself in a terminal. No flag
#   (--force included) skips a gate. --dry-run writes nothing and asks nothing.
#   The resolver is found from this file's own location, never from the
#   environment. A rewrite first copies settings.json to
#   settings.json.bak.<UTC timestamp> (0600).
#
# Usage:
#   bash scripts/usage-capture/enable.sh --help
#   bash scripts/usage-capture/enable.sh
#   bash scripts/usage-capture/enable.sh --dry-run --verbose
#   bash scripts/usage-capture/enable.sh --bodies
#   bash scripts/usage-capture/enable.sh --gateway-kind litellm --endpoint-label corp-gateway
#   bash scripts/usage-capture/enable.sh --disable
#   bash scripts/usage-capture/enable.sh --json
#
# Example:
#   bash scripts/usage-capture/enable.sh --dir "$HOME/.local/share/tamirs-superpowers/usage"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR="$SCRIPT_DIR/collector.py"
# The resolver, from THIS file's location (<plugin root>/scripts/usage-capture/),
# never from the environment: a variable that can name it can name a fake one.
RESOLVER="$SCRIPT_DIR/../resolve-permission.sh"
DEFAULT_DIR="${HOME}/.local/share/tamirs-superpowers/usage"
DEFAULT_PORT="17431"
SETTINGS="${HOME}/.claude/settings.json"

usage() {
  cat <<'EOF'
Usage: enable.sh [options]

Opt-in local LLM usage capture for Claude Code. Writes ~/.claude/settings.json
env keys so Claude's OpenTelemetry export points at a loopback collector, then
starts that collector. Nothing is sent off the machine.

Options:
  -h, --help       show this help and exit 0
  -v, --verbose    print planned settings to stderr
  --dry-run        show what would change; write nothing, ask nothing
  --disable        remove this tool's env keys and stop the collector
  --bodies         also persist untruncated API bodies under <dir>/bodies
  --no-bodies      (default) metadata only — no prompt or API JSON
  --force          overwrite an existing OTEL_EXPORTER_OTLP_ENDPOINT (still asks)
  --dir DIR        log directory (default: ~/.local/share/tamirs-superpowers/usage)
  --port PORT      collector port (default: 17431)
  --gateway-kind K opaque gateway kind, e.g. litellm (default: custom)
  --endpoint-label L opaque label; never an URL (default: custom)
  --json           print a machine-readable result object on stdout

Every write is gated (scripts/resolve-permission.sh): rewriting settings.json
and --bodies are R4 and need a typed "yes" on a terminal; with no terminal the
script stops (exit 3) and prints the setting that would allow it. A rewrite
backs settings.json up to settings.json.bak.<UTC timestamp> first.

Example:
  bash scripts/usage-capture/enable.sh --dry-run --json
EOF
}

# The arguments as given, shell-quoted, for the "run it yourself" line.
ORIG_ARGS=""
for _a in "$@"; do ORIG_ARGS="${ORIG_ARGS:+$ORIG_ARGS }$(printf '%q' "$_a")"; done
unset _a

VERBOSE=0
DRY_RUN=0
DISABLE=0
BODIES=0
FORCE=0
JSON_OUT=0
DIR="$DEFAULT_DIR"
PORT="$DEFAULT_PORT"
GATEWAY_KIND="custom"
ENDPOINT_LABEL="custom"

while (($# > 0)); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -v|--verbose) VERBOSE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --disable) DISABLE=1; shift ;;
    --bodies) BODIES=1; shift ;;
    --no-bodies) BODIES=0; shift ;;
    --force) FORCE=1; shift ;;
    --dir)
      [[ -n "${2:-}" && "${2:0:1}" != "-" ]] || { printf 'error: --dir needs a value\n' >&2; usage >&2; exit 1; }
      DIR="$2"; shift 2 ;;
    --port)
      [[ -n "${2:-}" && "${2:0:1}" != "-" ]] || { printf 'error: --port needs a value\n' >&2; usage >&2; exit 1; }
      PORT="$2"; shift 2 ;;
    --gateway-kind)
      [[ -n "${2:-}" && "${2:0:1}" != "-" ]] || { printf 'error: --gateway-kind needs a value\n' >&2; usage >&2; exit 1; }
      GATEWAY_KIND="$2"; shift 2 ;;
    --endpoint-label)
      [[ -n "${2:-}" && "${2:0:1}" != "-" ]] || { printf 'error: --endpoint-label needs a value\n' >&2; usage >&2; exit 1; }
      ENDPOINT_LABEL="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    -*)
      printf 'error: unknown flag %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
    *)
      printf 'error: unexpected argument %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require() { command -v "$1" >/dev/null 2>&1 || { printf 'error: %s is required (%s)\n' "$1" "$2" >&2; exit 1; }; }
require python3 "Python 3 is needed to merge settings and run the collector"

emit() {
  if [[ "$JSON_OUT" == 1 ]]; then
    printf '%s\n' "$1"
  else
    python3 - "$1" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
print(d.get("message") or json.dumps(d, indent=2))
PY
  fi
}

logv() { [[ "$VERBOSE" == 1 ]] && printf '%s\n' "$*" >&2 || true; }

OWNED_FIELDS=(
  TAMIRS_USAGE_CAPTURE
  TAMIRS_USAGE_CAPTURE_PORT
  TAMIRS_USAGE_CAPTURE_DIR
  TAMIRS_USAGE_CAPTURE_GATEWAY_KIND
  TAMIRS_USAGE_CAPTURE_ENDPOINT_LABEL
  CLAUDE_CODE_ENABLE_TELEMETRY
  CLAUDE_CODE_ENHANCED_TELEMETRY_BETA
  OTEL_METRICS_EXPORTER
  OTEL_LOGS_EXPORTER
  OTEL_TRACES_EXPORTER
  OTEL_EXPORTER_OTLP_PROTOCOL
  OTEL_EXPORTER_OTLP_ENDPOINT
  OTEL_LOG_TOOL_DETAILS
  OTEL_LOG_RAW_API_BODIES
  OTEL_RESOURCE_ATTRIBUTES
)

# merge_settings [plan] — "plan" computes the result and writes nothing.
merge_settings() {
  local dry="$DRY_RUN"
  [[ "${1:-}" == plan ]] && dry=1
  python3 - "$SETTINGS" "$DIR" "$PORT" "$GATEWAY_KIND" "$ENDPOINT_LABEL" "$BODIES" "$DISABLE" "$dry" "$FORCE" "${OWNED_FIELDS[*]}" <<'PY'
import json, os, sys
import re

path, log_dir, port, gateway_kind, endpoint_label, bodies, disable, dry_run, force, owned_csv = sys.argv[1:11]
owned = owned_csv.split()
bodies = bodies == "1"
disable = disable == "1"
dry_run = dry_run == "1"
force = force == "1"
if not re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", gateway_kind):
    raise SystemExit("error: --gateway-kind must be an opaque 1-80 character label")
if not re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", endpoint_label):
    raise SystemExit("error: --endpoint-label must be an opaque 1-80 character label, not an URL")

existing = {}
if os.path.isfile(path):
    with open(path, encoding="utf-8") as fh:
        raw = fh.read().strip()
        if raw:
            existing = json.loads(raw)
if not isinstance(existing, dict):
    raise SystemExit("settings.json is not a JSON object")

env = dict(existing.get("env") or {})
current_otlp = env.get("OTEL_EXPORTER_OTLP_ENDPOINT", "")
wanted_otlp = "http://127.0.0.1:%s" % port
if current_otlp and current_otlp != wanted_otlp and not disable and not force:
    sys.stderr.write(
        "error: OTEL_EXPORTER_OTLP_ENDPOINT is already %s; pass --force to replace\n"
        % current_otlp
    )
    raise SystemExit(2)

if disable:
    for name in owned:
        env.pop(name, None)
else:
    resource = env.get("OTEL_RESOURCE_ATTRIBUTES", "")
    parts = [p for p in resource.split(",") if p and not p.startswith("tamirs.endpoint=") and not p.startswith("tamirs.gateway_kind=") and not p.startswith("tamirs.endpoint_label=")]
    parts.extend(["tamirs.gateway_kind=%s" % gateway_kind, "tamirs.endpoint_label=%s" % endpoint_label])
    env.update({
        "TAMIRS_USAGE_CAPTURE": "1",
        "TAMIRS_USAGE_CAPTURE_PORT": str(port),
        "TAMIRS_USAGE_CAPTURE_DIR": log_dir,
        "TAMIRS_USAGE_CAPTURE_GATEWAY_KIND": gateway_kind,
        "TAMIRS_USAGE_CAPTURE_ENDPOINT_LABEL": endpoint_label,
        "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
        "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA": "1",
        "OTEL_METRICS_EXPORTER": "none",
        "OTEL_LOGS_EXPORTER": "otlp",
        "OTEL_TRACES_EXPORTER": "otlp",
        "OTEL_EXPORTER_OTLP_PROTOCOL": "http/json",
        "OTEL_EXPORTER_OTLP_ENDPOINT": wanted_otlp,
        "OTEL_LOG_TOOL_DETAILS": "1",
        "OTEL_RESOURCE_ATTRIBUTES": ",".join(parts),
    })
    env.pop("OTEL_LOG_USER_PROMPTS", None)
    if bodies:
        env["OTEL_LOG_RAW_API_BODIES"] = "file:%s" % os.path.join(log_dir, "bodies")
    else:
        env.pop("OTEL_LOG_RAW_API_BODIES", None)

out = dict(existing)
if env:
    out["env"] = env
else:
    out.pop("env", None)

text = json.dumps(out, indent=2, ensure_ascii=False) + "\n"
result = {"ok": True, "path": path, "disable": disable, "bodies": bodies, "gateway_kind": gateway_kind, "endpoint_label": endpoint_label}
result["replaces_endpoint"] = bool(current_otlp and current_otlp != wanted_otlp and not disable)
if dry_run:
    result["dry_run"] = True
    result["env"] = env
    print(json.dumps(result))
    raise SystemExit(0)

os.makedirs(os.path.dirname(path), exist_ok=True)
# A timestamped copy before any rewrite: git cannot undo a change to this file.
if os.path.isfile(path):
    import shutil, time
    backup = "%s.bak.%s" % (path, time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
    n = 1
    while os.path.exists(backup):
        n += 1
        backup = "%s.bak.%s-%d" % (path, time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()), n)
    fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with open(path, "rb") as src, os.fdopen(fd, "wb") as dst:
        shutil.copyfileobj(src, dst)
    result["backup"] = backup
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.write(text)
os.replace(tmp, path)
try:
    os.chmod(path, 0o600)
except OSError:
    pass
print(json.dumps(result))
PY
}

# --- permission gates (ADR 004) ------------------------------------------------
# can_prompt — a controlling terminal this process can open. An agent's shell
# and CI have none; that is what "headless" means here (D2).
can_prompt() { ( exec 3<>/dev/tty ) 2>/dev/null; }

# json_field <json> <key> — one top-level field as text ("" when absent or not JSON).
json_field() {
  python3 -c 'import json,sys
try:
    v = json.loads(sys.argv[1]).get(sys.argv[2])
except Exception:
    v = None
if isinstance(v, dict):
    parts = list(v.get("durable") or [])
    if v.get("once"):
        parts.insert(0, v["once"])
    if v.get("note"):
        parts.append(v["note"])
    v = "; ".join(parts)
print("" if v is None else v)' "$1" "$2" 2>/dev/null || true
}

# gate <action-id> <target> <what> — 0 proceed; exits 3 when blocked.
gate() {
  local action="$1" target="$2" what="$3" v="" verdict="" headless="" ans=""
  can_prompt || headless=1
  if [[ -f "$RESOLVER" ]]; then
    v="$(bash "$RESOLVER" --action "$action" --skill usage-capture --target "$target" \
          ${headless:+--headless} --json 2>/dev/null)" || v=""
  fi
  verdict="$(json_field "$v" verdict)"
  case "$verdict" in
    allow) return 0 ;;
    ask)
      if [[ -z "$headless" ]]; then
        {
          printf '\nusage-capture wants to: %s\n' "$what"
          printf '  action %s · target %s\n' "$action" "$target"
          printf '  %s\n' "$(json_field "$v" reason)"
          printf 'Type "yes" to allow this once (anything else refuses): '
        } > /dev/tty
        IFS= read -r ans < /dev/tty || ans=""
        if [[ "$ans" == yes ]]; then return 0; fi
        printf 'blocked: %s on %s — not confirmed; nothing was changed\n' "$action" "$target" >&2
        exit 3
      fi
      ;;
  esac
  if [[ -z "$v" || -z "$verdict" ]]; then
    printf 'blocked: %s on %s — the permission resolver is missing or failed (fail closed, ADR 004 D4); nothing was changed\n' \
      "$action" "$target" >&2
  else
    printf 'blocked: %s on %s — %s — allow with: %s\n' "$action" "$target" \
      "$(json_field "$v" reason)" "$(json_field "$v" setting_that_would_allow)" >&2
  fi
  if [[ -n "$headless" ]]; then
    printf 'No terminal, so nothing can be confirmed here. Run it yourself in a terminal:\n  bash %s/enable.sh%s\n' \
      "$SCRIPT_DIR" "${ORIG_ARGS:+ $ORIG_ARGS}" >&2
  fi
  printf 'Nothing was changed.\n' >&2
  exit 3
}

# The plan first: input errors and the foreign-endpoint refusal surface before
# anything is asked, and --dry-run is this plan alone.
PLAN="$(merge_settings plan)"
logv "$PLAN"

if [[ "$DRY_RUN" == 1 ]]; then
  if [[ "$DISABLE" == 1 && "$JSON_OUT" != 1 ]]; then
    printf 'dry run: --disable would remove usage-capture env keys from %s and stop the collector.\n' "$SETTINGS"
  else
    emit "$PLAN"
  fi
  exit 0
fi

if [[ "$DISABLE" == 1 ]]; then
  gate config.global.write "$SETTINGS" "remove the usage-capture env keys from $SETTINGS (a backup is written first)"
  gate daemon.stop "127.0.0.1:$PORT" "stop the usage-capture collector on 127.0.0.1:$PORT"
  RESULT="$(merge_settings)"
  logv "$RESULT"
  python3 "$COLLECTOR" --dir "$DIR" --port "$PORT" --stop >/dev/null 2>&1 || true
  if [[ "$JSON_OUT" == 1 ]]; then
    printf '%s\n' "$RESULT"
  else
    printf 'usage-capture disabled. Restart Claude Code so settings env is dropped.\n'
    [[ -n "$(json_field "$RESULT" backup)" ]] && printf 'Previous settings saved to %s\n' "$(json_field "$RESULT" backup)"
  fi
  exit 0
fi

what="point Claude Code's OpenTelemetry export at 127.0.0.1:$PORT by rewriting the env block of $SETTINGS (a backup is written first)"
if [[ "$(json_field "$PLAN" replaces_endpoint)" == True ]]; then
  what="$what, REPLACING the OTEL_EXPORTER_OTLP_ENDPOINT already set there (--force)"
fi
gate config.global.write "$SETTINGS" "$what"
if [[ "$BODIES" == 1 ]]; then
  gate secrets.capture.bodies "$DIR/bodies" \
    "write untruncated API request/response bodies (conversation, tool results, code — secret-bearing) under $DIR/bodies"
fi
gate daemon.start "127.0.0.1:$PORT" "start the local usage-capture collector on 127.0.0.1:$PORT (restarted each session while enabled)"

RESULT="$(merge_settings)"
logv "$RESULT"

python3 "$COLLECTOR" --dir "$DIR" --port "$PORT" --daemon >/dev/null
if [[ "$JSON_OUT" == 1 ]]; then
  printf '%s\n' "$RESULT"
else
  printf 'usage-capture enabled. Logs: %s  collector: 127.0.0.1:%s\n' "$DIR" "$PORT"
  [[ -n "$(json_field "$RESULT" backup)" ]] && printf 'Previous settings saved to %s\n' "$(json_field "$RESULT" backup)"
  printf 'Restart Claude Code so the new OTEL env is picked up.\n'
  if [[ "$BODIES" == 1 ]]; then
    printf 'API bodies will be written under %s/bodies (secret-bearing).\n' "$DIR"
  fi
fi
