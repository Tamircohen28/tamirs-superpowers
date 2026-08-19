#!/usr/bin/env bash
# test-readme-branding.sh — the four README branding defects, and their controls.
#
# WHY EVERY NEGATIVE HAS A POSITIVE CONTROL
#   A checker that never fires and a checker that always passes are the same green
#   dot. Each defect below is asserted twice: once on a README that HAS it (the
#   check must fire) and once on the corrected README (the check must go quiet).
#   Every case is built in a temp dir from literal text — nothing here reads the
#   live repo except the two "the shipped artifacts are clean" assertions at the
#   end, which are the point of the exercise.
#
# Usage: bash tests/test-readme-branding.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require jq python3
CHECK="$REPO_ROOT/skills/repo/_contract/scripts/check-readme-branding.sh"
INVENTORY="$REPO_ROOT/skills/repo/_contract/scripts/standards-inventory.sh"
SCORE="$REPO_ROOT/skills/repo/_contract/scripts/score-standards-gaps.sh"
CONTRACT="$REPO_ROOT/skills/repo/_contract"

TMP="$(harness_tmpdir)"

# case <name> — a fresh repo root; echoes its path.
case_dir() {
  local d="$TMP/$1"
  mkdir -p "$d/assets" "$d/docs/engineering/build-and-release"
  printf '%s\n' "$d"
}

fact() { bash "$CHECK" "$1" --json | jq -r "$2"; }

# A banner that passes the bar, written into <dir>/assets/banner.svg. Shapes are
# generated so the count is unambiguous rather than something a reader has to
# tally by eye.
good_banner() {
  local dir="$1" i
  {
    printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="400" viewBox="0 0 1200 400">'
    printf '%s\n' '  <title>fixture</title>'
    printf '%s\n' '  <desc>Motif: a pipeline of stages feeding one output — what this fixture project does.</desc>'
    printf '%s\n' '  <defs><linearGradient id="g"><stop offset="0" stop-color="#3DDC97"/><stop offset="1" stop-color="#0E5C6B"/></linearGradient></defs>'
    printf '%s\n' '  <rect width="1200" height="400" fill="#0B0E14"/>'
    for i in $(seq 1 20); do
      printf '  <circle cx="%d" cy="200" r="12" fill="url(#g)" opacity="0.8"/>\n' $(( 60 + i * 50 ))
    done
    printf '%s\n' '  <text x="96" y="190" font-size="56" fill="#E6EDF3">fixture</text>'
    printf '%s\n' '</svg>'
  } >"$dir/assets/banner.svg"
}

# A banner that fails it: the old art direction, rendered literally.
text_banner() {
  cat >"$1/assets/banner.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="600" height="200" viewBox="0 0 600 200">
  <rect width="600" height="200" fill="#0F1117"/>
  <rect width="600" height="3" y="197" fill="#0F6E56"/>
  <text x="300" y="105" font-size="36" fill="#E6EDF3" text-anchor="middle">fixture</text>
  <text x="300" y="135" font-size="14" fill="#8B949E" text-anchor="middle">a one-line description</text>
</svg>
SVG
}

targets_json() {
  cat >"$1/docs/engineering/build-and-release/platform-targets.json" <<'JSON'
{
  "schema_version": 2,
  "last_reviewed": "2026-08-19",
  "supported_targets": ["claude_code", "cursor"],
  "targets": {
    "claude_code": {"validated_against": "2.1.233", "latest_known": "2.1.233"},
    "cursor": {"validated_against": "3.16.17", "latest_known": "3.16.17"}
  }
}
JSON
}

# ===========================================================================
section "1. badge anchors — whitespace inside <a> is link text"
# ===========================================================================

d="$(case_dir anchor-bad)"; good_banner "$d"
cat >"$d/README.md" <<'MD'
<p align="center">
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT" />
  </a>
</p>

# fixture

## Quick Start
MD
judge "multi-line <a> wrapping an <img> is detected" 2 \
  "$(fact "$d" '.branding.anchor_form.multiline_img_anchors')"
judge "  ... and the human report exits non-zero" 1 \
  "$(bash "$CHECK" "$d" >/dev/null 2>&1; echo $?)"

d="$(case_dir anchor-good)"; good_banner "$d"
cat >"$d/README.md" <<'MD'
<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT" /></a>
  <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/version-1.0.0-blue" alt="Version" /></a>
</p>

# fixture

## Quick Start
MD
judge "positive control: single-line anchors are clean" 0 \
  "$(fact "$d" '.branding.anchor_form.multiline_img_anchors')"

# A wrapped anchor around PROSE is not this defect and must not be reported: the
# check is about badge rendering, not line length.
d="$(case_dir anchor-prose)"; good_banner "$d"
cat >"$d/README.md" <<'MD'
<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT" /></a>
</p>

# fixture

Read the
<a href="docs/README.md">
  documentation
</a>
first.

## Quick Start
MD
judge "a multi-line anchor around prose is NOT flagged" 0 \
  "$(fact "$d" '.branding.anchor_form.multiline_img_anchors')"

# ===========================================================================
section "2. AI-target badge versions vs platform-targets.json"
# ===========================================================================

badge_readme() {
  cat >"$1/README.md" <<MD
<p align="center">
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Claude%20Code-$2-blueviolet" alt="Claude Code" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Cursor-$3-000000" alt="Cursor" /></a>
</p>

# fixture

## Quick Start
MD
}

d="$(case_dir badge-stale)"; good_banner "$d"; targets_json "$d"
badge_readme "$d" 2.0.0 0.45.0
judge "stale badge versions are detected" 2 \
  "$(fact "$d" '.branding.badge_versions.mismatches | length')"
judge "  ... and the mismatch names both sides" \
  "claude_code 2.0.0 2.1.233" \
  "$(fact "$d" '[.branding.badge_versions.mismatches[] | select(.target=="claude_code")][0] | "\(.target) \(.readme) \(.platform_targets)"')"

d="$(case_dir badge-fresh)"; good_banner "$d"; targets_json "$d"
badge_readme "$d" 2.1.233 3.16.17
judge "positive control: badges matching validated_against pass" 0 \
  "$(fact "$d" '.branding.badge_versions.mismatches | length')"
judge "  ... and both targets were actually compared" 2 \
  "$(fact "$d" '.branding.badge_versions.matched')"

# A repo with no platform-targets.json has nothing to disagree with.
d="$(case_dir badge-no-targets)"; good_banner "$d"
badge_readme "$d" 9.9.9 9.9.9
judge "no platform-targets.json -> the badge check skips, not fails" false \
  "$(fact "$d" '.branding.badge_versions.checked')"
judge "  ... and the run as a whole still passes" 0 \
  "$(bash "$CHECK" "$d" >/dev/null 2>&1; echo $?)"

# "unknown" is an honest not-yet-validated state and carries no badge by design.
d="$(case_dir badge-unknown)"; good_banner "$d"; targets_json "$d"
python3 - "$d" <<'PY'
import json, sys
p = sys.argv[1] + "/docs/engineering/build-and-release/platform-targets.json"
d = json.load(open(p))
d["targets"]["cursor"]["validated_against"] = "unknown"
json.dump(d, open(p, "w"))
PY
badge_readme "$d" 2.1.233 0.45.0
judge "a target with validated_against=unknown is not compared" 0 \
  "$(fact "$d" '.branding.badge_versions.mismatches | length')"

# ===========================================================================
section "3. emoji in the README header"
# ===========================================================================

d="$(case_dir emoji-header)"; good_banner "$d"
cat >"$d/README.md" <<'MD'
<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT" /></a>
</p>

# fixture 🏠

An apartment hunter.

## Quick Start
MD
judge "emoji in the H1 is detected" 1 "$(fact "$d" '.branding.header_emoji.count')"

d="$(case_dir emoji-body)"; good_banner "$d"
cat >"$d/README.md" <<'MD'
<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT" /></a>
</p>

# fixture

An apartment hunter.

## Quick Start

Ship it 🚀 — emoji below the first `##` heading is allowed. 🏠 ✅
MD
judge "positive control: emoji in body prose is allowed" 0 \
  "$(fact "$d" '.branding.header_emoji.count')"
judge "  ... and the header region stopped at the first '##'" 8 \
  "$(fact "$d" '.branding.header_emoji.header_lines')"

# Em dashes and middots are house style, not emoji.
d="$(case_dir emoji-punctuation)"; good_banner "$d"
cat >"$d/README.md" <<'MD'
<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT" /></a>
</p>

# fixture

A toolkit — portable, fast · shipped once.

## Quick Start
MD
judge "em dash and middot are not emoji" 0 "$(fact "$d" '.branding.header_emoji.count')"

# ===========================================================================
section "4. banner quality bar"
# ===========================================================================

plain_readme() {
  cat >"$1/README.md" <<'MD'
<p align="center">
  <img src="assets/banner.svg" alt="fixture" width="600" />
</p>

# fixture

## Quick Start
MD
}

d="$(case_dir banner-text)"; text_banner "$d"; plain_readme "$d"
judge "a text-only banner fails the quality bar" false "$(fact "$d" '.branding.banner.pass')"
judge "  ... and says the shape count is the reason" yes \
  "$(has "$(fact "$d" '.branding.banner.reasons | join("|")')" "non-text shapes")"

d="$(case_dir banner-good)"; good_banner "$d"; plain_readme "$d"
judge "positive control: a designed banner passes" true "$(fact "$d" '.branding.banner.pass')"
judge "  ... with its shapes counted" 21 "$(fact "$d" '.branding.banner.shapes')"

# Emoji as clip-art is the tamirs-marketplace failure: it renders as tofu.
d="$(case_dir banner-emoji)"; good_banner "$d"; plain_readme "$d"
python3 - "$d" <<'PY'
import sys
p = sys.argv[1] + "/assets/banner.svg"
s = open(p, encoding="utf-8").read()
s = s.replace("</svg>", '  <text x="900" y="120" font-size="20">\N{HIGH VOLTAGE SIGN}</text>\n</svg>')
open(p, "w", encoding="utf-8").write(s)
PY
judge "emoji glyph art in an SVG banner fails" false "$(fact "$d" '.branding.banner.pass')"
judge "  ... naming emoji as the reason" yes \
  "$(has "$(fact "$d" '.branding.banner.reasons | join("|")')" "emoji glyphs")"

# A raster too small to be anything but flat text.
d="$(case_dir banner-tiny-raster)"
python3 - "$d" <<'PY'
import struct, sys, zlib, os
# A valid 1200x400 PNG whose payload is a single flat colour: passes the width
# and aspect criteria, fails the file-size floor. That is the intent — a wordmark
# render compresses to nothing.
w, h = 1200, 400
raw = b"".join(b"\x00" + b"\x11\x11\x11" * w for _ in range(h))
def chunk(tag, data):
    c = tag + data
    return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(raw, 9))
       + chunk(b"IEND", b""))
os.makedirs(sys.argv[1] + "/assets", exist_ok=True)
open(sys.argv[1] + "/assets/banner.png", "wb").write(png)
PY
cat >"$d/README.md" <<'MD'
<p align="center">
  <img src="assets/banner.png" alt="fixture" width="600" />
</p>

# fixture

## Quick Start
MD
judge "a raster banner is measured by size and dimensions" raster \
  "$(fact "$d" '.branding.banner.kind')"
judge "  ... its width is read from the PNG header" 1200 "$(fact "$d" '.branding.banner.width')"
judge "  ... and a near-empty render fails the floor" false "$(fact "$d" '.branding.banner.pass')"

# No banner at all is S1-05's job, not this one.
d="$(case_dir banner-absent)"
cat >"$d/README.md" <<'MD'
# fixture

## Quick Start
MD
judge "a repo with no banner skips the quality bar" false "$(fact "$d" '.branding.banner.checked')"

# ===========================================================================
section "5. the gaps reach the scorer (S1-11..S1-14)"
# ===========================================================================

# fires <id> <repo-root> -> yes|no, through the real inventory + scorer path.
fires() {
  local ids
  ids="$(CONTRACT_OFFLINE=1 bash "$INVENTORY" "$2" | bash "$SCORE" app-gold | jq -r '.gaps[].id')"
  case "$ids" in *"$1"*) echo yes ;; *) echo no ;; esac
}

judge "S1-11 fires on the multi-line anchor case" yes "$(fires S1-11 "$TMP/anchor-bad")"
judge "  positive control: not on the corrected one" no "$(fires S1-11 "$TMP/anchor-good")"
judge "S1-12 fires on the emoji header" yes "$(fires S1-12 "$TMP/emoji-header")"
judge "  positive control: not on emoji in body prose" no "$(fires S1-12 "$TMP/emoji-body")"
judge "S1-14 fires on the text-only banner" yes "$(fires S1-14 "$TMP/banner-text")"
judge "  positive control: not on the designed banner" no "$(fires S1-14 "$TMP/banner-good")"

# S1-13 is gated on multi_target: a single-platform repo is never asked to keep
# AI-target badges in sync, because it has none.
d="$(case_dir scored-stale)"; good_banner "$d"; targets_json "$d"
badge_readme "$d" 2.0.0 0.45.0
cp "$REPO_ROOT/AGENTS.md" "$d/AGENTS.md"
cp "$REPO_ROOT/CLAUDE.md" "$d/CLAUDE.md"
judge "S1-13 fires on a multi-target repo with stale badges" yes "$(fires S1-13 "$d")"

d2="$(case_dir scored-fresh)"; good_banner "$d2"; targets_json "$d2"
badge_readme "$d2" 2.1.233 3.16.17
cp "$REPO_ROOT/AGENTS.md" "$d2/AGENTS.md"
cp "$REPO_ROOT/CLAUDE.md" "$d2/CLAUDE.md"
judge "  positive control: not when the badges match" no "$(fires S1-13 "$d2")"

# An inventory that predates these facts must stay silent rather than invent a
# defect it never measured. This is the shape tests/test-shape.sh builds.
legacy_inv='{"readme":{"exists":true,"has_badges":true,"has_prerequisites":true,
  "has_quick_start":true,"has_license_line":true,"has_banner":true,"has_author_badge":true,
  "has_version_badge":true,"has_ai_targets":true,"has_multi_install":true},
  "makefile":{"install":true,"update":true,"uninstall":true},
  "versioning":{"root_changelog":true,"versioning_doc":true,"changelog_unreleased":true,
    "agents_references_versioning":true,"manifest_versions_match":true,"manifest_count":0,
    "manifest_version_tag_match":true,"release_tags_exist":false},
  "ai_platforms":{"count":1},
  "docs":{"readme":true,"changelog":true,"contributing":true,"user_dir":true,"engineering_dir":true},
  "github":{"ci_workflow":true,"secret_scan_job":true,"pr_template":true,"dependabot":true},
  "root_files":{"license":true,"codeowners":true,"gitignore":true,"claude_md":true,"agents_md":true},
  "branch_governance":{"readable":false,"protection_enabled":false,"requires_ci_check":false,
    "allow_auto_merge":false,"delete_branch_on_merge":false,"rulesets":{},
    "actions":{"checked":false,"violations":0}},
  "hygiene":{"misplaced_top_level_docs":0,"ticket_named_outside_engineering":0,"empty_dirs":0,
    "self_hosted_ci":false,"root_shell_scripts":0}}'
legacy_ids="$(echo "$legacy_inv" | bash "$SCORE" app-gold | jq -r '[.gaps[].id] | join(",")')"
judge "an inventory with no branding facts scores no branding gap" "no,no,no,no" \
  "$(printf '%s,%s,%s,%s' \
      "$(has "$legacy_ids" S1-11)" "$(has "$legacy_ids" S1-12)" \
      "$(has "$legacy_ids" S1-13)" "$(has "$legacy_ids" S1-14)")"

# ===========================================================================
section "6. the artifacts this repo ships are themselves clean"
# ===========================================================================

for target in "$REPO_ROOT" \
              "$CONTRACT/fixtures/scaffold-gold" \
              "$CONTRACT/fixtures/scaffold-plugin-gold" \
              "$CONTRACT/fixtures/scaffold-claude-plugin-gold"; do
  name="$(basename "$target")"
  judge "$name README passes the branding check" 0 \
    "$(bash "$CHECK" "$target" >/dev/null 2>&1; echo $?)"
done

# The reference doc must not carry a copyable version literal — that is exactly
# how the stale badges spread in the first place.
badges_ref="$CONTRACT/references/readme-badges.md"
judge "readme-badges.md ships no literal harness version" 0 \
  "$(grep -cE 'badge/(Claude%20Code|Cursor|Codex|Gemini%20CLI|OpenCode)-[0-9]' "$badges_ref")"
judge "  ... and names platform-targets.json as the source" yes \
  "$(has "$(cat "$badges_ref")" "validated_against")"
judge "the banner art direction reference exists" yes \
  "$(exists "$CONTRACT/references/readme-banner.md")"

harness_summary
