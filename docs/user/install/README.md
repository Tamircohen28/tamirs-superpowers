# Installation

**Six supported surfaces across five platforms.** A platform (Claude, Codex, Cursor, Gemini,
OpenCode) usually runs on more than one surface — a CLI, a desktop app, an editor extension —
and the install path belongs to the surface, not the vendor. Pick yours below; every guide
covers **install · verify · update · uninstall**, plus an honest capability table.

| Platform | Surface | Registry id | Kind | Install mechanism | Guide |
|---|---|---|---|---|---|
| Claude | Claude Code | `claude_code` | CLI | plugin marketplace | [claude-code.md](claude-code.md) |
| Claude | Claude Desktop | `claude_desktop` | desktop | same plugin as Claude Code | [claude-desktop.md](claude-desktop.md) |
| Codex | Codex CLI | `codex` | CLI | plugin marketplace | [codex.md](codex.md) |
| Cursor | Cursor IDE | `cursor` | IDE | team marketplace, import from repo | [cursor.md](cursor.md) |
| Gemini | Gemini CLI | `gemini_cli` | CLI | git-URL extension **+ a separate skills install** | [gemini.md](gemini.md) |
| OpenCode | OpenCode CLI | `opencode` | CLI | path (`skills.paths` or symlink) | [opencode.md](opencode.md) |

Each of those five platforms has a second surface — the Codex IDE extension, the Cursor CLI,
Gemini Code Assist, the OpenCode desktop app — that this repo has never installed into or
measured. They have no install guide here, and no capability is claimed for them in either
direction. [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json)
lists each one with the reason it is unverified; the [README](../../../README.md#supported-platforms)
shows the same split at a glance.

## Prerequisites

`git` 2.30+, `jq`, and bash. `gh` is optional and only affects PR/issue workflows. No Node,
no Python, no build step — the toolkit is Markdown, JSON, and bash.

Gemini is the one target where installing the extension is not the whole install: skills
live in a generated flat mirror at `.gemini/skills/` and are installed with a second command.
Gemini discovers skills exactly one level below a root, so the canonical two-level tree finds
zero — silently. The [Gemini guide](gemini.md) explains it before you hit it.

## Two separate things

Installing the plugin makes the skills available *inside* one surface. It writes no
configuration anywhere. Rendering your global rules and policies into the config directory
each CLI actually reads — `~/.claude`, `~/.codex`, `~/.cursor`, `~/.gemini`,
`~/.config/opencode` — is a second, optional step, and it covers **all five platforms at once**:

```bash
make setup-plan     # detect targets, print every change, write nothing
make setup          # diff → confirm → write
```

Every guide below has a **Machine-level setup** section for its own target. The engine and
its three verbs (`plan` / `apply` / `remove`) are documented in [setup](../setup.md); what
the four non-Claude platforms get, and what is deliberately left alone, in
[platform setup](../platform-setup.md).

## Verify any install

```bash
bash scripts/doctor.sh .
```

It reports the detected platform, canonical version and any drift, which tools are present,
which optional features are consequently usable, and a remedy line per gap. It exits
non-zero only when the install is genuinely broken.

## Users vs contributors

These guides are for **using** the toolkit. Working *on* it is a different setup —
see [docs/CONTRIBUTING.md](../../CONTRIBUTING.md). `make install` is not a way to install the
plugin: it is now a thin shim over `setup.sh apply --yes --targets claude`, i.e. the
machine-config step above, restricted to Claude Code.

## Before you file a bug

Capabilities differ per surface, sometimes surprisingly — hooks that do not run under the
Cursor IDE plugin, no parallel subagents outside Claude Code, no session transcripts anywhere
but Claude Code. Check [platform differences](../platform-differences.md) first; the behavior you
are seeing may be the documented, honest degradation.
