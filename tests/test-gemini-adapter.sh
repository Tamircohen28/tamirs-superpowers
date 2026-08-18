#!/usr/bin/env bash
# Behavior tests for the Gemini CLI adapter (gemini-extension.json +
# scripts/check-gemini-adapter.sh).
#
# WHY THE GUARD IS TESTED AND NOT THE MANIFEST
#   `jq empty gemini-extension.json` proves the file is JSON, which was never in
#   doubt. What can actually rot is the relationship between the manifest and the
#   repo around it: contextFileName pointing at a file someone renamed, an
#   mcpServers arg pointing at a deleted script, the version drifting away from
#   plugin-version.json, a Node dependency arriving. Those are exactly the things
#   check-gemini-adapter.sh claims to catch, so the tests plant each defect in a
#   synthetic repo root and assert the guard actually fails on it.
#
# WHY BOTH DIRECTIONS
#   A checker that fails on everything is indistinguishable from a broken one.
#   Every planted-defect case is paired with the same fixture left intact, which
#   must pass — and the real repo root must pass too.
#
# WHY A LIVE-CLI SECTION
#   The whole adapter design rests on one measured claim: Gemini discovers
#   extension skills exactly one level deep, so this repo's skills/<domain>/<name>
#   layout yields zero. If that ever stops being true the docs and the install
#   flow are wrong, and no amount of static checking would notice. When the
#   gemini CLI is on PATH the claim is re-measured; when it is not, the section
#   skips loudly rather than silently passing.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/check-gemini-adapter.sh"

PASS=0
FAIL=0
SKIP=0
FAILED_NAMES=()

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required to run these tests"; exit 1; }
[ -f "$CHECK" ] || { echo "FATAL: check script not found at $CHECK"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# --- fixture: a minimal repo root the checker considers healthy -------------
# Only the files check-gemini-adapter.sh actually reads. Building it from
# scratch rather than copying the repo keeps each planted defect the ONLY
# difference between a passing and a failing run.
make_fixture() {
  local d="$1"
  mkdir -p "$d/.gemini" "$d/platforms/gemini" "$d/docs/user/install" \
           "$d/scripts" "$d/skills/toolkit/demo-skill"
  cat > "$d/gemini-extension.json" <<'EOF'
{
  "name": "fixture-ext",
  "version": "1.2.3",
  "description": "fixture",
  "contextFileName": ".gemini/GEMINI.md",
  "mcpServers": {
    "github": {
      "command": "bash",
      "args": ["${extensionPath}/scripts/github-mcp.sh"],
      "cwd": "${extensionPath}"
    }
  }
}
EOF
  jq -n '{version:"1.2.3"}' > "$d/plugin-version.json"
  echo "context" > "$d/.gemini/GEMINI.md"
  echo "id: gemini" > "$d/platforms/gemini/adapter.yaml"
  echo "toolkit" > "$d/docs/user/install/gemini.md"
  echo "#!/usr/bin/env bash" > "$d/scripts/github-mcp.sh"
  printf -- '---\nname: demo-skill\ndescription: d\n---\n' > "$d/skills/toolkit/demo-skill/SKILL.md"
  # The real generator, so drift cases exercise the real comparison rather than
  # a stand-in that could agree with a broken checker.
  cp "$ROOT/scripts/build-gemini-extension.sh" "$d/scripts/build-gemini-extension.sh"
  mkdir -p "$d/agents"
  printf -- '---\nname: a\ndescription: d\ntools: Read, Bash\n---\nbody\n' > "$d/agents/a.md"
  bash "$d/scripts/build-gemini-extension.sh" "$d" >/dev/null 2>&1
}

# run_check <dir> — prints PASS or FAIL:<first error line>
run_check() {
  local out
  if out=$(bash "$CHECK" "$1" 2>&1); then
    printf 'PASS'
  else
    printf 'FAIL:%s' "$(printf '%s' "$out" | grep '^ERROR:' | head -1)"
  fi
}

judge() {
  local name="$1" expect="$2" result="$3" ok=0
  case "$expect" in
    PASS) [ "$result" = "PASS" ] && ok=1 ;;
    FAIL) case "$result" in FAIL*) ok=1 ;; esac ;;
  esac
  if [ "$ok" = 1 ]; then
    PASS=$((PASS + 1)); printf '  ok   %-56s [%s]\n' "$name" "$expect"
  else
    FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
    printf '  FAIL %-56s expected %s, got: %s\n' "$name" "$expect" "${result%%$'\n'*}"
  fi
}

# case <name> <expect> <mutation…> — fresh fixture, mutate, check.
# The mutation runs with $d bound to the fixture root.
case_with() {
  local name="$1" expect="$2" mutation="$3"
  local d="$TMPROOT/fix.$((PASS + FAIL + SKIP))"
  make_fixture "$d"
  ( d="$d"; eval "$mutation" )
  judge "$name" "$expect" "$(run_check "$d")"
}

echo "--- the intact fixture and the real repo must pass ---"
# Without these, every assertion below could be satisfied by a checker that
# fails unconditionally.
case_with "untouched fixture passes"                 PASS ':'
judge     "the real repo root passes"                PASS "$(run_check "$ROOT")"

echo "--- manifest presence and required fields ---"
case_with "missing manifest is caught"               FAIL 'rm "$d/gemini-extension.json"'
case_with "malformed JSON is caught"                 FAIL 'echo "{ not json" > "$d/gemini-extension.json"'
case_with "missing name is caught"                   FAIL 'jq "del(.name)" "$d/gemini-extension.json" > "$d/m" && mv "$d/m" "$d/gemini-extension.json"'
case_with "missing version is caught"                FAIL 'jq "del(.version)" "$d/gemini-extension.json" > "$d/m" && mv "$d/m" "$d/gemini-extension.json"'
case_with "missing description is caught"            FAIL 'jq "del(.description)" "$d/gemini-extension.json" > "$d/m" && mv "$d/m" "$d/gemini-extension.json"'
# Gemini expects the extension name to match its directory name and documents
# lowercase-with-dashes; a name the user cannot retype is a name they cannot
# pass to `gemini extensions disable`.
case_with "uppercase name is caught"                 FAIL 'jq ".name = \"Tamirs_Superpowers\"" "$d/gemini-extension.json" > "$d/m" && mv "$d/m" "$d/gemini-extension.json"'
case_with "a legal dashed name is allowed"           PASS 'jq ".name = \"tamirs-superpowers\"" "$d/gemini-extension.json" > "$d/m" && mv "$d/m" "$d/gemini-extension.json"'

echo "--- referenced paths must exist ---"
# The defect `gemini extensions validate` does NOT catch: on 0.55.1 it reports
# success for an extension whose contextFileName names a missing file.
case_with "dangling contextFileName is caught"       FAIL 'rm "$d/.gemini/GEMINI.md"'
case_with "dangling mcpServers arg is caught"        FAIL 'rm "$d/scripts/github-mcp.sh"'
# ...and the other direction: an extension that declares no context file at all
# is legal (Gemini falls back to GEMINI.md), so its absence must not fail.
case_with "no contextFileName declared is allowed"   PASS 'jq "del(.contextFileName)" "$d/gemini-extension.json" > "$d/m" && mv "$d/m" "$d/gemini-extension.json" && rm "$d/.gemini/GEMINI.md"'

echo "--- version truth: the manifest is a consumer, never a source ---"
case_with "version drift from plugin-version is caught" FAIL 'jq ".version = \"9.9.9\"" "$d/gemini-extension.json" > "$d/m" && mv "$d/m" "$d/gemini-extension.json"'
case_with "matching versions pass"                   PASS 'jq ".version = \"1.2.3\"" "$d/gemini-extension.json" > "$d/m" && mv "$d/m" "$d/gemini-extension.json"'

echo "--- no Node dependency may enter through the Gemini adapter ---"
# Gemini's own `extensions new` templates scaffold an npm package. Following
# them would make Gemini the one target that needs a toolchain.
case_with "a package.json is caught"                 FAIL 'echo "{}" > "$d/package.json"'
case_with "a lockfile is caught"                     FAIL 'touch "$d/package-lock.json"'
case_with "an npx mcp server is caught"              FAIL 'jq ".mcpServers.x = {command:\"npx\", args:[\"-y\",\"pkg\"]}" "$d/gemini-extension.json" > "$d/m" && mv "$d/m" "$d/gemini-extension.json"'

echo "--- adapter contract artifacts ---"
case_with "missing adapter.yaml is caught"           FAIL 'rm "$d/platforms/gemini/adapter.yaml"'
case_with "missing install doc is caught"            FAIL 'rm "$d/docs/user/install/gemini.md"'

echo "--- the generated skill mirror: the failure nobody would notice ---"
# Gemini finds skills exactly one level below a skills root. The canonical tree is
# two levels deep, so without the flat mirror Gemini discovers ZERO skills and says
# nothing about it. Every case below is a way that mirror can be silently wrong.
case_with "a missing mirror is caught"               FAIL 'rm -rf "$d/.gemini/skills"'
case_with "an EMPTY mirror is caught"                FAIL 'rm -f "$d"/.gemini/skills/*'
case_with "a mirror missing one skill is caught"     FAIL 'mkdir -p "$d/skills/toolkit/second/" && printf -- "---\nname: second\ndescription: d\n---\n" > "$d/skills/toolkit/second/SKILL.md"'
case_with "a dangling mirror symlink is caught"      FAIL 'rm -rf "$d/skills/toolkit/demo-skill"'
case_with "a stale extra mirror entry is caught"     FAIL 'ln -s ../../skills/toolkit/demo-skill "$d/.gemini/skills/ghost"'
# ...and the other direction: regenerating after a real change must pass, or the
# check is just asserting that nothing ever changes.
case_with "regenerating after adding a skill passes" PASS 'mkdir -p "$d/skills/creative/third/" && printf -- "---\nname: third\ndescription: d\n---\n" > "$d/skills/creative/third/SKILL.md" && bash "$d/scripts/build-gemini-extension.sh" "$d" >/dev/null 2>&1'
case_with "a deleted skill, regenerated, passes"     PASS 'rm -rf "$d/skills/toolkit/demo-skill" && mkdir -p "$d/skills/creative/only/" && printf -- "---\nname: only\ndescription: d\n---\n" > "$d/skills/creative/only/SKILL.md" && bash "$d/scripts/build-gemini-extension.sh" "$d" >/dev/null 2>&1'
case_with "a missing generator is caught"            FAIL 'rm -f "$d/scripts/build-gemini-extension.sh"'

echo "--- the generator itself ---"
# gen <name> <expect-rc: 0|2> <mutation> — asserts on the generator's own exit.
gen_case() {
  local name="$1" want="$2" mutation="$3"
  local d="$TMPROOT/gen.$((PASS + FAIL + SKIP))" rc=0
  make_fixture "$d"
  ( d="$d"; eval "$mutation" )
  bash "$d/scripts/build-gemini-extension.sh" "$d" >/dev/null 2>&1 || rc=$?
  if [ "$rc" = "$want" ]; then
    PASS=$((PASS + 1)); printf '  ok   %-56s [rc=%s]\n' "$name" "$want"
  else
    FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
    printf '  FAIL %-56s expected rc=%s, got rc=%s\n' "$name" "$want" "$rc"
  fi
}

# Flattening two levels into one makes cross-domain name collisions real. Silently
# overwriting would drop a skill from Gemini with nothing to say so.
gen_case "a cross-domain name collision fails loudly" 2 \
  'mkdir -p "$d/skills/creative/demo-skill" && printf -- "---\nname: demo-skill\ndescription: d\n---\n" > "$d/skills/creative/demo-skill/SKILL.md"'
# Refusing to generate an empty mirror is the difference between failing here and
# shipping an adapter that finds nothing.
gen_case "generating from an empty skills/ fails"     2 'rm -rf "$d/skills"'
gen_case "the healthy fixture generates cleanly"      0 ':'

# The translation Gemini's loader actually demands: an ARRAY of Gemini tool names,
# and no `model:` (a Claude alias passes validation and fails at invocation).
d="$TMPROOT/agentgen"; make_fixture "$d"
agent_out="$(cat "$d/.gemini/agents/a.md" 2>/dev/null)"
if printf '%s' "$agent_out" | grep -q 'tools: \[read_file,run_shell_command\]'; then
  PASS=$((PASS + 1)); printf '  ok   %-56s [TRANSLATED]\n' "Claude tool CSV becomes a Gemini tool array"
else
  FAIL=$((FAIL + 1)); FAILED_NAMES+=("agent tool translation")
  printf '  FAIL %-56s got: %s\n' "Claude tool CSV becomes a Gemini tool array" "$(printf '%s' "$agent_out" | grep -i tools || echo none)"
fi
# Relative links must be re-anchored for the extra directory level. The canonical
# file is agents/<n>.md (depth 1) and links `](../core/...)`; the generated file is
# .gemini/agents/<n>.md (depth 2), where that same text points at nothing. Copying
# the body verbatim produces 24 links that resolve nowhere and break no test that
# only reads frontmatter.
link_broken=0
link_total=0
while IFS= read -r target; do
  link_total=$((link_total + 1))
  [ -e "$ROOT/.gemini/agents/$target" ] || link_broken=$((link_broken + 1))
done < <(sed -n 's/.*](\(\.\.\/[^)]*\)).*/\1/p' "$ROOT"/.gemini/agents/*.md 2>/dev/null)
if [ "$link_total" -gt 0 ] && [ "$link_broken" = 0 ]; then
  PASS=$((PASS + 1)); printf '  ok   %-56s [%s links]\n' "generated agent links resolve from .gemini/agents/" "$link_total"
else
  FAIL=$((FAIL + 1)); FAILED_NAMES+=("agent link re-anchoring")
  printf '  FAIL %-56s %s of %s relative links resolve nowhere\n' \
    "generated agent links resolve from .gemini/agents/" "$link_broken" "$link_total"
fi

# Executable bit: every other tests/test-*.sh carries it, and a harness that
# invokes them directly rather than through `bash` silently skips this one.
if [ -x "$ROOT/tests/test-gemini-adapter.sh" ]; then
  PASS=$((PASS + 1)); printf '  ok   %-56s [MODE]\n' "this test file is executable"
else
  FAIL=$((FAIL + 1)); FAILED_NAMES+=("executable bit")
  printf '  FAIL %-56s run: chmod +x tests/test-gemini-adapter.sh\n' "this test file is executable"
fi

if printf '%s' "$agent_out" | grep -q '^model:'; then
  FAIL=$((FAIL + 1)); FAILED_NAMES+=("model emitted")
  printf '  FAIL %-56s a model: line was emitted\n' "no model: is emitted into the Gemini agent"
else
  PASS=$((PASS + 1)); printf '  ok   %-56s [TRANSLATED]\n' "no model: is emitted into the Gemini agent"
fi

echo "--- live CLI: the one-level discovery claim the design rests on ---"
if command -v gemini >/dev/null 2>&1; then
  # An isolated HOME so the test never touches the developer's real
  # ~/.gemini state, and cleans up completely by deletion.
  PROBE="$TMPROOT/probe"
  mkdir -p "$PROBE/home" "$PROBE/ext/skills/flat-probe" "$PROBE/ext/skills/domain/nested-probe"
  jq -n '{name:"probe-ext",version:"0.0.1",description:"probe"}' > "$PROBE/ext/gemini-extension.json"
  printf -- '---\nname: flat-probe\ndescription: one level deep.\n---\nb\n'   > "$PROBE/ext/skills/flat-probe/SKILL.md"
  printf -- '---\nname: nested-probe\ndescription: two levels deep.\n---\nb\n' > "$PROBE/ext/skills/domain/nested-probe/SKILL.md"

  probe_out=$(cd "$PROBE/ext" && HOME="$PROBE/home" gemini extensions link "$PROBE/ext" --consent >/dev/null 2>&1 \
              && HOME="$PROBE/home" gemini extensions list 2>&1)

  if printf '%s' "$probe_out" | grep -q 'flat-probe'; then
    PASS=$((PASS + 1)); printf '  ok   %-56s [MEASURED]\n' "a one-level extension skill IS discovered"
  else
    FAIL=$((FAIL + 1)); FAILED_NAMES+=("flat skill discovery")
    printf '  FAIL %-56s gemini did not load the probe extension at all\n' "a one-level extension skill IS discovered"
  fi

  # The load-bearing claim. If this ever starts passing, Gemini gained recursive
  # discovery, the extension can carry the canonical skills, and
  # docs/user/install/gemini.md + platforms/gemini/adapter.yaml are both wrong.
  if printf '%s' "$probe_out" | grep -q 'nested-probe'; then
    FAIL=$((FAIL + 1)); FAILED_NAMES+=("nested skill discovery changed")
    printf '  FAIL %-56s Gemini now discovers nested skills — revisit the adapter\n' "a two-level extension skill is NOT discovered"
  else
    PASS=$((PASS + 1)); printf '  ok   %-56s [MEASURED]\n' "a two-level extension skill is NOT discovered"
  fi
  # The payoff: the real repo's generated mirror, read by the real CLI at the
  # workspace tier. Counting is the point — "the extension loaded" was already
  # true back when it carried zero skills.
  # folderTrust off in the throwaway HOME: an untrusted folder yields zero skills
  # and zero agents, which is indistinguishable from a broken mirror.
  # A SECOND throwaway HOME: the first one has the probe extension linked into it,
  # and its flat-probe skill would inflate the repo count by one.
  mkdir -p "$PROBE/home2/.gemini"
  echo '{"security":{"folderTrust":{"enabled":false}}}' > "$PROBE/home2/.gemini/settings.json"
  repo_out=$(cd "$ROOT" && HOME="$PROBE/home2" gemini skills list --all 2>&1)
  seen=$(printf '%s\n' "$repo_out" | grep -cE '^[a-z0-9-]+ \[Enabled\]$')
  want=$(find "$ROOT/skills" -mindepth 3 -maxdepth 3 -name SKILL.md | wc -l | tr -d ' ')
  if [ "$seen" = "$want" ] && [ "$want" != "0" ]; then
    PASS=$((PASS + 1)); printf '  ok   %-56s [MEASURED: %s]\n' "the real mirror is discovered, all of it" "$seen"
  else
    FAIL=$((FAIL + 1)); FAILED_NAMES+=("real mirror discovery")
    printf '  FAIL %-56s gemini saw %s skills, repo has %s\n' "the real mirror is discovered, all of it" "$seen" "$want"
  fi

  # The generated agents must LOAD, not merely exist. An untranslated tool name
  # is rejected per-file with the extension still loading, so nothing else here
  # would notice.
  if printf '%s' "$repo_out" | grep -qi 'Invalid tool name\|Error loading agent'; then
    FAIL=$((FAIL + 1)); FAILED_NAMES+=("generated agents rejected")
    printf '  FAIL %-56s %s\n' "generated agents load with no errors" \
      "$(printf '%s' "$repo_out" | grep -i 'Invalid tool name\|Error loading agent' | head -1)"
  else
    PASS=$((PASS + 1)); printf '  ok   %-56s [MEASURED]\n' "generated agents load with no errors"
  fi
else
  SKIP=$((SKIP + 1))
  printf '  skip %-56s [gemini not on PATH]\n' "one-level discovery + real mirror re-measurement"
  printf '       install with: npm i -g @google/gemini-cli\n'
fi

echo
echo "passed: $PASS   failed: $FAIL   skipped: $SKIP"
if [ "$FAIL" -ne 0 ]; then
  printf 'failing: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
