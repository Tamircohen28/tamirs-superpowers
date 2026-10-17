#!/usr/bin/env bash
# test-guard-plugin.sh — the guard plugin (plugins/guard) keeps its shape.
#
# WHAT THIS PINS
#   The guard plugin is the one place in this repository that may hold or deny a
#   tool call in-process. It ships as a SEPARATE plugin so the core plugin keeps
#   the footprint Anthropic's plugin directory lists without review, and that
#   split only holds while three things stay true:
#     1. the guard's manifest parses, names its $.state contract, and carries the
#        two boolean options with their documented defaults;
#     2. its hooks.json names exactly one module and nothing else — no bash hook
#        rides along, so installing the guard never doubles a core hook;
#     3. the in-repo marketplace lists it at ./plugins/guard, which is the one
#        install path (the Claude-only distribution never includes plugins/).
#   And the module itself: every gating hook carries a `.catch`, so a hook that
#   throws lets the call through instead of refusing it; it runs no process,
#   makes no network call and submits no prompt; and no file names a model
#   product. The engine's own checks (`claude plugin validate`, `claude plugin
#   test`) run when the CLI is on PATH and are skipped with a notice otherwise,
#   as the core's test-mods target does. A type-check against the build's
#   claude-code.d.ts runs when tsc and a copy of the file are both present.
#
# Usage: bash tests/test-guard-plugin.sh
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"
harness_require jq
cd "$REPO_ROOT" || exit 1

GUARD="plugins/guard"
MANIFEST="$GUARD/.claude-plugin/plugin.json"
HOOKS="$GUARD/hooks/hooks.json"
MODULE="$GUARD/hooks/register.tsx"
TYPES="$GUARD/types/index.d.ts"
TESTFILE="$GUARD/hooks/guard.test.tsx"
MARKET=".claude-plugin/marketplace.json"

section "manifest"
if jq empty "$MANIFEST" 2>/dev/null; then ok "manifest parses"; else bad "manifest parses" "invalid JSON"; fi
judge "manifest name" "tamirs-superpowers-guard" "$(jq -r '.name // empty' "$MANIFEST")"
judge "manifest names the types contract" "./types/index.d.ts" "$(jq -r '.types // empty' "$MANIFEST")"
judge "types contract exists" yes "$(exists "$TYPES")"
judge "types contract declares the plugin's PluginState" yes "$(has "$(cat "$TYPES")" "'tamirs-superpowers-guard': {")"
judge "manifest version is the canonical one" "$(jq -r .version plugin-version.json)" "$(jq -r '.version // empty' "$MANIFEST")"
judge "plugin-version.json lists the guard manifest as a consumer" yes "$(has "$(jq -r '.consumers[].path' plugin-version.json)" "$MANIFEST")"
for opt in hold_destructive_commands deny_main_checkout_writes; do
  judge "userConfig.$opt is a boolean" boolean "$(jq -r --arg o "$opt" '.userConfig[$o].type // empty' "$MANIFEST")"
  judge "userConfig.$opt defaults to true" true "$(jq -r --arg o "$opt" '.userConfig[$o].default // empty' "$MANIFEST")"
  judge "userConfig.$opt is not sensitive" "" "$(jq -r --arg o "$opt" '.userConfig[$o].sensitive // empty' "$MANIFEST")"
done
judge "no other userConfig option" "2" "$(jq -r '.userConfig | length' "$MANIFEST")"
for field in author homepage repository license; do
  judge "manifest $field matches the core manifest" "$(jq -c ".$field" .claude-plugin/plugin.json)" "$(jq -c ".$field" "$MANIFEST")"
done
judge "manifest declares no mcpServers, skills, agents or settings (the core plugin owns those)" "" \
  "$(jq -r '[.mcpServers, .skills, .agents, .settings, .commands] | map(select(. != null)) | join(",")' "$MANIFEST")"

section "hooks.json names exactly one module"
if jq empty "$HOOKS" 2>/dev/null; then ok "hooks.json parses"; else bad "hooks.json parses" "invalid JSON"; fi
judge "hooks.json has the one key, modules" "modules" "$(jq -r 'keys | join(",")' "$HOOKS")"
judge "modules names exactly one module" "./register.tsx" "$(jq -r '.modules | join(",")' "$HOOKS")"
judge "that module exists" yes "$(exists "$MODULE")"
judge "no bash hook is wired (the core plugin's hooks stay canonical)" "" "$(jq -r '.hooks // empty' "$HOOKS")"

section "marketplace"
entry="$(jq -c '.plugins[] | select(.name == "tamirs-superpowers-guard")' "$MARKET")"
judge "the in-repo marketplace lists the guard plugin" yes "$([ -n "$entry" ] && echo yes || echo no)"
judge "its source is ./plugins/guard" "./plugins/guard" "$(printf '%s' "$entry" | jq -r '.source // empty')"
judge "the listed source holds a manifest" yes "$(exists "$GUARD/.claude-plugin/plugin.json")"
for field in displayName description author homepage repository license category keywords; do
  judge "marketplace entry carries $field (the core entry's field set)" true "$(printf '%s' "$entry" | jq -r --arg f "$field" 'has($f)')"
done
judge "marketplace description matches the manifest's" "$(jq -r .description "$MANIFEST")" "$(printf '%s' "$entry" | jq -r .description)"

section "the module's footprint"
# Every registration at a gating site carries a .catch. The two `tool.call`
# registrations are the only ones that can refuse anything; `command.run` for
# the plugin's own command is not a gate (it answers without `next`).
gating="$(grep -cE "^[[:space:]]*on\('tool\.call'" "$MODULE")"
judge "the module registers two tool.call hooks" "2" "$gating"
caught="$(awk '/^[[:space:]]*on\(.tool\.call./{inhook=1} inhook && /^[[:space:]]*\}\)\.catch\(\(\$, e, next\) => next\(e\)\)/{n++; inhook=0} END{print n+0}' "$MODULE")"
judge "every tool.call hook ends in .catch((\$, e, next) => next(e))" "$gating" "$caught"
judge "no \$.process call" "" "$(grep -nE '\$\.process\.' "$MODULE" || true)"
judge "no \$.http call" "" "$(grep -nE '\$\.http\.' "$MODULE" || true)"
judge "no \$.prompt call (nothing is submitted on the person's behalf)" "" "$(grep -nE '\$\.prompt\.' "$MODULE" || true)"
judge "no prompt.submit hook" "" "$(grep -nE "'prompt\.submit'" "$MODULE" || true)"
judge "no \$.model call" "" "$(grep -nE '\$\.model\.' "$MODULE" || true)"
judge "no dynamic import" "" "$(grep -nE 'import\(' "$MODULE" || true)"
judge "event names are string literals" "" "$(grep -nE "^\s*on\([^'\"]" "$MODULE" || true)"
judge "\$ is handed to no helper (only the claude-code state helpers take it)" "" \
  "$(grep -noE '\b[A-Za-z_][A-Za-z0-9_]*\(\s*\$\s*[,)]' "$MODULE" | grep -vE ':(atom|read|update|derive|memberOf)\(' || true)"
judge "the module imports its types from the contract" yes "$(has "$(cat "$MODULE")" "from '../types'")"
judge "the module names the \$.ui.ask fallback (no surface → the call goes through)" yes "$(has "$(cat "$MODULE")" 'surfaces.length === 0')"
judge "the deny reason names the guard" yes "$(has "$(cat "$MODULE")" '${PLUGIN}: Repo edits must happen in an objective worktree')"
judge "a test file exists" yes "$(exists "$TESTFILE")"
# A model product name must not appear in any shipped file of the plugin.
products="$(grep -rniE '\b(opus|sonnet|haiku)\b' "$GUARD" --include='*.tsx' --include='*.ts' --include='*.json' --include='*.md' || true)"
judge "no model product name in the plugin" "" "$products"

section "engine checks (claude CLI)"
if harness_have claude; then
  out="$(claude plugin validate "$MANIFEST" 2>&1)"; rc=$?
  judge "claude plugin validate $MANIFEST passes" 0 "$rc"
  judge "validate reports the Bash hook as a gating hook with .catch" yes "$(has "$out" 'gating hook with .catch: tool.call{tool=Bash}')"
  judge "validate reports no gating hook without .catch" "" "$(printf '%s' "$out" | grep -F 'gating hook without .catch' || true)"
  judge "validate lists the two state-contract keys the holds write" yes "$(has "$out" 'state writes: tamirs-superpowers-guard.cancelled, tamirs-superpowers-guard.deniedWrites')"
  if [ "$rc" -ne 0 ]; then printf '%s\n' "$out" | sed 's/^/    /'; fi
  tout="$(claude plugin test "$GUARD" 2>&1)"; trc=$?
  judge "claude plugin test $GUARD passes" 0 "$trc"
  judge "claude plugin test ran the guard's tests" yes "$(has "$tout" 'guard.test.tsx')"
  judge "claude plugin test reports no failure" yes "$(has "$tout" ' 0 fail')"
  if [ "$trc" -ne 0 ]; then printf '%s\n' "$tout" | tail -40 | sed 's/^/    /'; fi
else
  skip "claude plugin validate / test" "claude CLI not on PATH (install from claude.ai/code; CI runs these in test-mods)"
fi

section "type-check (tsc against the build's claude-code.d.ts)"
# The engine writes the declarations itself; scripts/typecheck-mods.sh explains
# where a copy may be. Same lookup, same skip-with-notice when none is present.
types=""
if [ -n "${CLAUDE_CODE_TYPES:-}" ] && [ -f "${CLAUDE_CODE_TYPES}" ]; then
  types="$CLAUDE_CODE_TYPES"
elif [ -f "$GUARD/.claude-plugin/types/claude-code/index.d.ts" ]; then
  types="$GUARD/.claude-plugin/types/claude-code/index.d.ts"
elif [ -f ".claude-plugin/types/claude-code/index.d.ts" ]; then
  types=".claude-plugin/types/claude-code/index.d.ts"
else
  types="$(ls -t "${TMPDIR:-/tmp}"/claude-*/bundled-skills/*/*/plugin-authoring/types/claude-code.d.ts 2>/dev/null | head -1 || true)"
fi
if [ -z "$types" ]; then
  skip "tsc" "no claude-code.d.ts found (set CLAUDE_CODE_TYPES, or load the plugin once with 'claude --plugin-dir plugins/guard')"
elif ! harness_have tsc; then
  skip "tsc" "tsc not on PATH (npm install -g typescript)"
else
  TMP="$(harness_tmpdir)"
  types_abs="$(cd "$(dirname "$types")" && pwd)/$(basename "$types")"
  cat > "$TMP/tsconfig.json" <<EOF
{
  "compilerOptions": {
    "target": "es2023", "lib": ["es2023"], "types": [],
    "module": "esnext", "moduleResolution": "bundler",
    "strict": true, "noUncheckedIndexedAccess": true,
    "noEmit": true, "skipLibCheck": true,
    "jsx": "react", "jsxFactory": "h", "jsxFragmentFactory": "Fragment"
  },
  "files": [
    "$types_abs",
    "$REPO_ROOT/$TYPES",
    "$REPO_ROOT/$MODULE",
    "$REPO_ROOT/$TESTFILE"
  ]
}
EOF
  if tsc -p "$TMP/tsconfig.json" >"$TMP/tsc.out" 2>&1; then
    ok "tsc passes against $types"
  else
    bad "tsc passes against $types" "$(head -5 "$TMP/tsc.out" | tr '\n' ' ')"
  fi
fi

harness_summary
