// Pure readers and formatters of the orchestration state orchestrate-dev and
// worker-dev keep in `.dev-files/objectives/<id>/` (objective.json, tasks/*.json,
// handoffs/*.json). Every function takes text or data the caller already read
// with `$.fs` and gives back data or text; `$` never comes here.
import type { ModsObjective, ModsObjectiveTask } from './types'

export const MAX_TASKS = 50

/** A task that still needs a worker: not completed and not cancelled. */
const CLOSED_TASK = new Set(['completed', 'cancelled'])

export function asNumber(v: unknown, fallback: number): number {
  const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v) : NaN
  return Number.isFinite(n) ? n : fallback
}

export const str = (v: unknown): string | undefined => (typeof v === 'string' ? v : undefined)

/** JSON text to an object, or null for anything that is not one. */
export function parseObject(text: string | null): Record<string, unknown> | null {
  if (text === null) return null
  try {
    const v: unknown = JSON.parse(text)
    return v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : null
  } catch {
    return null
  }
}

/**
 * Which objective under the state directory is the active one, as hooks/lib/
 * objective-common.sh and skills/dev-workflow/_shared/scripts/objective-state.sh
 * decide it: `preferredId` (SUPERPOWERS_OBJECTIVE_ID, or the id a person or the
 * model asked for) wins; else the first `active`; else the first not
 * completed/abandoned. `objectives` is id -> parsed objective.json.
 */
export function pickObjective(ids: string[], objectives: Map<string, Record<string, unknown> | null>, preferredId: string | undefined): { id: string; obj: Record<string, unknown> } | null {
  const ordered = preferredId && ids.includes(preferredId) ? [preferredId, ...ids.filter(i => i !== preferredId)] : ids
  let fallback: { id: string; obj: Record<string, unknown> } | null = null
  for (const id of ordered) {
    const obj = objectives.get(id) ?? null
    if (!obj) continue
    const status = str(obj.status) ?? ''
    if (id === preferredId || status === 'active') return { id, obj }
    if (!fallback && status !== 'completed' && status !== 'abandoned') fallback = { id, obj }
  }
  return fallback
}

export function taskIdsOf(obj: Record<string, unknown>): string[] {
  const tasks = Array.isArray(obj.tasks) ? obj.tasks.filter((t): t is string => typeof t === 'string') : []
  return tasks.slice(0, MAX_TASKS)
}

export function taskRow(tid: string, task: Record<string, unknown> | null, handoff: Record<string, unknown> | null): ModsObjectiveTask {
  return {
    id: tid,
    title: str(task?.title) ?? tid,
    status: str(task?.status) ?? 'pending',
    role: str(task?.role),
    branch: str(task?.branch),
    handoff: str(handoff?.status),
  }
}

/** The objective as `objective.json` plus its task and handoff rows describe it. */
export function objectiveOf(id: string, obj: Record<string, unknown>, tasks: ModsObjectiveTask[], readAt: number): ModsObjective {
  return { id, title: str(obj.title) ?? id, status: str(obj.status) ?? 'unknown', tasks, readAt }
}

export function openTaskCount(o: ModsObjective): number {
  return o.tasks.filter(t => !CLOSED_TASK.has(t.status)).length
}

/** The `/objective` answer and the compaction snapshot's objective block. */
export function objectiveText(o: ModsObjective | null): string {
  if (!o) return 'No objective is active (nothing under .dev-files/objectives). /plan-dev writes one.'
  const lines = [`Objective ${o.id} — ${o.title} [${o.status}]`]
  for (const t of o.tasks) {
    const tail = [t.role, t.branch, t.handoff ? `handoff: ${t.handoff}` : ''].filter(Boolean).join('  ')
    lines.push(`  ${t.id}  ${t.status.padEnd(9)}  ${t.title}${tail ? `  (${tail})` : ''}`)
  }
  if (o.tasks.length === 0) lines.push('  (no tasks yet)')
  return lines.join('\n')
}

/** The `objective_status` tool's answer: the objective summary as JSON text. */
export function objectiveSummaryJson(o: ModsObjective | null, requestedId: string | undefined): string {
  if (!o) {
    return JSON.stringify({
      objective: null,
      message: requestedId ? `No objective ${requestedId} under .dev-files/objectives.` : 'No objective is active (nothing under .dev-files/objectives). /plan-dev writes one.',
    })
  }
  return JSON.stringify({
    objective: {
      id: o.id,
      title: o.title,
      status: o.status,
      open_tasks: openTaskCount(o),
      tasks: o.tasks.map(t => ({ id: t.id, title: t.title, status: t.status, role: t.role ?? null, branch: t.branch ?? null, handoff: t.handoff ?? null })),
    },
  }, null, 2)
}

/**
 * The line appended to a dev-workflow skill's expanded prompt: the live objective,
 * the worktree the session runs in and how many tasks are still open.
 */
export function skillContext(o: ModsObjective, worktree: string): string {
  const open = openTaskCount(o)
  return `[tamirs-superpowers] Active objective ${o.id} — ${o.title} [${o.status}] · worktree ${worktree || '(unknown)'} · ${open} open task${open === 1 ? '' : 's'} of ${o.tasks.length}. objective_status answers the full table without a shell.`
}

/** The branch a .git/HEAD names, or the short commit when detached. */
export function branchOf(head: string | null): string {
  if (!head) return ''
  const ref = head.match(/^ref:\s*refs\/heads\/(\S+)/m)?.[1]
  if (ref) return ref
  const sha = head.trim()
  return /^[0-9a-f]{40}$/.test(sha) ? sha.slice(0, 12) : ''
}

/**
 * The gitdir a linked worktree's `.git` FILE points at, or null when the text
 * is not that (a main checkout has a `.git` directory, which reads as nothing).
 */
export function linkedGitDir(dotGit: string | null): string | null {
  const m = dotGit?.match(/^gitdir:\s*(.+)$/m)
  return m?.[1]?.trim() || null
}

export const STATUS_COLOR: Record<string, string> = {
  running: 'yellow', completed: 'green', failed: 'red', blocked: 'red', cancelled: 'gray', ready: 'cyan', pending: 'gray',
}

/** An agent of the session as `$.agent.list()` reports it, the fields the pane reads. */
export type AgentRow = { id: string; description: string; status: string }

/** Agent statuses that mean a worker is still at it. */
const LIVE_AGENT = new Set(['pending', 'running', 'waiting', 'idle'])

/**
 * Which agent is working each task: an agent whose description names the task id
 * (worker-dev spawns name it), else the running agents in order against the
 * tasks that are running, in order. Returns task id -> agent.
 */
export function agentsByTask(tasks: ModsObjectiveTask[], agents: AgentRow[]): Map<string, AgentRow> {
  const out = new Map<string, AgentRow>()
  const taken = new Set<string>()
  for (const t of tasks) {
    const named = agents.find(a => !taken.has(a.id) && a.description.includes(t.id))
    if (named) {
      out.set(t.id, named)
      taken.add(named.id)
    }
  }
  const spare = agents.filter(a => !taken.has(a.id) && LIVE_AGENT.has(a.status))
  let i = 0
  for (const t of tasks) {
    if (out.has(t.id) || t.status !== 'running') continue
    const a = spare[i]
    if (!a) break
    out.set(t.id, a)
    i += 1
  }
  return out
}
