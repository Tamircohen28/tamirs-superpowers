#!/usr/bin/env bash
# test-validate-marketplace.sh — the marketplace validator rejects what the platforms reject.
#
# WHAT THIS SUITE IS FOR
#   scripts/validate-marketplace.sh (canonical: the _contract template; the gold fixture
#   carries a byte-identical copy) is the deterministic gate for a `--type marketplace`
#   repo. The gold fixture proves the positive path; it cannot prove that a bad catalog
#   FAILS, and a validator that passes everything looks identical to one that works. Each
#   case here mutates a copy of the fixture into one documented mistake and asserts the
#   script exits 1 and names the problem. The first negative is the Codex-review repro: a
#   string-form local source whose plugin manifest carries a different name slipped past
#   the object-form check.
#
# Hermetic: temp copies of the fixture only, no network, MARKETPLACE_SKIP_CLI=1 so the
# result never depends on whether Claude Code is installed on this machine.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"

harness_require jq

FIXTURE="$ROOT/skills/repo/_contract/fixtures/scaffold-marketplace-gold"
TEMPLATE="$ROOT/skills/repo/_contract/templates/marketplace/scripts/validate-marketplace.sh.tmpl"
SCRIPT="$FIXTURE/scripts/validate-marketplace.sh"
PLUGIN="scaffold-marketplace-gold-starter"
TMP="$(harness_tmpdir)"
export MARKETPLACE_SKIP_CLI=1

# fresh <name> — a mutable copy of the fixture; prints its path.
fresh() {
  local d="$TMP/$1"
  rm -rf "$d"
  cp -R "$FIXTURE" "$d"
  printf '%s\n' "$d"
}

# run <dir> — sets RC (exit code) and OUT (combined output). Globals, not a command
# substitution: a subshell would keep OUT from reaching the judges.
run() {
  OUT="$(bash "$SCRIPT" "$1" 2>&1)"
  RC=$?
}

# set_json <file> <jq-filter> — in-place edit.
set_json() {
  local f="$1" filter="$2" tmp
  tmp="$(mktemp)"
  jq "$filter" "$f" > "$tmp" && mv "$tmp" "$f"
}

# ===========================================================================
section "the fixture copy is byte-identical to the canonical template"
# ===========================================================================
judge "fixture script == template (script-sync holds the link)" yes \
  "$(if cmp -s "$TEMPLATE" "$SCRIPT"; then echo yes; else echo no; fi)"

# ===========================================================================
section "positive control: the gold fixture passes"
# ===========================================================================
d="$(fresh gold)"
run "$d"; rc=$RC
judge "gold fixture exits 0" 0 "$rc"
judge "  ... and reports every platform that has a marketplace" yes \
  "$(if [[ "$OUT" == *"ok:    claude:"* && "$OUT" == *"ok:    cursor:"* && "$OUT" == *"ok:    codex:"* ]]; then echo yes; else echo no; fi)"
judge "  ... and says OpenCode has no manifest instead of inventing one" yes \
  "$(has "$OUT" "opencode: no marketplace manifest exists")"
judge "  ... and says the platform CLI was skipped, not silently" yes \
  "$(has "$OUT" "skip:  claude plugin validate")"

# ===========================================================================
section "Codex: a local plugin whose manifest name differs from the entry (both source spellings)"
# ===========================================================================
# Codex-review repro: string-form source "./plugins/<name>" with the plugin's
# .codex-plugin/plugin.json renamed. The object form already failed; the string form
# only checked that the directory existed.
d="$(fresh codex-string-mismatch)"
set_json "$d/.agents/plugins/marketplace.json" ".plugins[0].source = \"./plugins/$PLUGIN\""
set_json "$d/plugins/$PLUGIN/.codex-plugin/plugin.json" '.name = "different-name"'
run "$d"; rc=$RC
judge "string-form local source + renamed .codex-plugin/plugin.json -> exit 1" 1 "$rc"
judge "  ... naming the mismatch" yes "$(has "$OUT" "says 'different-name'")"

d="$(fresh codex-string-ok)"
set_json "$d/.agents/plugins/marketplace.json" ".plugins[0].source = \"./plugins/$PLUGIN\""
run "$d"; rc=$RC
judge "positive control: string-form local source with a matching name -> exit 0" 0 "$rc"

d="$(fresh codex-object-mismatch)"
set_json "$d/plugins/$PLUGIN/.codex-plugin/plugin.json" '.name = "different-name"'
run "$d"; rc=$RC
judge "object-form local source + renamed .codex-plugin/plugin.json -> exit 1" 1 "$rc"
judge "  ... naming the mismatch" yes "$(has "$OUT" "says 'different-name'")"

d="$(fresh codex-local-no-path)"
set_json "$d/.agents/plugins/marketplace.json" 'del(.plugins[0].source.path)'
run "$d"; rc=$RC
judge "object-form local source without path -> exit 1" 1 "$rc"
judge "  ... naming the missing field" yes "$(has "$OUT" "local source needs 'path'")"

# ===========================================================================
section "every documented manifest location must agree with the entry name"
# ===========================================================================
# Codex-review repro (round 4): a local Codex plugin in the root plugin.json format — the
# portable entry point the research doc records — named "different-name", with the
# optional .codex-plugin/plugin.json fallback matching. Only the fallback was compared.
d="$(fresh codex-root-mismatch)"
printf '{"name":"different-name","version":"0.1.0"}\n' > "$d/plugins/$PLUGIN/plugin.json"
run "$d"; rc=$RC
judge "Codex: root plugin.json 'different-name' + matching .codex-plugin fallback -> exit 1" 1 "$rc"
judge "  ... naming the root manifest" yes "$(has "$OUT" "plugins/$PLUGIN/plugin.json says 'different-name'")"

d="$(fresh codex-root-ok)"
printf '{"name":"%s","version":"0.1.0"}\n' "$PLUGIN" > "$d/plugins/$PLUGIN/plugin.json"
run "$d"; rc=$RC
judge "positive control: root plugin.json with the entry name, fallback matching -> exit 0" 0 "$rc"

d="$(fresh codex-fallback-only-mismatch)"
set_json "$d/plugins/$PLUGIN/.codex-plugin/plugin.json" '.name = "different-name"'
run "$d"; rc=$RC
judge "fallback order: no root plugin.json, .codex-plugin/plugin.json 'different-name' -> exit 1" 1 "$rc"
judge "  ... naming the fallback manifest" yes "$(has "$OUT" ".codex-plugin/plugin.json says 'different-name'")"

d="$(fresh codex-root-ok-fallback-mismatch)"
printf '{"name":"%s","version":"0.1.0"}\n' "$PLUGIN" > "$d/plugins/$PLUGIN/plugin.json"
set_json "$d/plugins/$PLUGIN/.codex-plugin/plugin.json" '.name = "different-name"'
run "$d"; rc=$RC
judge "root plugin.json matching but the fallback disagreeing -> exit 1 (a reader on the fallback resolves another plugin)" 1 "$rc"

d="$(fresh codex-root-only-ok)"
printf '{"name":"%s","version":"0.1.0"}\n' "$PLUGIN" > "$d/plugins/$PLUGIN/plugin.json"
rm "$d/plugins/$PLUGIN/.codex-plugin/plugin.json"
run "$d"; rc=$RC
judge "positive control: root plugin.json only, no fallback -> exit 0" 0 "$rc"

# Cursor documents two formats: .cursor-plugin/plugin.json (Cursor Plugins) and a root
# plugin.json (Agent Plugins). Both are merged with the entry when found.
d="$(fresh cursor-root-mismatch)"
rm "$d/plugins/$PLUGIN/.cursor-plugin/plugin.json"
printf '{"name":"different-name","version":"0.1.0"}\n' > "$d/plugins/$PLUGIN/plugin.json"
run "$d"; rc=$RC
judge "Cursor: Agent Plugins root plugin.json 'different-name' -> exit 1" 1 "$rc"
judge "  ... naming the root manifest" yes "$(has "$OUT" "plugins/$PLUGIN/plugin.json says 'different-name'")"

# ===========================================================================
section "Claude: the same name agreement, plus the documented source rules"
# ===========================================================================
d="$(fresh claude-mismatch)"
set_json "$d/plugins/$PLUGIN/.claude-plugin/plugin.json" '.name = "different-name"'
run "$d"; rc=$RC
judge "renamed .claude-plugin/plugin.json -> exit 1" 1 "$rc"
judge "  ... says install by name would resolve a different plugin" yes "$(has "$OUT" "install by name would resolve a different plugin")"

d="$(fresh claude-dotdot)"
set_json "$d/.claude-plugin/marketplace.json" '.plugins[0].source = "./plugins/../plugins/x"'
run "$d"; rc=$RC
judge "relative source containing '..' -> exit 1" 1 "$rc"
judge "  ... naming the escape" yes "$(has "$OUT" "contains '..'")"

d="$(fresh claude-missing-dir)"
set_json "$d/.claude-plugin/marketplace.json" '.plugins[0].source = "./plugins/not-there"'
run "$d"; rc=$RC
judge "relative source whose directory does not exist -> exit 1" 1 "$rc"
judge "  ... quoting the install-time error" yes "$(has "$OUT" "Source path does not exist")"

d="$(fresh claude-bad-kind)"
set_json "$d/.claude-plugin/marketplace.json" '.plugins[0].source = {"source":"gitlab","repo":"a/b"}'
run "$d"; rc=$RC
judge "an undocumented source kind -> exit 1" 1 "$rc"

d="$(fresh claude-space-name)"
set_json "$d/.claude-plugin/marketplace.json" '.name = "my marketplace"'
run "$d"; rc=$RC
judge "a marketplace name with a space -> exit 1" 1 "$rc"

# ===========================================================================
section "Cursor: kebab-case and path sources"
# ===========================================================================
d="$(fresh cursor-caps)"
set_json "$d/.cursor-plugin/marketplace.json" '.plugins[0].name = "Starter_Plugin"'
set_json "$d/.cursor-plugin/marketplace.json" ".plugins[0].name = \"$PLUGIN\" | .name = \"My-Marketplace\""
run "$d"; rc=$RC
judge "a non-kebab-case marketplace name -> exit 1" 1 "$rc"
judge "  ... naming kebab-case" yes "$(has "$OUT" "kebab-case")"

d="$(fresh cursor-abs)"
set_json "$d/.cursor-plugin/marketplace.json" '.plugins[0].source = "/plugins/x"'
run "$d"; rc=$RC
judge "an absolute path source -> exit 1" 1 "$rc"

# ===========================================================================
section "metadata.pluginRoot and symlinks: the resolved directory must be inside the checkout"
# ===========================================================================
# Codex-review repro (round 3): Cursor pluginRoot "../outside", the starter plugin moved
# there, entry source = its bare directory name. The entry passed the '..' check and the
# prefix was joined afterwards, so a catalog whose files would not accompany a clone
# validated clean. The same join exists on the Claude side.
d="$(fresh cursor-root-escape)"
mkdir -p "$TMP/outside" && cp -R "$d/plugins/$PLUGIN" "$TMP/outside/$PLUGIN"
set_json "$d/.cursor-plugin/marketplace.json" ".metadata.pluginRoot = \"../outside\" | .plugins[0].source = \"$PLUGIN\""
run "$d"; rc=$RC
judge "Cursor pluginRoot '../outside' + bare-name source -> exit 1" 1 "$rc"
judge "  ... blaming pluginRoot, before any entry is resolved under it" yes "$(has "$OUT" "metadata.pluginRoot '../outside' contains '..'")"

d="$(fresh claude-root-escape)"
set_json "$d/.claude-plugin/marketplace.json" ".metadata.pluginRoot = \"../outside\" | .plugins[0].source = \"$PLUGIN\""
run "$d"; rc=$RC
judge "Claude pluginRoot '../outside' + bare-name source -> exit 1" 1 "$rc"
judge "  ... blaming pluginRoot" yes "$(has "$OUT" "metadata.pluginRoot '../outside' contains '..'")"

d="$(fresh claude-root-abs)"
set_json "$d/.claude-plugin/marketplace.json" ".metadata.pluginRoot = \"$TMP/outside\" | .plugins[0].source = \"$PLUGIN\""
run "$d"; rc=$RC
judge "an absolute pluginRoot -> exit 1" 1 "$rc"
judge "  ... named as absolute" yes "$(has "$OUT" "is absolute; relative paths only")"

d="$(fresh claude-root-missing)"
set_json "$d/.claude-plugin/marketplace.json" ".metadata.pluginRoot = \"./nowhere\" | .plugins[0].source = \"$PLUGIN\""
run "$d"; rc=$RC
judge "a pluginRoot directory that does not exist -> exit 1" 1 "$rc"

d="$(fresh root-ok)"
set_json "$d/.claude-plugin/marketplace.json" ".metadata.pluginRoot = \"./plugins\" | .plugins[0].source = \"$PLUGIN\""
set_json "$d/.cursor-plugin/marketplace.json" ".metadata.pluginRoot = \"plugins\" | .plugins[0].source = \"$PLUGIN\""
run "$d"; rc=$RC
judge "positive control: a valid pluginRoot with bare-name sources on Claude and Cursor -> exit 0" 0 "$rc"

# A symlink under plugins/ is the other way a textually clean path leaves the checkout.
for platform in claude cursor codex; do
  d="$(fresh symlink-$platform)"
  mkdir -p "$TMP/elsewhere" && rm -rf "$TMP/elsewhere/$PLUGIN" && cp -R "$d/plugins/$PLUGIN" "$TMP/elsewhere/$PLUGIN"
  ln -s "$TMP/elsewhere/$PLUGIN" "$d/plugins/linked"
  case "$platform" in
    claude) set_json "$d/.claude-plugin/marketplace.json" '.plugins[0].source = "./plugins/linked"' ;;
    cursor) set_json "$d/.cursor-plugin/marketplace.json" '.plugins[0].source = "plugins/linked"' ;;
    codex)  set_json "$d/.agents/plugins/marketplace.json" '.plugins[0].source.path = "./plugins/linked"' ;;
  esac
  run "$d"; rc=$RC
  judge "$platform: a source that is a symlink to outside the checkout -> exit 1" 1 "$rc"
  judge "  ... naming the escape" yes "$(has "$OUT" "outside the marketplace root")"
done

d="$(fresh symlink-inside)"
ln -s "$PLUGIN" "$d/plugins/alias"
set_json "$d/.claude-plugin/marketplace.json" '.plugins[0].source = "./plugins/alias"'
run "$d"; rc=$RC
judge "positive control: a symlink that stays inside the checkout -> exit 0" 0 "$rc"

d="$(fresh codex-abs)"
set_json "$d/.agents/plugins/marketplace.json" ".plugins[0].source.path = \"$TMP/outside/$PLUGIN\""
run "$d"; rc=$RC
judge "Codex: an absolute local path -> exit 1" 1 "$rc"

# ===========================================================================
section "empty sources name no plugin (#375)"
# An empty string source skipped every local-source check (Codex) or resolved to
# metadata.pluginRoot itself (Claude); both passed while naming no plugin.
d="$(fresh codex-empty-string)"
set_json "$d/.agents/plugins/marketplace.json" '.plugins[0].source = ""'
run "$d"; rc=$RC
judge "Codex: an empty string source -> exit 1" 1 "$rc"
judge "  ... saying the source is empty" yes "$(has "$OUT" "source is an empty string")"
d="$(fresh claude-empty-under-root)"
set_json "$d/.claude-plugin/marketplace.json" '.metadata.pluginRoot = "./plugins" | .plugins[0].source = ""'
run "$d"; rc=$RC
judge "Claude: an empty source under metadata.pluginRoot -> exit 1" 1 "$rc"
judge "  ... saying the source is empty" yes "$(has "$OUT" "source is empty")"
d="$(fresh cursor-empty-string)"
set_json "$d/.cursor-plugin/marketplace.json" '.plugins[0].source = ""'
run "$d"; rc=$RC
judge "Cursor: an empty string source -> exit 1 (already rejected; held)" 1 "$rc"

section "cross-catalog agreement: the Claude list is canonical"
# ===========================================================================
d="$(fresh codex-extra)"
set_json "$d/.agents/plugins/marketplace.json" \
  '.plugins += [{"name":"only-in-codex","source":{"source":"npm","package":"x"},"policy":{"installation":"AVAILABLE","authentication":"ON_INSTALL"},"category":"Developer Tools"}]'
run "$d"; rc=$RC
judge "a plugin in the Codex catalog but not the Claude one -> exit 1" 1 "$rc"
judge "  ... naming the Claude catalog as canonical" yes "$(has "$OUT" "canonical list")"

d="$(fresh claude-only)"
set_json "$d/.claude-plugin/marketplace.json" \
  '.plugins += [{"name":"claude-only","source":{"source":"github","repo":"owner/repo"}}]'
run "$d"; rc=$RC
judge "a Claude-only plugin (hooks, MCP) is a warning, not an error -> exit 0" 0 "$rc"
judge "  ... and the warning names it" yes "$(has "$OUT" "'claude-only' is in .claude-plugin/marketplace.json but not in")"

# ===========================================================================
section "Codex entry policy"
# ===========================================================================
d="$(fresh codex-policy)"
set_json "$d/.agents/plugins/marketplace.json" '.plugins[0].policy.installation = "SOMETIMES"'
run "$d"; rc=$RC
judge "an undocumented policy.installation value -> exit 1" 1 "$rc"
judge "  ... listing the documented values" yes "$(has "$OUT" "INSTALLED_BY_DEFAULT")"

d="$(fresh codex-no-category)"
set_json "$d/.agents/plugins/marketplace.json" 'del(.plugins[0].category)'
run "$d"; rc=$RC
judge "a Codex entry without category -> exit 1" 1 "$rc"

harness_summary
