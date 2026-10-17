#!/usr/bin/env bash
# build-claude-dist.sh — the Claude-only distribution of this plugin, as a directory.
#
# Since 5.0.0 this is a thin wrapper: scripts/build-dist.sh writes every host's subset
# from one per-target table, and `--target claude` is the tree Anthropic's plugin
# directory reads (tagged `claude` by the release workflow). The name is kept because
# the release workflow, CI, the Makefile and the docs call it; the rules the tree must
# meet live in scripts/check-claude-dist.sh and
# docs/engineering/build-and-release/directory-distribution.md.
#
# Usage: build-claude-dist.sh <out-dir> [--source <repo-root>] [--force] [--quiet]
set -euo pipefail
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build-dist.sh" --target claude "$@"
