---
name: slack-cli
description: Interact with Slack workspaces and manage authentication using the official Slack CLI. Use when working with Slack channels, messages, users, or when the user mentions Slack operations.
allowed-tools:
  - Bash(slack:*)
  - Read
  - Write
---

# Slack CLI Skill

The official Slack CLI (`slack` command) provides command-line access to Slack workspaces and enables Slack app development.

## Installation

The Slack CLI is already installed at `/Users/rango/.local/bin/slack`.

**Verify installation:**
```bash
slack version
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

This generates a reusable token that won't expire, useful for CI/CD and automation.

### Logout
```bash
slack auth logout
```

## Main Commands

### App Management
```bash
# Create a new Slack app
slack create

# List teams where app is installed
slack app list

# Install app to a team
slack app install

# Uninstall from a team
slack app uninstall
```

### Workspace Authentication
```bash
# List all authorized accounts
slack auth list

# Revoke an authentication token
slack auth revoke
```

### Datastore Operations
```bash
# Put an item in datastore
slack datastore put <key> <value>

# Get an item from datastore
slack datastore get <key>

# Query datastore items
slack datastore query

# Delete an item
slack datastore delete <key>

# Bulk operations
slack datastore bulk-put
slack datastore bulk-get
slack datastore bulk-delete
```

### Environment Variables
```bash
# List all environment variables
slack env list

# Add an environment variable
slack env add VAR_NAME

# Remove an environment variable
slack env remove VAR_NAME
```

### Help and Documentation
```bash
# Show all available commands
slack help

# Show help for a specific command
slack help <command>

# Example: Help for app commands
slack help app
```

## Common Workflows

### 1. Getting Help
```bash
slack help auth          # Authentication help
slack help app           # App management help
slack help datastore     # Datastore operations help
```

### 2. Working with Slack Apps
```bash
# Create a new app
slack create

# Link an existing app to your project
slack app link

# List where your app is installed
slack app list

# Install to a new workspace
slack app install
```

### 3. Managing Tokens for CI/CD
```bash
# Generate a service token (non-expiring)
slack auth token

# List current authentication
slack auth list

# Revoke a token when no longer needed
slack auth revoke
```

## Troubleshooting

### Authentication Issues
```bash
# Check if you're properly authenticated
slack auth list

# If you get permission errors, log in again
slack auth login
```

### Command Not Found
```bash
# Ensure slack CLI is in PATH
which slack

# If not found, add to PATH
export PATH="/Users/rango/.local/bin:$PATH"
```

### View Debug Logs
```bash
# Logs are saved in:
cat /Users/rango/.slack/logs/slack-debug-*.log
```

## Important Notes

- **Service tokens** are long-lived and non-expiring. Store them securely.
- **Official CLI scope**: The Slack CLI is primarily designed for Slack app development and automation, not general workspace operations.
- **SSO support**: If your workspace uses SSO, authenticate via the login flow which respects your workspace's SSO configuration.
- For **direct workspace operations** (messages, channels, users), consider alternative tools designed for workspace automation.

## Getting Help

- View command help: `slack help <command>`
- Check documentation: https://docs.slack.dev/tools/slack-cli/
- View debug logs: `/Users/rango/.slack/logs/slack-debug-*.log`