# Sweep Checklist (fast pass)

Use this when running `review-docs` against a single file or small set. The
SKILL.md body has the full prose; this file is the per-file checklist.

## Inventory

```bash
{ printf '%s\n' README.md; find docs -name '*.md' -type f; } | sort -u
```

## Per-file (run all 5 axes)

```bash
F="$1"
bash .claude/skills/review-docs/scripts/file-freshness.sh "$F" | jq .
bash .claude/skills/review-docs/scripts/check-template.sh   "$F" | jq .
bash .claude/skills/review-docs/scripts/validate-links.sh   "$F" | jq .
```

Plan-file detection runs once for the whole repo, not per file:

```bash
bash .claude/skills/review-docs/scripts/detect-plan-files.sh
```

## Decision matrix

| Finding | Default action |
|---|---|
| `verdict=stale` and the doc references files that moved | Update the link, leave prose alone if still accurate |
| `verdict=stale` and a referenced script was removed | Remove the reference, add a note pointing at the replacement (if any) |
| `verdict=fresh` | Skip Axis 2 fixes for this file |
| `audience=top-level` and file is not `docs/README.md` | Move to `docs/user/` or `docs/engineering/`; relink callers |
| `footer_present=false` (only for `docs/user/**`) | Append the canonical footer block from `README.md` |
| `mermaid_violations > 0` | Strip the offending classDef / class / fill / style lines |
| `has_purpose_sentence=false` | Add a one-line purpose sentence below the title |
| `link_text_uses_path_count > 0` | Replace path-as-link-text with human-readable labels |
| `broken_links` non-empty | Fix the path or remove the link; never invent a target |
| `broken_anchors` non-empty | Fix anchor or rename target heading |
| `mermaid_parse_errors` non-empty | Add the diagram-type keyword (e.g. `flowchart TD`) |

## Plan-file confirmation

For each entry from `detect-plan-files.sh`:
1. Read the file briefly.
2. Cross-check against `references/known-canonical-plans.md` — if listed, KEEP.
3. Otherwise default to: `git rm --cached <file>`, optionally add to `.gitignore`.

## Final validators

```bash
python3 tooling/check-doc-orphans.py
bash tests/unit/skills/footer-center-aligned.sh
bash tests/unit/skills/mcp-auth-doc-consistency.sh   # only if you touched plugin/skills/
```
