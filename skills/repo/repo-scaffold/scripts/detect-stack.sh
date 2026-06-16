#!/usr/bin/env bash
# detect-stack.sh — Auto-detect tech stack from a description string and/or a source directory.
# Usage: detect-stack.sh "<description>" [<src-path-or-url>]
# Outputs one of: nextjs | node | python | swift | generic
# Exit 0 always; writes detected stack to stdout.

set -euo pipefail

DESCRIPTION="${1:-}"
SRC="${2:-}"

description_lower="$(echo "$DESCRIPTION" | tr '[:upper:]' '[:lower:]')"

# --- Priority order matters: nextjs before node ---

detect_from_description() {
  local d="$1"
  if echo "$d" | grep -qE '\b(next\.?js|nextjs|vercel)\b'; then
    echo "nextjs"; return
  fi
  if echo "$d" | grep -qE '\b(react|vue|angular|vite|frontend|tailwind)\b'; then
    echo "node"; return
  fi
  if echo "$d" | grep -qE '\b(python|fastapi|flask|django|poetry|uvicorn|pydantic|pandas|numpy)\b'; then
    echo "python"; return
  fi
  if echo "$d" | grep -qE '\b(swift|swiftui|macos|xcode|ios)\b'; then
    echo "swift"; return
  fi
  if echo "$d" | grep -qE '\b(node|express|cli|npm|typescript|ts)\b'; then
    echo "node"; return
  fi
  echo "generic"
}

detect_from_files() {
  local path="$1"
  if [[ -f "$path/next.config.js" || -f "$path/next.config.ts" || -f "$path/next.config.mjs" ]]; then
    echo "nextjs"; return
  fi
  if [[ -f "$path/package.json" ]]; then
    if grep -q '"next"' "$path/package.json" 2>/dev/null; then
      echo "nextjs"; return
    fi
    echo "node"; return
  fi
  if [[ -f "$path/pyproject.toml" || -f "$path/requirements.txt" || -f "$path/setup.py" ]]; then
    echo "python"; return
  fi
  if [[ -f "$path/Package.swift" ]]; then
    echo "swift"; return
  fi
  echo ""
}

# If --tech was already passed upstream, caller should not invoke this script.
# This script is for auto-detection only.

STACK=""

# 1. Try source directory first (most reliable signal)
if [[ -n "$SRC" && -d "$SRC" ]]; then
  STACK="$(detect_from_files "$SRC")"
fi

# 2. Fall back to description keywords
if [[ -z "$STACK" ]]; then
  STACK="$(detect_from_description "$description_lower")"
fi

echo "$STACK"
