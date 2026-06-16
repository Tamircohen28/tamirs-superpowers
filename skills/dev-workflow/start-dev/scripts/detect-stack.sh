#!/usr/bin/env bash
# detect-stack.sh — auto-detect project stack and emit the validation commands to run.
#
# Usage:
#   bash scripts/detect-stack.sh [project-root]
#
# Output (stdout): one shell command per line that should be executed for validation.
# Exit code: 0 always — callers decide whether to abort on command failure.
#
# Example output:
#   make validate
#   npm test
#   npm run lint
#
# The skill's Step 4 sources this output and runs each command in sequence.

set -euo pipefail

ROOT="${1:-.}"

emit() { echo "$1"; }

# ---------- Makefile-based repos (Claude Code plugins, config-heavy projects) ----------
if [ -f "$ROOT/Makefile" ]; then
  if grep -q "^validate:" "$ROOT/Makefile" 2>/dev/null; then
    emit "make validate"
  elif grep -q "^test:" "$ROOT/Makefile" 2>/dev/null; then
    emit "make test"
  elif grep -q "^lint:" "$ROOT/Makefile" 2>/dev/null; then
    emit "make lint"
  fi
fi

# ---------- Node / JavaScript / TypeScript ----------
if [ -f "$ROOT/package.json" ]; then
  PKG="$ROOT/package.json"

  # Prefer the package manager lockfile that exists
  if [ -f "$ROOT/pnpm-lock.yaml" ]; then
    PM="pnpm"
  elif [ -f "$ROOT/yarn.lock" ]; then
    PM="yarn"
  else
    PM="npm"
  fi

  # Test
  if grep -q '"test"' "$PKG" 2>/dev/null; then
    emit "$PM test"
  fi

  # Lint
  if grep -q '"lint"' "$PKG" 2>/dev/null; then
    emit "$PM run lint"
  fi

  # Type-check
  if grep -q '"typecheck"' "$PKG" 2>/dev/null; then
    emit "$PM run typecheck"
  elif [ -f "$ROOT/tsconfig.json" ]; then
    emit "npx tsc --noEmit"
  fi
fi

# ---------- Python ----------
if [ -f "$ROOT/pyproject.toml" ] || [ -f "$ROOT/setup.py" ] || [ -f "$ROOT/requirements.txt" ]; then
  emit "python -m pytest"
fi

# ---------- Go ----------
if [ -f "$ROOT/go.mod" ]; then
  emit "go test ./..."
  emit "go vet ./..."
fi

# ---------- Rust ----------
if [ -f "$ROOT/Cargo.toml" ]; then
  emit "cargo test"
  emit "cargo clippy -- -D warnings"
fi

# ---------- Ruby ----------
if [ -f "$ROOT/Gemfile" ]; then
  if [ -f "$ROOT/Rakefile" ] && grep -q "spec\|rspec\|test" "$ROOT/Rakefile" 2>/dev/null; then
    emit "bundle exec rake"
  else
    emit "bundle exec rspec"
  fi
fi

# ---------- Fallback: nothing detected ----------
# Emit nothing — callers should treat this as "no validation available"
