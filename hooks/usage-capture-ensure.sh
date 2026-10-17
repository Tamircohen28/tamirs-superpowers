#!/usr/bin/env bash
# SessionStart — start the local usage-capture collector when the user opted in.
#
# Silent no-op unless TAMIRS_USAGE_CAPTURE is set (same shape as ensure-exit.sh).
# Fail-open: a missing collector, missing python3, or a failed start never
# blocks the session. No stdout (SessionStart parses hook JSON).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"
# Notification tier (plugin option notification_hooks, default on). The
# TAMIRS_USAGE_CAPTURE opt-in below still applies when the tier is on.
hook_tier_gate notification

if [[ -z "${TAMIRS_USAGE_CAPTURE:-}" ]]; then
  exit 0
fi

COLLECTOR="$SCRIPT_DIR/../scripts/usage-capture/collector.py"
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
