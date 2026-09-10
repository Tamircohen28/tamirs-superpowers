#!/usr/bin/env bash
# SessionStart — start the local usage-capture collector when the user opted in.
#
# Silent no-op unless TAMIRS_USAGE_CAPTURE is set (same shape as ensure-exit.sh).
# Fail-open: a missing collector, missing python3, or a failed start never
# blocks the session. No stdout (SessionStart parses hook JSON).
set -uo pipefail

if [[ -z "${TAMIRS_USAGE_CAPTURE:-}" ]]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/..}/scripts/usage-capture/collector.py"
if [[ ! -f "$COLLECTOR" ]]; then
  COLLECTOR="$SCRIPT_DIR/../scripts/usage-capture/collector.py"
fi
if [[ ! -f "$COLLECTOR" ]] || ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi

DIR="${TAMIRS_USAGE_CAPTURE_DIR:-$HOME/.local/share/tamirs-superpowers/usage}"
PORT="${TAMIRS_USAGE_CAPTURE_PORT:-17431}"

python3 "$COLLECTOR" --dir "$DIR" --port "$PORT" --daemon </dev/null >/dev/null 2>&1 || true
exit 0
