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

Verified **2026-09-03** — Claude Code reviewed against the official changelog through **2.1.259** (released 2026-09-02), confirmed as the current npm dist-tag; this cycle's live `claude` CLI reported exactly `2.1.259`, so `validated_against` advances all the way to it, and `claude plugin validate .` (plus its new `--json` mode) and `bash scripts/doctor.sh .` were re-run for real against that CLI and both passed. 2.1.258 (macOS 12 launch regression; remote/scheduled-session permission-resubmission error) was already reviewed in #119 with nothing to adopt. 2.1.259 adds `managedMcpServers`, `--permission-prompts none`, `glab` merge-request recognition, and `--json` for `claude plugin validate` — none apply here (no managed-settings.json shipped, no non-interactive `claude` invocations, GitHub not GitLab, and CI already gates on exit code) — plus bug fixes to capabilities this repo depends on: frontmatter `model:` now honored reliably in auto mode and interactive sessions, worktree isolation no longer misidentifies hook-created worktrees or refuses Bash loops/`xargs`/launcher-wrapped commands, and a blocking `Stop` hook no longer costs the next turn's prompt cache. See `CLAUDE.md`'s Subagents and Hooks bullets and `platform-targets.json`'s `verification_method` for the full review. Cursor was verified against **3.18.9** on 2026-08-30; Gemini CLI remains directly validated at **0.55.1** and OpenCode at **1.18.11** (maintainer-machine run, 2026-08-03). Codex releases are reviewed through **0.152.1** (released 2026-09-01), while direct CLI validation remains at **0.146.0** until the next maintainer-machine run. The 0.150–0.152 delta does not require a plugin-manifest migration: native task references and `Interrupt` hooks are host-specific opportunities; optional-MCP discovery grace, MCP-result interception, per-repository plugin catalog configuration, package-style MCP server names, per-tool MCP `output_token_limit`, and longer app-server shell-command timeouts are native Codex capabilities. `tools.update_plan.enabled` is opt-in starting in 0.152; this repo does not depend on that tool, so no config migration is required. The shared cross-target hook bundle remains unchanged so Codex-only lifecycle semantics cannot alter Claude/Cursor behavior.

| Surface | Min supported | Validated against | Latest known | Install guide |
|----------|---------------|-------------------|--------------|---------------|
| Claude Code | 2.0.0 | 2.1.259 | 2.1.259 | [claude-code.md](../../user/install/claude-code.md) |
| Cursor | 3.18.9 | 3.18.9 | 3.18.9 | [cursor.md](../../user/install/cursor.md) |
| Codex | 0.40.0 | 0.146.0 | 0.152.1 | [codex.md](../../user/install/codex.md) |
| Gemini CLI | 0.55.1 | 0.55.1 | 0.55.1 | [gemini.md](../../user/install/gemini.md) |
| OpenCode | 1.16.2 | 1.18.11 | 1.18.18 | [opencode.md](../../user/install/opencode.md) |

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
