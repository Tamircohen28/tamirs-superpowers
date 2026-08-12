# Platform target versions

Machine-readable source: [`platform-targets.json`](platform-targets.json).

## The four supported targets

`tamirs-superpowers` ships as a **multi-platform plugin**. These four agent CLIs are the officially supported targets — every skill, doc, and release is validated against all four:

1. **Claude Code**
2. **Cursor**
3. **Codex**
4. **OpenCode**

Anything else is unsupported. Adding a fifth target means adding it to `supported_targets` in `platform-targets.json`, to the table below, to `scripts/check-platform-targets.sh`, and shipping a `docs/user/install/<target>.md` guide.

Row 3 README badges show **platform tool versions** directly validated in this release — not the plugin semver (Row 1).

## Versions

Verified **2026-08-07** — Claude Code from registry.npmjs.org + the official changelog (automated nightly review); other CLIs by running each on the maintainer machine (2026-08-03). Codex **0.147.0** was reviewed on **2026-08-09** against the official release delta and is the version this repo now supports/tracks; direct CLI validation remains at 0.146.0 until the next maintainer-machine run.

| Platform | Min supported | Validated against | Latest known | Install guide |
|----------|---------------|-------------------|--------------|---------------|
| Claude Code | 2.0.0 | 2.1.226 | 2.1.226 | [claude-code.md](../../user/install/claude-code.md) |
| Cursor | 3.15.19 | 3.15.19 | 3.15.19 | [cursor.md](../../user/install/cursor.md) |
| Codex | 0.40.0 | 0.146.0 | 0.147.0 | [codex.md](../../user/install/codex.md) |
| OpenCode | 1.16.2 | 1.18.11 | 1.18.11 | [opencode.md](../../user/install/opencode.md) |

### How each floor was set

`supported_min` is never a guess. Each target records a `supported_min_source` in `platform-targets.json`:

| Platform | Why that floor |
|----------|----------------|
| Claude Code | `.claude-plugin/plugin.json` manifest format has been stable since 2.0.0 |
| Cursor | Cursor's plugin docs state **no** minimum version. Rather than invent one, the floor equals the validated version. Older Cursor releases may work; they are simply untested. |
| Codex | Earliest release this repo has claimed `AGENTS.md` + `.codex-plugin` support for |
| OpenCode | Oldest version on which recursive (domain-nested) `SKILL.md` discovery was verified with `opencode debug skill` |

## Capability coverage

| Capability | Claude Code | Cursor | Codex | OpenCode |
|------------|:---:|:---:|:---:|:---:|
| Skills | ✅ | ✅ | ✅ | ✅ |
| Agents | ✅ | ✅ | ✅ | ✅ (adapters) |
| MCP servers | ✅ | ✅ | ✅ | ✅ |
| Rules | via `CLAUDE.md` | ✅ `.mdc` | via `AGENTS.md` | via `AGENTS.md` |
| Hooks | ✅ | ✅ | ✅ | ❌ JS plugins only |
| Statusline | ✅ | ❌ | ❌ | ❌ |
| Marketplace install | ✅ | ✅ | ✅ | ❌ path install |

OpenCode's gaps are recorded as `capability_gaps` in `platform-targets.json`. The two that matter:

- **No `hooks.json`.** OpenCode's lifecycle automation is JS/TS plugin modules, so the worktree hooks under `hooks/` do not port. Their intent is carried by `AGENTS.md` contributor rules instead.
- **Agent files need adapters.** A Claude Code agent (`tools: Read, Grep, Glob, Bash`, `model: sonnet`) fails OpenCode's config validation — it wants `tools` as an object and a provider-prefixed model. `.opencode/agent/*.md` holds the converted files; regenerate with `make opencode-agents`.

See [`platform-equivalence.md`](../../agent-guidelines/platform-equivalence.md) for the full capability mapping.

## Maintenance

When changing `skills/repo/**`, `platform-specs.md`, or platform-sync sub-skills:

**Agents** (not users) run these Make targets:

| Target | When |
|--------|------|
| `make platform-targets-sync` | Refresh `latest_known` after skill/platform-spec changes |
| `make platform-targets-assert` | Polish exit — configs caught up to latest_known |
| `make opencode-agents` | Regenerate `.opencode/agent/*.md` after editing `agents/*.md` |
| `make agent-polish-gate` | Full pre-PR gate (sync + assert + agent:check) |
| `make platform-targets-cochange` | CI on PRs touching `skills/repo/**` |

After `make platform-targets-sync`, the agent updates `validated_against`, README Row 3 badges, this table, and `CHANGELOG.md`.

Users run `/repo-standards polish` or `/multi-agent-repo dev` — not these Make targets directly.
