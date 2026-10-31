#!/usr/bin/env bash
# test-opencode-v2.sh — the OpenCode 2 adapter contract.
#
# WHAT THIS PINS
#   OpenCode 2 "does not run V1 plugin implementations", deprecated the 15-key
#   `permission` map, changed the default agent mode to `primary`, allows
#   `external_directory` by default where V1 asked, and resolves `skills` paths
#   from the working directory. Each of those is a way for an adapter that still
#   LOADS to silently mean something else. So every V2-specific shape is asserted
#   here, against the generated files OpenCode actually reads, not against the
#   generator's intentions:
#
#     1. Generated agents: `.opencode/agents/` (plural), `mode: subagent` explicit,
#        a `permissions:` ruleset whose actions are all OpenCode 2 Core actions,
#        an `external_directory: ask` rule, no V1 `permission:` map, no `bash`/
#        `task`/`doom_loop`/`lsp`/`list`/`todowrite`, and no ALLOW rule (an allow
#        appended after the base policy overrides the host's `.env` asks — measured
#        on 2.0.32, see the generator header).
#     2. Generated commands: `subagent:` not the deprecated `subtask:`.
#     3. opencode.json: `plugins[]` names the plugin directory, `mcp.servers.github`
#        is a `local` server with the token taken from the environment, the static
#        `permissions` carry the three invariants, and the file validates against
#        the published schema when the network allows (skipped with notice offline).
#     4. The plugin: its pure rules pass their Node unit tests (no install needed),
#        and the TypeScript type-checks against @opencode/plugin when npm can fetch
#        it (skipped with notice offline).
#     5. The usage-capture plugin is a V2 `{ id, setup }` export that produces the
#        documented records from V2 events.
#
# Hermetic: writes only under a temp dir; the network-dependent cases skip, never
# fail, when offline. Exit 0 if all pass, 1 otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"

harness_require jq python3 node
cd "$ROOT" || exit 1

AGENTS="$ROOT/.opencode/agents"
COMMANDS="$ROOT/.opencode/commands"
CONFIG="$ROOT/opencode.json"
PLUGIN="$ROOT/platforms/opencode/plugin"

# OpenCode 2 Core permission actions — https://opencode.ai/v2/docs/permissions/,
# read 2026-10-17. Pinned here independently of the generator and of
# scripts/check-opencode-permission-keys.sh, so a drift in either shows up as a
# disagreement rather than as two copies of one mistake.
V2_ACTIONS=" read edit glob grep shell subagent skill question webfetch websearch external_directory execute "
V1_ONLY=" bash task doom_loop lsp list todowrite write "

# frontmatter <file> — the YAML block between the first two `---` lines.
frontmatter() { awk 'NR==1&&/^---/{fm=1;next} fm&&/^---/{exit} fm{print}' "$1"; }

section "generators: --check passes (no drift, no stale OpenCode 1 tree)"
out="$(bash scripts/build-opencode-agents.sh "$ROOT" --check 2>&1)"
judge "build-opencode-agents.sh --check" 0 $?
out="$(bash scripts/build-opencode-commands.sh "$ROOT" --check 2>&1)"
judge "build-opencode-commands.sh --check" 0 $?
out="$(bash scripts/check-opencode-permission-keys.sh "$ROOT" 2>&1)"
judge "check-opencode-permission-keys.sh" 0 $?
judge "no OpenCode 1 .opencode/agent/ (singular) tree remains" no "$(exists "$ROOT/.opencode/agent")"

section ".opencode/agents: every adapter is OpenCode 2 shaped"
n_src="$(find "$ROOT/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
n_gen="$(find "$AGENTS" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
judge "one adapter per canonical agent in .opencode/agents/" "$n_src" "$n_gen"

for f in "$AGENTS"/*.md; do
  [ -e "$f" ] || continue
  b="$(basename "$f" .md)"
  fm="$(frontmatter "$f")"
  judge "$b: mode is explicit subagent (V2 defaults a custom agent to primary)" yes \
    "$(if printf '%s\n' "$fm" | grep -q '^mode: subagent$'; then echo yes; else echo no; fi)"
  judge "$b: no V1 'permission:' map" no \
    "$(if printf '%s\n' "$fm" | grep -q '^permission:'; then echo yes; else echo no; fi)"
  judge "$b: no deprecated 'tools:' object" no \
    "$(if printf '%s\n' "$fm" | grep -q '^tools:'; then echo yes; else echo no; fi)"
  # Only agents whose canonical file declares a tools: allowlist carry rules.
  if frontmatter "$ROOT/agents/$b.md" | grep -q '^tools:'; then
    judge "$b: has a 'permissions:' ruleset" yes \
      "$(if printf '%s\n' "$fm" | grep -q '^permissions:$'; then echo yes; else echo no; fi)"
    actions="$(printf '%s\n' "$fm" | sed -n 's/^  - action:[[:space:]]*//p')"
    bad_actions=""; v1_actions=""
    for a in $actions; do
      case "$V2_ACTIONS" in *" $a "*) ;; *) bad_actions="$bad_actions $a" ;; esac
      case "$V1_ONLY" in *" $a "*) v1_actions="$v1_actions $a" ;; esac
    done
    judge "$b: every rule action is an OpenCode 2 Core action" "" "$bad_actions"
    judge "$b: no V1-only action (bash/task/doom_loop/lsp/list/todowrite/write)" "" "$v1_actions"
    judge "$b: rule effects are allow|deny|ask only" "" \
      "$(printf '%s\n' "$fm" | sed -n 's/^    effect:[[:space:]]*//p' | grep -vE '^(allow|deny|ask)$' | tr '\n' ' ')"
    judge "$b: every rule has resource \"*\"" "" \
      "$(printf '%s\n' "$fm" | sed -n 's/^    resource:[[:space:]]*//p' | grep -vx '"\*"' | tr '\n' ' ')"
    judge "$b: external_directory is an explicit ask rule (V2 allows it by default)" yes \
      "$(if printf '%s\n' "$fm" | tr '\n' ' ' | grep -q 'action: external_directory *resource: "\*" *effect: ask'; then echo yes; else echo no; fi)"
    judge "$b: at least one deny rule (the allowlist is expressed as denies)" yes \
      "$(if printf '%s\n' "$fm" | grep -q '^    effect: deny$'; then echo yes; else echo no; fi)"
    judge "$b: no allow rule (would override the base policy's .env asks — last match wins)" no \
      "$(if printf '%s\n' "$fm" | grep -q '^    effect: allow$'; then echo yes; else echo no; fi)"
    # The translation itself: a canonical tool not granted must be a deny; a
    # granted one must NOT be denied.
    tools="$(frontmatter "$ROOT/agents/$b.md" | sed -n 's/^tools:[[:space:]]*//p' | tr ',' ' ' | tr '[:upper:]' '[:lower:]')"
    has_bash=no; has_edit=no
    for t in $tools; do
      case "$t" in bash) has_bash=yes ;; edit|write|multiedit) has_edit=yes ;; esac
    done
    denied="$(printf '%s\n' "$fm" | tr '\n' ' ' | grep -oE 'action: [a-z_]+ *resource: "\*" *effect: deny' | sed 's/action: \([a-z_]*\).*/\1/' | tr '\n' ' ')"
    if [ "$has_bash" = yes ]; then judge "$b: Bash granted -> shell is not denied" no "$(has " $denied " " shell ")"
    else judge "$b: no Bash -> shell is denied" yes "$(has " $denied " " shell ")"; fi
    if [ "$has_edit" = yes ]; then judge "$b: Edit/Write granted -> edit is not denied" no "$(has " $denied " " edit ")"
    else judge "$b: no Edit/Write -> edit is denied" yes "$(has " $denied " " edit ")"; fi
  fi
done

section ".opencode/commands: V2 frontmatter"
n_sub="$(grep -l '^subagent:' "$COMMANDS"/*.md 2>/dev/null | wc -l | tr -d ' ')"
n_cmd="$(find "$COMMANDS" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
judge "every command carries 'subagent:' ($n_cmd commands)" "$n_cmd" "$n_sub"
judge "no command carries the deprecated 'subtask:'" "" "$(grep -l '^subtask:' "$COMMANDS"/*.md 2>/dev/null | tr '\n' ' ')"
judge "no command body uses an @path attachment (V2 no longer expands it)" "" "$(grep -lE '(^|[[:space:]])@[A-Za-z0-9_./-]+' "$COMMANDS"/*.md 2>/dev/null | tr '\n' ' ')"

section "opencode.json: OpenCode 2 config"
judge "opencode.json is valid JSON" 0 "$(jq empty "$CONFIG" >/dev/null 2>&1; echo $?)"
judge "declares the plugin directory under plugins[]" yes \
  "$(if jq -e '.plugins | index("./platforms/opencode/plugin")' "$CONFIG" >/dev/null 2>&1; then echo yes; else echo no; fi)"
judge "the plugin directory has a server entrypoint (index.ts)" yes "$(exists "$PLUGIN/index.ts")"
judge "the plugin directory has a TUI entrypoint (tui.ts)" yes "$(exists "$PLUGIN/tui.ts")"
judge "mcp.servers.github is a local server" local "$(jq -r '.mcp.servers.github.type // ""' "$CONFIG")"
judge "mcp.servers.github runs scripts/github-mcp.sh" yes \
  "$(if jq -e '.mcp.servers.github.command == ["bash","scripts/github-mcp.sh"]' "$CONFIG" >/dev/null 2>&1; then echo yes; else echo no; fi)"
judge "mcp.servers.github takes the token from the environment, never a literal" '{env:GITHUB_PERSONAL_ACCESS_TOKEN}' \
  "$(jq -r '.mcp.servers.github.environment.GITHUB_PERSONAL_ACCESS_TOKEN // ""' "$CONFIG")"
judge "no V1 'mcp.<name>' entry outside mcp.servers" "" "$(jq -r '.mcp | keys[] | select(. != "servers" and . != "timeout")' "$CONFIG" | tr '\n' ' ')"
judge "no deprecated V1 'plugin' / 'permission' / 'agent' / 'command' keys" "" \
  "$(jq -r 'keys[] | select(. == "plugin" or . == "permission" or . == "agent" or . == "command")' "$CONFIG" | tr '\n' ' ')"
judge "static permissions deny editing lockfiles" yes \
  "$(if jq -e '.permissions[] | select(.action=="edit" and .resource=="*package-lock.json" and .effect=="deny")' "$CONFIG" >/dev/null 2>&1; then echo yes; else echo no; fi)"
judge "static permissions deny editing GitHub workflows" yes \
  "$(if jq -e '.permissions[] | select(.action=="edit" and .resource==".github/workflows/*" and .effect=="deny")' "$CONFIG" >/dev/null 2>&1; then echo yes; else echo no; fi)"
judge "static permissions deny a force push" yes \
  "$(if jq -e '.permissions[] | select(.action=="shell" and (.resource|startswith("git push --force")) and .effect=="deny")' "$CONFIG" >/dev/null 2>&1; then echo yes; else echo no; fi)"
judge "static permissions restore the external_directory prompt" yes \
  "$(if jq -e '.permissions[] | select(.action=="external_directory" and .effect=="ask")' "$CONFIG" >/dev/null 2>&1; then echo yes; else echo no; fi)"
judge "every static rule uses an OpenCode 2 Core action" "" \
  "$(jq -r '.permissions[].action' "$CONFIG" | while read -r a; do case "$V2_ACTIONS" in *" $a "*) ;; *) printf '%s ' "$a" ;; esac; done)"
judge "no 'policies' key (admin-only layer, not a plugin's to set)" no "$(if jq -e '.policies' "$CONFIG" >/dev/null 2>&1; then echo yes; else echo no; fi)"

# Schema validation needs the published schema and a validator; both optional.
tmp="$(harness_tmpdir)"
if curl -fsS --max-time 20 https://opencode.ai/config.json -o "$tmp/schema.json" 2>/dev/null; then
  if python3 -I -c 'import jsonschema' 2>/dev/null; then
    out="$(python3 -I - "$tmp/schema.json" "$CONFIG" <<'PY' 2>&1
import json, sys, jsonschema
schema = json.load(open(sys.argv[1])); cfg = json.load(open(sys.argv[2]))
errs = sorted(jsonschema.Draft202012Validator(schema).iter_errors(cfg), key=lambda e: list(e.path))
for e in errs[:5]:
    print("/".join(str(p) for p in e.path) or "<root>", ":", e.message[:160])
sys.exit(1 if errs else 0)
PY
)"
    judge "opencode.json validates against the published schema" "" "$out"
  else
    skip "opencode.json validates against the published schema" "python3 jsonschema module not installed"
  fi
  # Structural facts the schema encodes, checked without a validator.
  judge "published schema: Permission.Rule requires action/resource/effect" '["action","effect","resource"]' \
    "$(jq -c '."$defs"."Permission.Rule".required | sort' "$tmp/schema.json")"
  judge "published schema: top-level 'permission' (V1) is deprecated" true "$(jq -r '.properties.permission.deprecated // false' "$tmp/schema.json")"
  judge "published schema: mcp.servers accepts a local server" yes \
    "$(if jq -e '.properties.mcp.properties.servers' "$tmp/schema.json" >/dev/null 2>&1; then echo yes; else echo no; fi)"
else
  skip "opencode.json validates against the published schema" "https://opencode.ai/config.json unreachable (offline)"
fi

section "platforms/opencode/plugin: pure rules (Node, no install)"
out="$(node --test "$PLUGIN/rules.test.mjs" 2>&1)"
rc=$?
judge "rules.test.mjs passes (node --test)" 0 "$rc"
[ "$rc" -eq 0 ] || printf '%s\n' "$out" | tail -40
judge "rules.ts is pure (no node: imports, no process access)" "" \
  "$(grep -nE 'from "node:|require\(|process\.' "$PLUGIN/rules.ts" | tr '\n' ' ')"
judge "guard.ts registers the permission evaluate hook" yes "$(has "$(cat "$PLUGIN/guard.ts")" 'ctx.permission.hook("evaluate"')"
judge "guard.ts registers the shell create.before hook" yes "$(has "$(cat "$PLUGIN/guard.ts")" 'ctx.shell.hook("create.before"')"
judge "guard.ts is a V2 Plugin.define export" yes "$(has "$(cat "$PLUGIN/guard.ts")" 'Plugin.define({')"
judge "tui.tsx is a V2 TUI Plugin.define export" yes "$(has "$(cat "$PLUGIN/tui.tsx")" 'from "@opencode/plugin/tui"')"
judge "tui.tsx fills prompt.footer.status" yes "$(has "$(cat "$PLUGIN/tui.tsx")" '"prompt.footer.status"')"
judge "tui.tsx contributes session.panel" yes "$(has "$(cat "$PLUGIN/tui.tsx")" '"session.panel"')"
judge "no shipped plugin file uses eval" "" "$(grep -lE '\beval\(' "$PLUGIN"/*.ts "$PLUGIN"/*.tsx 2>/dev/null | tr '\n' ' ')"
judge "package.json has the tsc --noEmit check script" yes "$(has "$(jq -r '.scripts.check // ""' "$PLUGIN/package.json")" 'tsc --noEmit')"
judge "package.json names @opencode/plugin as a peer dependency" yes \
  "$(if jq -e '.peerDependencies["@opencode/plugin"]' "$PLUGIN/package.json" >/dev/null 2>&1; then echo yes; else echo no; fi)"

section "platforms/opencode/plugin: TypeScript type-check (npm, network)"
# A scratch copy next to a scratch node_modules: nothing is written under the repo.
if harness_have npm && [ "${TAMIRS_SKIP_NPM:-0}" != "1" ]; then
  mkdir -p "$tmp/tc"
  cp "$PLUGIN"/*.ts "$PLUGIN"/*.tsx "$PLUGIN"/package.json "$PLUGIN"/tsconfig.json "$tmp/tc/"
  if (cd "$tmp/tc" && npm install --no-audit --no-fund --no-package-lock >"$tmp/npm.log" 2>&1); then
    out="$(cd "$tmp/tc" && ./node_modules/.bin/tsc --noEmit -p tsconfig.json 2>&1)"
    rc=$?
    judge "tsc --noEmit against @opencode/plugin $(jq -r '.devDependencies["@opencode/plugin"]' "$PLUGIN/package.json")" 0 "$rc"
    [ "$rc" -eq 0 ] || printf '%s\n' "$out" | head -30
  else
    skip "tsc --noEmit against @opencode/plugin" "npm install failed (offline?): $(tail -1 "$tmp/npm.log")"
  fi
else
  skip "tsc --noEmit against @opencode/plugin" "npm not available or TAMIRS_SKIP_NPM=1"
fi

section "usage-capture: V2 plugin shape and record format"
out="$(node --input-type=module -e '
import mod, { recordFor } from "'"$ROOT"'/skills/toolkit/usage-capture/opencode-plugin.mjs"
const models = new Map()
const recs = [
  { type: "session.created", data: { sessionID: "s1", model: { providerID: "anthropic", id: "m" } } },
  { type: "session.skill.activated", data: { sessionID: "s1", id: "plan-dev", name: "plan-dev", text: "" } },
  { type: "session.step.ended", data: { sessionID: "s1", assistantMessageID: "a1", finish: "stop", cost: 0.5, tokens: { input: 10, output: 5, reasoning: 0, cache: { read: 3, write: 2 } } } },
  { type: "session.text.delta", data: { sessionID: "s1" } },
].map((e) => recordFor(e, models))
const shape = typeof mod.id === "string" && typeof mod.setup === "function"
const seen = new Set()
let calls = 0
async function* gen() { for (const e of [{ type: "session.created", data: { sessionID: "s2" } }]) yield e }
const cleanup = mod.setup({ event: { subscribe: () => { calls++; return gen() } } })
console.log(JSON.stringify({ shape, cleanup: typeof cleanup, subscribed: calls, recs }))
' 2>&1)"
judge "default export is { id, setup } (V2 Plugin.define shape)" true "$(printf '%s' "$out" | jq -r '.shape // "parse-error"' 2>/dev/null)"
judge "setup subscribes via ctx.event.subscribe() and returns a cleanup" "1 function" "$(printf '%s' "$out" | jq -r '"\(.subscribed) \(.cleanup)"' 2>/dev/null)"
judge "session.created -> session_start" session_start "$(printf '%s' "$out" | jq -r '.recs[0].event' 2>/dev/null)"
judge "session.skill.activated -> skill_activated with skill_name" "skill_activated plan-dev" "$(printf '%s' "$out" | jq -r '"\(.recs[1].event) \(.recs[1].skill_name)"' 2>/dev/null)"
judge "session.step.ended -> api_request with tokens, cost, model, stop_reason" "api_request 10 5 3 2 0.5 anthropic/m stop true" \
  "$(printf '%s' "$out" | jq -r '.recs[2] | "\(.event) \(.input_tokens) \(.output_tokens) \(.cache_read_tokens) \(.cache_creation_tokens) \(.cost_usd) \(.model) \(.stop_reason) \(.success)"' 2>/dev/null)"
judge "an unrelated event produces no record" null "$(printf '%s' "$out" | jq -r '.recs[3]' 2>/dev/null)"
judge "no V1 hook names remain in the plugin" "" "$(grep -nE '"chat\.params"|"experimental\.chat|"tool\.execute\.before"|"permission\.ask"' "$ROOT/skills/toolkit/usage-capture/opencode-plugin.mjs" | tr '\n' ' ')"
judge "the plugin still imports nothing at module scope" "" "$(grep -nE '^import ' "$ROOT/skills/toolkit/usage-capture/opencode-plugin.mjs" | tr '\n' ' ')"

section "live OpenCode CLI (optional)"
ver=""
harness_have opencode && ver="$(opencode --version 2>/dev/null | head -1)"
if harness_have opencode; then
  printf '  ..   %s detected\n' "$ver"
  plist="$(cd "$ROOT" && opencode plugin list 2>/dev/null)"
  judge "opencode plugin list shows the guard plugin" yes "$(has "$plist" 'tamirs-superpowers.guard')"
  agents_json="$(cd "$ROOT" && opencode debug agents 2>/dev/null)"
  judge "opencode debug agents lists every generated adapter" "$n_src" \
    "$(printf '%s' "$agents_json" | jq '[.[] | select(.system // "" | contains("GENERATED FILE"))] | length' 2>/dev/null)"
  judge "a generated adapter resolves with external_directory ask after the base policy" ask \
    "$(printf '%s' "$agents_json" | jq -r '[.[] | select(.id=="implementer")][0].permissions | map(select(.action=="external_directory"))[-1].effect // "missing"' 2>/dev/null)"
else
  skip "live OpenCode CLI" "opencode not on PATH"
fi

harness_summary
