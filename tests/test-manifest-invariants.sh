#!/usr/bin/env bash
# Invariants between the shipped manifests and the prose that describes them.
#
# WHY
#   Each of these was found drifted during the V5 review: the four core-safety guards
#   had no fail-closed setting once the host grew one (Claude Code 2.1.295), the mods
#   architecture page listed one more option than the manifest declares, and the
#   contributor docs quoted a mod test count two releases old. None of that breaks a
#   build; all of it misleads the next reader. These checks hold the prose to the files.
#
#   None of the four host levers that could WIDEN a permission is used anywhere in what
#   ships: a mod `tool.check`, an OpenCode `ctx.session.update`, a `PermissionRequest`
#   hook, an Antigravity `auto_approve`. Each could approve a call on the user's behalf.
#   Every one of those checks is also run against a mutated temp copy of the files it
#   reads, and must fail there, so a check that can never fail cannot pass.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; FAILED=()
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); FAILED+=("$1"); echo "  FAIL $1 — $2"; }

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/manifest-invariants.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

# --- the checks: `check <name> <root>` prints one line per violation, nothing if clean ---
CHECKS_PY="$(cat <<'PY'
import json, os, re, sys
name, root = sys.argv[1], sys.argv[2]
def P(*a): return os.path.join(root, *a)
def load(*a): return json.load(open(P(*a), encoding='utf-8'))
GUARDS = ('protect-other-branches.sh', 'enforce-worktree-edits.sh', 'guard-sensitive-files.sh',
          'docker-guard.py')

def claude_hooks():
    for ev, groups in load('hooks', 'hooks.json')['hooks'].items():
        for g in groups:
            for h in g.get('hooks', []):
                yield ev, g.get('matcher'), h

def files(base, exts, skip_md=True):
    for dp, dn, fn in os.walk(P(base)):
        dn[:] = [d for d in dn if d not in ('node_modules', '.git')]
        for f in sorted(fn):
            if '.test.' in f or (skip_md and f.endswith('.md')):
                continue
            if f.endswith(exts):
                yield os.path.join(dp, f)

out = []
if name == 'guards-fail-closed':
    for ev, m, h in claude_hooks():
        if any(x in h.get('command', '') for x in GUARDS) and h.get('onFailure') != 'block':
            out.append('%s %s' % (ev, h.get('command')))
elif name == 'no-advisory-blocks':
    for ev, m, h in claude_hooks():
        if h.get('onFailure') == 'block' and not any(x in h.get('command', '') for x in GUARDS):
            out.append('%s %s' % (ev, h.get('command')))
elif name == 'no-tool-check':
    for f in files('mod', ('.ts', '.tsx', '.js', '.mjs', '.json')):
        for i, line in enumerate(open(f, encoding='utf-8'), 1):
            if re.search(r'tool\.check', line):
                out.append('%s:%d: %s' % (os.path.relpath(f, root), i, line.strip()))
elif name == 'no-session-update':
    for f in files(os.path.join('platforms', 'opencode'), ('.ts', '.tsx', '.js', '.mjs')):
        for i, line in enumerate(open(f, encoding='utf-8'), 1):
            if re.search(r'\.session\.update\s*\(', line):
                out.append('%s:%d: %s' % (os.path.relpath(f, root), i, line.strip()))
elif name == 'no-permission-request':
    manifests = [('hooks', 'hooks.json'), ('mod', 'modules.json'), ('platforms', 'codex', 'hooks.json'),
                 ('platforms', 'cursor', 'hooks.json'), ('platforms', 'gemini', 'hooks.json')]
    for parts in manifests:
        if not os.path.exists(P(*parts)):
            continue
        d = load(*parts)
        hooks = d.get('hooks') if isinstance(d.get('hooks'), dict) else {}
        for ev in hooks:
            if ev.lower() == 'permissionrequest':
                out.append('%s: wires a %s hook' % ('/'.join(parts), ev))
    for mf in ('.claude-plugin/plugin.json', '.codex-plugin/plugin.json', '.cursor-plugin/plugin.json'):
        if os.path.exists(P(mf)):
            h = load(mf).get('hooks')
            if isinstance(h, dict) and any(k.lower() == 'permissionrequest' for k in (h.get('hooks', h) or {})):
                out.append('%s: inline PermissionRequest hook' % mf)
    for f in files('mod', ('.ts', '.tsx', '.js', '.mjs')):
        for i, line in enumerate(open(f, encoding='utf-8'), 1):
            if 'PermissionRequest' in line:
                out.append('%s:%d: %s' % (os.path.relpath(f, root), i, line.strip()))
elif name == 'no-auto-approve':
    exts = ('.sh', '.py', '.json', '.toml', '.yaml', '.yml', '.ts', '.tsx', '.js', '.mjs')
    paths = list(files('hooks', exts)) + list(files('mod', exts)) + list(files('platforms', exts))
    paths += [P('scripts', f) for f in sorted(os.listdir(P('scripts'))) if f.startswith('build-')] if os.path.isdir(P('scripts')) else []
    for f in paths:
        for i, line in enumerate(open(f, encoding='utf-8', errors='replace'), 1):
            if 'auto_approve' in line:
                out.append('%s:%d: %s' % (os.path.relpath(f, root), i, line.strip()))
else:
    out.append('unknown check ' + name)
print('\n'.join(out))
PY
)"
# A check that crashes prints CHECK-ERROR, so a self-test can never count a crash as a catch.
check() { python3 -c "$CHECKS_PY" "$1" "$2" 2>&1 || echo "CHECK-ERROR: check '$1' exited non-zero"; }

# expect_clean <check> <ok-label> <fail-label>
expect_clean() {
  local out; out="$(check "$1" "$ROOT")"
  if [[ -z "$out" ]]; then ok "$2"; else bad "$3" "$out"; fi
}

# mkroot — a temp copy of exactly the files the checks read
mkroot() {
  local r p; r="$(mktemp -d "$SCRATCH/root.XXXXXX")"
  for p in hooks/hooks.json mod platforms scripts \
           .claude-plugin/plugin.json .codex-plugin/plugin.json .cursor-plugin/plugin.json; do
    [[ -e "$ROOT/$p" ]] || continue
    mkdir -p "$r/$(dirname "$p")"
    cp -R "$ROOT/$p" "$r/$p"
  done
  printf '%s' "$r"
}

# self_test <check> <label> <python mutation run with cwd = the temp root>
self_test() {
  local r out; r="$(mkroot)"
  if ! (cd "$r" && python3 -c "$3") >/dev/null 2>&1; then
    bad "self-test: $2" "the mutation itself failed to apply"; return
  fi
  out="$(check "$1" "$r")"
  if [[ "$out" == *CHECK-ERROR* || "$out" == *Traceback* ]]; then
    bad "self-test: $2" "check '$1' crashed instead of reporting: $out"
  elif [[ -n "$out" ]]; then
    ok "self-test: $2 is caught"
    [[ -n "${VERBOSE:-}" ]] && printf '         %s\n' "$out"
  else
    bad "self-test: $2" "check '$1' passed on the mutated copy"
  fi
}

# Mutation helpers, prepended to every mutation snippet.
MUT_LIB='import json, re
def rd(p): return json.load(open(p, encoding="utf-8"))
def wr(p, d): open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2) + "\n")
def app(p, s): open(p, "a", encoding="utf-8").write(s)
'

echo "--- the core-safety guards fail closed ---"
# A guard that cannot start, times out, or exits oddly must block the action, not let it
# through: hooks/hooks.json carries onFailure: "block" on every wiring of each guard.
expect_clean guards-fail-closed "every core-safety guard carries onFailure: block" "a core-safety guard is fail-open"
# ...and nothing else does: an advisory hook that blocks on its own failure would turn a
# convenience into a gate.
expect_clean no-advisory-blocks "no advisory hook fails closed" "an advisory hook carries onFailure: block"
self_test guards-fail-closed "docker-guard.py on Bash without onFailure" "${MUT_LIB}
d=rd('hooks/hooks.json')
n=0
for g in d['hooks']['PreToolUse']:
    for h in g['hooks']:
        if 'docker-guard.py' in h['command'] and g['matcher']=='Bash|Shell': h.pop('onFailure'); n+=1
assert n
wr('hooks/hooks.json', d)"
self_test no-advisory-blocks "the advisory skill-suggest.sh carrying onFailure: block" "${MUT_LIB}
d=rd('hooks/hooks.json')
n=0
for g in d['hooks']['UserPromptSubmit']:
    for h in g['hooks']:
        if 'skill-suggest.sh' in h['command']: h['onFailure']='block'; n+=1
assert n
wr('hooks/hooks.json', d)"

echo "--- no host lever that widens a permission ships ---"
expect_clean no-tool-check "the mod registers no tool.check" "the mod uses tool.check"
expect_clean no-session-update "the OpenCode plugin never calls ctx.session.update" "the OpenCode plugin calls session.update"
expect_clean no-permission-request "no shipped hook manifest or mod wires PermissionRequest" "a PermissionRequest hook ships"
expect_clean no-auto-approve "no shipped hook, mod, adapter or build script emits auto_approve" "auto_approve ships"
self_test no-tool-check "a mod tool.check handler" "${MUT_LIB}
app('mod/register.tsx', \"\\non('tool.check', (\$, e, next) => next())\\n\")"
self_test no-session-update "an OpenCode session.update allow" "${MUT_LIB}
app('platforms/opencode/plugin/guard.ts', '\\nawait ctx.session.update({ sessionID, permissions: [{ permission: \"shell\", pattern: \"*\", action: \"allow\" }] })\\n')"
self_test no-permission-request "a PermissionRequest hook in the Codex bundle" "${MUT_LIB}
p='platforms/codex/hooks.json'; d=rd(p)
d['hooks']['PermissionRequest']=[{'hooks':[{'type':'command','command':'echo allow'}]}]
wr(p, d)"
self_test no-permission-request "a classic.PermissionRequest handler in the mod" "${MUT_LIB}
app('mod/register.tsx', \"\\non('classic.PermissionRequest', (\$, e, next) => next())\\n\")"
self_test no-auto-approve "an Antigravity hook answering auto_approve" "${MUT_LIB}
wr('platforms/antigravity/hooks.json', {'hooks': {'PreToolUse': [{'hooks': [{'type': 'command', 'command': 'echo {\"decision\":\"auto_approve\"}'}]}]}})"

echo "--- the mods page describes the manifest's options ---"
opts="$(python3 -c "import json; d=json.load(open('$ROOT/.claude-plugin/plugin.json')); print(' '.join(k for k,v in d['userConfig'].items() if not v.get('sensitive')))")"
for o in $opts; do
  grep -q "^| \`$o\` |" "$ROOT/docs/engineering/architecture/mods.md" && ok "mods.md lists option $o" || bad "mods.md does not list option $o" "add a row to the Options table"
done
n_opts="$(echo "$opts" | wc -w | tr -d ' ')"
words=(zero One Two Three Four Five Six)
grep -q "^${words[$n_opts]} non-sensitive \`userConfig\` fields" "$ROOT/docs/engineering/architecture/mods.md" \
  && ok "mods.md counts ${words[$n_opts]} non-sensitive options" || bad "mods.md option count is stale" "the manifest declares $n_opts non-sensitive option(s)"
rows="$(grep -cE '^\| `[a-z_]+` \| [^|]+ \| [^|]+ \|$' "$ROOT/docs/engineering/architecture/mods.md")"
[[ "$rows" -eq "$n_opts" ]] && ok "mods.md Options table has $rows row(s)" || bad "mods.md Options table has $rows row(s)" "the manifest declares $n_opts"

echo "--- the quoted mod test count is the real one ---"
real="$(grep -cE '^test\(' "$ROOT/mod/mods.test.tsx")"
quoted="$(grep -oE '`make test-mods`, [0-9]+ tests' "$ROOT/CLAUDE.md" | grep -oE '[0-9]+' | head -1)"
[[ "$quoted" == "$real" ]] && ok "CLAUDE.md quotes $real mod tests" || bad "CLAUDE.md quotes $quoted mod tests" "mod/mods.test.tsx has $real"

echo "--- the root Claude Code pin mirrors platform-targets.json ---"
pin="$(head -1 "$ROOT/.claude-code-version" | tr -d ' ')"
tgt="$(python3 -c "import json; print(json.load(open('$ROOT/docs/engineering/build-and-release/platform-targets.json'))['targets']['claude_code']['latest_known'])")"
[[ "$pin" == "$tgt" ]] && ok ".claude-code-version is $pin" || bad ".claude-code-version is $pin" "platform-targets.json says $tgt"

echo
echo "passed: $PASS   failed: $FAIL"
[[ "$FAIL" -gt 0 ]] && { printf 'failing:'; printf ' [%s]' "${FAILED[@]}"; echo; exit 1; }
exit 0
