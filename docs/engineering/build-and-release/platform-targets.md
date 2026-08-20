# Platform target versions

Machine-readable source: [`platform-targets.json`](platform-targets.json).

**This file is keyed by SURFACE id, and the reshape of the capability registry did not change it.** The capability registry is now rooted at the platform (`claude`, `codex`, `cursor`, `gemini`, `opencode`) with surfaces underneath; `platform-targets.json` was already keyed the way the registry's *surfaces* are keyed, so it stayed exactly as it was. `supported_targets` is still `claude_code`, `codex`, `cursor`, `gemini_cli`, `opencode` — nothing was added, removed, or renamed. If you came here expecting platform-level keys after seeing the new registry, that is the assumption to drop. The one addition is a `platform` back-pointer on each target, naming the registry platform its surface belongs to (`claude_code` → `claude`, `gemini_cli` → `gemini`), so the two files can be joined without a hardcoded mapping.

## The five supported targets

`tamirs-superpowers` ships as a **multi-platform plugin**. These five surfaces are the officially supported targets — every skill, doc, and release is validated against all five:

1. **Claude Code**
2. **Cursor IDE**
3. **Codex CLI**
4. **Gemini CLI**
5. **OpenCode CLI**

### Five targets, six supported surfaces

Both counts are right, and they answer different questions. The capability registry marks **six** surfaces `supported` — the five above plus **Claude Desktop** — while `supported_targets` lists five.

Claude Desktop is the difference. It carries `runtime_surface_of: "claude_code"` in the registry: it installs the Claude Code plugin from the Claude Code listing and ships no manifest, adapter, install command or version consumer of its own. A *target* is something this repo distributes to and validates as a distribution; Claude Desktop is a place that same distribution runs. It is fully supported — all 19 capability rows, several of them honestly `unknown` — and it is not a sixth target. `scripts/check-feature-equivalence.sh` and `tests/test-docs.sh` both skip `runtime_surface_of` surfaces when counting targets, for exactly this reason.

The registry also lists four **unverified** surfaces — Codex IDE extension, Cursor CLI, Gemini Code Assist and OpenCode desktop app. They are not targets and must never be added to `supported_targets`, given a badge, or counted here: nobody has measured them, and they claim nothing in either direction.

Anything else is unsupported. Adding a target means adding its surface id to `supported_targets` in `platform-targets.json`, to the table below, to `scripts/check-platform-targets.sh`, and shipping a `docs/user/install/<target>.md` guide — full procedure: [adding a platform](../architecture/adding-a-platform.md).

The README's platform badge row shows **platform tool versions** directly validated in this release — not the plugin semver, which comes from [`plugin-version.json`](../../../plugin-version.json).

## Versions

Verified **2026-08-17** — Cursor against **3.16.17** on 2026-08-17 (the most recent verification of any target, and therefore the `last_reviewed` date); Claude Code from the official changelog (automated nightly review, through **2.1.233**) on 2026-08-15; the remaining CLIs by running each on the maintainer machine (2026-08-03). Codex **0.147.0** was reviewed on **2026-08-09** against the official release delta and is the version this repo now supports/tracks; direct CLI validation remains at 0.146.0 until the next maintainer-machine run.

| Surface | Min supported | Validated against | Latest known | Install guide |
|----------|---------------|-------------------|--------------|---------------|
| Claude Code | 2.0.0 | 2.1.233 | 2.1.233 | [claude-code.md](../../user/install/claude-code.md) |
| Cursor | 3.16.17 | 3.16.17 | 3.16.17 | [cursor.md](../../user/install/cursor.md) |
| Codex | 0.40.0 | 0.146.0 | 0.147.0 | [codex.md](../../user/install/codex.md) |
| Gemini CLI | 0.55.1 | 0.55.1 | 0.55.1 | [gemini.md](../../user/install/gemini.md) |
| OpenCode | 1.16.2 | 1.18.11 | 1.18.11 | [opencode.md](../../user/install/opencode.md) |

### How each floor was set

`supported_min` is never a guess. Each target records a `supported_min_source` in `platform-targets.json`:

| Surface | Why that floor |
|----------|----------------|
| Claude Code | `.claude-plugin/plugin.json` manifest format has been stable since 2.0.0 |
| Cursor | Cursor's plugin docs state **no** minimum version. Rather than invent one, the floor equals the validated version. Older Cursor releases may work; they are simply untested. |
| Codex | Earliest release this repo has claimed `AGENTS.md` + `.codex-plugin` support for |
| Gemini CLI | Gemini CLI documents no minimum for extensions; the floor is the version the adapter was actually exercised on (0.55.1) rather than guessed |
| OpenCode | Oldest version on which recursive (domain-nested) `SKILL.md` discovery was verified with `opencode debug skill` |

## Capability coverage

Coarse summary only — the authoritative, per-capability picture is
[`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json), rendered for
users at [platform differences](../../user/platform-differences.md). The columns are the
five *targets*; Claude Desktop's rows live in the registry and in
[`platform-equivalence.md`](../../agent-guidelines/platform-equivalence.md), which is
keyed by all six supported surfaces.

| Capability | Claude Code | Cursor IDE | Codex CLI | Gemini CLI | OpenCode CLI |
|------------|:---:|:---:|:---:|:---:|:---:|
| Skills | ✅ | ✅ | ✅ | ✅ | ✅ |
| Agents | ✅ | ✅ | ✅ | ❌ frontmatter rejected | ✅ (adapters) |
| MCP servers | ✅ | ✅ | ✅ | ✅ | ✅ |
| Rules | via `CLAUDE.md` | ✅ `.mdc` | via `AGENTS.md` | via `.gemini/GEMINI.md` | via `AGENTS.md` |
| Hooks | ✅ | ⚠️ project-level only | ✅ manifest field | see install guide | ❌ JS plugins only |
| Statusline | ✅ | ❌ | ❌ | ❌ | ❌ |
| Marketplace install | ✅ | ✅ | ✅ | ❌ git-URL extension | ❌ path install |

Gemini's gaps are recorded as `capability_gaps` in `platform-targets.json`, measured on
0.55.1: no extension-declared statusline, no marketplace, and `agents/*.md` rejected because
Gemini expects its own tool names rather than Claude's. Nothing is shipped that would error
on every command.

OpenCode's gaps are recorded the same way. The two that matter:

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
