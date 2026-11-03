# Danger-score audit: toolkit, debugging, documentation, mcp, creative skills

Objective `permissions-design`, task-005. Read-only analysis (security-reviewer). Sibling audit of
dev-workflow/repo skills is task-004; action ids below use the same dot-form so the catalogs merge.

## A) Method and assumptions

- Read every `SKILL.md` frontmatter and body under `skills/{toolkit,debugging,documentation,mcp,creative}/`, then followed
  each script the body tells the agent to run (`scripts/` of the skill, plus `scripts/capture-config.sh`,
  `scripts/usage-capture/*`, `scripts/notify-pushover.sh`, `hooks/usage-capture-ensure.sh`). Nothing was executed.
- Rubric exactly as briefed: R0 observe, R1 local reversible (own worktree/scope, git can undo), R2 shared-additive,
  R3 shared-mutating, R4 irreversible/privileged (incl. global machine config writes, editing the plugin's own permission
  policy). Unclear => R4. Score = reversibility x blast radius x external visibility, per step; skill max R = max over steps.
- **Rubric gap (flagged, not decided):** machine-local side effects that are not "config" (start/stop a local daemon, SIGTERM a
  port holder, install a package, spawn a nested `claude -p`) have no row. They are scored conservatively and marked `*`.
- Assumption (medium confidence): `allowed-tools` in skill frontmatter pre-approves tools; it does not forbid others. Every
  audited skill lists at most `Read/Glob/Grep/AskUserQuestion/WebFetch(domain)/Skill/Agent` and none lists `Bash`, `Write` or
  `Edit`, yet most bodies tell the agent to run shell and write files. So the real gate for those steps is the host's ordinary
  tool-permission prompt, which a permission level (or bypass mode) replaces. No skill sets `disable-model-invocation: true`
  (all 16 are `false`) and none declares `hooks`; so every skill below is model-invocable and subagent-reachable
  (`user-invocable: false` only on changelog-review, docs-review, mcp-pagination, which stay reachable via `Skill`).
- Skills audited: 16 (toolkit 7, debugging 2, documentation 4, mcp 2, creative 1). `skill-creator/agents/{grader,comparator,
  analyzer}.md` are reference prompts (no tool frontmatter), counted under skill-creator.

## B) Per-skill table

Flags: N=network, S=secrets (reads/writes credentials), M=model-invocable, A=subagent-reachable. All 16 have M and A, so only
N and S are shown. `-` = none. "Gate" is what exists today.

| skill | max R | R-profile of steps | N / S | existing gate | evidence |
|---|---|---|---|---|---|
| usage-capture | **R4** | R0 query jsonl; R4 enable (writes `~/.claude/settings.json` env + starts daemon); R4 disable (rewrites settings, stops daemon); R4 `--bodies` (raw API bodies to disk) | N loopback only / S: bodies capture secrets | `--dry-run --json` exists but SKILL.md does not require it; prose "say so before turning bodies on"; refuses to replace a foreign `OTEL_EXPORTER_OTLP_ENDPOINT` without `--force`; loopback bind; 0700/0600 modes | SKILL.md:106,109,91; scripts/usage-capture/enable.sh:25,165,214-219,246; collector.py:536-548; hooks/usage-capture-ensure.sh:30 |
| capture-config | **R4** (conditional) | R0 detect; R1 review stages into repo canonical source; R1 deliver: local branch + commits; stage target `platforms/*/settings.d` / `core/global-rules.md` holds permission policy => R4 once rendered | S: reads `~/.claude`, `~/.codex`, `~/.cursor`, `~/.gemini`, `~/.config/opencode` (secrets classed + refused) | per-hunk `[y/N]` prompt on `/dev/tty`, default skip; no tty => adopts nothing; secret/IP-scan blocking; `make validate` before branch; never pushes/opens PR; prose "never adopt on user's behalf" | SKILL.md:95-113,128,155-160; scripts/capture-config.sh:508-521,460,692-735 |
| notify-setup | **R2** (R4 by suggestion) | R0 platform check; R2 credential validate POST + test push to Pushover; R4 *suggested* `claude plugin configure` (host secret store) and `bash scripts/uninstall.sh` (rewrites `~/.claude/settings.json`) | N external / S: asks user to paste Pushover token + user key in chat | prose: collect both creds, validate before storing, "never write them anywhere else"; stops on non-Claude platforms; AskUserQuestion where available | SKILL.md:138-169,171-176,225; scripts/notify-pushover.sh:40-41,103,106 |
| retro | **R4** (conditional) | R0 transcript analysis; on approval: writes memory under `~/.claude/projects/<p>/memory`, project rules, hooks, `settings.json` | - / - | "propose, stop, wait for approval" is a hard prose gate; framework policy (`core/**`, `rules/**`, registry) proposal-only even if approved; `allowed-tools: Read` | SKILL.md:100-121 |
| session-report | **R1** | R0 read all `~/.claude/projects/**.jsonl`; R1 write `/tmp/session-report.json` + `./session-report-*.html` in cwd | - / S: transcripts carry secrets and prompt text, copied into the HTML | none needed beyond node presence; zero-data stop | SKILL.md:121,168,198-202; analyze-sessions.mjs:57,482 |
| skill-creator | **R3*** | R1 author/edit skill files in repo; R1 eval workspaces + packaging; R1-R4 spawned eval subagents (inherit tools; execute skill-under-test + arbitrary eval prompts); R2* nested `claude -p` x many (run_eval/run_loop/improve_description); R1 transient `.claude/commands/*.md`; R1 loopback viewer + browser open; R3* SIGTERM of whatever listens on :3117 | N (model API via nested claude) / - | none on spawn or kill; `--static` fallback; quick_validate before package; "never fabricate benchmark" prose | scripts/run_eval.py:68,71,85,181; improve_description.py:26-38; run_loop.py:199,279; eval-viewer/generate_review.py:288-306,440,461; SKILL.md:278-300,353-358 |
| find-skill | **R0** | R0 WebFetch/WebSearch fan-out over source list; prints install instructions only | N (user query goes to third-party sites) / - | prose: do not invent URLs; verify before fetch; user-overridable sources file | SKILL.md:95-112,208-210; references/sources.json |
| diagnose-refusal | **R1** | R0 read env var NAMES, configs (litellm yaml, `.claude/`, `.cursor/`); R1 create/replace `<repo>/.refusal-debug/`; R1 in-place redact of bundle files | - / S: reads configs holding keys, redacts | "diagnostics only, never retry"; "no network requests to discover secrets"; names only, never values; redaction pass | SKILL.md:56,83,209,290; scripts/collect-environment.sh:91-114; init-bundle.sh:50; redact-secrets.py:87; .gitignore:70 |
| targeted-debug | **R0** | R0 read-only: `context: fork`, `agent: Explore`, tools Read/Grep/Glob; script only parses text; git blame/log | - / - | structurally read-only; "never opens a PR, commits or applies a fix" | SKILL.md (frontmatter agent: Explore); scripts/extract-error-paths.sh; SKILL.md:230 |
| changelog-review | **R0** | R0 WebFetch (3 domains, incl. all of github.com), local validators (jq, python frontmatter check) | N GET / - | read-only tool list; domain-scoped WebFetch | SKILL.md allowed-tools; scripts/validate-plugin-json.sh; check-skill-frontmatter.sh |
| docs-review | **R1** | R0 audit scripts (git log/diff, grep, link check); R1 fix docs in place; R1 `git rm --cached` + `.gitignore` edit; R1* runs `tooling/ci/regen-claude-md.sh` from the audited repo; R1 commits regen output | - / - | "confirm before first write when no parent skill" (prose; waived under repo-standards/sub-agent); "never delete a doc the user has not confirmed"; `make -n`/`bash -n` only, "never execute an install command" | SKILL.md:60-77,410,417; references/sweep-checklist.md:145,206,241,338,374 |
| platform-sync | **R0** | R0 repo detection, WebFetch (11 domains), optional probe script (curl GET api.github.com + npm registry) | N GET / - | report-only; never edits registry or manifests | SKILL.md:100-125,200-205; scripts/probe-platform-versions.sh:92-112 |
| dark-terminal-doc | **R1** | R1 write one `.html` (path chosen by agent); output links Google Fonts when opened | N when the file is opened / - | none (Write is not in allowed-tools, so host prompt applies) | SKILL.md:77,85,90 |
| field-notebook-ui | **R1** | R1 write one `.jsx`/`.html` file; no build/install/dev server | N when opened (Google Fonts link) / - | "never require build step, package install or dev server" | SKILL.md:112,422,436 |
| mcp-builder | **R4** | R1 scaffold project dir + files; R3* `npm install` / `pip install` / `npx @modelcontextprotocol/inspector@2.12.0` / `fastmcp dev`; R1* starts the generated server; **R4 Phase 6 registers server in user-level Claude Code config and `claude_desktop_config.json`** (persistent code-exec entry) | N (package registries, live docs) / S: `${ENV}` placeholders only | Phase 6: "generate config only for targets the user uses, detect or ask"; capability check; `${ENV}` only, never literal tokens; validate with `jq empty` | SKILL.md:157-195,290-300,338-392; scripts/scaffold.sh:26-32,232 |
| mcp-pagination | **R0** | R0 reads tool schemas, greps a JSON file | - / - | read-only (`allowed-tools: Read`) | SKILL.md; scripts/check-pagination.sh:25-67 |

## C) Per-action catalog

Ids marked (shared) reuse the shapes proposed for the task-004 catalog. `confirmed?`: yes = a gate the code enforces; partial =
prose or an opt-in flag; no = none.

| action id | R | skills using it | where | confirmed? |
|---|---|---|---|---|
| config.global.write | R4 | usage-capture (enable/disable); mcp-builder (Phase 6 user-level + Desktop config); retro (approved settings/hooks edits); notify-setup (suggested: plugin configure, uninstall.sh); capture-config (**reads** these, writes none) | enable.sh:25,214-219; mcp-builder SKILL.md:361-363; retro SKILL.md:117; notify-setup SKILL.md:150-169,225 | partial (retro: ask-first prose; others none) (shared) |
| config.policy.stage | R4 | capture-config (adopted hunks land in `platforms/*/settings.d`, `core/global-rules.md`; may include permission rules) | capture-config.sh:526-545; SKILL.md:116-125 | partial (per-hunk tty prompt; bypassable by `--adopt all`) |
| daemon.start | R4* | usage-capture (enable.sh, `collector.py --daemon`, SessionStart hook `usage-capture-ensure.sh` when env set) | enable.sh:246; collector.py:536-548; hooks/usage-capture-ensure.sh:30 | no |
| daemon.stop | R2* | usage-capture (`--disable`, `--stop`) | enable.sh:231; collector.py:495-505 | no |
| process.kill.port | R3* | skill-creator (eval viewer SIGTERMs any process on :3117 via `lsof -ti`) | generate_review.py:288-306,440 | no |
| process.spawn.claude_cli | R2* | skill-creator (`claude -p` per trigger query, per description-improve step, looped by run_loop) | run_eval.py:71-90; improve_description.py:26-38; run_loop.py:199 | no |
| agent.spawn | R1* (inherits child's actions) | skill-creator (with-skill + baseline eval subagents, grader); targeted-debug (fork/Explore, read-only) | skill-creator SKILL.md:278-300; targeted-debug frontmatter | no |
| server.local.start | R1* | skill-creator eval viewer (`nohup python ... &`, loopback, opens browser) | SKILL.md:353-358; generate_review.py:443,461 | no |
| pkg.install.network | R3* | mcp-builder (`npm install`, `pip install`, venv) | SKILL.md:180-191; scaffold.sh:85,331 | no |
| pkg.exec.network | R3* | mcp-builder (`npx @modelcontextprotocol/inspector@2.12.0`, `fastmcp dev`) | SKILL.md:295-299 | no (version pinned) |
| code.exec.repo_script | R1* | docs-review (`tooling/ci/regen-claude-md.sh` of audited repo; regen scripts); capture-config deliver (`make validate`); mcp-builder (start generated server) | sweep-checklist.md:145,374; capture-config.sh:710; mcp-builder SKILL.md:392 | no |
| notify.send | R2 | notify-setup (test push through `notify-pushover.sh`); runtime hook thereafter | SKILL.md:171-176; notify-pushover.sh:103 | partial (user asked to set up) |
| net.post.external | R2 | notify-setup (Pushover `users/validate.json` carries token+user key; `messages.json` carries up to 300 chars of last message by default) | SKILL.md:140-143; notify-pushover.sh:103,106 | partial |
| net.get.docs | R0 | find-skill, platform-sync, changelog-review (+probe script GETs) | find-skill SKILL.md:109; platform-sync allowed-tools; probe-platform-versions.sh:92-112 | yes (domain allowlist for sync/changelog; find-skill none) |
| secrets.collect.chat | R2 (visibility: credentials enter the transcript and the provider) | notify-setup | SKILL.md:138-143 | partial (prefix check; instruction not to echo) |
| secrets.read.config | R0 (secret-bearing) | capture-config (reads machine configs), diagnose-refusal (litellm/config.yaml, env names), session-report (transcripts) | capture-config.sh classification; collect-environment.sh:91-114; analyze-sessions.mjs:57 | yes for capture-config/diagnose (refuse or redact); no for session-report |
| secrets.capture.bodies | R4 | usage-capture `--bodies` (raw API request/response bodies to `<dir>/bodies`) | enable.sh:195; SKILL.md:91 | partial (prose warning) |
| file.write.outside_repo | R3 (R4 if the target is config) | retro (memory dir under `~/.claude/projects`); usage-capture (`~/.local/share/.../usage`); session-report (`/tmp/session-report.json`) | retro SKILL.md:119; collector.py:181; session-report SKILL.md:168 | partial (retro ask-first) (shared) |
| file.write.repo | R1 | docs-review, dark-terminal-doc, field-notebook-ui, mcp-builder scaffold, skill-creator, diagnose-refusal (`.refusal-debug/`), capture-config (stage), session-report (cwd html) | per skill rows above | n/a (git undoes) |
| file.overwrite.nocheck | R1 | mcp-builder scaffold.sh (`cat >` over existing package.json/index.ts/server.py; project path unvalidated, `../x` allowed) | scaffold.sh:26,32,102,232 | no |
| git.branch.create | R1 | capture-config deliver (`git checkout -q -b capture/<date>-<slug>` in the live checkout) | capture-config.sh:719 | partial (`make validate` first) (shared) |
| git.commit.local | R1 | capture-config deliver (one commit per platform dir via `git add -- core platforms`); docs-review (commit regen output) | capture-config.sh:721-733; sweep-checklist.md:374 | partial |
| git.index.untrack | R1 | docs-review (`git rm --cached` plan files, `.gitignore` edit) | sweep-checklist.md:206 | partial (needs user-confirmed Axis 3 hits) |
| git.push.branch, pr.create, pr.merge, branch.delete.remote, repo.create | R2/R3/R4 | **none of these skills**; capture-config prints `gh pr create` and stops, "never merge" | capture-config.sh:742-747 | yes (not performed) |
| browser.open | R0 | skill-creator (viewer, `run_loop` live report) | generate_review.py:461; run_loop.py:279 | no |
| env.read.names | R0 | diagnose-refusal | collect-environment.sh:91-114 | yes (names only) |

## D) Findings (R3/R4 steps with no gate, or "ask" only as prose)

Severity = harm if an unattended or bypass-mode agent follows the skill. Confidence in brackets.

**F1 HIGH [high]. usage-capture enable writes global config and starts a daemon with no confirmation.**
Evidence: enable.sh:25 targets `~/.claude/settings.json`; 214-219 atomically replaces it (no `.bak`, git cannot undo); 246 forks a
detached collector. Sets `CLAUDE_CODE_ENABLE_TELEMETRY`, OTLP endpoint, `OTEL_LOG_TOOL_DETAILS=1` (enable.sh:186-190), and with
`--bodies` raw API bodies (enable.sh:195). The skill is model-invocable (disable-model-invocation false) and subagent-reachable;
`--dry-run --json` exists (SKILL.md:109) but the workflow never requires it. SessionStart hook restarts the daemon each session
once the env flag is set (hooks/usage-capture-ensure.sh:30). Suggested minimal gate: `config.global.write` + `daemon.start` + `secrets.capture.bodies` require an
explicit per-invocation ask; make step 1 run `--dry-run --json` first and show the diff; add a settings backup; treat `--bodies`
and `--force` as separate asks. Never-auto candidate for unattended.

**F2 HIGH [medium]. mcp-builder Phase 6 writes user-level host config (persistent code execution) behind "detect or ask".**
Evidence: SKILL.md:361-363 lists user-level Claude Code config and `claude_desktop_config.json`; 342-345 says "detect them ... or
ask" (prose, and detection means no ask at all). The entry names a command the host will run on every start. Also steps in
Phase 4 install and exec packages (SKILL.md:180-191, 295-299). Suggested gate: `config.global.write` ask naming the exact
file and command; default to project-scoped `.mcp.json` (R1); package install/exec asked once per scaffold.

**F3 MEDIUM [high]. retro: the only gate for settings/hooks/memory edits is prose; skill has `allowed-tools: Read`.**
Evidence: SKILL.md:117 ("do not create or edit any files (especially hooks / settings.json) until they say yes"); 119 writes to
memory dir (`~/.claude/projects/...`, outside repo) and "hooks / settings.json" with no scope limit to project vs global. The
framework-policy exclusion (SKILL.md:100-113) is also prose-only. Approval is by chat reply, which an unattended run cannot give.
Suggested gate: classify each approved change by target (`config.project.write` R1, `config.global.write` R4,
`file.write.outside_repo` R3) and route through the level policy; keep "propose-only" for `core/**`/`rules/**` as a hard deny, not prose.

**F4 MEDIUM [high]. capture-config: documented "no --yes" is contradicted by `--adopt all`; stage target is permission policy.**
Evidence: SKILL.md:113-117 says no `--yes`; capture-config.sh:460 `[ "$OPT_ADOPT" = all ] && return 0` adopts every offerable hunk
without a prompt, and ask_hunk (508-514) honours it. Adopted hunks can be permission rules landing in `platforms/claude/settings.d`
(capture-config.sh:673-676), i.e. the plugin's own permission policy (R4 when merged and rendered). Further: SKILL.md:158 says
"never commit" but `deliver` commits (capture-config.sh:721-733); `git add -- core platforms` also sweeps unrelated pre-existing
edits in those dirs into the capture commits; `git checkout -b` runs in the user's live checkout (719). Offer-proactively wording
(SKILL.md:71) plus model-invocable. Suggested gate: reject `--adopt all` for agents (explicit ids only); make `config.policy.stage` of a
permission/hook hunk a separate ask; `deliver` should refuse with a dirty `core/`/`platforms/` it did not stage; fix the SKILL.md
"never commit" wording.

**F5 MEDIUM [medium]. skill-creator nested `claude -p` sessions are outside any permission level; eval subagents inherit full tools.**
Evidence: run_eval.py:71-90 launches `claude -p <query>` with no `--permission-mode`/`--allowedTools`, in `cwd=project_root`,
after stripping `CLAUDECODE`; it therefore loads the user's own settings (if their default mode is bypass, the child is bypass).
run_loop.py:199 + improve_description.py:26-38 repeat this per iteration (cost and N model calls). SKILL.md:278-300 spawns subagents
that "execute this task" for a skill-under-test and arbitrary eval prompts (could be a third-party skill). The transient
`.claude/commands/*.md` write (run_eval.py:68) is unlinked in `finally` (181) but survives a hard kill. Suggested gate: one ask
before the first `process.spawn.claude_cli` loop stating iteration count x queries; pass an explicit restrictive permission mode to
the child; subagents must inherit the parent's level, never raise it.

**F6 MEDIUM-LOW [high]. skill-creator viewer SIGTERMs whatever owns port 3117.**
Evidence: generate_review.py:288-306 `lsof -ti :3117` then `os.kill(pid, SIGTERM)` for every pid, unconditionally (called at 440).
Could kill an unrelated dev server. Suggested gate: only kill a pid whose command line matches `generate_review.py`, else pick a free
port (the fallback at 444-447 already exists).

**F7 LOW-MEDIUM [medium]. notify-setup handles credentials and sends to a third party with prose-only guards.**
Evidence: SKILL.md:138-143 pastes both keys into chat; the validate curl (SKILL.md:140-143) puts them in argv (visible to local `ps`
for the call's duration); test push at 171-176. Default config sends up to 300 chars of the last assistant message to Pushover on
every notification (SKILL.md "Privacy"; notify-pushover.sh:103), with "flag this to the user" as prose. Suggested gate: ask before
`net.post.external`; prefer the host's secret prompt over chat; default `PUSHOVER_INCLUDE_SNIPPET=0` on machines flagged sensitive.
Also the suggested `bash scripts/uninstall.sh` (SKILL.md:169,225) rewrites `~/.claude/settings.json` and must be a separate
`config.global.write` ask.

**F8 LOW-MEDIUM [medium]. docs-review: confirmation waived exactly when running unattended; runs repo-supplied scripts.**
Evidence: SKILL.md:60-77 requires go-ahead only when "no invoking parent skill" (an orchestrated sub-agent skips it by design);
sweep-checklist.md:145 and 374 execute `tooling/ci/regen-claude-md.sh` / "a regeneration script" from the audited repo, which may be
any repo `repo-standards` is pointed at (`$TARGET_ROOT`, possibly outside the worktree). Edits are git-undoable (R1). Suggested gate:
treat `code.exec.repo_script` of a script from a repo other than the current worktree as R3; file edits stay R1 inside scope.

**F9 LOW [high]. mcp-builder scaffold.sh overwrites and trusts its path argument.**
Evidence: scaffold.sh:26 `mkdir -p "$PROJECT"`; 32/102/232 `cat >` without existence checks; `PROJECT` arbitrary (`../../x`, absolute).
Suggested: refuse when the directory is non-empty or resolves outside cwd.

**F10 LOW [medium]. usage-capture `--stop` signals the PID in the pid file without confirming it is the collector.**
Evidence: collector.py:495-505 `pid_alive` then `os.kill(pid, SIGTERM)`; a stale file plus PID reuse could signal an unrelated
process. Suggested: verify `/health` or process command line first.

**F11 LOW [medium]. session-report copies transcript text into an HTML file in cwd and uses a fixed /tmp path.**
Evidence: SKILL.md:168 writes `/tmp/session-report.json` (predictable name in a shared dir) while 202 and "What NOT to do" say never
use /tmp; the HTML embeds `top_prompts` previews (analyze-sessions.mjs:482) and is written to cwd (SKILL.md:198), which may be a
tracked repo. Suggested: write both to a private dir or cwd with a `.gitignore` check; fix the contradictory instruction.

**F12 LOW [medium]. diagnose-refusal bundle location.** Evidence: SKILL.md:83 uses repo root or cwd; `.refusal-debug/` is gitignored
only in this repo (.gitignore:70). In other repos the bundle (redacted config excerpts, git status) could be committed. Suggested: check
`git check-ignore` before writing.

**F13 INFO [high]. Reads of secret-bearing config are well gated where it matters.** capture-config classifies and refuses secrets
(SKILL.md:140-146); diagnose-refusal records env var names only (collect-environment.sh:91-114). No skill in scope pushes, opens
or merges a PR, deletes a remote branch, creates a repo, tags or releases (verified by reading each script and body; the only `gh`
text is a printed command in capture-config.sh:746).

Counts. R3/R4 steps with no gate at all: 3 findings (F1, F2 incl. package install/exec, F6). R3/R4 steps gated only by prose or
bypassable by a flag: 3 (F3, F4, F7's `uninstall.sh`). Ungated R2* machine-local: F5. Rated R3 by this audit on a judgment call: F8
(foreign-repo script execution). Lower severity R1 issues: F9-F12.

## E) Level-fit preview (table only; no design decisions)

P = prompts, A = automatic, X = never automatic (refused/not executed without a level change). Standard = R2 automatic, R3 ask,
auto-merge off. Unattended = R3 automatic unless flagged never-auto, R4 never automatic. R-level taken from section C.

| action id | R | supervised (ask every R2+) | standard | unattended |
|---|---|---|---|---|
| net.get.docs, env.read.names, secrets.read.config, browser.open | R0 | A | A | A |
| file.write.repo, git.branch.create, git.commit.local, git.index.untrack, file.overwrite.nocheck | R1 | A | A | A |
| code.exec.repo_script, server.local.start, agent.spawn | R1* | A | A | A |
| notify.send, net.post.external, secrets.collect.chat | R2 | P | A | A |
| process.spawn.claude_cli, daemon.stop | R2* | P | A | A |
| file.write.outside_repo (non-config) | R3 | P | P | A |
| pkg.install.network, pkg.exec.network | R3* | P | P | A |
| process.kill.port | R3* | P | P | A (candidate never-auto) |
| config.global.write (usage-capture, mcp-builder Phase 6, retro settings, uninstall.sh) | R4 | P | P | X |
| config.policy.stage (capture-config permission/hook hunks) | R4 | P | P | X |
| daemon.start (usage-capture) | R4* | P | P | X |
| secrets.capture.bodies (`--bodies`) | R4 | P | P | X |
| git.push.branch, pr.create | R2 | (not used by these skills) | | |
| pr.merge, branch.delete.remote | R3 | (not used by these skills) | | |
| repo.create, release/tag, branch-protection edits | R4 | (not used by these skills) | | |

Rows where the skill-level prose gate and the level table disagree today: usage-capture, mcp-builder Phase 6, retro, capture-config
(`--adopt all`), skill-creator nested sessions. For every `*` row the rubric needs an owner decision on a machine-local class.
