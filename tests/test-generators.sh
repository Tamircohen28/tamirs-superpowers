#!/usr/bin/env bash
# Generator contract tests: .cursor/rules/*.mdc and .codex/agents/*.toml.
#
# WHAT THIS PINS
#   Two adapter surfaces that were hand-maintained are now generated output:
#     .cursor/rules/<rule>.mdc   from rules/dev/*.md + platforms/cursor/rules.map.json
#                                (scripts/build-cursor-rules.sh)
#     .codex/agents/<name>.toml  from agents/*.md (scripts/build-codex-agents.sh)
#
#   The failure modes are the usual two for generated files — someone hand-edits the
#   output, or adds a canonical source without regenerating — plus three that are
#   specific to these generators and would otherwise be invisible:
#     - a `--check` that passes on a drifted tree (so a planted drift MUST fail it);
#     - a manual Cursor adapter that a regenerate rewrites or prunes (the five
#       `manual: true` entries carry hand-written Cursor prose with no rules/dev source);
#     - a Codex body that does not survive the trip through TOML — a `'''` in the
#       Markdown breaks a literal string, so the fallback path is exercised with a
#       planted agent and parsed back with tomllib, byte for byte.
#
# Runs without any platform CLI. Needs jq and python3 >= 3.11 (tomllib).
# Exit 0 if all pass, 1 otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CURSOR_BUILD="$ROOT/scripts/build-cursor-rules.sh"
CODEX_BUILD="$ROOT/scripts/build-codex-agents.sh"
MAP="$ROOT/platforms/cursor/rules.map.json"

PASS=0
FAIL=0
FAILED_NAMES=()

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required to run these tests"; exit 1; }
python3 -c 'import tomllib' >/dev/null 2>&1 || { echo "FATAL: python3 >= 3.11 (tomllib) is required to run these tests"; exit 1; }
[ -x "$CURSOR_BUILD" ] || { echo "FATAL: generator not found or not executable at $CURSOR_BUILD"; exit 1; }
[ -x "$CODEX_BUILD" ]  || { echo "FATAL: generator not found or not executable at $CODEX_BUILD"; exit 1; }
[ -f "$MAP" ]          || { echo "FATAL: map not found at $MAP"; exit 1; }

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s\n       %s\n' "$1" "$2"; }

# assert <name> <detail-on-failure> <command...>
assert() {
  local name="$1" detail="$2"; shift 2
  local out
  if out=$("$@" 2>&1); then ok "$name"; else bad "$name" "$detail: ${out:0:400}"; fi
}

# assert_exit <name> <expected-code> <command...>
assert_exit() {
  local name="$1" want="$2"; shift 2
  local out got
  out=$("$@" 2>&1); got=$?
  if [ "$got" -eq "$want" ]; then ok "$name"; else bad "$name" "expected exit $want, got $got: ${out:0:400}"; fi
}

# A scratch copy of just what the two generators read, so drift can be planted
# without touching the working tree. The generators take the root as an argument
# and run from their real path, so the copy needs no scripts/.
make_copy() {
  local dst="$1"
  mkdir -p "$dst/platforms/cursor" "$dst/core/policies" "$dst/core/schemas" "$dst/.cursor" "$dst/.codex"
  cp -R "$ROOT/rules" "$dst/rules"
  cp -R "$ROOT/agents" "$dst/agents"
  cp -R "$ROOT/.cursor/rules" "$dst/.cursor/rules"
  cp -R "$ROOT/.codex/agents" "$dst/.codex/agents"
  cp "$MAP" "$dst/platforms/cursor/rules.map.json"
  # Sources the manual entries point at (existence is checked, content is not).
  cp "$ROOT/AGENTS.md" "$dst/AGENTS.md"
  cp "$ROOT/core/policies/git.md" "$dst/core/policies/git.md"
  cp "$ROOT/core/schemas/skill-frontmatter.json" "$dst/core/schemas/skill-frontmatter.json"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "--- both generators: --check passes on the committed tree ---"

assert_exit "build-cursor-rules.sh --check passes on the tree" 0 bash "$CURSOR_BUILD" "$ROOT" --check
assert_exit "build-codex-agents.sh --check passes on the tree" 0 bash "$CODEX_BUILD" "$ROOT" --check
assert_exit "build-cursor-rules.sh --help exits 0" 0 bash "$CURSOR_BUILD" --help
assert_exit "build-codex-agents.sh --help exits 0" 0 bash "$CODEX_BUILD" --help
assert_exit "build-cursor-rules.sh rejects an unknown flag" 1 bash "$CURSOR_BUILD" "$ROOT" --bogus
assert_exit "build-codex-agents.sh rejects an unknown flag" 1 bash "$CODEX_BUILD" "$ROOT" --bogus

echo "--- planted drift fails --check (temp copy, working tree untouched) ---"

C="$TMP/drift-mdc"; make_copy "$C"
printf '\nhand edit\n' >> "$C/.cursor/rules/dev-files-workspace.mdc"
assert_exit "hand-edited generated .mdc fails cursor --check" 1 bash "$CURSOR_BUILD" "$C" --check

C="$TMP/drift-toml"; make_copy "$C"
printf '\n# hand edit\n' >> "$C/.codex/agents/implementer.toml"
assert_exit "hand-edited .toml fails codex --check" 1 bash "$CODEX_BUILD" "$C" --check

C="$TMP/drift-src"; make_copy "$C"
printf '\nNew canonical paragraph.\n' >> "$C/agents/implementer.md"
assert_exit "edited canonical agent without regenerate fails codex --check" 1 bash "$CODEX_BUILD" "$C" --check

C="$TMP/drift-map"; make_copy "$C"
jq '.rules["dev-files-workspace"].summary += ["", "New summary line from the map."]' "$MAP" > "$C/platforms/cursor/rules.map.json"
assert_exit "edited map without regenerate fails cursor --check" 1 bash "$CURSOR_BUILD" "$C" --check

C="$TMP/drift-missing-manual"; make_copy "$C"
rm -f "$C/.cursor/rules/plugin-structure.mdc"
assert_exit "a missing manual adapter fails cursor --check" 1 bash "$CURSOR_BUILD" "$C" --check

C="$TMP/drift-manual-nofm"; make_copy "$C"
printf 'no frontmatter here\n' > "$C/.cursor/rules/hooks-guide.mdc"
assert_exit "a manual adapter without frontmatter fails cursor --check" 1 bash "$CURSOR_BUILD" "$C" --check

C="$TMP/drift-unmapped-rule"; make_copy "$C"
printf '# A new rule\n\nBody.\n' > "$C/rules/dev/brand-new-rule.md"
assert_exit "a rules/dev rule with no map entry is a build error (exit 2)" 2 bash "$CURSOR_BUILD" "$C" --check

C="$TMP/drift-stale"; make_copy "$C"
printf -- '---\nalwaysApply: false\n---\n\nstale\n' > "$C/.cursor/rules/left-behind.mdc"
assert_exit "an .mdc the map does not name fails cursor --check" 1 bash "$CURSOR_BUILD" "$C" --check
assert_exit "a normal run prunes the unmapped .mdc" 0 bash "$CURSOR_BUILD" "$C"
assert "pruned file is gone after the normal run" "left-behind.mdc still present" \
  test ! -e "$C/.cursor/rules/left-behind.mdc"

C="$TMP/drift-deleted-agent"; make_copy "$C"
rm -f "$C/agents/spec-reviewer.md"
assert_exit "a deleted canonical agent fails codex --check" 1 bash "$CODEX_BUILD" "$C" --check
assert_exit "a normal run prunes the orphaned .toml" 0 bash "$CODEX_BUILD" "$C"
assert "orphaned spec-reviewer.toml is gone after the normal run" "still present" \
  test ! -e "$C/.codex/agents/spec-reviewer.toml"

echo "--- Cursor rules: coverage and shape ---"

missing=""
while IFS= read -r f; do
  base="$(basename "$f" .md)"
  [ "$base" = "README" ] && continue
  [ -f "$ROOT/.cursor/rules/$base.mdc" ] || missing="$missing $base"
done < <(find "$ROOT/rules/dev" -maxdepth 1 -name '*.md' | sort)
assert "every rules/dev rule has a .cursor/rules/<basename>.mdc" "missing:$missing" test -z "$missing"

nogen=""
nofm=""
nopointer=""
while IFS= read -r key; do
  f="$ROOT/.cursor/rules/$key.mdc"
  head -1 "$f" | grep -q '^---' || nofm="$nofm $key"
  grep -q 'GENERATED FILE — DO NOT EDIT' "$f" || nogen="$nogen $key"
  grep -q "Canonical rule: \`rules/dev/$key.md\`" "$f" || nopointer="$nopointer $key"
done < <(jq -r '.rules | to_entries[] | select(.value.manual != true) | .key' "$MAP")
assert "every generated .mdc opens with YAML frontmatter" "no frontmatter:$nofm" test -z "$nofm"
assert "every generated .mdc carries the generated-file marker" "no marker:$nogen" test -z "$nogen"
assert "every generated .mdc points at its canonical rule" "no pointer:$nopointer" test -z "$nopointer"

marked=""
unlisted_src=""
while IFS= read -r key; do
  f="$ROOT/.cursor/rules/$key.mdc"
  grep -q 'GENERATED FILE — DO NOT EDIT' "$f" && marked="$marked $key"
  src="$(jq -r --arg k "$key" '.rules[$k].source' "$MAP")"
  [ -e "$ROOT/${src%%#*}" ] || unlisted_src="$unlisted_src $key"
done < <(jq -r '.rules | to_entries[] | select(.value.manual == true) | .key' "$MAP")
assert "no manual .mdc carries the generated-file marker" "marked:$marked" test -z "$marked"
assert "every manual entry names a canonical source that exists" "dangling:$unlisted_src" test -z "$unlisted_src"

nmanual="$(jq -r '[.rules[] | select(.manual == true)] | length' "$MAP")"
assert "the map lists exactly the five manual adapters" "got $nmanual" test "$nmanual" -eq 5

echo "--- Cursor rules: a regenerate leaves manual adapters byte-identical ---"

C="$TMP/regen"; make_copy "$C"
before="$TMP/manual-before.txt"; after="$TMP/manual-after.txt"
manual_sum() {
  while IFS= read -r key; do
    python3 -I -c 'import hashlib,sys;print(sys.argv[1], hashlib.sha256(open(sys.argv[2],"rb").read()).hexdigest())' \
      "$key" "$1/.cursor/rules/$key.mdc"
  done < <(jq -r '.rules | to_entries[] | select(.value.manual == true) | .key' "$MAP")
}
manual_sum "$C" > "$before"
assert_exit "regenerate (normal mode) succeeds in the copy" 0 bash "$CURSOR_BUILD" "$C"
manual_sum "$C" > "$after"
assert "manual adapters are untouched by a regenerate" "$(diff "$before" "$after" 2>&1 | head -5)" diff -q "$before" "$after"
assert "regenerate in the copy reproduces the committed generated files" "diff" \
  diff -r -q "$ROOT/.cursor/rules" "$C/.cursor/rules"

echo "--- Codex agents: every agent has a parseable .toml whose name matches ---"

for f in "$ROOT"/agents/*.md; do
  base="$(basename "$f" .md)"
  fm_name="$(awk 'NR==1{next} /^---/{exit} /^name:[[:space:]]*/{sub(/^name:[[:space:]]*/,""); print; exit}' "$f")"
  toml="$ROOT/.codex/agents/$base.toml"
  assert "agents/$base.md -> .codex/agents/$base.toml exists" "missing" test -f "$toml"
  [ -f "$toml" ] || continue
  assert ".codex/agents/$base.toml parses and name matches frontmatter ($fm_name)" "mismatch or parse error" \
    python3 -I - "$toml" "$fm_name" <<'PY'
import sys, tomllib
data = tomllib.loads(open(sys.argv[1], encoding="utf-8").read())
assert data["name"] == sys.argv[2], f"name {data['name']!r} != {sys.argv[2]!r}"
assert data["description"].strip(), "empty description"
assert data["developer_instructions"].strip(), "empty developer_instructions"
assert "model" not in data and not any(k.startswith("model_") for k in data), "a model field was emitted"
for k in data.get("features", {}):
    assert k in {"shell_tool", "apps", "plugins", "memories", "request_permissions_tool"}, f"undocumented features.{k}"
PY
done

nomarker=""
for t in "$ROOT"/.codex/agents/*.toml; do
  head -1 "$t" | grep -q '^# GENERATED FILE — DO NOT EDIT' || nomarker="$nomarker $(basename "$t")"
done
assert "every .toml opens with the generated-file comment" "no marker:$nomarker" test -z "$nomarker"

orphan=""
for t in "$ROOT"/.codex/agents/*.toml; do
  b="$(basename "$t" .toml)"
  [ -f "$ROOT/agents/$b.md" ] || orphan="$orphan $b"
done
assert "no .toml without a canonical agent" "orphans:$orphan" test -z "$orphan"

# shell_tool follows the canonical allowlist: no Bash -> false; Bash -> no reduction.
wrong=""
for f in "$ROOT"/agents/*.md; do
  base="$(basename "$f" .md)"
  tools="$(awk 'NR==1{next} /^---/{exit} /^tools:[[:space:]]*/{sub(/^tools:[[:space:]]*/,""); print; exit}' "$f")"
  has_shell=no; printf '%s\n' "$tools" | tr ',' '\n' | tr -d ' ' | grep -qi '^bash$' && has_shell=yes
  reduced=no; grep -q '^shell_tool = false$' "$ROOT/.codex/agents/$base.toml" && reduced=yes
  if [ -n "$tools" ] && [ "$has_shell" = no ] && [ "$reduced" = no ]; then wrong="$wrong $base(no-bash,not-reduced)"; fi
  if [ "$has_shell" = yes ] && [ "$reduced" = yes ]; then wrong="$wrong $base(bash,reduced)"; fi
done
assert "features.shell_tool = false exactly for allowlists without Bash" "wrong:$wrong" test -z "$wrong"

nomodel="$(grep -il '^model' "$ROOT"/.codex/agents/*.toml 2>/dev/null || true)"
assert "no .toml carries a model key" "found: $nomodel" test -z "$nomodel"

echo "--- Codex agents: a body with ''' (and quotes, backslashes) round-trips ---"

C="$TMP/roundtrip"; make_copy "$C"
cat > "$C/agents/probe-agent.md" <<'EOF'
---
name: probe-agent
description: Probe agent with "quotes" and a \backslash in its description.
role: reviewer
tools: Read, Grep
model: sonnet
---

# Probe

A body with a TOML literal-string terminator: ''' right here, and a second one '''.
It also has "double quotes", a \backslash, a `code span`, and tabs	like this.
Relative link rebased: [`core/policies/safety.md`](../core/policies/safety.md).

```toml
x = '''not a problem'''
```
EOF
cat > "$C/agents/probe-plain.md" <<'EOF'
---
name: probe-plain
description: Plain probe
role: reviewer
tools: Read, Grep, Bash
model: sonnet
---

Backslashes \n \t "stay literal" and 'single quotes' too, even two: ''.
EOF
assert_exit "generator accepts the probe agents" 0 bash "$CODEX_BUILD" "$C"
assert "''' body round-trips through tomllib byte for byte" "mismatch" \
  python3 -I - "$C" <<'PY'
import sys, tomllib, pathlib, re
root = pathlib.Path(sys.argv[1])
def expected(md):
    text = md.read_text(encoding="utf-8")
    body = text.split("\n---\n", 1)[1]
    body = body.replace("](../", "](")
    lines = body.split("\n")
    while lines and not lines[0].strip(): lines.pop(0)
    while lines and not lines[-1].strip(): lines.pop()
    return "\n".join(lines) + "\n"
for name in ("probe-agent", "probe-plain"):
    toml_path = root / ".codex" / "agents" / f"{name}.toml"
    data = tomllib.loads(toml_path.read_text(encoding="utf-8"))
    want = expected(root / "agents" / f"{name}.md")
    got = data["developer_instructions"]
    assert got == want, f"{name}: round-trip mismatch\n--- want\n{want!r}\n--- got\n{got!r}"
    assert data["name"] == name
probe = tomllib.loads((root / ".codex/agents/probe-agent.toml").read_text(encoding="utf-8"))
assert probe["description"] == 'Probe agent with "quotes" and a \\backslash in its description.', probe["description"]
assert probe["features"] == {"shell_tool": False}, probe.get("features")
plain = tomllib.loads((root / ".codex/agents/probe-plain.toml").read_text(encoding="utf-8"))
assert "features" not in plain, plain.get("features")
text = (root / ".codex/agents/probe-agent.toml").read_text(encoding="utf-8")
assert 'developer_instructions = """' in text, "''' body should use the basic-string fallback"
text = (root / ".codex/agents/probe-plain.toml").read_text(encoding="utf-8")
assert "developer_instructions = '''" in text, "plain body should use the literal string"
PY

echo
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  printf '  failed: %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
exit 0
