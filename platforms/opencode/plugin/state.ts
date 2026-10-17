// state.ts — the filesystem half shared by guard.ts (server) and tui.tsx (TUI).
//
// Reads git worktree layout and the orchestration state that orchestrate-dev /
// worker-dev keep under .dev-files/objectives/<id>/ — the same files
// mod/register.tsx draws on Claude Code and hooks/lib/objective-common.sh reads
// on every edit. Node fs only: no git process is spawned to find the main
// checkout, because a linked worktree's `.git` FILE already names it
// (`gitdir: <main>/.git/worktrees/<name>`, whose `commondir` points back).

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs"
import path from "node:path"
import { activeObjectiveId, parseObject, type ObjectiveEntry } from "./rules.ts"

export interface GitRoots {
  /** Top of the checkout `dir` sits in (a linked worktree or the main one). */
  readonly worktreeRoot: string
  /** The main checkout — where .dev-files/objectives and the claim-relevant config live. */
  readonly mainRoot: string
  /** This checkout's git dir (`.git` or `.git/worktrees/<name>`). */
  readonly gitDir: string
  /** The shared git dir (`<main>/.git`). */
  readonly commonDir: string
}

function readText(p: string): string | null {
  try {
    return readFileSync(p, "utf8")
  } catch {
    return null
  }
}

/** Walk up from `dir` to the nearest directory that exists (a Write may target a new directory). */
export function nearestExistingDir(dir: string): string {
  let d = path.resolve(dir)
  while (d && d !== path.dirname(d) && !existsSync(d)) d = path.dirname(d)
  return d
}

/** Resolve the checkout `dir` belongs to, or null when it is not inside a git repo. */
export function gitRoots(dir: string): GitRoots | null {
  let d = nearestExistingDir(dir)
  for (;;) {
    const dotGit = path.join(d, ".git")
    try {
      const st = statSync(dotGit)
      if (st.isDirectory()) {
        return { worktreeRoot: d, mainRoot: d, gitDir: dotGit, commonDir: dotGit }
      }
      if (st.isFile()) {
        const m = readText(dotGit)?.match(/^gitdir:\s*(.+)$/m)
        if (!m) return null
        const gitDir = path.resolve(d, m[1].trim())
        const commonRel = readText(path.join(gitDir, "commondir"))?.trim()
        const commonDir = commonRel ? path.resolve(gitDir, commonRel) : gitDir
        return { worktreeRoot: d, mainRoot: path.dirname(commonDir), gitDir, commonDir }
      }
    } catch {
      /* no .git here */
    }
    const parent = path.dirname(d)
    if (parent === d) return null
    d = parent
  }
}

/** The branch this checkout's HEAD names, or "" when detached/unreadable. */
export function currentBranch(roots: GitRoots): string {
  const head = readText(path.join(roots.gitDir, "HEAD"))
  return head?.match(/^ref:\s*refs\/heads\/(\S+)/m)?.[1] ?? ""
}

/** `owner/repo` of the origin remote from the shared git config, or null. */
export function originSlug(roots: GitRoots): string | null {
  const cfg = readText(path.join(roots.commonDir, "config"))
  if (!cfg) return null
  const m = cfg.match(/\[remote "origin"\][^[]*?\n\s*url\s*=\s*(\S+)/)
  if (!m) return null
  return m[1].replace(/^git@[^:]+:/, "").replace(/^[a-z+]+:\/\/[^/]+\//, "").replace(/\.git$/, "") || null
}

export function originIsGithub(roots: GitRoots): boolean {
  const cfg = readText(path.join(roots.commonDir, "config"))
  const m = cfg?.match(/\[remote "origin"\][^[]*?\n\s*url\s*=\s*(\S+)/)
  return !!m && m[1].includes("github.com")
}

/**
 * What `git push` with no refspec would push to: the branch's configured
 * upstream merge ref, else the branch itself. Empty when neither is known —
 * the caller then fails loud instead of guessing a default branch.
 */
export function pushFallbackBranch(roots: GitRoots): string | null {
  const branch = currentBranch(roots)
  if (!branch) return null
  const cfg = readText(path.join(roots.commonDir, "config")) ?? ""
  const esc = branch.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  const m = cfg.match(new RegExp(`\\[branch "${esc}"\\][^[]*?\\n\\s*merge\\s*=\\s*refs/heads/(\\S+)`))
  return m?.[1] ?? branch
}

// --------------------------------------------------------------- objectives ---

/**
 * Where objective state lives for the repo `mainRoot` is the main checkout of.
 * OBJECTIVES_ROOT (the override handoff.sh/objective-state.sh honour) wins; else
 * <main>/<SUPERPOWERS_OBJECTIVE_STATE_DIRNAME or .dev-files/objectives>.
 */
export function objectivesDir(mainRoot: string, env: NodeJS.ProcessEnv = process.env): string {
  const override = env.OBJECTIVES_ROOT
  if (override) return override.replace(/\/$/, "")
  return path.join(mainRoot, env.SUPERPOWERS_OBJECTIVE_STATE_DIRNAME || ".dev-files/objectives")
}

export function listObjectiveEntries(dir: string): ObjectiveEntry[] {
  let ids: string[]
  try {
    ids = readdirSync(dir, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .sort()
  } catch {
    return []
  }
  return ids.map((id) => ({ id, json: readText(path.join(dir, id, "objective.json")) }))
}

/** The active objective id for the repo at `mainRoot`, as the shell hooks decide it. */
export function activeObjectiveFor(mainRoot: string, env: NodeJS.ProcessEnv = process.env): string | null {
  return activeObjectiveId(listObjectiveEntries(objectivesDir(mainRoot, env)), env.SUPERPOWERS_OBJECTIVE_ID)
}

export interface ObjectiveTask {
  readonly id: string
  readonly title: string
  readonly status: string
  readonly role?: string
  readonly branch?: string
  readonly handoff?: string
}

export interface ObjectiveView {
  readonly id: string
  readonly title: string
  readonly status: string
  readonly tasks: ObjectiveTask[]
  readonly readAt: number
}

const MAX_TASKS = 50

function str(v: unknown): string | undefined {
  return typeof v === "string" && v ? v : undefined
}

/**
 * The objective pane's model, read the way mod/register.tsx reads it: the
 * active objective (or, for display only, the first not completed/abandoned
 * one), its ordered task ids, and each task's status/handoff.
 */
export function readObjectiveView(mainRoot: string, env: NodeJS.ProcessEnv = process.env): ObjectiveView | null {
  const dir = objectivesDir(mainRoot, env)
  const entries = listObjectiveEntries(dir)
  if (!entries.length) return null
  const preferred = env.SUPERPOWERS_OBJECTIVE_ID
  let pick: { id: string; obj: Record<string, unknown> } | null = null
  let fallback: { id: string; obj: Record<string, unknown> } | null = null
  const ordered = preferred && entries.some((e) => e.id === preferred) ? [...entries.filter((e) => e.id === preferred), ...entries.filter((e) => e.id !== preferred)] : entries
  for (const e of ordered) {
    const obj = parseObject(e.json)
    if (!obj) continue
    const status = str(obj.status) ?? ""
    if (e.id === preferred || status === "active") {
      pick = { id: e.id, obj }
      break
    }
    if (!fallback && status !== "completed" && status !== "abandoned") fallback = { id: e.id, obj }
  }
  pick = pick ?? fallback
  if (!pick) return null
  const ids = Array.isArray(pick.obj.tasks) ? pick.obj.tasks.filter((t): t is string => typeof t === "string").slice(0, MAX_TASKS) : []
  const tasks = ids.map((tid) => {
    const task = parseObject(readText(path.join(dir, pick!.id, "tasks", `${tid}.json`)))
    const handoff = parseObject(readText(path.join(dir, pick!.id, "handoffs", `${tid}.json`)))
    return {
      id: tid,
      title: str(task?.title) ?? tid,
      status: str(task?.status) ?? "pending",
      role: str(task?.role),
      branch: str(task?.branch),
      handoff: str(handoff?.status),
    }
  })
  return { id: pick.id, title: str(pick.obj.title) ?? pick.id, status: str(pick.obj.status) ?? "unknown", tasks, readAt: Date.now() }
}
