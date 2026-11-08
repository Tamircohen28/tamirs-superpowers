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
#   ADR 004 item 12 adds the permission-level invariants: the permission guard is wired
#   fail closed on every host that can run it (D8), and none of the four host levers that
#   could WIDEN a permission is used anywhere in what ships (D10.4): a mod `tool.check`,
#   an OpenCode `ctx.session.update`, a `PermissionRequest` hook, an Antigravity
#   `auto_approve`. Every one of those checks is also run against a mutated temp copy of
#   the files it reads, and must fail there, so a check that can never fail cannot pass.
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
PG = 'permission-guard.sh'
GUARDS = ('protect-other-branches.sh', 'enforce-worktree-edits.sh', 'guard-sensitive-files.sh',
          'docker-guard.py', PG)
MCP_MATCHER = 'mcp__plugin_tamirs-superpowers_github__.*'

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

def ver(v): return tuple(int(x) for x in re.findall(r'\d+', v))

out = []
if name == 'guards-fail-closed':
    for ev, m, h in claude_hooks():
        if any(x in h.get('command', '') for x in GUARDS) and h.get('onFailure') != 'block':
            out.append('%s %s' % (ev, h.get('command')))
elif name == 'no-advisory-blocks':
    for ev, m, h in claude_hooks():
        if h.get('onFailure') == 'block' and not any(x in h.get('command', '') for x in GUARDS):
            out.append('%s %s' % (ev, h.get('command')))
elif name == 'pg-claude':
    seen = {(m, h.get('onFailure')) for ev, m, h in claude_hooks()
            if ev == 'PreToolUse' and PG in h.get('command', '')}
    for want in ('Bash|Shell', MCP_MATCHER):
        if (want, 'block') not in seen:
            out.append('hooks/hooks.json: no PreToolUse %s on matcher %s with onFailure: block' % (PG, want))
elif name == 'pg-codex':
    pre = load('platforms', 'codex', 'hooks.json')['hooks'].get('PreToolUse', [])
    got = {g.get('matcher') for g in pre for h in g.get('hooks', []) if PG in h.get('command', '')}
    for want in ('Bash|Shell', MCP_MATCHER):
        if want not in got:
            out.append('platforms/codex/hooks.json: no PreToolUse %s on matcher %s' % (PG, want))
    # Codex has no onFailure: the guard itself must turn every exit into a deny and exit 0.
    src = open(P('hooks', PG), encoding='utf-8').read()
    body = re.search(r'^_pg_on_exit\(\) \{\n(.*?)\n\}', src, re.S | re.M)
    if not re.search(r'^trap _pg_on_exit EXIT$', src, re.M):
        out.append('hooks/%s: no `trap _pg_on_exit EXIT`' % PG)
    if not body or '_pg_lit_deny' not in body.group(1) or 'exit 0' not in body.group(1):
        out.append('hooks/%s: _pg_on_exit does not print a deny and exit 0' % PG)
elif name == 'pg-cursor':
    hk = load('platforms', 'cursor', 'hooks.json')['hooks']
    for ev in ('preToolUse', 'beforeShellExecution'):
        ents = [h for h in hk.get(ev, []) if PG in h.get('command', '')]
        if not ents:
            out.append('platforms/cursor/hooks.json: %s does not run %s' % (ev, PG))
        for h in ents:
            if h.get('failClosed') is not True:
                out.append('platforms/cursor/hooks.json: %s %s lacks failClosed: true' % (ev, PG))
            if ev == 'preToolUse' and h.get('matcher'):
                out.append('platforms/cursor/hooks.json: preToolUse %s is narrowed by matcher %r; it must see MCP calls too' % (PG, h['matcher']))
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
elif name == 'permissions-min':
    d = load('docs', 'engineering', 'build-and-release', 'platform-targets.json')
    for tk in d['supported_targets']:
        t = d['targets'][tk]
        pm = t.get('permissions_min')
        if not isinstance(pm, str) or not re.fullmatch(r'\d+(\.\d+)+', pm):
            out.append('%s: permissions_min missing or not a version (%r)' % (tk, pm)); continue
        if not t.get('permissions_min_source'):
            out.append('%s: permissions_min_source missing' % tk)
        if ver(pm) < ver(t['supported_min']):
            out.append('%s: permissions_min %s is below supported_min %s' % (tk, pm, t['supported_min']))
        if ver(t['validated_against']) < ver(pm):
            out.append('%s: permissions_min %s is above validated_against %s' % (tk, pm, t['validated_against']))
    if 'cursor' in d['targets'] and not re.fullmatch(r'\d{4}\.\d{2}\.\d{2}', d['targets']['cursor'].get('permissions_min_cli', '')):
        out.append('cursor: permissions_min_cli missing (ADR 004 D9 names a Cursor CLI floor)')
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
  for p in hooks/hooks.json hooks/permission-guard.sh mod platforms scripts \
           .claude-plugin/plugin.json .codex-plugin/plugin.json .cursor-plugin/plugin.json \
           docs/engineering/build-and-release/platform-targets.json; do
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

echo "--- the core-safety guards fail closed (permission-guard.sh included) ---"
# A guard that cannot start, times out, or exits oddly must block the action, not let it
# through: hooks/hooks.json carries onFailure: "block" on every wiring of each guard.
expect_clean guards-fail-closed "every core-safety guard carries onFailure: block" "a core-safety guard is fail-open"
# ...and nothing else does: an advisory hook that blocks on its own failure would turn a
# convenience into a gate.
expect_clean no-advisory-blocks "no advisory hook fails closed" "an advisory hook carries onFailure: block"
self_test guards-fail-closed "permission-guard.sh on Bash without onFailure" "${MUT_LIB}
d=rd('hooks/hooks.json')
for g in d['hooks']['PreToolUse']:
    for h in g['hooks']:
        if 'permission-guard.sh' in h['command'] and g['matcher']=='Bash|Shell': h.pop('onFailure')
wr('hooks/hooks.json', d)"
self_test no-advisory-blocks "the advisory permission-intent.sh carrying onFailure: block" "${MUT_LIB}
d=rd('hooks/hooks.json')
n=0
for g in d['hooks']['UserPromptSubmit']:
    for h in g['hooks']:
        if 'permission-intent.sh' in h['command']: h['onFailure']='block'; n+=1
assert n
wr('hooks/hooks.json', d)"

echo "--- the permission guard is wired fail closed on every host bundle (ADR 004 D8) ---"
expect_clean pg-claude "hooks/hooks.json runs permission-guard.sh on Bash|Shell and the GitHub MCP matcher, onFailure: block" \
  "permission-guard.sh wiring in hooks/hooks.json"
expect_clean pg-codex "the Codex bundle runs permission-guard.sh on both matchers, and the guard traps every exit to a deny" \
  "permission-guard.sh wiring for Codex"
expect_clean pg-cursor "the Cursor bundle runs permission-guard.sh on preToolUse and beforeShellExecution, failClosed: true" \
  "permission-guard.sh wiring for Cursor"
self_test pg-claude "hooks/hooks.json losing the GitHub MCP matcher" "${MUT_LIB}
d=rd('hooks/hooks.json')
d['hooks']['PreToolUse']=[g for g in d['hooks']['PreToolUse'] if g.get('matcher')!='mcp__plugin_tamirs-superpowers_github__.*']
wr('hooks/hooks.json', d)"
self_test pg-codex "the Codex bundle losing the GitHub MCP matcher" "${MUT_LIB}
p='platforms/codex/hooks.json'; d=rd(p)
d['hooks']['PreToolUse']=[g for g in d['hooks']['PreToolUse'] if g.get('matcher')!='mcp__plugin_tamirs-superpowers_github__.*']
wr(p, d)"
self_test pg-codex "permission-guard.sh without its EXIT trap" "
p='hooks/permission-guard.sh'; s=open(p).read()
assert 'trap _pg_on_exit EXIT\n' in s
open(p,'w').write(s.replace('trap _pg_on_exit EXIT\n','',1))"
self_test pg-cursor "the Cursor beforeShellExecution guard failing open" "${MUT_LIB}
p='platforms/cursor/hooks.json'; d=rd(p)
for h in d['hooks']['beforeShellExecution']:
    if 'permission-guard.sh' in h['command']: h['failClosed']=False
wr(p, d)"
self_test pg-cursor "the Cursor preToolUse guard narrowed to Shell" "${MUT_LIB}
p='platforms/cursor/hooks.json'; d=rd(p)
for h in d['hooks']['preToolUse']:
    if 'permission-guard.sh' in h['command']: h['matcher']='Shell'
wr(p, d)"

echo "--- no host lever that widens a permission ships (ADR 004 D10.4) ---"
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

echo "--- platform-targets.json records the D9 permission floors ---"
expect_clean permissions-min "every supported target carries permissions_min (supported_min <= it <= validated_against) and its source" \
  "permissions_min in platform-targets.json"
self_test permissions-min "a target without permissions_min" "${MUT_LIB}
p='docs/engineering/build-and-release/platform-targets.json'; d=rd(p)
del d['targets']['claude_code']['permissions_min']
wr(p, d)"
self_test permissions-min "a permissions_min above validated_against" "${MUT_LIB}
p='docs/engineering/build-and-release/platform-targets.json'; d=rd(p)
d['targets']['cursor']['permissions_min']='99.0.0'
wr(p, d)"

echo "--- the mods page describes the manifest's options ---"
opts="$(python3 -c "import json; d=json.load(open('$ROOT/.claude-plugin/plugin.json')); print(' '.join(k for k,v in d['userConfig'].items() if not v.get('sensitive')))")"
for o in $opts; do
  grep -q "^| \`$o\` |" "$ROOT/docs/engineering/architecture/mods.md" && ok "mods.md lists option $o" || bad "mods.md does not list option $o" "add a row to the Options table"
done
n_opts="$(echo "$opts" | wc -w | tr -d ' ')"
words=(zero One Two Three Four Five Six Seven Eight Nine Ten)
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
