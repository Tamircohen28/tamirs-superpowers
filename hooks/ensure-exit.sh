#!/usr/bin/env bash
# UserPromptSubmit hook — verify proxy exit node (opt-in).
# Configure by setting CLAUDE_EXIT_PROXY and CLAUDE_EXIT_PUBLIC_IP env vars.
# No-op (silent exit 0) if either variable is unset — safe to ship without configuration.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"
# Notification tier (plugin option notification_hooks, default on). The
# CLAUDE_EXIT_* opt-in below still applies when the tier is on.
hook_tier_gate notification

PROXY="${CLAUDE_EXIT_PROXY:-}"
PUBLIC_IP="${CLAUDE_EXIT_PUBLIC_IP:-}"

# Skip silently if not configured
if [[ -z "$PROXY" || -z "$PUBLIC_IP" ]]; then
  exit 0
fi

ip=$(curl -s --max-time 5 --proxy "$PROXY" https://api4.ipify.org 2>/dev/null || printf '')
if [[ "$ip" = "$PUBLIC_IP" ]]; then
  exit 0
fi

printf 'Proxy not routing through exit node — check VPN. IP seen: %s\n' "${ip:-none}" >&2
exit 0
