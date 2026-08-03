# Install on OpenCode

| | |
|---|---|
| **Validated against** | OpenCode **1.18.11** |
| **Minimum supported** | **1.16.2** — oldest version on which recursive skill discovery was verified |
| **Manifest** | none — OpenCode has no plugin-manifest bundle |
| **Config** | `opencode.json` (`skills.paths`), `.opencode/agent/` |
| **Official docs** | [Skills](https://opencode.ai/docs/skills/) · [Config](https://opencode.ai/docs/config/) · [Agents](https://opencode.ai/docs/agents/) |

Check your version:

```bash
opencode --version
```

## How OpenCode differs

OpenCode has no plugin marketplace and no plugin manifest. Its "plugins" are JavaScript/TypeScript modules registered under `"plugin"` in `opencode.json` — a different thing entirely from a skill bundle. So this repo installs on OpenCode by **path**: point OpenCode at the skills, and it reads them natively.

That is not a downgrade. OpenCode scans `.claude/skills/` and `.agents/skills/` alongside its own `.opencode/skills/`, so a Claude-shaped skill tree works without conversion.

> **Nested skills work.** OpenCode's published docs say discovery does not recurse into subdirectories. That is inaccurate as of 1.16.2 — this repo's domain-nested layout (`skills/<domain>/<name>/SKILL.md`) was verified discovered with `opencode debug skill` on both 1.16.2 and 1.18.11. OpenCode's own bundled `customize-opencode` skill confirms the loader scans `**/SKILL.md`.

## Method A — global install (all projects)

Symlink the clone into a path OpenCode scans globally:

```bash
git clone https://github.com/Tamircohen28/tamirs-superpowers.git ~/src/tamirs-superpowers
mkdir -p ~/.config/opencode
ln -s ~/src/tamirs-superpowers/skills ~/.config/opencode/skills
```

Symlinks are followed. Update with `git pull` — no re-link needed.

Other global paths OpenCode scans, if you prefer one:

| Path | Notes |
|------|-------|
| `~/.config/opencode/skill/` or `skills/` | OpenCode's own |
| `~/.claude/skills/` | Shared with Claude Code — install once, both read it |
| `~/.agents/skills/` | Shared agent convention |

## Method B — per-project via `skills.paths`

Add to the project's `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "skills": {
    "paths": ["../tamirs-superpowers/skills/toolkit"]
  }
}
```

`skills.paths` accepts absolute paths, relative paths, and *zero-level* paths — a path that **is** the skill directory (containing `SKILL.md` directly), not a parent of skill directories. All three forms were verified working.

This repo's own `opencode.json` uses the zero-level form for four entries, because pointing at `skills/repo` wholesale also picks up the two gold-fixture skills under `skills/repo/_contract/fixtures/`. Listing the real skills individually keeps the fixtures out:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "skills": {
    "paths": [
      "skills/creative", "skills/debugging", "skills/dev-workflow",
      "skills/documentation", "skills/mcp", "skills/toolkit",
      "skills/repo/cleanup", "skills/repo/multi-agent-repo",
      "skills/repo/repo-scaffold", "skills/repo/repo-standards"
    ]
  }
}
```

## Agents

Claude agent files do **not** load on OpenCode as-is — `tools: Read, Grep, Glob, Bash` must be an object of tool→boolean, and `model: sonnet` needs a provider prefix. This repo ships pre-translated adapters in `.opencode/agent/`, generated from `agents/*.md`:

```bash
mkdir -p ~/.config/opencode/agent
cp ~/src/tamirs-superpowers/.opencode/agent/*.md ~/.config/opencode/agent/
```

To regenerate after editing `agents/`:

```bash
make opencode-agents
```

## MCP servers (optional)

OpenCode does not read `.mcp.json`. Port the entries you want into the `mcp` block of `opencode.json` — see the [MCP docs](https://opencode.ai/docs/mcp-servers/). Use environment variables for tokens; never commit them.

## Verify

```bash
opencode debug skill           # lists every discovered skill
opencode debug agent security-reviewer
opencode debug config          # resolved config, including skills.paths
```

`opencode debug skill` should list all 27 skills and no fixture skills (`demo`, `example-skill`). If those two appear, a `skills.paths` entry is pointing at `skills/repo` rather than the four individual skill directories.

## What does not port

| Feature | Status on OpenCode |
|---------|--------------------|
| Hooks (`hooks/hooks.json`) | ❌ OpenCode has no `hooks.json`. Lifecycle automation is JS/TS plugin modules only — the worktree guards in `hooks/` do not port. |
| Statusline | ❌ No plugin-declared statusline |
| Marketplace install | ❌ No plugin marketplace — install is by path |
| `.mcp.json` auto-wiring | ❌ Port entries into `opencode.json` manually |

Skills and agents work fully.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| No skills listed | Run `opencode debug config` and confirm `skills.paths` resolved. Relative paths resolve against the config file's directory. |
| `Configuration is invalid at .opencode/agent/<x>.md` | An unconverted Claude agent file. Use `.opencode/agent/` adapters, or regenerate with `make opencode-agents`. |
| Fixture skills `demo` / `example-skill` appear | A `skills.paths` entry points at `skills/repo`; list the four real repo skills individually. |
| Symlinked skills not found | Confirm the link target exists — `ls -L ~/.config/opencode/skills`. |
