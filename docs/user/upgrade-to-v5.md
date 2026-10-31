# Upgrading to 5.0

5.0.0 is a major version because it changes what each host receives and what the plugin
asks of it. Nothing in it touches on-disk objective state: an objective under
`.dev-files/objectives/` that was in flight on 4.x resumes on 5.0 unchanged, and the
legacy worktree layouts (`.claude/.worktrees`, `~/.claude/worktrees/<repo>/<slug>`) stay
recognised. What follows is what changes for you, per host, and what to do about it.
The full record is the `[5.0.0]` section of [`CHANGELOG.md`](../../CHANGELOG.md).

## Every host

| Change | What it means | What to do |
|---|---|---|
| One source, one subset per host | The repository builds a distribution per host (`scripts/build-dist.sh --target …`); the GitHub Release attaches them as tarballs with `SHA256SUMS` and a build-provenance attestation | Install routes are unchanged. To verify an asset: [`release-verification.md`](../engineering/build-and-release/release-verification.md) |
| Thirty skills | `diagnose-objective` joins the dev-workflow set | Run it when an objective fails or stalls: it explains what happened and names the one command to run next |
| Capability registry | New surfaces (`claude_vscode`, `antigravity_cli`) and refreshed notes; `platforms-<version>.json` ships as a release asset | Nothing. A tool that reads the registry should read it from the release |

## Claude Code and Claude Desktop

| Change | What it means | What to do |
|---|---|---|
| Floor **2.1.287** (was 2.0.0); recommended 2.1.299+ | The mod (`mod/register.tsx`) needs the mods engine; bash hooks, skills and agents still run on older builds, but the plugin is no longer validated there | `claude --version`; update if below 2.1.287 |
| Hook tiers are plugin options | `notification_hooks` (default on) and `contributor_hooks` (default off) switch the notification hooks and the plugin-author hooks; core safety and worktree hooks always run | Nothing for most people. A contributor sets `contributor_hooks` under Plugins → Configure or `claude plugin configure tamirs-superpowers` |
| The guard plugin | Holds on destructive shell commands and main-checkout writes under an active objective moved into a second, optional plugin so the core plugin keeps its clean footprint | `/plugin install tamirs-superpowers-guard --marketplace Tamircohen28/tamirs-superpowers` if you want the in-process holds |
| Three guards fail closed | `enforce-worktree-edits.sh`, `guard-sensitive-files.sh` and `docker-guard.py` carry `onFailure: block`: a guard that cannot run denies rather than allows | If a guard errors, the tool call is refused with the error; fix the environment (usually `jq`) rather than retrying |
| Agent-teams hooks | `TaskCompleted` and `TeammateIdle` hooks check the handoff contract for `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` teams | Nothing unless you run agent teams; they are advisory |
| Agent frontmatter | Every specialist agent sets `effort`; the two workers set `autoCompactWindow` | Nothing. `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` and `maxEffortLevel` still override, as before |

## Codex CLI

| Change | What it means | What to do |
|---|---|---|
| Hooks now load | The Codex distribution ships a generated `platforms/codex/hooks.json` (the twelve Codex events, no `modules` key); 4.x shipped the Claude file, which Codex's parser rejected, so no hook ran | After updating, `/hooks` lists them untrusted; review and trust. A content change on the next update resets trust for that hook (Codex keys trust on content) |
| No root Agent Plugins manifest | Measured on 0.163.0: a root `plugin.json` makes Codex drop every hook, so Codex keeps reading `.codex-plugin/plugin.json` | Nothing |
| Stop-family hooks print JSON | `{}` is the no-op Codex requires on exit 0 | Nothing |

## Cursor

| Change | What it means | What to do |
|---|---|---|
| Ten events, fail-closed safety tier | The bundle wires ten of Cursor's twenty-one events (was six); the three guards carry `failClosed: true` | Nothing. A guard that cannot run now denies |
| The GitHub token is a plugin variable | `platforms/cursor/mcp.json` says `${GITHUB_TOKEN}`; the manifest declares it under `variables` | Dashboard → Plugins → tamirs-superpowers → Configure → set `GITHUB_TOKEN` |
| Lifecycle hooks speak Cursor's shapes | `user_message` on stop and subagent stop, `continue` on prompts, `pluginPaths` on workspace open; never `followup_message` | Nothing |

## Gemini CLI

| Change | What it means | What to do |
|---|---|---|
| Hooks and policies ship | The gemini distribution carries a generated `hooks/hooks.json` (Gemini events, `hooks/gemini-wrap.sh`) and `policies/*.toml` (five deny-only rules); 4.x shipped none | Install from the release tarball for hooks (`gemini extensions install <dir> --consent`); a bare git-URL install gets the Claude file, which Gemini misreads. Expect the consent prompt to list hooks and policies |
| The token is a manifest setting | `GITHUB_PERSONAL_ACCESS_TOKEN` under `settings[]`, stored in the OS keychain | `gemini extensions config tamirs-superpowers GITHUB_PERSONAL_ACCESS_TOKEN`, or `--skip-settings` and set it later |
| Consumer sunset | Google retired Gemini CLI for consumer tiers in favour of Antigravity; the adapter stays for enterprise Code Assist and API-key users | Consumer users: see [Antigravity](install/antigravity.md). The adapter is unverified against a live `agy` and ships no hooks |

## OpenCode

| Change | What it means | What to do |
|---|---|---|
| **OpenCode 2 only** (2.2.5+; validated on 2.2.5) | `opencode.json` uses the V2 vocabulary: `permissions` rules, `.opencode/agents/` (plural), `mcp.servers.github`, `plugins[]`; V1 plugins do not run on V2 and V2 shapes do not load on V1 | Follow the official [V1 migration guide](https://opencode.ai/v2/docs/migrate-v1/) (`opencode upgrade --help` on 2.2.5 has no `--major` flag; it takes an optional version and `--method`). OpenCode 1.x users stay on 4.12.x |
| The three core guards are a server plugin | `platforms/opencode/plugin/` (`permission.hook('evaluate')`, `shell.hook`) registered in `plugins[]`; a TUI plugin draws the status line and objective pane | Nothing; it loads with the config. Whether a deny stops an action live is not yet measured |
| `usage-capture` is a V2 plugin | `opencode-plugin.mjs` uses `Plugin.define` | If you listed it in your own `plugins`, keep it; on OpenCode 1 it no longer runs |

## Contributors

| Change | What it means | What to do |
|---|---|---|
| Generated files | `platforms/codex/hooks.json`, `platforms/gemini/hooks.json`, `platforms/gemini/policies/`, `platforms/antigravity/*.json`, `.codex/agents/`, `.opencode/agents/`, `.agents/skills/`, the five manifests and `.cursor/rules/` are generated; CI fails on drift | `make manifests codex-hooks gemini-hooks antigravity-plugin agents-skills codex-agents opencode-agents cursor-rules` after editing a source; `make validate` before every push |
| Host notes | Claude Code release notes live in `docs/engineering/host-notes/`; `platform-targets.json` is authoritative for versions | Add a release note there, not to `CLAUDE.md` |
| New gates | `check-skills-ref`, `check-token-budget` (`evals/budget.json`), `test-skill-contract --strict`, `test-hook-conformance.sh`, the nightly `evals.yml` | A skill that grows the always-on cost past the ceiling fails CI; `bash scripts/check-token-budget.sh --update` after a deliberate change |
