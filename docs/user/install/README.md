# Installation

Six supported platforms. Pick yours — every guide covers **install · verify · update ·
uninstall**, plus an honest capability table.

| Platform | Registry id | Install mechanism | Guide |
|---|---|---|---|
| Claude Code | `claude_code` | plugin marketplace | [claude-code.md](claude-code.md) |
| Claude Desktop | `claude_desktop` | same plugin as Claude Code | [claude-desktop.md](claude-desktop.md) |
| Codex CLI | `codex` | plugin marketplace | [codex.md](codex.md) |
| Cursor | `cursor` | team marketplace, import from repo | [cursor.md](cursor.md) |
| Gemini CLI | `gemini_cli` | git-URL extension **+ a separate skills install** | [gemini.md](gemini.md) |
| OpenCode | `opencode` | path (`skills.paths` or symlink) | [opencode.md](opencode.md) |

## Prerequisites

`git` 2.30+, `jq`, and bash. `gh` is optional and only affects PR/issue workflows. No Node,
no Python, no build step — the toolkit is Markdown, JSON, and bash.

Gemini is the one target where installing the extension is not the whole install: skills
live in a generated flat mirror at `.gemini/skills/` and are installed with a second command.
Gemini discovers skills exactly one level below a root, so the canonical two-level tree finds
zero — silently. The [Gemini guide](gemini.md) explains it before you hit it.

## Verify any install

```bash
bash scripts/doctor.sh .
```

It reports the detected platform, canonical version and any drift, which tools are present,
which optional features are consequently usable, and a remedy line per gap. It exits
non-zero only when the install is genuinely broken.

## Users vs contributors

These guides are for **using** the toolkit. Working *on* it is a different setup —
see [docs/CONTRIBUTING.md](../../CONTRIBUTING.md). In particular, `make install` bootstraps a
Claude machine profile for maintainers; it is not a way to install the plugin.

## Before you file a bug

Capabilities differ per platform, sometimes surprisingly — hooks that do not run under
Cursor, no parallel subagents outside Claude Code, no session transcripts anywhere but
Claude Code. Check [platform differences](../platform-differences.md) first; the behavior you
are seeing may be the documented, honest degradation.
