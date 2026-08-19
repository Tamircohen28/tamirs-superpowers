#!/usr/bin/env bash
# test-renderers.sh — the four machine-level renderers (codex, cursor, gemini,
# opencode) that turn core/global-rules.md into each platform's own format.
#
# HERMETIC BY CONSTRUCTION. Every run happens against a throwaway HOME created by
# mktemp -d, with XDG_CONFIG_HOME pointed inside it. The suite asserts that up
# front and refuses to run otherwise: a bug here would write to the user's real
# ~/.cursor, ~/.codex, ~/.gemini or ~/.config/opencode, and those are the files
# this whole feature exists to be careful with.
#
# WHAT IS ACTUALLY BEING PROVEN
#   1. each renderer emits its file from the canonical source
#   2. idempotence — a second apply reports "already up to date" and the bytes
#      are unchanged (the marker-replace path is a different code path from the
#      append path, so only a second run exercises it)
#   3. merge preservation — cmux/gortex-shaped wiring seeded before the run is
#      still there verbatim afterwards
#   4. the Codex renderer does not touch hook entries or `trusted_hash`
#   5. no `_`-prefixed metadata key reaches any rendered file
#   6. no absolute /Users/... path reaches any rendered file
#
# Usage: bash tests/test-renderers.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require jq awk
cd "$REPO_ROOT" || exit 1

REAL_HOME="$HOME"
FAKE_HOME="$(harness_tmpdir)/home"
mkdir -p "$FAKE_HOME"

case "$FAKE_HOME" in
  "$REAL_HOME"|"$REAL_HOME"/*) echo "FATAL: fake HOME is inside the real HOME"; exit 1 ;;
esac

CODEX_DIR="$FAKE_HOME/.codex"
CURSOR_DIR="$FAKE_HOME/.cursor"
GEMINI_DIR="$FAKE_HOME/.gemini"
OPENCODE_DIR="$FAKE_HOME/.config/opencode"
MDC="$CURSOR_DIR/rules/tamirs-superpowers.mdc"

# run_setup <verb> — the engine, with a fake HOME and no prompting. Output is
# captured so the assertions can read what the engine reported, not just what it
# wrote. SETUP_YES makes it non-interactive; it still never reads stdin.
run_setup() {
  env HOME="$FAKE_HOME" XDG_CONFIG_HOME="$FAKE_HOME/.config" \
      NO_COLOR=1 SETUP_YES=1 \
      bash scripts/setup.sh "$@" --targets cursor,codex,gemini,opencode 2>&1
}

# ---------------------------------------------------------------------------
section "canonical source"

judge "core/global-rules.md exists" yes "$(exists core/global-rules.md)"
judge "it declares itself canonical" yes \
  "$(has "$(head -3 core/global-rules.md)" 'CANONICAL')"
judge "identity placeholders survive in the canonical source" yes \
  "$(has "$(cat core/global-rules.md)" '<YOUR_GITHUB_HANDLE>')"
judge "the canonical source carries no absolute home path" 0 \
  "$(grep -c '/Users/' core/global-rules.md)"

# ---------------------------------------------------------------------------
section "seed third-party wiring, then render"

# cmux writes hook wiring into ~/.cursor/hooks.json, ~/.codex/config.toml and
# ~/.gemini/settings.json; gortex writes an AfterTool handler. These seeds are
# shaped like the real thing (taken from a live machine's backup) so "merge, do
# not clobber" is tested against what actually exists, not a toy object.
mkdir -p "$CODEX_DIR" "$CURSOR_DIR" "$GEMINI_DIR" "$OPENCODE_DIR"

CODEX_SEED="$CODEX_DIR/config.toml"
cat > "$CODEX_SEED" <<'TOML'
approval_policy = 'never'
model = "gpt-5.6-luna"

[features]
hooks = true

[hooks]
[hooks.state]
[hooks.state."warp@codex-warp:hooks/hooks.json:stop:0:0"]
trusted_hash = "sha256:6a3b3af655efa426e920425de93a830fe25b8b5a62ef7b9a699e7ff40d9ef351"

[hooks.state."vercel@claude-plugins-official:hooks/hooks.json:session_start:0:0"]
trusted_hash = "sha256:3854f8501763b92012b4def8de676279493adfbaec8cc1d00ce72b8e80341b1c"
TOML
CODEX_SEED_COPY="$(harness_tmpdir)/codex-seed.toml"
cp "$CODEX_SEED" "$CODEX_SEED_COPY"

cat > "$GEMINI_DIR/settings.json" <<'JSON'
{
  "hooks": {
    "AfterTool": [
      { "hooks": [ { "command": "gortex hook --agent gemini", "name": "gortex", "type": "command", "timeout": 10000 } ],
        "matcher": "run_shell_command|search_file_content|glob" } ]
  },
  "mcpServers": { "cmux": { "command": "cmux", "args": ["mcp"] } },
  "model": { "name": "gemini-3-pro" }
}
JSON

cat > "$CURSOR_DIR/cli-config.json" <<'JSON'
{ "version": 1,
  "permissions": { "allow": ["Mcp(cmux:*)"], "deny": ["Shell(rm)"] },
  "editor": { "vimMode": false } }
JSON

cat > "$CURSOR_DIR/hooks.json" <<'JSON'
{ "hooks": { "afterAgentResponse": [ { "command": "cmux hooks cursor agent-response" } ] } }
JSON
CURSOR_HOOKS_SUM="$(cksum < "$CURSOR_DIR/hooks.json")"

cat > "$OPENCODE_DIR/opencode.json" <<'JSON'
{ "plugin": ["./plugins/cmux-session.js"],
  "mcp": { "augment-context-engine": { "type": "local", "enabled": true } } }
JSON

OUT1="$(run_setup apply)"
judge "apply reports no failures" no "$(has "$OUT1" 'error:')"

# ---------------------------------------------------------------------------
section "each renderer produced its file"

judge "codex   ~/.codex/AGENTS.md"                 yes "$(exists "$CODEX_DIR/AGENTS.md")"
judge "gemini  ~/.gemini/GEMINI.md"                yes "$(exists "$GEMINI_DIR/GEMINI.md")"
judge "cursor  ~/.cursor/rules/*.mdc"              yes "$(exists "$MDC")"
judge "opencode ~/.config/opencode/AGENTS.md"      yes "$(exists "$OPENCODE_DIR/AGENTS.md")"

for f in "$CODEX_DIR/AGENTS.md" "$GEMINI_DIR/GEMINI.md" "$MDC" "$OPENCODE_DIR/AGENTS.md"; do
  judge "$(basename "$f") carries the canonical rules" yes "$(has "$(cat "$f")" '# Global Agent Rules')"
  judge "$(basename "$f") keeps the identity placeholders" yes "$(has "$(cat "$f")" '<YOUR_GITHUB_HANDLE>')"
done

# The .mdc needs frontmatter or Cursor treats it as an unscoped file; alwaysApply
# is what makes it global rather than glob-triggered.
judge "the Cursor rule declares alwaysApply" yes "$(has "$(head -5 "$MDC")" 'alwaysApply: true')"
judge "the Cursor rule starts with frontmatter" "---" "$(head -1 "$MDC")"

# Capability honesty: the notes section names the platform it was generated for.
# A renderer reading a global that the engine has already moved on from writes
# another platform's name here, which is how this went wrong once.
judge "codex notes name Codex CLI"     yes "$(has "$(cat "$CODEX_DIR/AGENTS.md")" 'Platform notes — Codex CLI')"
judge "gemini notes name Gemini CLI"   yes "$(has "$(cat "$GEMINI_DIR/GEMINI.md")" 'Platform notes — Gemini CLI')"
judge "cursor notes name Cursor"       yes "$(has "$(cat "$MDC")" 'Platform notes — Cursor')"
judge "opencode notes name OpenCode"   yes "$(has "$(cat "$OPENCODE_DIR/AGENTS.md")" 'Platform notes — OpenCode')"

# OpenCode records hooks as unsupported; that has to reach the rendered file
# rather than being silently dropped.
judge "opencode records that hooks are unsupported" yes \
  "$(has "$(cat "$OPENCODE_DIR/AGENTS.md")" '`hooks` — unsupported')"

# ---------------------------------------------------------------------------
section "idempotence — a second apply changes nothing"

SUMS_BEFORE="$(cksum "$CODEX_DIR/AGENTS.md" "$GEMINI_DIR/GEMINI.md" "$MDC" \
  "$OPENCODE_DIR/AGENTS.md" "$CODEX_DIR/config.toml" "$GEMINI_DIR/settings.json" \
  "$CURSOR_DIR/cli-config.json" "$OPENCODE_DIR/opencode.json")"

OUT2="$(run_setup apply)"
judge "second apply reports everything up to date" yes \
  "$(has "$OUT2" 'Everything is already up to date')"
judge "second apply wrote nothing" no "$(has "$OUT2" 'written')"

SUMS_AFTER="$(cksum "$CODEX_DIR/AGENTS.md" "$GEMINI_DIR/GEMINI.md" "$MDC" \
  "$OPENCODE_DIR/AGENTS.md" "$CODEX_DIR/config.toml" "$GEMINI_DIR/settings.json" \
  "$CURSOR_DIR/cli-config.json" "$OPENCODE_DIR/opencode.json")"
judge "every rendered file is byte-identical after the second run" "$SUMS_BEFORE" "$SUMS_AFTER"

PLAN_JSON="$(run_setup plan --json | tail -1)"
if printf '%s' "$PLAN_JSON" | jq empty >/dev/null 2>&1; then
  judge "plan --json reports zero changes on a converged machine" 0 \
    "$(printf '%s' "$PLAN_JSON" | jq '.summary.changes')"
else
  bad "plan --json is parseable" "not JSON: $(printf '%s' "$PLAN_JSON" | head -c 120)"
fi

# ---------------------------------------------------------------------------
section "merge preservation — third-party wiring survives"

judge "gemini gortex AfterTool hook survives verbatim" \
  "gortex hook --agent gemini" \
  "$(jq -r '.hooks.AfterTool[0].hooks[0].command' "$GEMINI_DIR/settings.json")"
judge "gemini mcpServers entry survives" "cmux" \
  "$(jq -r '.mcpServers | keys[0]' "$GEMINI_DIR/settings.json")"
judge "gemini model choice is not overwritten" "gemini-3-pro" \
  "$(jq -r '.model.name' "$GEMINI_DIR/settings.json")"
judge "gemini context.fileName is asserted" true \
  "$(jq -r '[.context.fileName[]] | index("AGENTS.md") != null' "$GEMINI_DIR/settings.json")"

judge "cursor cmux permission survives the union merge" true \
  "$(jq -r '[.permissions.allow[]] | index("Mcp(cmux:*)") != null' "$CURSOR_DIR/cli-config.json")"
judge "cursor deny list is never widened by us" 1 \
  "$(jq '.permissions.deny | length' "$CURSOR_DIR/cli-config.json")"
judge "cursor hooks.json (cmux-owned) is untouched" "$CURSOR_HOOKS_SUM" \
  "$(cksum < "$CURSOR_DIR/hooks.json")"

judge "opencode cmux plugin entry survives" "./plugins/cmux-session.js" \
  "$(jq -r '.plugin[0]' "$OPENCODE_DIR/opencode.json")"
judge "opencode mcp entry survives" "augment-context-engine" \
  "$(jq -r '.mcp | keys[0]' "$OPENCODE_DIR/opencode.json")"

# ---------------------------------------------------------------------------
section "codex — hooks and trusted_hash are never touched"

# Everything above our marker must be the seed, byte for byte. Comparing the
# prefix rather than grepping for the hash proves we did not reorder, reindent or
# requote the table either — any of which invalidates the trust Codex recorded.
CODEX_PREFIX="$(harness_tmpdir)/codex-prefix.toml"
awk '/^# >>> tamirs-superpowers >>>/ { exit } { print }' "$CODEX_DIR/config.toml" \
  | awk '{ lines[NR] = $0 } END { last = NR; while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--; for (i = 1; i <= last; i++) print lines[i] }' \
  > "$CODEX_PREFIX"
judge "config.toml above our block is the seed, unchanged" \
  "$(cksum < "$CODEX_SEED_COPY")" "$(cksum < "$CODEX_PREFIX")"

judge "both trusted_hash assignments are still present" 2 \
  "$(grep -c '^trusted_hash' "$CODEX_DIR/config.toml")"
judge "our block adds no trusted_hash of its own" 0 \
  "$(awk '/^# >>> tamirs-superpowers >>>/ { inb = 1 } inb { print } /^# <<< tamirs-superpowers <<</ { inb = 0 }' \
     "$CODEX_DIR/config.toml" | grep -c '^[^#]*trusted_hash')"
judge "our block is comments only — no bare TOML key can bind to [hooks.state]" 0 \
  "$(awk '/^# >>> tamirs-superpowers >>>/ { inb = 1; next } /^# <<< tamirs-superpowers <<</ { inb = 0 } inb && $0 !~ /^[[:space:]]*#/ && $0 !~ /^[[:space:]]*$/ { print }' \
     "$CODEX_DIR/config.toml" | wc -l | tr -d ' ')"

# ---------------------------------------------------------------------------
section "nothing leaks into a user's config"

RENDERED="$CODEX_DIR/AGENTS.md $GEMINI_DIR/GEMINI.md $MDC $OPENCODE_DIR/AGENTS.md \
$CODEX_DIR/config.toml $GEMINI_DIR/settings.json $CURSOR_DIR/cli-config.json \
$OPENCODE_DIR/opencode.json"

for f in $RENDERED; do
  judge "$(basename "$f") has no absolute /Users/ path" 0 "$(grep -c '/Users/' "$f")"
done

# `_comment` and friends document the fragments under platforms/*/templates/ for
# the next repo reader. They must never reach the machine.
for f in "$GEMINI_DIR/settings.json" "$CURSOR_DIR/cli-config.json" "$OPENCODE_DIR/opencode.json"; do
  judge "$(basename "$f") carries no _-prefixed metadata key" 0 \
    "$(jq '[paths | .[] | select(type == "string") | select(startswith("_"))] | length' "$f")"
done
judge "the source fragments really do carry metadata (so the strip is load-bearing)" yes \
  "$(has "$(cat platforms/cursor/templates/cli-config.json)" '"_comment"')"

# A token-shaped value must never be rendered. Nothing here reads credentials,
# but the check is cheap and the failure would be expensive.
judge "no secret-shaped value in any rendered file" 0 \
  "$(grep -lE '(ghp_|sk-[A-Za-z0-9]{16,}|xox[baprs]-)' $RENDERED 2>/dev/null | wc -l | tr -d ' ')"

# ---------------------------------------------------------------------------
section "remove is symmetric"

OUT3="$(run_setup remove)"
judge "remove reports no failures" no "$(has "$OUT3" 'error:')"
judge "codex AGENTS.md (ours alone) is deleted"   no "$(exists "$CODEX_DIR/AGENTS.md")"
judge "cursor rule file (ours alone) is deleted"  no "$(exists "$MDC")"
judge "codex config.toml is back to the seed" \
  "$(cksum < "$CODEX_SEED_COPY")" "$(cksum < "$CODEX_DIR/config.toml")"
judge "gemini gortex hook is still there after remove" \
  "gortex hook --agent gemini" \
  "$(jq -r '.hooks.AfterTool[0].hooks[0].command' "$GEMINI_DIR/settings.json")"
judge "opencode cmux plugin is still there after remove" "./plugins/cmux-session.js" \
  "$(jq -r '.plugin[0]' "$OPENCODE_DIR/opencode.json")"

# ---------------------------------------------------------------------------
section "the real machine was never touched"

# Not a proxy: these are the actual paths the feature writes to. If HOME override
# ever stops being honoured, this is the assertion that notices.
judge "everything written lives under the fake HOME" yes \
  "$(exists "$CODEX_DIR/config.toml")"
for d in "$REAL_HOME/.cursor/rules/tamirs-superpowers.mdc" "$REAL_HOME/.codex/AGENTS.md.tamirs-tmp"; do
  judge "no test artifact at $(basename "$d") in the real HOME" no "$(exists "$d")"
done

harness_summary
