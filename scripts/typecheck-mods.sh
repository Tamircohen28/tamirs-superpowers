#!/usr/bin/env bash
# typecheck-mods.sh — `tsc` over the mod (hooks/mods/) against the build's claude-code.d.ts.
#
# Usage: typecheck-mods.sh [repo-root]
#
# WHY THIS SKIPS INSTEAD OF FAILING WHEN THE TYPES ARE MISSING
#   The Claude Code engine writes the API declarations itself — there is no command that
#   emits them. It lays them beside the mod, in .claude-plugin/types/ (gitignored), whenever an
#   interactive session loads the plugin from a folder the person owns (`claude --plugin-dir .`
#   or the hot-reloaded mods folder); `claude plugin validate` and `claude plugin test` do not.
#   A CI runner has no such session, and the file is ~750 KB and regenerated per build, so it
#   is not vendored either. The gates that always run are `claude plugin validate
#   .claude-plugin/plugin.json` (reads the source the way the engine will) and `claude plugin
#   test .` (runs the hooks); this is the third check, for a machine that has the types.
#
# WHERE IT LOOKS, in order:
#   1. $CLAUDE_CODE_TYPES              an explicit path to a claude-code.d.ts
#   2. .claude-plugin/types/claude-code/index.d.ts   laid by the engine beside the mod
#   3. the plugin-authoring skill's bundled copy, written when that skill loads in a session
#      (newest under ${TMPDIR:-/tmp}/claude-*/bundled-skills/*/*/plugin-authoring/types/)
#
# Exit 0 on a clean check or a skip (with a notice); non-zero on type errors.
set -uo pipefail

ROOT="$(cd "${1:-.}" && pwd)"
MOD_DIR="$ROOT/hooks/mods"

if [[ ! -f "$MOD_DIR/register.tsx" ]]; then
  echo "typecheck-mods: no mod at $MOD_DIR — nothing to check"
  exit 0
fi

types=""
if [[ -n "${CLAUDE_CODE_TYPES:-}" && -f "${CLAUDE_CODE_TYPES}" ]]; then
  types="$CLAUDE_CODE_TYPES"
elif [[ -f "$ROOT/.claude-plugin/types/claude-code/index.d.ts" ]]; then
  types="$ROOT/.claude-plugin/types/claude-code/index.d.ts"
else
  # Newest bundled copy, if a plugin-authoring skill load left one on this machine.
  types="$(ls -t "${TMPDIR:-/tmp}"/claude-*/bundled-skills/*/*/plugin-authoring/types/claude-code.d.ts 2>/dev/null | head -1 || true)"
fi

if [[ -z "$types" ]]; then
  echo "typecheck-mods: SKIPPED — no claude-code.d.ts found (set CLAUDE_CODE_TYPES, or load the plugin"
  echo "  once in an interactive session with 'claude --plugin-dir .' so the engine lays .claude-plugin/types/)."
  exit 0
fi

if ! command -v tsc >/dev/null 2>&1; then
  echo "typecheck-mods: SKIPPED — tsc not on PATH (npm install -g typescript)"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The tsconfig the types file's own header prescribes for a hooks module: no DOM lib (its
# `Text` would shadow the element), JSX against the global `h`, strict.
cat > "$tmp/tsconfig.json" <<EOF
{
  "compilerOptions": {
    "target": "es2023", "lib": ["es2023"], "types": [],
    "module": "esnext", "moduleResolution": "bundler",
    "strict": true, "noUncheckedIndexedAccess": true,
    "noEmit": true, "skipLibCheck": true,
    "jsx": "react", "jsxFactory": "h", "jsxFragmentFactory": "Fragment"
  },
  "files": [
    "$types",
    "$MOD_DIR/types/index.d.ts",
    "$MOD_DIR/register.tsx"$(for t in "$MOD_DIR"/*.test.ts "$MOD_DIR"/*.test.tsx; do [[ -f "$t" ]] && printf ',\n    "%s"' "$t"; done)
  ]
}
EOF

echo "typecheck-mods: tsc against $types"
if tsc -p "$tmp/tsconfig.json"; then
  echo "  mod type-check passed"
else
  echo "  mod type-check FAILED" >&2
  exit 1
fi
