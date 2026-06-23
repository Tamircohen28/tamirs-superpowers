#!/usr/bin/env bash
# detect-contract-profile.sh — choose standards contract profile for a repo root.
#
# Usage: detect-contract-profile.sh [repo-root]
# Output: app-gold | plugin-gold
set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd || { echo "app-gold"; exit 0; })"

if [[ -d "$ROOT/canonical/rules" ]]; then
  echo "plugin-gold"
else
  echo "app-gold"
fi
