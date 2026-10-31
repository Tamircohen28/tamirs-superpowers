#!/usr/bin/env bash
# Platform contract tests for the OpenCode adapter (REFACTOR-SPEC §22.4).
#
# WHAT THIS PINS
#   The OpenCode adapter has two halves with opposite failure modes.
#
#   Skills are NOT adapted — the canonical skills/ tree is read in place through
#   opencode.json `skills`. The failure mode there is a path that quietly
#   stops resolving (a renamed domain, a moved skill), which looks like nothing at
#   all until a user finds half the skills missing. So the paths are checked for
#   existence AND for actually containing skills, and the gold fixtures under
#   skills/repo/_contract/ are asserted NOT to be exposed.
#
#   Agents ARE adapted — .opencode/agents/*.md is generated from agents/*.md. The
#   failure mode there is drift: someone hand-edits an adapter, or adds a canonical
#   agent without regenerating. Both are caught by --check, and hand-editing is
#   caught again by the generated-header assertion.
#
#   The third failure mode is subtler and is the reason this file exists at all: an
#   adapter that LOADS but silently widens permissions. The canonical `tools:` field
#   is an allowlist, and OpenCode's base policy allows every action, so an agent
#   that names only its allowed tools leaves every other action ENABLED. A
#   read-only reviewer would gain shell, edit and subagent without anything
#   failing. So every adapter is asserted to deny explicitly.
#
#   The OpenCode 2 shape itself (plural dir, `mode: subagent`, `permissions:`
#   ruleset, action vocabulary, `external_directory: ask`, V2 commands, the
#   plugin, opencode.json) is pinned by tests/test-opencode-v2.sh; this file keeps
#   the platform-contract half that predates V2 and is shared with the contract
#   runner.
#
# These tests are schema/contract only and run without the OpenCode CLI. The
# optional live section runs only when `opencode` is on PATH.
#
# Exit 0 if all pass, 1 otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/scripts/build-opencode-agents.sh"
CONFIG="$ROOT/opencode.json"
SRC="$ROOT/agents"
DEST="$ROOT/.opencode/agents"

PASS=0
FAIL=0
FAILED_NAMES=()

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required to run these tests"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 is required to run these tests"; exit 1; }
[ -f "$BUILD" ]  || { echo "FATAL: generator not found at $BUILD"; exit 1; }
[ -f "$CONFIG" ] || { echo "FATAL: opencode.json not found at $CONFIG"; exit 1; }

# ok <name> / bad <name> <detail>
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s\n       %s\n' "$1" "$2"; }

# assert <name> <detail-on-failure> <command...>
assert() {
  local name="$1" detail="$2"; shift 2
  local out
  if out=$("$@" 2>&1); then ok "$name"; else bad "$name" "$detail: ${out:0:400}"; fi
}

echo "--- opencode.json: config contract ---"

assert "opencode.json is valid JSON" "jq could not parse it" \
  jq empty "$CONFIG"

schema=$(jq -r '."$schema" // ""' "$CONFIG")
if [ "$schema" = "https://opencode.ai/config.json" ]; then
  ok "declares the published \$schema (editors catch bad fields)"
else
  bad "declares the published \$schema" "got '$schema'"
fi

# `skills` is the mechanism the whole skills story rests on: WITHOUT it, a skills/
# tree at the repo root is not discovered at all (it is not one of the scanned
# locations). v2 takes a FLAT ARRAY of strings ("Additional paths or URLs to
# discover skills from"). ASSERT THE TYPE, NOT JUST A LENGTH: an object's
# `length` is its key count, so a `> 0` check alone would accept `{ "paths": [...] }`.
if jq -e '(.skills | type) == "array"' "$CONFIG" >/dev/null 2>&1; then
  ok "skills is a flat array (v2 contract)"
else
  bad "skills is a flat array (v2 contract)" "got type '$(jq -r '.skills | type // "missing"' "$CONFIG" 2>/dev/null)' — OpenCode 2 expects a flat array of strings"
fi
if jq -e '(.skills | length) > 0 and all(.skills[]; type == "string")' "$CONFIG" >/dev/null 2>&1; then
  ok "skills is non-empty and all entries are strings ($(jq -r '.skills | length' "$CONFIG") entries)"
else
  bad "skills is non-empty and all entries are strings" "empty, or a non-string entry — OpenCode would discover zero skills from this repo"
fi

echo "--- opencode.json: every skills entry resolves to real skills ---"

missing=0
empty=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if [ ! -d "$ROOT/$p" ]; then
    bad "skills entry exists: $p" "no such directory"
    missing=$((missing + 1))
    continue
  fi
  # skills entries recurse, so a domain dir or a zero-level
  # skill dir are both valid — either way it must yield at least one SKILL.md.
  if [ -z "$(find "$ROOT/$p" -name SKILL.md -print -quit)" ]; then
    bad "skills entry yields a skill: $p" "directory contains no SKILL.md"
    empty=$((empty + 1))
  fi
done < <(jq -r '.skills[]? | select(startswith("http") | not)' "$CONFIG")
[ "$missing" -eq 0 ] && ok "every local skills entry is an existing directory"
[ "$empty" -eq 0 ]   && ok "every local skills entry contains at least one SKILL.md"

# The contract fixtures are complete skill trees. Pointing at skills/repo wholesale
# exposes them as real user-facing skills, which is why the repo skills are listed
# individually. Assert the shortcut has not been taken.
leaked=()
while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ -d "$ROOT/$p" ] || continue
  if find "$ROOT/$p" -path '*/_contract/*' -name SKILL.md -print -quit | grep -q .; then
    leaked+=("$p")
  fi
done < <(jq -r '.skills[]? | select(startswith("http") | not)' "$CONFIG")
if [ "${#leaked[@]}" -eq 0 ]; then
  ok "no gold-fixture skills exposed via skills"
else
  bad "no gold-fixture skills exposed via skills" "these entries reach skills/repo/_contract/: ${leaked[*]}"
fi

echo "--- .opencode/agents: generated, in sync, not hand-edited ---"

assert "generator runs clean (--check passes; no drift from agents/)" \
  "run: make opencode-agents" \
  bash "$BUILD" "$ROOT" --check

# --check diffs the tree, so a canonical agent with no adapter (or the reverse) is
# already covered. This asserts the pairing directly, for a readable failure.
n_src=$(find "$SRC" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
n_dest=$(find "$DEST" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "$n_src" = "$n_dest" ] && [ "$n_src" -gt 0 ]; then
  ok "one adapter per canonical agent ($n_src)"
else
  bad "one adapter per canonical agent" "agents/=$n_src but .opencode/agents/=$n_dest"
fi

for f in "$SRC"/*.md; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  [ -f "$DEST/$b" ] || bad "adapter exists for $b" "missing $DEST/$b"
done

# Hand-editing is the thing the header exists to prevent; assert it is present and
# names the real source, so a copied-around file cannot pose as generated.
noheader=()
badsource=()
for f in "$DEST"/*.md; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  grep -q 'GENERATED FILE — DO NOT EDIT' "$f" || noheader+=("$b")
  grep -q "Source:    agents/$b" "$f"         || badsource+=("$b")
done
if [ "${#noheader[@]}" -eq 0 ]; then
  ok "every adapter carries the generated-file header"
else
  bad "every adapter carries the generated-file header" "missing in: ${noheader[*]}"
fi
if [ "${#badsource[@]}" -eq 0 ]; then
  ok "every adapter names its canonical source file"
else
  bad "every adapter names its canonical source file" "wrong/absent source in: ${badsource[*]}"
fi

echo "--- .opencode/agents: allowlist semantics survive translation ---"

# The defect this pins: canonical `tools: Read, Grep, Glob` is read-only, but an
# OpenCode agent listing only its granted tools leaves the rest ENABLED — the V2
# base policy starts with `{action: "*", resource: "*", effect: allow}` (measured
# with `opencode debug agents`). Every adapter that came from a canonical file with a
# `tools:` allowlist must therefore deny explicitly, or the role's read/write
# boundary is silently gone.
noperm=()
nodeny=()
for f in "$SRC"/*.md; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  [ -f "$DEST/$b" ] || continue
  # Only agents whose canonical file declares an allowlist are constrained.
  awk 'NR==1&&/^---/{fm=1;next} fm&&/^---/{exit} fm&&/^tools:/{found=1} END{exit !found}' "$f" || continue
  grep -q '^permissions:' "$DEST/$b" || { noperm+=("$b"); continue; }
  grep -qE '^    effect: deny$' "$DEST/$b" || nodeny+=("$b")
done
if [ "${#noperm[@]}" -eq 0 ]; then
  ok "adapters use the OpenCode 2 'permissions:' ruleset"
else
  bad "adapters use the OpenCode 2 'permissions:' ruleset" "missing permissions block: ${noperm[*]}"
fi
if [ "${#nodeny[@]}" -eq 0 ]; then
  ok "adapters deny non-granted actions explicitly (allowlist is not silently widened)"
else
  bad "adapters deny non-granted actions explicitly" "no deny rules in: ${nodeny[*]}"
fi

# The V1 map is deprecated and V2 only auto-translates it; this repo targets V2.
if grep -l '^permission:' "$DEST"/*.md >/dev/null 2>&1; then
  bad "adapters avoid the deprecated V1 'permission:' map" "still emitted in: $(grep -l '^permission:' "$DEST"/*.md | xargs -n1 basename | tr '\n' ' ')"
else
  ok "adapters avoid the deprecated V1 'permission:' map"
fi

# `tools:` is a deprecated V1 key (`AgentConfig.tools`); `Config.AgentEncoded` has no such field.
if grep -l '^tools:' "$DEST"/*.md >/dev/null 2>&1; then
  bad "adapters avoid the deprecated 'tools:' field" "still emitted in: $(grep -l '^tools:' "$DEST"/*.md | xargs -n1 basename | tr '\n' ' ')"
else
  ok "adapters avoid the deprecated 'tools:' field"
fi

# OpenCode derives the agent id from the FILENAME; `name` is not an AgentConfig
# property. Emitting it is noise that invites the belief that it is authoritative.
badmodel=()
for f in "$DEST"/*.md; do
  [ -e "$f" ] || continue
  m=$(awk 'NR==1&&/^---/{fm=1;next} fm&&/^---/{exit} fm&&/^model:/{sub(/^model:[[:space:]]*/,"");print;exit}' "$f")
  [ -z "$m" ] && continue
  case "$m" in */*) ;; *) badmodel+=("$(basename "$f")=$m") ;; esac
done
if [ "${#badmodel[@]}" -eq 0 ]; then
  ok "every adapter model id is provider-prefixed"
else
  bad "every adapter model id is provider-prefixed" "OpenCode rejects bare aliases: ${badmodel[*]}"
fi

echo "--- .opencode/agents: relative links survive the depth change ---"

# Canonical agents/<n>.md sits ONE level below the root, so its links read
# `](../core/policies/safety.md)`. The generated file sits at .opencode/agents/<n>.md —
# TWO levels down — where that identical text points at .opencode/core/..., which does
# not exist. Copying the body verbatim silently invalidates every relative link: the
# file still parses, still loads, and every link in it is dead.
#
# This is the same class of bug as the allowlist defect above, one step removed —
# there, meaning was lost in translation; here, CONTEXT is lost in relocation. Neither
# is visible to a frontmatter- or schema-only test, which is why both are asserted
# against reality instead: the links are resolved on the filesystem.
link_out=$(python3 - "$ROOT" <<'PY'
import glob, os, re, sys
root = sys.argv[1]
total = 0
broken = []
for f in sorted(glob.glob(os.path.join(root, ".opencode", "agents", "*.md"))):
    d = os.path.dirname(f)
    with open(f) as fh:
        body = fh.read()
    # Relative markdown link targets only: skip http(s), absolute paths and bare anchors.
    for link in re.findall(r"\]\((\.[^)#]*)", body):
        total += 1
        if not os.path.exists(os.path.normpath(os.path.join(d, link))):
            broken.append(f"{os.path.basename(f)} -> {link}")
print(f"{total}\t{len(broken)}\t" + "; ".join(broken[:6]))
PY
)
link_total=$(printf '%s' "$link_out" | cut -f1)
link_broken=$(printf '%s' "$link_out" | cut -f2)
link_detail=$(printf '%s' "$link_out" | cut -f3)
if [ "$link_total" -eq 0 ] 2>/dev/null; then
  printf '  ..   no relative links in generated adapters — nothing to resolve\n'
elif [ "$link_broken" = "0" ]; then
  ok "every relative link in the generated adapters resolves ($link_total checked)"
else
  bad "every relative link in the generated adapters resolves" \
      "$link_broken of $link_total resolve nowhere: $link_detail"
fi

echo "--- platforms/*/adapter.yaml: parse and agree with the capability registry ---"

REG="$ROOT/core/capabilities/platforms.json"
for d in "$ROOT"/platforms/*/; do
  [ -d "$d" ] || continue
  id="$(basename "$d")"
  # platforms/agent-plugins/ holds the generated Agent Plugins package files, not a
  # platform adapter (there is no surface to install into: the files ship at the root
  # of the agent-plugins tarball). Nothing else under platforms/ is exempt.
  [ "$id" = "agent-plugins" ] && continue
  y="$d/adapter.yaml"
  if [ ! -f "$y" ]; then
    bad "platforms/$id has an adapter.yaml" "missing $y"
    continue
  fi
  assert "platforms/$id/adapter.yaml parses as YAML" "invalid YAML" \
    python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$y"
done

# The four coarse capability keys are a SUMMARY of the registry. A summary that can
# disagree with the thing it summarises is worse than no summary, so assert equality
# rather than trusting the author. `agents` maps to the registry's `subagents`.
if [ -f "$REG" ]; then
  out=$(python3 - "$ROOT" "$REG" <<'PY'
import sys, os, glob, yaml, json
root, reg_path = sys.argv[1], sys.argv[2]
raw = json.load(open(reg_path))["platforms"]
# The registry is rooted at the platform and lists its runtime surfaces underneath;
# adapter.yaml registry_key names a SURFACE, so read the flat per-surface view.
reg = {sid: surf for p in raw.values() for sid, surf in (p.get("surfaces") or {"": p}).items()
       if surf.get("support", "supported") == "supported"}
# An unverified surface (no live run recorded) may still carry an adapter, provided the
# adapter says so too; its coarse keys are all `unknown` and there is no capability block
# to compare against, so the comparison is skipped for it.
unverified = {sid for p in raw.values() for sid, surf in (p.get("surfaces") or {}).items()
              if surf.get("support") == "unverified"}
alias = {"agents": "subagents"}
problems = []
for y in sorted(glob.glob(os.path.join(root, "platforms", "*", "adapter.yaml"))):
    a = yaml.safe_load(open(y))
    pid = os.path.basename(os.path.dirname(y))
    for field in ("id", "display_name", "registry_key", "capabilities", "install", "validation"):
        if field not in a:
            problems.append(f"{pid}: missing required field '{field}'")
    if a.get("id") != pid:
        problems.append(f"{pid}: id '{a.get('id')}' does not match directory name")
    key = a.get("registry_key")
    if key in unverified and key not in reg:
        if a.get("support") != "unverified":
            problems.append(f"{pid}: registry surface '{key}' is unverified but the adapter does not say support: unverified")
        bad_caps = [k for k, v in (a.get("capabilities") or {}).items() if v != "unknown"]
        if bad_caps:
            problems.append(f"{pid}: unverified surface '{key}' claims {bad_caps}; every coarse key must be unknown until a live run records one")
        continue
    if key not in reg:
        problems.append(f"{pid}: registry_key '{key}' not in core/capabilities/platforms.json")
        continue
    rcaps = reg[key]["capabilities"]
    for k, v in (a.get("capabilities") or {}).items():
        rk = alias.get(k, k)
        if rk not in rcaps:
            problems.append(f"{pid}: capability '{k}' has no registry counterpart '{rk}'")
        elif rcaps[rk]["status"] != v:
            problems.append(f"{pid}: '{k}' says '{v}' but registry '{rk}' says '{rcaps[rk]['status']}'")
    inst = a.get("install") or {}
    if inst.get("type") not in ("marketplace", "extension", "path"):
        problems.append(f"{pid}: install.type '{inst.get('type')}' is not marketplace|extension|path")
    doc = inst.get("doc")
    if doc and not os.path.exists(os.path.join(root, doc)):
        problems.append(f"{pid}: install.doc '{doc}' does not exist")
    man = a.get("manifest")
    if man and not os.path.exists(os.path.join(root, man)):
        problems.append(f"{pid}: manifest '{man}' does not exist")
    if not (a.get("validation") or {}).get("command"):
        problems.append(f"{pid}: validation.command is empty")
if problems:
    print("\n".join(problems)); sys.exit(1)
PY
  )
  if [ $? -eq 0 ]; then
    ok "adapter.yaml metadata matches the capability registry"
  else
    bad "adapter.yaml metadata matches the capability registry" "$out"
  fi
else
  printf '  skip core/capabilities/platforms.json not present — registry cross-check skipped\n'
fi

echo "--- live OpenCode CLI (optional) ---"

ver=""
command -v opencode >/dev/null 2>&1 && ver="$(opencode --version 2>/dev/null | head -1)"
oc_ver="$(printf '%s' "$ver" | sed -n 's/^[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')"
# A build below targets.opencode.supported_min is skipped, not failed (see test-opencode-v2.sh).
oc_floor="$(jq -r '.targets.opencode.supported_min // empty' "$ROOT/docs/engineering/build-and-release/platform-targets.json")"
if [ -n "$oc_ver" ] && [ -n "$oc_floor" ] && [ "$(printf '%s\n%s\n' "$oc_floor" "$oc_ver" | sort -V | head -1)" = "$oc_floor" ]; then
  printf '  ..   opencode %s detected\n' "$ver"

  # OpenCode 2 removed `debug skill` and the per-agent `debug agent <name>`; its
  # debug surface is `agents` (every resolved agent, JSON), `config` and `paths`
  # (measured on 2.0.32). Skill discovery therefore cannot be enumerated from the
  # CLI — `opencode api --standalone skill.list` returned an empty list on 2.0.32
  # even for agents `debug agents` lists — and stays unverified live.
  agents_json="$(cd "$ROOT" && opencode debug agents 2>/dev/null)"
  if [ -n "$agents_json" ]; then
    loaded="$(printf '%s' "$agents_json" | jq -r '.[] | select(.system // "" | contains("GENERATED FILE — DO NOT EDIT")) | .id' 2>/dev/null)"
    loadfail=()
    for f in "$DEST"/*.md; do
      [ -e "$f" ] || continue
      a="$(basename "${f%.md}")"
      printf '%s\n' "$loaded" | grep -qx "$a" || loadfail+=("$a")
    done
    if [ "${#loadfail[@]}" -eq 0 ]; then
      ok "every generated adapter loads in OpenCode (debug agents)"
    else
      bad "every generated adapter loads in OpenCode (debug agents)" "not listed: ${loadfail[*]}"
    fi
  else
    bad "opencode debug agents succeeds" "command produced no output in $ROOT"
  fi
  printf '  skip per-skill discovery — OpenCode 2 has no CLI enumeration (see header)\n'
else
  printf '  skip opencode CLI %s — schema/contract tests only\n' "$([ -n "$ver" ] && echo "$ver is below the supported floor ${oc_floor:-unknown}" || echo 'not on PATH')"
fi

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'failing: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
