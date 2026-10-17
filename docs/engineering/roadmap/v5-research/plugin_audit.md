# tamirs-superpowers — factual audit of what ships and is used TODAY

Audited 2026-10-17 against the repository root at commit `2d9ee21` (`fix(registry): OpenCode parallel_subagents -> unknown, release 4.12.2 (#284)`), version **4.12.2** (`plugin-version.json`). Read-only; no file in the repo was modified. All paths are repo-relative unless absolute.

Top-level facts (`AGENTS.md`, `CLAUDE.md`): one canonical source tree shipped to **five platforms / six supported surfaces** (Claude Code, Claude Desktop, Codex CLI, Cursor IDE, Gemini CLI, OpenCode CLI) plus four surfaces explicitly listed as `unverified` (Codex IDE ext, Cursor CLI, Gemini Code Assist, OpenCode desktop). No build step for content; Markdown + JSON + Bash (+ one TSX mod, a few Python/mjs helpers).

---

## 1. Inventory

### 1.1 Skills — 29 shipped (`skills/<domain>/<name>/SKILL.md`; 3 more SKILL.md are gold-fixture samples under `skills/repo/_contract/fixtures/`, not shipped)

All 29 set `model: sonnet` except `diagnose-refusal` and `usage-capture` (no model). All set `user-invocable: true` / `disable-model-invocation: false` except the three internal companions (`user-invocable: false`). Exactly one uses `context: fork` (`targeted-debug`, `agent: Explore`). No skill sets `hooks`, `paths`, or `disallowed-tools`. Capability declarations are in `metadata.tamirs.capabilities.{required,optional}` (no skill uses a `preferred` key).

| Skill | Category / role / tier | effort | allowed-tools | caps required → optional | Scripts it runs (from SKILL.md body) |
|---|---|---|---|---|---|
| field-notebook-ui | creative / implementer / 1 | medium | Read | skills → artifacts, shell | none (references only) |
| diagnose-refusal | debugging / debugger / 1 | medium | Read, Grep, Glob | skills, shell → git, mcp | `scripts/collect-environment.sh`, `scripts/init-bundle.sh`, `scripts/redact-secrets.py` (skill-local) |
| targeted-debug | debugging / debugger / 1 | medium | Read, Grep, Glob; **`context: fork`, `agent: Explore`** | skills, shell → subagents, git | `scripts/extract-error-paths.sh` |
| decision | dev-workflow / none / 0 | medium | AskUserQuestion | skills → ask_user_question, github_cli, shell | none |
| deliver-dev | dev-workflow / integrator / 2 | high | Read, Glob, Grep, Skill(orchestrate-dev, pr-dev, start-dev) | skills, shell, git, github_cli | `_shared/scripts/handoff.sh`, `objective-state.sh`, `run-pre-pr-gates.sh` |
| orchestrate-dev | dev-workflow / orchestrator / 2 | high | Read, Glob, Grep, **Agent**, Skill(decision, deliver-dev, pr-dev, start-dev, worker-dev) | skills, shell, git → subagents, parallel_subagents, worktree_isolation, github_cli, background_tasks | `_shared/scripts/{handoff,objective-state,resolve-worktree}.sh`, `scripts/agent-health.sh` |
| plan-dev | dev-workflow / planner / 0 | high | Read, Glob, Grep, Agent | shell, git → github_cli, subagents | `scripts/validate_plan.py`, `_shared/scripts/{detect-multi-platform-repo,default-branch,objective-state}.sh` |
| pr-dev | dev-workflow / integrator / 3 | high | Read, Glob, Grep, Agent, Skill(cleanup, decision, deliver-dev, switch-dev) | shell, git, github_cli → background_tasks | `scripts/{fetch-pr-state,resolve-thread,resolve-merge-policy,cleanup-after-merge}.sh`, `_shared/run-pre-pr-gates.sh`; `references/ci-monitor-loop.md` is the one `Monitor` call site (30-min timeout) |
| start-dev | dev-workflow / implementer / 2 | high | Read, Glob, Grep, Agent, Skill(decision, deliver-dev, orchestrate-dev, pr-dev, switch-dev, worker-dev) | shell, git → github_cli, worktree_isolation, subagents | `scripts/{detect-objective,detect-stack}.sh`, `_shared/{detect-multi-platform-repo,objective-state,parse-issue-resume,resolve-worktree,run-pre-pr-gates,default-branch}.sh` |
| switch-dev | dev-workflow / none / 0 | high | Read, Glob, Grep | shell, git → github_cli, worktree_isolation | `scripts/parse-mode-args.sh`, `_shared/{detect-platform,handoff,list-agent-worktrees,objective-state,parse-issue-resume,resolve-worktree,update-issue-resume}.sh`; templates `handoff-comment.md.tmpl`, `resume-block.md.tmpl` |
| worker-dev | dev-workflow / implementer / 1 | high | Read, Glob, Grep, Skill(decision, deliver-dev, orchestrate-dev, start-dev) | skills, shell, git → subagents, worktree_isolation | `_shared/{handoff,objective-state}.sh`, `scripts/agent-health.sh` |
| changelog-review (**internal**) | documentation / reviewer / 2 | low | WebFetch(domain:code.claude.com\|github.com\|raw.githubusercontent.com), Read, Grep, Glob | skills → shell | `scripts/{check-skill-frontmatter,validate-plugin-json}.sh`, `scripts/check-version-truth.sh` |
| dark-terminal-doc | documentation / implementer / 1 | medium | Read | skills | none |
| docs-review (**internal**) | documentation / reviewer / 2 | low | Read, Glob, Grep | skills, shell → git | `scripts/{check-template,detect-plan-files,file-freshness,validate-links}.sh` |
| platform-sync | documentation / research-agent / 0 | high | Read, Glob, Grep, WebFetch(domain: code.claude.com, docs.claude.com, support.claude.com, github.com, raw.githubusercontent.com, docs.cursor.com, opencode.ai, registry.npmjs.org, cloud.google.com, developers.openai.com) | skills → parallel_subagents, subagents, slash_commands, shell | none; `references/platforms/{claude-code,codex,cursor,gemini-cli,opencode}.md`, `probe.md`, `registry.md`, `analysis-protocol.md`, `urls.md`, `detection.md` |
| mcp-builder | mcp / implementer / 1 | medium | Read, Glob, Grep, Skill(mcp-pagination, platform-sync) | skills, shell → mcp | `scripts/scaffold.sh` |
| mcp-pagination (**internal**) | mcp / reviewer / 1 | low | Read | skills → shell | `scripts/check-pagination.sh` |
| cleanup | repo / integrator / 3 | high | Read, Agent, Skill(decision, pr-dev), Glob, Grep | shell, git → github_cli, worktree_isolation | `scripts/cleanup.sh` |
| github-policy | repo / reviewer / 2 | high | Read, Grep, Glob | shell, github_cli → git | root `scripts/github-policy.sh` (1454 lines) |
| multi-agent-repo | repo / reviewer / 2 | high | Read, Glob, Grep, Agent | shell, git → github_cli | `scripts/{inventory-agent-setup,parse-mode-args,score-inventory-gaps,check-agent-drift}.sh` (shims into `_contract`); templates `check-no-agent-drift.mjs.tmpl`, `pr-body`, `remediation-plan`, `review-report` |
| repo-scaffold | repo / implementer / 3 | high | Read, Glob, Grep, Agent, Skill(github-policy, multi-agent-repo, pr-dev, skill-creator, start-dev) | shell, git → github_cli | `scripts/detect-stack.sh`; `_contract/scripts/{assert-contract,check-readme-branding,enable-repo-merge-settings,ensure-branch-protection}.sh`, `_contract/templates/check-agent-drift.sh`, `scripts/github-policy.sh` |
| repo-standards | repo / reviewer / 2 | high | Read, Glob, Grep, Agent, Skill(changelog-review, docs-review, github-policy, multi-agent-repo, platform-sync, pr-dev, repo-scaffold, start-dev) | shell, git → github_cli | `scripts/{ip-scan,parse-mode-args,score-contract-gaps,standards-inventory,assert-contract,check-repo-hygiene,score-standards-gaps}.sh`, `_contract/scripts/detect-contract-profile.sh`, `scripts/check-doc-claims.sh`, `scripts/check-platform-targets.sh` |
| capture-config | toolkit / integrator / 2 | medium | Read, Grep, AskUserQuestion | shell, git → github_cli, ask_user_question | `scripts/capture-config.sh`, `scripts/doctor.sh`, `scripts/setup.sh` |
| find-skill | toolkit / research-agent / 0 | medium | Skill(skill-creator) | skills → shell | none; `references/sources.{json,md}` |
| notify-setup | toolkit / none / 0 | medium | Read, AskUserQuestion | **hooks**, shell → ask_user_question | `hooks/notify.sh`, `scripts/notify-pushover.sh`, `scripts/pushover_format.py`, `scripts/uninstall.sh` |
| retro | toolkit / none / 0 | high | Read | skills → session_transcripts, subagents, hooks | none |
| session-report | toolkit / none / 0 | medium | Read | **session_transcripts**, shell | `analyze-sessions.mjs`, `template.html` |
| skill-creator | toolkit / implementer / 1 | medium | Read, Glob, Grep, Agent | skills, shell → subagents, parallel_subagents, background_tasks | `scripts/{run_eval,run_loop,improve_description,package_skill,aggregate_benchmark,generate_report,quick_validate,utils}.py`, `eval-viewer/generate_review.py`, root `scripts/validate-skill-frontmatter.py`; sub-agents `agents/{analyzer,comparator,grader}.md` |
| usage-capture | toolkit / none / 1 | medium | Read | shell → hooks | `scripts/usage-capture/{collector.py,enable.sh}`, `hooks/usage-capture-ensure.sh`, `opencode-plugin.mjs` (skill-local) |

Shared dev-workflow scripts (`skills/dev-workflow/_shared/scripts/`, 10 files, 2,081 lines): `default-branch.sh`, `detect-multi-platform-repo.sh`, `detect-platform.sh`, `handoff.sh`, `list-agent-worktrees.sh`, `objective-state.sh`, `parse-issue-resume.sh`, `resolve-worktree.sh`, `run-pre-pr-gates.sh`, `update-issue-resume.sh`.

Every skill ships `evals/evals.json` + `evals/trigger-evals.json` (skill-creator's trigger-accuracy format, run by `skills/toolkit/skill-creator/scripts/run_eval.py`; **not executed in CI**, see `tests/test-skill-contract.sh` "eval coverage (report — use --strict to gate)").

Invocation tiers (`CLAUDE.md` §"Invocation tiers"): 26 user+auto skills; 0 explicit-only (`switch-dev` was, and it cost "0 invocations across 953 sessions"); 3 internal companions (`changelog-review`, `docs-review`, `mcp-pagination`). The 26 user-invocable skills are what `.cursor/commands/` and `.opencode/commands/` are generated from.

Skills that `require` Claude-leaning capabilities: `notify-setup` requires `hooks`; `session-report` requires `session_transcripts`; `deliver-dev`, `pr-dev`, `github-policy` require `github_cli`. Skills that list `subagents`/`parallel_subagents` as optional: `orchestrate-dev`, `plan-dev`, `start-dev`, `worker-dev`, `targeted-debug`, `platform-sync`, `skill-creator`, `retro`. `worktree_isolation` optional: `orchestrate-dev`, `start-dev`, `switch-dev`, `worker-dev`, `cleanup`. `background_tasks` optional: `orchestrate-dev`, `pr-dev`, `skill-creator`. `artifacts` optional: `field-notebook-ui`. `ask_user_question` optional: `decision`, `capture-config`, `notify-setup`. Degradation text per capability lives in `core/capabilities/platforms.json` `capability_definitions.*.degradation` and `orchestrate-dev/references/{capability-gating,sequential-fallback}.md`.

### 1.2 Agents — 10 (`agents/*.md`), all `model: sonnet`, each declares a `role:` from `core/roles/`

| Agent | role | tools |
|---|---|---|
| architecture-reviewer | reviewer | Read, Grep, Glob |
| debugging-specialist | debugger | Read, Grep, Glob, Bash |
| implementer | implementer | Read, Grep, Glob, Bash, Edit, Write |
| integrator | integrator | Read, Grep, Glob, Bash, Edit, Write |
| orchestrator | orchestrator | Read, Grep, Glob, Bash |
| performance-reviewer | performance-reviewer | Read, Grep, Glob, Bash |
| research-agent | research-agent | Read, Grep, Glob, WebSearch, WebFetch, mcp__claude_ai_Context7__resolve-library-id, mcp__claude_ai_Context7__query-docs |
| security-reviewer | security-reviewer | Read, Grep, Glob, Bash |
| spec-reviewer | reviewer | Read, Grep, Glob, Bash |
| test-engineer | test-engineer | Read, Grep, Glob, Bash, Edit, Write |

No agent sets `effort`, `omitClaudeMd` (reviewed and declined, `CLAUDE.md`), `skills:`, `maxTurns`, or `permissionMode`. Generated translations: `.opencode/agent/*.md` (10, `scripts/build-opencode-agents.sh`, explicit `deny` per non-granted tool), `.gemini/agents/*.md` (10, `scripts/build-gemini-extension.sh`, tools array, `model:` omitted). Cursor reads `agents/` directly via `.cursor-plugin/plugin.json` `"agents": "./agents/"` but does not enforce `tools:` — hence `hooks/cursor-agent-tools-guard.sh`.

### 1.3 Hooks — `hooks/hooks.json` (27 shell-form commands + 1 Python, 13 events, plus `"modules": ["../mod/register.tsx"]`)

| Event | Matcher | Script | timeout | One line (from script header / `docs/engineering/architecture/hooks-classification.md`) |
|---|---|---|---|---|
| PreToolUse | `Bash\|Shell` | `hooks/protect-other-branches.sh` (394 l) | 15 | Concurrency guard: block push/`gh` mutations on a branch/PR/issue another agent holds a live claim on (`lib/agent-claim.sh`); integrator carve-out. **core-safety-invariant** |
| PreToolUse | `Edit\|Write\|MultiEdit\|NotebookEdit\|StrReplace` | `hooks/enforce-worktree-edits.sh` (296 l) | 10 | Deny edits in a main checkout; allows objective/legacy/native worktree layouts. **core-safety-invariant** |
| PreToolUse | same | `hooks/guard-sensitive-files.sh` (164 l) | 5 | Block writes to generated/protected files (lockfiles, workflows, build output); keys on write *targets* via `lib/write-targets.py`. **core-safety-invariant** |
| PreToolUse | same | `hooks/skill-creator-guard.sh` (68 l) | 5 | Inject reminder to use `/skill-creator` when a SKILL.md is written by hand. claude-convenience |
| PreToolUse | `Bash\|Shell` | `python3 hooks/docker-guard.py` (199 l) | 5 | Deny Docker commands that leave durable state unless `PM_ALLOW_DOCKER=1`. **core-safety-invariant** |
| PreToolUse | `Bash\|Shell` | `hooks/guard-sensitive-files.sh` | 5 | Same guard applied to shell write paths (`tee`, `sed -i`, redirects). |
| PostToolUse | `Edit\|Write` | `hooks/plugin-reload-reminder.sh` (28 l) | 5 | Remind `/reload-plugins` after editing plugin/hooks/marketplace manifests. contributor-only |
| PostToolUse | `Write` | `hooks/validate-report-links.sh` (89 l) | 10 | Validate URL patterns in `report.md`. contributor-only |
| SessionStart | — | `hooks/show-changelog.sh` (55 l) | — | Show changelog on version change (state via `lib/plugin-state.sh` / `CLAUDE_PLUGIN_DATA`). platform-specific |
| SessionStart | — | `hooks/session-init.sh` (203 l) | — | Init session dirs, reload session-files, prune stale worktrees, cache-staleness `additionalContext` (2.1.251 fields). worktree-lifecycle |
| SessionStart | — | `hooks/usage-capture-ensure.sh` (26 l) | 5 | Start local usage collector when `TAMIRS_USAGE_CAPTURE=1`. optional |
| SessionEnd | — | `hooks/session-end.sh` (39 l) | 30 | Archive session files, prune stale worktrees. worktree-lifecycle |
| SessionEnd | — | `hooks/handoff-reminder.sh` (49 l) | 10 | Remind to run `switch-dev handoff` from active worktrees (`systemMessage`). claude-convenience |
| SessionEnd | — | `hooks/release-agent-claims.sh` (27 l) | 10 | Release this agent's work claims. **core-safety-invariant** |
| UserPromptSubmit | — | `hooks/capture-task-slug.sh` (308 l) | 60 | Derive task slug from first prompt, create/reuse global worktree; stands down under an active objective. worktree-lifecycle |
| UserPromptSubmit | — | `hooks/goal-condition-lint.sh` (202 l) | 5 | Refuse a `/goal` condition that cannot terminate (blocks). **core-safety-invariant** |
| UserPromptSubmit | — | `hooks/goal-compact-reminder.sh` (22 l) | 5 | Remind `/compact` before `/goal`/`/login`. claude-convenience |
| UserPromptSubmit | — | `hooks/scope-decompose-reminder.sh` (23 l) | 5 | Nudge decomposition on sweeping prompts. claude-convenience |
| UserPromptSubmit | — | `hooks/ensure-exit.sh` (21 l) | 10 | Opt-in proxy exit-node check (`CLAUDE_EXIT_PROXY`). optional-notification |
| UserPromptSubmit | — | `hooks/skill-suggest.sh` (167 l) | 5 | Keyword-match the prompt to a bundled skill, inject `additionalContext` once per skill/session/repo. claude-convenience |
| WorktreeCreate | — | `hooks/worktree-create.sh` (270 l) | 120 | Create objective/global worktree; doubles as CLI (`--list`, `--migrate`). worktree-lifecycle |
| WorktreeRemove | — | `hooks/worktree-remove.sh` (63 l) | 60 | Remove agent worktrees in either layout, never a main checkout. worktree-lifecycle |
| DirectoryAdded | — | `hooks/directory-added.sh` (38 l) | 10 | Warn immediately when `/add-dir` adds a main checkout. claude-convenience |
| Notification | — | `hooks/notify.sh` (45 l) | 5 | macOS/OSC-99 desktop notification prefixed with task slug. optional-notification |
| Notification | — | `scripts/notify-pushover.sh` (102 l) | 10 | Pushover phone push, credentials from `userConfig` only (4.11.0). optional-notification |
| Stop | `*` | `hooks/check-done.sh` (125 l) | 10 | Advisory, tier-aware definition-of-done reminder when uncommitted changes exist. claude-convenience |
| StopFailure | `rate_limit` | `hooks/rate-limit-handoff.sh` (76 l) | 10 | `systemMessage` naming resumable work after a rate-limit kill. claude-convenience |
| SubagentStop | — | `hooks/subagent-handoff-check.sh` (80 l) | 10 | Warn orchestrator when a worker returns without a handoff / `completed` without validation. claude-convenience |
| PreCompact | — | `hooks/precompact-snapshot.sh` (86 l) | 10 | Write branch/dirty-files/objective snapshot to `.dev-files/compaction/latest.md`. claude-convenience |

Not in `hooks/hooks.json`: `hooks/cursor-agent-tools-guard.sh` (157 l) — Cursor-only, wired in `platforms/cursor/hooks.json` (`preToolUse` + `postToolUse`). Shared libs: `hooks/lib/agent-claim.sh` (688 l, tool-neutral claim store), `hook-output.sh` (90 l, Claude/Cursor JSON dialect), `objective-common.sh` (242 l), `platform-tools.sh` (39 l, maps Codex `apply_patch`/Cursor `Shell` tool names), `plugin-state.sh` (38 l, `CLAUDE_PLUGIN_DATA` with fallback), `worktree-common.sh` (750 l, protected), `write-targets.py` (968 l). Total hooks tree: 6,135 lines. Events NOT wired: `SubagentStart`, `PermissionRequest`, `PreModelSwitch`/`PostModelSwitch`, `PostCompact`, `mcp_tool` hooks (all noted as reviewed in `CLAUDE.md`).

Cursor bundle `platforms/cursor/hooks.json`: `preToolUse` → cursor-agent-tools-guard, enforce-worktree-edits, guard-sensitive-files, protect-other-branches, skill-creator-guard; `beforeShellExecution` → guard-sensitive-files; `postToolUse` → cursor-agent-tools-guard. Cursor exposes 21 events; plugin wires 3 (`docs/user/install/cursor.md` table). Project-root `.cursor/hooks.json` (contributor-only, advisory `beforeShellExecution` → `.cursor/hooks/warn-contributor-policy.sh`).

### 1.4 The mod — `mod/register.tsx` (510 lines), `mod/types/index.d.ts` (58 lines), `mod/mods.test.tsx` (21 tests)

Named by `hooks/hooks.json` `modules: ["../mod/register.tsx"]`; `$.state` contract named by `.claude-plugin/plugin.json` `"types": "./mod/types/index.d.ts"`. Imports `atom, read, update` + type `Register` from `'claude-code'`.

**14 `on(...)` registrations:** `session.start`; `command.run {command:'objective'}`; `ui.render {component:'Pane', requestId:'objective'}`; `agent.spawn`; `ui.render {component:'Spinner'}`; `ui.render {component:'UserMessage', props.origin.kind:'task-notification'}`; `session.measure`; `ui.render {component:'AbovePrompt'}`; `prompt.submit`; `turn.start`; `tool.call`; `turn.complete`; `session.compact`; `attribution.text {kind:'commit'}`.

**`$` capabilities used (call counts):** `$.clock.every` 1, `$.clock.now` 3, `$.command.register` 1, `$.env.get` 3 (`OBJECTIVES_ROOT`, `SUPERPOWERS_OBJECTIVE_STATE_DIRNAME`, `SUPERPOWERS_OBJECTIVE_ID`), `$.fs.exists` 7, `$.fs.list` 1, `$.fs.read` 6, `$.model.classify` 1, `$.session.repo` 3, `$.session.root` 1, `$.ui.invalidate` 2, `$.ui.open` 1, `$.ui.resolve` 3, `$.ui.toast` 1. State atoms (`$.state` via `atom`): `objective`, `usage`, `limitWarning`, `dismissedAtPercent`, `workers`. **Not used:** `$.process.*`, `$.http.*`, `$.tool.register`, `$.session.append`, `$.ui.view`, `$.ui.selection`, `$.fs.stat`, `$.fs.write`, `prompt.submit` *call* (only the hook), `$.session.usage()` directly (figures arrive via `session.measure`). No `.catch` handlers are present in the checked-out source (PR #271 adds them on branch `claude-code-update`, unmerged).

**Features (from the header, quoted in §5):** (1) objective pane + `/objective` (immediate), spinner worker count, compact task-notification row; (2) rate-limit band at `rate_limit_warn_percent` with Dismiss and a one-per-5-point toast — displays "type /switch-dev handoff", submits nothing; (3) usage line on Desktop only (`e.surface === 'desktop'`); (4) *removed in 4.11.1* Pushover post; (5) opt-in semantic skill suggestion (`semantic_skill_suggest`, prompts ≥12 words, `SKILL_LABELS` = 26 public skills + `none`, once per label per load, attached as `context`); (6) DoD line under an answer that wrote files (`WRITE_TOOLS` = Edit/Write/MultiEdit/NotebookEdit, main loop only), compaction snapshot (branch from `.git/HEAD` + objective text), Co-Authored-By trailer appended when the repo's `CLAUDE.md` declares one.

**userConfig options** (`.claude-plugin/plugin.json`): `github_token` (sensitive, for MCP), `pushover_token` + `pushover_user` (sensitive, read by `scripts/notify-pushover.sh` only), `rate_limit_warn_percent` (number, default 85, 50–100, mod), `semantic_skill_suggest` (boolean, default false, mod). `docs/engineering/architecture/mods.md` still says "Three non-sensitive userConfig fields" but lists two — stale by one (the third, `pushover_min_turn_seconds`, was removed in 4.11.1).

**Tests:** 21 `test(...)` in `mod/mods.test.tsx` (mods.md and `platform-targets.json` text say 23/24 in places — stale counts; `CHANGELOG` 4.11.1 says 21). Run by `claude plugin test .` (`make test-mods`, CI job `plugin-validate`). `make typecheck-mods` (`scripts/typecheck-mods.sh`) skips with a notice without a `claude-code.d.ts`; not a CI gate.

### 1.5 MCP servers

`.mcp.json`: one stdio server `github` → `${CLAUDE_PLUGIN_ROOT}/scripts/github-mcp.sh` (33 l; tries the official `github-mcp-server` binary, falls back to `docker run ghcr.io/github/github-mcp-server stdio`), env `GITHUB_PERSONAL_ACCESS_TOKEN: ${user_config.github_token}`; refuses to start without the token. Referenced by `.claude-plugin`, `.codex-plugin`, `.cursor-plugin` manifests (`mcpServers: ./.mcp.json`). `gemini-extension.json` declares the same server separately with `${extensionPath}` (Gemini has no option store; user exports the env var). OpenCode: not declared (`opencode.json` has no `mcp`). `agents/research-agent.md` additionally names `mcp__claude_ai_Context7__*` tools (a claude.ai connector, not shipped here).

### 1.6 Output styles, statusline, templates, config/

- `output-styles/evidence.md` — one style `Evidence`, `keep-coding-instructions: true`, no `force-for-plugin`; Claude Code only (`tests/test-output-styles.sh`).
- Statusline — `scripts/statusline.sh` (372 l) wired via manifest `settings.statusLine.command` (CLAUDE_PLUGIN_ROOT first, then marketplace-cache glob); 2–5 lines (model/effort/repo/branch/ctx/version; 5h; 7d; spend_limit; prompt_cache). Bounded `read -t`, never blocks (`docs/engineering/statusline.md`, `tests/test-statusline.sh`). Claude Code only; Desktop gets the mod's AbovePrompt usage line instead.
- `templates/global-CLAUDE.md` — global `~/.claude/CLAUDE.md` template with `<YOUR_GITHUB_HANDLE>`/`<YOUR_EMPLOYER>`/`<YOUR_PROJECTS_PATH>` placeholders; `core/global-rules.md` is the canonical cross-platform rules file rendered by `scripts/setup.sh` to `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`, `~/.cursor/rules/tamirs-superpowers.mdc`, `~/.config/opencode/AGENTS.md`.
- `config/github/repository-policy.json` (v1.3.0, schema `core/schemas/repository-policy.json`) — canonical GitHub rulesets (target `~DEFAULT_BRANCH`, strict status checks deliberately off, per-repo required contexts incl. `Tamircohen28/iBrain` 11 contexts); consumed by `scripts/github-policy.sh` (audit|plan|apply|verify) and `scripts/check-github-policy.sh`.

### 1.7 platforms/ adapters and generators

`platforms/<id>/adapter.yaml` (routing table only; coarse `skills/agents/hooks/mcp`), `setup.conf` (modules rendered by `scripts/setup.sh`), `capture.conf` (classification for `scripts/capture-config.sh`), and per-platform templates.

| Platform | adapter.yaml coarse caps | setup modules | Generated artifacts (generator → output, `--check` drift mode) |
|---|---|---|---|
| claude | skills native, agents native, hooks native, mcp native | settings plugins statusline agents claude-md exit-guard | none generated; `platforms/claude/settings.d/*.json` (7 fragments: auto-mode, defaults, marketplaces, misc, permissions-allow, permissions-ask, plugins) deep-merged into `~/.claude/settings.json`; `platforms/claude/directory/README.md` replaces README in the Claude-only dist |
| codex | skills native, agents **unknown**, hooks native, mcp native | agents-md config | none; `.codex/config.toml` is runtime config only; `.agents/plugins/marketplace.json` is the Codex-side marketplace descriptor |
| cursor | skills native, agents native, hooks **partial**, mcp native | rules cli-config | `scripts/build-cursor-commands.sh` → `.cursor/commands/*.md` (26, from user-invocable SKILL.md); `.cursor/rules/*.mdc` (13, hand-maintained thin pointers, no generator); `platforms/cursor/hooks.json` (hand-written bundle); `platforms/cursor/templates/cli-config.json` |
| gemini | skills **adapter**, agents **adapter**, hooks **unknown**, mcp native | gemini-md settings | `scripts/build-gemini-extension.sh` → `.gemini/skills/<name>` (29 tracked symlinks, flat mirror because Gemini discovers one level deep) + `.gemini/agents/*.md` (10, tools translated, model omitted); `gemini-extension.json` (contextFileName `.gemini/GEMINI.md`, MCP via `${extensionPath}`); `platforms/gemini/templates/settings.json` |
| opencode | skills native, agents **adapter**, hooks **unsupported**, mcp native | agents-md config | `scripts/build-opencode-agents.sh` → `.opencode/agent/*.md` (10, explicit per-tool deny); `scripts/build-opencode-commands.sh` → `.opencode/commands/*.md` (26); `opencode.json` `skills` paths (enumerates `skills/repo/*` individually to skip `_contract`); `platforms/opencode/templates/opencode.json`; opt-in `skills/toolkit/usage-capture/opencode-plugin.mjs` (not loaded by repo config) |

Claude-only distribution: `scripts/build-claude-dist.sh` (259 l) writes the subset (no tests, docs/engineering, evals, fixtures, platform mirrors, symlinks, CHANGELOG, AGENTS.md, Makefile; ~380–420 files; one image `listing/icon.png`); `scripts/check-claude-dist.sh` (253 l) enforces the directory's rules; `tests/test-claude-dist.sh` plants each finding class.

### 1.8 Capability registry — `core/capabilities/platforms.json` (schema v2, `last_reviewed` 2026-10-02, 21 capability keys, validated by `scripts/check-capability-registry.sh` against `core/capabilities/schema.json`; 90-day `last_verified` budget)

Capability keys (summary in `capability_definitions`): `skills`, `skill_auto_invocation`, `subagents`, `parallel_subagents`, `agent_teams`, `hooks`, `mcp`, `statusline`, `shell`, `git`, `github_cli`, `background_tasks`, `worktree_isolation`, `plugin_marketplace`, `extension_install`, `slash_commands`, `ask_user_question`, `artifacts`, `session_transcripts`, `dynamic_workflows`, `mods`.

Status per supported surface (status vocabulary: native / native-experimental / adapter / emulated / partial / unsupported / unknown; `unknown` is treated as `unsupported`):

| capability | claude_code | claude_desktop | codex | cursor | gemini_cli | opencode |
|---|---|---|---|---|---|---|
| skills | native | native | native | native | adapter | native |
| skill_auto_invocation | native | native | unknown | partial | unknown | unknown |
| subagents | native | unknown | unknown | native | adapter | adapter |
| parallel_subagents | native | unknown | unknown | partial | unsupported | unknown (4.12.2) |
| agent_teams | native-experimental | unknown | unknown | unknown | unknown | unknown |
| hooks | native | unknown | native | partial | unknown | unsupported |
| mcp | native | native | native | native | native | native |
| statusline | native | unsupported | unsupported | unsupported | unsupported | unsupported |
| shell | native | partial | native | native | native | native |
| git | native | partial | native | native | native | native |
| github_cli | native | unknown | native | native | native | native |
| background_tasks | native | unknown | unknown | unknown | unknown | unknown |
| worktree_isolation | native | unknown | emulated | emulated | emulated | emulated |
| plugin_marketplace | native | native | native | native | partial | unsupported |
| extension_install | unsupported | unsupported | unsupported | unsupported | native | unsupported |
| slash_commands | native | native | unsupported | partial | unknown | unknown |
| ask_user_question | native | unknown | unknown | unknown | unknown | unknown |
| artifacts | partial | partial | unsupported | unsupported | unsupported | unsupported |
| session_transcripts | native | unknown | unknown | unknown | unknown | unknown |
| dynamic_workflows | native | unsupported | unsupported | unsupported | unsupported | unsupported |
| mods | native | native | unsupported | unsupported | unsupported | unsupported |

Notable registry notes: Claude Desktop has 12 `unknown` rows (nothing measured on Desktop). Codex `subagents` demoted to `unknown` 2026-09-08 (the prior claim cited a derived mirror of itself). Gemini `parallel_subagents` is `unsupported` by documented recursion protection ("orchestrate-dev's fan-out pattern is structurally impossible on Gemini"). Gemini `plugin_marketplace` is `partial` because the repo lacks the `gemini-cli-extension` GitHub topic. OpenCode `slash_commands` ships 26 commands but discovery is unproven (`unknown`). Codex `mods`: whether Codex ignores the unknown `modules` key in `hooks/hooks.json` is UNVERIFIED. A sibling registry `core/capabilities/platforms.app.json` (last_reviewed 2026-09-08) exists for the `app-gold` scaffold profile.

### 1.9 repo-standards contract — `skills/repo/_contract/` (not a skill)

`standards-contract.json` v1.7.0 with profiles `app-gold` and `plugin-gold` (paths, README badges/headings/banner thresholds, docs tree, CI, exit gates); `feature-equivalence.json` v2.0.0 (model `capability_parity`; repo-contract delta over the registry — which artifact makes a capability reachable; never restates a status); `multi-agent-rubric.md`, `standards-rubric.md`; `references/{feature-equivalence,readme-badges,readme-banner,versioning-policy}.md`; 24 scripts (`assert-contract.sh`, `check-*.sh`, `score-*-gaps.sh`, `standards-inventory.sh`, `inventory-agent-setup.sh`, `plugin-inventory.sh`, `ip-scan.sh`, `sync-contract-scripts.sh`, `detect-contract-profile.sh`, `enable-repo-merge-settings.sh`, `ensure-branch-protection.sh`, `scan-allowlist.txt`); 42 `templates/**/*.tmpl` + `INDEX.md`, `scaffold-requirements{,-plugin}.md`, `legacy-scaffold-templates.md`; three gold fixtures `fixtures/scaffold-gold` (app-gold), `fixtures/scaffold-plugin-gold` (plugin-gold, has `package.json`/`npm run build`, `canonical/` + `dist/{codex,cursor,gemini,opencode}` + `plugins/`), `fixtures/scaffold-claude-plugin-gold` (claude plugin shape). `script-sync.json` v1.2.0 declares 14 groups / **36 copies** (see §6). Rule: "If a path or check is not in `standards-contract.json`, it does not belong in either skill's prose."

### 1.10 Usage-capture / telemetry

Opt-in, local-only (`PRIVACY.md`, `docs/user/usage-capture.md`). `scripts/usage-capture/collector.py` (ThreadingHTTPServer on 127.0.0.1:17431; accepts Claude Code OTLP/HTTP `/v1/logs`, `/v1/traces`, and harness-neutral `/ingest`; one JSONL per Asia/Jerusalem day under `~/.local/share/tamirs-superpowers/usage/`; HMAC-hashed request IDs; bodies only with `--bodies`). `scripts/usage-capture/enable.sh` writes OTEL env keys into `~/.claude/settings.json` and starts the collector (`--disable`, `--dry-run`, `--gateway-kind litellm --endpoint-label`). `hooks/usage-capture-ensure.sh` (SessionStart) starts it only if `TAMIRS_USAGE_CAPTURE=1`. OpenCode path: `skills/toolkit/usage-capture/opencode-plugin.mjs` (observe-only; user adds absolute path to their own `plugin` list; documented as partial). Fixtures `tests/fixtures/usage-capture/otlp-*.json`; `tests/test-usage-capture.sh`. Separate from `session-report` (reads Claude JSONL transcripts after the fact via `analyze-sessions.mjs`). Note: a stray untracked `scripts/usage-capture/__pycache__/` exists in the working tree (not in git).

### 1.11 Eval suite — `evals/` (`claude plugin eval`, Claude Code ≥ 2.1.269)

8 cases, each `prompt.md` + `graders/*.md` (29 grader files): `00-canary-can-write`, `01-new-skill-from-workflow`, `02-research-skill-isolation`, `03-fix-weak-description`, `04-turn-this-into-a-skill`, `05-external-distribution`, `06-neg-find-not-create`, `07-neg-explain-only`. Covers only `skill-creator`; with/without ablation; needs `--allow-tools Write` and `--judge-model sonnet`; ≈$0.50/run, ≈$24 for `--runs 3`. Not run in CI. Calibrated 2026-09-22 findings (`evals/README.md`): `fix-weak-description` Δ −0.25 (real regression), `research-skill-isolation` fails `context: fork` in both arms, `neg-explain-only` was a grader bug (fixed). Different harness from per-skill `evals/evals.json`.

### 1.12 Tests — `tests/` (all bash, hermetic, no network)

40 top-level `tests/test-*.sh` entrypoints (run by `make test-hooks`), 9 `tests/orchestration/scenario-*.sh` (via `test-orchestration.sh`, fake-agent + recording `gh` shim; proves one objective = one PR, no worker PR), 5 `tests/contract/{claude,codex,cursor,gemini,opencode}.sh` + `run.sh` (schema half always; CLI half skips when absent; "101 assertions"), 5 `tests/hooks/test-apply-patch-*.sh` (Codex `apply_patch` payloads), `tests/lib/{harness,portable,fake-agent,fake-gh}.sh` + `skill-meta.py`, ~190 GitHub API fixture files under `tests/fixtures/github/` (31 scenarios). ≈1,737 `ok/bad/judge/has/skip` assertion calls across suites (grep count, approximate). Notable: `test-concurrency-guard.sh` (46 cases), `test-claude-dist.sh` (29 planted probes), `test-hook-stdin.sh` (every hook returns promptly on any stdin), `test-static.sh` (positive controls mandatory for every scanner), `test-docs.sh` (docs tell the truth; `--strict` not on in CI). macOS bash 3.2 portability enforced (`tests/lib/portable.sh`). Open: `project-statusline-tmpdir-ci-flake` memory — unexplained `mktemp` dir vanishing in CI (4 occurrences 2026-09-02).

### 1.13 Makefile targets and CI jobs

`Makefile` (15.5 KB). `make validate` = `lint test-hooks test-contract test-repo-contract check-manifest-versions check-platform-equivalence check-marketplace-schema check-doc-claims check-version-truth check-capability-registry validate-roles check-gemini-adapter gemini-extension-check check-github-policy check-branch-literals check-action-pinning check-manifest-declares check-platform-version-pins check-claude-dist` + JSON parse + `validate-skill-frontmatter.py` + orphan-hook check. Other targets: `help setup setup-plan capture github-policy{,-plan} check-github-policy install update uninstall test-hooks test-contract check-agent-drift check-feature-equivalence check-platform-targets check-platform-version-pins check-marketplace-schema check-doc-claims check-branch-literals check-manifest-declares check-action-pinning doctor check-version-truth check-capability-registry validate-roles check-gemini-adapter gemini-extension{,-check} platform-targets-{sync,assert,cochange} opencode-agents{,-check} opencode-commands{,-check} cursor-commands{,-check} check-opencode-permission-keys agent:check agent-polish-gate assert-contract repo-standards-gate check-platform-equivalence lint test-repo-contract check-manifest-versions plugin-validate test-mods typecheck-mods build-claude-dist check-claude-dist test`. `make validate` deliberately does not require the `claude` CLI (`test-mods`/`plugin-validate` do). Duration: CI's `full-validate` measured **295 s** vs `test-hooks` alone 249 s (`.github/workflows/ci.yml` comment); `.claude/memory/feedback-background-task-exit-codes.md`: ">2min, must be backgrounded".

CI `.github/workflows/ci.yml` (PR + push to main/master, all `ubuntu-latest`, actions SHA-pinned, `check-action-pinning.sh`): jobs `lint` (shellcheck), `full-validate` (`make validate`, needs node for plugin-gold fixture), `orchestration-tests`, `skill-contract`, `static-and-docs`, `platform-contract` (matrix gemini, opencode), `validate-json`, `validate-skills`, `secret-scan`, `plugin-validate` (`npm i -g @anthropic-ai/claude-code`; `claude plugin validate .` + `make test-mods`), `claude-dist` (build + check), `contract-test` (gold fixtures), `contract-assert` (this repo vs its contract), `manifest-version-alignment`, `platform-targets` (co-change), `hol-scanner` (`pipx run plugin-scanner lint/verify`). `platform-currency.yml`: nightly 06:00 UTC `scripts/probe-platform-versions.sh` → opens a "Platform version drift detected" issue on drift (currently one per day, #270–#283).

### 1.14 Release pipeline

`release.yml` is `workflow_dispatch` only (input `version`): validates semver, checks tag absent, bumps the three `plugin.json` manifests with `jq`, commits, runs `check-manifest-version-alignment.sh --manifests-only`, tags `v<version>`, creates a GitHub Release; then job `claude-dist` checks out the tag, builds with `build-claude-dist.sh`, checks with `check-claude-dist.sh`, asserts dist version, writes the tree via a scratch index (`git write-tree`/`commit-tree`, parent = previous `claude` tag), tags `v<version>-claude` (immutable) and force-moves tag `claude` (what Anthropic's directory tracks; uses `RELEASE_PUSH_TOKEN` if set). Note: release.yml bumps only the three `plugin.json`s, whereas the documented path is `plugin-version.json` + `check-version-truth.sh --sync` (7 consumers incl. `gemini-extension.json`, README badge, `platform-targets.json.reviewed_by_skill`, CHANGELOG heading). Marketplace: `Tamircohen28/tamirs-marketplace` (separate repo) + in-repo `.claude-plugin/marketplace.json` (standalone) + `.agents/plugins/marketplace.json` (Codex). Version pins: `.claude-code-version` (2.1.287), `.codex-version` (0.160.1), `.cursor-version` (3.23.12 + feature 3.11), checked by `scripts/check-platform-version-pins.sh` (now in `make validate`).

### 1.15 Docs tree

`docs/README.md`, `docs/CONTRIBUTING.md`, `docs/CHANGELOG.md`; `docs/user/` (22 files: install guides for 6 surfaces, `platform-differences.md`, `platform-setup.md`, `setup.md`, `capture.md`, `usage-capture.md`, `orchestration.md`, `cross-platform-workflow.md`, `agents.md`, `skills.md`, `agent-kit.md`, `github-policy.md`, `phone-notifications.md`, `configuration.md`, `reference.md`, `troubleshooting.md`, `quick-start.md`, `getting-started.md`, `concepts.md`); `docs/engineering/` (`README.md`, `statusline.md`, `architecture/` 11 docs, `build-and-release/` 7 incl. `platform-targets.{json,md}`, `directory-distribution.md`, `testing-matrix.md`, `ci-workflow.md`, `versioning.md`, `development-workflow.md`; `decisions/` 2 ADRs; `refactor/` Phase-0 inventory); `docs/agent-guidelines/` (3); `docs/changelog/CHANGELOG-archive-{1,2,3}.md`. Root: `README.md`, `AGENTS.md`, `CLAUDE.md` (51 KB, mostly host-version notes), `CHANGELOG.md` (152 KB), `PRIVACY.md`, `SECURITY.md`, `CODEOWNERS`, `LICENSE`. `rules/dev/*.md` (8 canonical rules) + `rules/README.md` adapter map. `.claude/memory/` (17 files, mirrored to the transcript dir by hand).

---

## 2. Architecture summary (`docs/engineering/architecture/*.md`)

- **overview.md** — Two rules: one canonical source with thin adapters (per-platform files are references or *generated* artifacts whose drift fails CI), and capability-based degradation (nothing assumes subagents/hooks/statusline). Six subsystems: capability registry, roles+agents, skills (three-tier frontmatter), orchestration (objective→tasks→one PR, file state under `.dev-files/objectives/`), adapters, machine configuration (render out via `scripts/setup.sh`, capture back via `scripts/capture-config.sh`). Claims hooks "run as shipped only on Claude Code" and every hook-enforced rule also exists as a skill step and a CI check.
- **adapter-contract.md** — An adapter = one registry entry, one manifest/config, one install doc, one validation command wired into CI, one version consumer, and generation only where the format genuinely differs. Prohibited: copying skills/rules, rewriting agents, provider conditionals inside skills, a second source of truth, a new runtime dependency, destructive migration. A regressed surface is never flipped to `unverified`.
- **capability-model.md** — `schema.json` + `platforms.json`; platform → surfaces; `support: supported|unverified` (unverified surfaces carry **no** capability rows, only `unverified_reason`); status vocabulary and the rule that `unknown` is treated exactly as `unsupported`; skills declare `metadata.tamirs.capabilities.required/optional`; `compatibility` is derived, not written; `platform-targets.json` `capabilities`/`capability_gaps` are a derived mirror.
- **hooks-classification.md** — Each hook in one of six categories (core-safety-invariant, worktree-lifecycle, claude-convenience, contributor-only, optional-notification, platform-specific). Honest support statement: safety invariants are "enforced on Claude Code and Cursor; documented and CI-checked everywhere else". Recommends a tiered packaging (safety on / worktree opt-out / convenience opt-out / notification off / contributor off) that is **not implemented** — all hooks ship wholesale. Documents objective-model changes to four hooks, dependency-install throttles, stale-worktree retirement, and that mods are additive.
- **mods.md** — The mod does only what bash cannot (draw, react to pushed `session.measure`, act before a turn dies, answer a command with no model turn). Per-feature table with hooks and fallbacks (quoted in §5). Directory rules it meets (`MOD_CAPABILITY_USE_NOT_PLAIN`, no credential/process/network, `MOD_DATA_LEAVES_BY_PROMPT`). Runs on Claude Code CLI + Desktop Code tab; hooks run but nothing draws under `-p`/VS Code/cloud; dropped under `allowManagedModsOnly`/`--safe-mode`. Codex trade-off: same `hooks/hooks.json` carries `modules`; unverified whether Codex rejects it. Validation = `claude plugin validate .claude-plugin/plugin.json` + `claude plugin test .` (CI) + `make typecheck-mods` (not CI). API "marked early access and moves between releases".
- **orchestration-state-machine.md** — Objective states `draft→active→integrating→reviewing→delivering→completed` (+blocked/abandoned); task states `pending→ready→running→completed|failed|blocked|cancelled` (one retry, then re-plan); handoff `completed|partial|failed|blocked|cancelled` with `validation[]` only for commands that ran. Disjoint write `scope[]` enforced by `objective-state.sh validate`. Provider is metadata; resume is a read of files; "no handoff ⇒ failed".
- **branch-worktree-model.md** — `objective/<slug>` integration branch + `worker/<slug>/NNN`; worktrees at `.agent-worktrees/<objective>/{integration,task-NNN}` or `~/.agent-worktrees/<repo>/...`; legacy `.claude/.worktrees` etc. recognised, never orphaned, opt-in `--migrate`. Hook automation is `native` on Claude Code, `emulated` elsewhere, `unknown` on Desktop.
- **validation-tiers.md** — Tier 0 edit-time, 1 worker (scoped), 2 integration (`make validate`), 3 CI/delivery. A validation step with an unstated tier is a bug; skipped tiers are reported as skipped with a reason.
- Also present: `skill-schema.md` (three-tier frontmatter; Tier 3 = Claude-only fields validated when present), `adding-a-platform.md`, `claude-machine-config.md`, `repo-shape-conditionality.md` (backlog of hardcoded-assumption findings with STATUS column), `../statusline.md`.

---

## 3. Known gaps and debt (each with source)

**From `docs/engineering/refactor/file-inventory.md` (frozen Phase-0, 2026-08-19, baseline `c9399aa`, 451 files; explicitly "must not be edited to track the new tree")** — status today in brackets where verifiable:
1. 190/451 files (42%) had no validator; 47 skill-local scripts unlinted [closed: `make lint` now shellchecks every tracked `.sh`; `Makefile` comment cites §2.1].
2. `hooks/lib/*.sh` unlinted [closed, same].
3. `.codex-version`/`.cursor-version` read by no script [closed: `scripts/check-platform-version-pins.sh`, in `make validate`].
4. `.cursor/rules/*.mdc` unverified against `rules/dev/`; asymmetric mapping (4 Cursor-only rules, 2 canonical rules missing) [partially: `rules/README.md` adapter map now lists 13 `.mdc` incl. `gh-cli-preference`/`user-facing-script-standards`; still **no generator / drift check** for `.cursor/rules/`].
5. Evals "decorative" — never executed in CI [still true for per-skill `evals/*.json`; `evals/` plugin suite also not in CI].
6. Contract-script duplication 4–5-way [closed by `script-sync.json` + `sync-contract-scripts.sh --check`, but copies still exist: 36].
7. `${CLAUDE_PLUGIN_ROOT}` load-bearing in `.mcp.json` shared by Cursor/Codex manifests [still the case; Gemini/OpenCode declare separately/not at all].
8. Three manifests + `opencode.json` restate the skill-domain list and skill count [still: `check-doc-claims.sh` guards the count; lists are hand-synced].
9. `.claude/rules/skill-frontmatter.md` ≈ `.cursor/rules/skill-frontmatter.mdc` maintained separately [both still exist].
10. CI ≠ `make validate` [closed: `full-validate` job runs `make validate`].

**From `CLAUDE.md`:**
- "no script parses `.claude-code-version` yet… closing it… is a reasonable follow-up" (§Claude Code CLI baseline) — now stale: `check-platform-version-pins.sh` exists and is wired; the prose was not updated.
- `PreModelSwitch`/`PostModelSwitch` hook events "not wired… noted for Tamir's judgment".
- `--accept-command <sha256>` (2.1.271) "not adopted this cycle, recorded".
- `/plugin install <plugin> --marketplace <source>` one-step form "left as a Future opportunity" (CLAUDE.md §Marketplace cache); PR #271 (unmerged) adopts it in docs.
- `CLAUDE_CODE_MCP_STARTUP_WAIT_MS`, `CLAUDE_CODE_MAX_MCP_DESCRIPTION_LENGTH` — documented knobs, not set.
- `SubagentStart` hook not wired; `omitClaudeMd` reviewed-and-declined.
- Project memory must be hand-copied to the transcript dir (`CLAUDE_CODE_PROJECT_DIR_NAME` pin).

**From `docs/engineering/architecture/hooks-classification.md`:** recommended tiered hook packaging (safety/worktree/convenience/notification/contributor) "Not a change made here" — all 28 hooks ship to every user; `plugin-reload-reminder.sh` and `validate-report-links.sh` are "contributor-only… should not be on by default for users" yet are wired.

**From `docs/engineering/architecture/mods.md`:** `make typecheck-mods` is not a CI gate (no `claude-code.d.ts` on a runner); mods API is early access; Codex `modules`-key tolerance unverified; stale option count ("three… fields" lists two).

**From `docs/user/install/cursor.md` (hook-events table):** `subagentStart`/`subagentStop` "best available improvement… Not yet wired" (de-dup design needed); `sessionStart`/`sessionEnd`/`stop`/`preCompact` have Claude peers and are "a genuine gap — a Cursor user gets no session lifecycle today"; `beforeSubmitPrompt` port is "real work"; `docker-guard.py` is Claude-only (writes Claude-shaped JSON directly); skill invocation inside Cursor "still unverified".

**From `platforms/gemini/adapter.yaml` / registry:** Gemini ships no hooks; 3 events match by name (SessionStart/End/Notification, untested), 4 translate via `gemini hooks migrate --from-claude`, 3 have no counterpart; extension installed from a bare git URL logs an `Invalid tool name` error per canonical `agents/*.md` on every invocation (no subdirectory flag); repo lacks `gemini-cli-extension` topic (not in the auto-indexed gallery).

**From `core/capabilities/platforms.json`:** OpenCode `slash_commands` discovery unproven (API returned empty); OpenCode `parallel_subagents` conflicting evidence, no live v2 run; Codex `subagents`/`slash_commands`/`skill_auto_invocation` unknown; Claude Desktop 12 rows `unknown`; rows carry a 90-day `last_verified` budget that turned `make validate` red on master once (4.12.2).

**From `evals/README.md`:** `fix-weak-description` Δ −0.25 real regression; `research-skill-isolation` `context: fork` gap in both arms (skill-creator's `references/frontmatter-template.md` does not steer toward isolation fields).

**From `tests/README.md` / `tests/test-skill-contract.sh`:** `--strict` (eval-coverage gaps, link rot) is not on in CI; "Most do not yet [ship fallback evals] — that gap predates…".

**From `docs/engineering/architecture/repo-shape-conditionality.md`:** "the unfixed rows are a real backlog" (status table; e.g. line 244 "class of error, not yet caught").

**From `docs/user/agent-kit.md`:** "Full Handlebars pipeline (all rules → all adapters) — Follow-up"; "`npx @org/agent-kit install --target .` — Follow-up"; "Migrating flat plugins (e.g. tamirs-superpowers) to agent-kit — Optional follow-up".

**From `.claude/memory/`:** `project-statusline-tmpdir-ci-flake.md` (open, unexplained); `project-directory-submission-holds.md` (structural directory holds that stay: `UNREAD_ASSET_REFERENCED` ×14 while the icon ships, `COMMAND_NAMES_MOD_FILE` in `_contract/scripts`, `MCP_FORWARDS_CREDENTIAL_ENV` on `notify-pushover.sh`, `COMMAND_SCRIPT_NOT_FOLLOWED` here-docs, `UNKNOWN_KEY` `types`); `feedback-background-task-exit-codes.md` (`make validate` >2 min).

**From `CHANGELOG.md` [Unreleased] + last releases:** `[Unreleased]` is **empty**. 4.12.2 (2026-10-16): OpenCode `parallel_subagents` → unknown; field-notebook-ui wording. 4.12.1 (10-06): pr-dev CI watch fails closed, wait for reviewer bots; Codex 0.160.1 / OpenCode 2.0.24 review. 4.12.0 (10-03): `scripts/agent-health.sh`, iBrain required contexts, PR-driving discipline, Cursor 3.23.12. 4.11.11→4.11.1 (10-03/04): twelve Anthropic plugin-directory passes (credential-pairing scanner readings, inline shell spans removed from skills, `gh auth` wording removed, icon back to `listing/`, leaner dist). 4.11.0: Claude-only distribution + tag `claude`, `userConfig`-only credentials, scoped `allowed-tools`, mod moved to `mod/`, drift #247. 4.10.0: the mod (2.1.287), `make test-mods`, statusline `</dev/null` bug fixed, 2.1.287 baseline. 4.9.1: 2.1.281, quoted `${CLAUDE_PLUGIN_ROOT}`. PR #271 (unmerged) notes the `[Unreleased]` entry for the 2.1.293–2.1.300 cycles "was again drafted but not pushed" — a pending follow-up.

**Open issues/PRs (GitHub, 2026-10-17):** #283/#281/#280/#279/#278/#275/#274/#273/#272/#270 daily "Platform version drift detected" (Codex 0.160.1→**0.163.0**, Gemini 0.62.0→**0.64.0**, OpenCode 2.0.24→**2.0.30**; Claude Code and Cursor have no automated source). PR #271 `claude-code-update` (Claude Code **2.1.300**: fixes `turn.start` zeroing `writesThisTurn` for subagent turns since 2.1.299; `.catch` on 4 gating hooks; 22 mod tests; one-step install docs; future: `onFailure: "block"` for the four safety guards, `prompt.change`, `$.ui.view`, `virtualText`, `$.ui.selection`, `isDeferred`). Draft PR #277 `cursor-update` (Cursor desktop **3.24.12**: id-keyed `cursor-agent-tools-guard.sh` via `tool_use_id`/`parent_tool_call_id`; future: wire `subagentStart`/`subagentStop`, live Cursor run, `transcript_path`). PR #276 dependabot setup-node 7.1.0. Remote branch `origin/codex-update` exists with no open PR.

---

## 4. Platform parity matrix

Sources: manifests at root, `core/capabilities/platforms.json`, `platforms/*/adapter.yaml`, `docs/user/install/*.md`, `docs/engineering/build-and-release/platform-targets.json`.

| Platform (surface) | Skills | Agents | Hooks | MCP | Commands | Mod / statusline | Install & validation | Explicitly unsupported / unverified |
|---|---|---|---|---|---|---|---|---|
| **Claude Code** (`claude_code`) | 29 via `.claude-plugin/plugin.json` `skills[]` (7 domain dirs) | 10 `agents/*.md` (default discovery) | all 27+1 in `hooks/hooks.json` | `.mcp.json` (`github`) | skills double as `/name`; mod adds `/objective` | mod (`modules` key) + `settings.statusLine` + `output-styles/evidence.md` | marketplace `tamirs-marketplace` or in-repo `marketplace.json`; `claude plugin validate`, `test`, `eval` | `extension_install`; artifacts partial; `agent_teams` experimental |
| **Claude Desktop** (`claude_desktop`) | same plugin | same | **unknown** (never verified to fire) | native | native | mod draws usage line (no statusline) | same marketplace; manual checklist (`docs/user/install/claude-desktop.md`) | subagents, parallel_subagents, hooks, github_cli, background_tasks, worktree_isolation, ask_user_question, session_transcripts all `unknown`; shell/git partial; statusline, dynamic_workflows unsupported |
| **Codex CLI** (`codex`) | 29 via `.codex-plugin/plugin.json` `skills[]` | **none routed** (`unknown`; manifest spec has no agents field; openai/codex#28491) | `hooks/hooks.json` natively (no WorktreeCreate/Remove, DirectoryAdded, Notification; `apply_patch` mapped by `lib/platform-tools.sh`; `docker-guard.py` needs python3) | `.mcp.json` via manifest | `unsupported` (no plugin command mechanism; `interface.defaultPrompt` ×6 instead) | none (`mods` unsupported; `modules` key tolerance unverified) | marketplace via `.agents/plugins/marketplace.json`; `check-manifest-declares.sh … skills mcpServers hooks` | skill_auto_invocation, subagents, parallel_subagents, agent_teams, background_tasks, ask_user_question, session_transcripts `unknown`; statusline, extension_install, slash_commands, artifacts, dynamic_workflows, mods unsupported; **codex_ide** surface unverified; `validated_against` 0.156.0 vs latest 0.163.0 |
| **Cursor IDE** (`cursor`) | 29 via `.cursor-plugin/plugin.json` `skills[]` | `agents/` directly (`agents` field); `tools:` enforced only by `cursor-agent-tools-guard.sh` | `platforms/cursor/hooks.json` → 3 events (preToolUse ×5 guards, beforeShellExecution, postToolUse); `partial` | `.mcp.json` via manifest | 26 generated `.cursor/commands/*.md` (`partial`) | none | marketplace/team import; `check-manifest-declares.sh … skills mcpServers rules hooks commands agents` | no session lifecycle hooks, no `docker-guard`; skill auto-invocation partial (name it or pin a Custom Mode); parallel_subagents partial (cloud only); agent_teams, background_tasks, ask_user_question, session_transcripts unknown; statusline, extension_install, artifacts, dynamic_workflows, mods unsupported; **cursor_cli** unverified; `validated_against` 3.22.7, `latest_known` 3.23.12 (PR #277 → 3.24.12) |
| **Gemini CLI** (`gemini_cli`) | **adapter**: 29 symlinks `.gemini/skills/` (flat mirror) — not from `gemini-extension.json` | **adapter**: `.gemini/agents/*.md` generated | **none shipped** (`unknown`) | `gemini-extension.json` (`${extensionPath}/scripts/github-mcp.sh`, env exported by user) | `unknown` (TOML commands possible, none shipped) | none | `gemini extensions install <url>` / `gemini skills install --path .gemini/skills`; `scripts/check-gemini-adapter.sh`, `make gemini-extension-check` | parallel_subagents **unsupported** (recursion protection → orchestrate-dev fan-out impossible); plugin_marketplace partial (missing topic); skill_auto_invocation, agent_teams, hooks, background_tasks, slash_commands, ask_user_question, session_transcripts unknown; statusline, artifacts, dynamic_workflows, mods unsupported; canonical `agents/` logs load errors; **gemini_code_assist** unverified; `validated_against` 0.60.0, latest 0.62.0 (drift to 0.64.0) |
| **OpenCode CLI** (`opencode`) | 29 in place via `opencode.json` `skills` paths (recursive; symlinks not followed) | **adapter**: `.opencode/agent/*.md` generated (explicit denies) | **unsupported** (JS plugin API only; opt-in `opencode-plugin.mjs` for usage capture only) | not declared | 26 generated `.opencode/commands/*.md` (`unknown` — discovery unproven) | none | path install (absolute `skills.paths`); `opencode debug skill` (removed in v2), `scripts/check-opencode-permission-keys.sh`, `make opencode-agents-check` | plugin_marketplace, extension_install, hooks, statusline, artifacts, dynamic_workflows, mods unsupported; skill_auto_invocation, parallel_subagents, agent_teams, background_tasks, slash_commands, ask_user_question, session_transcripts unknown; **opencode_desktop** unverified; `supported_min` unknown; `validated_against` 2.0.14, latest 2.0.24 (drift to 2.0.30) |

Version pins (`platform-targets.json`, `last_reviewed` 2026-10-02): claude_code min 2.0.0 / validated 2.1.287 / reviewed 2.1.287 / latest 2.1.287 (issue #271 says 2.1.300 live); codex min 0.40.0 / 0.156.0 / 0.160.1 / 0.160.1; cursor min 3.22.7 / 3.22.7 / 3.23.12 / 3.23.12 (+ `.cursor-version` feature 3.11, changelog 2026-09-23, CLI changelog 2026-08-26, frontier_model grok-4.6); gemini_cli min 0.55.1 / 0.60.0 / 0.62.0 / 0.62.0; opencode min unknown / 2.0.14 / 2.0.24 / 2.0.24. Open drift per issue #283 (2026-10-16): **Codex 0.163.0, Gemini 0.64.0, OpenCode 2.0.30**. `validated_against` lags everywhere because no live non-Claude binary exists in the nightly review environment (`verification_method` strings).

---

## 5. Mod-specific

**Header of `mod/register.tsx` (lines 1–56), quoted:**

```
// tamirs-superpowers mod — Claude Code >= 2.1.287 function hooks.
//
// WHAT THIS IS, AND WHAT IT IS NOT
//   A mod runs IN-PROCESS on Claude Code and the Claude Desktop Code tab. It can
//   draw (a pane, the band above the prompt, the spinner), react to state the
//   host PUSHES (`session.measure`), and act before a turn dies. The bash hooks
//   in the hook manifest can do none of those three things.
//
//   It is ADDITIVE. Every guard, every worktree hook and every reminder in
//   the shell hook scripts stay canonical, because those run on Codex and (via
//   platforms/cursor/hooks.json) Cursor too, and a mod never will. Nothing here
//   denies a tool call, creates a worktree, or replaces a bash hook. Where a
//   feature below overlaps one (rate-limit-handoff.sh, check-done.sh,
//   precompact-snapshot.sh, skill-suggest.sh, notify-pushover.sh), the bash hook
//   is the fallback that still fires when this module cannot load — an org with
//   `allowManagedModsOnly`, `--safe-mode`, a VS Code chat panel.
//
// WHAT IT DOES
//   1. Objective pane + /objective — the orchestration state orchestrate-dev
//      and worker-dev keep in .dev-files/objectives/<id>/ (objective.json,
//      tasks/*.json, handoffs/*.json) drawn live; `/objective` answers at once,
//      with no model turn, even mid-turn (`immediate`). Spinner suffix counts
//      workers in flight; a task-notification row is drawn compact.
//   2. Rate-limit band — `session.measure` pushes rate-limit windows after every
//      turn. At `rate_limit_warn_percent` the band above the prompt shows a
//      a reminder to type /switch-dev handoff; the mod submits no prompt itself.
//      rate-limit-handoff.sh fires AFTER the turn died; this fires BEFORE.
//   3. Usage line on Desktop — the figures scripts/statusline.sh draws on the
//      CLI, where Desktop has no status line to draw into.
//   4. (removed in 4.11.1) A Pushover post on long or failed turns lived here
//      as a network call. The Notification bash hook covers phone alerts, and a
//      mod that both reads the conversation and sends it out is held by the
//      directory for review, so the mod now makes no network call at all.
//   5. Semantic skill suggestion — opt-in (`semantic_skill_suggest`): a small
//      model classifies a long prompt against the bundled skill names and the
//      match is attached as context to the prompt. skill-suggest.sh's keyword
//      matching keeps running regardless.
//   6. Definition-of-done line under an answer that wrote files (turn.complete),
//      a working-state snapshot folded into compaction instructions
//      (session.compact), and the repo's Co-Authored-By trailer policy enforced
//      on the commit attribution text when the repo's CLAUDE.md declares one.
//
// HOW IT IS WRITTEN
//   Every call on `$` is written out in full inside the hook that makes it:
//   `$` is never handed to a helper. The directory's scanner reads a mod the
//   same way `claude plugin validate` does, and a capability it cannot see at
//   the call site is one it cannot vouch for. The helpers below are pure: they
//   take text or data and give back text or data. No subprocess runs and no
//   network call is made: the main working tree comes from `$.session.repo()`
//   and the branch from reading `.git/HEAD`, both plain `$.fs`/`$.session` calls.
//   What leaves the session is one thing, on one press: the handoff button
//   submits a fixed prompt naming the rate-limit window (see the band below).
//
// BUDGET
//   Every hook has 10 s of its own time per dispatch; `next` and `$` calls do
//   not count. Nothing here sleeps. The objective re-read is bounded by the
//   number of tasks (a handful of small JSON files).
```
(Note: the "handoff button submits a fixed prompt" sentence in HOW IT IS WRITTEN is stale — 4.11.6 removed the button and the `prompt.submit` call; the band only says "type /switch-dev handoff".)

**`docs/engineering/architecture/mods.md` "What it does" table (the per-feature fallback table), quoted:**

| # | Feature | Hooks | Overlaps / fallback |
|---|---|---|---|
| 1 | **Objective pane + `/objective`** — the orchestration state `orchestrate-dev`/`worker-dev` keep in `.dev-files/objectives/<id>/` (`objective.json`, `tasks/*.json`, `handoffs/*.json`) drawn live, re-read every 5 s; `/objective` answers at once (`immediate`); the spinner counts workers in flight; a task-notification row is drawn compact | `session.start`, `command.run`, `ui.render{Pane}`, `agent.spawn`, `turn.complete`, `ui.render{Spinner}`, `ui.render{UserMessage}` | New capability. `objective-state.sh show` from a shell is the fallback |
| 2 | **Rate-limit band** — at `rate_limit_warn_percent` (default 85) of any window a band tells the user to type `/switch-dev handoff` (the mod submits no prompt; a `prompt.submit` call beside its file reads is a `MOD_DATA_LEAVES_BY_PROMPT` hold) and shows `[ Dismiss ]`; one toast per 5-point crossing | `session.measure`, `ui.render{AbovePrompt}` | `hooks/rate-limit-handoff.sh` (`StopFailure`, after the fact). Both stay |
| 3 | **Usage line on Desktop** — `ctx 12% · 5h 40% (resets 2h10m) · 7d 31% · $1.50`, Desktop only | `session.measure`, `ui.render{AbovePrompt}` | `scripts/statusline.sh` on the CLI (Desktop has no status line). The mod never draws it on the terminal |
| 4 | *(removed in 4.11.1)* A Pushover post on long or failed turns lived here as the mod's one network call. The plugin directory holds a mod that both reads the conversation and sends data out, and the `Notification` bash hook already covers phone alerts, so the mod now makes no network call at all | — | `scripts/notify-pushover.sh` on the `Notification` event is the one Pushover path |
| 5 | **Semantic skill suggestion** — opt-in `semantic_skill_suggest`: a prompt of 12+ words is classified by the engine's small model against the bundled skill names; a match is attached as context once per skill per load | `prompt.submit`, `$.model.classify` | `hooks/skill-suggest.sh` keyword matching stays on either way |
| 6 | **Definition-of-done line** under an answer whose turn wrote files | `turn.start`, `tool.call`, `turn.complete` | `hooks/check-done.sh` (`Stop`, stderr) |
| 6 | **Compaction snapshot** — branch, uncommitted files and the objective folded into the summariser's instructions | `session.compact`, `$.process.run` | `hooks/precompact-snapshot.sh` (writes a file; `PreCompact` has no context channel) |
| 6 | **Commit trailer policy** — when the repo's `CLAUDE.md` declares a `Co-Authored-By: Claude <…>` line and the attribution text lacks one, it is appended | `attribution.text{commit}` | The CLAUDE.md prose. Only enforced where the repo declares it; a repo without the line gets nothing |

(Doc drift: row 6 "Compaction snapshot" still names `$.process.run` and "uncommitted files"; the 4.11.0 rewrite removed `$.process` entirely and the snapshot no longer lists uncommitted files — the source reads `.git/HEAD` only.)

**Bash hooks the mod duplicates (both stay, bash is fallback):** `hooks/rate-limit-handoff.sh` (StopFailure, after) ↔ feature 2 (before); `hooks/check-done.sh` (Stop) ↔ feature 6 DoD line; `hooks/precompact-snapshot.sh` (PreCompact, file) ↔ feature 6 compaction snapshot (instructions); `hooks/skill-suggest.sh` (UserPromptSubmit keyword) ↔ feature 5 (semantic, opt-in); `scripts/statusline.sh` (CLI) ↔ feature 3 (Desktop); `scripts/notify-pushover.sh` ↔ removed feature 4; `CLAUDE.md` commit-trailer prose ↔ attribution hook; `objective-state.sh show` ↔ feature 1.

**Features that exist only in bash (not in the mod, deliberately per mods.md):** every guard — `enforce-worktree-edits.sh`, `guard-sensitive-files.sh`, `protect-other-branches.sh`, `docker-guard.py`, `goal-condition-lint.sh`, `skill-creator-guard.sh`, `cursor-agent-tools-guard.sh`; all worktree lifecycle — `capture-task-slug.sh`, `session-init.sh`, `session-end.sh`, `worktree-create.sh`, `worktree-remove.sh`, `directory-added.sh`; claims — `release-agent-claims.sh`; `show-changelog.sh` (reviewed, not ported); `handoff-reminder.sh`, `subagent-handoff-check.sh`, `goal-compact-reminder.sh`, `scope-decompose-reminder.sh`, `plugin-reload-reminder.sh`, `validate-report-links.sh`, `notify.sh`, `ensure-exit.sh`, `usage-capture-ensure.sh`.

**What the mod does not touch today:** tool denial/permission (`agent.spawn` only counts, `tool.call` only counts writes), any `$.process`/`$.http`/`$.fs.write`, `$.tool.register`, `$.session.append`/`usage()`, `prompt.change`, `$.ui.view`, `$.ui.selection`, `virtualText`, `Text.dir`, `isDeferred`, worktrees, git commands, MCP, Pushover, the skill eval harness.

---

## 6. Quality signals

- **Files:** 1,136 tracked (`git ls-files`). By extension: md 427, json 282, sh 226, tmpl 42, txt 33, py 19, mdc 16, yml 11, conf 10, yaml 5, png 4, mjs 4, html 3, tsx 2, ts 1, svg 2, toml 1, csv 1. 29 tracked symlinks (all `.gemini/skills/`).
- **Lines by language (tracked):** bash 47,362 (226 files; hooks tree 6,135; `scripts/github-policy.sh` 1,454; `hooks/lib/write-targets.py` is Python 968); Python 5,962 (19 files); TSX 899 (2 files: register 510 + tests 389) + TS 58; mjs 1,322 (4); Markdown 37,825 (427); JSON 17,566 (282); YAML 1,008.
- **Prose weight:** `CLAUDE.md` 51.8 KB, almost entirely per-host-release notes (2.1.234→2.1.287) inline in bullet paragraphs; `CHANGELOG.md` 152 KB (+3 archives); `platform-targets.json` 56.6 KB with multi-KB `verification_method` strings per target; `core/capabilities/platforms.json` 75.6 KB with narrative `notes` per cell. These three are the heaviest hand-maintained surfaces, and `check-doc-claims.sh`/`check-platform-targets.sh` only check counts/versions, not the narrative.
- **Tests:** 40 `tests/test-*.sh` + 9 orchestration scenarios + 5 contract suites + 5 apply-patch suites; ≈1,737 assertion calls; 21 mod tests; 8 plugin-eval cases (not CI); 29×2 per-skill eval JSON files (not executed in CI). `make validate` ≈ 295 s in CI (`ci.yml`), must be backgrounded locally (memory note).
- **Duplication / hand-synced copies:**
  - `skills/repo/_contract/script-sync.json`: 14 groups, **36 copies** regenerated/asserted by `sync-contract-scripts.sh --check` (run first by `assert-contract.sh`). Groups: `check-feature-equivalence` (5), `check-manifest-declares` (5), `check-platform-targets` (5), `check-action-pinning` (5), `check-agent-drift` (4; root `scripts/check-agent-drift.sh` is a *different* script sharing the name), `check-manifest-version-alignment` (1), `plugin-build-mjs` (1), `plugin-validate-mjs` (1), `capability-registry-schema-template` (1, reverse), `capability-registry-platforms-template` (1, reverse), `capability-registry-platforms-app-gold-template` (1, reverse), `capability-registry-schema` (3), `capability-registry-platforms` (2), `capability-registry-platforms-app-gold` (1); plus 3 derived `platform-targets.json` capability mirrors under fixtures.
  - Generated-and-committed (drift-checked): `.opencode/agent/` (10), `.opencode/commands/` (26), `.cursor/commands/` (26), `.gemini/skills/` (29 symlinks), `.gemini/agents/` (10), `platform-targets.json` `capabilities`/`capability_gaps` mirror, fixture registries.
  - Hand-synced with only partial checks: three `plugin.json` manifests + `marketplace.json` ×2 + `opencode.json` + `gemini-extension.json` (version by `check-version-truth.sh`; skill count by `check-doc-claims.sh`; `skills[]`/description/keywords free to diverge); `.cursor/rules/*.mdc` (13, no generator); `.claude/rules/skill-frontmatter.md` vs `.cursor/rules/skill-frontmatter.mdc`; `.claude/memory/` ↔ transcript dir; `core/capabilities/platforms.json` ↔ `platforms.app.json`; `CLAUDE.md` release notes ↔ `platform-targets.json.verification_method` ↔ `CHANGELOG.md` ↔ registry `notes` (same facts restated three to four times per host release); root pins `.claude-code-version`/`.codex-version`/`.cursor-version` (checked); `CHANGELOG.md` vs `docs/CHANGELOG.md`.
  - `release.yml` bumps only 3 manifests, not via `plugin-version.json --sync` (consumers: 7).
- **Heaviest-to-maintain areas (by evidence above):** (1) per-release prose in `CLAUDE.md`/`platform-targets.json`/registry notes/CHANGELOG — a nightly `platform-sync` workflow is producing PRs (#271, #277) that already note the CHANGELOG cannot be safely edited by whole-file replacement; (2) the Anthropic-directory scanner cycle (12 releases 4.11.0→4.11.11 in two days; `check-claude-dist.sh` + 29 planted probes mirror its heuristics); (3) the contract fixtures/templates (36 synced copies + 3 fixture trees that must co-change with any platform addition); (4) the five capability-registry surfaces with 90-day verification budgets and no live binary for Codex/Gemini/OpenCode in the review environment; (5) the four-way hook portability layer (`hook-output.sh` dual dialect, `platform-tools.sh` tool-name mapping, Cursor bundle, Python `docker-guard.py` outside it).

---

## Key questions, answered

- **What does the mod use today vs not touch?** Uses 14 event registrations and `$.{clock,command,env,fs(read/list/exists),model.classify,session(repo/root),ui(open/resolve/toast/invalidate)}` + `$.state` via `atom/read/update`. Does not touch `$.process`, `$.http`, `$.fs.write/stat`, `$.tool.register`, `$.session.append/usage`, `$.ui.view/selection`, `prompt.change`, permission/denial decisions, worktrees, MCP, network, or any bash guard's job (§1.4, §5).
- **Which skills depend on Claude-only capabilities and how do they degrade?** Hard `required`: `notify-setup` (hooks), `session-report` (session_transcripts — refuses/reports unavailable off Claude Code), `deliver-dev`/`pr-dev`/`github-policy` (github_cli — degrade by printing the PR/issue body). Optional Claude-leaning: `orchestrate-dev`/`plan-dev`/`start-dev`/`worker-dev`/`targeted-debug`/`skill-creator`/`platform-sync`/`retro` (subagents/parallel → sequential fan-out per `orchestrate-dev/references/sequential-fallback.md`; structurally impossible to parallelise on Gemini), `orchestrate-dev`/`start-dev`/`switch-dev`/`worker-dev`/`cleanup` (worktree_isolation → explicit `git worktree` steps, emulated on all non-Claude), `orchestrate-dev`/`pr-dev`/`skill-creator` (background_tasks → foreground with bounded timeout; `pr-dev`'s `Monitor` loop is Claude-only), `decision`/`capture-config`/`notify-setup` (ask_user_question → ask in prose), `field-notebook-ui` (artifacts → write file). `targeted-debug`'s `context: fork`/`agent: Explore` is Claude-only frontmatter ignored elsewhere (§1.1, §1.8).
- **Heaviest to maintain?** Prose version notes (`CLAUDE.md` 51 KB, `platform-targets.json` verification strings, registry notes, 152 KB CHANGELOG) restating the same per-release facts; the 36 contract copies and three gold fixture trees; the directory-scanner compliance layer; hand-synced manifests/`.cursor/rules`; capability rows with 90-day expiry and no live non-Claude binaries (§6).
- **What has the project written down as next steps?** Unmerged PR #271 (Claude Code 2.1.300 fix + `onFailure: "block"` decision for the four safety guards; `prompt.change`/`$.ui.view`/`virtualText`/`$.ui.selection`/`isDeferred` noted; `[Unreleased]` changelog entry still to be written) and draft PR #277 (Cursor 3.24.12; wire `subagentStart`/`subagentStop`; live Cursor run; `transcript_path`); daily drift issues #270–#283 (Codex 0.163.0, Gemini 0.64.0, OpenCode 2.0.30); `hooks-classification.md` tiered hook packaging; `cursor.md` session-lifecycle and `beforeSubmitPrompt` ports; Gemini translated hooks ("seven tenths transcription") and the `gemini-cli-extension` topic; OpenCode command discovery and a live v2 `parallel_subagents` run; `PreModelSwitch`/`PostModelSwitch`, `--accept-command`, MCP env knobs recorded-not-adopted in `CLAUDE.md`; eval findings (`fix-weak-description` regression, `context: fork` steering in skill-creator); `tests --strict` promotion; `make typecheck-mods` as a CI gate; `agent-kit.md` follow-ups; `repo-shape-conditionality.md` unfixed rows; the unexplained statusline tmpdir CI flake (§3).
