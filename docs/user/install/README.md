# Installing tamirs-superpowers

`tamirs-superpowers` is a **standalone plugin**. It installs on its own, from its own repository, on any of the four supported targets — you do not need the [`tamirs-marketplace`](https://github.com/Tamircohen28/tamirs-marketplace) catalog, though the catalog is the easiest path on Claude Code and Cursor.

## The four supported targets

| Target | Install guide | Validated against | Min supported |
|--------|---------------|-------------------|---------------|
| Claude Code | [claude-code.md](claude-code.md) | 2.1.231 | 2.0.0 |
| Cursor | [cursor.md](cursor.md) | 3.14.7 | 3.14.7 |
| Codex | [codex.md](codex.md) | 0.146.0 | 0.40.0 |
| OpenCode | [opencode.md](opencode.md) | 1.18.11 | 1.16.2 |

Versions verified 2026-08-03. The machine-readable source of truth is [`platform-targets.json`](../../engineering/build-and-release/platform-targets.json); the human mirror with per-floor rationale is [`platform-targets.md`](../../engineering/build-and-release/platform-targets.md).

## What ships, and where it lands

| Component | Claude Code | Cursor | Codex | OpenCode |
|-----------|:---:|:---:|:---:|:---:|
| 27 skills | ✅ | ✅ | ✅ | ✅ |
| 6 specialist agents | ✅ | ✅ | ✅ | ✅ via `.opencode/agent/` |
| Worktree hooks | ✅ | ✅ | ✅ | ❌ — see [opencode.md](opencode.md#what-does-not-port) |
| Statusline | ✅ | ❌ | ❌ | ❌ |
| MCP server stubs | ✅ | ✅ | ✅ | ✅ manual |
| Marketplace install | ✅ | ✅ | ✅ | ❌ path install |

Gaps are documented, not hidden. Each install guide states what that target does **not** get.

## Which install method?

- **Marketplace** (Claude Code, Cursor, Codex) — updates arrive automatically. Prefer this.
- **Clone + path install** (all four) — no marketplace account or team setup needed. Update with `git pull`. This is the only route on OpenCode.

## After installing

Every target should be able to run:

```
/tamirs-superpowers:find-skill
```

If that resolves, the skills loaded. Target-specific verification commands are in each guide.
