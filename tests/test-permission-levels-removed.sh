#!/usr/bin/env bash
# test-permission-levels-removed.sh — the permission-levels feature (ADR 004) stays
# removed (6.0.0, ADR 006, issue #409).
#
# WHAT IS HELD
#   - the removed hooks, scripts, catalog, schema and the configuration skill are gone;
#   - no hook wiring on any platform (Claude, Codex, Gemini, Cursor, OpenCode) names a
#     removed hook;
#   - no hook source can answer a permission `ask`: hook-output.sh has no ask helper and
#     no hook prints the ask shape (the Gemini wrapper only turns a stray ask into a deny);
#   - `git grep` finds no live reference to the removed names outside the history the
#     issue keeps: CHANGELOG.md, docs/changelog/, docs/engineering/research/, and the
#     two ADRs (004, superseded, and 006, which records the removal).
#
# The names are built from fragments so that this file does not match its own search.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
harness_require git jq

P="permission"
GUARD="${P}-guard"; INTENT="${P}-intent"; APPROVED="${P}-approved"
RESOLVER="resolve-${P}"; COMMON="${P}-common"; CONDS="${P}-conditions"
CFG="plugin-""config"; LEVEL="${P}_level"

# ===========================================================================
section "the removed files are gone"
# ===========================================================================
for f in "hooks/$GUARD.sh" "hooks/$INTENT.sh" "hooks/$APPROVED.sh" "hooks/lib/$CONDS.sh" \
         hooks/lib/pg_batch.py hooks/lib/pg_graphql.py hooks/lib/pg_http.py \
         "scripts/$RESOLVER.sh" "scripts/lib/$COMMON.sh" "scripts/$CFG.sh" \
         "core/${P}s" "core/schemas/${P}s.schema.json" "skills/toolkit/$CFG" \
         ".agents/skills/$CFG" ".gemini/skills/$CFG" ".cursor/commands/$CFG.md" ".opencode/commands/$CFG.md" \
         "platforms/gemini/policies/tamirs-superpowers-${P}s.toml" "platforms/opencode/plugin/$CFG.ts"; do
  judge "absent: $f" no "$(if [ -e "$ROOT/$f" ] || [ -L "$ROOT/$f" ]; then echo yes; else echo no; fi)"
done

# ===========================================================================
section "no platform's hook wiring names a removed hook"
# ===========================================================================
for w in hooks/hooks.json platforms/codex/hooks.json platforms/gemini/hooks.json platforms/cursor/hooks.json \
         platforms/opencode/plugin/guard.ts platforms/opencode/plugin/index.ts platforms/opencode/plugin/rules.ts; do
  [ -f "$ROOT/$w" ] || { bad "wiring file exists: $w" "missing"; continue; }
  hits="$(grep -nE "$GUARD|$INTENT|$APPROVED|$RESOLVER|$CFG\b" "$ROOT/$w" || true)"
  judge "$w names no removed hook" "" "$hits"
done
judge "hooks/hooks.json parses" yes "$(jq empty "$ROOT/hooks/hooks.json" 2>/dev/null && echo yes || echo no)"
judge "no UserPromptExpansion or Skill-matcher hook is wired" "" \
  "$(jq -r '.hooks | (.UserPromptExpansion // empty | "UserPromptExpansion"), (.PreToolUse[]? | select(.matcher == "Skill") | "Skill")' "$ROOT/hooks/hooks.json")"

# ===========================================================================
section "no hook can answer ask"
# ===========================================================================
judge "hook-output.sh defines no ask helper" "" \
  "$(grep -nE '^hook_(cursor_)?ask|HOOK_JQ_[A-Z_]*ASK' "$ROOT/hooks/lib/hook-output.sh" || true)"
asks="$(cd "$ROOT" && grep -nE 'permissionDecision"?[[:space:]]*:[[:space:]]*"ask"|permission"?[[:space:]]*:[[:space:]]*"ask"|hook_ask|emit\(ASK' \
  hooks/*.sh hooks/*.py hooks/lib/*.sh hooks/lib/*.py 2>/dev/null | grep -v '^hooks/lib/gemini-output.sh:' || true)"
judge "no hook prints the ask shape" "" "$asks"
judge "the OpenCode plugin never produces an ask" "" \
  "$(grep -nE '"ask"|deliverAsDeny' "$ROOT/platforms/opencode/plugin/guard.ts" "$ROOT/platforms/opencode/plugin/rules.ts" || true)"
# The one place ask is spelled is the Gemini wrapper's translation, which turns it into a deny.
ASK_ANSWER='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"r"}}'
translated="$(cd "$ROOT" && bash -c 'source hooks/lib/gemini-output.sh; gemini_translate_output BeforeTool "$1"' _ "$ASK_ANSWER" 2>/dev/null)"
judge "the Gemini wrapper turns an ask into a deny" deny "$(printf '%s' "$translated" | jq -r '.decision // empty' 2>/dev/null)"

# ===========================================================================
section "git grep: no live reference outside the kept history"
# ===========================================================================
pattern="$RESOLVER|$COMMON|$CONDS|$CFG([^u]|\$)|$LEVEL|$GUARD|$INTENT|$APPROVED|pg_http|pg_graphql|pg_batch|pg-batch|TAMIRS_""PERMISSION|core/${P}s/|${P}s\.schema\.json"
live="$(cd "$ROOT" && git grep -nIE "$pattern" -- . \
  ':!CHANGELOG.md' ':!docs/changelog' ':!docs/engineering/research' \
  ':!docs/engineering/decisions/004-permission-levels.md' ':!docs/engineering/decisions/006-remove-permission-levels.md' \
  ':!tests/test-permission-levels-removed.sh' 2>/dev/null || true)"
judge "no live reference (each hit is listed)" "" "$live"
ids="$(cd "$ROOT" && git grep -nIE '\b(pr\.merge\.auto|branch\.delete\.remote|docker\.state|deps\.install|policy\.edit|config\.global\.write|HOST_BYPASS|host_bypass\.still_ask)\b' -- . \
  ':!CHANGELOG.md' ':!docs/changelog' ':!docs/engineering/research' \
  ':!docs/engineering/decisions/004-permission-levels.md' ':!docs/engineering/decisions/006-remove-permission-levels.md' \
  ':!tests/test-permission-levels-removed.sh' 2>/dev/null || true)"
judge "no catalog action id is named" "" "$ids"

harness_summary
