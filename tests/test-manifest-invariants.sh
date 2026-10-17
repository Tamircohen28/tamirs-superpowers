#!/usr/bin/env bash
# Invariants between the shipped manifests and the prose that describes them.
#
# WHY
#   Each of these was found drifted during the V5 review: the four core-safety guards
#   had no fail-closed setting once the host grew one (Claude Code 2.1.295), the mods
#   architecture page listed one more option than the manifest declares, and the
#   contributor docs quoted a mod test count two releases old. None of that breaks a
#   build; all of it misleads the next reader. These checks hold the prose to the files.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; FAILED=()
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); FAILED+=("$1"); echo "  FAIL $1 — $2"; }

echo "--- the four core-safety guards fail closed ---"
# A guard that cannot start, times out, or exits oddly must block the action, not let it
# through: hooks/hooks.json carries onFailure: "block" on every wiring of each guard.
missing="$(python3 - "$ROOT/hooks/hooks.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
guards=('protect-other-branches.sh','enforce-worktree-edits.sh','guard-sensitive-files.sh','docker-guard.py')
for ev,groups in d['hooks'].items():
    for g in groups:
        for h in g['hooks']:
            cmd=h.get('command','')
            if any(x in cmd for x in guards) and h.get('onFailure')!='block':
                print(ev, cmd)
PY
)"
[[ -z "$missing" ]] && ok "every core-safety guard carries onFailure: block" || bad "a core-safety guard is fail-open" "$missing"
# ...and nothing else does: an advisory hook that blocks on its own failure would turn a
# convenience into a gate.
extra="$(python3 - "$ROOT/hooks/hooks.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
guards=('protect-other-branches.sh','enforce-worktree-edits.sh','guard-sensitive-files.sh','docker-guard.py')
for ev,groups in d['hooks'].items():
    for g in groups:
        for h in g['hooks']:
            cmd=h.get('command','')
            if h.get('onFailure')=='block' and not any(x in cmd for x in guards):
                print(ev, cmd)
PY
)"
[[ -z "$extra" ]] && ok "no advisory hook fails closed" || bad "an advisory hook carries onFailure: block" "$extra"

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
