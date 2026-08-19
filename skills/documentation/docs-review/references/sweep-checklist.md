# Sweep Checklist (fast pass)

Use this when running `docs-review` against a single file or small set. The
SKILL.md body has the full prose; this file is the per-file checklist.

Paths below use `<skill-dir>` for this skill's install directory — `$CLAUDE_SKILL_DIR` on
Claude Code, the directory this file was loaded from elsewhere.

## Inventory

```bash
{ printf '%s\n' README.md; find docs -name '*.md' -type f; } | sort -u
```

## Per-file (run all 5 axes)

```bash
F="$1"
bash <skill-dir>/scripts/file-freshness.sh "$F" | jq .
bash <skill-dir>/scripts/check-template.sh   "$F" | jq .
bash <skill-dir>/scripts/validate-links.sh   "$F" | jq .
```

Plan-file detection runs once for the whole repo, not per file:

```bash
bash <skill-dir>/scripts/detect-plan-files.sh
```

## Repo-wide axes (run once, not per file)

Axes 8–10 are repo-wide and are **not** part of the per-file loop. Run them once per sweep:

| Axis | Check | Pass condition |
|---|---|---|
| 8 — cross-platform docs | Platform-facing files agree with the capability registry; no duplicated canonical policy | 0 inconsistencies |
| 9 — install commands | `make -n <target>` / `bash -n <script>` / manifest name match, for every documented install command | 0 failures |
| 10 — generated tables | Skill counts, domain tables, per-skill rows and platform tables match the filesystem and the registry | 0 drifted |

Never execute an install command to verify it, and never hardcode a platform list — resolve
it from `core/capabilities/platforms.json`.

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
| doc claims a capability the registry marks `unsupported` / `unknown` | Remove the claim; never soften it to "may support" |
| documented platform set ≠ registry platform set | Update the doc; report the diff both ways |
| `make -n <target>` fails for a documented command | Fix the doc or the Makefile — do not leave a command that cannot run |
| skill count in a doc ≠ `find skills -name SKILL.md` count | Update every occurrence, not the first one found |
| a generated table was hand-edited | Fix the generator and regenerate; revert the hand edit |
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
