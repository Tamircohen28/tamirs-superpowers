// guard.ts — OpenCode 2 server plugin: the three core safety guards.
//
// This is the OpenCode translation of three hooks that stay canonical in hooks/
// (they run as shell PreToolUse hooks on Claude Code, Codex and Cursor; OpenCode
// executes no shell hook, its only lifecycle mechanism is this plugin API):
//
//   hooks/enforce-worktree-edits.sh  -> ctx.permission.hook("evaluate") on `edit`
//   hooks/guard-sensitive-files.sh   -> the same hook on `edit`, plus `shell` write
//                                       targets, plus ctx.shell.hook("create.before")
//   hooks/protect-other-branches.sh  -> the same hook on `shell` (git push), plus
//                                       ctx.shell.hook("create.before")
//
// WHY TWO HOOKS FOR THE SHELL
//   `permission.hook("evaluate")` is the documented V1 `permission.ask` successor:
//   it runs after the configured rules, for `allow` and `ask` decisions, and a
//   plugin may set `effect = "deny"` with a `message` that "becomes the denial
//   reason" — the cleanest mirror of a PreToolUse deny, and the agent reads the
//   reason. But it only runs inside the tool permission flow. A command injected
//   by a `!`cmd`` template, or any shell the host creates outside that flow, never
//   reaches it. `shell.hook("create.before")` sees every shell OpenCode creates
//   (it is where `command`, `cwd` and `env` are still mutable); throwing there is
//   the only way to stop one, and whether the host surfaces the thrown reason to
//   the agent is NOT documented — so the permission hook is the primary guard and
//   the shell hook the backstop, never the other way round.
//
// WHAT IS NOT MIRRORED, AND WHY
//   - The no-objective half of enforce-worktree-edits.sh (deny a main-checkout
//     edit and point at the session's own worktree, recreating it if needed). It
//     rests on a session task slug captured by a UserPromptSubmit hook; OpenCode
//     has no equivalent, so a deny would name no destination. rules.ts states the
//     narrower rule: main-checkout edits are denied only while an objective is
//     active, when the orchestrator's worktrees ARE the destination.
//   - write-targets.py's full command parse (interpreters, xargs, find -exec,
//     apply_patch). rules.ts reads redirects, tee, sed -i, cp/mv/install and rm;
//     everything else is invisible rather than UNSURE. The binding half is still
//     the git/CI check on the modified path, exactly as the shell hook's header says.
//   - Whether a plugin may shell out to the Python helper is undocumented
//     (platforms.json records that), so this file spawns `git` for exactly one
//     question the filesystem cannot answer — `check-ignore` on a build-output
//     path — and nothing else.
//
// OVERRIDES (same names as the shell hooks)
//   PM_ALLOW_PROTECTED=1    skip the sensitive-path rules for an intended edit
//   TAMIRS_OPENCODE_GUARD=0 disable this plugin entirely (the TUI plugin is separate)
//
// Observed on @opencode/cli 2.2.5: `opencode plugin list` and `opencode debug
// agents` run without a provider key, so the plugin's LOADING can be checked
// offline (service mode; the first `plugin list` on a fresh service prints nothing,
// the second lists it — see docs/engineering/roadmap/v5-research/opencode-2.2.5.md).
// Whether `effect = "deny"` and a thrown shell hook actually stop the action is
// recorded as unverified live in core/capabilities/platforms.json until a session
// with a provider runs it.

import { Plugin } from "@opencode/plugin"
import { execFileSync } from "node:child_process"
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs"
import { hostname } from "node:os"
import path from "node:path"
import {
  claimKey,
  gitPushes,
  inspectClaim,
  judgeEdit,
  judgePush,
  sensitiveReason,
  shellWriteTargets,
  type ClaimVerdict,
  type Decision,
  type SensitiveFacts,
  type WorktreeFacts,
} from "./rules.ts"
import { activeObjectiveFor, gitRoots, originIsGithub, originSlug, pushFallbackBranch, type GitRoots } from "./state.ts"

const ID = "tamirs-superpowers.guard"

function home(): string {
  return process.env.HOME || process.env.USERPROFILE || ""
}

function claimDir(): string {
  return process.env.AGENT_CLAIM_DIR || path.join(home(), ".agent-work-claims")
}

function staleSeconds(): number {
  const n = Number(process.env.AGENT_CLAIM_STALE_SECONDS)
  return Number.isFinite(n) && n > 0 ? n : 900
}

// `kill -0` semantics: false only on ESRCH. EPERM means a live process owned by
// someone else, which the shell helper deliberately reads as alive too.
function pidAlive(pid: number): boolean | null {
  try {
    process.kill(pid, 0)
    return true
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code
    if (code === "ESRCH") return false
    if (code === "EPERM") return true
    return null
  }
}

function gitIgnored(root: string, file: string): boolean {
  try {
    execFileSync("git", ["-C", root, "check-ignore", "-q", "--", file], { stdio: "ignore", timeout: 3000 })
    return true
  } catch {
    return false
  }
}

function sensitiveFacts(roots: GitRoots | null, file: string): SensitiveFacts {
  if (!roots) return {}
  const underBuild = /\/(dist|build|out|\.next|target\/debug|target\/release)\//.test(file.replace(/\\/g, "/"))
  return {
    repoRoot: roots.worktreeRoot,
    hasShadcnConfig: existsSync(path.join(roots.worktreeRoot, "components.json")),
    gitIgnored: underBuild ? gitIgnored(roots.worktreeRoot, file) : false,
    remoteIsGithub: originIsGithub(roots),
  }
}

function worktreeFacts(roots: GitRoots | null): WorktreeFacts {
  const env = process.env
  const h = home()
  return {
    mainRoot: roots?.mainRoot ?? null,
    objectiveId: roots ? activeObjectiveFor(roots.mainRoot, env) : null,
    agentWorktreeRoot: env.SUPERPOWERS_AGENT_WORKTREE_ROOT || undefined,
    agentWorktreeDirname: env.SUPERPOWERS_AGENT_WORKTREE_DIRNAME || undefined,
    claudeConfigRoot: env.CLAUDE_CONFIG_DIR || (h ? path.join(h, ".claude") : undefined),
    globalWorktreeRoot: env.WORKTREE_ROOT || (h ? path.join(h, ".claude", "worktrees") : undefined),
  }
}

/** Judge one file write: sensitive-path rules first, then the worktree invariant. */
function judgeWrite(file: string, kind: "write" | "delete", via: string): Decision {
  const roots = gitRoots(path.dirname(file))
  if (process.env.PM_ALLOW_PROTECTED !== "1") {
    const reason = sensitiveReason(file, sensitiveFacts(roots, file), kind, via)
    if (reason) return { effect: "deny", reason }
  }
  if (kind === "delete") return { effect: "allow" }
  return judgeEdit(file, worktreeFacts(roots))
}

function readClaim(resource: string): ClaimVerdict {
  const file = path.join(claimDir(), `${claimKey(resource)}.json`)
  let text: string | null = null
  if (existsSync(file)) {
    try {
      text = readFileSync(file, "utf8")
    } catch {
      return { status: "ERROR", detail: `claim file '${file}' exists but could not be read` }
    }
  }
  return inspectClaim(text, me(), { now: Math.floor(Date.now() / 1000), host: hostname(), pidAlive, staleSeconds: staleSeconds() })
}

// Claim identity. The shell helper keys on "<tool>:<session>"; the permission hook
// knows the session, the shell hook does not, so the last session seen is reused
// there (best effort — a guard that cannot name itself still denies on LIVE).
let lastSessionID = ""
function me(): string {
  if (process.env.AGENT_CLAIM_ID) return process.env.AGENT_CLAIM_ID
  return lastSessionID ? `opencode:${lastSessionID}` : `opencode:pid-${process.pid}`
}

/** Take or refresh a claim — atomic (tmp + rename), same JSON as claim_write. */
function writeClaim(resource: string, note: string): void {
  try {
    const dir = claimDir()
    mkdirSync(dir, { recursive: true, mode: 0o700 })
    const file = path.join(dir, `${claimKey(resource)}.json`)
    const tmp = `${file}.tmp.${process.pid}`
    const body = {
      schema: "agent-work-claim/1",
      resource,
      agent_id: me(),
      tool: "opencode",
      host: hostname(),
      pid: process.pid,
      heartbeat_at: Math.floor(Date.now() / 1000),
      note,
    }
    writeFileSync(tmp, JSON.stringify(body), { encoding: "utf8", mode: 0o600 })
    renameSync(tmp, file)
  } catch {
    // A claim that could not be written is reported by the next inspect, never hidden here.
  }
}

/** Judge one shell command string: git push first, then any write targets it names. */
function judgeShell(command: string, cwd: string): Decision {
  const roots = gitRoots(cwd)
  const push = judgePush(command, {
    repoSlug: roots ? originSlug(roots) : null,
    fallbackBranch: roots ? pushFallbackBranch(roots) : null,
    me: me(),
    inspect: readClaim,
    integratorObjectiveId: process.env.SUPERPOWERS_ROLE === "integrator" && roots ? activeObjectiveFor(roots.mainRoot) : null,
  })
  if (push.effect !== "allow") return push
  for (const t of shellWriteTargets(command)) {
    const abs = path.isAbsolute(t.path) ? t.path : path.resolve(cwd, t.path)
    const d = judgeWrite(abs, t.kind, t.via)
    if (d.effect !== "allow") return d
  }
  return { effect: "allow" }
}

/** After an allowed push, hold the destination branches the way the shell hook does. */
function claimPushes(command: string, cwd: string): void {
  const roots = gitRoots(cwd)
  if (!roots) return
  const slug = originSlug(roots)
  if (!slug) return
  // judgePush already validated the command, so every invocation here resolves.
  for (const push of gitPushes(command, pushFallbackBranch(roots))) {
    for (const dst of push.dests) writeClaim(`git:${slug}@${dst}`, `git push ${dst}`)
  }
}

export default Plugin.define({
  id: ID,
  async setup(ctx) {
    if (process.env.TAMIRS_OPENCODE_GUARD === "0") return
    const locationDir = ctx.location.directory

    const permission = await ctx.permission.hook("evaluate", (e) => {
      if (e.effect === "deny") return
      if (e.sessionID) lastSessionID = String(e.sessionID)
      if (e.action === "edit") {
        for (const r of e.resources) {
          const abs = path.isAbsolute(r) ? r : path.resolve(locationDir, r)
          const d = judgeWrite(abs, "write", "")
          if (d.effect !== "allow") {
            e.effect = d.effect
            e.message = d.reason
            return
          }
        }
        return
      }
      if (e.action === "shell") {
        const cwd = typeof e.metadata?.cwd === "string" ? e.metadata.cwd : locationDir
        for (const cmd of e.resources) {
          const d = judgeShell(cmd, cwd)
          if (d.effect !== "allow") {
            e.effect = d.effect
            e.message = d.reason
            return
          }
          claimPushes(cmd, cwd)
        }
      }
    })

    const shell = await ctx.shell.hook("create.before", (e) => {
      const d = judgeShell(e.command, e.cwd)
      if (d.effect === "deny") {
        // The backstop: a shell created outside the permission flow. Throwing is
        // the only lever this hook has; the message carries the same reason.
        throw new Error(`[${ID}] ${d.reason}`)
      }
      // Hand the shell the same override vocabulary the hook scripts read.
      if (process.env.PM_ALLOW_PROTECTED === "1") e.env.PM_ALLOW_PROTECTED = "1"
    })

    return async () => {
      await permission.dispose()
      await shell.dispose()
    }
  },
})
