# Prior art: configurable agent autonomy (for the plugin's own permission behavior)

Research input to ADR 004 (permission levels). Date 2026-11-03. Evidence tags: doc-cited / source-cited / measured / unverified.

Researched 2026-11-03. Scope: patterns, standards, how others expose autonomy. Per-host settings
references are covered by sibling reports; host rows below are only as deep as the pattern needs.
Anything not confirmed against a primary source is marked **unverified**.

---

## 1. Autonomy tiers in leading tools

### Comparison table

| Tool | Named presets | Granular rules | Granularity axis | Deny wins? | Persistence | How dangerous actions are singled out |
|---|---|---|---|---|---|---|
| **Claude Code** | Modes: default/Manual, acceptEdits, plan, auto, dontAsk, bypassPermissions [1] | allow/ask/deny rules per tool + specifier [1] | Per tool type (read, Bash, edit, web) and per command pattern [1] | **Yes** — "deny, then ask, then allow … rule specificity doesn't change the order"; any-scope deny beats any-scope allow [1] | "Don't ask again" is permanent per repo+command for Bash, session-only for edits [1]; managed > CLI > local > project > user [1] | A fixed list no mode auto-approves (explicit ask rules, AskUserQuestion, critical-path `rm`) [2]; protected paths `.git`, `.claude`, `.mcp.json`, shell rc files never auto-approved outside bypass [2]; auto-mode classifier blocks force push, prod deploys, `curl \| bash`, destroying pre-existing files [2]; `disableBypassPermissionsMode` can lock bypass out [1] |
| **Codex CLI** | Two orthogonal axes: approval `untrusted`/`on-request`/`never` × sandbox `read-only`/`workspace-write`/`danger-full-access` [3] | Config keys + flags [3] | Sandbox boundary, not per command | unverified | `~/.codex/config.toml` [3] | The *sandbox boundary* is the danger line: leaving it is what triggers approval under `on-request` [3]; the dangerous value is literally named `danger-full-access` |
| **Gemini CLI** | `default`, `auto_edit`, `plan`, `yolo` [4] | TOML policy engine, allow/deny/ask_user, priority 0–999, Default/User/Admin tiers, rules scoped to modes [5] | Per tool + args | Highest priority wins (not pure deny-wins) [5] | Settings file — but **YOLO "can only be enabled via command line"**, not `defaultApprovalMode` [4] | Untrusted folder forces any non-default mode back to default [5, search excerpt — partially verified]; an approval granted in yolo applies only to yolo, one granted in default applies upward [5] |
| **Cursor** | Run modes under Approvals & Execution: Auto-review, Allowlist, Run Everything [6] | Command allowlist | Per command; sandbox vs outside | unverified | Settings | Commands needing to leave the sandbox ask; "Run Everything" runs every call without checks [6] |
| **Cline** | One meta-switch: **YOLO mode** (no confirmation dialog when enabling) [7] | Toggles: read project / read all / edit project / edit all / safe commands / all commands / browser / MCP [7] | **Per category**, with "all files"/"all commands" as extensions of a base toggle [7] | n/a (no deny list) | Settings | "Safe" = model-tagged `requires_approval`, no fixed allowlist [7]; docs recommend only "read project files" on by default [7] |
| **Roo Code** | — | Per category: read, write, **protected files**, commands (allow+deny list), browser, MCP (global + per tool), mode switching, subtasks, follow-up auto-answer [8] | Per category + per command prefix | Deny wins when its prefix is equally or more specific (longest prefix wins) [8] | Settings | `.roo/` and `.rooignore` are protected even with write auto-approve; a separate "Include protected files" opt-in is needed [8] |
| **Aider** | — | Flags: `--yes-always`, `--auto-commits` (default **True**), `--dry-run` [9] | Global | n/a | CLI/config | No special tier; reversibility comes from auto-commit to git [9] |
| **GitHub Copilot coding agent** | — | Org/repo policy | Structural | n/a | Repo/org settings | Pushes only to its PR branch or a new `copilot/` branch; Actions on its PRs need write-access approval; firewall on by default [10]; admin opt-out of workflow approval exists (2026-03) [11] |
| **Windsurf / Devin Desktop** | Auto-execution levels: Disabled, Allowlist Only, Auto (model judges safety), Turbo [12] | User + team allow/deny lists [12] | Per command | **Yes** — "a denylist entry will always require user approval … regardless of user settings" [12] | User + team; admins cap the max level [12] | Deny list; admin ceiling on the level users may pick [12] |
| **Amp** | — | `amp.permissions` rules: allow / reject / ask / **delegate** (external program decides via exit code) [13] | Per tool + args; can target main thread vs sub-agents only [13] | First match (ordered list) [13] | Settings; `amp permissions test` to dry-run a rule [13] | Philosophy: gate only hard-to-undo actions — deploys, prod DB, `git push`, `terraform apply/destroy`, `rm -rf` — because "Git makes the cost of a wrong edit negligible" [14] |
| **Goose** | Autonomous (**default**), Manual Approval, Smart Approval, Chat Only; switch with `/mode` [15] | Per tool: Always Allow / Ask Before / Never Allow [15] | Per tool | unverified | Config + session switch | Smart Approval asks only for tools it deems "write" tools [15] |
| **Continue** | — | Per tool: Ask First (default) / Automatic / Excluded [16] | Per tool | n/a | Config | Docs warn against Automatic for non-read-only tools [16] |
| **Devin (cloud)** | unverified | unverified | — | — | — | Not researched to a primary source |

### Headline patterns
1. **Everyone converges on 3–4 named levels plus per-item allow/ask/deny.** Presets for the common case
   (Claude Code modes, Gemini modes, Windsurf levels, Goose modes); a rule list for exceptions.
2. **Deny-wins is the norm where deny exists** (Claude Code, Windsurf; Roo with a specificity twist).
   Gemini and Amp use ordered/prioritized first-match instead, which is harder to reason about.
3. **The danger axis is reversibility, not tool type.** Amp says so explicitly [14]; Claude Code's
   auto-mode block list is entirely irreversible/shared-state actions [2]; OpenAI's rating factors
   are read/write, reversibility, permissions, financial impact [17].
4. **The top tier is made hard to reach on purpose.** Gemini: YOLO is CLI-only, not persistable [4].
   Claude Code: bypass can be disabled by any scope [1]. Codex: named `danger-full-access` [3].
   Windsurf: admins cap the level [12].
5. **The agent's own config is a protected target.** Claude Code protects `.claude`, `.mcp.json` [2];
   Roo protects `.roo/` behind a separate opt-in [8]. This is a direct response to section 5's attacks.
6. **Some defaults are wide** (Goose Autonomous [15], Aider auto-commits [9], Cline docs ship the opposite
   advice [7]). There is no consensus default — but every security source says start narrow.

---

## 2. Standards and guidance

### MCP tool annotations (spec 2025-11-25) [18]
- `readOnlyHint` (default **false**), `destructiveHint` (default **true**, meaningful only when not
  read-only; false means "only additive updates"), `idempotentHint` (default false),
  `openWorldHint` (default **true**; open = interacts with external entities).
- "All properties in ToolAnnotations are **hints** … Clients should never make tool use decisions
  based on ToolAnnotations received from untrusted servers." [18]
- Tools page: "there **SHOULD** always be a human in the loop with the ability to deny tool
  invocations"; clients SHOULD "prompt for user confirmation on sensitive operations" and "show tool
  inputs to the user before calling the server" [19].
- **Transferable:** the four booleans are a ready-made vocabulary for classifying *plugin actions*,
  and the defaults are **pessimistic** (an unannotated action is assumed destructive and open-world).
- Client usage: ChatGPT reportedly skips confirmation for `readOnlyHint: true` and badges READ/WRITE;
  VS Code reportedly confirms tools lacking `readOnlyHint` — **unverified** (secondary blogs only) [20].

### OWASP LLM06:2025 Excessive Agency [21]
- Root causes: excessive **functionality**, excessive **permissions**, excessive **autonomy**
  ("does not independently verify and approve high-impact actions").
- Mitigations: minimize extensions; minimize extension functionality; avoid open-ended extensions;
  minimize permissions; execute in the user's context; **require user approval** for high-impact
  actions; **complete mediation** — "enforce authorization in downstream systems instead of trusting
  the LLM to decide whether an action is allowed"; sanitize inputs/outputs.
- **Implication for this plugin:** a level written only into SKILL.md prose is "trusting the LLM to
  decide." The gate must also live in a hook or the downstream system (GitHub branch protection).

### OWASP Top 10 for Agentic Applications 2026 (published 2025-12-09) [22]
- ASI01 Agent Goal Hijack, ASI02 Tool Misuse, ASI03 Identity & Privilege Abuse … ASI09 Human-Agent
  Trust Exploitation, ASI10 Rogue Agents — entry names via secondary sources [23]; the official page
  confirms the date and framing but I could not read the entry text — **details unverified**.
- Secondary sources attribute a "least agency" principle and "human approval for high-impact or
  goal-changing actions" to it [23] — **unverified** against the OWASP text.

### NIST
- AI 600-1 (GenAI Profile, July 2024) has no agent-specific human-oversight category; a CSA note argues
  it does not distinguish recommend-for-review from autonomous execution [24, secondary].
- NIST CAISI has published agent-hijacking evaluations (AgentDojo-based) and found hijacks succeed more
  with repeated attempts [24]. No NIST HITL rubric for agent actions found — **gap**.

### Vendor guidance
- **Anthropic** (framework, 2025-08): "humans should retain control over how their goals are pursued,
  particularly before high-stakes decisions"; Claude Code is "read-only … by default", "must ask for
  human approval before taking any actions that modify code or systems", "users can grant persistent
  permissions for routine tasks"; humans "can stop Claude whenever they want" [25].
- **OpenAI** ("A practical guide to building agents"): "Assess the risk of each tool … by assigning a
  rating—low, medium, or high—based on factors like read-only vs. write access, reversibility, required
  account permissions, and financial impact. Use these risk ratings to trigger automated actions, such
  as pausing for guardrail checks before executing high-risk functions or escalating to a human."
  High-risk = "sensitive, irreversible, or have high stakes … until confidence in the agent's
  reliability grows" [17].
- **Meta "Agents Rule of Two"**: an agent should hold at most two of [A] processes untrustworthy
  inputs, [B] access to sensitive systems/private data, [C] can change state or communicate
  externally; with all three it needs "human-in-the-loop approval or another reliable means of
  validation" [26, 27]. `pr-dev` reading PR review comments (A) with a GitHub token (B) and merging (C)
  is exactly the all-three case.
- **Willison "lethal trifecta"**: private data + untrusted content + external communication [28].

---

## 3. Plugin/skill ecosystems and transferable conventions

### Agent plugins / skill packs
- **obra/superpowers** `finishing-a-development-branch`: no autonomy config. It presents a *fixed*
  menu (merge locally / push+PR / keep), waits for the answer, and gates discard behind
  **"Type 'discard' to confirm."** plus a list of exactly what will be deleted [29]. A good pattern for
  the R4 tier; a counter-example for configurability (none).
- **Claude Code plugin `userConfig`** — the native install-time preset mechanism: prompted "when the
  plugin is enabled", `type: string` with `options` renders a picker (CC ≥2.1.271), each option also a
  row in `/config`; values stored under `pluginConfigs` in user `settings.json`; substituted into skill
  and agent content as `${user_config.KEY}`; exported to hooks as `CLAUDE_PLUGIN_OPTION_<KEY>` [30].
  `pluginConfigs` scope is listed as **"User or managed"** — not project [31, index row only].
  That means a cloned repo cannot widen it: a very useful property.
- Claude Code plugin subagents **ignore `permissionMode`, `hooks`, `mcpServers` frontmatter** "for
  security reasons" [32]. Host design intent: a plugin cannot self-grant host permission modes.
- I found **no other published plugin that exposes "may merge / may delete" as a setting** — this
  appears novel (search-based negative; **unverified** as exhaustive).

### Approval delegated to policy
- **GitHub auto-merge**: "merges a pull request automatically after all required reviews and status
  checks pass"; disabled "if someone without write permissions pushes new changes"; must be enabled
  per repo [33]. **Merge queue**: each PR clears required checks combined with the latest base and
  queued PRs ahead of it [34]. **Transfer:** an "auto" level for `pr-dev` can mean *arm*
  `gh pr merge --auto` and let branch protection decide — OWASP's complete mediation [21].
- **Copilot coding agent**: autonomy bounded structurally (own branch prefix, workflow approval) not
  by prompting [10].

### CLI conventions (clig.dev [35])
- Danger tiers **mild / moderate / severe**: mild "might" prompt; moderate "usually" prompt and offer a
  dry run; severe — "make it hard to confirm by accident", e.g. type the resource's name.
- `-n/--dry-run` "describe the changes that would occur"; `-f/--force` for scripts to skip a
  confirmation; `--no-input` disables all prompts and the command must **fail** and say which flag to
  pass if it needs input; only prompt when stdin is a TTY.
- **Transfer:** in a headless/no-human run, *ask* must degrade to *deny with instructions*, never to
  allow. Claude Code's `dontAsk` does exactly this: "never prompts … denies the call instead" [1].

### Terraform plan/apply [36]
- Default apply plans, then prompts; `-auto-approve` skips approval "including destructive operations";
  applying a **saved plan** runs it "without prompting". **Transfer:** `cleanup` should emit a plan
  (branches to delete), the human approves *the plan*, and apply executes exactly that plan — no new
  targets discovered after approval.

### Kubernetes RBAC [37, 38]
- Deny by default; verbs `get/list/watch/create/update/patch/delete/deletecollection`.
- Anti-escalation: "You can only create/update a role if … you already have all the permissions
  contained in the role" or hold `escalate`; same for bindings with `bind` [38]. **Transfer:** the
  config-changing skill, running at level L, may not set any action above L without a human.
- `get`/`list` are equivalent in data exposure [37] — read is not automatically harmless.

### VS Code Workspace Trust [39]
- Restricted Mode disables agents, tasks, debugging, workspace settings in untrusted folders; trust is
  per folder and inherited by subfolders. **Transfer:** repo-committed plugin config may only
  *narrow*; widening lives in user scope (matches `pluginConfigs` being user/managed [31]).

---

## 4. Risk-scoring rubric

### Published inputs
- OpenAI: low/medium/high from read-vs-write, reversibility, account permissions, financial impact [17].
- MCP: readOnly / destructive / idempotent / openWorld, pessimistic defaults [18].
- clig.dev: mild / moderate / severe, severe needs typed confirmation [35].
- Feng et al. "Levels of Autonomy for AI Agents" (arXiv 2506.12469): L1 Operator, L2 Collaborator,
  L3 Consultant, **L4 Approver** ("agent engages user only in risky or pre-specified scenarios"),
  L5 Observer; autonomy designed independently of capability [40]. This is a *user-role* scale, a good
  vocabulary for presets; it does not classify actions.
- Amp's gated list [14] and Claude Code's auto-mode block list [2] are de facto action classifications.
- No standard scoring formula (reversibility × blast radius × visibility) found in OWASP/NIST — **gap**;
  the rubric below synthesizes the above.

### Recommended 5-level action rubric (score each plugin action once, in a registry)

Dimensions: **Reversibility** (git-undo / restorable / irreversible), **Blast radius** (this worktree /
my branch / shared branch or repo / outside the repo), **Visibility** (local / visible to collaborators /
public or triggers external systems — CI, releases, notifications).

| Level | Name | Rule of thumb | Examples in this plugin | MCP-hint analogue |
|---|---|---|---|---|
| **R0** | Observe | Read-only, any scope | `gh pr view`, `git status`, list branches, read CI logs | readOnly |
| **R1** | Local | Writes undone with git, nothing leaves the machine | edit in worktree, local commit, create local branch/worktree, delete a *merged* local worktree | !readOnly, !destructive, closed-world |
| **R2** | Shared-additive | Visible to others, additive or trivially revertible | push to *own* feature branch, open/draft PR, comment, label, request review, re-run CI | !destructive, openWorld |
| **R3** | Shared-mutating | Changes shared state; undo is possible but costly or socially visible | merge a green PR into default branch, delete a remote branch, close PRs/issues, force-push *own* branch, push tags | destructive, openWorld |
| **R4** | Irreversible / privileged | Cannot be undone, crosses trust boundaries, or changes permissions | force-push/rewrite default branch, delete repo/releases, publish a release/package, edit branch protection, **edit this plugin's own permission config**, any host-level destructive op (e.g. device erase) | destructive, openWorld, !idempotent |

Rules: unknown/unclassified action → **R4** (MCP's pessimistic default [18]). Context can raise but
never lower a level (e.g. deleting a remote branch with unmerged commits = R4; merging with red or
missing checks = R4).

---

## 5. Security pitfalls

1. **Prompt injection → self-escalation by editing the agent's own config.** CVE-2025-53773: injected
   instructions made Copilot write `"chat.tools.autoApprove": true` to `.vscode/settings.json`, then run
   commands unprompted; also `tasks.json` and MCP server injection [41, 42]. Defense seen in the field:
   protected config paths (Claude Code `.claude`/`.mcp.json` [2], Roo `.roo/` [8]).
2. **Approved-once config swapped later (MCPoison, CVE-2025-54136).** Cursor trusted an MCP config
   "indefinitely … even if it has been changed"; the fix re-prompts on every modification [43].
   → Hash the effective plugin policy; any change not made through the sanctioned path is shown and
   re-confirmed (or ignored) on next load.
3. **Elevation leaking into subagents.** Claude Code: a subagent "inherits the main conversation's
   permission mode", and under bypass/acceptEdits/auto it "runs in that same mode and Claude Code
   ignores the `permissionMode` you set" [32]. The host already leaks *its* elevation downward; a plugin
   one-shot `--perms=...` passed in a worker prompt would leak the same way unless explicitly scoped.
4. **Model-reachable elevation.** If `/plugin-config` (or `--perms=`) is model-invocable, any injected
   PR comment can ask the model to call it. The plugin's own CLAUDE.md shows `disable-model-invocation`
   is heavy (blocks subagents too) — so widen via a *human-only* channel instead (host `/config`
   userConfig UI, or a question the host never auto-answers: `AskUserQuestion` is on Claude Code's
   "no mode auto-approves" list [2]).
5. **Naming collision with host modes.** "bypass" reads as Claude Code `bypassPermissions` (which also
   skips protected-path checks [1]) and Codex/Cursor/Gemini analogues. Users will believe it changes
   host behavior, or that host bypass implies plugin bypass. The plugin layer cannot loosen host gates;
   name its levels differently.
6. **Defaults that silently widen.** New skill/action added in an update inheriting a group's "auto";
   a preset whose meaning grows between versions; Cline advises revisiting auto-approve after adding a
   server because new tools widen risk [7, secondary echo]. Gemini's rule that an approval in a higher
   mode doesn't apply downward [5] is the inverse discipline.
7. **Advisory-only gates.** A level enforced only in SKILL.md prose fails OWASP complete mediation [21];
   Claude Code itself notes a Bash deny rule "isn't a security boundary around the program" [1].
8. **Approval fatigue / trust exploitation.** Over-prompting trains rubber-stamping (Amp's argument
   [14]; OWASP ASI09 Human-Agent Trust Exploitation [23, unverified]). Prompt only at R3+, and show the
   concrete effect (which PR, which SHA, which branches) at the moment of approval.

---

## Steal / Avoid

| | Item | From | Why |
|---|---|---|---|
| **Steal** | Few named presets + per-action allow/ask/deny overrides | Claude Code, Gemini, Windsurf, Goose | Matches every surveyed tool's UX |
| **Steal** | Deny-wins evaluation, independent of specificity and scope | Claude Code [1], Windsurf [12] | Simplest to reason about; avoid priority numbers |
| **Steal** | Classify actions once, by reversibility, with pessimistic default for unknowns | OpenAI [17], MCP [18], Amp [14] | Levels stay stable as skills change |
| **Steal** | Install-time picker via `userConfig.options`, stored in user scope | Claude Code plugins [30, 31] | Native, human-only UI; repo can't widen it |
| **Steal** | Top tier not persistable — per-invocation only, user-typed | Gemini YOLO CLI-only [4] | Stops "set it once, forget it" |
| **Steal** | Repo-scope config may only narrow | VS Code trust [39], pluginConfigs scope [31] | Defeats malicious-repo widening |
| **Steal** | Anti-escalation: config changes can't exceed the caller's level | K8s `escalate`/`bind` [38] | Blocks self-escalation |
| **Steal** | "auto merge" = arm GitHub auto-merge; branch protection decides | GitHub [33, 34], OWASP #7 [21] | Downstream enforcement, cancelled on foreign pushes |
| **Steal** | Plan → approve plan → apply exactly the plan | Terraform [36], clig.dev dry-run [35] | Right shape for `cleanup` |
| **Steal** | Typed confirmation naming the target for R4 | clig.dev [35], superpowers [29] | Hard to confirm by accident |
| **Steal** | Headless: ask → deny + say which flag/config to set | clig.dev `--no-input` [35], CC `dontAsk` [1] | Never silently allow when no human is present |
| **Steal** | Protect the plugin's own config path in the existing sensitive-files guard | CC protected paths [2], Roo [8] | Direct answer to CVE-2025-53773 |
| **Avoid** | Naming a level "bypass"/"yolo" | host mode collision | Implies host-level effect it can't have |
| **Avoid** | Model-tagged "is this safe?" as the only gate | Cline `requires_approval` [7], Windsurf Auto [12] | Injectable; fine as a hint, not a boundary |
| **Avoid** | Priority-number rule ordering | Gemini [5] | Docs themselves disagree on tier bases |
| **Avoid** | Wide default (autonomous out of the box) | Goose [15] | Contradicts Anthropic/OWASP/OpenAI guidance |
| **Avoid** | Group levels that auto-apply to future skills | — | Silent widening on update |
| **Avoid** | Trusting a config after first approval regardless of later edits | Cursor MCPoison [43] | Swap attack |
| **Avoid** | Prose-only enforcement | OWASP LLM06 [21] | Not complete mediation |

---

## Recommended model for this plugin

1. **Action registry** (one file, plugin-owned, not user-editable): every gated action
   (`pr.merge`, `branch.delete.remote`, `branch.force_push.own`, `release.publish`, `config.widen` …)
   with its R-level. Unlisted ⇒ R4.
2. **Presets = a ceiling on auto-approved R-level** (rename away from strict/auto/bypass):
   - `supervised` (default): auto ≤ R1, ask R2–R4.
   - `standard`: auto ≤ R2, ask R3, R4 typed-confirm.
   - `unattended`: auto ≤ R3 **only where downstream policy also gates** (merge = `gh pr merge --auto`
     behind branch protection; remote-branch delete only if fully merged), R4 typed-confirm, never auto.
   R4 is never auto-approved by any preset or flag.
3. **Overrides**: per-action and per-skill `allow|ask|deny` in user scope; **deny wins** across scopes;
   a repo-committed file may only add `ask`/`deny`.
4. **Per-invocation override** (`/pr-dev 42 --level=unattended`): honored only when present in the
   user's typed prompt (capture with a `UserPromptSubmit` hook into a one-shot ticket under
   `${CLAUDE_PLUGIN_DATA}`, bound to skill + target + short TTL), consumed on use, **not inherited** by
   subagents/workers unless the orchestrator re-scopes it to a named task. Narrowing flags are always
   honored.
5. **`/plugin-config`**: may narrow freely; widening requires a human-only confirmation
   (`AskUserQuestion` on Claude Code; the host `/config` userConfig UI; elsewhere a typed confirmation)
   and can never set anything to R4-auto. The policy file is added to `guard-sensitive-files.sh` so
   Edit/Write/Bash cannot touch it; the effective policy is hashed and an out-of-band change is shown
   and ignored until re-confirmed.
6. **Enforcement in hooks, not just prose**: the existing PreToolUse guards read the effective level
   (`CLAUDE_PLUGIN_OPTION_*` / policy file) and block `gh pr merge`, `git push --delete`, force pushes
   above the ceiling. Skills render the same decision for UX. Platforms without hooks degrade to
   `supervised` explicitly (per `core/policies/safety.md`).
7. **Headless**: any `ask` with no interactive human ⇒ deny with the exact setting/flag that would
   allow it.
8. **Every approval prompt shows the concrete effect** (PR #, head SHA, check status, branch list).

### Open questions
- Does the host expose "this skill invocation came from the user's typed prompt" on every platform, or
  only via a Claude Code `UserPromptSubmit` hook? (Determines whether one-shot elevation is portable.)
- Is `pluginConfigs` truly ignored in project/local settings? Index row says "User or managed" [31];
  the full entry was not read.
- Can a Codex/Cursor/Gemini/OpenCode hook read an equivalent of `CLAUDE_PLUGIN_OPTION_*`, or does the
  policy file have to be the single cross-platform source?
- Should `unattended` require the repo to have branch protection + auto-merge enabled, refusing to
  widen otherwise?
- OWASP Agentic Top 10 entry text and mitigations not read from the primary PDF.

---

## Sources
1. https://code.claude.com/docs/en/permissions
2. https://code.claude.com/docs/en/permission-modes
3. https://developers.openai.com/codex/concepts/sandboxing
4. https://geminicli.com/docs/reference/configuration/
5. https://geminicli.com/docs/reference/policy-engine/
6. https://cursor.com/docs/agent/security/run-modes
7. https://docs.cline.bot/features/auto-approve
8. https://roocodeinc.github.io/Roo-Code/features/auto-approving-actions
9. https://aider.chat/docs/config/options.html
10. https://docs.github.com/en/copilot/responsible-use/copilot-coding-agent
11. https://github.blog/changelog/2026-03-13-optionally-skip-approval-for-copilot-coding-agent-actions-workflows/
12. https://docs.windsurf.com/windsurf/terminal ; https://docs.devin.ai/desktop/terminal
13. https://ampcode.com/manual/appendix/legacy-permissions-rules.txt
14. https://ampcode.com/notes/permissions
15. https://goose-docs.ai/docs/guides/managing-tools/goose-permissions
16. https://docs.continue.dev/ide-extensions/agent/how-to-customize
17. https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf (pp. 26, 31)
18. https://modelcontextprotocol.io/specification/2025-11-25/schema#toolannotations
19. https://modelcontextprotocol.io/specification/2025-06-18/server/tools
20. https://codex.danielvaughan.com/2026/05/27/codex-cli-mcp-readonlyhint-concurrent-tool-execution-annotations-parallelism/ ; https://sunpeak.ai/blogs/testing-mcp-tool-annotations (secondary)
21. https://genai.owasp.org/llmrisk/llm062025-excessive-agency/
22. https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/
23. https://www.humansecurity.com/learn/blog/owasp-top-10-agentic-applications/ ; https://goteleport.com/blog/owasp-top-10-agentic-applications (secondary)
24. https://www.nist.gov/node/1872381 ; https://labs.cloudsecurityalliance.org/research/csa-research-note-nist-caisi-ai-agent-security-agenda-2026-2/
25. https://www.anthropic.com/news/our-framework-for-developing-safe-and-trustworthy-agents
26. https://ai.meta.com/blog/practical-ai-agent-security/
27. https://simonwillison.net/2025/Nov/2/new-prompt-injection-papers/
28. https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/
29. https://github.com/obra/superpowers/blob/main/skills/finishing-a-development-branch/SKILL.md
30. https://code.claude.com/docs/en/plugins-reference#user-configuration
31. https://code.claude.com/docs/en/settings-reference#pluginconfigs
32. https://code.claude.com/docs/en/sub-agents
33. https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request
34. https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue
35. https://clig.dev/
36. https://developer.hashicorp.com/terraform/cli/commands/apply
37. https://kubernetes.io/docs/reference/access-authn-authz/authorization/
38. https://kubernetes.io/docs/reference/access-authn-authz/rbac/
39. https://code.visualstudio.com/docs/editing/workspaces/workspace-trust
40. https://arxiv.org/abs/2506.12469
41. https://embracethered.com/blog/posts/2025/github-copilot-remote-code-execution-via-prompt-injection/ (cited via secondary; not fetched)
42. https://cybersecuritynews.com/github-copilot-rce-vulnerability (secondary)
43. https://nvd.nist.gov/vuln/detail/CVE-2025-54136 ; https://thehackernews.com/2025/08/cursor-ai-code-editor-vulnerability.html

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/tamirs-superpowers/issues/new/choose">Open an Issue</a></p>
