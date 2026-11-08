// guard.ts — OpenCode 2 server plugin: the core safety guards.
//
// This is the OpenCode translation of hooks that stay canonical in hooks/ (they run
// as shell PreToolUse hooks on Claude Code, Codex and Cursor; OpenCode executes no
// shell hook, its only lifecycle mechanism is this plugin API):
//
//   hooks/guard-sensitive-files.sh   -> ctx.permission.hook("evaluate") on `edit`, plus
//                                       `shell` write targets, plus
//                                       ctx.shell.hook("create.before"); its parse and
//                                       protected-path pass RUN AS IS:
//                                       python3 hooks/lib/write-targets.py --protected,
//                                       with rules.ts's port only where python3 is absent
//   hooks/enforce-worktree-edits.sh  -> the same hook on `edit`
//   hooks/protect-other-branches.sh  -> the same hook on `shell` (git push), plus
//                                       ctx.shell.hook("create.before")
//
// DENY ONLY
//   The plugin sets `effect = "deny"` and nothing else. A plugin `deny` is final under
//   `opencode --auto`; an `ask` is approved by it, and no plugin hook asks (6.0.0,
//   ADR 006). It never sets `allow`, which would widen a configured ask, and never calls
//   ctx.session.update, whose session rule overrides a deny in the user's opencode.json.
//   A hook that throws, or a missing or failing write-targets.py, is a deny (fail closed).
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
//   - guard-sensitive-files.sh's UNSURE advisory: OpenCode's permission hook has no
//     channel for a note that is not a decision. An unresolved write that NAMES a
//     protected path is still a deny, decided by write-targets.py.
//   - Without python3, write-targets.py cannot run, and rules.ts's port decides:
//     redirects (fd and exec ones too), tee, sed -i, cp/mv/install/ln/link/pax,
//     tree targets and rm, with case folding — but no git replays, patch headers,
//     downloaders or awk/sed programs. The binding half is still the git/CI check on
//     the modified path, exactly as the shell hook's header says.
//   - This file spawns `git` for one question the filesystem cannot answer —
//     `check-ignore` on a build-output path — and `python3 hooks/lib/write-targets.py`
//     (which itself runs read-only local git queries for replays). Nothing else.
//
// OVERRIDES (same names as the shell hooks)
//   PM_ALLOW_PROTECTED=1    skip the generated-file rules (lockfiles, .yarn/releases,
//                           shadcn ui, build output) for an intended edit; never a
//                           protected path
//   TAMIRS_OPENCODE_GUARD=0 disable the worktree, generated-file and branch-claim
//                           guards; the protected paths stay on
//
// Observed on @opencode/cli 2.2.5: `opencode plugin list` and `opencode debug
// agents` run without a provider key, so the plugin's LOADING can be checked
// offline (service mode; the first `plugin list` on a fresh service prints nothing,
// the second lists it — see docs/engineering/roadmap/v5-research/opencode-2.2.5.md).
// That an evaluate-hook deny stops a shell call under --auto was measured with a
// probe plugin; this plugin's own run in a session with a provider is still
// unmeasured, so core/capabilities/platforms.json keeps hooks at adapter.

import { Plugin } from "@opencode/plugin"
import { execFileSync } from "node:child_process"
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, renameSync, statSync, writeFileSync } from "node:fs"
import { hostname, userInfo } from "node:os"
import path from "node:path"
import { fileURLToPath } from "node:url"
import {
  ALLOW,
  claimKey,
  deny,
  gitPushes,
  inspectClaim,
  judgeEdit,
  judgePush,
  parseWriteTargets,
  protectedFromRecords,
  protectedReason,
  sensitiveReason,
  sessionWorktreeRoot,
  shellWriteTargets,
  writeTargetsFromRecords,
  type ClaimVerdict,
  type Decision,
  type ProtectedFacts,
  type SensitiveFacts,
  type TargetKind,
  type WorktreeFacts,
  type WriteTargetRecord,
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
    globalWorktreeRoot: sessionWorktreeRoot(env, h),
  }
}

// ------------------------------------------------------- protected paths ---

/** This plugin's repository root: guard.ts sits at <root>/platforms/opencode/plugin/. */
const PLUGIN_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..")
const WRITE_TARGETS = path.join(PLUGIN_ROOT, "hooks", "lib", "write-targets.py")
// guard-sensitive-files.sh runs under a 5 s hook timeout; the parse budgets its git queries at 2.5 s.
const WRITE_TARGETS_TIMEOUT_MS = 5_000

/**
 * `python3 hooks/lib/write-targets.py --protected` on one tool call, exactly as
 * hooks/guard-sensitive-files.sh runs it: the canonical parse (heredocs, fd and exec
 * redirects, copies and extractions as trees, git replays, patch headers, case folding,
 * an unresolved write that names a protected path). null only when python3 is not
 * installed, so the caller falls back to the rules.ts port; any other failure throws,
 * and the hook's failClosed denies.
 */
function writeTargetRecords(toolName: string, toolInput: Record<string, unknown>, cwd: string): WriteTargetRecord[] | null {
  // A missing parser falls back exactly as a missing python3 does: the rules.ts port judges.
  if (!existsSync(WRITE_TARGETS)) return null
  let out: string
  try {
    out = execFileSync("python3", [WRITE_TARGETS, "--protected"], {
      input: JSON.stringify({ hook_event_name: "PreToolUse", tool_name: toolName, tool_input: toolInput, cwd }),
      encoding: "utf8",
      timeout: WRITE_TARGETS_TIMEOUT_MS,
      maxBuffer: 4 << 20,
      cwd: cwd && path.isAbsolute(cwd) && existsSync(cwd) ? cwd : PLUGIN_ROOT,
      stdio: ["pipe", "pipe", "ignore"],
    })
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return null
    throw new Error(`write-targets.py failed (${String((err as Error)?.message ?? err).split("\n")[0]})`)
  }
  return parseWriteTargets(out)
}

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
  // The passwd home decides; the session HOME is added, never trusted instead.
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

/** The protected-path verdict for one absolute target: a deny, or no objection. */
function judgeProtected(abs: string, kind: TargetKind, via: string, cwd: string): Decision {
  const v = protectedReason(abs, pathForms(abs), protectedFacts(cwd), kind, via)
  if (!v) return ALLOW
  return deny(v.reason)
}

/** Judge one file write with the rules.ts port: protected paths (always), then judgeAfterProtected. */
function judgeWrite(file: string, kind: TargetKind, via: string, cwd: string, legacy: boolean): Decision {
  const p = judgeProtected(file, kind, via, cwd)
  if (p.effect !== "allow") return p
  return judgeAfterProtected(file, kind, via, legacy)
}

/**
 * Everything after the protected pass, in guard-sensitive-files.sh's order, and only with
 * the legacy guards on: the generated-file rules (which PM_ALLOW_PROTECTED=1 skips), then
 * the worktree invariant.
 */
function judgeAfterProtected(file: string, kind: TargetKind, via: string, legacy: boolean): Decision {
  if (!legacy || kind === "move" || kind === "link") return ALLOW
  const roots = gitRoots(path.dirname(file))
  if (process.env.PM_ALLOW_PROTECTED !== "1") {
    const reason = sensitiveReason(file, sensitiveFacts(roots, file), kind, via)
    if (reason) return deny(reason)
  }
  if (kind === "delete") return ALLOW
  return judgeEdit(file, worktreeFacts(roots))
}

/**
 * Judge one tool call's writes the way guard-sensitive-files.sh does: write-targets.py's
 * PROTECTED denies decide first,
 * then each TARGET / DELETE / TREE meets judgeAfterProtected. null when python3 or write-targets.py is
 * not installed: the caller then judges with the rules.ts port.
 */
function judgeWritesCanonical(toolName: string, toolInput: Record<string, unknown>, cwd: string, legacy: boolean): Decision | null {
  const records = writeTargetRecords(toolName, toolInput, cwd)
  if (!records) return null
  const p = protectedFromRecords(records)
  if (p) return p
  for (const t of writeTargetsFromRecords(records)) {
    const d = judgeAfterProtected(t.path, t.kind, t.via, legacy)
    if (d.effect !== "allow") return d
  }
  return ALLOW
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

/** Judge one shell command string: git push (legacy), then its write targets. */
function judgeShell(command: string, cwd: string, legacy: boolean): Decision {
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
  const canonical = judgeWritesCanonical("Bash", { command }, cwd, legacy)
  if (canonical && canonical.effect !== "allow") return canonical
  if (!canonical) {
    // No python3: the rules.ts port, which reads fewer writers (see the header).
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
  }
  return ALLOW
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

/** A hook that throws must not let the call through: every error is a deny. */
function failClosed(err: unknown): Decision {
  return deny(`tamirs-superpowers guard: an internal error stopped the check (${String((err as Error)?.message ?? err)}), so the call is denied (fail closed).`)
}

export default Plugin.define({
  id: ID,
  async setup(ctx) {
    // TAMIRS_OPENCODE_GUARD=0 turns off the legacy guards, never the protected paths.
    const legacy = process.env.TAMIRS_OPENCODE_GUARD !== "0"
    const locationDir = ctx.location.directory

    const permission = await ctx.permission.hook("evaluate", (e) => {
      if (e.effect === "deny") return
      try {
        if (e.sessionID) lastSessionID = String(e.sessionID)
        let d: Decision = ALLOW
        if (e.action === "edit") {
          for (const r of e.resources) {
            const abs = path.isAbsolute(r) ? r : path.resolve(locationDir, r)
            d = judgeWritesCanonical("Edit", { file_path: abs }, locationDir, legacy) ?? judgeWrite(abs, "write", "", locationDir, legacy)
            if (d.effect !== "allow") break
          }
        } else if (e.action === "shell") {
          const cwd = typeof e.metadata?.cwd === "string" ? e.metadata.cwd : locationDir
          for (const cmd of e.resources) {
            d = judgeShell(cmd, cwd, legacy)
            if (d.effect !== "allow") break
            if (legacy) claimPushes(cmd, cwd)
          }
        }
        if (d.effect !== "allow") {
          // Deny only: never allow, which would widen a configured ask.
          e.effect = "deny"
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
        d = judgeShell(e.command, e.cwd, legacy)
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
