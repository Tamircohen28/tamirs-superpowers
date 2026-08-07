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
#   - Open Claude Code and install tamirs-superpowers from the tamirs-marketplace marketplace
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
  "model": "opus",
  "effortLevel": "high",
  "alwaysThinkingEnabled": true,
  "skipDangerousModePermissionPrompt": true,
  "skipWorkflowUsageWarning": true,
  "theme": "dark",
  "tui": "fullscreen",
  "preferredNotifChannel": "auto",
  "agentPushNotifEnabled": true,
  "inputNeededNotifEnabled": true,
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
    "tamirs-marketplace": {
      "source": {
        "source": "github",
        "repo": "Tamircohen28/tamirs-marketplace"
      },
      "autoUpdate": true
    },
    "claude-plugins-official": {
      "source": {
        "source": "github",
        "repo": "anthropics/claude-plugins-official"
      }
    },
    "claude-code-warp": {
      "source": {
        "source": "github",
        "repo": "warpdotdev/claude-code-warp"
      }
    }
  }
}
SETTINGS

printf 'Wrote %s\n' "$SETTINGS_FILE"

# --- enabledPlugins: write the canonical set, keep local choices -----------------
# The canonical list is what makes a fresh machine match the reference setup —
# without it, install.sh leaves you with zero plugins and a manual checklist.
# Existing entries merge ON TOP, so a plugin deliberately disabled (or added
# locally) survives a re-run. A new machine has nothing to preserve, so the
# canonical set applies in full.
CANONICAL_PLUGINS='{
  "aws-startup-advisor@claude-plugins-official": true,
  "chrome-devtools-mcp@claude-plugins-official": true,
  "claude-md-management@claude-plugins-official": true,
  "code-review@claude-plugins-official": true,
  "code-simplifier@claude-plugins-official": true,
  "commit-commands@claude-plugins-official": true,
  "context7@claude-plugins-official": true,
  "frontend-design@claude-plugins-official": true,
  "hookify@claude-plugins-official": true,
  "jose-claudinho@tamirs-marketplace": true,
  "learning-output-style@claude-plugins-official": true,
  "playground@claude-plugins-official": true,
  "playwright@claude-plugins-official": true,
  "pr-review-toolkit@claude-plugins-official": true,
  "project-artifact@claude-plugins-official": true,
  "rust-analyzer-lsp@claude-plugins-official": true,
  "skill-creator@claude-plugins-official": true,
  "supabase@claude-plugins-official": true,
  "tamirs-superpowers@tamirs-marketplace": true,
  "vercel@claude-plugins-official": true,
  "warp@claude-code-warp": true
}'

if command -v jq &>/dev/null; then
  # Migrate preserved keys off the pre-2.0.0 marketplace name so a re-run on an
  # older machine doesn't leave dead `@tamirs-plugins` selectors behind.
  PRESERVED="$(printf '%s' "${ENABLED_PLUGINS:-\{\}}" \
    | jq 'with_entries(.key |= sub("@tamirs-plugins$"; "@tamirs-marketplace"))' 2>/dev/null || echo '{}')"
  jq --argjson canon "$CANONICAL_PLUGINS" --argjson keep "$PRESERVED" \
    '. + {enabledPlugins: ($canon * $keep)}' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" \
    && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
  printf 'Wrote enabledPlugins (%d canonical, %d preserved from this machine)\n' \
    "$(printf '%s' "$CANONICAL_PLUGINS" | jq 'length')" "$(printf '%s' "$PRESERVED" | jq 'length')"
else
  printf 'jq not found — skipped enabledPlugins. Install jq and re-run.\n'
fi

# Wire statusLine — finds the latest installed plugin version at runtime
# so the path survives plugin updates without needing to re-run install.sh.
if command -v jq &>/dev/null; then
  # shellcheck disable=SC2016  # single quotes intentional: $HOME must expand at runtime, not here
  STATUS_CMD='f=$(ls "$HOME"/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/*/scripts/statusline.sh 2>/dev/null | sort -rV | head -1) && [ -n "$f" ] && bash "$f"'
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

# --- Install global CLAUDE.md (never clobber a customised one) -------------------
# The template carries <PLACEHOLDER> values filled in per machine, so overwriting
# an existing file would silently discard those edits. Install only when absent;
# otherwise drop it alongside for a manual diff.
CLAUDE_MD_SRC="${PLUGIN_DIR}/templates/global-CLAUDE.md"
CLAUDE_MD_DEST="${CLAUDE_DIR}/CLAUDE.md"
if [[ -f "$CLAUDE_MD_SRC" ]]; then
  if [[ -f "$CLAUDE_MD_DEST" ]]; then
    cp "$CLAUDE_MD_SRC" "${CLAUDE_MD_DEST}.new"
    printf 'CLAUDE.md exists — left untouched; template written to %s.new for comparison\n' "$CLAUDE_MD_DEST"
  else
    cp "$CLAUDE_MD_SRC" "$CLAUDE_MD_DEST"
    printf 'Installed global CLAUDE.md -> %s (fill in the <PLACEHOLDER> values)\n' "$CLAUDE_MD_DEST"
  fi
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

# --- Optional: configure Pushover phone notifications ---
# Opt-in: skipped entirely unless BOTH credentials are supplied, e.g.
#   PUSHOVER_TOKEN=... PUSHOVER_USER=... bash scripts/install.sh
# Complements hooks/notify.sh (macOS banner) — both fire, so you get a desktop
# alert at the machine and a phone push when away from it.
PUSHOVER_TOKEN_IN="${PUSHOVER_TOKEN:-}"
PUSHOVER_USER_IN="${PUSHOVER_USER:-}"

if [[ -n "$PUSHOVER_TOKEN_IN" && -n "$PUSHOVER_USER_IN" ]]; then
  # Credentials live outside the plugin cache: that directory is version-pathed
  # and replaced wholesale on every update, which would delete them.
  PUSHOVER_ENV_FILE="${CLAUDE_DIR}/pushover.env"
  umask 077
  cat > "$PUSHOVER_ENV_FILE" <<PUSHOVER_CREDS
# Pushover credentials for scripts/notify-pushover.sh — keep private, never commit.
PUSHOVER_TOKEN=${PUSHOVER_TOKEN_IN}
PUSHOVER_USER=${PUSHOVER_USER_IN}
PUSHOVER_CREDS
  chmod 600 "$PUSHOVER_ENV_FILE"
  printf 'Wrote Pushover credentials to %s (mode 600)\n' "$PUSHOVER_ENV_FILE"

  if command -v jq &> /dev/null; then
    # shellcheck disable=SC2016  # single quotes intentional: $HOME must expand at runtime, not here
    PUSH_CMD='f=$(ls "$HOME"/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/*/scripts/notify-pushover.sh 2>/dev/null | sort -rV | head -1) && [ -n "$f" ] && bash "$f"'
    # Append without clobbering other Notification hooks, and drop any previous
    # pushover entry first so re-running install.sh stays idempotent.
    jq --arg cmd "$PUSH_CMD" '
      .hooks //= {} |
      .hooks.Notification = (
        ((.hooks.Notification // [])
          | map(select(
              [(.hooks // [])[] | .command // "" | test("notify-pushover")] | any | not
            )))
        + [{hooks: [{type: "command", command: $cmd, timeout: 10}]}]
      )
    ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    printf 'Wired Pushover Notification hook (finds latest installed version at runtime)\n'
  else
    printf 'jq not found — skipped Pushover hook wiring. Install jq and re-run.\n'
  fi
elif [[ -n "$PUSHOVER_TOKEN_IN" || -n "$PUSHOVER_USER_IN" ]]; then
  printf 'Pushover: need BOTH PUSHOVER_TOKEN and PUSHOVER_USER — skipped.\n'
  printf '  Token: https://pushover.net/apps/build   User key: https://pushover.net\n'
fi

printf '\nDone. Next steps:\n'
printf '  1. Open Claude Code\n'
printf '  2. Go to Settings > Plugins > Add marketplace: tamirs-marketplace\n'
printf '  3. Install tamirs-superpowers\n'
printf '  4. Run /reload-plugins\n'
if [[ -z "${PUSHOVER_TOKEN_IN}" || -z "${PUSHOVER_USER_IN}" ]]; then
  printf '\nOptional: phone notifications via Pushover — run /tamirs-superpowers:notify-setup\n'
fi
