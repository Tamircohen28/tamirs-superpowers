#!/usr/bin/env bash
# smoke.sh — full plugin health check for tamirs-superpowers
# Run from repo root: bash .claude/skills/run-tamirs-superpowers/smoke.sh
# Exit 0 = all pass, 1 = failures found

ROOT="$(git rev-parse --show-toplevel)" || {
  echo "smoke.sh: not inside a git repository" >&2; exit 1
}
cd "$ROOT" || { echo "smoke.sh: cannot cd to repo root '$ROOT'" >&2; exit 1; }

PASS=0; FAIL=0; WARN=0

ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }
warn() { echo "  WARN  $1"; WARN=$((WARN+1)); }

# ── 1. make validate (shellcheck + JSON + frontmatter) ─────────────────────
echo ""
echo "=== 1. make validate ==="
if make validate 2>&1 | grep -q "All local checks passed"; then
  ok "make validate"
else
  fail "make validate — run it directly to see errors"
fi

# ── 2. Statusline script ───────────────────────────────────────────────────
echo ""
echo "=== 2. statusline.sh ==="
output=$(bash scripts/statusline.sh 2>&1) || true
if echo "$output" | grep -qE '(ctx:|h:)'; then
  ok "statusline.sh — output: $(echo "$output" | head -1)"
else
  fail "statusline.sh — unexpected or empty output: $output"
fi

# ── 3. plugin.json required fields ────────────────────────────────────────
echo ""
echo "=== 3. plugin.json structure ==="
for field in name version description homepage; do
  val=$(jq -r ".$field // empty" .claude-plugin/plugin.json 2>/dev/null) || val=""
  if [ -n "$val" ]; then
    ok "plugin.json .$field = $val"
  else
    fail "plugin.json missing .$field"
  fi
done
sl_type=$(jq -r '.settings.statusLine | type' .claude-plugin/plugin.json 2>/dev/null) || sl_type="error"
if [ "$sl_type" = "object" ]; then
  ok "plugin.json .settings.statusLine is an object"
else
  fail "plugin.json .settings.statusLine must be object not $sl_type"
fi

# ── 4. SKILL.md frontmatter (full official field set) ─────────────────────
echo ""
echo "=== 4. SKILL.md frontmatter ==="
if python3 scripts/validate-skill-frontmatter.py >/dev/null 2>&1; then
  ok "all SKILL.md frontmatter fields"
else
  fail "SKILL.md frontmatter — run: python3 scripts/validate-skill-frontmatter.py"
fi

# ── 5. Hook wiring check ──────────────────────────────────────────────────
echo ""
echo "=== 5. Hook wiring ==="
while IFS= read -r script; do
  base=$(basename "$script")
  if grep -q "$base" hooks/hooks.json 2>/dev/null; then
    ok "wired: $base"
  else
    warn "NOT in hooks.json: $base (may be intentional)"
  fi
done < <(find hooks -maxdepth 1 -name '*.sh')

# ── 6. No hardcoded /Users/ paths in skills ──────────────────────────────
echo ""
echo "=== 6. No hardcoded /Users/ paths in skills ==="
hits=$(grep -rl '/Users/' skills/ --include='*.md' 2>/dev/null | grep -v '.git' || true)
if [ -z "$hits" ]; then
  ok "no /Users/ paths in skill files"
else
  for f in $hits; do warn "hardcoded /Users/ path in $f"; done
fi

# ── 7. No employer/internal references ───────────────────────────────────
# No employer is named in the pattern: a public repo that hardcodes one ships the
# very reference this check exists to catch. Generic internal-hostname shapes need
# no private name; $TAMIRS_EMPLOYER_PATTERN adds a per-machine regex, the same seam
# scripts/lib/capture-common.sh uses. Documentation domains (.example/.invalid/
# .test) are excluded — they exist so docs need no real internal hostname.
echo ""
echo "=== 7. No employer/internal references ==="
internal_re='[A-Za-z0-9-]+\.(corp|internal|intranet)\b|#skipreview'
[ -n "${TAMIRS_EMPLOYER_PATTERN:-}" ] && internal_re="$internal_re|$TAMIRS_EMPLOYER_PATTERN"
internal_hits=$(grep -rlEi "$internal_re" skills/ --include='*.md' 2>/dev/null \
  | while IFS= read -r f; do
      grep -Ei "$internal_re" "$f" | grep -qvE '\.(example|invalid|test)\b' && printf '%s\n' "$f"
    done || true)
if [ -z "$internal_hits" ]; then
  ok "no employer/internal references in skills"
else
  for f in $internal_hits; do warn "employer/internal reference in $f"; done
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo "  PASS: $PASS  |  WARN: $WARN  |  FAIL: $FAIL"
echo "══════════════════════════════════════════"

if [ $FAIL -eq 0 ]; then
  echo "Plugin health: OK (warnings=$WARN)"
  exit 0
else
  echo "Plugin health: DEGRADED ($FAIL failures)"
  exit 1
fi
