#!/usr/bin/env bash
# check-readme-branding.sh — the four README branding defects, as observable facts.
#
# Usage:
#   check-readme-branding.sh <repo-root>            human report; exit 1 on any defect
#   check-readme-branding.sh <repo-root> --json     facts only; always exit 0
#
# WHY THIS EXISTS
#   Four defects shipped in real repos because nothing measured them. Each one is
#   mechanical, each one was invisible to every existing checker, and each one is
#   scored here as an OBSERVABLE fact rather than a matter of taste:
#
#   1. ANCHOR FORM. `<a href="..">\n  <img/>\n</a>` puts a newline and an indent
#      INSIDE the anchor. GitHub renders that whitespace as link text, so a row of
#      badges grows blue underlined gaps between them. The single-line form
#      `<a href=".."><img/></a>` has no text node and cannot underline. This is a
#      rendering fact, not a formatting preference — see readme-badges.md.
#
#   2. BADGE VERSIONS. AI-target badges carry a version number. Repos copied the
#      sample values out of the reference doc instead of deriving them from
#      docs/engineering/build-and-release/platform-targets.json, so READMEs
#      advertise harness versions that were never validated. The badge is compared
#      against `validated_against` here, the same source scripts/check-platform-
#      targets.sh uses; that script is the enforcing gate for repos that ship it,
#      and this is the portable read for repos that do not.
#
#   3. HEADER EMOJI. Emoji above the first `##` heading — in the H1, the tagline
#      or a badge row — reads as unprofessional in the one part of the README that
#      is always screenshotted. Body prose is unaffected.
#
#   4. BANNER QUALITY. A 600x200 rectangle with the repo name centred in it is a
#      wordmark, not a banner, and it is what the old art direction literally asked
#      for. A designed banner is detectable: it has many non-text shapes, it has
#      depth (gradients/filters/opacity), text does not dominate it, and it does
#      not use emoji glyphs as clip-art (they render as tofu off-platform). The
#      thresholds live in standards-contract.json under `readme.banner`.
#
# The emoji and SVG facts need python3. Without it every fact reports
# `"checked": false` and the scorer emits no gap — an unread control is reported
# as unread, never as a pass and never as a failure.
set -euo pipefail

ROOT="${1:-.}"
JSON=false
for arg in "$@"; do
  case "$arg" in
    --json) JSON=true ;;
    -h|--help) sed -n '2,8p' "$0" | sed -E 's/^# ?//'; exit 0 ;;
  esac
done

if ! ROOT="$(cd "$ROOT" 2>/dev/null && pwd)"; then
  echo '{"branding":{"checked":false,"reason":"not a directory"}}'
  exit 0
fi

CONTRACT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_FILE="${CONTRACT_FILE:-$CONTRACT_DIR/standards-contract.json}"
PROFILE="${CONTRACT_PROFILE:-app-gold}"

# Banner thresholds come from the contract so a repo can tune them in one place.
# Defaults match app-gold and keep a vendored/older contract working.
bopt() {
  local key="$1" fallback="$2" v=""
  if [[ -f "$CONTRACT_FILE" ]] && command -v jq >/dev/null 2>&1; then
    v="$(jq -r --arg p "$PROFILE" --arg k "$key" \
      '(.profiles[$p].readme.banner[$k]) // empty' "$CONTRACT_FILE" 2>/dev/null || true)"
  fi
  [[ -n "$v" ]] && echo "$v" || echo "$fallback"
}

MIN_SVG_SHAPES="$(bopt min_svg_shapes 16)"
MAX_SVG_TEXT="$(bopt max_svg_text_elements 3)"
RASTER_MIN_BYTES="$(bopt raster_min_bytes 20000)"
RASTER_MIN_WIDTH="$(bopt raster_min_width 800)"

# The analysis runs as a function rather than inline in a command substitution:
# bash 3.2 (the macOS system shell) mis-parses a here-document that sits inside
# $( ... ) when the document contains unbalanced parens or quotes, which any
# non-trivial program does.
analyze() {
  python3 - "$ROOT" "$MIN_SVG_SHAPES" "$MAX_SVG_TEXT" "$RASTER_MIN_BYTES" "$RASTER_MIN_WIDTH" <<'PY'
import json, os, re, struct, sys

root = sys.argv[1]
MIN_SVG_SHAPES = int(sys.argv[2])
MAX_SVG_TEXT = int(sys.argv[3])
RASTER_MIN_BYTES = int(sys.argv[4])
RASTER_MIN_WIDTH = int(sys.argv[5])

readme_path = os.path.join(root, "README.md")

# Emoji, defined by codepoint range. Deliberately NOT "any non-ASCII": the house
# style uses em dashes and middots, and banning those would be a different rule.
EMOJI_RANGES = (
    (0x1F000, 0x1FAFF),   # pictographs, transport, symbols, extended-A
    (0x1F100, 0x1F1FF),   # enclosed alphanumerics + regional indicators (flags)
    (0x2600, 0x27BF),     # misc symbols + dingbats
    (0x2B00, 0x2BFF),     # misc symbols and arrows
    (0xFE0F, 0xFE0F),     # variation selector-16 (emoji presentation)
)


def emoji_chars(text):
    out = []
    for ch in text:
        cp = ord(ch)
        if any(lo <= cp <= hi for lo, hi in EMOJI_RANGES):
            out.append(ch)
    return out


result = {
    "checked": True,
    "readme": os.path.isfile(readme_path),
    "anchor_form": {"checked": False, "multiline_img_anchors": 0, "lines": []},
    "header_emoji": {"checked": False, "count": 0, "samples": [], "header_lines": 0},
    "badge_versions": {"checked": False, "mismatches": [], "missing": [], "matched": 0},
    "banner": {"checked": False, "kind": "none", "path": None, "pass": False, "reasons": []},
}

readme = ""
if result["readme"]:
    with open(readme_path, encoding="utf-8", errors="replace") as fh:
        readme = fh.read()

# --- 1. anchor form ---------------------------------------------------------
# The defect is a TEXT NODE inside the anchor element, on either side of the img:
#   <a ...>\n  <img/>   or   <img/>\n</a>
# Both are matched against the joined source so a wrapped-but-closed anchor on a
# single line never trips, and prose links that wrap (no <img> inside) never do
# either — this is a badge-rendering check, not a line-length check.
if result["readme"]:
    open_gap = re.compile(r"<a\b[^>]*>[ \t]*\r?\n[ \t]*<img\b", re.I)
    close_gap = re.compile(r"<img\b[^>]*/?>[ \t]*\r?\n[ \t]*</a>", re.I)
    hits = []
    for rx in (open_gap, close_gap):
        for m in rx.finditer(readme):
            hits.append(readme.count("\n", 0, m.start()) + 1)
    result["anchor_form"] = {
        "checked": True,
        "multiline_img_anchors": len(hits),
        "lines": sorted(set(hits))[:20],
    }

# --- 2. header emoji --------------------------------------------------------
# Header region = everything above the first `##` heading: banner, badge rows,
# H1, tagline. A README with no `##` at all ends its header at the H1 line; one
# with neither uses its first 10 lines. Body prose below the first `##` is free
# to use emoji and is never inspected.
if result["readme"]:
    lines = readme.splitlines()
    end = None
    for i, line in enumerate(lines):
        if re.match(r"^##\s", line):
            end = i
            break
    if end is None:
        for i, line in enumerate(lines):
            if re.match(r"^#\s", line):
                end = i + 1
                break
    if end is None:
        end = min(10, len(lines))
    header = lines[:end]
    found = emoji_chars("\n".join(header))
    result["header_emoji"] = {
        "checked": True,
        "count": len(found),
        "samples": sorted(set(found))[:10],
        "header_lines": end,
    }

# --- 3. badge versions vs platform-targets.json -----------------------------
# Same target -> badge-prefix table as scripts/check-platform-targets.sh. A repo
# with no platform-targets.json has nothing to disagree with and is skipped.
BADGE_PREFIX = {
    "claude_code": "Claude%20Code",
    "cursor": "Cursor",
    "codex": "Codex",
    "gemini_cli": "Gemini%20CLI",
    "opencode": "OpenCode",
}
targets_path = os.path.join(
    root, "docs", "engineering", "build-and-release", "platform-targets.json"
)
if result["readme"] and os.path.isfile(targets_path):
    try:
        targets = json.load(open(targets_path, encoding="utf-8"))
    except Exception as exc:  # a malformed file is a different check's failure
        result["badge_versions"] = {
            "checked": False, "mismatches": [], "missing": [], "matched": 0,
            "reason": "unreadable platform-targets.json: %s" % exc,
        }
        targets = None
    if targets is not None:
        keys = targets.get("supported_targets") or ["claude_code", "cursor", "codex"]
        mismatches, missing, matched = [], [], 0
        for key in keys:
            prefix = BADGE_PREFIX.get(key)
            if not prefix:
                continue
            validated = (targets.get("targets", {}).get(key) or {}).get("validated_against")
            # "unknown" is an honest not-yet-validated state; it carries no badge
            # by design, so there is nothing to compare.
            if not validated or validated == "unknown":
                continue
            found = re.findall(
                r"badge/%s-([^-\s/\"'\)]+)-" % re.escape(prefix), readme
            )
            if not found:
                missing.append(key)
                continue
            for ver in set(found):
                if ver != validated:
                    mismatches.append(
                        {"target": key, "readme": ver, "platform_targets": validated}
                    )
                else:
                    matched += 1
        result["badge_versions"] = {
            "checked": True,
            "mismatches": mismatches,
            "missing": missing,
            "matched": matched,
        }

# --- 4. banner quality ------------------------------------------------------
def png_size(data):
    if data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR":
        return struct.unpack(">II", data[16:24])
    return None


def jpeg_size(data):
    i = 2
    while i + 9 < len(data):
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            i += 2
            continue
        seglen = struct.unpack(">H", data[i + 2:i + 4])[0]
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            return (w, h)
        i += 2 + seglen
    return None


def webp_size(data):
    if data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        return None
    if data[12:16] == b"VP8X":
        w = int.from_bytes(data[24:27], "little") + 1
        h = int.from_bytes(data[27:30], "little") + 1
        return (w, h)
    return None


banner_rel = None
m = re.search(r'<img[^>]+src="([^"]*banner[^"]*)"', readme, re.I)
if m:
    banner_rel = m.group(1)
if banner_rel is None or not os.path.isfile(os.path.join(root, banner_rel)):
    for ext in ("png", "jpg", "jpeg", "webp", "svg"):
        cand = os.path.join("assets", "banner." + ext)
        if os.path.isfile(os.path.join(root, cand)):
            banner_rel = cand
            break
    else:
        banner_rel = None

if banner_rel and os.path.isfile(os.path.join(root, banner_rel)):
    path = os.path.join(root, banner_rel)
    ext = os.path.splitext(banner_rel)[1].lower().lstrip(".")
    reasons = []
    if ext == "svg":
        src = open(path, encoding="utf-8", errors="replace").read()
        shapes = len(re.findall(
            r"<(?:path|rect|circle|ellipse|polygon|polyline|line)\b", src, re.I))
        texts = len(re.findall(r"<text\b", src, re.I))
        depth = bool(re.search(
            r"<(?:linearGradient|radialGradient|filter|mask|clipPath)\b"
            r"|\bopacity\s*=|\bfill-opacity\s*=|\bstop-color\s*=", src, re.I))
        described = bool(re.search(r"<(?:title|desc)\b", src, re.I))
        glyph_art = emoji_chars(src)
        if shapes < MIN_SVG_SHAPES:
            reasons.append(
                "only %d non-text shapes (need >= %d) — a wordmark on a rectangle, "
                "not a designed banner" % (shapes, MIN_SVG_SHAPES))
        if texts > MAX_SVG_TEXT:
            reasons.append("%d <text> elements (max %d)" % (texts, MAX_SVG_TEXT))
        if texts and shapes < 5 * texts:
            reasons.append(
                "text dominates the composition (%d shapes vs %d text elements; "
                "need >= 5 shapes per text element)" % (shapes, texts))
        if not depth:
            reasons.append(
                "flat fills only — no gradient, filter, mask or opacity anywhere")
        if not described:
            reasons.append(
                "no <title>/<desc> naming the visual motif and how it relates to "
                "the project")
        if glyph_art:
            reasons.append(
                "emoji glyphs used as artwork (%s) — they render as tofu wherever "
                "the font is missing" % "".join(sorted(set(glyph_art))[:5]))
        result["banner"] = {
            "checked": True, "kind": "vector", "path": banner_rel,
            "pass": not reasons, "reasons": reasons,
            "shapes": shapes, "text_elements": texts, "has_depth": depth,
            "described": described,
        }
    elif ext in ("png", "jpg", "jpeg", "webp"):
        data = open(path, "rb").read()
        size = len(data)
        dims = png_size(data) if ext == "png" else (
            jpeg_size(data) if ext in ("jpg", "jpeg") else webp_size(data))
        if size < RASTER_MIN_BYTES:
            reasons.append(
                "%d bytes (need >= %d) — too small to be anything but flat text"
                % (size, RASTER_MIN_BYTES))
        if dims:
            w, h = dims
            if w < RASTER_MIN_WIDTH:
                reasons.append("%dpx wide (need >= %dpx)" % (w, RASTER_MIN_WIDTH))
            if h and not (1.5 <= w / h <= 5.0):
                reasons.append(
                    "aspect ratio %.2f:1 is not a hero banner (want 1.5:1 to 5:1)"
                    % (w / h))
        result["banner"] = {
            "checked": True, "kind": "raster", "path": banner_rel,
            "pass": not reasons, "reasons": reasons,
            "bytes": size, "width": dims[0] if dims else None,
            "height": dims[1] if dims else None,
        }
    else:
        result["banner"] = {
            "checked": False, "kind": "unknown", "path": banner_rel,
            "pass": False,
            "reasons": ["unrecognised banner format '%s' — use png, jpg, webp or svg" % ext],
        }

print(json.dumps({"branding": result}))
PY
}

if command -v python3 >/dev/null 2>&1; then
  RESULT="$(analyze)"
else
  RESULT='{"branding":{"checked":false,"reason":"python3 unavailable"}}'
fi

if [[ "$JSON" == true ]]; then
  echo "$RESULT"
  exit 0
fi

# --- human report -----------------------------------------------------------
FAILED=0
say() { printf '%s\n' "$*"; }
get() { echo "$RESULT" | jq -r "$1"; }

if [[ "$(get '.branding.checked')" != true ]]; then
  say "README branding check skipped: $(get '.branding.reason // "unknown reason"')"
  exit 0
fi
if [[ "$(get '.branding.readme')" != true ]]; then
  say "No README.md at $ROOT — nothing to check"
  exit 0
fi

n="$(get '.branding.anchor_form.multiline_img_anchors')"
if [[ "$n" != 0 ]]; then
  say "FAIL badge anchors: $n <a> element(s) wrap an <img> across lines (line(s): $(get '.branding.anchor_form.lines | join(", ")'))"
  say "     The newline and indent are link TEXT — GitHub underlines the gap between badges."
  say "     Put each anchor on one line: <a href=\"...\"><img ... /></a>"
  FAILED=$((FAILED + 1))
else
  say "ok   badge anchors are single-line"
fi

n="$(get '.branding.header_emoji.count')"
if [[ "$n" != 0 ]]; then
  say "FAIL header emoji: $n emoji character(s) above the first '##' heading ($(get '.branding.header_emoji.samples | join(" ")'))"
  say "     The title area and badge rows carry no emoji. Body prose is unaffected."
  FAILED=$((FAILED + 1))
else
  say "ok   no emoji in the README header"
fi

if [[ "$(get '.branding.badge_versions.checked')" == true ]]; then
  n="$(get '.branding.badge_versions.mismatches | length')"
  if [[ "$n" != 0 ]]; then
    say "FAIL badge versions: $n AI-target badge(s) disagree with platform-targets.json"
    get '.branding.badge_versions.mismatches[] | "     \(.target): README says \(.readme), validated_against is \(.platform_targets)"'
    FAILED=$((FAILED + 1))
  else
    say "ok   AI-target badge versions match platform-targets.json ($(get '.branding.badge_versions.matched') checked)"
  fi
else
  say "skip AI-target badge versions — no docs/engineering/build-and-release/platform-targets.json"
fi

if [[ "$(get '.branding.banner.checked')" == true ]]; then
  if [[ "$(get '.branding.banner.pass')" == true ]]; then
    say "ok   banner $(get '.branding.banner.path') meets the quality bar"
  else
    say "FAIL banner $(get '.branding.banner.path') is not a designed graphic:"
    get '.branding.banner.reasons[] | "     - \(.)"'
    say "     See skills/repo/_contract/references/readme-banner.md"
    FAILED=$((FAILED + 1))
  fi
else
  say "skip banner quality — no assets/banner.* found"
fi

if (( FAILED > 0 )); then
  say ""
  say "README branding check failed ($FAILED defect group(s))"
  exit 1
fi
say ""
say "README branding check passed"
