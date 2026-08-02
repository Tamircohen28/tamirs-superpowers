# Platform target versions

Machine-readable source: [`platform-targets.json`](platform-targets.json).

This repo ships as a **multi-platform plugin** (Claude Code, Cursor, Codex). Row 3 README badges show **platform tool versions** validated in this release — not the plugin semver (Row 1).

| Platform | Min supported | Validated against | Latest known |
|----------|---------------|-------------------|--------------|
| Claude Code | 2.0.0 | 2.1.220 | 2.1.220 |
| Cursor | 0.45.0 | 0.45.0 | 0.45.0 |
| Codex | 0.40.0 | 0.40.0 | 0.40.0 |

## Maintenance

When changing `skills/repo/**`, `platform-specs.md`, or platform-sync sub-skills:

**Agents** (not users) run these Make targets:

| Target | When |
|--------|------|
| `make platform-targets-sync` | Refresh `latest_known` after skill/platform-spec changes |
| `make platform-targets-assert` | Polish exit — configs caught up to latest_known |
| `make agent-polish-gate` | Full pre-PR gate (sync + assert + agent:check) |
| `make platform-targets-cochange` | CI on PRs touching `skills/repo/**` |

After `make platform-targets-sync`, the agent updates `validated_against`, README Row 3 badges, this table, and `CHANGELOG.md`.

Users run `/repo-standards polish` or `/multi-agent-repo dev` — not these Make targets directly.

See also [`platform-equivalence.md`](../../agent-guidelines/platform-equivalence.md) for capability mappings.
