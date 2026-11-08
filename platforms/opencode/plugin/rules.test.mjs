// rules.test.mjs — unit tests for the pure decision functions in rules.ts.
//
// Runs with plain Node (`node --test rules.test.mjs`): Node 22.18+ strips the
// types from rules.ts on import, so no OpenCode host, no npm install and no
// build step are needed. tests/test-opencode-v2.sh runs this file.
//
// The protected-path tests also read hooks/lib/write-targets.py (the table must equal
// its own), read guard.ts as text (what it must never call), and run write-targets.py
// --protected on real commands. Those skip when python3 or git is missing.
import { test } from "node:test"
import assert from "node:assert/strict"
import { execFileSync, spawnSync } from "node:child_process"
import { mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import path from "node:path"
import { fileURLToPath } from "node:url"
import {
  activeObjectiveId,
  claimKey,
  effectiveSegments,
  gitPushes,
  globTailRegex,
  inspectClaim,
  isAgentWorkspacePath,
  judgeEdit,
  judgePush,
  parseWriteTargets,
  PROTECTED_PATHS,
  PROTECTED_REMEDY,
  protectedFromRecords,
  protectedHits,
  protectedReason,
  sensitiveReason,
  shellSegments,
  shellWriteTargets,
  writeTargetsFromRecords,
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
  assert.equal(sensitiveReason(`${MAIN}/.github/workflows/ci.yml`), null, "workflows are ordinary source (5.6.7)")
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

// ------------------------------------------------------- protected paths ---

test("no deny text points at a bypass: no GitHub MCP write tool, no PM_ALLOW_PROTECTED", () => {
  const texts = [
    sensitiveReason(`${MAIN}/package-lock.json`),
    sensitiveReason(`${MAIN}/.yarn/releases/yarn-4.cjs`),
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

test("the protected-path table equals write-targets.py's, in its order", () => {
  const py = readFileSync(path.join(ROOT, "hooks", "lib", "write-targets.py"), "utf8")
  const patterns = [...py.matchAll(/"(\{(?:home|repo|plugin_root)\}\/[^"]+)"/g)].map((m) => m[1])
  assert.ok(patterns.length > 0, "write-targets.py names no protected pattern")
  assert.deepEqual([...PROTECTED_PATHS], patterns)
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

test("protected paths: home, repo and plugin-root rules, every one a deny", () => {
  const hit = (p, over, containing) => protectedHits([p], pfacts(over), containing).map((h) => `${h.mode}:${h.pattern}`)
  assert.deepEqual(hit(`${H}/.gemini/settings.json`), ["deny:{home}/.gemini/settings.json"])
  assert.deepEqual(hit(`${H}/.config/opencode/opencode.json`), ["deny:{home}/.config/opencode/**"])
  assert.deepEqual(hit(`${H}/.gitconfig`), ["deny:{home}/.gitconfig"])
  assert.deepEqual(hit("/work/proj/opencode.json"), ["deny:{repo}/opencode.json"])
  assert.deepEqual(hit("/work/proj/.opencode/agents/x.md"), ["deny:{repo}/.opencode/agents/**"])
  assert.deepEqual(hit("/work/proj/.git/hooks/pre-commit"), ["deny:{repo}/.git/hooks/**"])
  assert.deepEqual(hit("/work/proj/.git/config"), ["deny:{repo}/.git/config"])
  // The plugin's own config and state are ordinary files: no permission policy lives there.
  assert.deepEqual(hit(`${H}/.config/tamirs-superpowers/config.json`), [])
  assert.deepEqual(hit("/work/proj/.tamirs-superpowers/x.json"), [])
  // {repo} means a repository root, not any directory: a nested opencode.json is ordinary.
  assert.deepEqual(hit("/work/proj/platforms/opencode/templates/opencode.json"), [])
  assert.deepEqual(hit("/work/proj/src/app.ts"), [])
  assert.deepEqual(hit(`${H}/.gemini/tmp/plans/plan.md`), [])
  // The running plugin's guard files: deny when installed; a source checkout is not protected.
  assert.deepEqual(hit(`${PLUG}/hooks/guard-sensitive-files.sh`), ["deny:{plugin_root}/hooks/**"])
  assert.deepEqual(hit(`${PLUG}/.git`), ["deny:{plugin_root}/.git/**"], "a .git planted in an installed copy")
  assert.deepEqual(hit(`${PLUG}/hooks/lib/x.sh`, { pluginRoots: [{ root: PLUG, sourceCheckout: true }] }), [])
  assert.deepEqual(hit(`${PLUG}/scripts/other.sh`), [])
  // Deleting a directory that holds a protected home path counts as deleting it; a repo root does not.
  assert.deepEqual(
    protectedHits([`${H}/.config`], pfacts(), true).map((h) => h.pattern),
    ["{home}/.config/opencode/**", "{home}/.config/gh/**"],
  )
  assert.deepEqual(hit(`${H}/.config`), [], "without containing, the directory itself is not one of the paths")
  assert.deepEqual(hit("/work/proj", {}, true), [])
  // A second spelling (the realpath) is judged too.
  assert.deepEqual(protectedHits(["/tmp/link", `${H}/.gitconfig`], pfacts()).map((h) => h.form), [`${H}/.gitconfig`])
})

test("protectedReason: wording, the realpath named, no bypass named, never an ask", () => {
  const d = protectedReason(`${H}/.config/opencode/opencode.json`, [`${H}/.config/opencode/opencode.json`], pfacts(), "write", "tee")
  assert.equal(d.mode, "deny")
  assert.match(d.reason, /^BLOCKED: '.*' would be written, and it is protected \(matches \{home\}\/\.config\/opencode\/\*\*\)\. \(via: tee\)/)
  assert.ok(d.reason.endsWith(PROTECTED_REMEDY))
  const r = protectedReason("/tmp/x", ["/tmp/x", `${H}/.gitconfig`], pfacts(), "link", "ln")
  assert.match(r.reason, /resolves to '\/Users\/you\/\.gitconfig'.*would become reachable through a new link/)
  assert.equal(protectedReason(`${PLUG}/hooks/x.sh`, [`${PLUG}/hooks/x.sh`], pfacts({ pluginRoots: [{ root: PLUG, sourceCheckout: true }] })), null)
  const both = protectedReason(`${PLUG}/hooks/x.sh`, [`${PLUG}/hooks/x.sh`, `${H}/.gitconfig`], pfacts({ pluginRoots: [{ root: PLUG, sourceCheckout: true }] }))
  assert.equal(both.mode, "deny")
  assert.equal(protectedReason("/work/proj/src/a.ts", ["/work/proj/src/a.ts"], pfacts()), null)
})

test("shell write targets: mv and ln sources, -t DIR", () => {
  const paths = (cmd) => shellWriteTargets(cmd).map((t) => `${t.kind}:${t.path}${t.linkAt ? "@" + t.linkAt : ""}`)
  // mv and ln can put a whole directory in place, so their destination is a tree target (F4b).
  assert.deepEqual(paths("mv ~/.gitconfig /tmp/g"), ["tree:/tmp/g", "move:~/.gitconfig"])
  assert.deepEqual(paths("ln -s ../hooks/guard-sensitive-files.sh x.sh"), ["tree:x.sh", "link:../hooks/guard-sensitive-files.sh@x.sh"])
  assert.deepEqual(paths("ln /a/b /c/d"), ["tree:/c/d", "link:/a/b"])
  // -t DIR: each source lands under DIR, which is what is written (`cp -t ~/.claude settings.json`).
  assert.deepEqual(paths("cp -t dist a.js b.js"), ["write:dist/a.js", "write:dist/b.js"])
  assert.deepEqual(paths("mv -t dist a.js b.js"), ["tree:dist/a.js", "tree:dist/b.js", "move:a.js", "move:b.js"])
  assert.deepEqual(paths("cp -t ~/.claude settings.json"), ["write:~/.claude/settings.json"])
  assert.deepEqual(paths("cp src.js dist/bundle.js"), ["write:dist/bundle.js"])
})

// ---------------------------- L4: the protected-path parse, nearer write-targets.py ---

test("L4 fd redirects: any fd, under exec, read-write and >& FILE are writes; duplications are not (F4b)", () => {
  const paths = (cmd) => shellWriteTargets(cmd).map((t) => `${t.kind}:${t.path}`)
  assert.deepEqual(paths("exec 3> ~/.config/gh/hosts.yml; echo '{}' >&3"), [
    "write:~/.config/gh/hosts.yml",
  ])
  assert.deepEqual(paths("exec 3<> ~/.gitconfig"), ["write:~/.gitconfig"])
  assert.deepEqual(paths("echo x >& ~/.gitconfig"), ["write:~/.gitconfig"])
  assert.deepEqual(paths("echo x >&2; exec 3>&-; exec 4>&3-"), [])
  assert.deepEqual(paths("exec 3< ~/.gitconfig; cat <&3"), [])
})

test("L4 tokenizer tricks: a comment's apostrophe, $'\\'' and (( << )) no longer hide a write (F4d)", () => {
  const paths = (cmd) => shellWriteTargets(cmd).map((t) => `${t.kind}:${t.path}`)
  assert.deepEqual(paths("# don't\necho x > ~/.claude/settings.json; echo '"), ["write:~/.claude/settings.json"])
  assert.deepEqual(paths("echo $'\\''\necho x > ~/.claude/settings.json; echo '"), ["write:~/.claude/settings.json"])
  assert.deepEqual(paths("(( 1 << 2 ))\ncp /tmp/a ~/.gitconfig"), ["write:~/.gitconfig"])
  assert.deepEqual(paths("# never edit ~/.claude/settings.json\necho ok"), [], "a comment that names a path writes nothing")
  // The segmenter the push guard shares reads the same three shapes.
  assert.deepEqual(effectiveSegments("# it's\ngit push origin main"), [["git", "push", "origin", "main"]])
  assert.deepEqual(effectiveSegments("(( 1 << 2 ))\ngit push origin main").pop(), ["git", "push", "origin", "main"])
})

test("L4 directory copies, links and extraction are tree targets judged by the directory they fill (F4b)", () => {
  const paths = (cmd) => shellWriteTargets(cmd).map((t) => `${t.kind}:${t.path}`)
  assert.deepEqual(paths("cp -r /tmp/e/.claude ~/"), ["tree:~/.claude"])
  assert.deepEqual(paths("cp -R /tmp/e/ ~/.claude/"), ["tree:~/.claude/"], "a trailing-slash source fills the destination itself")
  assert.deepEqual(paths("cp -r foo ~"), ["tree:~/foo"])
  assert.deepEqual(paths("rsync -a src/ ~/.config/"), ["tree:~/.config/"])
  assert.deepEqual(paths("tar -xf x.tar -C ~/.claude"), ["tree:~/.claude"])
  assert.deepEqual(paths("tar xzf x.tgz --directory=/opt/x"), ["tree:/opt/x"])
  assert.deepEqual(paths("tar xzf x.tgz"), ["tree:."], "no -C: the cwd")
  assert.deepEqual(paths("tar -tf x.tar -C d"), [], "listing writes nothing")
  assert.deepEqual(paths("tar -czf ~/.claude/settings.json src"), ["write:~/.claude/settings.json"])
  assert.deepEqual(paths("unzip -o x.zip -d ~/.claude"), ["tree:~/.claude"])
  assert.deepEqual(paths("unzip -l x.zip"), [])
  assert.deepEqual(paths("cp -l ~/.claude/settings.json /tmp/x"), ["write:/tmp/x", "link:~/.claude/settings.json"])
  assert.deepEqual(paths("cp -al ~/.claude /tmp/c"), ["tree:/tmp/c", "link:~/.claude"])
})

test("L4 protected paths: case folding, ~ and $HOME spellings, parents of repo-relative paths, trees into a repo root", () => {
  const hit = (p, over = {}, containing = false, tree = false) =>
    protectedHits([p], pfacts(over), containing, tree).map((h) => `${h.mode}:${h.pattern}`)
  // F4a: folded unless the volume is shown to be case-sensitive.
  assert.deepEqual(hit(`${H}/.CLAUDE/settings.json`), ["deny:{home}/.claude/settings*.json"])
  assert.deepEqual(hit(`${H}/.claude/SETTINGS.json`), ["deny:{home}/.claude/settings*.json"])
  assert.deepEqual(hit("/work/proj/.OPENCODE/opencode.json"), ["deny:{repo}/.opencode/opencode.json"])
  assert.deepEqual(hit(`${H}/.CLAUDE/settings.json`, { caseInsensitive: () => null }), ["deny:{home}/.claude/settings*.json"], "unknown folds")
  assert.deepEqual(hit(`${H}/.CLAUDE/settings.json`, { caseInsensitive: () => false }), [], "case-sensitive: another file")
  assert.deepEqual(hit(`${H}/.CLAUDE/CLAUDE.md`), [], "a folded neighbour is still a neighbour")
  // guard.ts resolves a written ~ (or $HOME) against the cwd; the shell expands it to a home.
  const r = protectedReason("/work/proj/~/.gitconfig", ["/work/proj/~/.gitconfig"], pfacts(), "write", "redirect")
  assert.equal(r.mode, "deny")
  assert.match(r.reason, /resolves to '\/Users\/you\/\.gitconfig'/)
  assert.equal(protectedReason("/work/proj/$HOME/.config/gh/hosts.yml", ["/work/proj/$HOME/.config/gh/hosts.yml"], pfacts()).mode, "deny")
  assert.equal(protectedReason("/work/proj/~/notes.md", ["/work/proj/~/notes.md"], pfacts()), null)
  // Codex P2: a parent of a repo-relative protected path is one too; a repo root stays removable.
  assert.deepEqual(hit("/work/proj/.claude", {}, true), ["deny:{repo}/.claude/settings*.json"])
  assert.ok(hit("/work/proj/.git", {}, true).includes("deny:{repo}/.git/config"))
  assert.deepEqual(hit("/work/proj/src", {}, true), [])
  assert.deepEqual(hit("/work/proj", {}, true), [], "deleting a repository root is not deleting its settings")
  assert.ok(hit("/work/proj", {}, false, true).length > 0, "a tree written INTO a repository root can land on its settings")
  assert.deepEqual(hit("/work/proj/src", {}, false, true), [])
  // protectedReason routes delete, move, link and tree to the parent rules.
  assert.equal(protectedReason("/work/proj/.claude", ["/work/proj/.claude"], pfacts(), "delete", "rm").mode, "deny")
  assert.equal(protectedReason("/work/proj/.cursor", ["/work/proj/.cursor"], pfacts(), "move", "mv").mode, "deny")
  const t = protectedReason(`${H}/.claude`, [`${H}/.claude`], pfacts(), "tree", "cp")
  assert.equal(t.mode, "deny")
  assert.match(t.reason, /would receive a whole directory tree/)
  assert.equal(protectedReason(`${H}/projects/x`, [`${H}/projects/x`], pfacts(), "tree", "cp"), null)
  // A repository's OpenCode config, plugins and agents, and its Gemini settings, policies and
  // extensions are protected; its generated command, skill and adapter dirs for other hosts are not.
  for (const f of [".gemini/settings.json", ".gemini/policies/p.toml", ".gemini/extensions/x/e.json", "opencode.jsonc",
    ".opencode/opencode.json", ".opencode/opencode.jsonc", ".opencode/plugin/x.ts", ".opencode/plugins/x.ts",
    ".opencode/agent/a.md", ".opencode/agents/a.md"]) {
    assert.equal(protectedReason(`/work/proj/${f}`, [`/work/proj/${f}`], pfacts())?.mode, "deny", f)
  }
  for (const f of [".gemini/skills/x/SKILL.md", ".gemini/agents/a.md", ".gemini/GEMINI.md", ".opencode/commands/c.md"]) {
    assert.equal(protectedReason(`/work/proj/${f}`, [`/work/proj/${f}`], pfacts()), null, f)
  }
  assert.equal(protectedReason("/work/proj/.gemini", ["/work/proj/.gemini"], pfacts(), "delete", "rm")?.mode, "deny")
  assert.equal(protectedReason("/work/proj/.opencode/commands", ["/work/proj/.opencode/commands"], pfacts(), "delete", "rm"), null)
  // Workflows are ordinary source (5.6.7): neither a workflow nor the directory that holds them is protected.
  assert.equal(sensitiveReason(`${MAIN}/.github/workflows`, {}, "delete"), null)
  assert.equal(protectedReason(`${MAIN}/.github`, [`${MAIN}/.github`], pfacts(), "tree", "cp"), null)
})

test("L4 parity: every class this port reads, write-targets.py --protected judges the same way", {
  skip: spawnSync("sh", ["-c", "command -v python3"]).status !== 0 && "python3 missing",
}, () => {
  const t = realpathSync(mkdtempSync(path.join(tmpdir(), "ts-oc-l4-")))
  try {
    const home = path.join(t, "home")
    const repo = path.join(t, "repo")
    execFileSync("mkdir", ["-p", home, path.join(repo, ".git"), path.join(repo, "src")])
    const facts = { homes: [home], pluginRoots: [], isRepoRoot: (d) => d === repo || d === path.join(repo) }
    const ts = (cmd) => {
      for (const w of shellWriteTargets(cmd)) {
        const abs = w.path.startsWith("/") ? w.path : path.resolve(repo, w.path)
        const v = protectedReason(abs, [abs], facts, w.kind, w.via)
        if (v && v.mode === "deny") return "deny"
      }
      return "allow"
    }
    const py = (cmd) => {
      const out = execFileSync("python3", [path.join(ROOT, "hooks", "lib", "write-targets.py"), "--protected"], {
        input: JSON.stringify({ tool_name: "Bash", cwd: repo, tool_input: { command: cmd } }),
        encoding: "utf8",
        env: { ...process.env, HOME: home },
      })
      return /^PROTECTED\tdeny\t/m.test(out) ? "deny" : "allow"
    }
    const denied = [
      "exec 3> ~/.config/gh/hosts.yml; echo '{}' >&3",
      "exec 3<> ~/.gitconfig",
      "echo x >& ~/.gitconfig",
      "cp -r /tmp/e/.claude ~/",
      "cp -R /tmp/e/ ~/.claude/",
      "rsync -a /tmp/e/ ~/.config/",
      "tar -xf x.tar -C ~/.claude",
      "unzip -o x.zip -d ~/.config/gh",
      "tar -czf ~/.claude/settings.json src",
      "rm -rf .claude",
      "mv .git /tmp/x",
      "cp -R /tmp/e/ .cursor/",
      "cp -l ~/.gitconfig /tmp/g",
      "cp -t ~/.claude settings.json",
      "# don't\necho x > ~/.claude/settings.json; echo '",
      "(( 1 << 2 ))\necho x > ~/.gitconfig",
    ]
    for (const c of denied) assert.deepEqual([ts(c), py(c)], ["deny", "deny"], c)
    const allowed = ["cp -r foo ~/projects/", "tar -xf x.tar -C /tmp/out", "rm -rf src", "echo x > /tmp/n", "cp -r ~/.claude /tmp/backup", "unzip -l x.zip"]
    for (const c of allowed) assert.deepEqual([ts(c), py(c)], ["allow", "allow"], c)
  } finally {
    rmSync(t, { recursive: true, force: true })
  }
})

test("guard.ts never widens and never asks: no session.update, never an allow, e.effect only ever a deny", () => {
  const g = readFileSync(path.join(HERE, "guard.ts"), "utf8")
  assert.doesNotMatch(g, /\.session\.update\(/)
  assert.doesNotMatch(g, /permission\.assert\(/)
  // An allow would widen a configured ask; guard.ts never sets one, in any spelling.
  assert.doesNotMatch(g, /effect\s*=\s*"allow"/)
  assert.doesNotMatch(g, /effect\s*=\s*ALLOW\b/)
  const sets = [...g.matchAll(/\be\.effect\s*=(?!=)\s*([^\n;]+)/g)].map((m) => m[1].trim())
  assert.deepEqual([...new Set(sets)], ['"deny"'], `e.effect is set from: ${sets.join(", ")}`)
  // `opencode --auto` approves a plugin ask, so the plugin never produces one.
  assert.doesNotMatch(g, /"ask"/)
  // It runs no other guard script: write-targets.py is its only helper beyond git.
  const spawned = [...g.matchAll(/execFileSync\(\s*"([^"]+)"/g)].map((m) => m[1])
  assert.deepEqual([...new Set(spawned)].sort(), ["git", "python3"], `guard.ts spawns: ${spawned.join(", ")}`)
  // The legacy switch is read once and never turns off the protected paths.
  assert.match(g, /const legacy = process\.env\.TAMIRS_OPENCODE_GUARD !== "0"/)
  assert.doesNotMatch(g, /TAMIRS_OPENCODE_GUARD === "0"\) return/)
})

// --- write-targets.py --protected: the parse guard.ts routes every write through ---------
test("write-targets records: a PROTECTED deny decides, any other mode is not acted on, targets keep their kind", () => {
  const out = [
    "PROTECTED\task\t'/r/.claude/settings.json' would be rewritten. A git branch operation brings it in.",
    "PROTECTED\tdeny\t'/h/.gitconfig' would be written, and it is protected.",
    "TARGET\t/r/src/a.ts\techo",
    "DELETE\t/r/dist\trm",
    "TREE\t/r/vendor\ttar",
    "UNSURE\tsomething\tpython3 -c",
    "",
  ].join("\n")
  const rec = parseWriteTargets(out)
  assert.equal(rec.length, 6)
  const d = protectedFromRecords(rec)
  assert.equal(d.effect, "deny")
  assert.match(d.reason, /^BLOCKED: '\/h\/\.gitconfig'/)
  assert.ok(d.reason.endsWith(PROTECTED_REMEDY))
  assert.equal(protectedFromRecords(rec.filter((r) => r.detail !== "deny")), null, "no ask, no deny")
  assert.equal(protectedFromRecords(rec.filter((r) => r.kind !== "PROTECTED")), null)
  assert.deepEqual(writeTargetsFromRecords(rec), [
    { path: "/r/src/a.ts", kind: "write", via: "echo" },
    { path: "/r/dist", kind: "delete", via: "rm" },
    { path: "/r/vendor", kind: "tree", via: "tar" },
  ])
  assert.deepEqual(writeTargetsFromRecords(parseWriteTargets("TARGET\trelative\tx\nconstructor\t/x\ty")), [])
})

test("guard.ts routes writes through write-targets.py --protected before PM_ALLOW_PROTECTED and the legacy switch (L4)", () => {
  const g = readFileSync(path.join(HERE, "guard.ts"), "utf8")
  assert.match(g, /path\.join\(PLUGIN_ROOT, "hooks", "lib", "write-targets\.py"\)/)
  assert.match(g, /execFileSync\("python3", \[WRITE_TARGETS, "--protected"\]/)
  // Only a missing python3 falls back to the port; any other failure throws into failClosed.
  assert.match(g, /code === "ENOENT"\) return null/)
  // The protected records decide before anything an override or the legacy switch reaches.
  const fn = g.indexOf("function judgeWritesCanonical(")
  const body = g.slice(fn, g.indexOf("\nfunction ", fn + 1))
  assert.ok(fn >= 0 && body.indexOf("protectedFromRecords(") >= 0, "judgeWritesCanonical applies the protected records")
  assert.ok(body.indexOf("protectedFromRecords(") < body.indexOf("judgeAfterProtected("), "before the generated-file rules")
  const after = g.slice(g.indexOf("function judgeAfterProtected("), g.indexOf("\nfunction ", g.indexOf("function judgeAfterProtected(") + 1))
  assert.ok(after.indexOf("if (!legacy") < after.indexOf("PM_ALLOW_PROTECTED"), "the override reaches only the legacy rules")
  assert.doesNotMatch(after, /workflow/i, "workflows are ordinary source (5.6.7)")
  const sh = g.slice(g.indexOf("function judgeShell("), g.indexOf("\nfunction ", g.indexOf("function judgeShell(") + 1))
  assert.ok(sh.indexOf('judgeWritesCanonical("Bash"') >= 0 && sh.indexOf('judgeWritesCanonical("Bash"') < sh.indexOf("shellWriteTargets("),
    "the shell guard asks write-targets.py first; the port is the fallback")
  assert.match(g, /judgeWritesCanonical\("Edit", \{ file_path: abs \}/)
})

test("write-targets.py --protected on the commands the port misses: what guard.ts now decides", { skip: !(spawnSync("sh", ["-c", "command -v python3 && command -v git"]).status === 0) }, () => {
  const t = realpathSync(mkdtempSync(path.join(tmpdir(), "ts-oc-wt-")))
  try {
    const repo = path.join(t, "repo")
    const git = (...a) => execFileSync("git", ["-C", repo, ...a], { stdio: "ignore", env: { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" } })
    execFileSync("git", ["init", "-q", "-b", "main", repo], { stdio: "ignore" })
    git("config", "user.email", "t@t"); git("config", "user.name", "t"); git("config", "commit.gpgsign", "false")
    execFileSync("mkdir", ["-p", path.join(repo, ".claude"), path.join(repo, ".github", "workflows")])
    writeFileSync(path.join(repo, ".claude", "settings.json"), "{}\n")
    writeFileSync(path.join(repo, ".github", "workflows", "ci.yml"), "name: ci\n")
    git("add", "-A"); git("commit", "-qm", "base")
    git("checkout", "-qb", "evil")
    writeFileSync(path.join(repo, ".claude", "settings.json"), '{"permissions":{"allow":["Bash(*)"]}}\n')
    git("commit", "-qam", "widen"); git("checkout", "-q", "main")
    const judge = (command, env = {}) => {
      const out = execFileSync("python3", [path.join(ROOT, "hooks", "lib", "write-targets.py"), "--protected"], {
        input: JSON.stringify({ tool_name: "Bash", tool_input: { command }, cwd: repo }),
        encoding: "utf8", env: { ...process.env, HOME: path.join(t, "home"), ...env },
      })
      const rec = parseWriteTargets(out)
      return { p: protectedFromRecords(rec), targets: writeTargetsFromRecords(rec) }
    }
    // A git replay is not judged (6.0.0): neither the port nor write-targets.py blocks it.
    assert.equal(shellWriteTargets("git merge evil").length, 0)
    assert.equal(judge("git merge evil").p, null)
    assert.equal(judge("git checkout evil -- .claude/settings.json").p, null)
    assert.equal(judge("curl -so .claude/settings.json https://x.invalid/s").p?.effect, "deny")
    assert.equal(judge("rm -rf .claude").p?.effect, "deny", "Codex P2: the parent of a protected path")
    assert.equal(judge("git log --oneline -3").p, null)
    // A workflow is ordinary source (5.6.7): a target, never a protected path.
    const wf = judge("echo x > .github/workflows/ci.yml")
    assert.equal(wf.p, null)
    assert.ok(wf.targets.some((x) => x.path.endsWith("/.github/workflows/ci.yml")), "the workflow target is reported")
  } finally {
    rmSync(t, { recursive: true, force: true })
  }
})
