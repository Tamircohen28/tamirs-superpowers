#!/usr/bin/env bash
# check-agent-drift.sh — the agent-drift enforcement gate.
#
# Two halves:
#
#   FRONTMATTER — every SKILL.md validates against core/schemas/skill-frontmatter.json.
#
#   THIN-ADAPTER — the canonical-AGENTS.md model actually holds: the per-platform
#   adapters point AT AGENTS.md instead of restating it. This half used to be
#   missing, and its absence was load-bearing: the whole "Surface skills at the
#   moment they apply" section — heading, trigger table and rationale — sat
#   byte-for-byte identical in AGENTS.md and CLAUDE.md while this script reported
#   "no frontmatter drift detected" and the repo's gap scorer reported zero gaps.
#   A gate named for drift that never looked at the adapters is worse than no
#   gate, because it is quoted as evidence.
#
# Usage: bash scripts/check-agent-drift.sh [repo-root]
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

fail=0

echo "=== Agent drift check: skill frontmatter validation ==="
python3 scripts/validate-skill-frontmatter.py

echo "=== Agent drift check: thin adapters point at AGENTS.md ==="

if [ ! -f AGENTS.md ]; then
  echo "  FAIL  AGENTS.md is missing — it is the canonical entrypoint" >&2
  exit 1
fi

if grep -q 'AGENTS\.md' CLAUDE.md; then
  echo "  ok    CLAUDE.md references AGENTS.md"
else
  echo "  FAIL  CLAUDE.md never references AGENTS.md — it is not an adapter, it is a fork" >&2
  fail=1
fi

# At least one always-applied Cursor rule has to name the canonical entrypoint, or
# a Cursor session never learns AGENTS.md exists.
always_ref=0
for f in .cursor/rules/*.mdc; do
  [ -e "$f" ] || continue
  awk 'NR<=10 && /^alwaysApply:[[:space:]]*true[[:space:]]*$/ {found=1} END{exit !found}' "$f" || continue
  grep -q 'AGENTS\.md' "$f" && always_ref=1
done
if [ -d .cursor/rules ]; then
  if [ "$always_ref" -eq 1 ]; then
    echo "  ok    an alwaysApply Cursor rule references AGENTS.md"
  else
    echo "  FAIL  no alwaysApply:true .cursor/rules/*.mdc references AGENTS.md" >&2
    fail=1
  fi
fi

# The duplication check. Compare AGENTS.md and CLAUDE.md section by section: a
# '## ' heading present in both whose bodies are identical is policy maintained
# in two places, which is the drift this model exists to prevent. Platform-specific
# content under a shared heading is fine — only an exact match is a finding.
dupes="$(python3 - <<'PY'
import re, sys

def sections(path):
    text = open(path, encoding='utf-8').read()
    out, cur, buf = {}, None, []
    for line in text.splitlines():
        if line.startswith('## '):
            if cur is not None:
                out[cur] = '\n'.join(buf).strip()
            cur, buf = line[3:].strip(), []
        elif cur is not None:
            buf.append(line)
    if cur is not None:
        out[cur] = '\n'.join(buf).strip()
    return out

a, c = sections('AGENTS.md'), sections('CLAUDE.md')
for h in sorted(set(a) & set(c)):
    if a[h] and a[h] == c[h]:
        print(h)
PY
)"

if [ -n "$dupes" ]; then
  echo "  FAIL  these sections are byte-identical in AGENTS.md and CLAUDE.md:" >&2
  printf '%s\n' "$dupes" | sed 's/^/          /' >&2
  echo "        Keep the body in AGENTS.md and leave a one-line pointer in CLAUDE.md." >&2
  fail=1
else
  echo "  ok    no section body is duplicated between AGENTS.md and CLAUDE.md"
fi

# CATALOG — every canonical skill is listed in the user-facing catalog. The
# manifests are covered by tests/contract, but docs/user/skills.md is a hand-kept
# table: github-policy shipped as a real skill and was absent from it, from
# opencode.json, and from the copy-paste block in docs/user/install/opencode.md.
missing=""
while IFS= read -r skill; do
  name="$(basename "$(dirname "$skill")")"
  grep -q -- "$name" "$ROOT/docs/user/skills.md" || missing="$missing $name"
done < <(find "$ROOT/skills" -name SKILL.md -not -path '*/_contract/*' | sort)

if [ -n "$missing" ]; then
  echo "  FAIL  skills missing from docs/user/skills.md:$missing" >&2
  fail=1
else
  echo "  ok    every canonical skill appears in docs/user/skills.md"
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL — adapter drift detected" >&2
  exit 1
fi

echo "PASS — no frontmatter or adapter drift detected"
