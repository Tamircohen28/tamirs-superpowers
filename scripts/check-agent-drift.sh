#!/usr/bin/env bash
# check-agent-drift.sh — verify all SKILL.md frontmatter is valid.
# Wraps validate-skill-frontmatter.py; exits non-zero on any violation.
# Used as the agent-drift enforcement gate (equivalent of check-agent-drift in app repos).
#
# Usage: bash scripts/check-agent-drift.sh [repo-root]
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

echo "=== Agent drift check: skill frontmatter validation ==="
python3 scripts/validate-skill-frontmatter.py
echo "PASS — no frontmatter drift detected"
