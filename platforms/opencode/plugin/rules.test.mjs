// rules.test.mjs — unit tests for the pure decision functions in rules.ts.
//
// Runs with plain Node (`node --test rules.test.mjs`): Node 22.18+ strips the
// types from rules.ts on import, so no OpenCode host, no npm install and no
// build step are needed. tests/test-opencode-v2.sh runs this file.
import { test } from "node:test"
import assert from "node:assert/strict"
import {
  activeObjectiveId,
  claimKey,
  effectiveSegments,
  gitPushes,
  inspectClaim,
  isAgentWorkspacePath,
  judgeEdit,
  judgePush,
  sensitiveReason,
  shellSegments,
  shellWriteTargets,
} from "./rules.ts"

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
  assert.match(sensitiveReason(`${MAIN}/.github/workflows/ci.yml`, { remoteIsGithub: true }), /GitHub MCP/)
  assert.match(sensitiveReason(`${MAIN}/.github/workflows/ci.yml`, { remoteIsGithub: false }), /GitHub host's API/)
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
