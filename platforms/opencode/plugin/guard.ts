// guard.ts — OpenCode 2 server plugin: the core safety guards and the ADR 004
// permission layer.
//
// This is the OpenCode translation of hooks that stay canonical in hooks/ (they run
// as shell PreToolUse hooks on Claude Code, Codex and Cursor; OpenCode executes no
// shell hook, its only lifecycle mechanism is this plugin API):
//
//   hooks/permission-guard.sh        -> RUN AS IS from ctx.permission.hook("evaluate")
//                                       on `shell` and on the bundled GitHub MCP
//                                       server's `github_<tool>` actions, and from
//                                       ctx.shell.hook("create.before") (ADR 004 D8)
//   hooks/guard-sensitive-files.sh   -> the same hook on `edit`, plus `shell` write
//                                       targets, plus ctx.shell.hook("create.before");
//                                       its protected pass (D10.1) via rules.ts
//   hooks/enforce-worktree-edits.sh  -> the same hook on `edit`
//   hooks/protect-other-branches.sh  -> the same hook on `shell` (git push), plus
//                                       ctx.shell.hook("create.before")
//
// THE PERMISSION LAYER (ADR 004 D8, spikes O1/O2)
//   - One source of truth: the canonical bash guard decides, through the same action
//     catalog, conditions and resolver as on every other host; guard.ts only hands it
//     a payload in the guard's OPENCODE dialect (opencodePayload: rules.ts pgPayload
//     without the Codex marker, plus "host": "opencode"; resolver host opencode, no
//     option store) and reads the answer (opencodeVerdict). A TypeScript port of the
//     matcher would drift.
//   - D8's OpenCode row, "R2: hook ask (A under --auto); R3/R4: deny". The guard
//     answers ask only for an R2 call (never_auto and UNCLASSIFIED excluded) and deny
//     for everything that must survive `opencode --auto`: a plugin `deny` is final
//     under it (measured O1b), an `ask` is approved by it (O1c). So guard.ts sets
//     the guard's own effect, ask or deny, and never allow, which would widen a
//     configured ask (O1e).
//   - Never ctx.session.update: a session rule overrides a config deny (measured O2),
//     so using it would let this plugin widen what the user's opencode.json forbids
//     (ADR 004 D10.4).
//   - Fail closed: a missing guard, a non-zero exit, a timeout, unreadable output or
//     an exception in either hook is a deny (D4, D8 "guard.ts catches every error").
//   - Not switchable from the environment: TAMIRS_OPENCODE_GUARD=0 turns off the
//     legacy guards only, because an env switch may only tighten (D3).
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
//   the shell hook the backstop, never the other way round. The guard's verdict for
//   a command is cached for a few seconds, so the second hook does not run it twice.
//
// WHAT IS NOT MIRRORED, AND WHY
//   - The no-objective half of enforce-worktree-edits.sh (deny a main-checkout
//     edit and point at the session's own worktree, recreating it if needed). It
//     rests on a session task slug captured by a UserPromptSubmit hook; OpenCode
//     has no equivalent, so a deny would name no destination. rules.ts states the
//     narrower rule: main-checkout edits are denied only while an objective is
//     active, when the orchestrator's worktrees ARE the destination.
//   - write-targets.py's full command parse (interpreters, xargs, find -exec,
//     apply_patch). rules.ts reads redirects, tee, sed -i, cp/mv/install/ln and rm;
//     everything else is invisible rather than UNSURE. The binding half is still
//     the git/CI check on the modified path, exactly as the shell hook's header says.
//   - This file spawns `git` for one question the filesystem cannot answer —
//     `check-ignore` on a build-output path — and `bash hooks/permission-guard.sh`
//     (which itself runs python3 and the resolver). Nothing else.
//
// OVERRIDES (same names as the shell hooks; none reaches the permission layer)
//   PM_ALLOW_PROTECTED=1    skip the generated-file rules (lockfiles, workflows,
//                           .yarn/releases, shadcn ui, build output) for an intended
//                           edit; never a protected path (D10.1)
//   TAMIRS_OPENCODE_GUARD=0 disable the legacy guards above; the permission layer
//                           and the protected paths stay on
//
// Observed on @opencode/cli 2.2.5: `opencode plugin list` and `opencode debug
// agents` run without a provider key, so the plugin's LOADING can be checked
// offline (service mode; the first `plugin list` on a fresh service prints nothing,
// the second lists it — see docs/engineering/roadmap/v5-research/opencode-2.2.5.md).
// That an evaluate-hook deny stops a shell call under --auto was measured with a
// probe plugin (spike O1b, docs/engineering/research/permissions/spikes/); this
// plugin's own run in a session with a provider is still unmeasured, so
// core/capabilities/platforms.json keeps hooks at adapter.

import { Plugin } from "@opencode/plugin"
import { execFileSync } from "node:child_process"
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, renameSync, statSync, writeFileSync } from "node:fs"
import { hostname, userInfo } from "node:os"
import path from "node:path"
import { fileURLToPath } from "node:url"
import {
  ALLOW,
  claimKey,
  deliverAsDeny,
  deny,
  gitPushes,
  githubMcpTool,
  inspectClaim,
  judgeEdit,
  judgePush,
  pgEnv,
  pgPayload,
  pgVerdict,
  protectedReason,
  sensitiveReason,
  shellWriteTargets,
  type ClaimVerdict,
  type Decision,
  type PgCall,
  type ProtectedFacts,
  type SensitiveFacts,
  type TargetKind,
  type WorktreeFacts,
} from "./rules.ts"
import { activeObjectiveFor, gitRoots, nearestExistingDir, originSlug, pushFallbackBranch, type GitRoots } from "./state.ts"

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

// ------------------------------------------------- protected paths (D10.1) ---

/** This plugin's repository root: guard.ts sits at <root>/platforms/opencode/plugin/. */
const PLUGIN_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..")
const PERMISSION_GUARD = path.join(PLUGIN_ROOT, "hooks", "permission-guard.sh")

/** The lexical spelling and the realpath of an absolute path (its nearest existing ancestor resolved). */
function pathForms(abs: string): string[] {
  const lexical = path.normalize(abs)
  const forms = [lexical]
  try {
    const anchor = nearestExistingDir(lexical)
    const real = path.join(realpathSync(anchor), path.relative(anchor, lexical))
    if (!forms.includes(real)) forms.push(real)
    if (existsSync(lexical)) {
      const full = realpathSync(lexical)
      if (!forms.includes(full)) forms.push(full)
    }
  } catch {
    /* an unresolvable path is judged on its lexical form */
  }
  return forms
}

function protectedFacts(cwd: string): ProtectedFacts {
  const homes: string[] = []
  // The passwd home decides (ADR 004 D3, SR S-04); the session HOME is added, never trusted instead.
  let passwd = ""
  try {
    passwd = userInfo().homedir
  } catch {
    /* no passwd entry: HOME alone */
  }
  for (const h of [passwd, process.env.HOME || ""]) {
    if (!h || !path.isAbsolute(h)) continue
    for (const f of pathForms(h)) if (f !== "/" && !homes.includes(f)) homes.push(f)
  }
  const pluginRoots: { root: string; sourceCheckout: boolean }[] = []
  for (const r of pathForms(PLUGIN_ROOT)) {
    let real = r
    try {
      real = realpathSync(r)
    } catch {
      /* keep the lexical form */
    }
    pluginRoots.push({ root: r, sourceCheckout: existsSync(path.join(real, ".git")) })
  }
  const cwdForms = cwd && path.isAbsolute(cwd) ? pathForms(cwd) : []
  return {
    homes,
    pluginRoots,
    isRepoRoot: (dir) => cwdForms.includes(dir) || lexists(path.join(dir, ".git")),
  }
}

function lexists(p: string): boolean {
  try {
    lstatSync(p)
    return true
  } catch {
    return false
  }
}

/** The protected-path verdict for one absolute target, delivered as OpenCode can (an R4 ask is a deny). */
function judgeProtected(abs: string, kind: TargetKind, via: string, cwd: string): Decision {
  const v = protectedReason(abs, pathForms(abs), protectedFacts(cwd), kind, via)
  if (!v) return ALLOW
  return v.mode === "deny" ? deny(v.reason) : deliverAsDeny(v.reason)
}

/** Judge one file write: protected paths (always), then the generated-file rules and the worktree invariant (legacy). */
function judgeWrite(file: string, kind: TargetKind, via: string, cwd: string, legacy: boolean): Decision {
  const p = judgeProtected(file, kind, via, cwd)
  if (p.effect !== "allow") return p
  if (!legacy || kind === "move" || kind === "link") return ALLOW
  const roots = gitRoots(path.dirname(file))
  if (process.env.PM_ALLOW_PROTECTED !== "1") {
    const reason = sensitiveReason(file, sensitiveFacts(roots, file), kind, via)
    if (reason) return deny(reason)
  }
  if (kind === "delete") return ALLOW
  return judgeEdit(file, worktreeFacts(roots))
}

// ---------------------------------------- hooks/permission-guard.sh (ADR 004 D8) ---

// The guard's own budget is at most 20 s; give it that plus start-up, then deny.
const PG_TIMEOUT_MS = 25_000
const PG_CACHE_MS = 5_000
const pgCache = new Map<string, { at: number; d: Decision }>()
// Shell commands whose R2 ask the permission hook put to OpenCode's own prompt. The
// create.before backstop lets such a command through once, within this window, and
// denies any other asked command: a shell created outside the permission flow never
// saw a prompt.
const PG_ASKED_MS = 15 * 60_000
const pgAsked = new Map<string, number>()

/**
 * The guard payload in its OpenCode dialect: pgPayload's call without the Codex marker
 * (`turn_id`, which would make the guard answer as Codex, deny only), with "host":
 * "opencode" — honoured by the guard only where the host otherwise reads as Claude Code.
 */
function opencodePayload(call: PgCall, sessionID: string): Record<string, unknown> {
  const p: Record<string, unknown> = { ...pgPayload(call, sessionID), host: "opencode" }
  delete p.turn_id
  return p
}

/**
 * Read the guard's OpenCode-dialect answer: its ask (an R2 call, D8) stays an ask with
 * its reason; everything else is read by pgVerdict, which allows only `{}` or an
 * explicit allow and denies a deny, garbage and silence (fail closed, D4).
 */
function opencodeVerdict(stdout: string): Decision {
  try {
    const o: unknown = JSON.parse(stdout.trim())
    const h = o && typeof o === "object" && !Array.isArray(o) ? (o as Record<string, unknown>).hookSpecificOutput : undefined
    if (h && typeof h === "object" && (h as Record<string, unknown>).permissionDecision === "ask") {
      const r = (h as Record<string, unknown>).permissionDecisionReason
      return {
        effect: "ask",
        reason: typeof r === "string" && r ? r : "tamirs-superpowers permission guard asks before this R2 call (ADR 004 D8).",
      }
    }
  } catch {
    /* not JSON: pgVerdict denies it */
  }
  return pgVerdict(stdout)
}

/** Run the canonical permission guard on one call. Every failure is a deny. */
function runPermissionGuard(call: PgCall, sessionID: string): Decision {
  const key = JSON.stringify(call)
  const now = Date.now()
  const hit = pgCache.get(key)
  if (hit && now - hit.at < PG_CACHE_MS) return hit.d
  let d: Decision
  if (!existsSync(PERMISSION_GUARD)) {
    d = deny(
      `tamirs-superpowers permission guard: ${PERMISSION_GUARD} is missing, so the call cannot be judged and is denied ` +
        "(fail closed, ADR 004 D4, D8). Restore the plugin's hooks/ directory.",
    )
  } else {
    try {
      const out = execFileSync("bash", [PERMISSION_GUARD], {
        input: JSON.stringify(opencodePayload(call, sessionID)),
        encoding: "utf8",
        timeout: PG_TIMEOUT_MS,
        maxBuffer: 1 << 20,
        env: pgEnv(process.env),
        cwd: call.cwd && path.isAbsolute(call.cwd) && existsSync(call.cwd) ? call.cwd : PLUGIN_ROOT,
        stdio: ["pipe", "pipe", "pipe"],
      })
      d = opencodeVerdict(out)
    } catch (err) {
      const why = (err as NodeJS.ErrnoException & { signal?: string }).signal
        ? `it was stopped (${(err as { signal?: string }).signal})`
        : `it failed (${(err as Error).message.split("\n")[0]})`
      d = deny(`tamirs-superpowers permission guard: ${why}, so the call is denied (fail closed, ADR 004 D4, D8).`)
    }
  }
  if (pgCache.size > 64) pgCache.clear()
  pgCache.set(key, { at: now, d })
  return d
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

/** Judge one shell command string: git push (legacy), its write targets, then the permission guard. */
function judgeShell(command: string, cwd: string, legacy: boolean, sessionID: string): Decision {
  if (legacy) {
    const roots = gitRoots(cwd)
    const push = judgePush(command, {
      repoSlug: roots ? originSlug(roots) : null,
      fallbackBranch: roots ? pushFallbackBranch(roots) : null,
      me: me(),
      inspect: readClaim,
      integratorObjectiveId: process.env.SUPERPOWERS_ROLE === "integrator" && roots ? activeObjectiveFor(roots.mainRoot) : null,
    })
    if (push.effect !== "allow") return push
  }
  for (const t of shellWriteTargets(command)) {
    const bases = [cwd]
    // A relative symlink target resolves against the link's directory (write-targets.py _source_records).
    if (t.kind === "link" && t.linkAt) {
      const at = path.isAbsolute(t.linkAt) ? t.linkAt : path.resolve(cwd, t.linkAt)
      bases.push(t.linkAt.endsWith("/") || isDir(at) ? at : path.dirname(at))
    }
    for (const b of path.isAbsolute(t.path) ? [""] : bases) {
      const abs = b ? path.resolve(b, t.path) : t.path
      const d = judgeWrite(abs, t.kind, t.via, cwd, legacy)
      if (d.effect !== "allow") return d
    }
  }
  return runPermissionGuard({ kind: "shell", command, cwd }, sessionID)
}

function isDir(p: string): boolean {
  try {
    return statSync(p).isDirectory()
  } catch {
    return false
  }
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

/** A hook that throws must not let the call through (D8: guard.ts catches every error as deny). */
function failClosed(err: unknown): Decision {
  return deny(`tamirs-superpowers guard: an internal error stopped the check (${String((err as Error)?.message ?? err)}), so the call is denied (fail closed, ADR 004 D8).`)
}

export default Plugin.define({
  id: ID,
  async setup(ctx) {
    // An environment switch may only tighten (ADR 004 D3): this one turns off the
    // legacy guards, never the permission layer or the protected paths.
    const legacy = process.env.TAMIRS_OPENCODE_GUARD !== "0"
    const locationDir = ctx.location.directory

    const permission = await ctx.permission.hook("evaluate", (e) => {
      if (e.effect === "deny") return
      try {
        if (e.sessionID) lastSessionID = String(e.sessionID)
        const session = String(e.sessionID || lastSessionID || "")
        let d: Decision = ALLOW
        if (e.action === "edit") {
          for (const r of e.resources) {
            const abs = path.isAbsolute(r) ? r : path.resolve(locationDir, r)
            d = judgeWrite(abs, "write", "", locationDir, legacy)
            if (d.effect !== "allow") break
          }
        } else if (e.action === "shell") {
          const cwd = typeof e.metadata?.cwd === "string" ? e.metadata.cwd : locationDir
          const asked: string[] = []
          for (const cmd of e.resources) {
            const c = judgeShell(cmd, cwd, legacy, session)
            // A deny of any command decides; an ask is kept while the rest are still judged.
            if (c.effect === "deny") {
              d = c
              break
            }
            if (c.effect === "ask") {
              if (d.effect === "allow") d = c
              asked.push(cmd)
            }
            if (legacy) claimPushes(cmd, cwd)
          }
          if (d.effect === "ask") {
            if (pgAsked.size > 256) pgAsked.clear()
            for (const cmd of asked) pgAsked.set(cmd, Date.now())
          }
        } else {
          const tool = githubMcpTool(String(e.action))
          // MCP tool input reaches permission requests as metadata.input (OpenCode 2.0.30).
          if (tool) d = runPermissionGuard({ kind: "mcp", tool, input: e.metadata?.input, cwd: locationDir }, session)
        }
        if (d.effect !== "allow") {
          // The guard's own effect, deny or (R2 only) ask; never allow, which would widen a
          // configured ask (O1e). A deny is final under --auto (O1b); the R2 ask is approved by
          // it (O1c), which ADR 004 D8 accepts for R2 alone.
          e.effect = d.effect
          e.message = d.reason
        }
      } catch (err) {
        e.effect = "deny"
        e.message = failClosed(err).reason
      }
    })

    const shell = await ctx.shell.hook("create.before", (e) => {
      let d: Decision
      try {
        d = judgeShell(e.command, e.cwd, legacy, lastSessionID)
        if (d.effect === "ask") {
          // An R2 ask the permission hook put to OpenCode's prompt: this is the shell it
          // asked about, once. Any other ask has had no prompt, so it is a deny here.
          const at = pgAsked.get(e.command)
          if (at !== undefined && Date.now() - at < PG_ASKED_MS) {
            pgAsked.delete(e.command)
            d = ALLOW
          } else {
            d = deny(
              `${d.reason} This shell was created outside OpenCode's permission flow, where that ask is put, so it ` +
                "is denied (ADR 004 D8).",
            )
          }
        }
      } catch (err) {
        d = failClosed(err)
      }
      if (d.effect !== "allow") {
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
