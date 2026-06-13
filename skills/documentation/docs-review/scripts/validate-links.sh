#!/usr/bin/env bash
# validate-links.sh — relative-link / anchor / Mermaid / link-text validity.
#
# Usage:
#   validate-links.sh <FILE> [--skip-external]
#   validate-links.sh -h | --help
#
# Output (to stdout): JSON with broken_links[], broken_anchors[],
#   mermaid_parse_errors[], link_text_warnings[].
#
# Each entry includes line_no and context. broken_anchors checks heading anchors
# in the target file using a slug-style normalization (lowercase, non-alnum
# becomes -, leading/trailing - stripped).
set -uo pipefail

usage() { sed -n '2,11p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi
if [[ -z "${1:-}" ]]; then echo "ERROR: missing FILE" >&2; usage 1; fi

FILE="$1"; shift || true
SKIP_EXT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-external) SKIP_EXT=1; shift ;;
    *) shift ;;
  esac
done

[[ -f "$FILE" ]] || { echo "ERROR: $FILE not found" >&2; exit 1; }
DOC_DIR=$(dirname "$FILE")

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//'
}

broken_links_json="[]"
broken_anchors_json="[]"
link_text_warnings_json="[]"
mermaid_errors_json="[]"

LN=0
in_mermaid=0
mermaid_buf=""
mermaid_start_ln=0

while IFS= read -r line; do
  LN=$((LN + 1))

  # Mermaid block tracking.
  if [[ "$line" =~ ^\`\`\`mermaid ]]; then
    in_mermaid=1; mermaid_buf=""; mermaid_start_ln=$LN; continue
  fi
  if (( in_mermaid )) && [[ "$line" =~ ^\`\`\`$ ]]; then
    # Cheap parse check: must contain at least one of graph|flowchart|sequenceDiagram|classDiagram|stateDiagram|erDiagram|gantt
    if ! printf '%s\n' "$mermaid_buf" | grep -qE '^[[:space:]]*(graph|flowchart|sequenceDiagram|classDiagram|stateDiagram|erDiagram|gantt|pie|journey)'; then
      mermaid_errors_json=$(jq -c --argjson cur "$mermaid_errors_json" \
        --arg ln "$mermaid_start_ln" \
        --arg reason "no diagram type keyword (graph/flowchart/etc.)" \
        '$cur + [{line_no: ($ln|tonumber), reason: $reason}]' <<<'null')
    fi
    in_mermaid=0; continue
  fi
  if (( in_mermaid )); then
    mermaid_buf+=$'\n'"$line"
    continue
  fi

  # Extract markdown links: [text](target)
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    # Strip [ and split on ](
    text=${match#[}
    text=${text%%]\(*}
    target=${match#*](}
    target=${target%)}

    # Skip external + mailto + bare anchors
    case "$target" in
      http://*|https://*)
        (( SKIP_EXT == 1 )) && continue
        # External not validated here (no network)
        continue ;;
      mailto:*) continue ;;
      \#*)
        # In-file anchor — we do not pre-build a heading set here; mark for later
        continue ;;
    esac

    # Split anchor.
    file_part=${target%%#*}
    anchor=""
    if [[ "$target" == *"#"* ]]; then
      anchor=${target#*#}
    fi

    # Resolve file relative to DOC_DIR.
    if [[ -n "$file_part" ]]; then
      resolved=$(cd "$DOC_DIR" 2>/dev/null && cd "$(dirname "$file_part")" 2>/dev/null && \
        printf '%s/%s\n' "$(pwd)" "$(basename "$file_part")" 2>/dev/null || true)
      if [[ -z "$resolved" || ! -f "$resolved" ]]; then
        broken_links_json=$(jq -c --argjson cur "$broken_links_json" \
          --arg ln "$LN" --arg target "$target" --arg text "$text" \
          '$cur + [{line_no: ($ln|tonumber), target: $target, text: $text}]' <<<'null')
        continue
      fi

      # Anchor check.
      if [[ -n "$anchor" ]]; then
        slug_target=$(slugify "$anchor")
        # Build set of heading slugs from resolved file.
        if ! grep -E '^#+[[:space:]]' "$resolved" \
              | sed -E 's/^#+[[:space:]]+//' \
              | while read -r h; do slugify "$h"; done \
              | grep -qx "$slug_target"; then
          broken_anchors_json=$(jq -c --argjson cur "$broken_anchors_json" \
            --arg ln "$LN" --arg target "$target" --arg slug "$slug_target" \
            '$cur + [{line_no: ($ln|tonumber), target: $target, slug: $slug}]' <<<'null')
        fi
      fi
    fi

    # Link-text uses raw path warning.
    if [[ "$text" == *"/"* ]] && [[ "$text" == *".md"* ]]; then
      link_text_warnings_json=$(jq -c --argjson cur "$link_text_warnings_json" \
        --arg ln "$LN" --arg text "$text" \
        '$cur + [{line_no: ($ln|tonumber), text: $text, reason: "link text is a raw path; use a human-readable label"}]' <<<'null')
    fi
  done < <(grep -oE '\[[^]]+\]\([^)]+\)' <<<"$line" || true)

done < "$FILE"

jq -nc \
  --arg file "$FILE" \
  --argjson broken_links "$broken_links_json" \
  --argjson broken_anchors "$broken_anchors_json" \
  --argjson mermaid_parse_errors "$mermaid_errors_json" \
  --argjson link_text_warnings "$link_text_warnings_json" \
  '{
    file: $file,
    broken_links: $broken_links,
    broken_anchors: $broken_anchors,
    mermaid_parse_errors: $mermaid_parse_errors,
    link_text_warnings: $link_text_warnings,
    summary: {
      broken_links_count: ($broken_links | length),
      broken_anchors_count: ($broken_anchors | length),
      mermaid_parse_errors_count: ($mermaid_parse_errors | length),
      link_text_warnings_count: ($link_text_warnings | length)
    }
  }'
