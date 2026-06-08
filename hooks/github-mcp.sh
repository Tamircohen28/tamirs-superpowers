#!/usr/bin/env bash
# Start the GitHub MCP server with zero-config authentication via gh CLI.
# Tries the official binary first, falls back to Docker.
set -euo pipefail

TOKEN=$(gh auth token 2>/dev/null || true)
if [[ -z "$TOKEN" ]]; then
  echo '{"jsonrpc":"2.0","error":{"code":-32000,"message":"gh CLI not authenticated. Run: gh auth login"}}' >&2
  exit 1
fi

export GITHUB_PERSONAL_ACCESS_TOKEN="$TOKEN"

if command -v github-mcp-server &>/dev/null; then
  exec github-mcp-server stdio
elif command -v docker &>/dev/null; then
  exec docker run -i --rm \
    -e GITHUB_PERSONAL_ACCESS_TOKEN \
    ghcr.io/github/github-mcp-server stdio
else
  echo '{"jsonrpc":"2.0","error":{"code":-32000,"message":"Install github-mcp-server: brew install github/tap/github-mcp-server"}}' >&2
  exit 1
fi
