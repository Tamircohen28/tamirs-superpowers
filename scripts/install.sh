#!/usr/bin/env bash
# install.sh — bootstrap this machine's Claude Code profile from the repo.
#
# THIS IS A SHIM. All the work happens in scripts/setup.sh, which is the one
# writer for every platform. install.sh exists because `make install` is the
# documented entry point and because "install" reads better than "apply" for a
# first run; it adds nothing but the `--yes --targets claude` opinion and the
# marketplace next-steps that a script cannot perform.
#
# Usage:
#   make install
#   bash scripts/install.sh [--dry-run] [--verbose] [--help]
#
# Optional — proxy exit-node guard (writes ~/.claude/ensure-exit.sh):
#   CLAUDE_EXIT_PROXY=http://proxy:port CLAUDE_EXIT_PUBLIC_IP=1.2.3.4 make install
#
# Optional — phone notifications (writes ~/.claude/pushover.env, mode 600):
#   PUSHOVER_TOKEN=... PUSHOVER_USER=... make install
#
# What it writes: ~/.claude/settings.json (MERGED, not overwritten — see below),
# ~/.claude/agents/, ~/.claude/CLAUDE.md, and the two optional files above.
#
# CHANGED IN PHASE 2 — settings.json is now merged, not clobbered. Earlier
# versions of this script rewrote the file wholesale on every run, preserving
# only enabledPlugins; every other key you had set was destroyed and recoverable
# only from the .bak file. It now merges, keeps a fixed-name backup at
# ~/.claude/settings.json.pre-tamirs-superpowers, and `make uninstall` restores it.
#
# To see what it would do without writing anything:
#   bash scripts/install.sh --dry-run
#
# Exit codes: 0 success, 1 failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
esac

bash "${SCRIPT_DIR}/setup.sh" apply --yes --targets claude "$@"

# The marketplace steps are the part no script can do — plugin installation is a
# Claude Code operation, not a filesystem one.
printf '\nNext steps (Claude Code, not this script):\n'
printf '  1. Open Claude Code\n'
printf '  2. Settings > Plugins > Add marketplace: tamirs-marketplace\n'
printf '  3. Install tamirs-superpowers\n'
printf '  4. On Claude Code < 2.1.221 only: run /reload-plugins\n'
if [ -z "${PUSHOVER_TOKEN:-}" ] || [ -z "${PUSHOVER_USER:-}" ]; then
  printf '\nOptional: phone notifications via Pushover — run /tamirs-superpowers:notify-setup\n'
fi
