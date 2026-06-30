# Repo contract — shared scaffold / standards source of truth

`skills/repo/_contract/` is **not** a skill. It holds the machine contract, scoring scripts, templates, and gold fixture used by `repo-scaffold`, `repo-standards`, and `multi-agent-repo`.

## Change workflow

1. Edit `standards-contract.json` and/or `templates/`
2. Update `fixtures/scaffold-gold/` to match
3. Run `make test-repo-contract`
4. Grep `repo-scaffold` and `repo-standards` SKILL.md for stale paths
5. Bump `version` in `standards-contract.json`

**Rule:** If a path or check is not in `standards-contract.json`, it does not belong in either skill's prose.

## Commands

```bash
# Offline fixture test (skips GitHub API probes S4-02–S4-06)
CONTRACT_OFFLINE=1 bash scripts/assert-contract.sh fixtures/scaffold-gold app-gold

# Full gap report
bash scripts/score-contract-gaps.sh /path/to/repo app-gold

# Scaffold exit gate (online — includes branch protection when gh available)
bash scripts/assert-contract.sh "$REPO_ROOT" app-gold
```

## Profiles

| Profile | Use |
|---------|-----|
| `app-gold` | Greenfield app repos from `repo-scaffold`; polish target for `repo-standards` (default) |
| `plugin-gold` | Agent-kit distribution repos from `repo-scaffold --type plugin`; auto-detected when `canonical/rules/` exists |

Detect profile: `bash scripts/detect-contract-profile.sh <repo-root>`

Exit gate: P1 = P2 = P3 = 0 on merged standards + multi-agent + plugin (if plugin-gold) deterministic checks.
