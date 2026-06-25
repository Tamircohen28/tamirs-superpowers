#!/usr/bin/env bash
# install.sh — bootstrap ~/.claude/settings.json for a new machine.
#
# Usage:
#   bash install.sh
#
# Optional — configure proxy exit-node guard (sets up ~/.claude/ensure-exit.sh):
#   CLAUDE_EXIT_PROXY=http://proxy:port CLAUDE_EXIT_PUBLIC_IP=1.2.3.4 bash install.sh
#
# What this does:
#   1. Backs up existing ~/.claude/settings.json (if any) to settings.json.bak.<timestamp>
#   2. Writes a clean settings.json with base preferences (no hooks — those come from the plugin)
#   3. Optionally copies a configured ensure-exit.sh to ~/.claude/ensure-exit.sh
#
# What you still need to do manually after running this:
#   - Open Claude Code and install tamirs-superpowers from the tamirs-plugins marketplace
#   - (The marketplace URL is already configured in extraKnownMarketplaces below)

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

# --- Backup existing settings ---
if [[ -f "$SETTINGS_FILE" ]]; then
  backup="${SETTINGS_FILE}.bak.$(date +%s)"
  cp "$SETTINGS_FILE" "$backup"
  printf 'Backed up existing settings to: %s\n' "$backup"
fi

mkdir -p "$CLAUDE_DIR"

# --- Write base settings ---
cat > "$SETTINGS_FILE" <<'SETTINGS'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "model": "sonnet",
  "effortLevel": "xhigh",
  "alwaysThinkingEnabled": true,
  "skipDangerousModePermissionPrompt": true,
  "skipWorkflowUsageWarning": true,
  "theme": "dark",
  "tui": "fullscreen",
  "preferredNotifChannel": "auto",
  "autoCompactEnabled": true,
  "autoScrollEnabled": true,
  "fileCheckpointingEnabled": true,
  "showTurnDuration": true,
  "todoFeatureEnabled": true,
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "permissions": {
    "allow": [
      "Bash(gh repo create *)",
      "Bash(gh api repos/TamirCohen28/* *)",
      "Bash(git init)",
      "Bash(git remote add *)",
      "Bash(git push *)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git tag *)",
      "Bash(find * -maxdepth * *)",
      "Bash(grep -rn *)",
      "Bash(grep -rE *)",
      "Bash(python3:*)",
      "Bash(gh api:*)",
      "Read"
    ]
  },
  "extraKnownMarketplaces": {
    "tamirs-plugins": {
      "source": {
        "source": "git",
        "url": "git@github.com:Tamircohen28/plugins.git"
      },
      "autoUpdate": true
    },
    "claude-plugins-official": {
      "source": {
        "source": "github",
        "repo": "anthropics/claude-plugins-official"
      }
    }
  }
}
SETTINGS

printf 'Wrote %s\n' "$SETTINGS_FILE"

# --- Optional: configure ensure-exit.sh ---
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXIT_PROXY="${CLAUDE_EXIT_PROXY:-}"
EXIT_IP="${CLAUDE_EXIT_PUBLIC_IP:-}"

if [[ -n "$EXIT_PROXY" && -n "$EXIT_IP" ]]; then
  TEMPLATE="${PLUGIN_DIR}/hooks/ensure-exit.sh"
  TARGET="${CLAUDE_DIR}/ensure-exit.sh"
  if [[ -f "$TEMPLATE" ]]; then
    sed \
      -e "s|CLAUDE_EXIT_PROXY:-}|CLAUDE_EXIT_PROXY:-${EXIT_PROXY}}|g" \
      -e "s|CLAUDE_EXIT_PUBLIC_IP:-}|CLAUDE_EXIT_PUBLIC_IP:-${EXIT_IP}}|g" \
      "$TEMPLATE" > "$TARGET"
    chmod +x "$TARGET"
    printf 'Configured ensure-exit.sh with proxy=%s ip=%s -> %s\n' "$EXIT_PROXY" "$EXIT_IP" "$TARGET"
  fi
fi

printf '\nDone. Next steps:\n'
printf '  1. Open Claude Code\n'
printf '  2. Go to Settings > Plugins > Add marketplace: tamirs-plugins\n'
printf '  3. Install tamirs-superpowers\n'
printf '  4. Run /reload-plugins\n'
