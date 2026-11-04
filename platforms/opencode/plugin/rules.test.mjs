// rules.test.mjs — unit tests for the pure decision functions in rules.ts.
//
// Runs with plain Node (`node --test rules.test.mjs`): Node 22.18+ strips the
// types from rules.ts on import, so no OpenCode host, no npm install and no
// build step are needed. tests/test-opencode-v2.sh runs this file.
//
// The ADR 004 tests at the end also read core/permissions/actions.json and
// hooks/lib/write-targets.py (the protected-path table must equal both), read
// guard.ts as text (what it must never call), and run hooks/permission-guard.sh on
// the payload pgPayload builds, through a wrapper the resolver trusts for its test
// root (no real permission file is read). Those skip when bash, jq or python3 is missing.
import { test } from "node:test"
import assert from "node:assert/strict"
import { execFileSync, spawnSync } from "node:child_process"
import { chmodSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import path from "node:path"
import { fileURLToPath } from "node:url"
import {
  activeObjectiveId,
  claimKey,
  deliverAsDeny,
  effectiveSegments,
  githubMcpTool,
  gitPushes,
  globTailRegex,
  inspectClaim,
  isAgentWorkspacePath,
  judgeEdit,
  judgePush,
  opencodeReason,
  PG_MCP_PREFIX,
  pgEnv,
  pgPayload,
  pgVerdict,
  PROTECTED_PATHS,
  PROTECTED_REMEDY,
  protectedHits,
  protectedReason,
  sensitiveReason,
  shellSegments,
  shellWriteTargets,
} from "./rules.ts"

const HERE = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.resolve(HERE, "..", "..", "..")

const MAIN = "/work/proj"
const facts = (over = {}) => ({ mainRoot: MAIN, objectiveId: "obj-1", claudeConfigRoot: "/work/dot/.claude", globalWorktreeRoot: "/work/dot/.claude/worktrees", ...over })

test("main-checkout write under an active objective is denied, naming the objective worktrees", () => {
  const d = judgeEdit(`${MAIN}/src/app.ts`, facts())
  assert.equal(d.effect, "deny")
  assert.match(d.reason, /Objective 'obj-1' is active/)
  assert.match(d.reason, /\.agent-worktrees\/obj-1\/task-NNN/)
})

test("the same write with no active objective is allowed (no destination to name)", () => {
  assert.equal(judgeEdit(`${MAIN}/src/app.ts`, facts({ objectiveId: null })).effect, "allow")
})

test("writes inside an objective worktree, a legacy worktree, or the Claude config dir are allowed", () => {
  assert.equal(judgeEdit(`${MAIN}/.agent-worktrees/obj-1/task-001/src/app.ts`, facts()).effect, "allow")
  assert.equal(judgeEdit(`/elsewhere/wt/obj-1/task-001/x.ts`, facts({ agentWorktreeRoot: "/elsewhere/wt" })).effect, "allow")
  assert.equal(judgeEdit(`${MAIN}/.claude/.worktrees/slug/x.ts`, facts()).effect, "allow")
  assert.equal(judgeEdit(`/work/dot/.claude/worktrees/proj/slug/x.ts`, facts()).effect, "allow")
  assert.equal(judgeEdit(`/work/dot/.claude/settings.json`, facts()).effect, "allow")
  assert.equal(judgeEdit(`/tmp/notes.txt`, facts()).effect, "allow")
  assert.equal(judgeEdit(`/tmp/notes.txt`, facts({ mainRoot: null })).effect, "allow")
  assert.equal(isAgentWorkspacePath(`${MAIN}/src/app.ts`, facts()), false)
})

test("sensitive paths are denied regardless of the tool doing the writing", () => {
  assert.match(sensitiveReason(`${MAIN}/package-lock.json`), /lockfile/)
  assert.match(sensitiveReason(`${MAIN}/Cargo.lock`), /lockfile/)
  assert.match(sensitiveReason(`${MAIN}/.github/workflows/ci.yml`), /R4 action \(workflow\.edit\): ask the user to approve this exact change/)
  assert.match(sensitiveReason(`${MAIN}/.yarn/releases/yarn-4.cjs`), /vendored Yarn/)
  assert.match(sensitiveReason(`${MAIN}/src/components/ui/button.tsx`, { repoRoot: MAIN, hasShadcnConfig: true }), /shadcn/)
  assert.equal(sensitiveReason(`${MAIN}/src/components/ui/button.tsx`, { repoRoot: MAIN, hasShadcnConfig: false }), null)
  assert.match(sensitiveReason(`${MAIN}/dist/bundle.js`, { repoRoot: MAIN, gitIgnored: true }), /build output/)
  assert.equal(sensitiveReason(`${MAIN}/dist/bundle.js`, { repoRoot: MAIN, gitIgnored: false }), null)
  assert.equal(sensitiveReason(`${MAIN}/dist/bundle.js`, { repoRoot: MAIN, gitIgnored: true }, "delete"), null)
  assert.equal(sensitiveReason(`${MAIN}/src/app.ts`), null)
  assert.match(sensitiveReason(`${MAIN}/go.sum`, {}, "write", "tee"), /\(via: tee\)/)
})

test("ordinary edits are allowed end to end", () => {
  assert.equal(sensitiveReason(`${MAIN}/README.md`), null)
  assert.equal(judgeEdit(`${MAIN}/README.md`, facts({ objectiveId: null })).effect, "allow")
})

test("active objective: env override wins, else the first status=active objective.json", () => {
  const entries = [
    { id: "b-done", json: JSON.stringify({ id: "b-done", status: "completed" }) },
    { id: "c-live", json: JSON.stringify({ id: "c-live", status: "active" }) },
    { id: "a-bad", json: "not json" },
  ]
  assert.equal(activeObjectiveId(entries, undefined), "c-live")
  assert.equal(activeObjectiveId(entries, "forced"), "forced")
  assert.equal(activeObjectiveId([{ id: "x", json: JSON.stringify({ status: "planned" }) }], undefined), null)
  assert.equal(activeObjectiveId([{ id: "noid", json: JSON.stringify({ status: "active" }) }], undefined), "noid")
})

test("shell segments: quoted text and heredoc bodies are arguments, never commands", () => {
  assert.deepEqual(shellSegments(`git commit -m "fixed: git push -q origin main"`), [["git", "commit", "-m", "fixed: git push -q origin main"]])
  assert.deepEqual(shellSegments(`git commit -m "wip" && git push origin dev`), [["git", "commit", "-m", "wip"], ["git", "push", "origin", "dev"]])
  assert.deepEqual(shellSegments("cat <<EOF\ngit push origin main\nEOF\necho ok"), [["cat"], ["echo", "ok"]])
  assert.deepEqual(shellSegments("git push origin br 2>&1"), [["git", "push", "origin", "br"]])
  assert.deepEqual(effectiveSegments("FOO=1 sudo -n git push origin x"), [["git", "push", "origin", "x"]])
  assert.deepEqual(effectiveSegments(`bash -c 'git push origin y'`), [["git", "push", "origin", "y"]])
})

test("git push destinations and force detection", () => {
  assert.deepEqual(gitPushes("git status", "main"), [])
  assert.deepEqual(gitPushes("git push origin feature", "main"), [{ dests: ["feature"], force: false }])
  assert.deepEqual(gitPushes("git push", "main"), [{ dests: ["main"], force: false }])
  assert.deepEqual(gitPushes("git push origin HEAD:release", "main"), [{ dests: ["release"], force: false }])
  assert.deepEqual(gitPushes("git -C /x push -u origin a b", null), [{ dests: ["a", "b"], force: false }])
  assert.equal(gitPushes("git push --force origin main", "main")[0].force, true)
  assert.equal(gitPushes("git push -f origin main", "main")[0].force, true)
  assert.equal(gitPushes("git push --force-with-lease=main origin main", "main")[0].force, true)
  assert.equal(gitPushes("git push origin +main", "main")[0].force, true)
  assert.equal(gitPushes("git push -q origin main", "main")[0].force, false)
  assert.match(gitPushes("git push --all", "main")[0].error, /--all/)
  assert.match(gitPushes("git push", null)[0].error, /could not be resolved/)
  assert.match(gitPushes("git push origin 'refs/heads/*'", "main")[0].error, /does not resolve/)
})

test("claim inspection mirrors claim_inspect: FREE / MINE / LIVE / STALE / ERROR", () => {
  const clock = { now: 1_000_000, host: "box", pidAlive: () => true, staleSeconds: 900 }
  const claim = (over = {}) => JSON.stringify({ schema: "agent-work-claim/1", agent_id: "claude-code:s1", tool: "claude-code", host: "box", pid: 42, heartbeat_at: 999_900, ...over })
  assert.equal(inspectClaim(null, "me", clock).status, "FREE")
  assert.equal(inspectClaim(claim({ agent_id: "me" }), "me", clock).status, "MINE")
  assert.equal(inspectClaim(claim(), "me", clock).status, "LIVE")
  assert.equal(inspectClaim(claim({ heartbeat_at: 1 }), "me", clock).status, "STALE")
  assert.equal(inspectClaim(claim(), "me", { ...clock, pidAlive: () => false }).status, "STALE")
  assert.equal(inspectClaim(claim({ host: "other" }), "me", { ...clock, pidAlive: () => false }).status, "LIVE")
  assert.equal(inspectClaim("{not json", "me", clock).status, "ERROR")
  assert.equal(inspectClaim(JSON.stringify({ tool: "x" }), "me", clock).status, "ERROR")
  assert.equal(claimKey("git:owner/repo@feature/x"), "git_owner_repo_feature_x")
})

test("judgePush: force push refused, LIVE claim by another agent refused, ERROR fails loud, own/stale/free allowed", () => {
  const base = { repoSlug: "owner/repo", fallbackBranch: "main", me: "opencode:s1" }
  const inspect = (status, extra = {}) => () => ({ status, detail: "d", holder: "claude-code:s9", tool: "claude-code", ...extra })
  assert.equal(judgePush("git status", { ...base, inspect: inspect("LIVE") }).effect, "allow")
  assert.match(judgePush("git push --force origin main", { ...base, inspect: inspect("FREE") }).reason, /force push to 'main' refused/)
  assert.match(judgePush("git push origin feature", { ...base, inspect: inspect("LIVE") }).reason, /another agent is actively working on git:owner\/repo@feature/)
  assert.match(judgePush("git push origin feature", { ...base, inspect: inspect("ERROR") }).reason, /cannot determine/)
  assert.equal(judgePush("git push origin feature", { ...base, inspect: inspect("MINE") }).effect, "allow")
  assert.equal(judgePush("git push origin feature", { ...base, inspect: inspect("STALE") }).effect, "allow")
  assert.equal(judgePush("git push origin feature", { ...base, inspect: inspect("FREE") }).effect, "allow")
  assert.match(judgePush("git push --all", { ...base, inspect: inspect("FREE") }).reason, /cannot be checked/)
  assert.match(judgePush("git push origin feature", { ...base, repoSlug: null, inspect: inspect("FREE") }).reason, /could not be identified/)
  // The integrator may take a worker branch of its own objective even while the worker's claim is live.
  assert.equal(judgePush("git push origin worker/obj-1/001", { ...base, inspect: inspect("LIVE"), integratorObjectiveId: "obj-1" }).effect, "allow")
  assert.equal(judgePush("git push origin worker/obj-2/001", { ...base, inspect: inspect("LIVE"), integratorObjectiveId: "obj-1" }).effect, "deny")
  // A quoted push in a commit message is text, not an invocation.
  assert.equal(judgePush(`git commit -m "git push --force origin main"`, { ...base, inspect: inspect("LIVE") }).effect, "allow")
})

test("shell write targets: redirects, tee, sed -i, cp/mv, rm", () => {
  const paths = (cmd) => shellWriteTargets(cmd).map((t) => `${t.kind}:${t.path}`)
  assert.deepEqual(paths("echo hi > out.txt"), ["write:out.txt"])
  assert.deepEqual(paths("echo hi >> .github/workflows/ci.yml"), ["write:.github/workflows/ci.yml"])
  assert.deepEqual(paths("make 2>/dev/null"), [])
  assert.deepEqual(paths("cmd 2>&1"), [])
  assert.deepEqual(paths("echo x | tee -a package-lock.json"), ["write:package-lock.json"])
  assert.deepEqual(paths("sed -i 's/a/b/' go.sum"), ["write:go.sum"])
  assert.deepEqual(paths("sed -i -e 's/a/b/' a.txt b.txt"), ["write:a.txt", "write:b.txt"])
  assert.deepEqual(paths("cp src.js dist/bundle.js"), ["write:dist/bundle.js"])
  assert.deepEqual(paths("rm -rf dist/"), ["delete:dist/"])
  assert.deepEqual(paths(`git commit -m "see > notes"`), [])
  assert.deepEqual(paths("grep -r 'pattern' src"), [])
})

// ------------------------------------------------------------- ADR 004 ---

test("no deny text points at a bypass: no GitHub MCP write tool, no PM_ALLOW_PROTECTED (D10.5)", () => {
  const texts = [
    sensitiveReason(`${MAIN}/package-lock.json`),
    sensitiveReason(`${MAIN}/.yarn/releases/yarn-4.cjs`),
    sensitiveReason(`${MAIN}/.github/workflows/ci.yml`),
    sensitiveReason(`${MAIN}/src/components/ui/button.tsx`, { repoRoot: MAIN, hasShadcnConfig: true }),
    sensitiveReason(`${MAIN}/dist/bundle.js`, { repoRoot: MAIN, gitIgnored: true }),
    PROTECTED_REMEDY,
  ]
  for (const t of texts) {
    assert.ok(t)
    assert.doesNotMatch(t, /create_or_update_file|PM_ALLOW_PROTECTED|GitHub MCP/)
  }
  const src = readFileSync(path.join(HERE, "rules.ts"), "utf8")
  assert.doesNotMatch(src, /create_or_update_file/)
})

test("the protected-path table equals core/permissions/actions.json and write-targets.py's fallback", () => {
  const cat = JSON.parse(readFileSync(path.join(ROOT, "core", "permissions", "actions.json"), "utf8"))
  const byId = Object.fromEntries(cat.actions.map((a) => [a.id, a]))
  for (const id of Object.keys(PROTECTED_PATHS)) {
    assert.deepEqual([...PROTECTED_PATHS[id]], byId[id].equivalents.paths, `${id} differs from actions.json`)
  }
  const py = readFileSync(path.join(ROOT, "hooks", "lib", "write-targets.py"), "utf8")
  const block = py.slice(py.indexOf("FALLBACK_PROTECTED = {"), py.indexOf("GLOB_CHARS"))
  for (const id of Object.keys(PROTECTED_PATHS)) {
    const m = new RegExp(`"${id.replace(".", "\\.")}": \\[([^\\]]*)\\]`).exec(block)
    assert.ok(m, `write-targets.py has no ${id} fallback`)
    assert.deepEqual([...m[1].matchAll(/"([^"]+)"/g)].map((x) => x[1]), [...PROTECTED_PATHS[id]], `${id} differs from write-targets.py`)
  }
})

const H = "/Users/you"
const PLUG = "/opt/ts"
const pfacts = (over = {}) => ({
  homes: [H],
  pluginRoots: [{ root: PLUG, sourceCheckout: false }],
  isRepoRoot: (d) => d === "/work/proj",
  ...over,
})

test("glob tails: ** crosses directories, * does not, a /** tail also matches the directory itself", () => {
  const rx = (t) => new RegExp("^" + globTailRegex(t) + "$")
  assert.ok(rx(".config/opencode/**").test(".config/opencode/opencode.json"))
  assert.ok(rx(".config/opencode/**").test(".config/opencode"))
  assert.ok(rx(".config/opencode/**").test(".config/opencode/a/b"))
  assert.ok(rx(".claude/settings*.json").test(".claude/settings.local.json"))
  assert.ok(!rx(".claude/settings*.json").test(".claude/x/settings.json"))
  assert.ok(!rx(".gitconfig").test(".gitconfigx"))
})

test("protected paths: home, repo and plugin-root rules, with deny over ask", () => {
  const hit = (p, over, containing) => protectedHits([p], pfacts(over), containing).map((h) => `${h.mode}:${h.id}`)
  assert.deepEqual(hit(`${H}/.config/tamirs-superpowers/permissions.json`), ["deny:policy.edit"])
  assert.deepEqual(hit(`${H}/.gemini/settings.json`), ["deny:policy.edit"])
  assert.deepEqual(hit(`${H}/.config/opencode/opencode.json`), ["deny:policy.edit"])
  assert.deepEqual(hit(`${H}/.gitconfig`), ["deny:policy.edit"])
  assert.deepEqual(hit("/work/proj/opencode.json"), ["deny:policy.edit"])
  assert.deepEqual(hit("/work/proj/.opencode/agents/x.md"), ["deny:policy.edit"])
  assert.deepEqual(hit("/work/proj/.tamirs-superpowers/permissions.json"), ["deny:policy.edit"])
  assert.deepEqual(hit("/work/proj/.git/hooks/pre-commit"), ["deny:config.global.write"])
  assert.deepEqual(hit("/work/proj/.git/config"), ["deny:config.global.write"])
  // {repo} means a repository root, not any directory: a nested opencode.json is ordinary.
  assert.deepEqual(hit("/work/proj/platforms/opencode/templates/opencode.json"), [])
  assert.deepEqual(hit("/work/proj/src/app.ts"), [])
  assert.deepEqual(hit(`${H}/.gemini/tmp/plans/plan.md`), [])
  // The running plugin's guard files: deny when installed, an R4 ask in a source checkout.
  assert.deepEqual(hit(`${PLUG}/hooks/permission-guard.sh`), ["deny:policy.edit"])
  assert.deepEqual(hit(`${PLUG}/hooks/lib/x.sh`, { pluginRoots: [{ root: PLUG, sourceCheckout: true }] }), ["ask:policy.edit"])
  assert.deepEqual(hit(`${PLUG}/scripts/resolve-permission.sh`), ["deny:policy.edit"])
  assert.deepEqual(hit(`${PLUG}/scripts/other.sh`), [])
  // Deleting a directory that holds a protected home path counts as deleting it; a repo root does not.
  assert.deepEqual(
    protectedHits([`${H}/.config`], pfacts(), true).map((h) => h.pattern),
    ["{home}/.config/tamirs-superpowers/**", "{home}/.config/opencode/**", "{home}/.config/gh/**"],
  )
  assert.deepEqual(hit(`${H}/.config`), [], "without containing, the directory itself is not one of the paths")
  assert.deepEqual(hit("/work/proj", {}, true), [])
  // A second spelling (the realpath) is judged too.
  assert.deepEqual(protectedHits(["/tmp/link", `${H}/.gitconfig`], pfacts()).map((h) => h.form), [`${H}/.gitconfig`])
})

test("protectedReason: R4 wording, deny beats ask, the realpath named, no bypass named", () => {
  const d = protectedReason(`${H}/.config/opencode/opencode.json`, [`${H}/.config/opencode/opencode.json`], pfacts(), "write", "tee")
  assert.equal(d.mode, "deny")
  assert.match(d.reason, /^BLOCKED: '.*' would be written, and it is protected as policy\.edit \(R4; matches \{home\}\/\.config\/opencode\/\*\*\)\. \(via: tee\)/)
  assert.ok(d.reason.endsWith(PROTECTED_REMEDY))
  const r = protectedReason("/tmp/x", ["/tmp/x", `${H}/.gitconfig`], pfacts(), "link", "ln")
  assert.match(r.reason, /resolves to '\/Users\/you\/\.gitconfig'.*would become reachable through a new link/)
  const a = protectedReason(`${PLUG}/hooks/x.sh`, [`${PLUG}/hooks/x.sh`], pfacts({ pluginRoots: [{ root: PLUG, sourceCheckout: true }] }))
  assert.equal(a.mode, "ask")
  assert.match(a.reason, /^R4 ASK: .*source checkout/)
  const both = protectedReason(`${PLUG}/hooks/x.sh`, [`${PLUG}/hooks/x.sh`, `${H}/.gitconfig`], pfacts({ pluginRoots: [{ root: PLUG, sourceCheckout: true }] }))
  assert.equal(both.mode, "deny")
  assert.equal(protectedReason("/work/proj/src/a.ts", ["/work/proj/src/a.ts"], pfacts()), null)
})

test("an R4 ask leaves OpenCode as a deny (D8: --auto approves a plugin ask)", () => {
  const d = deliverAsDeny("R4 ASK: x.")
  assert.equal(d.effect, "deny")
  assert.match(d.reason, /delivered as a deny \(ADR 004 D8\)/)
})

test("shell write targets: mv and ln sources, -t DIR", () => {
  const paths = (cmd) => shellWriteTargets(cmd).map((t) => `${t.kind}:${t.path}${t.linkAt ? "@" + t.linkAt : ""}`)
  assert.deepEqual(paths("mv ~/.gitconfig /tmp/g"), ["write:/tmp/g", "move:~/.gitconfig"])
  assert.deepEqual(paths("ln -s ../hooks/permission-guard.sh x.sh"), ["write:x.sh", "link:../hooks/permission-guard.sh@x.sh"])
  assert.deepEqual(paths("ln /a/b /c/d"), ["write:/c/d", "link:/a/b"])
  assert.deepEqual(paths("cp -t dist a.js b.js"), ["write:dist"])
  assert.deepEqual(paths("mv -t dist a.js b.js"), ["write:dist", "move:a.js", "move:b.js"])
  assert.deepEqual(paths("cp src.js dist/bundle.js"), ["write:dist/bundle.js"])
})

test("GitHub MCP actions map onto the guard's tool names; nothing else does", () => {
  assert.equal(githubMcpTool("github_merge_pull_request"), "merge_pull_request")
  assert.equal(githubMcpTool("github_create_or_update_file"), "create_or_update_file")
  assert.equal(githubMcpTool("shell"), null)
  assert.equal(githubMcpTool("edit"), null)
  assert.equal(githubMcpTool("gitlab_merge"), null)
  assert.equal(githubMcpTool("github_"), null)
})

test("pgPayload: the Codex dialect (deny only, no option store), Claude tool names", () => {
  const sh = pgPayload({ kind: "shell", command: "gh pr create", cwd: "/w" }, "s1")
  assert.deepEqual(sh, { session_id: "s1", turn_id: "opencode", hook_event_name: "PreToolUse", cwd: "/w", tool_name: "Bash", tool_input: { command: "gh pr create" } })
  const m = pgPayload({ kind: "mcp", tool: "merge_pull_request", input: { pullNumber: 3 }, cwd: "/w" }, "")
  assert.equal(m.tool_name, PG_MCP_PREFIX + "merge_pull_request")
  assert.deepEqual(m.tool_input, { pullNumber: 3 })
  assert.equal(m.session_id, "opencode")
  assert.deepEqual(pgPayload({ kind: "mcp", tool: "x", input: "nope", cwd: "/w" }, "s").tool_input, {})
})

test("pgEnv drops what would make the guard judge as another host", () => {
  const e = pgEnv({ PATH: "/bin", GEMINI_SESSION_ID: "g", GEMINI_PROJECT_DIR: "/p", GEMINI_CWD: "/c", CODEX_HOME: "/x", HOME: "/h", U: undefined })
  assert.deepEqual(e, { PATH: "/bin", HOME: "/h" })
})

test("pgVerdict: {} is the only allow; deny keeps its reason; ask, garbage and silence are denies", () => {
  assert.equal(pgVerdict("{}\n").effect, "allow")
  assert.equal(pgVerdict('{"hookSpecificOutput":{"permissionDecision":"allow"}}').effect, "allow")
  const reason = "tamirs-superpowers permission guard (ADR 004): denied pr.create (R2). asks: level supervised ceiling for R2; codex cannot carry a hook ask (it would run the call unchecked), so the ask is delivered as a deny (D8). To allow it: codex has no host-attested channel: x."
  const d = pgVerdict(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: reason } }))
  assert.equal(d.effect, "deny")
  assert.match(d.reason, /opencode cannot carry a plugin ask \(`opencode --auto` approves it, measured O1\)/)
  assert.match(d.reason, /opencode has no host-attested channel/)
  assert.doesNotMatch(d.reason, /codex/)
  assert.equal(pgVerdict('{"hookSpecificOutput":{"permissionDecision":"ask","permissionDecisionReason":"r"}}').effect, "deny")
  for (const bad of ["", "not json", "[]", "null", '{"systemMessage":"x"}', '{"hookSpecificOutput":{}}']) {
    assert.equal(pgVerdict(bad).effect, "deny", `${JSON.stringify(bad)} must deny`)
  }
  assert.equal(opencodeReason("plain"), "plain")
})

test("guard.ts never widens: no session.update, never an allow, e.effect only from the guard's Decision, ask only via opencodeVerdict (D8, D10.4)", () => {
  const g = readFileSync(path.join(HERE, "guard.ts"), "utf8")
  assert.doesNotMatch(g, /\.session\.update\(/)
  assert.doesNotMatch(g, /permission\.assert\(/)
  // An allow would widen a configured ask (O1e); guard.ts never sets one, in any spelling.
  assert.doesNotMatch(g, /effect\s*=\s*"allow"/)
  assert.doesNotMatch(g, /effect\s*=\s*ALLOW\b/)
  // An ask is not a widening: it is the guard's own R2 answer (D8 OpenCode row). The evaluate
  // hook copies e.effect only from a Decision that is not an allow, or sets a fail-closed deny.
  const sets = [...g.matchAll(/\be\.effect\s*=(?!=)\s*([^\n;]+)/g)].map((m) => m[1].trim())
  assert.deepEqual([...new Set(sets)].sort(), ['"deny"', "d.effect"], `e.effect is set from: ${sets.join(", ")}`)
  assert.match(g, /if \(d\.effect !== "allow"\) \{[^}]*?e\.effect = d\.effect/)
  // The only ask literal is opencodeVerdict's, which keeps the guard's own ask and hands
  // everything else to pgVerdict (fail closed).
  const asks = [...g.matchAll(/effect:\s*"ask"/g)]
  assert.equal(asks.length, 1, "exactly one ask literal in guard.ts")
  const fn = g.indexOf("function opencodeVerdict(")
  const end = g.indexOf("\nfunction ", fn + 1)
  assert.ok(fn >= 0 && asks[0].index > fn && asks[0].index < end, "the ask literal is inside opencodeVerdict")
  assert.match(g.slice(fn, end), /permissionDecision === "ask"/)
  assert.match(g.slice(fn, end), /return pgVerdict\(stdout\)/)
  assert.doesNotMatch(g, /effect\s*=\s*"ask"/)
  assert.match(g, /execFileSync\("bash", \[PERMISSION_GUARD\]/)
  assert.match(g, /path\.join\(PLUGIN_ROOT, "hooks", "permission-guard\.sh"\)/)
  // The legacy switch is read once and never gates the permission guard call.
  assert.match(g, /const legacy = process\.env\.TAMIRS_OPENCODE_GUARD !== "0"/)
  assert.doesNotMatch(g, /TAMIRS_OPENCODE_GUARD === "0"\) return/)
})

// --- hooks/permission-guard.sh on the payload pgPayload builds (hermetic resolver) ---
const have = (bin) => spawnSync("sh", ["-c", `command -v ${bin}`]).status === 0
const canRun = have("bash") && have("jq") && have("python3")

function pgHarness() {
  const t = realpathSync(mkdtempSync(path.join(tmpdir(), "ts-oc-pg-")))
  chmodSync(t, 0o700)
  const ph = path.join(t, "passwd-home")
  execFileSync("mkdir", ["-m", "700", ph])
  // The resolver honours TAMIRS_PERMISSION_TEST_ROOT only under an ancestor running a file of this name.
  const w = path.join(t, "test-resolve-permission.sh")
  writeFileSync(w, '#!/usr/bin/env bash\n"$@"\nrc=$?\nexit "$rc"\n')
  const env = pgEnv({ ...process.env, TAMIRS_PERMISSION_TEST_ROOT: ph, HOME: path.join(t, "env-home") })
  delete env.TS_PERMISSION_LEVEL
  delete env.TAMIRS_AUTO_MERGE
  const raw = (payload) =>
    execFileSync("bash", [w, "bash", path.join(ROOT, "hooks", "permission-guard.sh")], {
      input: JSON.stringify(payload),
      encoding: "utf8",
      env,
      stdio: ["pipe", "pipe", "ignore"],
    })
  const run = (call) => pgVerdict(raw(pgPayload(call, "s")))
  const home = execFileSync("bash", [w, "bash", path.join(ROOT, "scripts", "resolve-permission.sh"), "repo.read", "--json"], { encoding: "utf8", env })
  return { t, run, raw, homeSource: JSON.parse(home).home_source }
}

test("the real permission guard behind pgPayload/pgVerdict (Codex dialect): allows ordinary calls, never asks", { skip: !canRun && "bash, jq or python3 missing" }, () => {
  const h = pgHarness()
  try {
    assert.equal(h.homeSource, "test-root", "the resolver must read the temp passwd home, never the real one")
    const sh = (command) => h.run({ kind: "shell", command, cwd: h.t })
    assert.equal(sh("ls -la").effect, "allow")
    assert.equal(sh("git status").effect, "allow")
    for (const c of ["gh pr create --fill", "gh repo create me/x --private", "claude -p hi", "gh frobnicate --now", "gemini extensions config tamirs-superpowers TS_PERMISSION_LEVEL"]) {
      const d = sh(c)
      assert.equal(d.effect, "deny", `${c} must be a deny at supervised on OpenCode`)
      assert.match(d.reason, /tamirs-superpowers permission guard/)
      assert.doesNotMatch(d.reason, /\bcodex\b/)
    }
    const mcp = (tool, input) => h.run({ kind: "mcp", tool, input, cwd: h.t })
    assert.equal(mcp("get_file_contents", { owner: "o", repo: "r", path: "README.md" }).effect, "allow")
    assert.equal(mcp("merge_pull_request", { owner: "o", repo: "r", pullNumber: 1 }).effect, "deny")
    assert.equal(mcp("delete_repository", { owner: "o", repo: "r" }).effect, "deny")
    assert.equal(mcp("no_such_tool", {}).effect, "deny", "an unknown tool of the server is UNCLASSIFIED (R4)")
  } finally {
    rmSync(h.t, { recursive: true, force: true })
  }
})

test("the real permission guard in the OpenCode dialect (pgPayload + host opencode, no turn_id): R2 asks, R3/R4 deny, never allow", { skip: !canRun && "bash, jq or python3 missing" }, () => {
  const h = pgHarness()
  try {
    assert.equal(h.homeSource, "test-root", "the resolver must read the temp passwd home, never the real one")
    // guard.ts's opencodePayload: pgPayload without the Codex marker, plus the host key.
    const oc = (call) => {
      const p = { ...pgPayload(call, "s"), host: "opencode" }
      delete p.turn_id
      return JSON.parse(h.raw(p) || "{}")
    }
    const decision = (o) => (o.hookSpecificOutput || {}).permissionDecision || "allow"
    const sh = (command) => oc({ kind: "shell", command, cwd: h.t })
    assert.equal(decision(sh("ls -la")), "allow")
    const create = sh("gh pr create --fill")
    assert.equal(decision(create), "ask", "an R2 call is the guard's own ask on OpenCode (D8)")
    assert.match(create.hookSpecificOutput.permissionDecisionReason, /tamirs-superpowers permission guard/)
    for (const c of ["gh pr merge 1 --squash", "gh pr merge 1 --admin", "gh repo delete me/x --yes"]) {
      assert.equal(decision(sh(c)), "deny", `${c} must be a deny on OpenCode (R3/R4: --auto would approve an ask, O1c)`)
    }
    const mcp = (tool, input) => decision(oc({ kind: "mcp", tool, input, cwd: h.t }))
    assert.equal(mcp("merge_pull_request", { owner: "o", repo: "r", pullNumber: 1 }), "deny")
    assert.equal(mcp("no_such_tool", {}), "deny", "UNCLASSIFIED is never an ask")
    // Nothing the guard answers in this dialect is an explicit allow: {} is its only allow.
    for (const o of [create, sh("ls -la"), sh("gh pr merge 1 --squash")]) {
      assert.notEqual((o.hookSpecificOutput || {}).permissionDecision, "allow")
    }
  } finally {
    rmSync(h.t, { recursive: true, force: true })
  }
})
