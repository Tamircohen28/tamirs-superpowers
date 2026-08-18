# tamirs-superpowers — Gemini CLI context

Gemini CLI specifics for this repo. **Everything that is not Gemini-specific lives elsewhere — start with [`AGENTS.md`](../AGENTS.md)**, the shared entrypoint into [`core/`](../core/) and [`rules/`](../rules/README.md). This file adds only what is true of the Gemini surface.

When this file and a canonical rule disagree, the canonical rule wins.

## What this repo is

A multi-platform agent plugin (skills, agents, hooks, MCP stubs) shipped to Claude Code, Claude Desktop, Cursor, Codex, Gemini CLI, and OpenCode. No build step, no `package.json`, no compiled output — Markdown, JSON, and Bash. **Do not add Node dependencies to this repo**, including for the Gemini adapter.

## What ships to Gemini, and how

`gemini-extension.json` at the repo root ships the context file and the `github` MCP server. **Skills and sub-agents do not come from the extension** — they come from a generated flat mirror at `.gemini/skills/` and `.gemini/agents/`, because Gemini discovers skills exactly one level below a skills root and the canonical tree is two levels deep. The limits are measured against 0.55.1, not assumed; [`docs/user/install/gemini.md`](../docs/user/install/gemini.md) has the evidence.

| Surface | On Gemini | How |
|---------|-----------|-----|
| Context | ✅ this file | `contextFileName` accepts a subpath |
| MCP | ✅ `github` | `${extensionPath}` keeps it portable |
| Skills | ✅ | generated symlink mirror at `.gemini/skills/` |
| Sub-agents | ✅ | generated at `.gemini/agents/`, `tools` translated to Gemini names |
| Hooks | ❌ none shipped | By design, not a verdict on Gemini. Of this repo's ten hook events, three (`SessionStart`, `SessionEnd`, `Notification`) name real Gemini events and are simply untested; four translate only through `gemini hooks migrate --from-claude`; three have no counterpart. Gemini accepts unknown event names silently, so a dropped-in Claude file would look live while most of it did nothing |

## `.gemini/skills/` and `.gemini/agents/` are GENERATED

Never edit them. Edit `skills/<domain>/<name>/` or `agents/*.md`, then:

```bash
make gemini-extension          # regenerate
make gemini-extension-check    # fail on drift (CI runs this)
```

Skills are symlinks, so there is exactly one copy of every skill in the repo and the mirror cannot drift in content — only in membership, which the check enforces. Gemini's skill namespace is flat, so the generator fails loudly if two domains ever ship the same skill name.

Working inside this repo, you need no install step at all: `.gemini/skills/` is a workspace skills root. Trust the folder when asked — an untrusted folder silently yields zero skills and zero agents, which looks identical to a broken mirror.

## Verifying the adapter

```bash
gemini extensions validate .          # manifest only — shallow by design
bash scripts/check-gemini-adapter.sh  # structural checks, always runs
bash tests/test-gemini-adapter.sh     # behavior tests
make validate                         # the full repo gate
```

`gemini extensions validate` checks the manifest and nothing else — a passing result says nothing about skills, agents, or hooks. `scripts/check-gemini-adapter.sh` is what actually pins the adapter's shape.

## Working in this repo

Branching, worktrees, commits, PRs, and the validation tiers are all canonical — read [`AGENTS.md`](../AGENTS.md) and the [`rules/`](../rules/README.md) index rather than improvising. Two that bite most often:

- Scratch files, plans, and reviews go in `.dev-files/`, never the repo root — [`rules/dev/dev-files-workspace.md`](../rules/dev/dev-files-workspace.md).
- Shipped content changes need a version bump in `plugin-version.json` followed by `--sync`, which is what keeps `gemini-extension.json`'s `version` honest — [`rules/dev/plugin-version-bump.md`](../rules/dev/plugin-version-bump.md).
