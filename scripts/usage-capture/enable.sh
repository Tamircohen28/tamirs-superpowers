#!/usr/bin/env bash
# enable.sh — opt-in local usage capture for Claude Code.
#
# Writes Claude Code user settings so native OTEL logs/traces go to the local
# collector on 127.0.0.1. Does not commit anything. Does not send telemetry
# off-machine. Full API bodies stay off unless --bodies is passed.
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
  --dry-run        show what would change; write nothing
  --disable        remove this tool's env keys and stop the collector
  --bodies         also persist untruncated API bodies under <dir>/bodies
  --no-bodies      (default) metadata only — no prompt or API JSON
  --force          overwrite an existing OTEL_EXPORTER_OTLP_ENDPOINT
  --dir DIR        log directory (default: ~/.local/share/tamirs-superpowers/usage)
  --port PORT      collector port (default: 17431)
  --gateway-kind K opaque gateway kind, e.g. litellm (default: custom)
  --endpoint-label L opaque label; never an URL (default: custom)
  --json           print a machine-readable result object on stdout

Example:
  bash scripts/usage-capture/enable.sh --dry-run --json
EOF
}

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

OWNED_KEYS=(
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

merge_settings() {
  python3 - "$SETTINGS" "$DIR" "$PORT" "$GATEWAY_KIND" "$ENDPOINT_LABEL" "$BODIES" "$DISABLE" "$DRY_RUN" "$FORCE" "${OWNED_KEYS[*]}" <<'PY'
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
    for key in owned:
        env.pop(key, None)
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
if dry_run:
    result["dry_run"] = True
    result["env"] = env
    print(json.dumps(result))
    raise SystemExit(0)

os.makedirs(os.path.dirname(path), exist_ok=True)
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

RESULT="$(merge_settings)"
logv "$RESULT"

if [[ "$DISABLE" == 1 ]]; then
  if [[ "$DRY_RUN" == 0 ]]; then
    python3 "$COLLECTOR" --dir "$DIR" --port "$PORT" --stop >/dev/null 2>&1 || true
  fi
  if [[ "$JSON_OUT" == 1 ]]; then
    printf '%s\n' "$RESULT"
  else
    printf 'usage-capture disabled. Restart Claude Code so settings env is dropped.\n'
  fi
  exit 0
fi

if [[ "$DRY_RUN" == 1 ]]; then
  emit "$RESULT"
  exit 0
fi

python3 "$COLLECTOR" --dir "$DIR" --port "$PORT" --daemon >/dev/null
if [[ "$JSON_OUT" == 1 ]]; then
  printf '%s\n' "$RESULT"
else
  printf 'usage-capture enabled. Logs: %s  collector: 127.0.0.1:%s\n' "$DIR" "$PORT"
  printf 'Restart Claude Code so the new OTEL env is picked up.\n'
  if [[ "$BODIES" == 1 ]]; then
    printf 'API bodies will be written under %s/bodies (secret-bearing).\n' "$DIR"
  fi
fi
