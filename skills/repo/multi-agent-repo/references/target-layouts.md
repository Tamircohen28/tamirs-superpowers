# Target layouts — app vs plugin vs hybrid

Use this reference when classifying `$TARGET_ROOT` at the start of every mode.

## Repo types

| Type | Signals | Skill location | Notes |
|------|---------|----------------|-------|
| **app/library** | `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, etc.; no `.claude-plugin/plugin.json` | `.agents/skills/<name>/SKILL.md` | Canonical portable layout |
| **claude-plugin** | `.claude-plugin/plugin.json` + `skills/` domain dirs | `skills/<domain>/<name>/SKILL.md` per manifest | Do not force `.agents/skills/` |
| **hybrid** | Both app artifacts and plugin manifest | Document per-tool paths in review report | Common in monorepos |

## Recommended app/library layout

```
repo/
├── AGENTS.md                         # Canonical rules (100–200 lines max)
├── CLAUDE.md                         # @AGENTS.md + Claude-only addenda
├── .cursor/
│   └── rules/
│       ├── 000-project.mdc           # alwaysApply: true — points to AGENTS.md
│       ├── frontend.mdc              # optional globs
│       ├── backend.mdc
│       └── tests.mdc
├── .agents/
│   └── skills/
│       └── <skill-name>/
│           └── SKILL.md
├── .claude/
│   └── skills -> ../.agents/skills  # optional symlink (Unix); use @import on Windows
├── docs/
│   └── agent-guidelines/
│       ├── architecture.md
│       ├── testing.md
│       ├── security.md
│       └── style.md
├── scripts/
│   ├── check-agent-drift.sh
│   └── check-no-agent-drift.mjs      # optional Node variant
└── Makefile / package.json           # agent:check / agent:rules targets
```

## Recommended Claude plugin layout

```
repo/
├── AGENTS.md                         # Portable cross-agent rules (no Claude-only syntax)
├── CLAUDE.md                         # @AGENTS.md + plugin contributor rules
├── .claude-plugin/plugin.json
├── skills/<domain>/<name>/SKILL.md
├── .cursor/rules/*.mdc
├── .codex-plugin/plugin.json         # optional
├── .cursor-plugin/plugin.json        # optional
└── hooks/hooks.json
```

## Size and format constraints

| File | Limit | Rule |
|------|-------|------|
| `AGENTS.md` | ≤ 32 KiB | Codex truncates beyond this |
| `AGENTS.md` | 100–200 lines ideal | Commands, constraints, non-obvious patterns only |
| `.cursor/rules/*.mdc` | ≤ 500 lines each | Split by topic |
| `alwaysApply: true` rules | ≤ 2 | More burns context; agents ignore instructions |
| `AGENTS.md` content | No tool-specific syntax | No `!` blocks, `$CLAUDE_SKILL_DIR`, YAML frontmatter |

## Bridging Claude Code

Preferred (cross-platform):

```markdown
@AGENTS.md

## Claude Code-specific
- Use plan mode for risky changes.
```

Avoid duplicating policy text in `CLAUDE.md`. Symlinks (`ln -s AGENTS.md CLAUDE.md`) work on Unix but fail on Windows without Developer Mode — prefer `@AGENTS.md` import.

## Skills portability

| Tool | Default skills path |
|------|---------------------|
| Claude Code (plugin) | `skills/` via `plugin.json` |
| Claude Code (project) | `.claude/skills/` |
| Codex / portable | `.agents/skills/` |
| Cursor | Reads project skills where configured; portable format is `.agents/skills/` |

Same `SKILL.md` format everywhere (YAML frontmatter + markdown body). Bridge with symlinks or document both paths in `AGENTS.md`.
