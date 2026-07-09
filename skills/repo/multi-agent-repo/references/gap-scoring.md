# Gap scoring — inventory JSON to rubric IDs

`score-inventory-gaps.sh` handles deterministic checks. The model still walks `audit-rubric.md` for qualitative items (policy duplication, command accuracy, hand-written vs bloat).

## Auto-scored from inventory

| Rubric ID | Condition | Severity |
|-----------|-----------|----------|
| L1-01 | `agents_md.exists == false` | P1 |
| L1-04 | `agents_md.over_codex_limit == true` | P1 |
| L2-01 | `claude_md.exists == false` | P1 |
| L2-02 | `claude_md.imports_agents == false` (when CLAUDE.md exists) | P1 |
| L3-01 | `cursor_rules.count == 0` | P2 |
| L3-02 | `cursor_rules.non_mdc_count > 0` | P1 |
| L3-04 | `cursor_rules.always_apply_count > 2` | P1 |
| L4-02 | `repo_type == app` and no skills dirs | P2 |
| L4-03 | `skills/plugin_skills_dir` with SKILL.md files and no `manifests.claude_plugin` | P1 |
| L5-01 | `docs.agent_guidelines_dir == false` | P2 |
| L6-03 | `enforcement.has_agent_check == false` | P1 |
| L6-04 | CI exists but no agent check | P1 |
| L7-01 | `enforcement.drift_script == false` | P2 |

## Manual follow-up (read files)

After auto-scoring, verify in `audit-rubric.md`:

- L1-06–L1-14 — AGENTS.md content quality (commands, constraints, no tool-specific syntax)
- L2-03–L2-05 — CLAUDE.md length and policy duplication
- L3-03, L3-06–L3-08 — Cursor rules reference AGENTS.md, file sizes
- L4-05–L4-08 — SKILL.md frontmatter, skill purpose vs standards
- L6-01–L6-02, L6-05–L6-08 — linter, tests, secret scan
- L7-03–L7-05 — cross-file policy consistency

Merge auto + manual gaps into the review report. Deduplicate by rubric ID.


## Auto-scored E-layer (feature equivalence)

See `score-equivalence-gaps.sh` — E1-01 through E5-01.

## Auto-scored V-layer (platform targets)

See `score-platform-target-gaps.sh` — V1-01 through V1-05.
