---
name: slack-cli
description: Interact with Slack workspaces and manage authentication using the official Slack CLI. Use when working with Slack app development, workspace authentication, datastore operations, or environment variable management via the Slack CLI.
when_to_use: "User asks to do something with Slack via CLI — authenticate a workspace, manage a Slack app, work with Slack datastores, or manage Slack environment variables. Trigger phrases: 'slack cli', 'slack auth', 'slack app', 'slack workspace', 'slack datastore'."
argument-hint: "[optional: specific Slack CLI command or operation]"
allowed-tools:
  - Bash(slack:*)
  - Read
  - Write
metadata:
  capability: slack-integration
  tags:
    - slack
    - cli
    - authentication
    - integrations
  updated-date: "2026-06-08"
---

# Slack CLI Skill

The official Slack CLI (`slack` command) provides command-line access to Slack workspaces and enables Slack app development.

## Installation

Install the Slack CLI via npm or the official installer:
```bash
# npm
npm install -g @slack/cli

# or via the official installer (macOS/Linux)
curl -fsSL https://downloads.slack-edge.com/slack-cli/install.sh | bash
```

**Verify installation:**
```bash
slack version
```

If the command is not found, ensure the install directory is on your `PATH`:
```bash
which slack || echo "slack not in PATH — check your shell profile"
```

## Authentication

### List Authorized Accounts
```bash
slack auth list
```

### Login to a Workspace
```bash
slack auth login
```

### Get Service Token
For programmatic access, generate a service token:
```bash
slack auth token
```

This generates a reusable token useful for CI/CD and automation.

### Logout
```bash
slack auth logout
```

## Main Commands

### App Management
```bash
slack create          # Create a new Slack app
slack app list        # List teams where app is installed
slack app install     # Install app to a team
slack app uninstall   # Uninstall from a team
```

### Workspace Authentication
```bash
slack auth list       # List all authorized accounts
slack auth revoke     # Revoke an authentication token
```

### Datastore Operations
```bash
slack datastore put <key> <value>   # Put an item
slack datastore get <key>           # Get an item
slack datastore query               # Query items
slack datastore delete <key>        # Delete an item
slack datastore bulk-put            # Bulk put
slack datastore bulk-get            # Bulk get
slack datastore bulk-delete         # Bulk delete
```

### Environment Variables
```bash
slack env list                  # List all environment variables
slack env add VAR_NAME          # Add an environment variable
slack env remove VAR_NAME       # Remove an environment variable
```

### Help
```bash
slack help              # All available commands
slack help <command>    # Help for a specific command
```

## Common Workflows

### Getting Started
```bash
slack auth list              # Check current auth
slack auth login             # Authenticate a workspace
slack app list               # See installed apps
```

### Working with Slack Apps
```bash
slack create                 # Create a new app
slack app link               # Link an existing app
slack app install            # Install to a workspace
```

### Managing Tokens for CI/CD
```bash
slack auth token             # Generate a service token
slack auth list              # Verify authentication
slack auth revoke            # Revoke a token
```

## Troubleshooting

### Authentication Issues
```bash
slack auth list              # Check if authenticated
slack auth login             # Re-authenticate if needed
```

### Command Not Found
```bash
which slack                  # Find the binary location
# Add to PATH if needed (edit your shell profile)
export PATH="$HOME/.local/bin:$PATH"
```

### View Debug Logs
```bash
ls ~/.slack/logs/            # Find log files
cat ~/.slack/logs/slack-debug-*.log   # Read latest log
```

## Important Notes

- **Service tokens** are long-lived and non-expiring — store them securely.
- The Slack CLI is primarily for Slack app development, not general workspace messaging.
- For workspace messaging/channels/users, use the Slack MCP server (declared in `.mcp.json`).
- If your workspace uses SSO, authenticate via the login flow which respects SSO configuration.
