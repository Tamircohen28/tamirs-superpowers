#!/usr/bin/env bash
# Start the GitHub MCP server for the plugin's `github` entry in .mcp.json.
#
# The token arrives in GITHUB_PERSONAL_ACCESS_TOKEN, which .mcp.json sets from the
# manifest's `github_token` userConfig option (`${user_config.github_token}`):
# the person pastes it once in the plugin's config dialog (or `claude plugin
# configure tamirs-superpowers`), and the host keeps it in secure storage.
#
# Nothing is read from the machine. An earlier version derived the token from
# `gh auth token`; the Anthropic directory policy forbids a plugin reading a
# credential already on the user's machine and handing it to a server, so that
# path is gone. A person who prefers the gh CLI's token runs `gh auth token`
# themselves and pastes the result into the option.
#
# Tries the official binary first, falls back to Docker.
set -euo pipefail

if [[ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]]; then
  echo '{"jsonrpc":"2.0","error":{"code":-32000,"message":"github_token is not set. Run: claude plugin configure tamirs-superpowers (or /plugin > tamirs-superpowers > Configure) and paste a GitHub token with repo scope."}}' >&2
  exit 1
fi
export GITHUB_PERSONAL_ACCESS_TOKEN

if command -v github-mcp-server &>/dev/null; then
  exec github-mcp-server stdio
elif command -v docker &>/dev/null; then
  exec docker run -i --rm \
    -e GITHUB_PERSONAL_ACCESS_TOKEN \
    ghcr.io/github/github-mcp-server stdio
else
  echo '{"jsonrpc":"2.0","error":{"code":-32000,"message":"Install github-mcp-server: brew install github-mcp-server"}}' >&2
  exit 1
fi
