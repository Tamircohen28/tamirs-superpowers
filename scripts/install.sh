#!/usr/bin/env bash
# install.sh — bootstrap ~/.claude/settings.json for a new machine.
#
# Usage:
#   make install
#   bash scripts/install.sh
#
# Optional — configure proxy exit-node guard (sets up ~/.claude/ensure-exit.sh):
#   CLAUDE_EXIT_PROXY=http://proxy:port CLAUDE_EXIT_PUBLIC_IP=1.2.3.4 make install
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

# --- Backup existing settings ---
if [[ -f "$SETTINGS_FILE" ]]; then
  backup="${SETTINGS_FILE}.bak.$(date +%s)"
  cp "$SETTINGS_FILE" "$backup"
  printf 'Backed up existing settings to: %s\n' "$backup"
fi

mkdir -p "$CLAUDE_DIR"

# Preserve enabledPlugins from existing settings (install.sh overwrites the file)
ENABLED_PLUGINS=""
if [[ -f "$SETTINGS_FILE" ]] && command -v jq &>/dev/null; then
  ENABLED_PLUGINS="$(jq '.enabledPlugins // empty' "$SETTINGS_FILE" 2>/dev/null || true)"
fi

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

# Merge enabledPlugins back in if we had any
if [[ -n "$ENABLED_PLUGINS" ]] && command -v jq &>/dev/null; then
  jq --argjson ep "$ENABLED_PLUGINS" '. + {enabledPlugins: $ep}' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" \
    && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
  printf 'Preserved enabledPlugins (%d entries)\n' "$(echo "$ENABLED_PLUGINS" | jq 'length')"
fi

# Wire statusLine — finds the latest installed plugin version at runtime
# so the path survives plugin updates without needing to re-run install.sh.
if command -v jq &>/dev/null; then
  # shellcheck disable=SC2016  # single quotes intentional: $HOME must expand at runtime, not here
  STATUS_CMD='f=$(ls "$HOME"/.claude/plugins/cache/tamirs-plugins/tamirs-superpowers/*/scripts/statusline.sh 2>/dev/null | sort -rV | head -1) && [ -n "$f" ] && bash "$f"'
  jq --arg cmd "$STATUS_CMD" '. + {statusLine: {type: "command", command: $cmd}}' \
    "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
  printf 'Wired statusLine (finds latest installed version at runtime)\n'
fi

# --- Install specialist agents to ~/.claude/agents/ ---
# The plugin validator doesn't yet support an "agents" manifest key,
# so agents are shipped in agents/ and installed here instead.
AGENTS_SRC="${PLUGIN_DIR}/agents"
AGENTS_DEST="${CLAUDE_DIR}/agents"
if [[ -d "$AGENTS_SRC" ]]; then
  mkdir -p "$AGENTS_DEST"
  cp "${AGENTS_SRC}"/*.md "$AGENTS_DEST/"
  printf 'Installed %d agent(s) to %s\n' "$(find "${AGENTS_SRC}" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')" "$AGENTS_DEST"
fi

# --- Optional: configure ensure-exit.sh ---
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
