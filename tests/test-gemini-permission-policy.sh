#!/usr/bin/env bash
# test-gemini-permission-policy.sh — the Gemini CLI half of ADR 004's permission layer
# (items 4 and 7; D3, D7, D8, D10.5).
#
# WHAT IT HOLDS
#   1. platforms/gemini/policies/tamirs-superpowers-permissions.toml is generated from
#      policies.source.json `permission_rules` and in sync; the generator refuses an
#      allow, a `modes` key, an ask_user on anything but R4, an unknown regex macro and
#      an ask_user priority that is not below the deny priority.
#   2. The generated policies never allow, carry no `modes`, put every deny above every
#      ask_user, name only catalog ids, give ask_user only to R4 ids, and cover every R4
#      id of core/permissions/actions.json (or name it as not expressible). No deny text
#      points at the GitHub MCP write tool or at PM_ALLOW_PROTECTED (D10.5).
#   3. Behaviour: a model of Gemini 0.60.0's policy engine (stable-stringified
#      arguments with NUL-wrapped top-level pairs, commandRegex as `"command":"<re>`,
#      mcpName + toolName -> mcp_<server>_<tool>, highest priority first, a compound
#      shell command checked part by part) answers ask_user for the R4 forms, deny for
#      the denied forms, and nothing for ordinary commands.
#   4. platforms/gemini/hooks.json wires hooks/permission-guard.sh on BeforeTool
#      run_shell_command through gemini-wrap.sh; the GitHub MCP matcher group is left
#      out, never turned into a match-all.
#   5. The guard in the Gemini dialect never answers ask (a hook ask hangs a headless
#      run, G1): every call that asks on Claude Code is a deny through gemini-wrap.sh,
#      at supervised and at unattended (TS_PERMISSION_LEVEL in the extension .env).
#   6. TS_PERMISSION_LEVEL: platforms/manifests.source.json and gemini-extension.json
#      agree, the setting is a plain (non-keychain) string whose description lists the
#      three levels and says the plugin validates it, and the resolver reads that name.
#
# HERMETIC
#   The resolver reads the passwd home, never HOME, and honours its test override
#   TAMIRS_PERMISSION_TEST_ROOT only under an ancestor process running a file named
#   test-resolve-permission.sh, so every guard run here goes through a wrapper of that
#   name in the temp dir. The suite stops if the override did not take. No Gemini
#   binary, no network, no login.
#
# Needs jq, git and python3 >= 3.11 (tomllib). Bash 3.2 compatible.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
harness_require jq git python3
python3 -c 'import tomllib' >/dev/null 2>&1 || { echo "FATAL: python3 >= 3.11 (tomllib) is required"; exit 1; }

GEN="$ROOT/scripts/build-gemini-hooks.sh"
WRAP="$ROOT/hooks/gemini-wrap.sh"
PG="$ROOT/hooks/permission-guard.sh"
HOOKS="$ROOT/platforms/gemini/hooks.json"
SRC="$ROOT/platforms/gemini/policies.source.json"
LEGACY="$ROOT/platforms/gemini/policies/tamirs-superpowers.toml"
PERM="$ROOT/platforms/gemini/policies/tamirs-superpowers-permissions.toml"
CATALOG="$ROOT/core/permissions/actions.json"
MCP_TOKEN='mcp__plugin_tamirs-superpowers_github__.*'

T="$(harness_tmpdir)"
T="$(cd "$T" && pwd -P)"
chmod 700 "$T"

assert_exit() {
  local name="$1" want="$2"; shift 2
  local out got
  out=$("$@" 2>&1); got=$?
  if [ "$got" -eq "$want" ]; then ok "$name"; else bad "$name" "expected exit $want, got $got: ${out:0:300}"; fi
}

# A scratch copy of what the generator reads (it takes the root as an argument).
make_copy() {
  local dst="$1"
  mkdir -p "$dst/platforms/gemini/policies" "$dst/scripts"
  cp -R "$ROOT/hooks" "$dst/hooks"
  cp "$ROOT/scripts/notify-pushover.sh" "$dst/scripts/notify-pushover.sh"
  cp "$SRC" "$dst/platforms/gemini/"
}
edit_json() { local f="$1" q="$2"; jq "$q" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }

# --------------------------------------------------------------------------------
section "generator: in sync, and refuses what could widen"
assert_exit "build-gemini-hooks.sh --check passes (hooks.json and both policy files)" 0 bash "$GEN" "$ROOT" --check
judge "the permissions policy file exists" yes "$(exists "$PERM")"

C="$T/perm-drift"; make_copy "$C"; bash "$GEN" "$C" >/dev/null 2>&1
edit_json "$C/platforms/gemini/policies.source.json" '.permission_rules[0].denyMessage = "changed"'
assert_exit "an edited permission rule without a regenerate fails --check" 1 bash "$GEN" "$C" --check

C="$T/perm-allow"; make_copy "$C"
edit_json "$C/platforms/gemini/policies.source.json" '.permission_rules[0].decision = "allow"'
assert_exit "a permission rule with decision allow is exit 2" 2 bash "$GEN" "$C"

C="$T/perm-modes"; make_copy "$C"
edit_json "$C/platforms/gemini/policies.source.json" '.permission_rules[0].modes = ["default"]'
assert_exit "a permission rule with modes is exit 2 (a mode-scoped rule does not hold everywhere)" 2 bash "$GEN" "$C"

C="$T/perm-ask-r3"; make_copy "$C"
edit_json "$C/platforms/gemini/policies.source.json" '(.permission_rules[] | select(.decision == "ask_user") | .r) |= 3'
assert_exit "an ask_user on an R3 action is exit 2 (only R4 asks at every level)" 2 bash "$GEN" "$C"

C="$T/perm-prio"; make_copy "$C"
edit_json "$C/platforms/gemini/policies.source.json" '.ask_user_priority = .priority'
assert_exit "an ask_user priority not below the deny priority is exit 2" 2 bash "$GEN" "$C"

C="$T/perm-macro"; make_copy "$C"
edit_json "$C/platforms/gemini/policies.source.json" '.permission_rules[0].commandRegex = "%NOPE%git"'
assert_exit "an unknown regex macro is exit 2" 2 bash "$GEN" "$C"

C="$T/perm-redos"; make_copy "$C"
edit_json "$C/platforms/gemini/policies.source.json" '.permission_rules[0].commandRegex = "(?:FOO=1\\s+)?git\\s+commit\\s--no-verify"'
assert_exit "a pattern Gemini drops as a potential ReDoS (a quantifier after a group) is exit 2" 2 bash "$GEN" "$C"

C="$T/perm-key"; make_copy "$C"
edit_json "$C/platforms/gemini/policies.source.json" '.permission_rules[0].allowRedirection = true'
assert_exit "an unknown permission-rule key is exit 2" 2 bash "$GEN" "$C"

# --------------------------------------------------------------------------------
section "generated policies: never allow, deny above ask, catalog ids, R4 coverage"
static="$(python3 -I - "$LEGACY" "$PERM" "$CATALOG" "$SRC" <<'PY' 2>&1
import json, re, sys, tomllib
legacy, perm, catalog, src = sys.argv[1:5]
cat = json.load(open(catalog))
by_id = {a["id"]: a for a in cat["actions"]}
problems = []
rules = []
for path in (legacy, perm):
    d = tomllib.load(open(path, "rb"))
    if set(d) != {"rule"}:
        problems.append("%s has keys %s besides [[rule]]" % (path, sorted(set(d) - {"rule"})))
    for r in d.get("rule", []):
        r["_file"] = path
        rules.append(r)
for r in rules:
    if r["decision"] not in ("deny", "ask_user"):
        problems.append("a %s rule in %s" % (r["decision"], r["_file"]))
    if "modes" in r:
        problems.append("a rule with modes: %r" % r)
    if not (0 <= r["priority"] <= 999):
        problems.append("priority out of range: %r" % r)
    pat = r.get("commandRegex") or r.get("argsPattern") or ""
    re.compile(pat)
    # Gemini 0.60.0 isSafeRegExp (packages/core/src/policy/utils.ts): such a rule is dropped.
    built = ('"command":"' + pat) if "commandRegex" in r else pat
    if len(built) > 2048 or re.search(r"\([^)]*[*+?{].*\)[*+?{]", built):
        problems.append("Gemini would drop this pattern as a potential ReDoS: %s" % built[:100])
denies = [r["priority"] for r in rules if r["decision"] == "deny"]
asks = [r["priority"] for r in rules if r["decision"] == "ask_user"]
if not asks or not denies:
    problems.append("expected both deny and ask_user rules")
elif max(asks) >= min(denies):
    problems.append("an ask_user (%d) is not below every deny (%d)" % (max(asks), min(denies)))
if any(r["decision"] != "deny" for r in rules if r["_file"] == legacy):
    problems.append("the guard-mirror file is not deny-only")
# action comments name catalog ids; ask_user only for R4
text = open(perm, encoding="utf-8").read()
blocks = text.split("[[rule]]")[1:]
covered = set()
for b in blocks:
    m = re.search(r"^# action: (.+) \(R(\d)\)$", b, re.M)
    if not m:
        problems.append("a permission rule without an action comment: %s" % b[:80]); continue
    ids = [x.strip() for x in m.group(1).split(",")]
    dec = re.search(r'^decision = "(\w+)"', b, re.M).group(1)
    for i in ids:
        if i not in by_id:
            problems.append("unknown catalog id %s" % i); continue
        covered.add(i)
        if dec == "ask_user" and by_id[i]["r"] != 4:
            problems.append("ask_user for %s, which is R%d in the catalog" % (i, by_id[i]["r"]))
s = json.load(open(src, encoding="utf-8"))
notexpr = " ".join(s.get("permission_not_expressible", []))
for a in cat["actions"]:
    if a["r"] == 4 and a["id"] not in covered and a["id"] not in notexpr:
        problems.append("R4 id %s has no static rule and is not named as not expressible" % a["id"])
# D10.5: no deny text points at the GitHub MCP write tool or the env switch
for r in rules:
    msg = r.get("denyMessage", "")
    for bad in ("create_or_update_file", "PM_ALLOW_PROTECTED", "MCP server (", "github MCP server"):
        if bad in msg:
            problems.append("denyMessage names %r: %s" % (bad, msg[:100]))
for r in s["rules"] + s["permission_rules"]:
    if "create_or_update_file" in (r.get("mirrors") or "") + r.get("denyMessage", ""):
        problems.append("source rule %s recommends create_or_update_file" % r["id"])
print("\n".join(problems) if problems else "ok %d rules (%d ask_user, %d deny)" % (len(rules), len(asks), len(denies)))
PY
)"
case "$static" in
  ok*) ok "static policy invariants hold ($static)" ;;
  *) bad "static policy invariants hold" "$static" ;;
esac

# --------------------------------------------------------------------------------
section "behaviour: a model of Gemini 0.60.0's policy engine over both files"
# Expected: ask (ask_user), deny, or - (no rule of this extension decides).
CASES="$T/cases.tsv"
cat > "$CASES" <<'TSV'
ask	shell	git commit --no-verify -m wip
ask	shell	git -C /r commit -nm wip
ask	shell	HUSKY=0 git commit -m wip
ask	shell	git -c core.hooksPath=/dev/null commit -m x
ask	shell	GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null GIT_CONFIG_COUNT=1 git commit -m x
ask	shell	git push --no-verify origin feat
ask	shell	gh pr merge 12 --admin --squash
ask	shell	git push --force-with-lease origin main
ask	shell	git push origin +main
ask	shell	git push origin +HEAD:refs/heads/master
ask	shell	git push --mirror origin
ask	shell	gh release create v1.2.0 --generate-notes
ask	shell	gh workflow run release.yml
ask	shell	git tag v1.2.0
ask	shell	git tag -a v1 -m x
ask	shell	git push origin --tags
ask	shell	git push origin refs/tags/v1
ask	shell	claude -p "hi"
ask	shell	gemini -p hi
ask	shell	/usr/local/bin/codex exec x
ask	shell	npx -y @google/gemini-cli -p x
ask	shell	bunx opencode run x
ask	shell	node ./node_modules/@anthropic-ai/claude-code/cli.js -p x
ask	shell	script -q /dev/null bash
ask	shell	tmux send-keys -t 0 y Enter
ask	shell	osascript -e 'tell application "System Events" to keystroke "y"'
ask	shell	python3 -c "import pty; pty.spawn('bash')"
ask	shell	gh repo create me/x --private
ask	shell	gh repo delete me/x --yes
ask	shell	gh repo fork o/r
ask	shell	bash skills/repo/github-policy/scripts/github-policy.sh apply --repo o/r
ask	shell	bash scripts/ensure-branch-protection.sh
ask	shell	gh api -X PUT repos/o/r/branches/main/protection --input p.json
ask	shell	gh api repos/o/r/rulesets -f name=x
ask	shell	gh api graphql -f query='mutation { createBranchProtectionRule(input: {}) { clientMutationId } }'
ask	shell	gh workflow disable ci.yml
ask	shell	git config --global user.name x
ask	shell	git config alias.co checkout
ask	shell	git -c alias.x=!sh x
ask	shell	gh alias set co 'pr checkout'
ask	shell	gh auth setup-git
ask	shell	bash scripts/setup.sh
ask	shell	./scripts/install.sh
ask	shell	bash skills/toolkit/usage-capture/enable.sh --bodies
ask	shell	bash scripts/capture-config.sh --adopt all
ask	shell	bash scripts/plugin-config.sh confirm 0123abcd
ask	shell	bash scripts/plugin-config.sh standard
ask	shell	scripts/plugin-config.sh pr.merge.auto allow
ask	shell	cd /r && git push --force-with-lease origin main
deny	shell	bash scripts/plugin-config.sh provision --level standard
deny	shell	gemini extensions config tamirs-superpowers TS_PERMISSION_LEVEL
deny	shell	claude plugin configure tamirs-superpowers
deny	shell	git push --force origin feat
deny	shell	git push origin feat -f
deny	shell	git push --force --no-verify origin x
deny	shell	git commit -m x && git push -f
deny	write_file	/home/u/.config/tamirs-superpowers/permissions.json
deny	write_file	/home/u/.local/state/tamirs-superpowers/seen/x
deny	write_file	/r/.tamirs-superpowers/permissions.json
deny	write_file	.tamirs-superpowers/permissions.json
deny	replace	/home/u/.gemini/settings.json
deny	write_file	/home/u/.gemini/policies/mine.toml
deny	write_file	/home/u/.gemini/extensions/tamirs-superpowers/.env
deny	write_file	/home/u/.claude/settings.local.json
deny	write_file	/home/u/.codex/config.toml
deny	write_file	/home/u/.cursor/hooks.json
deny	write_file	/home/u/.config/opencode/opencode.json
deny	write_file	/home/u/.config/gh/hosts.yml
deny	write_file	/home/u/.gitconfig
deny	write_file	/r/.git/hooks/pre-commit
deny	replace	/r/.git/config
deny	write_file	/r/.github/workflows/ci.yml
deny	mcp	merge_pull_request
deny	mcp	create_repository
deny	mcp	fork_repository
deny	mcp	delete_repository
deny	mcp	create_or_update_file
deny	mcp	push_files
deny	mcp	issue_write
deny	mcp	pull_request_review_write
-	shell	git status
-	shell	git push origin feat
-	shell	git push origin main
-	shell	git push --force-with-lease origin feat
-	shell	git commit -m wip
-	shell	git commit --amend --no-edit
-	shell	git log -n 5
-	shell	git branch -d topic
-	shell	gh pr create --fill
-	shell	gh pr merge 12 --auto --squash
-	shell	gh pr merge 12
-	shell	gh release view v1
-	shell	gh release list
-	shell	git tag
-	shell	git tag -l "v*"
-	shell	git tag --sort=-creatordate
-	shell	git tag -d v1
-	shell	npx prettier --check .
-	shell	npm exec -- eslint .
-	shell	node --test rules.test.mjs
-	shell	python3 -c "print(1)"
-	shell	bash scripts/build-gemini-hooks.sh . --check
-	shell	ls scripts/
-	shell	echo claude is here
-	shell	cat script.txt
-	shell	bash scripts/plugin-config.sh show
-	shell	bash scripts/plugin-config.sh --help
-	shell	git config user.name
-	shell	git config --get alias.co
-	shell	git config --global --list
-	shell	gh api repos/o/r/branches/main/protection
-	shell	gh api repos/o/r/rulesets
-	shell	gh workflow run ci.yml
-	shell	gh workflow view ci.yml
-	shell	bash scripts/ensure-branch-protection.sh --verify-only
-	shell	bash skills/repo/github-policy/scripts/github-policy.sh plan
-	shell	tmux ls
-	shell	gh repo view
-	shell	gh repo clone o/r
-	write_file	/r/src/app.ts
-	write_file	/r/.gemini/GEMINI.md
-	write_file	/home/u/.gemini/tmp/abc/plans/plan.md
-	write_file	/r/docs/settings.json
-	write_file	/r/platforms/cursor/hooks.json
-	write_file	/r/.github/CODEOWNERS
-	mcp	get_file_contents
-	mcp	create_pull_request
-	mcp	add_issue_comment
-	othermcp	merge_pull_request
TSV
behaviour="$(python3 -I - "$LEGACY" "$PERM" "$CASES" <<'PY' 2>&1
import json, re, sys, tomllib

def stable_stringify(args):
    # packages/core/src/policy/stable-stringify.ts (0.60.0): sorted keys, top-level pairs wrapped in NUL.
    return "{" + ",".join("\0" + json.dumps(k, ensure_ascii=False) + ":" + json.dumps(args[k], ensure_ascii=False,
                          separators=(",", ":")) + "\0" for k in sorted(args)) + "}"

rules = []
for path in sys.argv[1:3]:
    for r in tomllib.load(open(path, "rb"))["rule"]:
        names = r["toolName"] if isinstance(r["toolName"], list) else [r["toolName"]]
        if r.get("mcpName"):
            names = ["mcp_%s_%s" % (r["mcpName"], n) for n in names]
        pat = None
        if "commandRegex" in r:
            pat = re.compile('"command":"' + r["commandRegex"])
        elif "argsPattern" in r:
            pat = re.compile(r["argsPattern"])
        rules.append((2 + r["priority"] / 1000.0, names, r.get("mcpName"), pat, r["decision"]))
rules.sort(key=lambda x: -x[0])

def first_match(tool, args, server):
    s = stable_stringify(args)
    for prio, names, mcp, pat, dec in rules:
        if tool not in names:
            continue
        if mcp and server != mcp:
            continue
        if pat is not None and not pat.search(s):
            continue
        return dec
    return None

def split_shell(cmd):
    # Enough of the shell grammar for these samples: && || ; | and newlines outside quotes.
    parts, cur, q, i = [], "", "", 0
    while i < len(cmd):
        c = cmd[i]
        if q:
            cur += c
            if c == q:
                q = ""
        elif c in "'\"":
            q = c; cur += c
        elif cmd[i:i + 2] in ("&&", "||"):
            parts.append(cur); cur = ""; i += 1
        elif c in ";|\n":
            parts.append(cur); cur = ""
        else:
            cur += c
        i += 1
    parts.append(cur)
    return [p.strip() for p in parts if p.strip()]

RANK = {None: 0, "ask_user": 1, "deny": 2}

def decide_shell(cmd):
    top = first_match("run_shell_command", {"command": cmd}, None)
    if top == "deny":
        return "deny"
    parts = split_shell(cmd)
    if len(parts) == 1:
        return top
    worst = top
    for p in parts:
        d = first_match("run_shell_command", {"command": p}, None)
        if d == "deny":
            return "deny"
        if RANK[d] > RANK[worst]:
            worst = d
    return worst

fails, n = [], 0
for line in open(sys.argv[3], encoding="utf-8"):
    line = line.rstrip("\n")
    if not line:
        continue
    want, kind, subject = line.split("\t", 2)
    n += 1
    if kind == "shell":
        got = decide_shell(subject)
    elif kind in ("write_file", "replace"):
        got = first_match(kind, {"file_path": subject, "content": "x"} if kind == "write_file" else
                          {"file_path": subject, "old_string": "a", "new_string": "b", "instruction": "i"}, None)
    elif kind == "mcp":
        got = first_match("mcp_github_" + subject, {"owner": "o", "repo": "r"}, "github")
    else:
        got = first_match("mcp_other_" + subject, {"owner": "o", "repo": "r"}, "other")
    got = {None: "-", "ask_user": "ask", "deny": "deny"}[got]
    if got != want:
        fails.append("%s %r: expected %s, got %s" % (kind, subject, want, got))
print("\n".join(fails) if fails else "ok %d cases" % n)
PY
)"
case "$behaviour" in
  ok*) ok "every sample gets the decision ADR 004 gives it ($behaviour)" ;;
  *) bad "every sample gets the decision ADR 004 gives it" "$behaviour" ;;
esac

# The same table through Gemini CLI's OWN policy engine, when a local install is
# present (never in CI, never fetched): loadExtensionPolicies + the default policies
# + PolicyEngine.check from the installed bundle. This is what caught Gemini dropping
# every nested-quantifier pattern as a potential ReDoS, which the model above cannot.
gem_chunk=""
if [ "${TAMIRS_SKIP_GEMINI_ENGINE:-0}" != 1 ] && command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  gem_bundle="$(npm root -g 2>/dev/null)/@google/gemini-cli/bundle"
  if [ -d "$gem_bundle/policies" ]; then
    for f in "$gem_bundle"/*.js; do
      if grep -q '^  loadExtensionPolicies,$' "$f" 2>/dev/null && grep -q '^  PolicyEngine,$' "$f" 2>/dev/null &&
         grep -q '^  loadPoliciesFromToml,$' "$f" 2>/dev/null; then
        gem_chunk="$f"; break
      fi
    done
  fi
fi
if [ -n "$gem_chunk" ]; then
  cat > "$T/engine.mjs" <<'JS'
import { readFileSync } from "node:fs"
import path from "node:path"
import { pathToFileURL } from "node:url"
const [chunk, polDir, casesFile] = process.argv.slice(2)
const g = await import(pathToFileURL(chunk).href)
const defaults = await g.loadPoliciesFromToml([path.join(path.dirname(chunk), "policies")], () => 1)
const ext = await g.loadExtensionPolicies("tamirs-superpowers", polDir)
const out = []
for (const e of ext.errors ?? []) out.push(`load error: ${e.fileName}: ${e.message}: ${String(e.details).slice(0, 160)}`)
const cases = readFileSync(casesFile, "utf8").split("\n").filter(Boolean).map((l) => l.split("\t"))
let n = 0
// yolo is the discriminating mode (its allow-all is the only lower rule); default adds
// Gemini's own asks; headless the engine still answers ask_user and the scheduler
// refuses the call (packages/core/src/scheduler/policy.ts, checkPolicy).
for (const [mode, nonInteractive] of [["yolo", false], ["default", false], ["yolo", true]]) {
  const engine = new g.PolicyEngine({ rules: [...defaults.rules, ...ext.rules], approvalMode: mode, nonInteractive })
  for (const [want, kind, subject] of cases) {
    let call, server
    if (kind === "shell") call = { name: "run_shell_command", args: { command: subject } }
    else if (kind === "write_file") call = { name: "write_file", args: { file_path: subject, content: "x" } }
    else if (kind === "replace") call = { name: "replace", args: { file_path: subject, old_string: "a", new_string: "b", instruction: "i" } }
    else if (kind === "mcp") { call = { name: "mcp_github_" + subject, args: { owner: "o", repo: "r" } }; server = "github" }
    else { call = { name: "mcp_other_" + subject, args: { owner: "o", repo: "r" } }; server = "other" }
    const res = await engine.check(call, server)
    const ours = String(res.rule?.source ?? "").includes("tamirs-superpowers")
    n++
    let good
    if (want === "deny") good = res.decision === "deny" && ours
    else if (want === "ask") good = res.decision === "ask_user" && (ours || mode === "default")
    else good = mode === "default" ? !(ours && res.decision === "deny") : !ours && res.decision === "allow"
    if (!good) out.push(`${mode}${nonInteractive ? " headless" : ""}: ${kind} ${JSON.stringify(subject)}: want ${want}, got ${res.decision} (${res.rule?.source ?? "no rule"})`)
  }
}
process.stdout.write("\nPROBE " + JSON.stringify({ n, ext: ext.rules.length, out }) + "\n")
JS
  probe="$(cd "$T" && node "$T/engine.mjs" "$gem_chunk" "$ROOT/platforms/gemini/policies" "$CASES" 2>/dev/null | sed -n 's/^PROBE //p' | tail -1)"
  if [ -z "$probe" ]; then
    skip "Gemini's own policy engine agrees" "the installed bundle could not be driven ($gem_chunk)"
  else
    judge "Gemini's own policy engine (@google/gemini-cli $(jq -r .version "$gem_bundle/../package.json" 2>/dev/null)) loads every rule and agrees on all $(jq -r .n <<<"$probe") checks" \
      "" "$(jq -r '.out[]' <<<"$probe" | head -20)"
  fi
else
  skip "Gemini's own policy engine agrees" "no local @google/gemini-cli bundle (or TAMIRS_SKIP_GEMINI_ENGINE=1)"
fi

# --------------------------------------------------------------------------------
section "hooks.json: permission-guard.sh on BeforeTool, the MCP group left out"
pg_groups="$(jq -c '[.hooks.BeforeTool[] | select(any(.hooks[]; .command | endswith("/hooks/permission-guard.sh\""))) | .matcher]' "$HOOKS")"
judge "permission-guard.sh runs on exactly one BeforeTool group, matcher ^(run_shell_command)\$" '["^(run_shell_command)$"]' "$pg_groups"
# shellcheck disable=SC2016  # ${extensionPath} is Gemini's placeholder, expanded by Gemini, never by this shell
judge "...through gemini-wrap.sh" 'bash "${extensionPath}/hooks/gemini-wrap.sh" "${extensionPath}/hooks/permission-guard.sh"' \
  "$(jq -r '[.hooks.BeforeTool[].hooks[] | select(.name == "permission-guard-shell") | .command][0] // empty' "$HOOKS")"
judge "...with its timeout in milliseconds" 30000 \
  "$(jq -r '[.hooks.BeforeTool[].hooks[] | select(.name == "permission-guard-shell") | .timeout][0] // empty' "$HOOKS")"
judge "the canonical file still wires the GitHub MCP matcher (so the skip is exercised)" yes \
  "$(if jq -e --arg m "$MCP_TOKEN" '[.hooks.PreToolUse[] | select(.matcher == $m)] | length == 1' "$ROOT/hooks/hooks.json" >/dev/null; then echo yes; else echo no; fi)"
judge "no generated tool group lacks a matcher (a skipped group never becomes match-all)" 0 \
  "$(jq '[(.hooks.BeforeTool + .hooks.AfterTool)[] | select(has("matcher") | not)] | length' "$HOOKS")"
judge "no generated matcher names an MCP tool" "" \
  "$(jq -r '(.hooks.BeforeTool + .hooks.AfterTool)[] | .matcher' "$HOOKS" | grep -E 'mcp' || true)"
judge "the description says why the MCP group is left out" yes \
  "$(has "$(jq -r .description "$HOOKS")" "Left out on purpose: PreToolUse $MCP_TOKEN")"

C="$T/mixed"; make_copy "$C"
jq --arg m "$MCP_TOKEN" '.hooks.PreToolUse[0].matcher = "Bash|" + $m' "$C/hooks/hooks.json" > "$C/h" && mv "$C/h" "$C/hooks/hooks.json"
bash "$GEN" "$C" >/dev/null 2>&1
judge "a group mixing a skipped token and a mapped one keeps the mapped one" '^(run_shell_command)$' \
  "$(jq -r '.hooks.BeforeTool[0].matcher' "$C/platforms/gemini/hooks.json")"
C="$T/other-mcp"; make_copy "$C"
jq '.hooks.PreToolUse[1].matcher = "mcp__other__.*"' "$C/hooks/hooks.json" > "$C/h" && mv "$C/h" "$C/hooks/hooks.json"
assert_exit "an MCP matcher token the generator does not know is still an error" 2 bash "$GEN" "$C"

# --------------------------------------------------------------------------------
section "the guard in the Gemini dialect never answers ask"
PH="$T/passwd-home"
mkdir -m 700 "$PH"
export TAMIRS_PERMISSION_TEST_ROOT="$PH"
export HOME="$T/env-home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$T/gitconfig"
: > "$GIT_CONFIG_GLOBAL"
unset CODEX_HOME GEMINI_SESSION_ID GEMINI_PROJECT_DIR GEMINI_CWD TS_PERMISSION_LEVEL \
  CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL TAMIRS_AUTO_MERGE GH_REPO GH_HOST CLAUDE_PLUGIN_ROOT 2>/dev/null || true
W="$T/bin/test-resolve-permission.sh"
mkdir -p "$T/bin"
cat > "$W" <<'SH'
#!/usr/bin/env bash
# Named so the resolver honours TAMIRS_PERMISSION_TEST_ROOT below this process. Not exec: it must stay the ancestor.
"$@"
rc=$?
exit "$rc"
SH
hs="$(bash "$W" bash "$ROOT/scripts/resolve-permission.sh" repo.read --json 2>/dev/null | jq -r '.home_source // empty')"
if [ "$hs" != "test-root" ]; then
  echo "FATAL: the resolver did not take TAMIRS_PERMISSION_TEST_ROOT (home_source=$hs); refusing to judge the real permission file" >&2
  exit 1
fi
ok "the resolver reads the temp passwd home"

REPO="$T/repo"
harness_new_repo "$REPO" main
git -C "$REPO" remote add origin https://github.com/me/app.git
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$REPO" checkout -q -b feat

claude_verdict() { # the same call as Claude Code sends it: ask is possible there
  jq -cn --arg c "$1" --arg cwd "$REPO" '{session_id:"s",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:$cwd}' |
    bash "$W" bash "$PG" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"'
}
gemini_answer() { # a Gemini BeforeTool payload through the generated command
  jq -cn --arg c "$1" --arg cwd "$REPO" '{session_id:"s",transcript_path:"/t",cwd:$cwd,hook_event_name:"BeforeTool",
      timestamp:"now",tool_name:"run_shell_command",tool_input:{command:$c}}' |
    GEMINI_SESSION_ID=s GEMINI_PROJECT_DIR="$REPO" bash "$W" bash "$WRAP" "$PG" 2>/dev/null
}

ASKS=(
  "gh pr create --fill"
  "git push origin feat"
  "gh pr merge 5 --squash"
  "gh repo create me/x --private"
  "gh release create v1"
  "claude -p hi"
  "gh frobnicate --now"
  "bash scripts/plugin-config.sh confirm 0123456789abcdef"
)
for c in "${ASKS[@]}"; do
  judge "control: Claude Code asks for \`$c\` at supervised" ask "$(claude_verdict "$c")"
  out="$(gemini_answer "$c")"
  judge "Gemini: \`$c\` is a deny, not an ask" deny "$(jq -r '.decision // "allow"' <<<"$out" 2>/dev/null)"
  judge "...answered as one JSON object on one line" "1 object" \
    "$(printf '%s\n' "$out" | wc -l | tr -d ' ') $(jq -r type <<<"$out" 2>/dev/null)"
done
judge "...and the deny says why (ask delivered as a deny, D8)" yes \
  "$(has "$(gemini_answer "gh pr create --fill" | jq -r .reason)" "delivered as a deny")"

# TS_PERMISSION_LEVEL in the extension .env is the Gemini option store (D3, D7).
ENVF="$PH/.gemini/extensions/tamirs-superpowers/.env"
mkdir -p "$(dirname "$ENVF")"
chmod 700 "$PH/.gemini" "$PH/.gemini/extensions" "$PH/.gemini/extensions/tamirs-superpowers"
printf 'TS_PERMISSION_LEVEL=unattended\n' > "$ENVF"
chmod 600 "$ENVF"
judge "TS_PERMISSION_LEVEL=unattended in the extension .env: an R2 call runs on Gemini" allow \
  "$(gemini_answer "gh pr create --fill" | jq -r '.decision // "allow"')"
for c in "gh repo create me/x --private" "claude -p hi" "gh pr merge 5 --squash" "gh frobnicate --now"; do
  judge "...an R3/R4/UNCLASSIFIED call is still a deny, never an ask: \`$c\`" deny \
    "$(gemini_answer "$c" | jq -r '.decision // "allow"')"
done
printf 'TS_PERMISSION_LEVEL=yolo\n' > "$ENVF"
judge "a value outside the enum counts as supervised (D7): the R2 call is a deny" deny \
  "$(gemini_answer "gh pr create --fill" | jq -r '.decision // "allow"')"
rm -f "$ENVF"
judge "no Gemini answer from the guard ever carries decision ask" "" \
  "$(for c in "${ASKS[@]}"; do gemini_answer "$c"; done | jq -r 'select(.decision == "ask") | .reason' 2>/dev/null)"

# --------------------------------------------------------------------------------
section "TS_PERMISSION_LEVEL: manifest source, generated extension manifest, resolver"
assert_exit "build-manifests.sh --check passes" 0 bash "$ROOT/scripts/build-manifests.sh" "$ROOT" --check
judge "gemini-extension.json settings == manifests.source.json gemini.manifest.settings" \
  "$(jq -cS '.gemini.manifest.settings' "$ROOT/platforms/manifests.source.json")" \
  "$(jq -cS '.settings' "$ROOT/gemini-extension.json")"
setting="$(jq -c '.settings[] | select(.envVar == "TS_PERMISSION_LEVEL")' "$ROOT/gemini-extension.json")"
judge "the extension declares one TS_PERMISSION_LEVEL setting" 1 "$(jq -c '[.settings[] | select(.envVar == "TS_PERMISSION_LEVEL")] | length' "$ROOT/gemini-extension.json")"
judge "...named as its env var (gemini extensions config takes either)" TS_PERMISSION_LEVEL "$(jq -r .name <<<"$setting")"
judge "...not sensitive: it must land in the .env the resolver reads, not the keychain" false "$(jq -r '.sensitive // false' <<<"$setting")"
desc="$(jq -r .description <<<"$setting")"
for w in supervised standard unattended validates; do
  judge "...its description names '$w'" yes "$(has "$desc" "$w")"
done
judge "the GitHub token setting is still there and still sensitive" true \
  "$(jq -r '.settings[] | select(.envVar == "GITHUB_PERSONAL_ACCESS_TOKEN") | .sensitive' "$ROOT/gemini-extension.json")"
judge "the resolver reads exactly that name from the extension .env" yes \
  "$(if grep -q '"TS_PERMISSION_LEVEL"' "$ROOT/scripts/lib/permission-common.sh"; then echo yes; else echo no; fi)"

section "housekeeping"
judge "this test file is executable" yes "$(if [ -x "$ROOT/tests/test-gemini-permission-policy.sh" ]; then echo yes; else echo no; fi)"

harness_summary
